import Foundation

/// `brimline report claude --account <address|auto> [--statusline] [--dir <folder>]`, apart from the process so
/// that tests run it on a pipe of their own.
///
/// Reads what Claude Code prints and keeps only its limits: from stream-json, the `rate_limit_event` lines; with
/// `--statusline`, the `rate_limits` of the status line JSON. The input is always read to its end, a usage error
/// included, so that the program writing into the pipe never sees it closed early.
///
/// With `--statusline` the command stays quiet: whatever goes wrong it prints nothing on the error output and exits
/// 0. It prints one short line ("5 h 23% · Week 41%") only when this input gave limits; otherwise nothing (Claude
/// Code then shows an empty status line if this command is the only one in it).
public struct ClaudeReportCommand: Sendable {
    public struct Outcome: Equatable, Sendable {
        public var code: Int32
        /// One line for the standard output.
        public var output: String?
        /// One line for the error output (never with `--statusline`).
        public var error: String?

        public init(code: Int32, output: String? = nil, error: String? = nil) {
            self.code = code
            self.output = output
            self.error = error
        }
    }

    public enum Exit {
        public static let recorded: Int32 = 0
        public static let notWritten: Int32 = 1
        public static let nothing: Int32 = 3
        public static let formatChanged: Int32 = 4
        public static let usage: Int32 = 64
    }

    public static let usageLine = "brimline: usage: brimline report claude --account <address|auto> [--statusline] [--dir <folder>]"
    /// The status line JSON is a few KiB: past 1 MiB it is not kept (it is still read to its end).
    public static let maxStatuslineBytes = 1 << 20

    public var environment: [String: String]
    public var home: URL
    public var strings: Strings
    public var now: Date

    public init(environment: [String: String] = ProcessInfo.processInfo.environment,
                home: URL = FileManager.default.homeDirectoryForCurrentUser,
                strings: Strings = Strings(), now: Date = Date()) {
        self.environment = environment
        self.home = home
        self.strings = strings
        self.now = now
    }

    /// Runs the command on `input` (a file descriptor: the standard input) and says what to print and how to exit.
    public func run(_ arguments: [String], input: Int32) -> Outcome {
        let statusline = arguments.contains("--statusline")
        func fail(_ message: String, _ code: Int32) -> Outcome {
            BoundedInput.drain(descriptor: input)
            return statusline ? Outcome(code: 0) : Outcome(code: code, error: message)
        }

        var account: String?
        var folder: String?
        var words: [String] = []
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            var name: String?
            for option in ["--account", "--dir"] where argument == option || argument.hasPrefix(option + "=") {
                name = option
            }
            if argument == "--statusline" {
            } else if let name {
                let value: String
                if argument.hasPrefix(name + "=") {
                    value = String(argument.dropFirst(name.count + 1))
                } else {
                    index += 1
                    guard index < arguments.count else { return fail(Self.usageLine, Exit.usage) }
                    value = arguments[index]
                }
                if name == "--account" { account = value } else { folder = value }
            } else if argument == "--provider" || argument.hasPrefix("--provider=") {
                return fail("brimline: --provider goes with status and accounts (the MCP tools take a provider argument). See brimline --help.", Exit.usage)
            } else if argument.hasPrefix("-") {
                return fail("brimline: unknown option \(argument). See brimline --help.", Exit.usage)
            } else {
                words.append(argument)
            }
            index += 1
        }
        guard words == ["claude"], let account else { return fail(Self.usageLine, Exit.usage) }

        let email: String
        // With `auto`, the Claude Code folder it stands for: a status line's transcript must lie in it.
        var autoFolder: String?
        if account == "auto" {
            guard let found = ClaudeReportEmail.autoAccount(environment: environment, home: home) else {
                return fail("brimline: no address in the .claude.json of the Claude Code folder (CLAUDE_CONFIG_DIR of this command, or ~/.claude): give --account <address>.", Exit.usage)
            }
            email = found.email
            autoFolder = found.configDirectory
        } else {
            guard let normalized = ClaudeReportEmail.normalize(account) else {
                return fail("brimline: \(account) is not a plain email address (\(ClaudeReportEmail.maxLength) characters at most).", Exit.usage)
            }
            email = normalized
        }

        let extraction: ClaudeCodeExtraction
        if statusline {
            guard let data = BoundedInput.readAll(descriptor: input, limit: Self.maxStatuslineBytes) else { return Outcome(code: 0) }
            // `auto` takes the folder from this command's environment; the session's transcript says the folder of
            // the session. When they differ, the numbers belong to another account; without an absolute transcript
            // path, nothing says whose they are. Either way, nothing is written or shown.
            if let autoFolder {
                guard let transcript = ClaudeCodeReportParser.transcriptPath(data),
                      ClaudeReportEmail.transcript(transcript, isIn: autoFolder) else { return Outcome(code: 0) }
            }
            extraction = ClaudeCodeReportParser.parseStatusline(data, now: now)
        } else {
            extraction = ClaudeCodeReportParser.parseStream(descriptor: input, now: now)
        }

        let directory = folder.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }
            ?? BrimlinePaths(home: home).claudeReportsDirectory
        let store = ClaudeReportStore(directory: directory)
        let written: ClaudeCodeReport?
        do {
            written = try store.record(extraction, email: email, now: now)
        } catch {
            let place = (directory.path as NSString).abbreviatingWithTildeInPath
            let why = (error as? ClaudeReportStore.Failure) == .unsafeFolder
                ? "the folder is a link, someone else's, or open to other users (it must be yours, 0700)"
                : "\(error)"
            if statusline, case .observed(let observation) = extraction {
                // Not written, but this input's numbers are known: the status line still shows them.
                return Outcome(code: 0, output: summary(ClaudeCodeReport.first(email: email, extraction: .observed(observation), at: now)))
            }
            return fail("brimline: could not write the report in \(place): \(why).", Exit.notWritten)
        }

        if statusline {
            guard case .observed = extraction else { return Outcome(code: 0) }
            return Outcome(code: 0, output: summary(written))
        }
        switch extraction {
        case .nothing:
            return Outcome(code: Exit.nothing, error: "brimline: no rate_limit_event in the input: nothing recorded.")
        case .formatChanged:
            return Outcome(code: Exit.formatChanged,
                           error: "brimline: Claude Code's rate_limit_event has a format Brimline does not know: recorded as format_changed, update Brimline.")
        case .observed:
            return Outcome(code: Exit.recorded)
        }
    }

    func summary(_ report: ClaudeCodeReport?) -> String? {
        guard let report, report.status == .ok else { return nil }
        return strings.statuslineSummary(report.limits(at: now), now: now)
    }
}
