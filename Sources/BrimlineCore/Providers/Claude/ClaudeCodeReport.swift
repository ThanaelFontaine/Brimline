import Foundation

/// A report of the limits Claude Code itself saw for one account, written by `brimline report claude`.
///
/// Claude Code already learns the limits of its account with every answer: it gives them to a status line
/// command (`rate_limits`, documented) and, in `-p` mode with `--output-format stream-json`, prints a
/// `rate_limit_event` line. The command takes only the numbers out of that input and keeps them here, one
/// file per address; the app reads the file. No token is read, no request is sent, no quota is spent.
///
/// The file holds the address, the source of the last observation, its time, and the two windows (share
/// used and reset time, each with the time it was seen). Its types have no other field: nothing else of the
/// input can be written, whatever the input holds.
public struct ClaudeCodeReport: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1
    /// 64 KiB: a report is a few hundred bytes.
    public static let maxBytes = 64 * 1024

    /// Where the numbers came from.
    public enum Source: String, Codable, Sendable, CaseIterable {
        /// A `rate_limit_event` line of `claude -p --output-format stream-json`.
        case streamJSON = "stream-json"
        /// The JSON Claude Code gives a status line command on its standard input.
        case statusline
    }

    /// `formatChanged` when the last input had a limits event Brimline could not read: the windows are the
    /// last ones read, and the app says the format changed instead of showing them as new.
    public enum Status: String, Codable, Sendable {
        case ok
        case formatChanged = "format_changed"
    }

    public struct Window: Codable, Sendable, Equatable {
        /// Share used, from 0 to 100.
        public var percent: Double
        public var resetsAt: Date?
        /// When Claude Code gave this window.
        public var observedAt: Date

        public init(percent: Double, resetsAt: Date?, observedAt: Date) {
            self.percent = percent
            self.resetsAt = resetsAt
            self.observedAt = observedAt
        }

        enum CodingKeys: String, CodingKey {
            case percent
            case resetsAt = "resets_at"
            case observedAt = "observed_at"
        }
    }

    public var schemaVersion: Int
    /// The address, lower case.
    public var email: String
    public var source: Source
    /// When the last input was recorded.
    public var observedAt: Date
    public var status: Status
    public var fiveHour: Window?
    /// The week across all models. Absent until Claude Code has given it once (a team seat never has it).
    public var sevenDay: Window?

    public init(email: String, source: Source, observedAt: Date, status: Status = .ok,
                fiveHour: Window? = nil, sevenDay: Window? = nil) {
        self.schemaVersion = Self.currentSchemaVersion
        self.email = email
        self.source = source
        self.observedAt = observedAt
        self.status = status
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
    }

    enum CodingKeys: String, CodingKey {
        case email, source, status
        case schemaVersion = "schema_version"
        case observedAt = "observed_at"
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }

    /// The report with one more input: each window Claude Code gave replaces the one kept, a window it did not
    /// give stays as it was (the week is missing from a few events, and the status line drops a window once its
    /// reset time has passed). An input with an unreadable limits event keeps every window and says so.
    public func merged(with extraction: ClaudeCodeExtraction, at now: Date) -> ClaudeCodeReport {
        var next = self
        switch extraction {
        case .nothing:
            return self
        case .formatChanged(let source):
            next.source = source
            next.observedAt = now
            next.status = .formatChanged
        case .observed(let observation):
            next.source = observation.source
            next.observedAt = now
            next.status = .ok
            if let w = observation.fiveHour { next.fiveHour = Window(percent: w.percent, resetsAt: w.resetsAt, observedAt: now) }
            if let w = observation.sevenDay { next.sevenDay = Window(percent: w.percent, resetsAt: w.resetsAt, observedAt: now) }
        }
        return next
    }

    /// A first report from one input, nil when the input held nothing to record.
    public static func first(email: String, extraction: ClaudeCodeExtraction, at now: Date) -> ClaudeCodeReport? {
        switch extraction {
        case .nothing: return nil
        case .formatChanged(let source):
            return ClaudeCodeReport(email: email, source: source, observedAt: now, status: .formatChanged)
        case .observed(let observation):
            return ClaudeCodeReport(email: email, source: observation.source, observedAt: now)
                .merged(with: extraction, at: now)
        }
    }

    /// The limits as they apply at `now`: a window whose reset time has passed is back to 0 % (with no reset
    /// time: the next one is not known yet). The week is there only when it was seen once; a week never seen
    /// is unknown, never "no weekly limit".
    public func limits(at now: Date) -> [UsageLimit] {
        func limit(_ kind: LimitKind, _ window: Window?) -> UsageLimit? {
            guard let window, let percent = ProviderText.percent(window.percent) else { return nil }
            if let resets = window.resetsAt, resets <= now { return UsageLimit(kind: kind, percent: 0, resetsAt: nil) }
            return UsageLimit(kind: kind, percent: percent, resetsAt: window.resetsAt)
        }
        return [limit(.session, fiveHour), limit(.weekly, sevenDay)].compactMap { $0 }
    }

    /// The time of the numbers at `now`: the oldest window that still runs, so the age shown is never younger
    /// than a number in use. A window whose reset time has passed is 0 % whatever its age, so it does not count,
    /// unless every window has reset (then the latest observation).
    public func numbersObservedAt(at now: Date) -> Date? {
        let windows = [fiveHour, sevenDay].compactMap { $0 }
        let running = windows.filter { w in w.resetsAt.map { $0 > now } ?? true }
        return running.isEmpty ? windows.map(\.observedAt).max() : running.map(\.observedAt).min()
    }
}

