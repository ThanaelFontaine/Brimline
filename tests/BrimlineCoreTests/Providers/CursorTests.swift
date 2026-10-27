import Foundation
import SQLite3
import Testing
@testable import BrimlineCore

/// Cursor, detection and the sign-in database (the reading of the limits is in `CursorUsageTests`). The databases are built by the tests, in a temporary home, with
/// the schema VS Code gives `state.vscdb` (microsoft/vscode, `src/vs/base/parts/storage/node/storage.ts`:
/// `CREATE TABLE IF NOT EXISTS ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB)`), the key
/// and the encrypted prefix that CodexBar reads from Cursor (steipete/CodexBar at commit 5f93dc3,
/// `Sources/CodexBarCore/Providers/Cursor/CursorAppAuth.swift`: `cursorAuth/accessToken`,
/// `cursor-safe-storage:v1:`, and the place `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`).
/// Every value is invented: no real database, token or account is involved, and the real Cursor
/// folder is never opened.
@Suite("Cursor: detection and the sign-in database")
struct CursorTests {
    let now = date("2026-10-27T10:00:00Z")
    var on: BrimlineSettings {
        var settings = BrimlineSettings()
        settings.enabledProviders.append("cursor")
        return settings
    }

    /// No test of this suite reaches the network: a reader gets a client that is offline, or one that answers.
    static func offline() -> CursorFakeHTTP { .offline() }

    static let relative = "Library/Application Support/Cursor/User/globalStorage/state.vscdb"
    /// An unsigned JWT with invented claims (`sub` auth0|user_01SEED, `exp` in 2030), the shape of Cursor's access token.
    static let seedToken = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJhdXRoMHx1c2VyXzAxU0VFRCIsImV4cCI6MTg5MzQ1NjAwMH0.SEED-CURSOR-SIGNATURE-7c21"
    static let seedRefresh = "SEED-CURSOR-REFRESH-TOKEN-4e8b"
    static let encrypted = "cursor-safe-storage:v1:" + Data("v10-SEED-CIPHERTEXT-0123456789abcdef".utf8).base64EncodedString()

    /// A Cursor state database in a home folder, kept open (as the app keeps it). Two modes:
    ///
    /// - classic (`wal: false`, the default of SQLite, `journal_mode=delete`): the mode VS Code uses.
    ///   Its `SQLiteStorageDatabase` (microsoft/vscode, `src/vs/base/parts/storage/node/storage.ts`,
    ///   lines 345 to 347) runs `PRAGMA journal_mode=WAL` only when its `useWAL` option is true, and
    ///   the three calls of `src/vs/platform/storage/electron-main/storageMain.ts` (lines 305, 378 and
    ///   439) never pass it. No `-wal` and no `-shm` ever exist next to such a database. Cursor itself
    ///   is closed source and not checked: this is the mode of its upstream.
    /// - WAL (`wal: true`): the other mode Cursor could be in, kept open so that `-wal` and `-shm`
    ///   exist. `closeAndRemoveLogs()` gives a closed Cursor.
    final class StateDatabase {
        let url: URL
        private var handle: OpaquePointer?

        init(in home: TemporaryHome, rows: [(String, Data?)] = [], table: Bool = true, wal: Bool = true) throws {
            url = home.url.appendingPathComponent(CursorTests.relative)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard sqlite3_open(url.path, &handle) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
            if wal {
                try exec("PRAGMA journal_mode=WAL")
                try exec("PRAGMA wal_autocheckpoint=0")
            }
            try exec(table ? "CREATE TABLE IF NOT EXISTS ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB)"
                           : "CREATE TABLE Unrelated (key TEXT, value BLOB)")
            for (key, value) in rows { try put(key, value) }
        }

        deinit { close() }

        func exec(_ sql: String) throws {
            guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
        }

        func put(_ key: String, _ value: Data?, asText: Bool = false) throws {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, "INSERT INTO ItemTable (key, value) VALUES (?1, ?2)", -1, &statement, nil) == SQLITE_OK else {
                throw CocoaError(.fileWriteUnknown)
            }
            defer { sqlite3_finalize(statement) }
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(statement, 1, key, -1, transient)
            if let value {
                if asText {
                    sqlite3_bind_text(statement, 2, String(decoding: value, as: UTF8.self), -1, transient)
                } else {
                    _ = value.withUnsafeBytes { sqlite3_bind_blob(statement, 2, $0.baseAddress, Int32(value.count), transient) }
                }
            } else {
                sqlite3_bind_null(statement, 2)
            }
            guard sqlite3_step(statement) == SQLITE_DONE else { throw CocoaError(.fileWriteUnknown) }
        }

