import Foundation

/// A local MCP server over stdio: JSON-RPC 2.0, one message per line, written by hand.
///
/// It answers `initialize`, `ping`, `tools/list` and `tools/call` with three read-only tools:
/// `list_accounts`, `get_usage` and `best_account`. It reads the cache written by the app,
/// never the Keychain, so it can never expose a token. Every answer carries the age of the data.
public struct MCPServer: Sendable {
    public static let supportedProtocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]
    public static let preferredProtocolVersion = "2025-06-18"

    public var version: String
    /// Returns the last snapshot (nil when the app has not written one yet) and the settings.
    public var load: @Sendable () -> (UsageSnapshot?, BrimlineSettings)
    public var now: @Sendable () -> Date
    /// The home folder, for writing paths as `~/...` in the answers.
    public var home: URL

    public init(version: String,
                load: @escaping @Sendable () -> (UsageSnapshot?, BrimlineSettings),
                now: @escaping @Sendable () -> Date = { Date() },
                home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.version = version
        self.load = load
        self.now = now
        self.home = home
    }

    /// Largest message accepted on one line.
    public static let maxLineBytes = 1024 * 1024

    /// Reads lines from the standard input and writes answers to `output` until the input closes.
    /// A line longer than `maxLineBytes` is dropped up to its newline and answered with -32600.
    public func run(input: FileHandle = .standardInput, output: FileHandle = .standardOutput) {
        var splitter = BoundedLineSplitter(maxBytes: Self.maxLineBytes)
        func answer(_ items: [BoundedLineSplitter.Item]) {
            for item in items {
                let reply: String?
                switch item {
                case .line(let line): reply = handle(line: line)
                case .tooLong: reply = Self.encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32600, "message": "Invalid Request"]])
                }
                if let reply { output.write(Data((reply + "\n").utf8)) }
            }
        }
        // read(2) returns as soon as some bytes are there; FileHandle.read(upToCount:) would wait for
        // 64 KiB or the end of the input on a pipe, and a client that keeps stdin open would get no answer.
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        let descriptor = input.fileDescriptor
        while true {
            let count = buffer.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { break }
            answer(splitter.push(Data(buffer[0..<count])))
        }
        answer(splitter.finish())
    }

    /// Handles one message. Returns the answer line, or nil for a notification.
    public func handle(line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) else {
            return Self.encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
        }
        guard let message = object as? [String: Any], message["jsonrpc"] as? String == "2.0",
              let method = message["method"] as? String else {
            let id = (object as? [String: Any])?["id"] ?? NSNull()
            return Self.encode(["jsonrpc": "2.0", "id": id, "error": ["code": -32600, "message": "Invalid Request"]])
        }
        guard let id = message["id"], !(id is NSNull) else {
            return nil // a notification (for example notifications/initialized): no answer
        }
        let params = message["params"] as? [String: Any] ?? [:]
        switch dispatch(method: method, params: params) {
        case .success(let result):
            return Self.encode(["jsonrpc": "2.0", "id": id, "result": result])
        case .failure(let error):
            return Self.encode(["jsonrpc": "2.0", "id": id, "error": ["code": error.code, "message": error.message]])
        }
    }

    struct RPCError: Error {
        var code: Int
        var message: String
    }

    func dispatch(method: String, params: [String: Any]) -> Result<Any, RPCError> {
        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String
            let version = requested.flatMap { Self.supportedProtocolVersions.contains($0) ? $0 : nil }
                ?? Self.preferredProtocolVersion
            return .success([
                "protocolVersion": version,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "brimline", "title": "Brimline", "version": self.version],
                "instructions": "Read-only usage of the user's AI subscription limits, account by account. Numbers come from the Brimline app's cache: check age_seconds.",
            ] as [String: Any])
        case "ping":
            return .success([String: Any]())
        case "tools/list":
            return .success(["tools": Self.tools])
        case "tools/call":
            guard let name = params["name"] as? String else {
                return .failure(RPCError(code: -32602, message: "Missing tool name"))
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            return call(tool: name, arguments: arguments)
        default:
            return .failure(RPCError(code: -32601, message: "Method not found: \(method)"))
        }
    }

    // MARK: Tools

    static var providerNames: [String] { Provider.allCases.map(\.rawValue) }

    static var tools: [[String: Any]] { [
        [
            "name": "list_accounts",
            "title": "List accounts",
            "description": "Lists the AI subscription accounts Brimline knows on this Mac (provider, email address, organization, source, status). No usage numbers.",
            "inputSchema": ["type": "object", "properties": [String: Any](), "additionalProperties": false] as [String: Any],
            "annotations": ["readOnlyHint": true, "openWorldHint": false],
        ],
        [
            "name": "get_usage",
            "title": "Get usage",
            "description": "Usage of each account: every limit (five hour session, week, day, month, per model...) with the percentage used and the reset time, plus the age of the numbers.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "provider": ["type": "string", "enum": providerNames, "description": "Optional: only the accounts of this provider. All providers when omitted."],
                    "account": ["type": "string", "description": "Optional: an email address or an account id. All accounts when omitted."],
                    "include_hidden": ["type": "boolean", "description": "Include the accounts hidden in the app's settings. Default false."],
                ] as [String: Any],
                "additionalProperties": false,
            ] as [String: Any],
            "annotations": ["readOnlyHint": true, "openWorldHint": false],
        ],
        [
            "name": "best_account",
            "title": "Best account",
            "description": "The account of one provider with the most room left. provider: claude (default), chatgpt, gemini, grok or cursor. window: any (every limit that applies, default), session, week, day, month or period: a window that does not exist for the provider is an error. model: optional model name (for example Fable) to include its own limit.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "provider": ["type": "string", "enum": providerNames, "description": "Which provider's accounts are ranked. Default claude."],
                    "window": ["type": "string", "enum": UsageWindow.names, "description": "Which limits count. Default any."],
                    "model": ["type": "string", "description": "Optional model name, matched without case."],
                ] as [String: Any],
                "additionalProperties": false,
            ] as [String: Any],
            "annotations": ["readOnlyHint": true, "openWorldHint": false],
        ],
    ] }

    func call(tool: String, arguments: [String: Any]) -> Result<Any, RPCError> {
        guard Self.tools.contains(where: { $0["name"] as? String == tool }) else {
            return .failure(RPCError(code: -32602, message: "Unknown tool: \(tool)"))
        }
        let (snapshot, settings) = load()
        let now = self.now()
        guard let snapshot else {
            return .success(Self.toolError("No usage data yet: open the Brimline app once (it writes the cache), then try again."))
        }

        switch tool {
        case "list_accounts":
            let accounts = snapshot.accounts.map { u -> [String: Any] in
                var entry: [String: Any] = [
                    "id": u.account.id,
                    "provider": u.account.provider.rawValue,
                    "source": AgentPath.display(u.account.source, home: home),
                    "hidden": settings.isHidden(u.account.id),
                    "status": u.status.rawValue,
                ]
                entry["folder"] = u.account.provider == .claude ? u.account.source : NSNull()
                entry["reason"] = u.status == .notReadable ? (u.reason?.rawValue ?? NSNull()) : NSNull()
                entry["email"] = u.account.email ?? NSNull()
                entry["organization"] = u.account.organization ?? NSNull()
                entry["label"] = settings.label(for: u.account.id) ?? NSNull()
                return entry
            }
            return .success(Self.toolResult([
                "generated_at": ISODate.format(snapshot.generatedAt),
                "age_seconds": max(0, Int(now.timeIntervalSince(snapshot.generatedAt))),
                "accounts": accounts,
            ]))

        case "get_usage":
            let includeHidden = arguments["include_hidden"] as? Bool ?? false
            var provider: Provider?
            if let name = arguments["provider"] as? String {
                guard let parsed = Provider(rawValue: name) else {
                    return .success(Self.toolError("Unknown provider \(name): use \(Self.providerNames.joined(separator: ", "))."))
                }
                provider = parsed
            }
            var report = AgentUsageReport(snapshot: snapshot, settings: settings, source: "cache", now: now,
                                          includeHidden: includeHidden, provider: provider, home: home)
            if let wanted = (arguments["account"] as? String)?.trimmingCharacters(in: .whitespaces), !wanted.isEmpty {
                report.accounts = report.accounts.filter {
                    $0.id == wanted || $0.email?.caseInsensitiveCompare(wanted) == .orderedSame
                }
                if report.accounts.isEmpty {
                    return .success(Self.toolError("No account matches \(wanted). Call list_accounts to see the accounts."))
                }
            }
            var result = AgentJSON.object(report)
            if report.accounts.isEmpty, let provider, var object = result as? [String: Any] {
                object["note"] = Self.emptyNote(provider, settings: settings)
                result = object
            }
            return .success(Self.toolResult(result))

        case "best_account":
            let providerName = (arguments["provider"] as? String) ?? Provider.claude.rawValue
            guard let provider = Provider(rawValue: providerName) else {
                return .success(Self.toolError("Unknown provider \(providerName): use \(Self.providerNames.joined(separator: ", "))."))
            }
            let windowName = (arguments["window"] as? String) ?? "any"
            guard let window = UsageWindow(rawValue: windowName) else {
                return .success(Self.toolError("Unknown window \(windowName): use \(UsageWindow.names.joined(separator: ", "))."))
            }
            guard provider.windows.contains(window) else {
                return .success(Self.toolError("The window \(windowName) does not exist for \(provider.rawValue): use \(provider.windows.map(\.rawValue).joined(separator: " or "))."))
            }
            let model = arguments["model"] as? String
            let visible = snapshot.accounts.filter { !settings.isHidden($0.account.id) && $0.account.provider == provider }
            let ranking = Ranking.rank(visible, window: window, model: model, now: now)
            let entries = ranking.map { choice -> [String: Any] in
                var entry: [String: Any] = AgentJSON.object(AgentAccount(choice.usage, settings: settings, now: now, home: home)) as? [String: Any] ?? [:]
                entry["headroom_percent"] = choice.headroom
                entry["binding_limit"] = choice.bindingLimit.map { AgentJSON.object(AgentLimit($0, now: now)) } ?? NSNull()
                return entry
            }
            var result: [String: Any] = [
                "provider": provider.rawValue,
                "window": window.rawValue,
                "generated_at": ISODate.format(snapshot.generatedAt),
                "age_seconds": max(0, Int(now.timeIntervalSince(snapshot.generatedAt))),
                "best": entries.first ?? NSNull(),
                "ranking": entries,
            ]
            result["model"] = model ?? NSNull()
            if entries.isEmpty { result["note"] = Self.emptyNote(provider, settings: settings) }
            return .success(Self.toolResult(result))

        default:
            return .failure(RPCError(code: -32602, message: "Unknown tool: \(tool)"))
        }
    }

    /// Why an answer holds no account of a provider: it is off (nothing of it is read), or it has no numbers.
    static func emptyNote(_ provider: Provider, settings: BrimlineSettings,
                          readers: [any ProviderReader] = Providers.all) -> String {
        if !settings.isEnabled(provider) {
            // A provider without a reader cannot be switched on: do not point at a switch that is refused.
            if !Providers.isSupported(provider, readers: readers) {
                return "This version of Brimline does not read \(provider.rawValue) yet, so there is no account to show."
            }
            return "\(provider.rawValue) is off in Brimline, so nothing of it is read. The user can turn it on in the Brimline settings or with: brimline providers enable \(provider.rawValue)"
        }
        return "No \(provider.rawValue) account has usage numbers yet."
    }

    static func toolResult(_ structured: Any) -> [String: Any] {
        let text = (try? JSONSerialization.data(withJSONObject: structured, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]))
            .map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        return ["content": [["type": "text", "text": text]], "structuredContent": structured, "isError": false]
    }

    static func toolError(_ message: String) -> [String: Any] {
        ["content": [["type": "text", "text": message]], "isError": true]
    }

    static func encode(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) else {
            return #"{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"Internal error"}}"#
        }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Splits a byte stream into lines without ever holding more than `maxBytes` of one line.
