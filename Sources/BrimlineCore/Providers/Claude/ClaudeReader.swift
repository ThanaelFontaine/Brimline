import Foundation

/// Claude Code: the sign-in from the Keychain, then the usage endpoint of Anthropic.
///
/// Rules: an expired token is never sent and never renewed; a refused token asks to sign in
/// again; every other failure is `unavailable`, which the service retries with a growing delay.
///
/// An account may also have a Claude Code report (`brimline report claude`): the numbers Claude Code saw
/// itself. An account known by its report only is read from it; an account with a folder keeps the direct
/// reading, and falls back on its report when its session has expired or its Keychain item is missing.
public struct ClaudeReader: ProviderReader {
    public var credentials: any CredentialReading
    public var http: any HTTPClient
    /// The folder of the reports; nil is `~/Library/Application Support/Brimline/claude-reports` of the home.
    public var reportsDirectory: URL?

    public init(credentials: any CredentialReading = SecurityToolCredentialReader(),
                http: any HTTPClient = URLSessionHTTPClient(), reportsDirectory: URL? = nil) {
        self.credentials = credentials
        self.http = http
        self.reportsDirectory = reportsDirectory
    }

    public var provider: Provider { .claude }
    public var allowedURLs: [URL] { [ClaudeUsageAPI.url] }

    public func discover(home: URL, settings: BrimlineSettings) -> [Account] {
        AccountDiscovery(home: home, extraFolders: settings.extraFolders,
                         reportsDirectory: reportsDirectory ?? BrimlinePaths(home: home).claudeReportsDirectory).discover()
    }

    public func read(account: Account, now: Date) async -> ProviderReading {
        if account.readsReportOnly { return readReport(of: account, now: now, instead: nil) }
        guard let service = account.keychainService else {
            return .failure(status: .signedOut, detail: "no Keychain item", retryAfter: nil)
        }
        let credential: ClaudeCredential
        do throws(CredentialError) {
            credential = try await Self.read(credentials, service: service)
        } catch {
            switch error {
            case .notFound:
                return fallback(account, now: now, otherwise: .failure(status: .signedOut, detail: "no Keychain item", retryAfter: nil))
            case .unreadable:
                return .failure(status: .signedOut, detail: "unreadable Keychain item", retryAfter: nil)
            case .toolFailed(let code):
                return .failure(status: .unavailable, detail: "security exited with \(code)", retryAfter: nil)
            }
        }

        if credential.isExpired(at: now) { return fallback(account, now: now, otherwise: .expired) }
        // A token that cannot go in a header as it is (a line break, a space) is never sent.
        guard ProviderText.isHeaderToken(credential.accessToken) else {
            return .failure(status: .reconnect, detail: "unusable token", retryAfter: nil)
        }

        do {
            let client = http.restricted(to: allowedURLs)
            let (data, response) = try await client.send(ClaudeUsageAPI.request(accessToken: credential.accessToken))
            switch response.statusCode {
            case 200:
                do {
                    return .limits(try UsageParser.parse(data), shape: ResponseShape.fingerprint(of: data))
                } catch {
                    // JSON that is not the expected one, or a page: the format changed, never a number.
                    return .failure(status: .formatChanged, detail: "unknown answer", retryAfter: nil)
                }
            case 401:
                return .failure(status: .reconnect, detail: "HTTP 401", retryAfter: nil)
            case 429:
                return .failure(status: .unavailable, detail: "HTTP 429", retryAfter: response.retryAfterSeconds)
            default:
                return .failure(status: .unavailable, detail: "HTTP \(response.statusCode)", retryAfter: nil)
            }
        } catch {
            return .failure(status: .unavailable, detail: "network", retryAfter: nil)
        }
    }

    /// The report of an account whose direct reading cannot be done, or `otherwise` when it has none that reads.
    func fallback(_ account: Account, now: Date, otherwise: ProviderReading) -> ProviderReading {
        guard account.claudeReport != nil else { return otherwise }
        let status: AccountStatus
        switch otherwise {
        case .expired: status = .expired
        case .failure(let s, _, _): status = s
        default: return otherwise
        }
        let reading = readReport(of: account, now: now, instead: status)
        if case .observed = reading { return reading }
        return otherwise
    }

    /// Reads the report of an account: no link followed, the user's own file, 64 KiB at most.
    func readReport(of account: Account, now: Date, instead: AccountStatus?) -> ProviderReading {
        guard let path = account.claudeReport, let email = account.email.flatMap(ClaudeReportEmail.normalize) else {
            return .failure(status: .unavailable, detail: "no report", retryAfter: nil)
        }
        let file = URL(fileURLWithPath: path)
        let report: ClaudeCodeReport
        do throws(ClaudeReportStore.Failure) {
            report = try ClaudeReportStore(directory: file.deletingLastPathComponent()).load(file: file, email: email)
        } catch {
            switch error {
            case .file(.notFound): return .failure(status: .unavailable, detail: "no report", retryAfter: nil)
            case .notAReport: return .failure(status: .formatChanged, detail: "unknown report", retryAfter: nil)
            default: return .failure(status: .unavailable, detail: "report not readable", retryAfter: nil)
            }
        }
        if report.status == .formatChanged {
            return .failure(status: .formatChanged, detail: "Claude Code changed its report", retryAfter: nil)
        }
        let limits = report.limits(at: now)
        guard !limits.isEmpty, let observedAt = report.numbersObservedAt(at: now) else {
            return .failure(status: .unavailable, detail: "no report", retryAfter: nil)
        }
        return .observed(limits, observedAt: observedAt, instead: instead)
    }

    /// Runs the blocking Keychain read off the caller's thread.
    private static func read(_ reader: any CredentialReading, service: String) async throws(CredentialError) -> ClaudeCredential {
        let result: Result<ClaudeCredential, CredentialError> = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do throws(CredentialError) {
                    continuation.resume(returning: .success(try reader.readCredential(service: service)))
                } catch {
                    continuation.resume(returning: .failure(error))
                }
            }
        }
        return try result.get()
    }
}