        func checkpoint() throws { try exec("PRAGMA wal_checkpoint(TRUNCATE)") }

        func close() {
            if let handle { sqlite3_close(handle) }
            handle = nil
        }

        /// What a closed Cursor leaves: the database alone. (Cursor's own SQLite removes the log files
        /// when its last connection closes; the system one keeps them, so the test removes them.)
        func closeAndRemoveLogs() throws {
            try? checkpoint()
            close()
            for suffix in ["-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
        }
    }

    static func token(_ text: String) -> (String, Data?) { ("cursorAuth/accessToken", Data(text.utf8)) }

    func card(_ home: TemporaryHome) -> Account {
        Account(provider: .cursor, source: home.path(Self.relative), email: nil, organization: nil, seatTier: nil,
                keychainService: nil)
    }

    func reading(_ rows: [(String, Data?)], table: Bool = true, wal: Bool = true,
                 http: CursorFakeHTTP = .offline()) async throws -> ProviderReading {
        let home = try TemporaryHome()
        let database = try StateDatabase(in: home, rows: rows, table: table, wal: wal)
        defer { database.close() }
        return await CursorReader(http: http).read(account: card(home), now: now)
    }

    func expectLimits(_ reading: ProviderReading, sourceLocation: SourceLocation = #_sourceLocation) {
        guard case .limits(let limits, _) = reading else {
            Issue.record("expected the limits, got \(reading)", sourceLocation: sourceLocation)
            return
        }
        #expect(!limits.isEmpty, sourceLocation: sourceLocation)
    }

    func expectNotReadable(_ reading: ProviderReading, sourceLocation: SourceLocation = #_sourceLocation) {
        guard case .notReadable(let reason) = reading else {
            Issue.record("expected not_readable, got \(reading)", sourceLocation: sourceLocation)
            return
        }
        #expect(reason == .protectedSignIn, sourceLocation: sourceLocation)
    }

    func expectFailure(_ reading: ProviderReading, _ status: AccountStatus, sourceLocation: SourceLocation = #_sourceLocation) {
        guard case .failure(let got, _, _) = reading else {
            Issue.record("expected a failure, got \(reading)", sourceLocation: sourceLocation)
            return
        }
        #expect(got == status, sourceLocation: sourceLocation)
    }

    // MARK: Registry and discovery

    @Test("Cursor is in the registry, last, and calls one URL")
    func registry() {
        #expect(Providers.all.map(\.provider) == [.claude, .chatgpt, .gemini, .grok, .cursor])
        #expect(CursorReader(http: Self.offline()).allowedURLs == [URL(string: "https://cursor.com/api/usage-summary")!])
        #expect(Providers.isSupported(.cursor))
    }

    @Test("Cursor is off by default: its folder is not even looked for")
    func offByDefault() throws {
        let home = try TemporaryHome()
        let database = try StateDatabase(in: home, rows: [Self.token(Self.seedToken)])
        defer { database.close() }
        #expect(!BrimlineSettings().isEnabled(.cursor))
        #expect(Providers.discover(home: home.url, settings: BrimlineSettings()).isEmpty)
        #expect(Providers.discover(home: home.url, settings: on).map(\.provider) == [.cursor])
    }

    @Test("One card when the state database is a regular file, none otherwise, and the card holds no identity")
    func discovery() throws {
        let home = try TemporaryHome()
        #expect(CursorReader(http: Self.offline()).discover(home: home.url, settings: on).isEmpty)

        // The app's folder without its database, and a folder where the database should be.
        try home.mkdir("Library/Application Support/Cursor/User/globalStorage")
        #expect(CursorReader(http: Self.offline()).discover(home: home.url, settings: on).isEmpty)
        try home.mkdir(Self.relative)
        #expect(CursorReader(http: Self.offline()).discover(home: home.url, settings: on).isEmpty)
        try FileManager.default.removeItem(at: home.url.appendingPathComponent(Self.relative))

        try home.write(Self.relative, "not even a database: only its presence counts here")
        let accounts = CursorReader(http: Self.offline()).discover(home: home.url, settings: on)
        #expect(accounts.count == 1)
        let found = try #require(accounts.first)
        #expect(found.provider == .cursor)
        #expect(found.source == home.path(Self.relative))
        #expect(found.id == "cursor:\(home.path(Self.relative))")
        #expect(found.email == nil && found.organization == nil && found.seatTier == nil && found.keychainService == nil)
        // The card is named Cursor, not after the database file.
        #expect(found.folderName == "Cursor")
    }

