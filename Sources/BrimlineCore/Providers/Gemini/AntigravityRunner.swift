import Foundation

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
}

/// Launches `agy`. A protocol, so that no test and no CI run ever starts a real `agy`.
public protocol AntigravityRunning: Sendable {
    func run(binary: URL, arguments: [String], home: URL) async throws(AntigravityRunFailure) -> AntigravityRun
}

/// The real launcher: a `Process` with everything fixed.
///
/// - the working folder is new and empty, inside Brimline's own temporary folder (owner only), and
///   removed afterwards, so the program has nothing of the user's to look at;
/// - the environment is `HOME`, `PATH=/usr/bin:/bin` and `LANG=en_US.UTF-8` and nothing else (no
///   token, no proxy, no variable of the user's shell);
/// - nothing is typed to it (standard input is empty), and its output is read on other threads, at
///   most `maxOutputBytes` per stream: past that, or past `timeout` seconds, it is stopped.
public struct ProcessAntigravityRunner: AntigravityRunning {
    public static let defaultTimeout: TimeInterval = 20
    public static let defaultMaxOutputBytes = 64 * 1024

    public var timeout: TimeInterval
    public var maxOutputBytes: Int

    public init(timeout: TimeInterval = Self.defaultTimeout, maxOutputBytes: Int = Self.defaultMaxOutputBytes) {
        self.timeout = timeout
        self.maxOutputBytes = maxOutputBytes
    }

    public func run(binary: URL, arguments: [String], home: URL) async throws(AntigravityRunFailure) -> AntigravityRun {
        let timeout = self.timeout, limit = maxOutputBytes
        let result: Result<AntigravityRun, AntigravityRunFailure> = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: Self.runBlocking(binary: binary, arguments: arguments, home: home,
                                                                timeout: timeout, limit: limit))
            }
        }
        return try result.get()
    }

    /// The environment the program gets: exactly this.
    static func environment(home: URL) -> [String: String] {
        ["HOME": home.path, "PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"]
    }

    private static func runBlocking(binary: URL, arguments: [String], home: URL, timeout: TimeInterval,
                                    limit: Int) -> Result<AntigravityRun, AntigravityRunFailure> {
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

        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        process.environment = environment(home: home)
        process.currentDirectoryURL = workFolder
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice

        let stop = Flag()
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return .failure(.couldNotLaunch) }

        let overflow = Flag()
        let readers = DispatchGroup()
        let outBuffer = Buffer(), errBuffer = Buffer()
        for (pipe, buffer) in [(out, outBuffer), (err, errBuffer)] {
            readers.enter()
            let descriptor = pipe.fileHandleForReading.fileDescriptor
            DispatchQueue.global(qos: .utility).async {
                defer { readers.leave() }
                drain(descriptor, into: buffer, limit: limit, stop: stop, onOverflow: {
                    overflow.set()
                    finished.signal()
                })
            }
        }

        let timedOut = finished.wait(timeout: .now() + timeout) == .timedOut
        let exited = process.isRunning == false
        if !exited {
            process.terminate()
            if finished.wait(timeout: .now() + 2) == .timedOut { kill(process.processIdentifier, SIGKILL) }
        }
        // The program is gone: what is left in the pipes arrives at once, unless a child of it holds them.
        if readers.wait(timeout: .now() + 2) == .timedOut { stop.set() }
        readers.wait()

        if overflow.isSet { return .failure(.outputTooLong) }
        if timedOut && !exited { return .failure(.timedOut) }
        let code = process.terminationReason == .exit ? process.terminationStatus : 128 + process.terminationStatus
        return .success(AntigravityRun(exitCode: code, stdout: outBuffer.data, stderr: errBuffer.data))
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
