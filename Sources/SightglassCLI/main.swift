import Foundation
import SightglassCore

// The `sightglass` command: the same numbers as the menu bar, for people and agents.
//
//   sightglass status [--json] [--live]   usage of each account (from the app's cache, or read now)
//   sightglass accounts [--json]          accounts found on this Mac (no Keychain read)
//   sightglass mcp                        local MCP server over stdio
//   sightglass --version | --help

let version = SightglassVersion.current

func printError(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
}

let usage = """
Sightglass \(version): your AI subscription limits, account by account.

Usage:
  sightglass status [--json] [--live]   Usage of each account. Reads the cache written by the
                                        Sightglass app; --live reads the Keychain and asks the
                                        provider now (macOS may ask to allow the Keychain read).
  sightglass accounts [--json]          Accounts found on this Mac.
  sightglass mcp                        Local MCP server over stdio (list_accounts, get_usage,
                                        best_account).
  sightglass --version                  Print the version.

Documentation: \(Links.agentsDoc.absoluteString)
"""

var arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? "status"
if !arguments.isEmpty { arguments.removeFirst() }
let flags = Set(arguments)

func rejectUnknown(_ allowed: Set<String>) {
    let unknown = flags.subtracting(allowed)
    if !unknown.isEmpty {
        printError("sightglass: unknown option \(unknown.sorted().joined(separator: " ")). See sightglass --help.")
        exit(64)
    }
}

let paths = SightglassPaths()
let settings = SettingsStore(file: paths.settingsFile).load()
let strings = Strings()
let time = TimeFormatter()

switch command {
case "--version", "-v", "version":
    print(version)

case "--help", "-h", "help":
    print(usage)

case "accounts":
    rejectUnknown(["--json"])
    let accounts = AccountDiscovery(extraFolders: settings.extraFolders).discover()
    if flags.contains("--json") {
        struct Entry: Encodable {
            var id, provider, folder, keychainService: String
            var email, organization, label: String?
            var hidden: Bool
            enum CodingKeys: String, CodingKey {
                case id, provider, folder, email, organization, label, hidden
                case keychainService = "keychain_service"
            }
        }
        let entries = accounts.map {
            Entry(id: $0.id, provider: $0.provider.rawValue, folder: $0.configDir, keychainService: $0.keychainService,
                  email: $0.email, organization: $0.organization, label: settings.label(for: $0.id),
                  hidden: settings.isHidden($0.id))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        print(String(decoding: try encoder.encode(["accounts": entries]), as: UTF8.self))
    } else if accounts.isEmpty {
        print(strings.noAccountTitle + ". " + strings.noAccountBody)
    } else {
        for a in accounts {
            let hidden = settings.isHidden(a.id) ? "  (hidden)" : ""
            print("\(a.email ?? a.folderName)\(hidden)")
            if let org = a.organization { print("  \(org)") }
            print("  \((a.configDir as NSString).abbreviatingWithTildeInPath)")
        }
    }

case "status":
    rejectUnknown(["--json", "--live"])
    let now = Date()
    let cache = UsageCache(file: paths.cacheFile)
    let snapshot: UsageSnapshot
    let source: String
    if flags.contains("--live") {
        let accounts = AccountDiscovery(extraFolders: settings.extraFolders).discover()
        snapshot = await UsageService().refresh(accounts: accounts, previous: cache.load(), now: now, force: true)
        source = "live"
    } else if let cached = cache.load() {
        snapshot = cached
        source = "cache"
    } else {
        let message = "No usage data yet: open the Sightglass app once (it writes the cache), or run sightglass status --live."
        if flags.contains("--json") {
            print(#"{"error": "\#(message)"}"#)
        } else {
            printError(message)
        }
        exit(2)
    }

    if flags.contains("--json") {
        print(AgentUsageReport(snapshot: snapshot, settings: settings, source: source, now: now).jsonString())
    } else {
        let visible = snapshot.accounts.filter { !settings.isHidden($0.account.id) }
        if visible.isEmpty { print(strings.noAccountTitle) }
        for u in visible {
            let title = settings.label(for: u.account.id) ?? u.account.email ?? u.account.folderName
            print(title)
            if let message = strings.statusMessage(u.status), u.status != .ok {
                print("  \(message)")
            }
            var rows: [(String, String, String)] = []
            for limit in u.limits {
                let percent = strings.percentText(limit.effectivePercent(at: now))
                let reset = limit.resetsAt.map { time.reset($0, now: now) } ?? ""
                rows.append((strings.limitName(limit), percent, reset))
            }
            if u.hasNoGlobalWeeklyLimit { rows.insert((strings.noGlobalWeekly, "", ""), at: min(1, rows.count)) }
            let width = rows.filter { !$0.1.isEmpty }.map(\.0.count).max() ?? 0
            for (name, percent, reset) in rows {
                if percent.isEmpty {
                    print("  \(name)")
                } else {
                    let padded = name.padding(toLength: width, withPad: " ", startingAt: 0)
                    let pct = String(repeating: " ", count: max(0, 5 - percent.count)) + percent
                    print("  \(padded)  \(pct)   \(reset)")
                }
            }
            if let age = u.age(at: now), u.status == .ok, age > TimeInterval(settings.refreshMinutes * 120 + 60) {
                print("  " + strings.dataAge(time.age(age)))
            }
        }
        let age = max(0, now.timeIntervalSince(snapshot.generatedAt))
        print("")
        print(source == "live" ? "(read now)" : "(cache, \(time.age(age)))")
    }

case "mcp":
    rejectUnknown([])
    let server = MCPServer(version: version, load: {
        let paths = SightglassPaths()
        return (UsageCache(file: paths.cacheFile).load(), SettingsStore(file: paths.settingsFile).load())
    })
    server.run()

default:
    printError("sightglass: unknown command \(command). See sightglass --help.")
    exit(64)
}
