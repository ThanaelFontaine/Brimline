import Foundation
import Testing
@testable import BrimlineCore

@Suite("Agents: provider, windows, source")
struct AgentProviderTests {
    static let now = date("2026-10-27T10:00:00Z")
    static let homeURL = URL(fileURLWithPath: "/opt/box/you")
    static let later = date("2026-10-28T10:00:00Z")

    static func other(_ provider: Provider, _ name: String) -> Account {
        Account(provider: provider, source: "/opt/box/you/.\(name)/auth.json", email: nil, organization: nil,
                seatTier: nil, keychainService: nil)
    }

    static var snapshot: UsageSnapshot {
        let claude = AccountUsage(account: account("you@example.com", dir: "/opt/box/you/.claude"), status: .ok,
                                  limits: [UsageLimit(kind: .session, percent: 60, resetsAt: later),
                                           UsageLimit(kind: .weekly, percent: 40, resetsAt: later)], fetchedAt: now)
        let chatgpt = AccountUsage(account: other(.chatgpt, "codex"), status: .ok,
                                   limits: [UsageLimit(kind: .session, percent: 10, resetsAt: later, windowSeconds: 18000),
                                            UsageLimit(kind: .weekly, percent: 20, resetsAt: later, windowSeconds: 604800)], fetchedAt: now)
        let grokA = AccountUsage(account: other(.grok, "grok-a"), status: .ok,
                                 limits: [UsageLimit(kind: .period, percent: 70, resetsAt: later, windowSeconds: 604800, label: "Credits")], fetchedAt: now)
        let grokB = AccountUsage(account: other(.grok, "grok-b"), status: .ok,
                                 limits: [UsageLimit(kind: .period, percent: 30, resetsAt: later)], fetchedAt: now)
        let gemini = AccountUsage(account: other(.gemini, "gemini"), status: .notReadable, reason: .consumerPlan)
        return UsageSnapshot(generatedAt: now, accounts: [claude, chatgpt, grokA, grokB, gemini])
    }

    func server(_ snapshot: UsageSnapshot? = snapshot, settings: BrimlineSettings = allOn) -> MCPServer {
        MCPServer(version: "0.0.0", load: { (snapshot, settings) }, now: { Self.now }, home: Self.homeURL)
    }

    func call(_ server: MCPServer, _ tool: String, _ arguments: String = "{}") throws -> [String: Any] {
        let line = try #require(server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"\#(tool)","arguments":\#(arguments)}}"#))
        let answer = try #require(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        return try #require(answer["result"] as? [String: Any])
    }

    func data(_ result: [String: Any]) throws -> [String: Any] {
        #expect(result["isError"] as? Bool == false)
        return try #require(result["structuredContent"] as? [String: Any])
    }

    func errorText(_ result: [String: Any]) -> String? {
        #expect(result["isError"] as? Bool == true)
        return (result["content"] as? [[String: Any]])?.first?["text"] as? String
    }

    @Test("list_accounts says the provider, the source from the home folder, and why an account is not readable")
    func list() throws {
        let accounts = try #require(try data(try call(server(), "list_accounts"))["accounts"] as? [[String: Any]])
        #expect(accounts.map { $0["provider"] as? String } == ["claude", "chatgpt", "grok", "grok", "gemini"])
        #expect(accounts[0]["source"] as? String == "~/.claude")
        #expect(accounts[0]["folder"] as? String == "/opt/box/you/.claude")
        #expect(accounts[1]["source"] as? String == "~/.codex/auth.json")
        #expect(accounts[1]["folder"] is NSNull)
        #expect(accounts[4]["status"] as? String == "not_readable")
        #expect(accounts[4]["reason"] as? String == "consumer_plan")
        #expect(accounts[0]["reason"] is NSNull)
        for entry in accounts {
            #expect(!(entry["source"] as? String ?? "").contains("/opt/box"))
        }
    }

    @Test("get_usage with a provider keeps that provider's accounts; the limits carry their window and label")
    func usageByProvider() throws {
        let grok = try #require(try data(try call(server(), "get_usage", #"{"provider":"grok"}"#))["accounts"] as? [[String: Any]])
        #expect(grok.count == 2)
        let limit = try #require((grok[0]["limits"] as? [[String: Any]])?.first)
        #expect(limit["kind"] as? String == "period")
        #expect(limit["window_seconds"] as? Int == 604800)
        #expect(limit["label"] as? String == "Credits")
        #expect((grok[1]["limits"] as? [[String: Any]])?.first?["window_seconds"] is NSNull)

        let all = try #require(try data(try call(server(), "get_usage"))["accounts"] as? [[String: Any]])
        #expect(all.count == 5)

        #expect(errorText(try call(server(), "get_usage", #"{"provider":"mistral"}"#))?.contains("Unknown provider mistral") == true)
    }

