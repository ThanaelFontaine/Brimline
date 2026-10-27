import Foundation
import SQLite3

/// What Cursor's own database says about the sign-in, and nothing more: the value of
/// `cursorAuth/accessToken` is looked at only to be classified, then dropped. It is never kept, never
/// sent and never returned.
///
/// The database is `state.vscdb`, the SQLite file of the Cursor app. It is opened read-only, without
/// following a link, and nothing is ever created in Cursor's folder. The journal mode, written in the
/// file header (bytes 18 and 19: 2 is WAL, 1 is the classic rollback journal), says what that takes:
///
/// - WAL: only if its log files (`-wal` and `-shm`) already exist, because without them SQLite could
///   create them (sqlite.org/wal.html, "Read-Only Databases").
/// - Classic journal: nothing else is needed, a read-only opening creates no file; but a `-journal`
///   file next to the database means a write is going on, and nothing is opened until it is gone.
///
/// VS Code, which Cursor derives from, does not turn WAL on (`SQLiteStorageDatabase` in
/// `src/vs/base/parts/storage/node/storage.ts` runs `PRAGMA journal_mode=WAL` only when `useWAL` is
/// true, and the three calls of `src/vs/platform/storage/electron-main/storageMain.ts` never pass it),
/// so the classic journal is the likely case; both are handled. `immutable=1` is never used (it would
/// ignore a token still in a log or a journal: sqlite.org/uri.html), and the file is never copied.
enum CursorSession {
    /// The one row looked up.
    static let tokenKey = "cursorAuth/accessToken"
    /// The prefix Cursor puts on a value it encrypts with the Keychain item "Cursor Safe Storage"
    /// (seen by CodexBar, `CursorAppAuth.swift`): such a value is never read nor decrypted.
    static let encryptedPrefix = "cursor-safe-storage:"
    /// A token is a JWT of about a kilobyte: a bigger value is not one, and is not even copied.
    static let maxValueBytes = 16 * 1024

    /// What the token row holds.
    enum Kind: Equatable, Sendable {
        /// A plain JWT: the sign-in can be read.
        case clear
        /// A value Cursor encrypted with its Keychain item.
        case encrypted
        /// No row, an empty value or a null one: signed out, or the sign-in is kept elsewhere.
        case absent
        /// Something else than a JWT or an encrypted value (the format changed).
        case unrecognized
    }

    enum Failure: Error, Equatable, Sendable {
        /// No database at this path.
        case notFound
        /// A link, a folder or any file that is not a regular file (the database or a log file).
        case notRegularFile
        /// The database belongs to someone else.
        case wrongOwner
        /// The database is in WAL mode and `-wal` or `-shm` is missing (Cursor is closed): nothing is
        /// opened, so that SQLite creates nothing.
        case logFilesMissing
        /// The database is busy, locked, being written (a `-journal` file is there) or could not be
        /// read: a new attempt can succeed.
        case busy
        /// Not a database (no SQLite header, or a journal mode that is neither WAL nor the classic
        /// one), or no `ItemTable`: Cursor changed how it stores its state.
        case notADatabase
    }

    /// Classifies the token row of `database`. Opens nothing before the checks have passed, and
    /// never writes.
    static func classify(database url: URL, owner: uid_t = getuid()) throws(Failure) -> Kind {
        // SQLite's `NOFOLLOW` refuses a link anywhere in the path, and a home folder can sit behind
        // one (`/var` is `/private/var`): the folders above the file are resolved, the file itself is
        // never followed (`check` refuses a link there).
        let database = resolvedFolder(of: url).appendingPathComponent(url.lastPathComponent)
        try check(database, owner: owner)
        switch try journalMode(of: database) {
        case .wal:
            for suffix in ["-wal", "-shm"] {
                do {
                    try check(URL(fileURLWithPath: database.path + suffix), owner: owner)
                } catch .notFound {
                    throw .logFilesMissing
                }
            }
        case .rollback:
            // A journal next to the database is a write in progress (a "hot" journal): a read-only
            // opening could not roll it back, and reading around it could show half a change.
            if exists(URL(fileURLWithPath: database.path + "-journal")) { throw .busy }
        }

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOFOLLOW | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(uri(for: database), &handle, flags, nil) == SQLITE_OK, let handle else {
            let code = handle.map { sqlite3_extended_errcode($0) } ?? SQLITE_CANTOPEN
            sqlite3_close(handle)
            throw failure(code)
        }
        defer { sqlite3_close(handle) }
        sqlite3_busy_timeout(handle, 500)

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT value FROM ItemTable WHERE key = ?1 LIMIT 1", -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw failure(sqlite3_extended_errcode(handle))
        }
        defer { sqlite3_finalize(statement) }
        // SQLITE_TRANSIENT: SQLite copies the key before this call returns.
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(statement, 1, tokenKey, -1, transient) == SQLITE_OK else { throw .busy }

