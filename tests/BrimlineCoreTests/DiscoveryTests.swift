import Foundation
import Testing
@testable import BrimlineCore

@Suite("Account discovery and Keychain service names")
struct DiscoveryTests {
    @Test("The Keychain service of a folder is the base name plus 8 hex characters of SHA-256 of its path")
    func serviceNameHash() {
        // Expected values computed with: printf '%s' <path> | shasum -a 256 | cut -c1-8
        #expect(KeychainServiceName.hashPrefix(of: "/opt/team/.claude-work") == "222bfaf5")
        #expect(KeychainServiceName.forConfigDir("/opt/team/.claude-work", isDefault: false)
                == "Claude Code-credentials-222bfaf5")
        #expect(KeychainServiceName.forConfigDir("/Volumes/Data/claude-config/", isDefault: false)
                == "Claude Code-credentials-3239adac")
        #expect(KeychainServiceName.forConfigDir("/anything", isDefault: true) == "Claude Code-credentials")
    }

    @Test("Paths are normalized: no trailing slash, dots resolved")
    func normalize() {
        #expect(KeychainServiceName.normalize("/opt/team/.claude-work/") == "/opt/team/.claude-work")
        #expect(KeychainServiceName.normalize("/opt/team/x/../.claude-work") == "/opt/team/.claude-work")
    }

    @Test("Finds ~/.claude, then each ~/.claude-* folder with a .claude.json, then folders added by hand")
    func discovery() throws {
        let home = try TemporaryHome()
        try home.write(".claude.json", claudeJSON(email: "you@example.com", organization: "Example", seat: "max"))
        try home.mkdir(".claude")
        try home.write(".claude-work/.claude.json", claudeJSON(email: "team@example.org", organization: "Team Org"))
        try home.write(".claude-a-first/.claude.json", claudeJSON(email: "first@example.net"))
        try home.mkdir(".claude-empty")                       // no .claude.json: skipped
        try home.write(".claude-file", "not a folder")         // a file: skipped
        try home.write("elsewhere/custom/.claude.json", claudeJSON(email: "custom@example.com"))
        try home.mkdir("elsewhere/not-signed-in")

        let found = AccountDiscovery(home: home.url, extraFolders: [
            home.path("elsewhere/custom") + "/",
            home.path("elsewhere/not-signed-in"),
            home.path(".claude-work"),                       // already found: not listed twice
        ]).discover()

        #expect(found.map(\.email) == ["you@example.com", "first@example.net", "team@example.org",
                                       "custom@example.com", nil])
        let main = try #require(found.first)
        #expect(main.source == home.path(".claude"))
        #expect(main.keychainService! == "Claude Code-credentials")
        #expect(main.organization == "Example")
        #expect(main.seatTier == "max")
        #expect(!main.addedByHand)

        let work = found[2]
        #expect(work.organization == "Team Org")
        #expect(work.keychainService! == "Claude Code-credentials-" + KeychainServiceName.hashPrefix(of: home.path(".claude-work")))

        #expect(found[3].addedByHand)
        #expect(found[3].source == home.path("elsewhere/custom"))
        #expect(found[4].folderName == "not-signed-in")
    }

    @Test("Without ~/.claude.json, ~/.claude/.claude.json is read")
    func defaultFolderFallback() throws {
        let home = try TemporaryHome()
        try home.write(".claude/.claude.json", claudeJSON(email: "you@example.com"))
        let found = AccountDiscovery(home: home.url).discover()
        #expect(found.map(\.email) == ["you@example.com"])
    }

    @Test("A home without Claude Code gives no account")
    func emptyHome() throws {
        let home = try TemporaryHome()
        #expect(AccountDiscovery(home: home.url).discover().isEmpty)
    }

    @Test("A settings file without oauthAccount gives an account without address")
    func noIdentity() throws {
        let home = try TemporaryHome()
        try home.write(".claude-api/.claude.json", #"{"numStartups": 1}"#)
        let found = AccountDiscovery(home: home.url).discover()
        #expect(found.count == 1)
        #expect(found[0].email == nil)
        #expect(found[0].folderName == ".claude-api")
    }

    @Test("Four Claude accounts, one per folder, are found in a stable order with distinct Keychain items")
    func fourClaudeAccounts() throws {
        let home = try TemporaryHome()
        try home.write(".claude.json", claudeJSON(email: "main@example.com"))
        try home.mkdir(".claude")
        try home.write(".claude-one/.claude.json", claudeJSON(email: "one@example.com"))
        try home.write(".claude-two/.claude.json", claudeJSON(email: "two@example.org"))
        try home.write(".claude-three/.claude.json", claudeJSON(email: "three@example.net"))

        let found = AccountDiscovery(home: home.url).discover()

        #expect(found.map(\.email) == ["main@example.com", "one@example.com", "three@example.net", "two@example.org"])
        #expect(Set(found.map(\.source)).count == 4)
        let services = found.compactMap(\.keychainService)
        #expect(services.count == 4)
        #expect(Set(services).count == 4)
        #expect(services.first == "Claude Code-credentials")
        #expect(found.allSatisfy { !$0.addedByHand })
        #expect(AccountDiscovery(home: home.url).discover() == found)   // same order every time
    }

    @Test("Reports merge with the folders by address, whatever the case; an address with no folder becomes its own account")
    func reportsMerge() throws {
        let home = try TemporaryHome()
        try home.write(".claude.json", claudeJSON(email: "Main@Example.com"))
        try home.mkdir(".claude")
        try home.write(".claude-work/.claude.json", claudeJSON(email: "work@example.org"))
        let reports = home.url.appendingPathComponent("reports")
        let store = ClaudeReportStore(directory: reports)
        let window = ClaudeCodeObservation(source: .statusline, fiveHour: ClaudeCodeWindow(percent: 1, resetsAt: nil), sevenDay: nil)
        for email in ["main@example.com", "zeta@example.net", "alpha@example.net"] {
            try store.record(.observed(window), email: email, now: date("2026-10-28T00:00:00Z"))
        }

        let found = AccountDiscovery(home: home.url, reportsDirectory: reports).discover()

        #expect(found.map(\.email) == ["Main@Example.com", "work@example.org", "alpha@example.net", "zeta@example.net"])
        #expect(found[0].claudeReport == store.file(for: "main@example.com").path)
        #expect(found[0].keychainService == "Claude Code-credentials")
        #expect(!found[0].readsReportOnly)
        #expect(found[1].claudeReport == nil)
        #expect(found[2].readsReportOnly && found[3].readsReportOnly)
        #expect(found[2].keychainService == nil)
        #expect(found[2].source == store.file(for: "alpha@example.net").path)
        #expect(Set(found.map(\.id)).count == 4)
        // Without the reports folder, or with none in it, the folders only, as before.
        #expect(AccountDiscovery(home: home.url).discover().count == 2)
        #expect(AccountDiscovery(home: home.url, reportsDirectory: home.url.appendingPathComponent("none")).discover().count == 2)
    }
}
