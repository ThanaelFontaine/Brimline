import Foundation
import BrimlineCore

// The `brimline` command: the same numbers as the menu bar, for people and agents.
//
//   brimline status [--json] [--live]   usage of each account (from the app's cache, or read now)
//   brimline accounts [--json]          accounts found on this Mac (no Keychain read)
//   brimline providers [enable|disable <name>]   which providers Brimline reads
//   brimline mcp                        local MCP server over stdio
//   brimline --version | --help

let version = BrimlineVersion.current

func printError(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
}

let usage = """
Brimline \(version): your AI subscription limits, account by account.

Usage:
  brimline status [--json] [--live]   Usage of each account. Reads the cache written by the
                                      Brimline app; --live reads the Keychain and asks the
                                      provider now (macOS may ask to allow the Keychain read).
  brimline accounts [--json]          Accounts found on this Mac.
  brimline providers [--json]         The providers and whether each is on. Only Claude is on by
                                      default: a provider that is off is not touched at all.
  brimline providers enable <name>    Turn a provider on (claude, chatgpt, gemini, grok, cursor).
  brimline providers disable <name>   Turn it off: nothing of it is opened or requested again.
  brimline mcp                        Local MCP server over stdio (list_accounts, get_usage,
                                      best_account).
  brimline --version                  Print the version.

Documentation: \(Links.agentsDoc.absoluteString)
"""

var arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? "status"
if !arguments.isEmpty { arguments.removeFirst() }
let flags = Set(arguments)

func rejectUnknown(_ allowed: Set<String>) {
    let unknown = flags.subtracting(allowed)
    if !unknown.isEmpty {
        printError("brimline: unknown option \(unknown.sorted().joined(separator: " ")). See brimline --help.")
        exit(64)
    }
}

let paths = BrimlinePaths()
// Before anything is read, including by `brimline mcp`: the files of the old folder (named after the former name) come over.
LegacyMigration.run(paths: paths)
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
    let accounts = Providers.discover(settings: settings)
    if flags.contains("--json") {
        struct Entry: Encodable {
            var id, provider, folder: String
            var keychainService, email, organization, label: String?
            var hidden: Bool
            enum CodingKeys: String, CodingKey {
                case id, provider, folder, email, organization, label, hidden
                case keychainService = "keychain_service"
            }
        }
        let entries = accounts.map {
            Entry(id: $0.id, provider: $0.provider.rawValue, folder: $0.source, keychainService: $0.keychainService,
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
            print("  \((a.source as NSString).abbreviatingWithTildeInPath)")
        }
    }

case "providers":
    let options = Set(arguments.filter { $0.hasPrefix("-") })
    let words = arguments.filter { !$0.hasPrefix("-") }
    if !options.subtracting(["--json"]).isEmpty {
        printError("brimline: unknown option \(options.subtracting(["--json"]).sorted().joined(separator: " ")). See brimline --help.")
        exit(64)
    }
    var current = settings
    if let action = words.first {
        guard action == "enable" || action == "disable", words.count == 2, !options.contains("--json") else {
            printError("brimline: usage: brimline providers [enable|disable <name>]. See brimline --help.")
            exit(64)
        }
        guard let provider = Provider(rawValue: words[1].lowercased()) else {
            printError("brimline: unknown provider \(words[1]). Choose one of \(Provider.allCases.map(\.rawValue).joined(separator: ", ")).")
            exit(64)
        }
        guard Providers.isSupported(provider) else {
            printError("brimline: \(provider.displayName) is not read by this version of Brimline.")
            exit(1)
        }
        current.enabledProviders.removeAll { $0 == provider.rawValue }
        if action == "enable" { current.enabledProviders.append(provider.rawValue) }
        do {
            try SettingsStore(file: paths.settingsFile).save(current)
        } catch {
            printError("brimline: could not save the settings: \(error.localizedDescription)")
            exit(1)
        }
        print("\(provider.displayName): \(action == "enable" ? "on" : "off")")
        print("(the app takes it at its next refresh)")
    } else if options.contains("--json") {
        struct Entry: Encodable { var provider: String; var enabled: Bool; var available: Bool }
        let entries = Provider.allCases.map {
            Entry(provider: $0.rawValue, enabled: current.isEnabled($0), available: Providers.isSupported($0))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        print(String(decoding: try encoder.encode(["providers": entries]), as: UTF8.self))
    } else {
        for provider in Provider.allCases {
            let state = Providers.isSupported(provider) ? (current.isEnabled(provider) ? "on" : "off") : "not available yet"
            print("\(provider.displayName.padding(toLength: 8, withPad: " ", startingAt: 0))\(state)")
        }
    }

case "status":
    rejectUnknown(["--json", "--live"])
    let now = Date()
    let cache = UsageCache(file: paths.cacheFile)
    let snapshot: UsageSnapshot
    let source: String
    if flags.contains("--live") {
        let accounts = Providers.discover(settings: settings)
        snapshot = await UsageService().refresh(accounts: accounts, settings: settings, previous: cache.load(), now: now, force: true)
        source = "live"
    } else if let cached = cache.load() {
        snapshot = cached
        source = "cache"
    } else {
        let message = "No usage data yet: open the Brimline app once (it writes the cache), or run brimline status --live."
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
        let paths = BrimlinePaths()
        return (UsageCache(file: paths.cacheFile).load(), SettingsStore(file: paths.settingsFile).load())
    })
    server.run()

default:
    printError("brimline: unknown command \(command). See brimline --help.")
    exit(64)
}