        switch sqlite3_step(statement) {
        case SQLITE_DONE:
            return .absent
        case SQLITE_ROW:
            return classify(column: statement)
        default:
            throw failure(sqlite3_extended_errcode(handle))
        }
    }

    /// The two journal modes the state database can be in.
    enum JournalMode: Equatable, Sendable {
        case wal
        case rollback
    }

    /// The journal mode written in the header of the SQLite file: its first 16 bytes are
    /// `SQLite format 3` and a zero byte, and bytes 18 and 19 are the file format version numbers for
    /// writing and for reading (1 is the classic journal, 2 is WAL; sqlite.org/fileformat2.html). Only
    /// those 20 bytes are read, through a descriptor opened read-only that never follows a link.
    static func journalMode(of url: URL) throws(Failure) -> JournalMode {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            switch errno {
            case ENOENT, ENOTDIR: throw .notFound
            case ELOOP: throw .notRegularFile
            default: throw .busy
            }
        }
        defer { close(descriptor) }
        var header = [UInt8](repeating: 0, count: 20)
        let count = pread(descriptor, &header, header.count, 0)
        guard count >= 0 else { throw .busy }
        guard count == header.count, Array(header[0..<16]) == Array("SQLite format 3".utf8) + [0] else { throw .notADatabase }
        switch (header[18], header[19]) {
        case (1, 1): return .rollback
        case (2, 2), (2, 1), (1, 2): return .wal
        default: throw .notADatabase
        }
    }

    /// Whether something (a file, a link, a folder) is at `url`, without following it. A path that
    /// cannot be examined counts as there.
    private static func exists(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 || (errno != ENOENT && errno != ENOTDIR)
    }

    /// Classifies a value from its first column, copying nothing when it is not a short text.
    private static func classify(column statement: OpaquePointer) -> Kind {
        let type = sqlite3_column_type(statement, 0)
        guard type == SQLITE_TEXT || type == SQLITE_BLOB else {
            return type == SQLITE_NULL ? .absent : .unrecognized
        }
        let count = Int(sqlite3_column_bytes(statement, 0))
        if count == 0 { return .absent }
        guard count <= maxValueBytes, let bytes = sqlite3_column_blob(statement, 0) else { return .unrecognized }
        return classify(value: Data(bytes: bytes, count: count))
    }

    /// The kind of a value. The value is dropped when this returns.
    static func classify(value: Data) -> Kind {
        guard let text = text(of: value) else { return .unrecognized }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .absent }
        if trimmed.hasPrefix(encryptedPrefix) { return .encrypted }
        return isJWT(trimmed) ? .clear : .unrecognized
    }

    /// The value as text: UTF-8, or the ASCII-only UTF-16 little-endian that VS Code based apps also
    /// write in a BLOB (CodexBar handles both, `CursorAppAuth.swift`, `decodeSQLiteValue`).
    private static func text(of value: Data) -> String? {
        if value.count.isMultiple(of: 2), value.count >= 2,
           stride(from: 0, to: value.count, by: 2).allSatisfy({ (1..<128).contains(value[$0]) && value[$0 + 1] == 0 }) {
            return String(data: value, encoding: .utf16LittleEndian)
        }
        return String(data: value, encoding: .utf8)
    }

    /// Three non-empty segments of base64url characters, the shape of a JWT. Nothing is decoded.
    static func isJWT(_ text: String) -> Bool {
        let segments = text.split(separator: ".", omittingEmptySubsequences: false)
        return segments.count == 3 && segments.allSatisfy { segment in
            !segment.isEmpty && segment.utf8.allSatisfy {
                ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A) || $0 == 0x2D || $0 == 0x5F
            }
        }
    }

    /// The folder of `url` with every link in it resolved by `realpath` (`URL.resolvingSymlinksInPath`
    /// would turn `/private/var` back into `/var`). Unchanged when it cannot be resolved.
    static func resolvedFolder(of url: URL) -> URL {
        let folder = url.deletingLastPathComponent()
        guard let resolved = realpath(folder.path, nil) else { return folder }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
    }

    /// `lstat`: a regular file of the user, a link not followed.
    private static func check(_ url: URL, owner: uid_t) throws(Failure) {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            throw errno == ENOENT || errno == ENOTDIR ? .notFound : .busy
        }
        guard (info.st_mode & S_IFMT) == S_IFREG else { throw .notRegularFile }
        guard info.st_uid == owner else { throw .wrongOwner }
    }

    /// `file:<path>?mode=ro`, the path percent-encoded so that a space, `?` or `#` in it stays a path.
    private static func uri(for url: URL) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~/")
        return "file:" + (url.path.addingPercentEncoding(withAllowedCharacters: allowed) ?? url.path) + "?mode=ro"
    }

    /// A busy or unreadable database is tried again; a file that is not a database, or has no
    /// `ItemTable`, is a change of format.
    private static func failure(_ code: Int32) -> Failure {
        switch code & 0xFF {
        case SQLITE_NOTADB, SQLITE_CORRUPT, SQLITE_ERROR: return .notADatabase
        default: return .busy
        }
    }
}