/// One window as Claude Code gave it.
public struct ClaudeCodeWindow: Sendable, Equatable {
    public var percent: Double
    public var resetsAt: Date?

    public init(percent: Double, resetsAt: Date?) {
        self.percent = percent
        self.resetsAt = resetsAt
    }
}

public struct ClaudeCodeObservation: Sendable, Equatable {
    public var source: ClaudeCodeReport.Source
    public var fiveHour: ClaudeCodeWindow?
    public var sevenDay: ClaudeCodeWindow?
}

/// What an input gave.
public enum ClaudeCodeExtraction: Sendable, Equatable {
    /// No limits in it (a status line before the first answer, a plan without limits, a stream with no event).
    case nothing
    case observed(ClaudeCodeObservation)
    /// A limits event was there, but not in a form Brimline knows: its format changed.
    case formatChanged(ClaudeCodeReport.Source)
}

/// Takes the limits out of what Claude Code prints, and nothing else.
///
/// - The status line JSON: only `rate_limits.five_hour` and `rate_limits.seven_day`, each with
///   `used_percentage` (0 to 100) and `resets_at` (Unix seconds), as https://code.claude.com/docs/en/statusline
///   documents them. `spend_limit` and every other key are ignored.
/// - A stream-json line: only a line whose `type` is `rate_limit_event`, and of it only
///   `rate_limit_info.unifiedWindows.{five_hour,seven_day}`, with `utilization` (a fraction, 0 to 1) and
///   `resetsAt` (Unix seconds). `unifiedWindows` is not in the published type of the event (it was seen on
///   October 2026 versions): when it is missing, the format changed, and nothing is guessed.
public enum ClaudeCodeReportParser {
    /// A line longer than this is never parsed: a limits event is a few hundred bytes.
    public static let maxLineBytes = 64 * 1024

    public static func parseStatusline(_ data: Data, now: Date) -> ClaudeCodeExtraction {
        guard let object = try? JSONSerialization.jsonObject(with: data), let root = object as? [String: Any] else {
            return .nothing
        }
        guard let rateLimits = root["rate_limits"] else { return .nothing }
        guard let limits = rateLimits as? [String: Any] else { return .formatChanged(.statusline) }
        var observation = ClaudeCodeObservation(source: .statusline)
        for (key, path) in [("five_hour", \ClaudeCodeObservation.fiveHour), ("seven_day", \ClaudeCodeObservation.sevenDay)] {
            guard let value = limits[key] else { continue }
            guard let window = value as? [String: Any],
                  let used = UsageParser.number(window["used_percentage"]), used.isFinite, used >= 0, used <= 1000,
                  case .valid(let resets) = resetTime(window["resets_at"], now: now) else {
                return .formatChanged(.statusline)
            }
            observation[keyPath: path] = ClaudeCodeWindow(percent: min(used, 100), resetsAt: resets)
        }
        return observation.fiveHour == nil && observation.sevenDay == nil ? .nothing : .observed(observation)
    }

