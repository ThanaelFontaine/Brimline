import Foundation
import Security
import Testing
@testable import BrimlineCore

/// A small program that stands in for `agy` (the real one is never started): compiled once for the run, signed ad
/// hoc with a test identifier, and told what to do by the file `mode` in the `HOME` it is given. Shell scripts
/// cannot stand in any more: the launcher checks the code of the process, and for a script that code is `/bin/sh`.
enum Standin {
    static let identifier = "com.brimline.standin"

    struct Built: Sendable {
        var url: URL
        var cdhash: String
        /// The requirement the launcher gets in the tests: this identifier and exactly this build.
        var requirement: String { "identifier \"\(identifier)\" and cdhash H\"\(cdhash)\"" }
    }

    /// Nil, with the reason, when there is no compiler or no `codesign` on this machine: the tests are then
    /// skipped with that message, never green by default.
    static let built: Result<Built, StandinFailure> = build()
    static var available: Bool { if case .success = built { return true }; return false }
    static func require() throws -> Built {
        switch built {
        case .success(let value): return value
        case .failure(let failure): throw failure
        }
    }

    struct StandinFailure: Error, CustomStringConvertible { var description: String }

    private static let source = #"""
    #include <dirent.h>
    #include <fcntl.h>
    #include <signal.h>
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>
    #include <sys/stat.h>
    #include <sys/wait.h>
    #include <unistd.h>
    extern char **environ;

    static void touch(const char *home, const char *name, const char *text) {
        char path[4096];
        snprintf(path, sizeof path, "%s/%s", home, name);
        FILE *f = fopen(path, "w");
        if (f) { fputs(text, f); fclose(f); }
    }

