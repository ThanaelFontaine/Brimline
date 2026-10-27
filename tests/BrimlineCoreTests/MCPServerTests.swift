import Foundation
import Testing
@testable import BrimlineCore

@Suite("MCP server over stdio")
struct MCPServerTests {
    static let now = CacheAndRankingTests.now

    func server(snapshot: UsageSnapshot? = UsageSnapshot(generatedAt: now.addingTimeInterval(-90), accounts: CacheAndRankingTests.accounts),
                settings: BrimlineSettings = BrimlineSettings()) -> MCPServer {
        MCPServer(version: "0.0.0", load: { (snapshot, settings) }, now: { Self.now })
    }

    func call(_ server: MCPServer, _ json: String) throws -> [String: Any] {
        let line = try #require(server.handle(line: json))
        #expect(!line.contains("\n"))
        return try #require(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
    }

    func structured(_ answer: [String: Any]) throws -> [String: Any] {
        let result = try #require(answer["result"] as? [String: Any])
        #expect(result["isError"] as? Bool == false)
        let content = try #require(result["content"] as? [[String: Any]])
        #expect(content.first?["type"] as? String == "text")
        return try #require(result["structuredContent"] as? [String: Any])
    }

    @Test("initialize answers with the requested version when supported, and the tools capability")
    func initialize() throws {
        let answer = try call(server(), #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}"#)
        #expect(answer["id"] as? Int == 1)
        let result = try #require(answer["result"] as? [String: Any])
        #expect(result["protocolVersion"] as? String == "2025-06-18")
        #expect((result["capabilities"] as? [String: Any])?["tools"] != nil)
        #expect((result["serverInfo"] as? [String: Any])?["name"] as? String == "brimline")

        let other = try call(server(), #"{"jsonrpc":"2.0","id":"a","method":"initialize","params":{"protocolVersion":"1999-01-01"}}"#)
        #expect((other["result"] as? [String: Any])?["protocolVersion"] as? String == MCPServer.preferredProtocolVersion)
        #expect(other["id"] as? String == "a")
    }

    @Test("Notifications get no answer; ping answers an empty result")
    func notificationsAndPing() throws {
        #expect(server().handle(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
        #expect(server().handle(line: "   ") == nil)
        let ping = try call(server(), #"{"jsonrpc":"2.0","id":7,"method":"ping"}"#)
        #expect((ping["result"] as? [String: Any])?.isEmpty == true)
    }

    @Test("tools/list gives the three read-only tools with their input schemas")
    func toolsList() throws {
        let answer = try call(server(), #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
        let tools = try #require((answer["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        #expect(tools.map { $0["name"] as? String } == ["list_accounts", "get_usage", "best_account"])
        for tool in tools {
            #expect((tool["inputSchema"] as? [String: Any])?["type"] as? String == "object")
            #expect(tool["description"] is String)
        }
    }

    @Test("tools/call list_accounts")
    func listAccounts() throws {
        let data = try structured(try call(server(), #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_accounts","arguments":{}}}"#))
        let accounts = try #require(data["accounts"] as? [[String: Any]])
        #expect(accounts.count == 4)
        #expect(accounts[0]["email"] as? String == "you@example.com")
        #expect(data["age_seconds"] as? Int == 90)
    }

    @Test("tools/call get_usage, for all accounts or one, hidden accounts left out by default")
    func getUsage() throws {
        var settings = BrimlineSettings()
        settings.hiddenAccounts = [CacheAndRankingTests.accounts[3].account.id]
        let s = server(settings: settings)
        let all = try structured(try call(s, #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"get_usage"}}"#))
        let accounts = try #require(all["accounts"] as? [[String: Any]])
        #expect(accounts.count == 3)
        #expect(all["age_seconds"] as? Int == 90)
        let limits = try #require(accounts[0]["limits"] as? [[String: Any]])
        #expect(limits.map { $0["kind"] as? String } == ["session", "weekly", "model"])
        #expect(limits[0]["percent"] as? Double == 34)
        #expect(limits[0]["resets_at"] as? String == "2026-10-25T03:00:00Z")
        #expect(accounts[0]["age_seconds"] as? Int == 60)

        let one = try structured(try call(s, #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"get_usage","arguments":{"account":"TEAM@example.org"}}}"#))
        let team = try #require((one["accounts"] as? [[String: Any]])?.first)
        #expect(team["no_global_weekly_limit"] as? Bool == true)

        let none = try call(s, #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"get_usage","arguments":{"account":"nobody@example.com"}}}"#)
        #expect((none["result"] as? [String: Any])?["isError"] as? Bool == true)
    }

    @Test("tools/call best_account")
    func bestAccount() throws {
        let data = try structured(try call(server(), #"{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"best_account","arguments":{"window":"week","model":"Fable"}}}"#))
        let best = try #require(data["best"] as? [String: Any])
        #expect(best["email"] as? String == "idle@example.net")
        #expect(best["headroom_percent"] as? Double == 80)
        #expect((data["ranking"] as? [Any])?.count == 3)
        #expect(data["model"] as? String == "Fable")

        let bad = try call(server(), #"{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"best_account","arguments":{"window":"month"}}}"#)
        #expect((bad["result"] as? [String: Any])?["isError"] as? Bool == true)
    }

    @Test("Unknown tool and unknown method are JSON-RPC errors; bad JSON is a parse error")
    func errors() throws {
        let tool = try call(server(), #"{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"delete_everything"}}"#)
        let toolError = try #require(tool["error"] as? [String: Any])
        #expect(toolError["code"] as? Int == -32602)
        #expect(toolError["message"] as? String == "Unknown tool: delete_everything")

        let method = try call(server(), #"{"jsonrpc":"2.0","id":11,"method":"resources/list"}"#)
        #expect((method["error"] as? [String: Any])?["code"] as? Int == -32601)

        let parse = try call(server(), "{not json")
        #expect((parse["error"] as? [String: Any])?["code"] as? Int == -32700)
        #expect(parse["id"] is NSNull)

        let invalid = try call(server(), #"{"id":12,"method":"ping"}"#)
        #expect((invalid["error"] as? [String: Any])?["code"] as? Int == -32600)
    }

    @Test("Without a cache, tools answer a tool error that explains what to do")
    func noCache() throws {
        let answer = try call(server(snapshot: nil), #"{"jsonrpc":"2.0","id":13,"method":"tools/call","params":{"name":"get_usage"}}"#)
        let result = try #require(answer["result"] as? [String: Any])
        #expect(result["isError"] as? Bool == true)
        let text = (result["content"] as? [[String: Any]])?.first?["text"] as? String
        #expect(text?.contains("open the Brimline app") == true)
    }
}