    /// Reads stream-json lines in order. The windows of the last readable event win, window by window; a stream
    /// whose every event was unreadable is a format change; a stream with no event gives nothing.
    public static func parseStream<S: Sequence>(lines: S, now: Date) -> ClaudeCodeExtraction where S.Element == String {
        var reader = StreamReader(now: now)
        for line in lines { reader.add(line) }
        return reader.extraction
    }

    /// Reads stream-json from a file descriptor (the standard input) to its end, in blocks: a line longer than
    /// `maxLineBytes` is dropped without being held whole, and only the lines whose `type` is `rate_limit_event`
    /// are decoded, one at a time.
    public static func parseStream(descriptor: Int32, now: Date) -> ClaudeCodeExtraction {
        var reader = StreamReader(now: now)
        BoundedInput.forEachLine(descriptor: descriptor, maxLineBytes: maxLineBytes) { line in
            guard namesEventType(line) else { return }
            reader.add(String(decoding: line, as: UTF8.self))
        }
        return reader.extraction
    }

    /// True when the line has `"type"`, then `:` and `"rate_limit_event"`, with only blanks between. The words
    /// in a text (a message that quotes an event, its quotes escaped) never match, so such a line is not decoded.
    static func namesEventType(_ line: Data) -> Bool {
        let value = Data(#""rate_limit_event""#.utf8)
        let key = Data(#""type""#.utf8)
        func isBlank(_ byte: UInt8) -> Bool { byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D }
        var from = line.startIndex
        while let found = line.range(of: value, in: from..<line.endIndex) {
            from = found.upperBound
            var index = found.lowerBound
            while index > line.startIndex, isBlank(line[index - 1]) { index -= 1 }
            guard index > line.startIndex, line[index - 1] == UInt8(ascii: ":") else { continue }
            index -= 1
            while index > line.startIndex, isBlank(line[index - 1]) { index -= 1 }
            if index - line.startIndex >= key.count, line[(index - key.count)..<index] == key { return true }
        }
        return false
    }

    /// The stream-json lines one by one.
    struct StreamReader {
        let now: Date
        var fiveHour: ClaudeCodeWindow?
        var sevenDay: ClaudeCodeWindow?
        var sawEvent = false
        var readOne = false

        init(now: Date) { self.now = now }

        mutating func add(_ line: String) {
            guard line.utf8.count <= maxLineBytes, namesEventType(Data(line.utf8)) else { return }
            // The decoded objects go with their line: a long stream of events never piles them up.
            let event = autoreleasepool { parseEvent(line, now: now) }
            switch event {
            case .notAnEvent:
                return
            case .unreadable:
                sawEvent = true
            case .windows(let five, let seven):
                sawEvent = true
                readOne = true
                if let five { fiveHour = five }
                if let seven { sevenDay = seven }
            }
        }

        var extraction: ClaudeCodeExtraction {
            if fiveHour != nil || sevenDay != nil {
                return .observed(ClaudeCodeObservation(source: .streamJSON, fiveHour: fiveHour, sevenDay: sevenDay))
            }
            // Events were read but gave neither window (another kind of limit only): nothing to record.
            if readOne { return .nothing }
            return sawEvent ? .formatChanged(.streamJSON) : .nothing
        }
    }

    /// The `transcript_path` of a status line JSON, when it is a non-empty string (`ClaudeReportEmail.transcript`
    /// then requires an absolute path).
    public static func transcriptPath(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data), let root = object as? [String: Any],
              let path = root["transcript_path"] as? String, !path.isEmpty else { return nil }
        return path
    }

    enum Event: Equatable {
        case notAnEvent
        case unreadable
        case windows(ClaudeCodeWindow?, ClaudeCodeWindow?)
    }

    static func parseEvent(_ line: String, now: Date) -> Event {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)),
              let root = object as? [String: Any], root["type"] as? String == "rate_limit_event" else { return .notAnEvent }
        guard let info = root["rate_limit_info"] as? [String: Any],
              let windows = info["unifiedWindows"] as? [String: Any] else { return .unreadable }
        var found: [ClaudeCodeWindow?] = []
        for key in ["five_hour", "seven_day"] {
            guard let value = windows[key] else { found.append(nil); continue }
            // A fraction: up to 2 is taken (a limit can be passed a little); more means the unit changed.
            guard let window = value as? [String: Any],
                  let utilization = UsageParser.number(window["utilization"]), utilization.isFinite,
                  utilization >= 0, utilization <= 2,
                  case .valid(let resets) = resetTime(window["resetsAt"], now: now) else { return .unreadable }
            found.append(ClaudeCodeWindow(percent: min(utilization * 100, 100), resetsAt: resets))
        }
        return .windows(found[0], found[1])
    }

    enum ResetTime: Equatable {
        /// Absent (nil) or a plausible time.
        case valid(Date?)
        case invalid
    }

    /// The earliest reset time taken (1 January 2020): anything before is not Unix seconds.
    static let earliestReset = Date(timeIntervalSince1970: 1_577_836_800)

    /// A reset time in Unix seconds. Absent is fine; a value that is not a number, or not a time in seconds
    /// (before 2020, or more than 400 days ahead, which also refuses milliseconds), is refused. A time already
    /// past is kept: an input relayed late may carry a window that has reset since, and it then counts as 0 %.
    static func resetTime(_ value: Any?, now: Date) -> ResetTime {
        guard let value, !(value is NSNull) else { return .valid(nil) }
        guard let seconds = UsageParser.number(value), seconds.isFinite else { return .invalid }
        let date = Date(timeIntervalSince1970: seconds.rounded())
        guard date >= earliestReset, date <= now.addingTimeInterval(400 * 24 * 3600) else { return .invalid }
        return .valid(date)
    }
}