    int main(int argc, char **argv) {
        const char *home = getenv("HOME");
        if (!home) return 99;
        char pid[32];
        snprintf(pid, sizeof pid, "%d", getpid());
        touch(home, "ran", "1");
        touch(home, "pid", pid);
        char path[4096], mode[64] = "collect";
        snprintf(path, sizeof path, "%s/mode", home);
        FILE *f = fopen(path, "r");
        if (f) { if (fscanf(f, "%63s", mode) != 1) strcpy(mode, "collect"); fclose(f); }

        if (!strcmp(mode, "collect")) {
            printf("out:");
            for (int i = 1; i < argc; i++) printf("%s%s", i > 1 ? " " : "", argv[i]);
            fprintf(stderr, "err");
            return 3;
        }
        if (!strcmp(mode, "env")) { for (char **e = environ; *e; e++) puts(*e); return 0; }
        if (!strcmp(mode, "folder")) {
            char here[4096];
            if (!getcwd(here, sizeof here)) return 98;
            int count = 0;
            DIR *d = opendir(".");
            struct dirent *entry;
            while (d && (entry = readdir(d))) if (strcmp(entry->d_name, ".") && strcmp(entry->d_name, "..")) count++;
            if (d) closedir(d);
            struct stat info;
            stat(".", &info);
            printf("%s\n%d\n%o\n", here, count, info.st_mode & 0777);
            return 0;
        }
        if (!strcmp(mode, "stdin")) {
            long total = 0;
            char chunk[512];
            ssize_t n;
            while ((n = read(0, chunk, sizeof chunk)) > 0) total += n;
            printf("%ld\n", total);
            return 0;
        }
        if (!strcmp(mode, "descriptors")) {
            for (int fd = 0; fd < 256; fd++) if (fcntl(fd, F_GETFD) != -1) printf("%d ", fd);
            printf("\n");
            return 0;
        }
        if (!strcmp(mode, "signals")) {
            sigset_t blocked;
            sigprocmask(SIG_BLOCK, NULL, &blocked);
            int count = 0, handled = 0;
            for (int s = 1; s < 32; s++) {
                if (sigismember(&blocked, s)) count++;
                struct sigaction a;
                if (s != SIGKILL && s != SIGSTOP && sigaction(s, NULL, &a) == 0 && a.sa_handler != SIG_DFL) handled++;
            }
            printf("blocked=%d notdefault=%d\n", count, handled);
            return 0;
        }
        if (!strcmp(mode, "print") || !strcmp(mode, "stuckchild") || !strcmp(mode, "childreport")) {
            // What the end-to-end tests need: the arguments and the environment as seen here, a child that
            // outlives the program or hangs on, and a text to print (the file `stdout` of the home).
            if (!strcmp(mode, "print")) {
                snprintf(path, sizeof path, "%s/agylog", home);
                FILE *log = fopen(path, "a");
                if (log) {
                    for (int i = 1; i < argc; i++) fprintf(log, "%s%s", i > 1 ? " " : "", argv[i]);
                    fprintf(log, "\n");
                    for (char **e = environ; *e; e++) fprintf(log, "%s\n", *e);
                    fclose(log);
                }
            } else {
                pid_t child = fork();
                if (child == 0) { sleep(47); _exit(0); }
                char text[32];
                snprintf(text, sizeof text, "%d", child);
                touch(home, "childpid", text);
                if (!strcmp(mode, "stuckchild")) { int st; waitpid(child, &st, 0); return 0; }
            }
            snprintf(path, sizeof path, "%s/stdout", home);
            int in = open(path, O_RDONLY);
            char chunk[8192];
            ssize_t n;
            while (in >= 0 && (n = read(in, chunk, sizeof chunk)) > 0) if (write(1, chunk, n) < 0) return 1;
            return 0;
        }
        if (!strcmp(mode, "ident")) { printf("%d %d\n", getpid(), getpgrp()); return 0; }
        if (!strcmp(mode, "sleep")) { sleep(30); return 0; }
        if (!strcmp(mode, "ignoreterm")) { signal(SIGTERM, SIG_IGN); sleep(30); return 0; }
        if (!strcmp(mode, "flood") || !strcmp(mode, "floodErr")) {
            int fd = !strcmp(mode, "flood") ? 1 : 2;
            for (;;) if (write(fd, "brimline\n", 9) < 0) return 1;
        }
        if (!strcmp(mode, "grandchild") || !strcmp(mode, "leaver")) {
            // A child that keeps the pipes (and, for "leaver", leaves the group), while this program ends.
            pid_t child = fork();
            if (child == 0) {
                if (!strcmp(mode, "leaver")) setsid();
                sleep(30);
                _exit(0);
            }
            printf("%d\n", child);
            fflush(stdout);
            return 0;
        }
        return 97;
    }
    """#

    private static func run(_ tool: String, _ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// Signs a copy ad hoc with an identifier and gives the `cdhash` it ends up with.
    static func sign(_ url: URL, identifier: String = Standin.identifier) throws -> String {
        let signed = try run("/usr/bin/codesign", ["-f", "-s", "-", "-i", identifier, url.path])
        guard signed.status == 0 else { throw StandinFailure(description: "codesign: \(signed.output)") }
        return try cdhash(of: url)
    }

    static func cdhash(of url: URL) throws -> String {
        let shown = try run("/usr/bin/codesign", ["-dvvv", url.path])
        guard let line = shown.output.split(separator: "\n").first(where: { $0.hasPrefix("CDHash=") }) else {
            throw StandinFailure(description: "no CDHash in: \(shown.output)")
        }
        return String(line.dropFirst("CDHash=".count))
    }

    private static func build() -> Result<Built, StandinFailure> {
        do {
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("brimline-standin-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let code = folder.appendingPathComponent("standin.c")
            try Data(source.utf8).write(to: code)
            let url = folder.appendingPathComponent("standin")
            let compiled = try run("/usr/bin/cc", ["-o", url.path, code.path])
            guard compiled.status == 0 else { return .failure(StandinFailure(description: "No C compiler here: \(compiled.output)")) }
            let hash = try sign(url)
            Folder.path = folder.path
            atexit { try? FileManager.default.removeItem(atPath: Standin.Folder.path) }
            return .success(Built(url: url, cdhash: hash))
        } catch {
            return .failure(StandinFailure(description: "Cannot build the stand-in program: \(error)"))
        }
    }

    /// Where the stand-in is, for the removal at the end of the run.
    enum Folder { nonisolated(unsafe) static var path = "" }
}

/// Runs `work` and gives up after `seconds` with `BoundedTimeout`, even if `work` never comes back (a launcher
/// stuck in `waitpid` on a process that nothing killed): the test then fails at once instead of hanging the run.
/// `.timeLimit` alone only records the failure, the run still waits for the body.
struct BoundedTimeout: Error, CustomStringConvertible { var description: String { "no answer in time" } }

private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func first() -> Bool { lock.withLock { defer { done = true }; return !done } }
}

func bounded<T: Sendable>(seconds: Double = 30, _ body: @escaping () async throws -> T) async throws -> T {
    // The closures capture test fixtures that are not `Sendable`; they are only read, by one task.
    nonisolated(unsafe) let work = body
    let once = Once()
    return try await withCheckedThrowingContinuation { continuation in
        Task {
            do {
                let value = try await work()
                if once.first() { continuation.resume(returning: value) }
            } catch {
                if once.first() { continuation.resume(throwing: error) }
            }
        }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if once.first() { continuation.resume(throwing: BoundedTimeout()) }
        }
    }
}

private final class Seen: @unchecked Sendable {
    private let lock = NSLock()
    private var state: String?
    private var ran: Bool?
    func set(state: String?, ran: Bool) { lock.withLock { self.state = state; self.ran = ran } }
    var value: (String?, Bool?) { lock.withLock { (state, ran) } }
}

/// The real launcher on a program that stands in for `agy`: started suspended, its code checked on the process,
/// then let go; a program that is not the one required never runs.
@Suite("The launcher of agy: suspended, checked on the process, fixed folder and environment, bounded, stopped",
       .enabled(if: Standin.available, "No C compiler or codesign here: the launcher tests need a compiled stand-in"))
struct AntigravityRunnerTests {
    /// A home that tells the stand-in what to do, and the launcher that requires exactly that stand-in.
    func launch(_ mode: String, arguments: [String] = [], timeout: TimeInterval = 20,
                maxOutputBytes: Int = ProcessAntigravityRunner.defaultMaxOutputBytes, requirement: String? = nil,
                binary: URL? = nil) async throws -> (run: AntigravityRun, home: TemporaryHome) {
        let (home, runner, binary) = try prepare(mode, timeout: timeout, maxOutputBytes: maxOutputBytes,
                                                 requirement: requirement, binary: binary)
        return (try await runner.run(binary: binary, arguments: arguments, home: home.url), home)
    }

    func prepare(_ mode: String, timeout: TimeInterval = 20,
                 maxOutputBytes: Int = ProcessAntigravityRunner.defaultMaxOutputBytes, requirement: String? = nil,
                 binary: URL? = nil) throws -> (TemporaryHome, ProcessAntigravityRunner, URL) {
        let built = try Standin.require()
        let home = try TemporaryHome()
        try home.write("mode", mode)
        let runner = ProcessAntigravityRunner(timeout: timeout, maxOutputBytes: maxOutputBytes,
                                              requirement: requirement ?? built.requirement)
        return (home, runner, binary ?? built.url)
    }

    func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }

    /// Whether a process of this number still exists (a zombie counts: it is not gone until it is waited for).
    func exists(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 }

    func pid(in home: TemporaryHome) throws -> pid_t {
        let text = try String(contentsOf: home.url.appendingPathComponent("pid"), encoding: .utf8)
        return try #require(pid_t(text))
    }

    func ran(_ home: TemporaryHome) -> Bool {
        FileManager.default.fileExists(atPath: home.url.appendingPathComponent("ran").path)
    }

    /// Waits up to `seconds` for a process (not ours to wait for) to be gone.
    func gone(_ pid: pid_t, within seconds: Double = 3) async -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while exists(pid) && Date() < end { try? await Task.sleep(nanoseconds: 50_000_000) }
        return !exists(pid)
    }

    // MARK: What the launcher does with a program that is the one required

    @Test("Output, errors and exit code come back, and the arguments are the ones given")
    func collects() async throws {
        let (run, home) = try await launch("collect", arguments: ["--print", "/usage"])
        #expect(run.exitCode == 3)
        #expect(text(run.stdout) == "out:--print /usage")
        #expect(text(run.stderr) == "err")
        #expect(ran(home))
    }

    @Test("The environment is HOME, PATH and LANG: a secret of the user's shell never reaches the program")
    func reducedEnvironment() async throws {
        setenv("BRIMLINE_TEST_SECRET", "hunter2", 1)
        setenv("HTTPS_PROXY", "http://proxy.invalid", 1)
        defer { unsetenv("BRIMLINE_TEST_SECRET"); unsetenv("HTTPS_PROXY") }
        let (run, home) = try await launch("env")
        let lines = Set(text(run.stdout).split(separator: "\n").map(String.init))
        #expect(lines == ["HOME=\(home.url.path)", "PATH=/usr/bin:/bin", "LANG=en_US.UTF-8"])
        #expect(ProcessAntigravityRunner.environment(home: home.url).count == 3)
    }

    @Test("The working folder is new, empty, private, inside Brimline's temporary folder, and removed afterwards")
    func workingFolder() async throws {
        let (run, home) = try await launch("folder")
        let lines = text(run.stdout).split(separator: "\n").map(String.init)
        #expect(lines.count == 3)
        let folder = lines[0]
        #expect(folder.contains("/Brimline/agy-"))
        #expect(!folder.hasPrefix(home.url.path))
        #expect(lines[1] == "0")
        #expect(lines[2] == "700")
        #expect(!FileManager.default.fileExists(atPath: folder))
    }

    @Test("Nothing is typed to it: standard input is empty, so it never waits for an answer")
    func emptyInput() async throws {
        let (run, _) = try await launch("stdin", timeout: 5)
        #expect(text(run.stdout).trimmingCharacters(in: .whitespacesAndNewlines) == "0")
    }

    @Test("Only the three standard descriptors reach the program: nothing else of Brimline's is open in it")
    func onlyStandardDescriptors() async throws {
        // Something of ours that would be inherited by a plain launch.
        let leak = open("/dev/null", O_RDONLY)
        defer { close(leak) }
        _ = fcntl(leak, F_SETFD, 0)
        let (run, _) = try await launch("descriptors")
        #expect(text(run.stdout).trimmingCharacters(in: .whitespacesAndNewlines) == "0 1 2")
    }

    @Test("No signal is blocked in the program and every handler is the default one")
    func cleanSignals() async throws {
        var blocked = sigset_t(), previous = sigset_t()
        sigemptyset(&blocked)
        sigaddset(&blocked, SIGUSR2)
        pthread_sigmask(SIG_BLOCK, &blocked, &previous)
        defer { pthread_sigmask(SIG_SETMASK, &previous, nil) }
        let (run, _) = try await launch("signals")
        #expect(text(run.stdout).trimmingCharacters(in: .whitespacesAndNewlines) == "blocked=0 notdefault=0")
    }

    @Test("The program leads a process group of its own, which is not Brimline's")
    func ownGroup() async throws {
        let (run, _) = try await launch("ident")
        let parts = text(run.stdout).split(whereSeparator: \.isWhitespace).compactMap { pid_t($0) }
        #expect(parts.count == 2)
        #expect(parts[0] == parts[1])
        #expect(parts[1] != getpgrp())
    }

    // MARK: Delays, bounds, no process left behind

    @Test("A program that does not finish is stopped at the delay, and is gone")
    func timesOut() async throws {
        let (home, runner, binary) = try prepare("sleep", timeout: 1)
        let started = Date()
        await #expect(throws: AntigravityRunFailure.timedOut) {
            _ = try await runner.run(binary: binary, arguments: [], home: home.url)
        }
        #expect(Date().timeIntervalSince(started) < 10)
        #expect(await gone(try pid(in: home), within: 0.1))
    }

    @Test("A program that ignores the polite stop is killed 2 seconds later")
    func ignoresTerm() async throws {
        let (home, runner, binary) = try prepare("ignoreterm", timeout: 1)
        let started = Date()
        await #expect(throws: AntigravityRunFailure.timedOut) {
            _ = try await runner.run(binary: binary, arguments: [], home: home.url)
        }
        let elapsed = Date().timeIntervalSince(started)
        #expect(elapsed >= 2.5 && elapsed < 10)
        #expect(await gone(try pid(in: home), within: 0.1))
    }

    @Test("A program that writes too much is stopped, on either stream, and is gone")
    func outputBounded() async throws {
        for mode in ["flood", "floodErr"] {
            let (home, runner, binary) = try prepare(mode, timeout: 10, maxOutputBytes: 4096)
            await #expect(throws: AntigravityRunFailure.outputTooLong) {
                _ = try await runner.run(binary: binary, arguments: [], home: home.url)
            }
            #expect(await gone(try pid(in: home), within: 0.1))
        }
    }

    @Test("The limit is per stream: a text of exactly the limit passes, one byte more does not")
    func limitIsExact() async throws {
        let (home, runner, binary) = try prepare("collect", maxOutputBytes: 6)
        let run = try await runner.run(binary: binary, arguments: ["ab"], home: home.url)   // "out:ab" is 6 bytes
        #expect(text(run.stdout) == "out:ab")
        await #expect(throws: AntigravityRunFailure.outputTooLong) {
            _ = try await runner.run(binary: binary, arguments: ["abc"], home: home.url)
        }
    }

    @Test("A child that keeps the pipes is stopped with its group: the run ends at once and nothing stays behind")
    func childKeepsThePipes() async throws {
        let started = Date()
        let (run, home) = try await launch("grandchild", timeout: 20)
        #expect(Date().timeIntervalSince(started) < 5)
        let child = try #require(pid_t(text(run.stdout).trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(run.exitCode == 0)
        #expect(await gone(child))
        #expect(await gone(try pid(in: home), within: 0.1))
    }

    @Test("A child that left the group and keeps the pipes: the run still ends (the pipes are given up after 2 seconds)")
    func childLeftTheGroup() async throws {
        let started = Date()
        let (run, _) = try await launch("leaver", timeout: 20)
        let child = try #require(pid_t(text(run.stdout).trimmingCharacters(in: .whitespacesAndNewlines)))
        defer { kill(child, SIGKILL) }   // out of Brimline's reach, as SECURITY.md says: the test cleans up
        #expect(Date().timeIntervalSince(started) < 8)
        #expect(run.exitCode == 0)
    }

    @Test("A hundred launches leave no zombie and no process")
    func noZombies() async throws {
        let built = try Standin.require()
        let home = try TemporaryHome()
        try home.write("mode", "ident")
        let runner = ProcessAntigravityRunner(requirement: built.requirement)
        var pids: [pid_t] = []
        for _ in 0..<100 {
            let run = try await runner.run(binary: built.url, arguments: [], home: home.url)
            let parts = text(run.stdout).split(whereSeparator: \.isWhitespace).compactMap { pid_t($0) }
            try #require(parts.count == 2)
            pids.append(parts[0])
        }
        // `kill(pid, 0)` succeeds on a zombie: the program was waited for, every time.
        #expect(pids.filter { exists($0) }.isEmpty)
    }

    @Test("Many launches at once do not hold each other up: each blocking piece has a thread of its own (the shared pool of Dispatch is never starved)")
    func manyAtOnce() async throws {
        let built = try Standin.require()
        let home = try TemporaryHome()
        try home.write("mode", "ident")
        let runner = ProcessAntigravityRunner(timeout: 20, requirement: built.requirement)
        let url = built.url, homeURL = home.url
        let started = Date()
        let done = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<100 {
                group.addTask { (try? await runner.run(binary: url, arguments: [], home: homeURL)) != nil }
            }
            var count = 0
            for await ok in group where ok { count += 1 }
            return count
        }
        #expect(done == 100)
        #expect(Date().timeIntervalSince(started) < 15)
    }

    @Test("A program that cannot start is reported, not crashed on")
    func cannotLaunch() async throws {
        let home = try TemporaryHome()
        await #expect(throws: AntigravityRunFailure.couldNotLaunch) {
            _ = try await ProcessAntigravityRunner().run(binary: home.url.appendingPathComponent("missing"), arguments: [], home: home.url)
        }
    }

    @Test("The default limits are 20 seconds and 64 KiB, and the default requirement is Google's")
    func defaults() {
        let runner = ProcessAntigravityRunner()
        #expect(runner.timeout == 20)
        #expect(runner.maxOutputBytes == 64 * 1024)
        #expect(runner.requirement == SecurityFrameworkCodeChecker.google)
    }

    /// What `ps` says of a process (its state letters), or nil when it cannot be read.
    static func state(of pid: pid_t) -> String? {
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-o", "stat=", "-p", String(pid)]
        let pipe = Pipe()
        ps.standardOutput = pipe
        do { try ps.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        ps.waitUntilExit()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Test("The program is held suspended while its code is checked: stopped (T) and not a single instruction run",
          .timeLimit(.minutes(1)))
    func heldSuspendedWhileChecked() async throws {
        let built = try Standin.require()
        for requirement in [built.requirement, SecurityFrameworkCodeChecker.google] {
            let home = try TemporaryHome()
            try home.write("mode", "collect")
            let seen = Seen()
            var runner = ProcessAntigravityRunner(requirement: requirement)
            let ranFile = home.url.appendingPathComponent("ran").path
            runner.afterSpawn = { pid in
                seen.set(state: Self.state(of: pid), ran: FileManager.default.fileExists(atPath: ranFile))
            }
            _ = try await bounded { [runner] in try? await runner.run(binary: built.url, arguments: [], home: home.url) }
            let (state, ranBefore) = seen.value
            #expect(state?.contains("T") == true, "state of the process before the check: \(state ?? "unreadable")")
            #expect(ranBefore == false)
        }
    }

    // MARK: A program that is not the one required never runs

    @Test("The same program against Google's requirement is rejected before it runs a single instruction", .timeLimit(.minutes(1)))
    func notGoogle() async throws {
        let (home, runner, binary) = try prepare("collect", requirement: SecurityFrameworkCodeChecker.google)
        await #expect(throws: AntigravityRunFailure.codeRejected(errSecCSReqFailed)) {
            _ = try await bounded { [runner] in try await runner.run(binary: binary, arguments: [], home: home.url) }
        }
        #expect(!ran(home))
    }

    @Test("The default launcher (Google's requirement) rejects an ad hoc signed program that even carries the identifier cli", .timeLimit(.minutes(1)))
    func adHocCli() async throws {
        let built = try Standin.require()
        let folder = built.url.deletingLastPathComponent().appendingPathComponent("cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let copy = folder.appendingPathComponent("agy")
        try FileManager.default.copyItem(at: built.url, to: copy)
        _ = try Standin.sign(copy, identifier: "cli")
        let home = try TemporaryHome()
        try home.write("mode", "collect")
        await #expect(throws: AntigravityRunFailure.codeRejected(errSecCSReqFailed)) {
            _ = try await bounded { try await ProcessAntigravityRunner().run(binary: copy, arguments: [], home: home.url) }
        }
        #expect(!ran(home))
    }

    @Test("Another build at the path (replaced after the check) is rejected and never runs", .timeLimit(.minutes(1)))
    func replacedBeforeLaunch() async throws {
        let built = try Standin.require()
        let folder = built.url.deletingLastPathComponent().appendingPathComponent("swap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("agy")
        try FileManager.default.copyItem(at: built.url, to: path)
        let wanted = try Standin.sign(path)
        let requirement = "identifier \"\(Standin.identifier)\" and cdhash H\"\(wanted)\""

        let home = try TemporaryHome()
        try home.write("mode", "collect")
        // The build that was checked runs...
        let first = try await ProcessAntigravityRunner(requirement: requirement).run(binary: path, arguments: [], home: home.url)
        #expect(text(first.stdout) == "out:")
        try FileManager.default.removeItem(at: home.url.appendingPathComponent("ran"))

        // ...then another copy, signed ad hoc too, takes its place: same path, same identifier, another code.
        try FileManager.default.removeItem(at: path)
        try FileManager.default.copyItem(at: built.url, to: path)
        let other = try Standin.sign(path, identifier: "com.brimline.standin.other")
        #expect(other != wanted)
        await #expect(throws: AntigravityRunFailure.codeRejected(errSecCSReqFailed)) {
            _ = try await bounded { try await ProcessAntigravityRunner(requirement: requirement).run(binary: path, arguments: [], home: home.url) }
        }
        #expect(!ran(home))
    }

    @Test("A shell script is rejected: the code of the process is /bin/sh, not the script", .timeLimit(.minutes(1)))
    func scriptRejected() async throws {
        let built = try Standin.require()
        let home = try TemporaryHome()
        try home.write("fake-agy", "#!/bin/sh\ntouch \"$HOME/ran\"\necho hello\n")
        let script = home.url.appendingPathComponent("fake-agy")
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        await #expect(throws: AntigravityRunFailure.codeRejected(errSecCSReqFailed)) {
            _ = try await bounded { try await ProcessAntigravityRunner(requirement: built.requirement).run(binary: script, arguments: [], home: home.url) }
        }
        #expect(!ran(home))
    }

    @Test("A rejected program is gone: killed and waited for, no process and no zombie of it is left", .timeLimit(.minutes(1)))
    func rejectedIsGone() async throws {
        // A copy at a path of its own, so that no other test's stand-in can show up in the list of processes.
        let built = try Standin.require()
        let folder = built.url.deletingLastPathComponent().appendingPathComponent("gone-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let copy = folder.appendingPathComponent("agy")
        try FileManager.default.copyItem(at: built.url, to: copy)
        let home = try TemporaryHome()
        try home.write("mode", "sleep")
        let runner = ProcessAntigravityRunner(requirement: SecurityFrameworkCodeChecker.google)
        // One bound for the twenty launches: a launcher that hangs fails the test once, not twenty times.
        let rejections = try await bounded(seconds: 60) { [runner] in
            var count = 0
            for _ in 0..<20 {
                do { _ = try await runner.run(binary: copy, arguments: [], home: home.url) }
                catch AntigravityRunFailure.codeRejected(let status) where status == errSecCSReqFailed { count += 1 }
                catch { break }
            }
            return count
        }
        #expect(rejections == 20)
        #expect(!ran(home))
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-axo", "stat=,command="]
        let pipe = Pipe()
        ps.standardOutput = pipe
        try ps.run()
        let listing = text(pipe.fileHandleForReading.readDataToEndOfFile())
        ps.waitUntilExit()
        // A zombie of a launched copy shows in `ps` with its path; a rejected one must not.
        #expect(!listing.contains(copy.path))
    }

    @Test("A requirement the system cannot read is a rejection too, never a launch", .timeLimit(.minutes(1)))
    func brokenRequirement() async throws {
        let (home, runner, binary) = try prepare("collect", requirement: "this is not a requirement")
        await #expect(throws: AntigravityRunFailure.self) {
            _ = try await bounded { [runner] in try await runner.run(binary: binary, arguments: [], home: home.url) }
        }
        #expect(!ran(home))
    }

    // MARK: The real agy (never in CI)

    @Test("The real agy, on the Mac that has it: only with BRIMLINE_REAL_AGY=1 (never in CI)",
          .enabled(if: ProcessInfo.processInfo.environment["BRIMLINE_REAL_AGY"] == "1"))
    func realAgy() async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let run = try await ProcessAntigravityRunner().run(binary: AntigravityBinary.url(home: home),
                                                           arguments: GeminiReader.usageArguments, home: home)
        #expect(run.exitCode == 0)
        let limits = try AntigravityUsageParser.parse(run.stdout)
        #expect(!limits.isEmpty)
    }
}