    @Test("Only that one place is considered: no other Cursor file, no VS Code, no folder added by hand")
    func exactPlace() throws {
        let home = try TemporaryHome()
        try home.write("Library/Application Support/Cursor/User/state.vscdb", "x")
        try home.write("Library/Application Support/Code/User/globalStorage/state.vscdb", "x")
        try home.write(".cursor/state.vscdb", "x")
        try home.write(".config/Cursor/User/globalStorage/state.vscdb", "x")
        var settings = on
        settings.extraFolders = [home.path("Library/Application Support/Cursor/User/globalStorage")]
        settings.extraCodexFolders = [home.path("Library/Application Support/Cursor")]
        #expect(CursorReader(http: Self.offline()).discover(home: home.url, settings: settings).isEmpty)
    }

    @Test("A link where the database should be is not a card, and a card pointing elsewhere is refused")
    func links() async throws {
        let home = try TemporaryHome()
        let elsewhere = try TemporaryHome()
        let real = try StateDatabase(in: elsewhere, rows: [Self.token(Self.seedToken)])
        defer { real.close() }
        try home.mkdir("Library/Application Support/Cursor/User/globalStorage")
        let link = home.url.appendingPathComponent(Self.relative)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real.url)
        #expect(CursorReader(http: Self.offline()).discover(home: home.url, settings: on).isEmpty)