/// The addresses reports are filed under: lower case, a plain address, 200 characters at most, so that it can
/// name a file as it is (no `/`, no leading dot, no space), its lock and its temporary file included (a file
/// name has 255 bytes at most).
public enum ClaudeReportEmail {
    public static let maxLength = 200

    private static let alphanumerics = Set("abcdefghijklmnopqrstuvwxyz0123456789")
    private static let localCharacters = alphanumerics.union("._%+-")
    private static let domainCharacters = alphanumerics.union("-")

    /// The address in lower case when it is a plain one: a local part of letters, digits and `._%+-` that starts
    /// with a letter or a digit, one `@`, then at least two labels of letters, digits and `-`. Otherwise nil.
    public static func normalize(_ text: String) -> String? {
        let email = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard email.utf8.count <= maxLength else { return nil }
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, let first = parts[0].first, alphanumerics.contains(first),
              parts[0].allSatisfy(localCharacters.contains) else { return nil }
        let labels = parts[1].split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty && $0.allSatisfy(domainCharacters.contains) }) else { return nil }
        return email
    }

    /// The address of the Claude Code folder in use: the `.claude.json` of `CLAUDE_CONFIG_DIR`, or of the
    /// default folder when the variable is not set (`~/.claude.json`, then `~/.claude/.claude.json`).
    public static func auto(environment: [String: String] = ProcessInfo.processInfo.environment,
                            home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        autoAccount(environment: environment, home: home)?.email
    }

    /// `.claude.json` keeps the history of every project: it may be large, never this large.
    public static let maxConfigBytes = 16 * 1024 * 1024

    /// The address and the Claude Code folder `auto` stands for. `.claude.json` is opened without following a
    /// link, must be the user's own regular file of 16 MiB at most, and only `oauthAccount.emailAddress` of it
    /// is decoded.
    public static func autoAccount(environment: [String: String] = ProcessInfo.processInfo.environment,
                                   home: URL = FileManager.default.homeDirectoryForCurrentUser)
        -> (email: String, configDirectory: String)? {
        let defaultDir = KeychainServiceName.normalize(home.appendingPathComponent(".claude").path)
        let directory: String
        let candidates: [String]
        if let dir = environment["CLAUDE_CONFIG_DIR"].map(KeychainServiceName.normalize), !dir.isEmpty, dir != defaultDir {
            directory = dir
            candidates = [(dir as NSString).appendingPathComponent(".claude.json")]
        } else {
            directory = defaultDir
            candidates = [home.appendingPathComponent(".claude.json").path, home.appendingPathComponent(".claude/.claude.json").path]
        }
        struct File: Decodable {
            struct OAuthAccount: Decodable { var emailAddress: String? }
            var oauthAccount: OAuthAccount?
        }
        for candidate in candidates {
            do throws(SecretFile.Failure) {
                let file = try SecretFile.readJSON(File.self, url: URL(fileURLWithPath: candidate), maxBytes: maxConfigBytes)
                guard let email = file.oauthAccount?.emailAddress.flatMap(normalize) else { return nil }
                return (email, directory)
            } catch {
                if error == .notFound { continue }
                return nil
            }
        }
        return nil
    }

    /// True when a status line's `transcript_path` lies in `<configDirectory>/projects/`, where Claude Code keeps
    /// the session history of that folder (https://code.claude.com/docs/en/env-vars, `CLAUDE_CONFIG_DIR`). The
    /// transcript must be an absolute path with no `.` or `..` in it (Claude Code writes it so), never resolved
    /// against the current folder. Paths are compared as written and with their links resolved: a transcript not
    /// created yet is placed by the folders above it that exist.
    public static func transcript(_ transcriptPath: String, isIn configDirectory: String) -> Bool {
        guard transcriptPath.hasPrefix("/"),
              !transcriptPath.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else { return false }
        let written = KeychainServiceName.normalize(transcriptPath)
        let projects = KeychainServiceName.normalize(configDirectory) + "/projects"
        let transcripts = [written, resolvingLinks(written)].compactMap { $0 }
        let folders = [projects, resolvingLinks(projects)].compactMap { $0 }
        return transcripts.contains { t in folders.contains { t.hasPrefix($0 + "/") } }
    }

    /// The path with its links resolved by the system (`realpath`) up to the deepest folder that exists, the
    /// names below it kept as written; nil when it cannot be resolved (a loop, a part that is not a folder).
    static func resolvingLinks(_ path: String) -> String? {
        var existing = path
        var missing: [String] = []
        while true {
            if let resolved = realpath(existing, nil) {
                defer { free(resolved) }
                return missing.reversed().reduce(String(cString: resolved)) { ($0 as NSString).appendingPathComponent($1) }
            }
            guard errno == ENOENT, existing != "/" else { return nil }
            missing.append((existing as NSString).lastPathComponent)
            existing = (existing as NSString).deletingLastPathComponent
        }
    }
}

