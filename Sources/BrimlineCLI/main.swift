import Foundation
import BrimlineCore

// The `brimline` command: the same numbers as the menu bar, for people and agents.
//
//   brimline status [--json] [--live] [--provider <name>]   usage of each account (from the app's cache, or read now)
//   brimline status --live --shape [--provider <name>]      the skeleton of each provider's answer (keys and types)
//   brimline accounts [--json] [--provider <name>]          accounts found on this Mac (no Keychain read)
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
  brimline status [--json] [--live] [--provider <name>]
                                      Usage of each account. Reads the cache written by the
                                      Brimline app; --live reads the sign-in and asks the
                                      provider now, for the providers that are on.
                                      --provider limits the answer to one provider.
  brimline status --live --shape [--provider <name>]
                                      Shows the shape of the provider's answer (keys and the type
                                      of each value, never a value), to check a format.
  brimline accounts [--json] [--provider <name>]
                                      Accounts found on this Mac.
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

// `--provider <name>` (or `--provider=<name>`) is taken out first: its value is not a flag.
var providerFilter: Provider?
var providerGiven = false
do {
    var rest: [String] = []
    var index = 0
    while index < arguments.count {
        let argument = arguments[index]
        var value: String?
        if argument == "--provider" {
            index += 1
            guard index < arguments.count else {
                printError("brimline: --provider needs a name (\(Provider.allCases.map(\.rawValue).joined(separator: ", "))).")
                exit(64)
            }
            value = arguments[index]
        } else if argument.hasPrefix("--provider=") {
            value = String(argument.dropFirst("--provider=".count))
        }
        if let value {
            providerGiven = true
            guard let provider = Provider(rawValue: value.lowercased()) else {
                printError("brimline: unknown provider \(value). Choose one of \(Provider.allCases.map(\.rawValue).joined(separator: ", ")).")
                exit(64)
            }
            providerFilter = provider
        } else {
            rest.append(argument)
        }
        index += 1
    }
    arguments = rest
}
let flags = Set(arguments)
if providerGiven && command != "status" && command != "accounts" {
    printError("brimline: --provider goes with status and accounts (the MCP tools take a provider argument). See brimline --help.")
    exit(64)
}

/// A short hint on stderr when a provider was asked for and there is nothing to show: it is off.
nonisolated(unsafe) var hinted = false
func hintIfEmpty(_ provider: Provider?, settings: BrimlineSettings) {
    guard let provider, !settings.isEnabled(provider), !hinted else { return }
    hinted = true
    if Providers.isSupported(provider) {
        printError("\(provider.displayName) is off, so nothing of it is read. Turn it on with: brimline providers enable \(provider.rawValue)")
    } else {
        printError("This version of Brimline does not read \(provider.displayName) yet, so there is nothing to show.")
    }
}

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
    let accounts = Providers.discover(settings: settings).filter { providerFilter == nil || $0.provider == providerFilter }
    if accounts.isEmpty { hintIfEmpty(providerFilter, settings: settings) }
    if flags.contains("--json") {
        struct Entry: Encodable {
            var id, provider, source: String
            var folder, keychainService, email, organization, label: String?
            var hidden: Bool
            enum CodingKeys: String, CodingKey {
                case id, provider, source, folder, email, organization, label, hidden
                case keychainService = "keychain_service"
            }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let entries = accounts.map {
            Entry(id: $0.id, provider: $0.provider.rawValue, source: AgentPath.display($0.source, home: home),
                  folder: $0.provider == .claude ? $0.source : nil, keychainService: $0.keychainService,
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
            let place = (a.source as NSString).abbreviatingWithTildeInPath
            print(a.provider == .claude ? "  \(place)" : "  \(a.provider.displayName) · \(place)")
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
    rejectUnknown(["--json", "--live", "--shape"])
    let now = Date()
    let cache = UsageCache(file: paths.cacheFile)
    let snapshot: UsageSnapshot
    let source: String
    let showShape = flags.contains("--shape")
    if showShape && (!flags.contains("--live") || flags.contains("--json")) {
        printError("brimline: --shape goes with --live, and replaces --json. See brimline --help.")
        exit(64)
    }
    if flags.contains("--live") {
        let accounts = Providers.discover(settings: settings).filter { providerFilter == nil || $0.provider == providerFilter }
        if accounts.isEmpty { hintIfEmpty(providerFilter, settings: settings) }
        let recorder = RecordingHTTPClient()
        let service = showShape
            ? UsageService(readers: Providers.make(credentials: SecurityToolCredentialReader(), http: recorder))
            : UsageService()
        snapshot = await service.refresh(accounts: accounts, settings: settings, previous: cache.load(), now: now, force: true)
        source = "live"
        if showShape {
            // The skeleton of the last answer of each endpoint: keys and types, never a value.
            let skeletons = recorder.skeletons
            if skeletons.isEmpty {
                printError("brimline: no answer to show (nothing was asked, or the provider did not answer with JSON).")
                exit(2)
            }
            for entry in skeletons {
                print(entry.url)
                print(entry.skeleton)
            }
            exit(0)
        }
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
        print(AgentUsageReport(snapshot: snapshot, settings: settings, source: source, now: now,
                               provider: providerFilter).jsonString())
    } else {
        let visible = snapshot.accounts.filter {
            !settings.isHidden($0.account.id) && (providerFilter == nil || $0.account.provider == providerFilter)
        }
        if visible.isEmpty {
            print(strings.noAccountTitle)
            hintIfEmpty(providerFilter, settings: settings)
        }
        for u in visible {
            let title = settings.label(for: u.account.id) ?? u.account.email ?? u.account.folderName
            print(u.account.provider == .claude ? title : "\(u.account.provider.displayName) · \(title)")
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
