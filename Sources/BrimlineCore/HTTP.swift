import Foundation

/// Sends one HTTP request. A protocol, so tests can answer without the network.
public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// A reader may only call its own closed list of URLs, whole (scheme, host, path and query), and the
/// answer must come from one of them. Anything else is refused before the request leaves, so a token
/// is never sent anywhere a reader did not declare.
public struct AllowListHTTPClient: HTTPClient {
    public var base: any HTTPClient
    public var allowed: [URL]

    public init(_ base: any HTTPClient, allowed: [URL]) {
        self.base = base
        self.allowed = allowed
    }

    private func isAllowed(_ url: URL?) -> Bool {
        guard let url, url.scheme == "https" else { return false }
        return allowed.contains { $0.absoluteString == url.absoluteString }
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard isAllowed(request.url) else { throw URLError(.unsupportedURL) }
        let (data, response) = try await base.send(request)
        guard isAllowed(response.url) else { throw URLError(.badServerResponse) }
        return (data, response)
    }
}

extension HTTPURLResponse {
    /// The wait a provider asks for with `Retry-After`, in seconds, capped at one hour. Nil when the
    /// header is absent or is not a positive number of seconds.
    public var retryAfterSeconds: TimeInterval? {
        guard let header = value(forHTTPHeaderField: "Retry-After"),
              let seconds = TimeInterval(header.trimmingCharacters(in: .whitespaces)), seconds > 0 else { return nil }
        return min(seconds, 3600)
    }
}

extension HTTPClient {
    /// This client, limited to the given URLs.
    public func restricted(to urls: [URL]) -> AllowListHTTPClient { AllowListHTTPClient(self, allowed: urls) }
}

public struct URLSessionHTTPClient: HTTPClient {
    /// Largest answer read: a usage answer is a few Kio.
    public static let maxBodyBytes = 256 * 1024
    public static let timeout: TimeInterval = 15

    private let session: URLSession

    public init() {
        self.init(protocolClasses: nil)
    }

    init(protocolClasses: [AnyClass]?) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = Self.timeout
        config.timeoutIntervalForResource = Self.timeout
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        config.urlCache = nil
        if let protocolClasses { config.protocolClasses = protocolClasses }
        session = URLSession(configuration: config)
    }

    /// Refuses every redirection (the 3xx becomes the answer), any URL that is not https and any
    /// answer that does not come from the URL asked; handles and keeps no cookie itself (a `Cookie` header set by a reader, Cursor, is sent as set); the body is read up
    /// to `maxBodyBytes`, then the request fails.
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url, url.scheme == "https" else { throw URLError(.unsupportedURL) }
        var request = request
        request.httpShouldHandleCookies = false
        let (bytes, response) = try await session.bytes(for: request, delegate: NoRedirectDelegate())
        guard let http = response as? HTTPURLResponse, http.url == url else {
            throw URLError(.badServerResponse)
        }
        if http.expectedContentLength > Int64(Self.maxBodyBytes) { throw URLError(.dataLengthExceedsMaximum) }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > Self.maxBodyBytes { throw URLError(.dataLengthExceedsMaximum) }
        }
        return (data, http)
    }
}

/// Never follows a redirection: the request carries a token and must stay on the URL asked.
final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}