    @Test("get_usage for a provider that is off says so")
    func usageOff() throws {
        var settings = BrimlineSettings()
        settings.enabledProviders = ["claude"]
        let empty = UsageSnapshot(generatedAt: Self.now, accounts: [Self.snapshot.accounts[0]])
        let result = try data(try call(server(empty, settings: settings), "get_usage", #"{"provider":"cursor"}"#))
        #expect((result["accounts"] as? [Any])?.isEmpty == true)
        #expect((result["note"] as? String)?.contains("brimline providers enable cursor") == true)
    }

    @Test("best_account ranks Claude by default, and the provider asked otherwise")
    func best() throws {
        let byDefault = try data(try call(server(), "best_account"))
        #expect(byDefault["provider"] as? String == "claude")
        #expect((byDefault["ranking"] as? [[String: Any]])?.map { $0["provider"] as? String } == ["claude"])

        let grok = try data(try call(server(), "best_account", #"{"provider":"grok"}"#))
        let best = try #require(grok["best"] as? [String: Any])
        #expect(best["source"] as? String == "~/.grok-b/auth.json")
        #expect(best["headroom_percent"] as? Double == 70)
        #expect((grok["ranking"] as? [Any])?.count == 2)

        let period = try data(try call(server(), "best_account", #"{"provider":"grok","window":"period"}"#))
        #expect((period["best"] as? [String: Any])?["headroom_percent"] as? Double == 70)

        let chatgpt = try data(try call(server(), "best_account", #"{"provider":"chatgpt","window":"week"}"#))
        let chatgptBest = try #require(chatgpt["best"] as? [String: Any])
        #expect(chatgptBest["headroom_percent"] as? Double == 80)
        #expect((chatgptBest["binding_limit"] as? [String: Any])?["kind"] as? String == "weekly")
    }

    @Test("A window that does not exist for the provider is a clear error")
    func windowMissing() throws {
        let text = errorText(try call(server(), "best_account", #"{"provider":"grok","window":"session"}"#))
        #expect(text == "The window session does not exist for grok: use any or period.")
        #expect(errorText(try call(server(), "best_account", #"{"provider":"claude","window":"day"}"#))?.contains("does not exist for claude") == true)
        #expect(errorText(try call(server(), "best_account", #"{"provider":"cursor","window":"week"}"#))?.contains("use any or month") == true)
        #expect(errorText(try call(server(), "best_account", #"{"window":"fortnight"}"#))?.contains("Unknown window fortnight") == true)
        #expect(errorText(try call(server(), "best_account", #"{"provider":"mistral"}"#))?.contains("Unknown provider mistral") == true)
    }

    @Test("Accounts that cannot be read are not ranked; a provider that is off says so")
    func notRanked() throws {
        let gemini = try data(try call(server(), "best_account", #"{"provider":"gemini"}"#))
        #expect(gemini["best"] is NSNull)
        #expect((gemini["note"] as? String) == "No gemini account has usage numbers yet.")

        var settings = BrimlineSettings()
        settings.enabledProviders = ["claude"]
        let off = try data(try call(server(settings: settings), "best_account", #"{"provider":"gemini"}"#))
        #expect((off["note"] as? String)?.contains("gemini is off in Brimline") == true)
    }

    @Test("The tools list names the providers and the windows")
    func schema() throws {
        let tools = MCPServer.tools
        let best = try #require(tools.first { $0["name"] as? String == "best_account" })
        let properties = try #require((best["inputSchema"] as? [String: Any])?["properties"] as? [String: Any])
        #expect((properties["provider"] as? [String: Any])?["enum"] as? [String] == ["claude", "chatgpt", "gemini", "grok", "cursor"])
        #expect((properties["window"] as? [String: Any])?["enum"] as? [String] == ["any", "session", "week", "day", "month", "period"])
        let usage = try #require(tools.first { $0["name"] as? String == "get_usage" })
        #expect(((usage["inputSchema"] as? [String: Any])?["properties"] as? [String: Any])?["provider"] != nil)
    }

    @Test("A cache of the previous schema is not read: the agent is told there is no data yet")
    func oldCache() throws {
        let home = try TemporaryHome()
        try home.write("usage.json", #"{"schemaVersion":1,"generatedAt":"2026-10-26T10:00:00Z","accounts":[]}"#)
        let file = home.url.appendingPathComponent("usage.json")
        #expect(UsageCache(file: file).load() == nil)
        let server = MCPServer(version: "0.0.0", load: { (UsageCache(file: file).load(), BrimlineSettings()) }, now: { Self.now })
        let result = try call(server, "get_usage")
        #expect(errorText(result)?.contains("No usage data yet") == true)
    }

    @Test("Every window of each provider is one the ranking understands")
    func windowsPerProvider() {
        for provider in Provider.allCases {
            #expect(provider.windows.first == .any)
            #expect(provider.windows.contains(.any))
        }
        #expect(Provider.claude.windows == [.any, .session, .week])
        #expect(Provider.gemini.windows == [.any, .day])
        #expect(Provider.cursor.windows == [.any, .month])
    }

    @Test("Ranking looks at the limits of the window asked")
    func rankingWindows() {
        let usage = AccountUsage(account: Self.other(.cursor, "cursor"), status: .ok, limits: [
            UsageLimit(kind: .monthly, percent: 30, resetsAt: Self.later),
            UsageLimit(kind: .model, model: "auto", percent: 90, resetsAt: Self.later),
            UsageLimit(kind: .daily, percent: 50, resetsAt: Self.later),
        ], fetchedAt: Self.now)
        #expect(Ranking.rank([usage], window: .month, model: nil, now: Self.now).first?.headroom == 70)
        #expect(Ranking.rank([usage], window: .day, model: nil, now: Self.now).first?.headroom == 50)
        #expect(Ranking.rank([usage], window: .any, model: nil, now: Self.now).first?.headroom == 50)
        #expect(Ranking.rank([usage], window: .month, model: "Auto", now: Self.now).first?.headroom == 10)
    }
}