/// The folder of the reports, `~/Library/Application Support/Brimline/claude-reports/`: one file per address,
/// `<address>.json`, readable by the user only (folder 0700, files 0600, written atomically).
public struct ClaudeReportStore: Sendable {
    public var directory: URL

    public init(directory: URL = BrimlinePaths().claudeReportsDirectory) {
        self.directory = directory
    }

    public func file(for email: String) -> URL { directory.appendingPathComponent("\(email).json") }

    public enum Failure: Error, Equatable, Sendable {
        /// The folder is a link, not a folder, or someone else's.
        case unsafeFolder
        case file(SecretFile.Failure)
        /// The file is not a report of this version, or not the report of its address.
        case notAReport
    }

    /// Reads one report: no link followed, owned by the user, 64 KiB at most, the address inside matching the file.
    public func load(_ email: String) throws(Failure) -> ClaudeCodeReport {
        try load(file: file(for: email), email: email)
    }

    public func load(file: URL, email: String) throws(Failure) -> ClaudeCodeReport {
        guard folderIsSafe(mayBeMissing: false) else { throw .unsafeFolder }
        let data: Data
        do { data = try SecretFile.read(url: file, maxBytes: ClaudeCodeReport.maxBytes) } catch { throw .file(error) }
        guard let report = try? JSONCoding.decoder().decode(ClaudeCodeReport.self, from: data),
              report.schemaVersion == ClaudeCodeReport.currentSchemaVersion, report.email == email else { throw .notAReport }
        return report
    }

