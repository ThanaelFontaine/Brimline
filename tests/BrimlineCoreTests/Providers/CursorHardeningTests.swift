import Foundation
import Testing
@testable import BrimlineCore

/// Cursor, detection: three guarantees that the main suite did not pin down (found by mutating the
/// reader by hand: removing `mode=ro`, widening the size bound, or mislabelling an unreadable
/// database each left every test green). The databases are built by the tests, as in `CursorTests`.
@Suite("Cursor: read-only, size bound, unreadable database")
struct CursorHardeningTests {
    let now = date("2026-10-27T10:00:00Z")

    /// A copy of a live WAL database with its two log files, as Cursor leaves them while it runs,
    /// but with no other connection open on the copy: the reader is then the only one, the case where
    /// a read-write connection would checkpoint and delete the log files when it closes.
    func lonelyCopy(rows: [(String, Data?)]) throws -> (home: TemporaryHome, database: URL) {
        let source = try TemporaryHome()
        let live = try CursorTests.StateDatabase(in: source, rows: rows)
        defer { live.close() }
        let home = try TemporaryHome()
        let target = home.url.appendingPathComponent(CursorTests.relative)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        for suffix in ["", "-wal", "-shm"] {
            try FileManager.default.copyItem(atPath: live.url.path + suffix, toPath: target.path + suffix)
        }
        return (home, target)
    }

    @Test("Alone on the database, the reader still deletes nothing and writes nothing: no checkpoint, no log removed")
    func readOnlyForReal() throws {
        let (home, database) = try lonelyCopy(rows: [CursorTests.token(CursorTests.seedToken)])
        _ = home
        let wal = URL(fileURLWithPath: database.path + "-wal")
        let shm = URL(fileURLWithPath: database.path + "-shm")
        let mainBefore = try Data(contentsOf: database)
        let walBefore = try Data(contentsOf: wal)
        #expect(!walBefore.isEmpty)
        #expect(try CursorSession.classify(database: database) == .clear)
        #expect(FileManager.default.fileExists(atPath: wal.path))
        #expect(FileManager.default.fileExists(atPath: shm.path))
        #expect(try Data(contentsOf: database) == mainBefore)
        #expect(try Data(contentsOf: wal) == walBefore)
    }

    /// A token shaped like a JWT, padded to exactly `bytes` bytes.
    func token(bytes: Int) -> String {
        let head = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ4In0."
        return head + String(repeating: "S", count: bytes - head.utf8.count)
    }

    @Test("The size bound is exactly 16 KiB: a token of that size is plain, one byte more is not even copied")
    func sizeBound() throws {
        let limit = CursorSession.maxValueBytes
        #expect(limit == 16 * 1024)
        #expect(CursorSession.classify(value: Data(token(bytes: limit).utf8)) == .clear)
        for size in [limit + 1, 64 * 1024] {
            let (home, database) = try lonelyCopy(rows: [CursorTests.token(token(bytes: size))])
            _ = home
            #expect(try CursorSession.classify(database: database) == .unrecognized, "\(size) bytes")
        }
        let (home, database) = try lonelyCopy(rows: [CursorTests.token(token(bytes: limit))])
        _ = home
        #expect(try CursorSession.classify(database: database) == .clear)
    }

    @Test("A database that cannot be opened is a passing failure (unavailable), never a changed format")
    func unreadableDatabase() async throws {
        let home = try TemporaryHome()
        let database = try CursorTests.StateDatabase(in: home, rows: [CursorTests.token(CursorTests.seedToken)])
        defer { database.close() }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: database.url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: database.url.path) }
        let card = Account(provider: .cursor, source: database.url.path, email: nil, organization: nil, seatTier: nil,
                           keychainService: nil)
        guard case .failure(let status, let detail, _) = await CursorReader().read(account: card, now: now) else {
            Issue.record("expected a failure")
            return
        }
        #expect(status == .unavailable)
        #expect(detail == "state database busy")
    }

    @Test("Whatever stands at the -journal name (a link, a folder) keeps a classic database from being opened")
    func oddJournal() throws {
        let home = try TemporaryHome()
        let database = try CursorTests.StateDatabase(in: home, rows: [CursorTests.token(CursorTests.seedToken)], wal: false)
        defer { database.close() }
        let journal = URL(fileURLWithPath: database.url.path + "-journal")
        try FileManager.default.createSymbolicLink(at: journal, withDestinationURL: home.url.appendingPathComponent("nowhere"))
        #expect(throws: CursorSession.Failure.busy) { try CursorSession.classify(database: database.url) }
        try FileManager.default.removeItem(at: journal)
        try FileManager.default.createDirectory(at: journal, withIntermediateDirectories: false)
        #expect(throws: CursorSession.Failure.busy) { try CursorSession.classify(database: database.url) }
    }
}
