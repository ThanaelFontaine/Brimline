import Foundation

/// Cursor: detection and a sentence, nothing read from the network yet.
///
/// The app keeps its sign-in in its SQLite state database. This reader looks at that one database
/// and answers with what it finds: a plain token is acknowledged (the limits come with the next lot),
/// a protected, absent or unreadable one is a sentence. The value is never kept and never sent.
///
/// Rules: one file (`~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`), opened
/// read-only without following a link, and creating nothing: in WAL mode only when its `-wal` and
/// `-shm` files already exist, in the classic journal mode only when no `-journal` file is there (a
/// write is in progress); one prepared query; no Keychain item (never "Cursor Safe Storage"), no program launched, no request.
/// The provider is off until the user turns it on, like every provider but Claude.
public struct CursorReader: ProviderReader {
    public init() {}

    public var provider: Provider { .cursor }
    /// Nothing is requested yet.
    public var allowedURLs: [URL] { [] }

    static let databaseName = "state.vscdb"

    /// The one place, under a home folder.
    static func databaseURL(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/\(databaseName)")
    }

    /// One card when the database is there and is a regular file of the user, none otherwise. The
    /// file is only looked for (`lstat`), never opened here.
    public func discover(home: URL, settings: BrimlineSettings) -> [Account] {
        let database = Self.databaseURL(home: home)
        var info = stat()
        guard lstat(database.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return [] }
        return [Account(provider: .cursor, source: KeychainServiceName.normalize(database.path), email: nil,
                        organization: nil, seatTier: nil, keychainService: nil)]
    }

    public func read(account: Account, now: Date) async -> ProviderReading {
        let database = URL(fileURLWithPath: account.source)
        // A card only ever points at the database found by `discover`.
        guard database.lastPathComponent == Self.databaseName else {
            return .failure(status: .unavailable, detail: "unexpected source", retryAfter: nil)
        }
        do throws(CursorSession.Failure) {
            switch try CursorSession.classify(database: database) {
            case .clear:
                // The sign-in is readable; reading the limits comes next. The value is already gone.
                return .failure(status: .pending, detail: "reading to come", retryAfter: nil)
            case .encrypted, .absent:
                return .notReadable(reason: .protectedSignIn)
            case .unrecognized:
                return .failure(status: .formatChanged, detail: "unknown sign-in format", retryAfter: nil)
            }
        } catch {
            switch error {
            case .logFilesMissing:
                // A WAL database with no log files: Cursor is closed, so nothing is opened and
                // nothing is known about the sign-in.
                return .notReadable(reason: .protectedSignIn)
            case .notFound:
                // The card came from a database that is gone since: a passing failure, not a verdict
                // on the sign-in.
                return .failure(status: .unavailable, detail: "state database not found", retryAfter: nil)
            case .notRegularFile, .wrongOwner:
                return .failure(status: .unavailable, detail: "state database refused", retryAfter: nil)
            case .busy:
                return .failure(status: .unavailable, detail: "state database busy", retryAfter: nil)
            case .notADatabase:
                return .failure(status: .formatChanged, detail: "unknown state database", retryAfter: nil)
            }
        }
    }
}
