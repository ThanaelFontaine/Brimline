import Darwin
import Foundation
import Security

/// What a launch of `agy` gave back.
public struct AntigravityRun: Sendable, Equatable {
    public var exitCode: Int32
    public var stdout: Data
    public var stderr: Data

    public init(exitCode: Int32, stdout: Data, stderr: Data) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public enum AntigravityRunFailure: Error, Equatable, Sendable {
    /// The program could not be started.
    case couldNotLaunch
    /// It did not finish in time and was stopped.
    case timedOut
    /// It wrote more than the limit and was stopped.
    case outputTooLong
    /// The program that was started, held suspended, did not satisfy the signature requirement (the status
    /// of Security.framework is carried). It was killed before it ran a single instruction.
    case codeRejected(OSStatus)
}

/// Launches `agy`. A protocol, so that no test and no CI run ever starts a real `agy`.
public protocol AntigravityRunning: Sendable {
    func run(binary: URL, arguments: [String], home: URL) async throws(AntigravityRunFailure) -> AntigravityRun
}

/// The real launcher: `posix_spawn`, with everything fixed.
///
/// - **suspended, then checked:** the program is started with `POSIX_SPAWN_START_SUSPENDED`, so it runs no
///   instruction yet. Brimline takes the audit token of that process, asks Security.framework for its code
///   (`SecCodeCopyGuestWithAttributes`, by the token, never by the pid alone) and checks it against
///   `requirement` (`SecCodeCheckValidityWithErrors`). What is checked is the code the kernel holds for that
///   process (its `cdhash`), not the file at the path: a file replaced between the static check and the launch
///   is another program, and it is rejected. Only then `SIGCONT`; otherwise `SIGKILL` and nothing ran;
/// - the working folder is new and empty, inside Brimline's own temporary folder (owner only), and
///   removed afterwards, so the program has nothing of the user's to look at;
/// - the environment is `HOME`, `PATH=/usr/bin:/bin` and `LANG=en_US.UTF-8` and nothing else (no
///   token, no proxy, no variable of the user's shell); no signal is blocked, every handler is the default one;
/// - nothing is typed to it (standard input is `/dev/null`), no other descriptor of Brimline's reaches it
///   (`POSIX_SPAWN_CLOEXEC_DEFAULT`), and its output is read on other threads, at most `maxOutputBytes` per
///   stream: past that, or past `timeout` seconds, it is stopped;
/// - it is the leader of a new process group, and the whole group is stopped when the run ends (`SIGTERM`
///   then, after 2 seconds, `SIGKILL`; at the end of every run a last `SIGKILL`), and the program is always
///   waited for: no process stays behind, no zombie. A program that leaves its group on purpose is out of
///   reach (said in SECURITY.md); the pipes are then given up after 2 seconds.
public struct ProcessAntigravityRunner: AntigravityRunning {
    public static let defaultTimeout: TimeInterval = 20
    public static let defaultMaxOutputBytes = 64 * 1024

    public var timeout: TimeInterval
    public var maxOutputBytes: Int
    /// The signature requirement the suspended process must satisfy: Google's (tests give another).
    public var requirement: String
    /// Test seam: called with the pid right after the program is spawned and before its code is checked, that is
    /// while it must still be suspended. `nil` in production.
    var afterSpawn: (@Sendable (pid_t) -> Void)?

    public init(timeout: TimeInterval = Self.defaultTimeout, maxOutputBytes: Int = Self.defaultMaxOutputBytes,
                requirement: String = SecurityFrameworkCodeChecker.google) {
        self.timeout = timeout
        self.maxOutputBytes = maxOutputBytes
        self.requirement = requirement
    }

    public func run(binary: URL, arguments: [String], home: URL) async throws(AntigravityRunFailure) -> AntigravityRun {
        let timeout = self.timeout, limit = maxOutputBytes, requirement = self.requirement
        let afterSpawn = self.afterSpawn
        let result: Result<AntigravityRun, AntigravityRunFailure> = await withCheckedContinuation { continuation in
            Self.onOwnThread {
                continuation.resume(returning: Self.runBlocking(binary: binary, arguments: arguments, home: home,
                                                                timeout: timeout, limit: limit,
                                                                requirement: requirement, afterSpawn: afterSpawn))
            }
        }
        return try result.get()
    }

    /// Everything here blocks (waiting for the program, reading a pipe): each piece runs on a thread of its own,
    /// never on the shared pool of Dispatch, which a few runs at once would starve (and the run would then time out
    /// without the program being at fault).
    private static func onOwnThread(_ work: @escaping @Sendable () -> Void) {
        let thread = Thread(block: work)
        thread.qualityOfService = .utility
        thread.start()
    }

