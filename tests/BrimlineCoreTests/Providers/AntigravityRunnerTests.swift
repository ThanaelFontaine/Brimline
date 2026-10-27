import Foundation
import Testing
@testable import BrimlineCore

/// The real launcher, on small shell scripts that stand in for `agy` (the real one is never started).
@Suite("The launcher of agy: fixed folder, fixed environment, bounded, stopped")
struct AntigravityRunnerTests {
    func script(_ body: String) throws -> (home: TemporaryHome, binary: URL) {
        let home = try TemporaryHome()
        try home.write("fake-agy", "#!/bin/sh\n" + body + "\n")
        let url = home.url.appendingPathComponent("fake-agy")
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return (home, url)
    }

    @Test("Output, errors and exit code come back, and the arguments are the ones given")
    func collects() async throws {
        let (home, binary) = try script(#"printf 'out:%s' "$*"; printf 'err' >&2; exit 3"#)
        let run = try await ProcessAntigravityRunner().run(binary: binary, arguments: ["--print", "/usage"], home: home.url)
        #expect(run.exitCode == 3)
        #expect(String(decoding: run.stdout, as: UTF8.self) == "out:--print /usage")
        #expect(String(decoding: run.stderr, as: UTF8.self) == "err")
    }

    @Test("The environment is HOME, PATH and LANG: a secret of the user's shell never reaches the program")
    func reducedEnvironment() async throws {
        let (home, binary) = try script("/usr/bin/env")
        setenv("BRIMLINE_TEST_SECRET", "hunter2", 1)
        setenv("HTTPS_PROXY", "http://proxy.invalid", 1)
        defer { unsetenv("BRIMLINE_TEST_SECRET"); unsetenv("HTTPS_PROXY") }
        let run = try await ProcessAntigravityRunner().run(binary: binary, arguments: [], home: home.url)
        let lines = Set(String(decoding: run.stdout, as: UTF8.self).split(separator: "\n").map(String.init))
        #expect(lines.contains("HOME=\(home.url.path)"))
        #expect(lines.contains("PATH=/usr/bin:/bin"))
        #expect(lines.contains("LANG=en_US.UTF-8"))
        #expect(!lines.contains { $0.contains("hunter2") || $0.hasPrefix("HTTPS_PROXY") || $0.hasPrefix("BRIMLINE_TEST") })
        #expect(ProcessAntigravityRunner.environment(home: home.url).count == 3)
    }

    @Test("The working folder is new, empty, private, inside Brimline's temporary folder, and removed afterwards")
    func workingFolder() async throws {
        let (home, binary) = try script(#"pwd -P; ls -A | wc -l | tr -d ' '; stat -f %Lp ."#)
        let run = try await ProcessAntigravityRunner().run(binary: binary, arguments: [], home: home.url)
        let lines = String(decoding: run.stdout, as: UTF8.self).split(separator: "\n").map(String.init)
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
        let (home, binary) = try script(#"cat | wc -c | tr -d ' '"#)
        let run = try await ProcessAntigravityRunner(timeout: 5).run(binary: binary, arguments: [], home: home.url)
        #expect(String(decoding: run.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "0")
    }

    @Test("A program that does not finish is stopped at the delay")
    func timesOut() async throws {
        let (home, binary) = try script("exec sleep 30")
        let started = Date()
        await #expect(throws: AntigravityRunFailure.timedOut) {
            _ = try await ProcessAntigravityRunner(timeout: 1).run(binary: binary, arguments: [], home: home.url)
        }
        #expect(Date().timeIntervalSince(started) < 10)
    }

    @Test("A program that writes too much is stopped, on either stream")
    func outputBounded() async throws {
        let (home, binary) = try script("exec yes brimline")
        await #expect(throws: AntigravityRunFailure.outputTooLong) {
            _ = try await ProcessAntigravityRunner(timeout: 10, maxOutputBytes: 4096).run(binary: binary, arguments: [], home: home.url)
        }
        let (home2, binary2) = try script("exec yes brimline >&2")
        await #expect(throws: AntigravityRunFailure.outputTooLong) {
            _ = try await ProcessAntigravityRunner(timeout: 10, maxOutputBytes: 4096).run(binary: binary2, arguments: [], home: home2.url)
        }
    }

    @Test("A program that cannot start is reported, not crashed on")
    func cannotLaunch() async throws {
        let home = try TemporaryHome()
        await #expect(throws: AntigravityRunFailure.couldNotLaunch) {
            _ = try await ProcessAntigravityRunner().run(binary: home.url.appendingPathComponent("missing"), arguments: [], home: home.url)
        }
    }

    @Test("The default limits are 20 seconds and 64 KiB")
    func defaults() {
        let runner = ProcessAntigravityRunner()
        #expect(runner.timeout == 20)
        #expect(runner.maxOutputBytes == 64 * 1024)
    }
}
