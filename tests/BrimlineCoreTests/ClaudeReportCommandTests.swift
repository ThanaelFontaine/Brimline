import Foundation
import Testing
@testable import BrimlineCore

/// `brimline report claude` run on a pipe of its own: the input is read to its end whatever happens, a long line
/// is dropped without being held, the status line prints only what this input gave, `auto` agrees with the
/// session's transcript, `--dir` never changes a folder, and "Do not read" keeps a report closed by address.
@Suite("Claude Code reports: the command")
struct ClaudeReportCommandTests {
    let now = date("2026-10-28T00:00:00Z")
    var epoch: Int { Int(now.timeIntervalSince1970) }

    func event(_ windows: String) -> String {
        #"{"type":"rate_limit_event","rate_limit_info":{"status":"allowed","unifiedWindows":\#(windows)},"session_id":"s"}"#
    }

    func statusline(_ rateLimits: String?, transcript: String? = nil) -> String {
        var object: [String: Any] = ["session_id": "s", "model": ["display_name": "Opus"]]
        if let transcript { object["transcript_path"] = transcript }
        var text = String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        if let rateLimits { text = String(text.dropLast()) + #","rate_limits":\#(rateLimits)}"# }
        return text
    }

    final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.lock(); value = true; lock.unlock() }
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    }

    /// Runs the command with its input on a pipe that a producer fills piece by piece, `delay` apart, the first piece
    /// after `delay` too: like `claude -p`, which writes while the command already runs. Says whether one of the
    /// producer's writes failed (the pipe closed early: `EPIPE`).
    func run(_ command: ClaudeReportCommand, _ arguments: [String], pieces: [String],
             delay: useconds_t = 50_000) -> (outcome: ClaudeReportCommand.Outcome, writeFailed: Bool) {
        signal(SIGPIPE, SIG_IGN)
        var ends: [Int32] = [0, 0]
        precondition(pipe(&ends) == 0)
        let (reading, writing) = (ends[0], ends[1])
        let failed = Flag()
        let done = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            for piece in pieces {
                usleep(delay)
                let bytes = Array(piece.utf8)
                var offset = 0
                while offset < bytes.count {
                    let n = bytes[offset...].withUnsafeBytes { Darwin.write(writing, $0.baseAddress, $0.count) }
                    if n < 0 { failed.set(); break }
                    offset += n
                }
            }
            close(writing)
            done.signal()
        }
        let outcome = command.run(arguments, input: reading)
        close(reading)
        done.wait()
        return (outcome, failed.isSet)
    }

    func command(_ home: TemporaryHome, environment: [String: String] = [:]) -> ClaudeReportCommand {
        ClaudeReportCommand(environment: environment, home: home.url, strings: Strings(.en), now: now)
    }

    func store(_ home: TemporaryHome) -> ClaudeReportStore {
        ClaudeReportStore(directory: BrimlinePaths(home: home.url).claudeReportsDirectory)
    }

    // MARK: The input is read to its end

    @Test("A usage error still reads the whole input: a producer that writes after the decision never sees the pipe closed")
    func usageErrorDrains() throws {
        let home = try TemporaryHome()
        let pieces = ["{\"type\":\"system\"}\n", "{\"type\":\"assistant\"}\n", event(#"{"five_hour":{"utilization":0.5}}"#) + "\n"]
        for arguments in [["claude", "--account", "not an address"], ["claude"], ["claude", "--account", "a@example.com", "--bogus"],
                          ["claude", "--account", "auto"], ["claude", "--provider", "claude", "--account", "a@example.com"]] {
            let (outcome, writeFailed) = run(command(home), arguments, pieces: pieces)
            #expect(outcome.code == ClaudeReportCommand.Exit.usage, "\(arguments)")
            #expect(outcome.error != nil)
            #expect(!writeFailed, "\(arguments)")
        }
        // The same with --statusline: silent, exit 0, input read to its end.
        let (outcome, writeFailed) = run(command(home), ["claude", "--account", "nope", "--statusline"], pieces: pieces)
        #expect(outcome == ClaudeReportCommand.Outcome(code: 0))
        #expect(!writeFailed)
        #expect(store(home).list().isEmpty)
    }

    @Test("A report that cannot be written still reads the whole input")
    func writeFailureDrains() throws {
        let home = try TemporaryHome()
        try home.mkdir("open")
        chmod(home.path("open"), 0o755)
        let pieces = [event(#"{"five_hour":{"utilization":0.5}}"#) + "\n", "{\"type\":\"result\"}\n"]
        let (outcome, writeFailed) = run(command(home), ["claude", "--account", "a@example.com", "--dir", home.path("open")], pieces: pieces)
        #expect(outcome.code == ClaudeReportCommand.Exit.notWritten)
        #expect(!writeFailed)
    }

    @Test("stream-json piece by piece: the event is recorded, exit 0; no event, exit 3; an unknown event, exit 4")
    func streamCodes() throws {
        let home = try TemporaryHome()
        let event = event(#"{"five_hour":{"utilization":0.25,"resetsAt":\#(epoch + 3600)},"seven_day":{"utilization":0.5}}"#)
        let half = event.index(event.startIndex, offsetBy: event.count / 2)
        let (ok, failed) = run(command(home), ["claude", "--account=Someone@Example.com"],
                               pieces: ["{\"type\":\"system\"}\n", String(event[..<half]), String(event[half...]) + "\n"])
        #expect(ok == ClaudeReportCommand.Outcome(code: 0))
        #expect(!failed)
        let report = try store(home).load("someone@example.com")
        #expect(report.fiveHour?.percent == 25 && report.sevenDay?.percent == 50)

        #expect(run(command(home), ["claude", "--account", "someone@example.com"], pieces: ["{\"type\":\"result\"}\n"]).outcome.code == 3)
        let bare = #"{"type":"rate_limit_event","rate_limit_info":{"status":"allowed"}}"#
        #expect(run(command(home), ["claude", "--account", "someone@example.com"], pieces: [bare + "\n"]).outcome.code == 4)
        #expect(try store(home).load("someone@example.com").status == .formatChanged)
    }

    // MARK: Long lines

    @Test("A line longer than 64 KiB is dropped whole, across blocks, and the lines after it are read")
    func longLines() throws {
        var lines: [String] = []
        let (r, w) = try pipePair()
        let text = "a\r\n" + String(repeating: "x", count: 300_000) + "\nb\n" + String(repeating: "y", count: 10) + "\n" + "tail"
        let writer = Thread {
            _ = text.utf8CString.withUnsafeBufferPointer { Darwin.write(w, $0.baseAddress, $0.count - 1) }
            close(w)
        }
        writer.start()
        BoundedInput.forEachLine(descriptor: r, maxLineBytes: 64 * 1024) { lines.append(String(decoding: $0, as: UTF8.self)) }
        close(r)
        #expect(lines == ["a", "b", String(repeating: "y", count: 10), "tail"])

        let home = try TemporaryHome()
        let huge = #"{"type":"rate_limit_event","pad":""# + String(repeating: "z", count: 200_000) + "\"}\n"
        let (outcome, _) = run(command(home), ["claude", "--account", "a@example.com"],
                               pieces: [huge, event(#"{"five_hour":{"utilization":0.1}}"#) + "\n"])
        #expect(outcome.code == 0)
        #expect(try store(home).load("a@example.com").fiveHour?.percent == 10)
    }

    func pipePair() throws -> (Int32, Int32) {
        var ends: [Int32] = [0, 0]
        guard pipe(&ends) == 0 else { throw POSIXError(.EIO) }
        return (ends[0], ends[1])
    }

    // MARK: The status line

    @Test("The status line prints only what this input gave: nothing without rate_limits, even with a report kept")
    func statuslinePrintsThisInput() throws {
        let home = try TemporaryHome()
        let arguments = ["claude", "--account", "a@example.com", "--statusline"]
        let first = run(command(home), arguments, pieces: [statusline(#"{"five_hour":{"used_percentage":23,"resets_at":\#(epoch + 3600)},"seven_day":{"used_percentage":41,"resets_at":\#(epoch + 86400)}}"#)])
        #expect(first.outcome == ClaudeReportCommand.Outcome(code: 0, output: "5 h 23% · Week 41%"))
        // Before the first answer of a session: no rate_limits, nothing printed, the report kept as it was.
        let before = try store(home).load("a@example.com")
        #expect(run(command(home), arguments, pieces: [statusline(nil)]).outcome == ClaudeReportCommand.Outcome(code: 0))
        #expect(try store(home).load("a@example.com") == before)
        // A week missing from this input is shown as last seen (the report merges window by window).
        let second = run(command(home), arguments, pieces: [statusline(#"{"five_hour":{"used_percentage":30,"resets_at":\#(epoch + 3600)}}"#)])
        #expect(second.outcome.output == "5 h 30% · Week 41%")
        // A format Brimline does not know: recorded as such, nothing printed.
        #expect(run(command(home), arguments, pieces: [statusline("[]")]).outcome == ClaudeReportCommand.Outcome(code: 0))
        #expect(try store(home).load("a@example.com").status == .formatChanged)
    }

    @Test("auto takes the folder of the command; with a transcript in another folder, nothing is written or shown")
    func autoAgreesWithTranscript() throws {
        let home = try TemporaryHome()
        try home.write(".claude.json", claudeJSON(email: "main@example.com"))
        try home.write(".claude-work/.claude.json", claudeJSON(email: "work@example.org"))
        let limits = #"{"five_hour":{"used_percentage":12,"resets_at":\#(epoch + 3600)}}"#
        let arguments = ["claude", "--account", "auto", "--statusline"]
        let work = command(home, environment: ["CLAUDE_CONFIG_DIR": home.path(".claude-work")])

        // The session's transcript is in the folder of CLAUDE_CONFIG_DIR: recorded for that address.
        let agrees = run(work, arguments, pieces: [statusline(limits, transcript: home.path(".claude-work/projects/-tmp/s.jsonl"))])
        #expect(agrees.outcome.output == "5 h 12%")
        #expect(store(home).list().map(\.email) == ["work@example.org"])

        // The variable did not reach the command (it reads ~/.claude), but the session is the work folder's.
        let disagrees = run(command(home), arguments, pieces: [statusline(limits, transcript: home.path(".claude-work/projects/-tmp/s.jsonl"))])
        #expect(disagrees.outcome == ClaudeReportCommand.Outcome(code: 0))
        #expect(store(home).list().map(\.email) == ["work@example.org"])

        // The default folder: transcripts in ~/.claude/projects, address in ~/.claude.json.
        let main = run(command(home), arguments, pieces: [statusline(limits, transcript: home.path(".claude/projects/-tmp/s.jsonl"))])
        #expect(main.outcome.output == "5 h 12%")
        // No transcript_path: nothing to compare, the folder of the command is taken.
        #expect(run(work, arguments, pieces: [statusline(limits)]).outcome.output == "5 h 12%")
        // An address written out is never compared.
        let explicit = run(command(home), ["claude", "--account", "other@example.net", "--statusline"],
                           pieces: [statusline(limits, transcript: "/elsewhere/projects/x/s.jsonl")])
        #expect(explicit.outcome.output == "5 h 12%")
    }

    @Test("auto reads .claude.json without following a link")
    func autoNoLink() throws {
        let home = try TemporaryHome()
        try home.write("elsewhere.json", claudeJSON(email: "main@example.com"))
        try FileManager.default.createSymbolicLink(atPath: home.path(".claude.json"), withDestinationPath: home.path("elsewhere.json"))
        #expect(ClaudeReportEmail.auto(environment: [:], home: home.url) == nil)
        #expect(ClaudeReportEmail.transcript("/a/.claude/projects/x/s.jsonl", isIn: "/a/.claude"))
        #expect(!ClaudeReportEmail.transcript("/a/.claude-work/projects/x/s.jsonl", isIn: "/a/.claude"))
        #expect(!ClaudeReportEmail.transcript("/a/.claude/projectsX/s.jsonl", isIn: "/a/.claude"))
    }

    // MARK: The folder

    @Test("--dir: an existing folder open to others is refused and left as it was; a missing one is made 0700")
    func dirNeverChanged() throws {
        let home = try TemporaryHome()
        chmod(home.url.path, 0o755)
        let pieces = [event(#"{"five_hour":{"utilization":0.5}}"#) + "\n"]
        let refused = run(command(home), ["claude", "--account", "a@example.com", "--dir", home.url.path], pieces: pieces)
        #expect(refused.outcome.code == ClaudeReportCommand.Exit.notWritten)
        #expect(refused.outcome.error?.contains("0700") == true)
        let mode = try FileManager.default.attributesOfItem(atPath: home.url.path)[.posixPermissions] as? Int
        #expect(mode == 0o755)
        #expect(!FileManager.default.fileExists(atPath: home.url.appendingPathComponent("a@example.com.json").path))

        let nested = home.url.appendingPathComponent("new/reports")
        #expect(run(command(home), ["claude", "--account", "a@example.com", "--dir", nested.path], pieces: pieces).outcome.code == 0)
        for folder in [nested, nested.deletingLastPathComponent()] {
            #expect(try FileManager.default.attributesOfItem(atPath: folder.path)[.posixPermissions] as? Int == 0o700)
        }
    }

    @Test("An address is 200 characters at most, so that its lock and its temporary file can be named")
    func longAddress() throws {
        let home = try TemporaryHome()
        let longest = String(repeating: "a", count: 200 - "@example.com".count) + "@example.com"
        let pieces = [event(#"{"five_hour":{"utilization":0.5}}"#) + "\n"]
        #expect(run(command(home), ["claude", "--account", longest], pieces: pieces).outcome.code == 0)
        #expect(try store(home).load(longest).fiveHour?.percent == 50)
        #expect(run(command(home), ["claude", "--account", "a" + longest], pieces: pieces).outcome.code == ClaudeReportCommand.Exit.usage)
    }

    // MARK: "Do not read", by address

    @Test("\"Do not read\" closes the report of the address, and keeps it closed when the folder loses its address")
    func doNotReadByAddress() async throws {
        let home = try TemporaryHome()
        try home.write(".claude-work/.claude.json", claudeJSON(email: "Work@Example.org"))
        try store(home).record(.observed(ClaudeCodeObservation(source: .statusline, fiveHour: .init(percent: 40, resetsAt: nil), sevenDay: nil)),
                               email: "work@example.org", now: now)
        let service = UsageService(credentials: FakeCredentials([:]), http: FakeHTTP([:]))
        let folder = try #require(Providers.discover(readers: service.readers, home: home.url, settings: BrimlineSettings()).first)
        #expect(folder.claudeReport != nil)

        var settings = BrimlineSettings()
        settings.setUnread(true, account: folder)
        #expect(settings.unreadAccounts == [folder.id, "claude:report:work@example.org"])
        #expect(settings.closedReports == ["work@example.org"])
        // Marked: the report is linked to no folder, and no account of its own is added.
        let marked = Providers.discover(readers: service.readers, home: home.url, settings: settings)
        #expect(marked.count == 1 && marked[0].claudeReport == nil)

        // The folder's .claude.json loses its address for a while: the report comes as an account of its own,
        // with an id of its address, already marked, so it is not opened.
        try home.write(".claude-work/.claude.json", #"{"numStartups":3}"#)
        let lost = Providers.discover(readers: service.readers, home: home.url, settings: settings)
        let reportOnly = try #require(lost.first { $0.readsReportOnly })
        #expect(reportOnly.id == Account.claudeReportID("work@example.org"))
        #expect(!settings.mayRead(reportOnly))
        let usage = await service.refresh(accounts: lost, settings: settings, previous: nil, now: now)
        #expect(usage.accounts.allSatisfy { $0.fetchedAt == nil && $0.observedAt == nil })

        // Turned on again: both marks go.
        settings.setUnread(false, account: folder)
        #expect(settings.unreadAccounts.isEmpty)

        // A folder marked before reports existed gets the mark of its address.
        var legacy = BrimlineSettings()
        legacy.unreadAccounts = [folder.id]
        legacy.closeReportsOfUnreadAccounts([folder])
        #expect(legacy.closedReports == ["work@example.org"])
        // The id of a report only account does not depend on the folder of the reports.
        #expect(Account.claudeReportOnly(email: "x@example.com", file: "/a/x@example.com.json").id
                == Account.claudeReportOnly(email: "x@example.com", file: "/b/x@example.com.json").id)
    }
}