struct BoundedLineSplitter {
    enum Item: Equatable {
        case line(String)
        case tooLong
    }

    let maxBytes: Int
    private var buffer = Data()
    private var discarding = false

    init(maxBytes: Int) { self.maxBytes = maxBytes }

    mutating func push(_ chunk: Data) -> [Item] {
        var items: [Item] = []
        var rest = chunk[...]
        while !rest.isEmpty {
            if let newline = rest.firstIndex(of: 0x0A) {
                let head = rest[rest.startIndex..<newline]
                rest = rest[rest.index(after: newline)...]
                if discarding {
                    discarding = false
                } else if buffer.count + head.count > maxBytes {
                    items.append(.tooLong)
                } else {
                    items.append(.line(String(decoding: buffer + head, as: UTF8.self)))
                }
                buffer.removeAll(keepingCapacity: true)
            } else {
                if !discarding {
                    if buffer.count + rest.count > maxBytes {
                        discarding = true
                        buffer.removeAll()
                        items.append(.tooLong)
                    } else {
                        buffer.append(contentsOf: rest)
                    }
                }
                rest = rest[rest.endIndex...]
            }
        }
        return items
    }

    /// The last line when the input closes without a final newline.
    mutating func finish() -> [Item] {
        defer { buffer.removeAll(); discarding = false }
        guard !discarding, !buffer.isEmpty else { return [] }
        return [.line(String(decoding: buffer, as: UTF8.self))]
    }
}