        // Even handed the link as a card, nothing is opened through it.
        let direct = Account(provider: .cursor, source: link.path, email: nil, organization: nil, seatTier: nil, keychainService: nil)
        expectFailure(await CursorReader(http: Self.offline()).read(account: direct, now: now), .unavailable)
        // A card for any other file name is never read.
        let other = Account(provider: .cursor, source: real.url.deletingLastPathComponent().appendingPathComponent("storage.json").path,
                            email: nil, organization: nil, seatTier: nil, keychainService: nil)
        expectFailure(await CursorReader(http: Self.offline()).read(account: other, now: now), .unavailable)
    }

    @Test("Discovery opens nothing: a database that cannot be read still gives its card")
    func discoveryOpensNothing() throws {
        let home = try TemporaryHome()
        try home.write(Self.relative, "SEED-DATABASE-BAIT")
        let file = home.url.appendingPathComponent(Self.relative)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path) }
        #expect(CursorReader(http: Self.offline()).discover(home: home.url, settings: on).count == 1)
    }

    // MARK: What the token row holds

    @Test("A plain token is used for the one request, and the answer gives the limits")
    func clearToken() async throws {
        let http = try CursorFakeHTTP.answering()
        expectLimits(try await reading([Self.token(Self.seedToken)], http: http))
        #expect(http.requests.count == 1)
    }

    @Test("A token written as UTF-16 text in a BLOB, or as TEXT, is a plain token too")
    func encodings() async throws {
        let utf16 = Data(Self.seedToken.utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] })
        expectLimits(try await reading([("cursorAuth/accessToken", utf16)], http: try .answering()))
        let home = try TemporaryHome()
        let database = try StateDatabase(in: home)
        defer { database.close() }
        try database.put("cursorAuth/accessToken", Data(Self.seedToken.utf8), asText: true)
        expectLimits(await CursorReader(http: try CursorFakeHTTP.answering()).read(account: card(home), now: now))
    }

    @Test("A token that is still in the write-ahead log is seen: the database is read as the app sees it")
    func tokenInTheLog() async throws {
        let home = try TemporaryHome()
        let database = try StateDatabase(in: home)
        defer { database.close() }
        try database.checkpoint()
        // Written after the checkpoint with no new one: the main file does not hold it, the log does.
        try database.put("cursorAuth/accessToken", Data(Self.seedToken.utf8))
        let main = try Data(contentsOf: database.url)
        #expect(!String(decoding: main, as: UTF8.self).contains("SEED-CURSOR-SIGNATURE"))
        let wal = try Data(contentsOf: URL(fileURLWithPath: database.url.path + "-wal"))
        #expect(String(decoding: wal, as: UTF8.self).contains("SEED-CURSOR-SIGNATURE"))
        expectLimits(await CursorReader(http: try CursorFakeHTTP.answering()).read(account: card(home), now: now))
    }

    @Test("A value Cursor encrypted is never read nor decrypted: protected sign-in")
    func encryptedToken() async throws {
        expectNotReadable(try await reading([Self.token(Self.encrypted)]))
    }

    @Test("No row, an empty value, a null value and an unrelated row all leave nothing to read: protected sign-in")
    func absentToken() async throws {
        expectNotReadable(try await reading([]))
        expectNotReadable(try await reading([("cursorAuth/accessToken", Data())]))
        expectNotReadable(try await reading([("cursorAuth/accessToken", nil)]))
        expectNotReadable(try await reading([("cursorAuth/accessToken", Data("   ".utf8))]))
        // Only the token row is looked at: a refresh token, or a look-alike key, is not it.
        expectNotReadable(try await reading([
            ("cursorAuth/refreshToken", Data(Self.seedToken.utf8)),
            ("cursorAuth/accessToken ", Data(Self.seedToken.utf8)),
            ("cursorAuth/accessTokenX", Data(Self.seedToken.utf8)),
            ("cursorAuth/cachedEmail", Data("someone@example.com".utf8)),
        ]))
    }

    @Test("Something that is neither a JWT nor an encrypted value is a changed format, never a token")
    func unrecognizedToken() async throws {
        expectFailure(try await reading([Self.token("not a token at all")]), .formatChanged)
        expectFailure(try await reading([Self.token("a.b")]), .formatChanged)
        expectFailure(try await reading([Self.token("a..c")]), .formatChanged)
        expectFailure(try await reading([Self.token("v10" + String(repeating: "A", count: 64))]), .formatChanged)
        expectFailure(try await reading([Self.token(Self.seedToken + "\nX-Injected: 1")]), .formatChanged)
        // A value that is not even text, and one that is far too large for a token.
        expectFailure(try await reading([("cursorAuth/accessToken", Data([0xFF, 0xFE, 0x00, 0xC3, 0x28]))]), .formatChanged)
        expectFailure(try await reading([Self.token(String(repeating: "A", count: 64 * 1024))]), .formatChanged)
    }

    @Test("A file that is not a database, or a database with no ItemTable, is a changed format")
    func notADatabase() async throws {
        expectFailure(try await reading([], table: false), .formatChanged)

        let home = try TemporaryHome()
        try home.write(Self.relative, String(repeating: "this is plain text, not an SQLite header. ", count: 40))
        try home.write(Self.relative + "-wal", "")
        try home.write(Self.relative + "-shm", "")
        expectFailure(await CursorReader(http: Self.offline()).read(account: card(home), now: now), .formatChanged)
    }

    // MARK: The classic journal (VS Code's mode), and the header that tells the two modes apart

    @Test("A database in the classic journal mode (no -wal, no -shm ever) is read: plain token, encrypted, absent")
    func classicJournal() async throws {
        expectLimits(try await reading([Self.token(Self.seedToken)], wal: false, http: try .answering()))
        expectNotReadable(try await reading([Self.token(Self.encrypted)], wal: false))
        expectNotReadable(try await reading([], wal: false))
        expectFailure(try await reading([Self.token("not a token at all")], wal: false), .formatChanged)
        expectFailure(try await reading([], table: false, wal: false), .formatChanged)
    }

    @Test("In the classic mode, with the app's connection open, nothing is created and nothing changes")
    func classicJournalCreatesNothing() async throws {
        let home = try TemporaryHome()
        let database = try StateDatabase(in: home, rows: [Self.token(Self.seedToken)], wal: false)
        defer { database.close() }
        let folder = database.url.deletingLastPathComponent()
        #expect(try Self.names(in: folder).map { ($0 as NSString).lastPathComponent } == ["state.vscdb"])
        let before = try Self.listing(of: home.url)
        let service = UsageService(readers: [CursorReader(http: Self.offline())])
        let accounts = Providers.discover(readers: service.readers, home: home.url, settings: on)
        for _ in 0..<3 { _ = await service.refresh(accounts: accounts, settings: on, previous: nil, now: now, force: true) }
        #expect(try Self.listing(of: home.url) == before)
        #expect(try Self.names(in: folder).map { ($0 as NSString).lastPathComponent } == ["state.vscdb"])
    }

    @Test("In the classic mode, alone on the database, the reader writes nothing and creates no file")
    func classicJournalReadOnly() throws {
        let source = try TemporaryHome()
        let live = try StateDatabase(in: source, rows: [Self.token(Self.seedToken)], wal: false)
        defer { live.close() }
        let home = try TemporaryHome()
        let target = home.url.appendingPathComponent(Self.relative)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: live.url.path, toPath: target.path)
        let before = try Self.listing(of: home.url)
        #expect(try CursorSession.classify(database: target) == .clear)
        #expect(try Self.listing(of: home.url) == before)
    }

    @Test("A -journal file next to a classic database means a write in progress: nothing is opened, busy, nothing is created")
    func hotJournal() async throws {
        let home = try TemporaryHome()
        let database = try StateDatabase(in: home, rows: [Self.token(Self.seedToken)], wal: false)
        defer { database.close() }
        try home.write(Self.relative + "-journal", "a write is going on")
        let before = try Self.listing(of: home.url)
        #expect(throws: CursorSession.Failure.busy) { try CursorSession.classify(database: database.url) }
        // The answer is a passing failure to try again, never a verdict on the sign-in.
        guard case .failure(let status, let detail, _) = await CursorReader(http: Self.offline()).read(account: card(home), now: now) else {
            Issue.record("expected a failure")
            return
        }
        #expect(status == .unavailable)
        #expect(detail == "state database busy")
        #expect(try Self.listing(of: home.url) == before)
        // Even an empty journal, which SQLite alone would ignore, keeps the reader from opening.
        try FileManager.default.removeItem(atPath: database.url.path + "-journal")
        try home.write(Self.relative + "-journal", "")
        #expect(throws: CursorSession.Failure.busy) { try CursorSession.classify(database: database.url) }
        // Once the journal is gone, the database is read again.
        try FileManager.default.removeItem(atPath: database.url.path + "-journal")
        #expect(try CursorSession.classify(database: database.url) == .clear)
    }

    @Test("The journal mode comes from bytes 18 and 19 of the header: 2 is WAL, 1 is the classic journal")
    func journalMode() throws {
        let home = try TemporaryHome()
        let wal = try StateDatabase(in: home, rows: [Self.token(Self.seedToken)])
        defer { wal.close() }
        #expect(try CursorSession.journalMode(of: wal.url) == .wal)
        let other = try TemporaryHome()
        let classic = try StateDatabase(in: other, rows: [Self.token(Self.seedToken)], wal: false)
        defer { classic.close() }
        #expect(try CursorSession.journalMode(of: classic.url) == .rollback)
    }

    @Test("A WAL database with no log files stays 'Cursor is closed', even if the header is all that is checked")
    func walHeaderNeedsLogs() async throws {
        let home = try TemporaryHome()
        let database = try StateDatabase(in: home, rows: [Self.token(Self.seedToken)])
        try database.closeAndRemoveLogs()
        #expect(try CursorSession.journalMode(of: database.url) == .wal)
        #expect(throws: CursorSession.Failure.logFilesMissing) { try CursorSession.classify(database: database.url) }
    }

    @Test("A header that is not SQLite's, too short, or with another version number is a changed format")
    func badHeaders() async throws {
        var valid = Data("SQLite format 3".utf8) + Data([0]) + Data([0x10, 0x00, 1, 1]) + Data(repeating: 0, count: 80)
        func reading(of bytes: Data) async throws -> ProviderReading {
            let home = try TemporaryHome()
            try FileManager.default.createDirectory(at: home.url.appendingPathComponent(Self.relative).deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try bytes.write(to: home.url.appendingPathComponent(Self.relative))
            return await CursorReader(http: Self.offline()).read(account: card(home), now: now)
        }
        expectFailure(try await reading(of: Data()), .formatChanged)
        expectFailure(try await reading(of: Data(valid.prefix(19))), .formatChanged)
        valid[18] = 3; valid[19] = 3
        expectFailure(try await reading(of: valid), .formatChanged)
        valid[18] = 0; valid[19] = 0
        expectFailure(try await reading(of: valid), .formatChanged)
        valid[0] = UInt8(ascii: "X"); valid[18] = 1; valid[19] = 1
        expectFailure(try await reading(of: valid), .formatChanged)
    }

    @Test("A database that is gone since discovery is a passing failure, not a verdict on the sign-in")
    func gone() async throws {
        let home = try TemporaryHome()
        guard case .failure(.unavailable, _, _) = await CursorReader(http: Self.offline()).read(account: card(home), now: now) else {
            Issue.record("expected unavailable")
            return
        }
    }

    // MARK: Nothing is created, nothing is written

    @Test("A WAL database without -wal and -shm (Cursor is closed) is not opened and nothing is created")
    func logFilesMissing() async throws {
        let home = try TemporaryHome()
        let database = try StateDatabase(in: home, rows: [Self.token(Self.seedToken)])
        try database.closeAndRemoveLogs()
        let shm = database.url.path + "-shm", wal = database.url.path + "-wal"
        #expect(!FileManager.default.fileExists(atPath: wal) && !FileManager.default.fileExists(atPath: shm))
        let before = try Self.listing(of: home.url)

        expectNotReadable(await CursorReader(http: Self.offline()).read(account: card(home), now: now))
        // One of the two is not enough either.
        try home.write(Self.relative + "-wal", "")
        expectNotReadable(await CursorReader(http: Self.offline()).read(account: card(home), now: now))
        try FileManager.default.removeItem(atPath: wal)
        try home.write(Self.relative + "-shm", "")
        expectNotReadable(await CursorReader(http: Self.offline()).read(account: card(home), now: now))
        try FileManager.default.removeItem(atPath: shm)
        #expect(try Self.listing(of: home.url) == before)
    }

    @Test("A link standing for -wal or -shm is refused, and the database is not opened through it")
    func linkedLogFiles() async throws {
        let home = try TemporaryHome()
        let database = try StateDatabase(in: home, rows: [Self.token(Self.seedToken)])
        defer { database.close() }
        let wal = URL(fileURLWithPath: database.url.path + "-wal")
        let moved = home.url.appendingPathComponent("moved-wal")
        try FileManager.default.moveItem(at: wal, to: moved)
        try FileManager.default.createSymbolicLink(at: wal, withDestinationURL: moved)
        expectFailure(await CursorReader(http: Self.offline()).read(account: card(home), now: now), .unavailable)
    }

    @Test("A database of someone else is refused")
    func wrongOwner() throws {
        let home = try TemporaryHome()
        let database = try StateDatabase(in: home, rows: [Self.token(Self.seedToken)])
        defer { database.close() }
        #expect(throws: CursorSession.Failure.wrongOwner) {
            try CursorSession.classify(database: database.url, owner: getuid() &+ 1)
        }
        #expect(try CursorSession.classify(database: database.url) == .clear)
    }

    @Test("The database is read only: its bytes, its log and its dates do not change, and no file appears")
    func homeStaysAsItWas() async throws {
        let home = try TemporaryHome()
        let database = try StateDatabase(in: home, rows: [Self.token(Self.seedToken), ("other", Data("x".utf8))])
        defer { database.close() }
        let wal = database.url.path + "-wal"
        let names = try Self.names(in: home.url)
        let files = [database.url.path, wal]
        func snapshot() throws -> [String] {
            try files.map { path in
                let attributes = try FileManager.default.attributesOfItem(atPath: path)
                return "\(path)|\(attributes[.size] ?? 0)|\(attributes[.modificationDate] ?? Date())|\(try Data(contentsOf: URL(fileURLWithPath: path)).base64EncodedString())"
            }
        }
        let before = try snapshot()
        let service = UsageService(readers: [CursorReader(http: Self.offline())])
        let accounts = Providers.discover(readers: service.readers, home: home.url, settings: on)
        for _ in 0..<3 { _ = await service.refresh(accounts: accounts, settings: on, previous: nil, now: now, force: true) }
        #expect(try snapshot() == before)
        #expect(try Self.names(in: home.url) == names)

        // The statement is a single read: the reader cannot write, even asked to.
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOFOLLOW
        #expect(sqlite3_open_v2("file:\(CursorSession.resolvedFolder(of: database.url).path)/state.vscdb?mode=ro", &handle, flags, nil) == SQLITE_OK)
        #expect(sqlite3_exec(handle, "INSERT INTO ItemTable (key, value) VALUES ('x', 'y')", nil, nil, nil) == SQLITE_READONLY)
        sqlite3_close(handle)
    }

    /// Every path under the folder with its size and modification date, and the bytes of each file.
    static func listing(of root: URL) throws -> [String] {
        let fm = FileManager.default
        var rows: [String] = []
        for case let url as URL in fm.enumerator(at: root, includingPropertiesForKeys: nil)! {
            let attributes = try fm.attributesOfItem(atPath: url.path)
            let content = (attributes[.type] as? FileAttributeType) == .typeRegular ? try Data(contentsOf: url).base64EncodedString() : ""
            rows.append("\(url.path)|\(attributes[.size] ?? 0)|\(attributes[.modificationDate] ?? Date())|\(content)")
        }
        return rows.sorted()
    }

    static func names(in root: URL) throws -> [String] {
        (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!.allObjects as! [URL]).map(\.path).sorted()
    }

    // MARK: Service, consent and leaks

    @Test("Turned off, or marked \"Do not read\", Cursor is not read at all: the database is not opened")
    func consent() async throws {
        let home = try TemporaryHome()
        let database = try StateDatabase(in: home, rows: [Self.token(Self.encrypted)])
        defer { database.close() }
        let card = card(home)
        let service = UsageService(readers: [CursorReader(http: Self.offline())])
        let off = await service.refresh(account: card, settings: BrimlineSettings(), previous: nil, now: now, force: true)
        #expect(off.status == .pending && off.checkedAt == nil && off.reason == nil)
        var unread = on
        unread.unreadAccounts = [card.id]
        let skipped = await service.refresh(account: card, settings: unread, previous: nil, now: now, force: true)
        #expect(skipped.status == .pending && skipped.checkedAt == nil && skipped.reason == nil)
        // On, the same account is read.
        let read = await service.refresh(account: card, settings: on, previous: nil, now: now, force: true)
        #expect(read.status == .notReadable && read.reason == .protectedSignIn && read.checkedAt == now)
    }

    @Test("The service keeps the limits of a plain token, and a network failure is a passing failure with a growing delay")
    func serviceStates() async throws {
        let home = try TemporaryHome()
        let database = try StateDatabase(in: home, rows: [Self.token(Self.seedToken)])
        defer { database.close() }
        let service = UsageService(readers: [CursorReader(http: try CursorFakeHTTP.answering())])
        let usage = await service.refresh(account: card(home), settings: on, previous: nil, now: now)
        #expect(usage.status == .ok)
        #expect(usage.limits.count == 3 && usage.fetchedAt == now && usage.checkedAt == now)
        #expect(usage.retryAfter == nil && usage.failureCount == 0)

        let down = UsageService(readers: [CursorReader(http: Self.offline())])
        let failed = await down.refresh(account: card(home), settings: on, previous: usage, now: now.addingTimeInterval(900), force: true)
        #expect(failed.status == .unavailable && failed.detail == "network")
        #expect(failed.failureCount == 1 && failed.retryAfter != nil)
        // The last numbers stay, and say how old they are.
        #expect(failed.limits == usage.limits && failed.fetchedAt == now)
    }

    @Test("The seeded token and refresh token are found nowhere in the cache, the settings, the JSON and the MCP answers")
    func seeds() async throws {
        let home = try TemporaryHome()
        let database = try StateDatabase(in: home, rows: [
            Self.token(Self.seedToken),
            ("cursorAuth/refreshToken", Data(Self.seedRefresh.utf8)),
            ("cursorAuth/cachedEmail", Data("someone@example.com".utf8)),
        ])
        defer { database.close() }
        // The answer sets a cookie of its own, which no output may hold either.
        let http = try CursorFakeHTTP.answering(headers: ["Set-Cookie": "WorkosCursorSessionToken=SEED-SET-COOKIE-91ac; Path=/"])
        let service = UsageService(readers: [CursorReader(http: http)])
        let accounts = Providers.discover(readers: service.readers, home: home.url, settings: on)
        let snapshot = await service.refresh(accounts: accounts, settings: on, previous: nil, now: now, force: true)
        #expect(snapshot.accounts.first?.status == .ok)

        let paths = BrimlinePaths(home: home.url)
        try UsageCache(file: paths.cacheFile).save(snapshot)
        var settings = on
        settings.labels = [accounts[0].id: "Cursor work"]
        try SettingsStore(file: paths.settingsFile).save(settings)
        var outputs: [String] = [
            String(decoding: try Data(contentsOf: paths.cacheFile), as: UTF8.self),
            String(decoding: try Data(contentsOf: paths.settingsFile), as: UTF8.self),
            AgentUsageReport(snapshot: snapshot, settings: settings, source: "live", now: now, home: home.url).jsonString(),
            String(describing: snapshot),
        ]
        let finalSettings = settings
        let server = MCPServer(version: "0.0.0", load: { (snapshot, finalSettings) }, now: { now }, home: home.url)
        for tool in ["list_accounts", "get_usage", "best_account"] {
            let arguments = tool == "list_accounts" ? "{}" : #"{"provider":"cursor"}"#
            outputs.append(try #require(server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"\#(tool)","arguments":\#(arguments)}}"#)))
        }
        let seeds = [Self.seedToken, "SEED-CURSOR-SIGNATURE", Self.seedRefresh, "someone@example.com", "user_01SEED", "SEED-SET-COOKIE-91ac", "WorkosCursorSessionToken"]
        for text in outputs {
            for seed in seeds { #expect(!text.contains(seed), "\(seed) found in an output") }
        }
        let report = AgentUsageReport(snapshot: snapshot, settings: settings, source: "live", now: now, home: home.url)
        #expect(report.accounts.first?.source == "~/" + Self.relative)
        #expect(report.accounts.first?.provider == "cursor")
    }

    // MARK: Sentences

    @Test("The sentence is exact, in English and French, and never uses a long dash")
    func sentences() {
        let account = Account(provider: .cursor, source: "/opt/box/you/" + Self.relative, email: nil, organization: nil,
                              seatTier: nil, keychainService: nil)
        let protected = AccountUsage(account: account, status: .notReadable, reason: .protectedSignIn)
        let en = "Cursor protects its sign-in on this Mac: Brimline does not read it. Usage is on cursor.com, Dashboard, Usage."
        let fr = "Cursor protège sa connexion sur ce Mac : Brimline ne la lit pas. L'usage est sur cursor.com, Dashboard, Usage."
        #expect(Strings(.en).message(for: protected) == en)
        #expect(Strings(.fr).message(for: protected) == fr)
        for text in [en, fr] { #expect(!text.contains("\u{2014}") && !text.contains("\u{2013}")) }
        // The other states keep the generic messages.
        for status in [AccountStatus.pending, .unavailable, .formatChanged] {
            #expect(Strings(.en).message(for: AccountUsage(account: account, status: status)) == Strings(.en).statusMessage(status))
        }
        #expect(Strings(.en).message(for: AccountUsage(account: account, status: .ok)) == nil)
    }

    @Test("The agent report and the MCP answer carry the sentence and the reason of a protected sign-in")
    func agentsGetTheSentence() throws {
        let account = Account(provider: .cursor, source: "/opt/box/you/" + Self.relative, email: nil, organization: nil,
                              seatTier: nil, keychainService: nil)
        let usage = AccountUsage(account: account, status: .notReadable, reason: .protectedSignIn)
        let snapshot = UsageSnapshot(generatedAt: now, accounts: [usage])
        let settings = on
        let report = AgentUsageReport(snapshot: snapshot, settings: settings, source: "cache", now: now,
                                      home: URL(fileURLWithPath: "/opt/box/you"))
        #expect(report.accounts[0].message == Strings(.en).cursorProtectedMessage)
        #expect(report.accounts[0].reason == "protected_sign_in")
        #expect(report.accounts[0].source == "~/" + Self.relative)
        let server = MCPServer(version: "0.0.0", load: { (snapshot, settings) }, now: { now }, home: URL(fileURLWithPath: "/opt/box/you"))
        let line = try #require(server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_usage","arguments":{"provider":"cursor"}}}"#))
        #expect(line.contains("protected_sign_in"))
        #expect(line.contains("Cursor protects its sign-in"))
    }
}
