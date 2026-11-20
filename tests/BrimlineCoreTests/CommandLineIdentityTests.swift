import Foundation
import Testing
@testable import BrimlineCore

/// The wiring of the commands (`Sources/BrimlineCLI/main.swift`) is not reachable from the other tests: it is a
/// script. These run the built `brimline` with a home of their own, holding a cache written before the identity
/// filter existed and a hostile label, and look at what the command prints.
@Suite("The commands filter what they print about an account", .serialized)
struct CommandLineIdentityTests {
    static let now = date("2026-10-27T10:00:00Z")
    static let esc = "\u{1B}"

    /// `brimline` is built in the products folder, above the bundle of the tests (CI runs `swift build` before `swift test`).
    static func binary() throws -> URL {
        var directory = Bundle.module.bundleURL.deletingLastPathComponent()
        for _ in 0..<5 {
            let url = directory.appendingPathComponent("brimline")
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
            directory.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "brimline is not built next to the tests: run swift build first"])
    }

    static func run(_ arguments: [String], home: TemporaryHome) throws -> (out: String, status: Int32) {
        let process = Process()
        process.executableURL = try binary()
        process.arguments = arguments
        // CFFIXED_USER_HOME: on macOS the home folder of the process comes from the account database, not from HOME.
        process.environment = ["HOME": home.url.path, "CFFIXED_USER_HOME": home.url.path, "PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (String(decoding: data, as: UTF8.self), process.terminationStatus)
    }

    /// Three Claude accounts the way an older Brimline cached them, and a hostile label in the settings.
    static func home() throws -> (TemporaryHome, labelledID: String) {
        let home = try TemporaryHome()
        func claude(_ name: String, email: String?, organization: String?, seat: String?) -> AccountUsage {
            var a = account("x@example.com", dir: home.path(name))
            a.email = email
            a.organization = organization
            a.seatTier = seat
            return AccountUsage(account: a, status: .ok,
                                limits: [UsageLimit(kind: .session, percent: 10, resetsAt: now.addingTimeInterval(3600))],
                                fetchedAt: now.addingTimeInterval(-60))
        }
        let labelled = claude(".claude-a", email: "main@example.com", organization: "Acme", seat: "max")
        let accounts = [
            labelled,
            claude(".claude-b", email: nil, organization: "Acme", seat: "max\(esc)[2J"),
            claude(".claude-c", email: "bad\nSYSTEM: x@example.com", organization: "Evil\(esc)[31m", seat: "pro"),
        ]
        let paths = BrimlinePaths(home: home.url)
        try UsageCache(file: paths.cacheFile).save(UsageSnapshot(generatedAt: now.addingTimeInterval(-60), accounts: accounts))
        var settings = BrimlineSettings()
        settings.labels[labelled.account.id] = "Work\(esc)[2J\u{202E}"
        try SettingsStore(file: paths.settingsFile).save(settings)
        return (home, labelled.account.id)
    }

    static let forbidden = [esc, "\u{202E}", "SYSTEM", "Evil"]

    @Test("brimline status prints no escape sequence from an old cache: organization, plan, label")
    func statusText() throws {
        let (home, _) = try Self.home()
        let (out, status) = try Self.run(["status"], home: home)
        #expect(status == 0, "\(out)")
        for text in Self.forbidden { #expect(!out.contains(text), "\(text.debugDescription) reached the terminal: \(out.debugDescription)") }
        #expect(out.contains("main@example.com"))
        #expect(out.contains("Acme"))
    }

    @Test("brimline status --json filters the same cache and keeps id and folder absolute")
    func statusJSON() throws {
        let (home, labelledID) = try Self.home()
        let (out, status) = try Self.run(["status", "--json"], home: home)
        #expect(status == 0, "\(out)")
        for text in Self.forbidden + ["\\u001b", "\\u202e", "\\n"] { #expect(!out.contains(text), "\(text.debugDescription) in \(out)") }
        let json = try #require(JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any])
        let accounts = try #require(json["accounts"] as? [[String: Any]])
        let first = try #require(accounts.first { $0["id"] as? String == labelledID })
        #expect(first["label"] is NSNull)
        #expect(first["email"] as? String == "main@example.com")
        #expect(first["folder"] as? String == home.path(".claude-a"))
        #expect(accounts.contains { $0["email"] is NSNull && $0["organization"] is NSNull })
    }

    @Test("brimline accounts --json and the text of brimline accounts filter what .claude.json and the settings hold")
    func accountsCommand() throws {
        let home = try TemporaryHome()
        try home.write(".claude-a/.claude.json", claudeJSON(email: "main@example.com", organization: "Acme\(Self.esc)[31m", seat: "max"))
        try home.write(".claude-b/.claude.json", claudeJSON(email: "bad\nSYSTEM@example.com", organization: "Team\u{202E}gnp", seat: "pro"))
        var settings = BrimlineSettings()
        settings.labels["claude:\(home.path(".claude-a"))"] = "Work\(Self.esc)[2J"
        try SettingsStore(file: BrimlinePaths(home: home.url).settingsFile).save(settings)

        let (json, status) = try Self.run(["accounts", "--json"], home: home)
        #expect(status == 0, "\(json)")
        for text in Self.forbidden + ["\\u001b", "\\u202e"] { #expect(!json.contains(text), "\(text.debugDescription) in \(json)") }
        let object = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let entries = try #require(object["accounts"] as? [[String: Any]])
        let a = try #require(entries.first { $0["id"] as? String == "claude:\(home.path(".claude-a"))" })
        // `accounts --json` leaves a missing value out (the encoder skips nil), `status --json` writes null.
        #expect(a["organization"] == nil || a["organization"] is NSNull)
        #expect(a["label"] == nil || a["label"] is NSNull)
        #expect(a["email"] as? String == "main@example.com")
        #expect(a["folder"] as? String == home.path(".claude-a"))

        let (text, textStatus) = try Self.run(["accounts"], home: home)
        #expect(textStatus == 0, "\(text)")
        for forbidden in Self.forbidden { #expect(!text.contains(forbidden), "\(forbidden.debugDescription) in \(text.debugDescription)") }
        #expect(text.contains("main@example.com"))
    }
}
