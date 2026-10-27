import Foundation

/// Sends one HTTP request. A protocol, so tests can answer without the network.
public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionHTTPClient: HTTPClient {
    /// Largest answer read: the usage answer is a few Kio.
    public static let maxBodyBytes = 256 * 1024

    private let session: URLSession

    public init() {
        self.init(protocolClasses: nil)
    }

    init(protocolClasses: [AnyClass]?) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = ClaudeUsageAPI.timeout
        config.timeoutIntervalForResource = ClaudeUsageAPI.timeout
        config.httpCookieStorage = nil
        config.urlCache = nil
        if let protocolClasses { config.protocolClasses = protocolClasses }
        session = URLSession(configuration: config)
    }

    /// Refuses every redirection (the 3xx becomes the answer) and any answer that does not come
    /// from the usage URL; the body is read up to `maxBodyBytes`, then the request fails.
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (bytes, response) = try await session.bytes(for: request, delegate: NoRedirectDelegate())
        guard let http = response as? HTTPURLResponse, http.url == ClaudeUsageAPI.url else {
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

/// Never follows a redirection: the request carries a token and must stay on the usage URL.
final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}

/// The Claude usage endpoint used by Claude Code. Internal and undocumented: it may change.
public enum ClaudeUsageAPI {
    public static let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    public static let timeout: TimeInterval = 15
    public static let betaHeader = "oauth-2025-04-20"
    /// Brimline says who it is: it never presents itself as Claude Code.
    public static var userAgent: String { "Brimline/\(BrimlineVersion.current) (+\(Links.repository.absoluteString))" }

    public static func request(accessToken: String) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(betaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}
