import Foundation
import BrimlineCore

// The `brimline` command: the same numbers as the menu bar, for people and agents.
//
//   brimline status [--json] [--live] [--provider <name>]   usage of each account (from the app's cache, or read now)
//   brimline status --live --shape [--provider <name>]      the skeleton of each provider's answer (keys and types)
//   brimline accounts [--json] [--provider <name>]          accounts found on this Mac (no Keychain read)
//   brimline providers [enable|disable <name>]   which providers Brimline reads
//   brimline report claude --account <address|auto> [--statusline] [--dir <folder>]
//                                       records the limits Claude Code printed (standard input)
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
  brimline report claude --account <address|auto> [--statusline] [--dir <folder>]
                                      Records the limits Claude Code gives, read on standard input:
                                      the rate_limit_event lines of claude -p --output-format
                                      stream-json, or with --statusline the JSON of a status line
                                      (then it prints "5 h 23% · Week 41%" or nothing, and never
                                      fails). Only the percentages and reset times are kept, in
                                      ~/Library/Application Support/Brimline/claude-reports/
                                      (--dir another folder). auto takes the address of the
                                      CLAUDE_CONFIG_DIR folder (or ~/.claude). Exit codes: 0
                                      recorded, 3 nothing in the input, 4 format changed (recorded
                                      as such), 1 not written, 64 usage.
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
// `brimline report claude`: handled first and on its own, before the settings or the migration, so that a
// status line runs it fast. It reads standard input and writes one report file, nothing else.
if command == "report" {
    if providerGiven && !arguments.contains("--statusline") {
        printError("brimline: --provider goes with status and accounts (the MCP tools take a provider argument). See brimline --help.")
        exit(64)
    }
    runReport(arguments)
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
            Entry(id: $0.id, provider: $0.provider.rawValue, source: AgentPath.source(of: $0, home: home),
                  folder: AgentPath.folder(of: $0), keychainService: $0.keychainService,
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
            let place = a.readsReportOnly ? strings.reportSourceLine : (a.source as NSString).abbreviatingWithTildeInPath
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
        let home = FileManager.default.homeDirectoryForCurrentUser
        for u in visible {
            for line in StatusText.lines(for: u, among: visible, settings: settings, strings: strings, time: time,
                                         now: now, home: home, refreshMinutes: settings.refreshMinutes) {
                print(line)
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

/// `brimline report claude --account <address|auto> [--statusline] [--dir <folder>]`.
///
/// Reads what Claude Code prints and keeps only its limits: from stream-json, the `rate_limit_event` lines; with
/// `--statusline`, the `rate_limits` of the status line JSON. With `--statusline` the command must stay quick and
/// quiet: whatever goes wrong, it prints nothing on the error output and exits 0 (a status line whose command
/// fails or prints nothing goes blank); when it knows the account's numbers it prints one short line.
func runReport(_ arguments: [String]) -> Never {
    let statusline = arguments.contains("--statusline")
    let usageLine = "brimline: usage: brimline report claude --account <address|auto> [--statusline] [--dir <folder>]"
    func fail(_ message: String, _ code: Int32) -> Never {
        if statusline { exit(0) }
        printError(message)
        exit(code)
    }

    var account: String?
    var folder: String?
    var words: [String] = []
    var index = 0
    while index < arguments.count {
        let argument = arguments[index]
        func value(_ name: String) -> String {
            if argument.hasPrefix(name + "=") { return String(argument.dropFirst(name.count + 1)) }
            index += 1
            guard index < arguments.count else { fail(usageLine, 64) }
            return arguments[index]
        }
        if argument == "--statusline" {
        } else if argument == "--account" || argument.hasPrefix("--account=") {
            account = value("--account")
        } else if argument == "--dir" || argument.hasPrefix("--dir=") {
            folder = value("--dir")
        } else if argument.hasPrefix("-") {
            fail("brimline: unknown option \(argument). See brimline --help.", 64)
        } else {
            words.append(argument)
        }
        index += 1
    }
    guard words == ["claude"], let account else { fail(usageLine, 64) }
    let email: String
    if account == "auto" {
        guard let found = ClaudeReportEmail.auto() else {
            fail("brimline: no address in the .claude.json of the Claude Code folder (CLAUDE_CONFIG_DIR, or ~/.claude): give --account <address>.", 64)
        }
        email = found
    } else {
        guard let normalized = ClaudeReportEmail.normalize(account) else {
            fail("brimline: \(account) is not a plain email address.", 64)
        }
        email = normalized
    }

    let now = Date()
    let extraction: ClaudeCodeExtraction
    if statusline {
        // The status line JSON is a few KiB: past 1 MiB it is not read at all.
        extraction = readStandardInput(limit: 1 << 20).map { ClaudeCodeReportParser.parseStatusline($0, now: now) } ?? .nothing
    } else {
        extraction = ClaudeCodeReportParser.parseStream(lines: sequence(state: ()) { _ in readLine(strippingNewline: true) },
                                                        now: now)
    }

    let directory = folder.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }
        ?? BrimlinePaths().claudeReportsDirectory
    let store = ClaudeReportStore(directory: directory)
    let written: ClaudeCodeReport?
    do {
        written = try store.record(extraction, email: email, now: now)
    } catch {
        fail("brimline: could not write the report in \((directory.path as NSString).abbreviatingWithTildeInPath): \(error).", 1)
    }

    if statusline {
        let report = written ?? (try? store.load(email))
        if let summary = report.flatMap({ $0.status == .ok ? Strings().statuslineSummary($0.limits(at: now), now: now) : nil }) {
            print(summary)
        }
        exit(0)
    }
    switch extraction {
    case .nothing:
        printError("brimline: no rate_limit_event in the input: nothing recorded.")
        exit(3)
    case .formatChanged:
        printError("brimline: Claude Code's rate_limit_event has a format Brimline does not know: recorded as format_changed, update Brimline.")
        exit(4)
    case .observed:
        exit(0)
    }
}

/// The whole standard input, or nil past `limit` bytes.
func readStandardInput(limit: Int) -> Data? {
    var data = Data()
    var chunk = [UInt8](repeating: 0, count: 16 * 1024)
    while true {
        let count = chunk.withUnsafeMutableBytes { Darwin.read(STDIN_FILENO, $0.baseAddress, $0.count) }
        if count < 0 {
            if errno == EINTR { continue }
            return nil
        }
        if count == 0 { return data }
        data.append(contentsOf: chunk[0..<count])
        if data.count > limit { return nil }
    }
}