    /// The environment the program gets: exactly this.
    static func environment(home: URL) -> [String: String] {
        ["HOME": home.path, "PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"]
    }

    private static func runBlocking(binary: URL, arguments: [String], home: URL, timeout: TimeInterval,
                                    limit: Int, requirement: String,
                                    afterSpawn: (@Sendable (pid_t) -> Void)?) -> Result<AntigravityRun, AntigravityRunFailure> {
        let workFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Brimline", isDirectory: true)
            .appendingPathComponent("agy-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: workFolder, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        } catch {
            return .failure(.couldNotLaunch)
        }
        defer { try? FileManager.default.removeItem(at: workFolder) }

        var outPipe: [Int32] = [-1, -1], errPipe: [Int32] = [-1, -1]
        guard pipe(&outPipe) == 0 else { return .failure(.couldNotLaunch) }
        guard pipe(&errPipe) == 0 else {
            close(outPipe[0]); close(outPipe[1])
            return .failure(.couldNotLaunch)
        }
        // Brimline's ends never pass to a program launched by anything else of Brimline's.
        for descriptor in outPipe + errPipe { _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC) }
        var readEnds: [Int32] = [outPipe[0], errPipe[0]]
        defer { for descriptor in readEnds where descriptor >= 0 { close(descriptor) } }

        let spawned = spawnSuspended(binary: binary, arguments: arguments, home: home, workFolder: workFolder,
                                     standardOutput: outPipe[1], standardError: errPipe[1])
        // The child has its own copies: the write ends close here, so that the readers see the end.
        close(outPipe[1]); close(errPipe[1])
        guard let pid = spawned else { return .failure(.couldNotLaunch) }

        // The program exists, suspended: nothing of it has run. Its code is checked before it is let go.
        afterSpawn?(pid)
        if let rejection = verify(pid: pid, requirement: requirement) {
            kill(-pid, SIGKILL)
            kill(pid, SIGKILL)
            var status: Int32 = 0
            while waitpid(pid, &status, 0) < 0 && errno == EINTR {}
            return .failure(rejection)
        }
        kill(pid, SIGCONT)

        let stop = Flag()
        let finished = DispatchSemaphore(value: 0)
        // The program has ended (reaped later, so that its group number stays its own until the group is stopped).
        let ended = DispatchSemaphore(value: 0)
        let exited = Flag()
        onOwnThread {
            var info = siginfo_t()
            while waitid(P_PID, id_t(pid), &info, WEXITED | WNOWAIT) < 0 && errno == EINTR {}
            exited.set()
            ended.signal()
            finished.signal()
        }

        let overflow = Flag()
        let readers = DispatchGroup()
        let outBuffer = Buffer(), errBuffer = Buffer()
        for (descriptor, buffer) in [(outPipe[0], outBuffer), (errPipe[0], errBuffer)] {
            readers.enter()
            onOwnThread {
                defer { readers.leave() }
                drain(descriptor, into: buffer, limit: limit, stop: stop, onOverflow: {
                    overflow.set()
                    finished.signal()
                })
            }
        }

        let timedOut = finished.wait(timeout: .now() + timeout) == .timedOut
        let alreadyEnded = exited.isSet
        if !alreadyEnded {
            kill(-pid, SIGTERM)
            if ended.wait(timeout: .now() + 2) == .timedOut {
                kill(-pid, SIGKILL)
                ended.wait()
            }
        } else {
            ended.wait()
        }
        // Nothing of the run outlives it: the program is a zombie still, so the group is still its own.
        kill(-pid, SIGKILL)
        var status: Int32 = 0
        while waitpid(pid, &status, 0) < 0 && errno == EINTR {}

        // The group is gone: what is left in the pipes arrives at once, unless a child that left the group holds them.
        if readers.wait(timeout: .now() + 2) == .timedOut { stop.set() }
        readers.wait()
        readEnds = []
        close(outPipe[0]); close(errPipe[0])

        if overflow.isSet { return .failure(.outputTooLong) }
        if timedOut && !alreadyEnded { return .failure(.timedOut) }
        // Exit code as a shell shows it: the code, or 128 plus the signal that ended the program.
        let signal = status & 0x7f
        let code = signal == 0 ? (status >> 8) & 0xff : 128 + signal
        return .success(AntigravityRun(exitCode: code, stdout: outBuffer.data, stderr: errBuffer.data))
    }

