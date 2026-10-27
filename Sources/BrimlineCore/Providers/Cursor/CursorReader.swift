import Foundation

/// Cursor: the sign-in the app keeps in its SQLite state database, then the call its own dashboard
/// makes for the usage of a plan (`GET https://cursor.com/api/usage-summary`).
///
/// Rules: one file (`~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`), opened
/// read-only without following a link, and creating nothing: in WAL mode only when its `-wal` and
/// `-shm` files already exist, in the classic journal mode only when no `-journal` file is there (a
/// write is in progress); one prepared query; no Keychain item (never "Cursor Safe Storage"), no
/// program launched. A value Cursor encrypted is never decrypted: the card says where to see the usage.
/// A plain token is used once, in memory, for the one request below, and never kept (see `CursorToken`).
/// An expired token is never sent and never renewed (Cursor renews it when it runs); a refused one, or a
/// redirection (to the sign-in page), asks to open Cursor; every other failure is `unavailable`, which
/// the service retries with a growing delay. The provider is off until the user turns it on, like every
/// provider but Claude.
public struct CursorReader: ProviderReader {
    public var http: any HTTPClient

    /// How long before its expiry a token is no longer sent.
    static let expiryMargin: TimeInterval = 60

    public init(http: any HTTPClient = URLSessionHTTPClient()) {
        self.http = http
    }

    public var provider: Provider { .cursor }
    public var allowedURLs: [URL] { [CursorUsageAPI.url] }

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
        let content: CursorSession.Content
        do throws(CursorSession.Failure) {
            content = try CursorSession.content(database: database)
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

        switch content {
        case .clear(let jwt):
            return await readUsage(jwt: jwt, now: now)
        case .encrypted, .absent:
            return .notReadable(reason: .protectedSignIn)
        case .unrecognized:
            return .failure(status: .formatChanged, detail: "unknown sign-in format", retryAfter: nil)
        }
    }

    /// The one request, with the plain token of the app.
    private func readUsage(jwt: String, now: Date) async -> ProviderReading {
        // A token that cannot go in a header, or whose `sub` is not a plain identifier, is never sent.
        guard let token = CursorToken(jwt: jwt) else {
            return .failure(status: .formatChanged, detail: "unusable token", retryAfter: nil)
        }
        if let expiry = token.expiry, expiry <= now.addingTimeInterval(Self.expiryMargin) {
            return .expired
        }

        do {
            let client = http.restricted(to: allowedURLs)
            let (data, response) = try await client.send(CursorUsageAPI.request(token: token))
            switch response.statusCode {
            case 200:
                let shape = ResponseShape.fingerprint(of: data)
                do {
                    let reading = try CursorUsageParser.parse(data)
                    if reading.unlimited { return .annotated([], shape: shape, note: .noLimit) }
                    if reading.limits.isEmpty { return .annotated([], shape: shape, note: .noFigureYet) }
                    return .limits(reading.limits, shape: shape)
                } catch {
                    // JSON that is not the expected one, or a page: the format changed, never a number.
                    return .failure(status: .formatChanged, detail: "unknown answer", retryAfter: nil)
                }
            case 401, 403, 300..<400:
                // Refused, or sent to the sign-in page: Cursor renews its sign-in when it is opened.
                return .expired
            case 429:
                return .failure(status: .unavailable, detail: "HTTP 429", retryAfter: response.retryAfterSeconds)
            default:
                return .failure(status: .unavailable, detail: "HTTP \(response.statusCode)", retryAfter: nil)
            }
        } catch {
            return .failure(status: .unavailable, detail: "network", retryAfter: nil)
        }
    }
}
