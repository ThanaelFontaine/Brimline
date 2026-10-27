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
