import Foundation
import Testing
@testable import BrimlineCore

/// The Claude Code reports: what is taken out of the status line JSON and of stream-json, how two inputs merge,
/// what a report gives once read (reset passed, week never seen, age), the safe reading of the file, and what
/// the reader and the JSON for agents make of it.
@Suite("Claude Code reports")
struct ClaudeReportTests {
    let now = date("2026-10-28T00:00:00Z")
    var epoch: Int { Int(now.timeIntervalSince1970) }

    func statusline(_ rateLimits: String) -> Data {
        Data(#"{"model":{"display_name":"Opus"},"session_id":"s","rate_limits":\#(rateLimits)}"#.utf8)
    }

    func event(_ windows: String) -> String {
        #"{"type":"rate_limit_event","rate_limit_info":{"status":"allowed","resetsAt":\#(epoch + 3600),"rateLimitType":"five_hour","unifiedWindows":\#(windows)},"uuid":"u","session_id":"s"}"#
    }

    func observed(_ extraction: ClaudeCodeExtraction) -> ClaudeCodeObservation? {
        if case .observed(let o) = extraction { return o }
        return nil
    }

    // MARK: The status line

    @Test("The status line gives used_percentage from 0 to 100 and resets_at in Unix seconds, window by window")
    func statuslineWindows() throws {
        let data = statusline(#"{"five_hour":{"used_percentage":23.5,"resets_at":\#(epoch + 3600)},"seven_day":{"used_percentage":41.2,"resets_at":\#(epoch + 86400)},"spend_limit":{"used_percentage":62.8,"resets_at":\#(epoch + 999)}}"#)
        let o = try #require(observed(ClaudeCodeReportParser.parseStatusline(data, now: now)))
        #expect(o.source == .statusline)
        #expect(o.fiveHour == ClaudeCodeWindow(percent: 23.5, resetsAt: now.addingTimeInterval(3600)))
        #expect(o.sevenDay == ClaudeCodeWindow(percent: 41.2, resetsAt: now.addingTimeInterval(86400)))
    }

    @Test("No rate_limits, or only a spend limit, gives nothing; a window not in the documented form is a format change")
    func statuslineEdges() {
        #expect(ClaudeCodeReportParser.parseStatusline(Data(#"{"model":{}}"#.utf8), now: now) == .nothing)
        #expect(ClaudeCodeReportParser.parseStatusline(Data("not json".utf8), now: now) == .nothing)
        #expect(ClaudeCodeReportParser.parseStatusline(statusline(#"{"spend_limit":{"used_percentage":5}}"#), now: now) == .nothing)
        #expect(ClaudeCodeReportParser.parseStatusline(statusline("[]"), now: now) == .formatChanged(.statusline))
        #expect(ClaudeCodeReportParser.parseStatusline(statusline(#"{"five_hour":{"used_percentage":"23"}}"#), now: now) == .formatChanged(.statusline))
        #expect(ClaudeCodeReportParser.parseStatusline(statusline(#"{"five_hour":{"used_percentage":-1}}"#), now: now) == .formatChanged(.statusline))
        // Milliseconds instead of seconds: refused, never read as a date far in the future.
        #expect(ClaudeCodeReportParser.parseStatusline(statusline(#"{"five_hour":{"used_percentage":3,"resets_at":\#(epoch)000}}"#), now: now) == .formatChanged(.statusline))
        // No reset time is fine; more than 100 % is held at 100.
        let o = observed(ClaudeCodeReportParser.parseStatusline(statusline(#"{"five_hour":{"used_percentage":130}}"#), now: now))
        #expect(o?.fiveHour == ClaudeCodeWindow(percent: 100, resetsAt: nil))
    }

    // MARK: stream-json

    @Test("A rate_limit_event gives unifiedWindows as fractions; other lines, and the words in a text, are ignored")
    func streamEvent() throws {
        let lines = [
            #"{"type":"system","subtype":"init","session_id":"s"}"#,
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"{\"type\":\"rate_limit_event\",\"rate_limit_info\":{\"unifiedWindows\":{\"five_hour\":{\"utilization\":0.99}}}}"}]}}"#,
            event(#"{"five_hour":{"utilization":0.39,"resetsAt":\#(epoch + 3600),"status":"allowed"},"seven_day":{"utilization":0.16,"resetsAt":\#(epoch + 86400)}}"#),
            #"{"type":"result","result":"done"}"#,
        ]
        let o = try #require(observed(ClaudeCodeReportParser.parseStream(lines: lines, now: now)))
        #expect(o.source == .streamJSON)
        #expect(o.fiveHour == ClaudeCodeWindow(percent: 39, resetsAt: now.addingTimeInterval(3600)))
        #expect(o.sevenDay == ClaudeCodeWindow(percent: 16, resetsAt: now.addingTimeInterval(86400)))
    }

    @Test("The last event wins window by window: a week missing from the last one stays from the one before")
    func streamLastWins() throws {
        let lines = [
            event(#"{"five_hour":{"utilization":0.10},"seven_day":{"utilization":0.20}}"#),
            event(#"{"five_hour":{"utilization":0.30}}"#),
        ]
        let o = try #require(observed(ClaudeCodeReportParser.parseStream(lines: lines, now: now)))
        #expect(o.fiveHour?.percent == 30)
        #expect(o.sevenDay?.percent == 20)
    }

    @Test("Without unifiedWindows the format changed; one readable event is enough; no event is nothing")
    func streamFormatChanged() {
        let bare = #"{"type":"rate_limit_event","rate_limit_info":{"status":"allowed","utilization":0.5,"rateLimitType":"five_hour"}}"#
        #expect(ClaudeCodeReportParser.parseStream(lines: [bare], now: now) == .formatChanged(.streamJSON))
        // A percentage where a fraction is expected: the unit changed.
        #expect(ClaudeCodeReportParser.parseStream(lines: [event(#"{"five_hour":{"utilization":39}}"#)], now: now) == .formatChanged(.streamJSON))
        #expect(ClaudeCodeReportParser.parseStream(lines: [event(#"{"five_hour":{"utilization":"0.3"}}"#)], now: now) == .formatChanged(.streamJSON))
        let mixed = ClaudeCodeReportParser.parseStream(lines: [bare, event(#"{"five_hour":{"utilization":0.5}}"#)], now: now)
        #expect(observed(mixed)?.fiveHour?.percent == 50)
        #expect(ClaudeCodeReportParser.parseStream(lines: [#"{"type":"result"}"#], now: now) == .nothing)
        // An event with neither window (another kind of limit only) records nothing.
        #expect(ClaudeCodeReportParser.parseStream(lines: [event(#"{"overage":{"utilization":0.5}}"#)], now: now) == .nothing)
        // A limit passed a little is held at 100 %.
        #expect(observed(ClaudeCodeReportParser.parseStream(lines: [event(#"{"five_hour":{"utilization":1.02}}"#)], now: now))?.fiveHour?.percent == 100)
    }

    @Test("Only a line whose type is rate_limit_event is decoded, blanks around its colon allowed")
    func streamEventType() throws {
        for line in [#"{"type":"rate_limit_event"}"#, #"{"session_id":"s", "type" : "rate_limit_event"}"#,
                     "{\"type\":\t\"rate_limit_event\"}"] {
            #expect(ClaudeCodeReportParser.namesEventType(Data(line.utf8)), "\(line)")
        }
        for line in [#"{"type":"assistant","text":"{\"type\":\"rate_limit_event\"}"}"#, #"{"type":"assistant","text":"rate_limit_event"}"#,
                     #"{"kind":"rate_limit_event"}"#, #"{"type":"rate_limit_events"}"#, #"{"subtype":"rate_limit_event"}"#,
                     #""type""rate_limit_event""#, #"rate_limit_event"#] {
            #expect(!ClaudeCodeReportParser.namesEventType(Data(line.utf8)), "\(line)")
        }
        let spaced = event(#"{"five_hour":{"utilization":0.5}}"#).replacingOccurrences(of: #""type":"#, with: #""type": "#)
        #expect(observed(ClaudeCodeReportParser.parseStream(lines: [spaced], now: now))?.fiveHour?.percent == 50)
    }

    @Test("A line longer than 64 KiB is never parsed")
    func streamLineBound() {
        let padding = String(repeating: "x", count: ClaudeCodeReportParser.maxLineBytes)
        let long = event(#"{"five_hour":{"utilization":0.5}}"#).replacingOccurrences(of: #""uuid":"u""#, with: #""uuid":"\#(padding)""#)
        #expect(ClaudeCodeReportParser.parseStream(lines: [long], now: now) == .nothing)
    }

    // MARK: Merging and reading back

    @Test("A window given replaces the one kept, a window missing stays with the time it was seen")
    func merge() throws {
        let first = try #require(ClaudeCodeReport.first(email: "someone@example.com", extraction: .observed(ClaudeCodeObservation(
            source: .streamJSON, fiveHour: ClaudeCodeWindow(percent: 10, resetsAt: now.addingTimeInterval(3600)),
            sevenDay: ClaudeCodeWindow(percent: 20, resetsAt: now.addingTimeInterval(86400)))), at: now))
        let later = now.addingTimeInterval(600)
        let second = first.merged(with: .observed(ClaudeCodeObservation(
            source: .statusline, fiveHour: ClaudeCodeWindow(percent: 15, resetsAt: now.addingTimeInterval(3600)), sevenDay: nil)), at: later)
        #expect(second.source == .statusline)
        #expect(second.observedAt == later)
        #expect(second.fiveHour == .init(percent: 15, resetsAt: now.addingTimeInterval(3600), observedAt: later))
        #expect(second.sevenDay == .init(percent: 20, resetsAt: now.addingTimeInterval(86400), observedAt: now))
        // The age of the numbers is the oldest window still running.
        #expect(second.numbersObservedAt(at: later) == now)

        let changed = second.merged(with: .formatChanged(.streamJSON), at: later)
        #expect(changed.status == .formatChanged)
        #expect(changed.fiveHour == second.fiveHour && changed.sevenDay == second.sevenDay)
        #expect(changed.merged(with: .observed(ClaudeCodeObservation(source: .streamJSON, fiveHour: .init(percent: 1, resetsAt: nil), sevenDay: nil)), at: later).status == .ok)
        #expect(second.merged(with: .nothing, at: later) == second)
        #expect(ClaudeCodeReport.first(email: "someone@example.com", extraction: .nothing, at: now) == nil)
    }

    @Test("A reset time passed is 0 % with no reset time; a week never seen is not there")
    func limitsAtNow() {
        var report = ClaudeCodeReport(email: "someone@example.com", source: .statusline, observedAt: now,
                                      fiveHour: .init(percent: 80, resetsAt: now.addingTimeInterval(3600), observedAt: now))
        #expect(report.limits(at: now) == [UsageLimit(kind: .session, percent: 80, resetsAt: now.addingTimeInterval(3600))])
        #expect(report.limits(at: now.addingTimeInterval(3601)) == [UsageLimit(kind: .session, percent: 0, resetsAt: nil)])
        report.sevenDay = .init(percent: 30, resetsAt: now.addingTimeInterval(-60), observedAt: now.addingTimeInterval(-7 * 86400))
        #expect(report.limits(at: now).last == UsageLimit(kind: .weekly, percent: 0, resetsAt: nil))
        // A week that has reset does not make the numbers look a week old.
        #expect(report.numbersObservedAt(at: now) == now)
    }

    // MARK: The files

    @Test("Written atomically, file 0600 in a folder 0700, with nothing but the address, the source, the times and the windows")
    func storeWrites() throws {
        let home = try TemporaryHome()
        let store = ClaudeReportStore(directory: home.url.appendingPathComponent("reports"))
        #expect(try store.record(.nothing, email: "someone@example.com", now: now) == nil)
        #expect(!FileManager.default.fileExists(atPath: store.directory.path))

        let written = try #require(try store.record(ClaudeCodeReportParser.parseStatusline(
            statusline(#"{"five_hour":{"used_percentage":12,"resets_at":\#(epoch + 600)}}"#), now: now), email: "someone@example.com", now: now))
        #expect(try store.load("someone@example.com") == written)
        let file = store.file(for: "someone@example.com")
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        #expect((attributes[.posixPermissions] as? Int) == 0o600)
        let folder = try FileManager.default.attributesOfItem(atPath: store.directory.path)
        #expect((folder[.posixPermissions] as? Int) == 0o700)
        let object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        #expect(Set(object.keys) == ["schema_version", "email", "source", "observed_at", "status", "five_hour"])
        let window = try #require(object["five_hour"] as? [String: Any])
        #expect(Set(window.keys) == ["percent", "resets_at", "observed_at"])
        #expect(store.list().map(\.email) == ["someone@example.com"])
    }

    @Test("A report is read without following a link, 64 KiB at most, and only if its address is the file's")
    func storeReadsSafely() throws {
        let home = try TemporaryHome()
        let store = ClaudeReportStore(directory: home.url.appendingPathComponent("reports"))
        try store.record(.observed(ClaudeCodeObservation(source: .statusline, fiveHour: .init(percent: 5, resetsAt: nil), sevenDay: nil)),
                         email: "real@example.com", now: now)
        let fm = FileManager.default
        try fm.createSymbolicLink(at: store.file(for: "link@example.com"), withDestinationURL: store.file(for: "real@example.com"))
        #expect(throws: ClaudeReportStore.Failure.file(.notRegularFile)) { try store.load("link@example.com") }
        try fm.copyItem(at: store.file(for: "real@example.com"), to: store.file(for: "other@example.com"))
        #expect(throws: ClaudeReportStore.Failure.notAReport) { try store.load("other@example.com") }
        try Data(repeating: 0x20, count: ClaudeCodeReport.maxBytes + 1).write(to: store.file(for: "big@example.com"))
        #expect(throws: ClaudeReportStore.Failure.file(.tooLarge)) { try store.load("big@example.com") }
        // Listed: plain addresses only, regular files only, no temporary or hidden file, no link.
        try Data().write(to: store.directory.appendingPathComponent(".real@example.com.json.1234.tmp"))
        try Data().write(to: store.directory.appendingPathComponent("Not An Address.json"))
        #expect(store.list().map(\.email) == ["big@example.com", "other@example.com", "real@example.com"])

        // A folder that is a link is not used, for reading or for writing.
        let linked = ClaudeReportStore(directory: home.url.appendingPathComponent("linked"))
        try fm.createSymbolicLink(at: linked.directory, withDestinationURL: store.directory)
        #expect(linked.list().isEmpty)
        #expect(throws: ClaudeReportStore.Failure.unsafeFolder) { try linked.load("real@example.com") }
        #expect(throws: ClaudeReportStore.Failure.unsafeFolder) {
            try linked.record(.formatChanged(.statusline), email: "real@example.com", now: now)
        }
    }

    @Test("Addresses: lower case, plain, usable as a file name")
    func emails() throws {
        #expect(ClaudeReportEmail.normalize(" Someone@Example.COM ") == "someone@example.com")
        #expect(ClaudeReportEmail.normalize("first.last+tag@sub.example.org") == "first.last+tag@sub.example.org")
        for bad in ["", "someone", "@example.com", "someone@example", "a/b@example.com", ".dot@example.com",
                    "a@b@example.com", "some one@example.com", "someone@exa_mple.com", "someone@example..com"] {
            #expect(ClaudeReportEmail.normalize(bad) == nil, "\(bad)")
        }
        let home = try TemporaryHome()
        try home.write(".claude.json", claudeJSON(email: "Main@Example.com"))
        try home.write(".claude-work/.claude.json", claudeJSON(email: "work@example.org"))
        #expect(ClaudeReportEmail.auto(environment: [:], home: home.url) == "main@example.com")
        #expect(ClaudeReportEmail.auto(environment: ["CLAUDE_CONFIG_DIR": home.path(".claude-work")], home: home.url) == "work@example.org")
        #expect(ClaudeReportEmail.auto(environment: ["CLAUDE_CONFIG_DIR": home.path(".claude")], home: home.url) == "main@example.com")
        #expect(ClaudeReportEmail.auto(environment: ["CLAUDE_CONFIG_DIR": home.path("nowhere")], home: home.url) == nil)
    }

    // MARK: The reader and what agents see

    func reportsHome(_ windows: ClaudeCodeObservation, email: String = "someone@example.com", at time: Date? = nil) throws -> TemporaryHome {
        let home = try TemporaryHome()
        try ClaudeReportStore(directory: BrimlinePaths(home: home.url).claudeReportsDirectory)
            .record(.observed(windows), email: email, now: time ?? now)
        return home
    }

    @Test("An address with a report only is an account of its own, read from the report, its week unknown")
    func reportOnlyAccount() async throws {
        let home = try reportsHome(ClaudeCodeObservation(source: .statusline, fiveHour: .init(percent: 42, resetsAt: now.addingTimeInterval(3600)), sevenDay: nil),
                                   at: now.addingTimeInterval(-300))
        let credentials = FakeCredentials([:])
        let http = FakeHTTP([:])
        let service = UsageService(credentials: credentials, http: http)
        let accounts = Providers.discover(readers: service.readers, home: home.url, settings: BrimlineSettings())
        let account = try #require(accounts.first)
        #expect(accounts.count == 1)
        #expect(account.readsReportOnly)
        #expect(account.email == "someone@example.com")
        #expect(account.keychainService == nil)

        let usage = await service.refresh(account: account, settings: BrimlineSettings(), previous: nil, now: now)
        #expect(usage.status == .ok)
        #expect(usage.limits == [UsageLimit(kind: .session, percent: 42, resetsAt: now.addingTimeInterval(3600))])
        #expect(usage.observedAt == now.addingTimeInterval(-300))
        #expect(usage.fetchedAt == usage.observedAt)
        #expect(usage.weekUnknown)
        #expect(!usage.hasNoGlobalWeeklyLimit)
        #expect(credentials.reads.isEmpty)
        #expect(http.requests.isEmpty)

        let agent = AgentAccount(usage, settings: BrimlineSettings(), now: now, home: home.url)
        #expect(agent.source == "report")
        #expect(agent.folder == nil)
        #expect(agent.observedAt == "2026-10-27T23:55:00Z")
        #expect(agent.ageSeconds == 300)
        #expect(!agent.noGlobalWeeklyLimit)
        let json = AgentJSON.encode(agent)
        #expect(json.contains(#""observed_at" : "2026-10-27T23:55:00Z""#))

        // "Do not read": the report is not opened, the account stays as it was.
        var settings = BrimlineSettings()
        settings.unreadAccounts = [account.id]
        let unread = await service.refresh(account: account, settings: settings, previous: nil, now: now)
        #expect(unread.status == .pending)
        #expect(unread.fetchedAt == nil)

        let strings = Strings(.en)
        let lines = StatusText.lines(for: usage, among: [usage], settings: BrimlineSettings(), strings: strings,
                                     time: TimeFormatter(language: .en, timeZone: utc), now: now, home: home.url, refreshMinutes: 5)
        #expect(lines.contains("  " + strings.weekUnknown))
        #expect(lines.contains("  Claude Code report, 5 min ago"))
        #expect(strings.statuslineSummary(usage.limits, now: now) == "5 h 42%")
        #expect(Strings(.fr).statuslineSummary(usage.limits + [UsageLimit(kind: .weekly, percent: 7.4, resetsAt: nil)], now: now) == "5 h 42 % · Semaine 7 %")
    }

    @Test("A report Claude Code wrote in a format Brimline does not know is format_changed, never a number")
    func formatChangedReport() async throws {
        let home = try TemporaryHome()
        try ClaudeReportStore(directory: BrimlinePaths(home: home.url).claudeReportsDirectory)
            .record(.formatChanged(.streamJSON), email: "someone@example.com", now: now)
        let service = UsageService(credentials: FakeCredentials([:]), http: FakeHTTP([:]))
        let account = try #require(Providers.discover(readers: service.readers, home: home.url, settings: BrimlineSettings()).first)
        let usage = await service.refresh(account: account, settings: BrimlineSettings(), previous: nil, now: now)
        #expect(usage.status == .formatChanged)
        #expect(usage.limits.isEmpty)
    }

    @Test("A folder with its Keychain item keeps the direct reading; an expired session falls back on the report")
    func folderFallback() async throws {
        let home = try reportsHome(ClaudeCodeObservation(source: .streamJSON, fiveHour: .init(percent: 64, resetsAt: now.addingTimeInterval(3600)),
                                                         sevenDay: .init(percent: 12, resetsAt: now.addingTimeInterval(86400))),
                                   email: "work@example.org", at: now.addingTimeInterval(-60))
        try home.write(".claude-work/.claude.json", claudeJSON(email: "Work@Example.org"))
        let service = home.path(".claude-work")
        let keychain = KeychainServiceName.forConfigDir(service, isDefault: false)
        let answer = #"{"five_hour":{"utilization":30,"resets_at":"2026-10-28T02:00:00Z"}}"#

        // A session that reads: the answer of Anthropic, never the report.
        let fresh = UsageService(credentials: FakeCredentials([keychain: .success(ClaudeCredential(accessToken: "tok", expiresAt: nil))]),
                                 http: FakeHTTP(["tok": (200, Data(answer.utf8), [:])]))
        let accounts = Providers.discover(readers: fresh.readers, home: home.url, settings: BrimlineSettings())
        #expect(accounts.count == 1)                         // the report is linked to the folder, not listed twice
        let account = try #require(accounts.first)
        #expect(account.claudeReport != nil && !account.readsReportOnly)
        let direct = await fresh.refresh(account: account, settings: BrimlineSettings(), previous: nil, now: now)
        #expect(direct.status == .ok)
        #expect(direct.observedAt == nil)
        #expect(direct.sessionLimit?.percent == 30)
        #expect(direct.hasNoGlobalWeeklyLimit)

        // Expired: the report, newer than nothing.
        let expired = UsageService(credentials: FakeCredentials([keychain: .success(ClaudeCredential(accessToken: "tok", expiresAt: now.addingTimeInterval(-1)))]),
                                   http: FakeHTTP([:]))
        let fallback = await expired.refresh(account: account, settings: BrimlineSettings(), previous: nil, now: now)
        #expect(fallback.status == .ok)
        #expect(fallback.observedAt == now.addingTimeInterval(-60))
        #expect(fallback.sessionLimit?.percent == 64)
        #expect(fallback.weeklyLimit?.percent == 12)

        // Expired, with numbers from Anthropic newer than the report: they stay, the account says expired.
        var previous = direct
        previous.fetchedAt = now.addingTimeInterval(-30)
        let kept = await expired.refresh(account: account, settings: BrimlineSettings(), previous: previous, now: now)
        #expect(kept.status == .expired)
        #expect(kept.sessionLimit?.percent == 30)
        #expect(kept.observedAt == nil)

        // Expired, with numbers from Anthropic older than the report: the report wins.
        var older = direct
        older.fetchedAt = now.addingTimeInterval(-600)
        let newer = await expired.refresh(account: account, settings: BrimlineSettings(), previous: older, now: now)
        #expect(newer.status == .ok)
        #expect(newer.observedAt == now.addingTimeInterval(-60))
        #expect(newer.sessionLimit?.percent == 64)
        #expect(newer.weeklyLimit?.percent == 12)

        // No Keychain item at all: the report too.
        let missing = UsageService(credentials: FakeCredentials([:]), http: FakeHTTP([:]))
        #expect(await missing.refresh(account: account, settings: BrimlineSettings(), previous: nil, now: now).observedAt != nil)
    }
}