    /// Starts the program suspended, in a new process group, with only the fixed descriptors, environment and folder.
    private static func spawnSuspended(binary: URL, arguments: [String], home: URL, workFolder: URL,
                                       standardOutput: Int32, standardError: Int32) -> pid_t? {
        var attributes: posix_spawnattr_t?
        guard posix_spawnattr_init(&attributes) == 0 else { return nil }
        defer { posix_spawnattr_destroy(&attributes) }
        var actions: posix_spawn_file_actions_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else { return nil }
        defer { posix_spawn_file_actions_destroy(&actions) }

        let flags = POSIX_SPAWN_START_SUSPENDED | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETPGROUP
            | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF
        var noSignalBlocked = sigset_t(), allDefault = sigset_t()
        sigemptyset(&noSignalBlocked)
        sigfillset(&allDefault)
        guard posix_spawnattr_setflags(&attributes, Int16(flags)) == 0,
              posix_spawnattr_setpgroup(&attributes, 0) == 0,
              posix_spawnattr_setsigmask(&attributes, &noSignalBlocked) == 0,
              posix_spawnattr_setsigdefault(&attributes, &allDefault) == 0 else { return nil }

        guard posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0) == 0,
              posix_spawn_file_actions_adddup2(&actions, standardOutput, 1) == 0,
              posix_spawn_file_actions_adddup2(&actions, standardError, 2) == 0,
              posix_spawn_file_actions_addchdir_np(&actions, workFolder.path) == 0 else { return nil }

        let argv = cStrings([binary.path] + arguments)
        let envp = cStrings(environment(home: home).map { "\($0.key)=\($0.value)" }.sorted())
        defer { for pointer in argv + envp { free(pointer) } }

        var pid: pid_t = 0
        let status = (argv + [nil]).withUnsafeBufferPointer { argvPointer in
            (envp + [nil]).withUnsafeBufferPointer { envpPointer in
                posix_spawn(&pid, binary.path, &actions, &attributes,
                            UnsafeMutablePointer(mutating: argvPointer.baseAddress),
                            UnsafeMutablePointer(mutating: envpPointer.baseAddress))
            }
        }
        return status == 0 ? pid : nil
    }

    private static func cStrings(_ strings: [String]) -> [UnsafeMutablePointer<CChar>?] {
        strings.map { strdup($0) }
    }

    /// Checks the code of the suspended process. Nil when it satisfies `requirement`; else why not.
    private static func verify(pid: pid_t, requirement text: String) -> AntigravityRunFailure? {
        // The audit token names this process and no other, even if its number were reused.
        var port: mach_port_t = 0
        guard task_name_for_pid(mach_task_self_, pid, &port) == KERN_SUCCESS else { return .couldNotLaunch }
        defer { mach_port_deallocate(mach_task_self_, port) }
        var token = audit_token_t()
        var count = mach_msg_type_number_t(MemoryLayout<audit_token_t>.size / MemoryLayout<natural_t>.size)
        let info = withUnsafeMutablePointer(to: &token) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(port, task_flavor_t(TASK_AUDIT_TOKEN), $0, &count)
            }
        }
        // `val.5` is the pid in an audit token (`audit_token_to_pid`).
        guard info == KERN_SUCCESS, token.val.5 == UInt32(pid) else { return .couldNotLaunch }

        let attributes = [kSecGuestAttributeAudit: withUnsafeBytes(of: &token) { Data($0) }] as CFDictionary
        var code: SecCode?
        let guest = SecCodeCopyGuestWithAttributes(nil, attributes, [], &code)
        guard guest == errSecSuccess, let code else { return .codeRejected(guest) }
        var requirement: SecRequirement?
        let created = SecRequirementCreateWithString(text as CFString, [], &requirement)
        guard created == errSecSuccess, let requirement else { return .codeRejected(created) }
        let status = SecCodeCheckValidityWithErrors(code, [], requirement, nil)
        return status == errSecSuccess ? nil : .codeRejected(status)
    }

    /// Reads a pipe until its end (or `stop`), with `poll` so that a blocked read never outlives the run.
    private static func drain(_ descriptor: Int32, into buffer: Buffer, limit: Int, stop: Flag,
                              onOverflow: () -> Void) {
        var chunk = [UInt8](repeating: 0, count: 8192)
        while !stop.isSet {
            var item = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&item, 1, 100)
            if ready < 0 { if errno == EINTR { continue }; return }
            if ready == 0 { continue }
            let count = chunk.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
            if count < 0 { if errno == EINTR || errno == EAGAIN { continue }; return }
            if count == 0 { return }
            if !buffer.append(chunk[0..<count], limit: limit) { onOverflow(); return }
        }
    }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
}

private final class Buffer: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes = Data()
    /// False when the bytes would go past `limit` (nothing more is kept).
    func append(_ chunk: ArraySlice<UInt8>, limit: Int) -> Bool {
        lock.withLock {
            guard bytes.count + chunk.count <= limit else { return false }
            bytes.append(contentsOf: chunk)
            return true
        }
    }
    var data: Data { lock.withLock { bytes } }
}