    /// The reports of the folder: the address of each file whose name is a plain address, regular, the user's.
    /// Only names are listed here; nothing is opened.
    public func list() -> [(email: String, file: URL)] {
        guard folderIsSafe(mayBeMissing: false),
              let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        var found: [(String, URL)] = []
        for name in names.sorted() where name.hasSuffix(".json") && !name.hasPrefix(".") {
            let stem = String(name.dropLast(".json".count))
            guard let email = ClaudeReportEmail.normalize(stem), email == stem else { continue }
            let url = directory.appendingPathComponent(name)
            var info = stat()
            guard lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_uid == getuid() else { continue }
            found.append((email, url))
            if found.count >= 64 { break }
        }
        return found
    }

    /// Records one input for `email`: reads the report kept (if any), merges window by window, writes it back
    /// atomically. Returns the report written, nil when the input held nothing (and nothing was written).
    @discardableResult
    public func record(_ extraction: ClaudeCodeExtraction, email: String, now: Date = Date()) throws -> ClaudeCodeReport? {
        guard extraction != .nothing else { return nil }
        guard folderIsSafe(mayBeMissing: true, privateOnly: true) else { throw Failure.unsafeFolder }
        try createFolder()
        guard folderIsSafe(mayBeMissing: false, privateOnly: true) else { throw Failure.unsafeFolder }
        // Two sessions of one account may write at once: a lock per address, waited for a little, never forever.
        let lock = Lock(path: directory.appendingPathComponent(".\(email).lock").path)
        defer { lock.release() }
        let previous = try? load(email)
        let next = previous.map { $0.merged(with: extraction, at: now) }
            ?? ClaudeCodeReport.first(email: email, extraction: extraction, at: now)
        guard let next else { return nil }
        try JSONCoding.write(try JSONCoding.encoder().encode(next), to: file(for: email))
        return next
    }

    /// Creates the folder and the missing folders above it, each `0700`. A folder that exists is never changed.
    func createFolder() throws {
        var missing: [String] = []
        var path = directory.standardizedFileURL.path
        var info = stat()
        while path != "/", lstat(path, &info) != 0 {
            guard errno == ENOENT else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            missing.append(path)
            path = (path as NSString).deletingLastPathComponent
        }
        for folder in missing.reversed() where mkdir(folder, 0o700) != 0 && errno != EEXIST {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    /// The folder is a real folder (not a link) of the user's; with `mayBeMissing`, its absence is fine too. With
    /// `privateOnly`, a folder that others may read or write is refused: the command writes only in a folder of
    /// its own (`--dir ~` is refused, never turned to `0700`).
    func folderIsSafe(mayBeMissing: Bool, privateOnly: Bool = false) -> Bool {
        var info = stat()
        guard lstat(directory.path, &info) == 0 else { return mayBeMissing && errno == ENOENT }
        guard (info.st_mode & S_IFMT) == S_IFDIR && info.st_uid == getuid() else { return false }
        return !privateOnly || (info.st_mode & 0o077) == 0
    }

    /// An advisory lock (`flock`) on a file of its own, tried for half a second at most.
    final class Lock {
        private var descriptor: Int32

        init(path: String) {
            descriptor = open(path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard descriptor >= 0 else { return }
            for _ in 0..<50 {
                if flock(descriptor, LOCK_EX | LOCK_NB) == 0 { return }
                usleep(10_000)
            }
        }

        func release() {
            guard descriptor >= 0 else { return }
            flock(descriptor, LOCK_UN)
            close(descriptor)
            descriptor = -1
        }

        deinit { release() }
    }
}

extension ClaudeCodeObservation {
    init(source: ClaudeCodeReport.Source) {
        self.init(source: source, fiveHour: nil, sevenDay: nil)
    }
}
