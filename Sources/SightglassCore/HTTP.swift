import Foundation

/// Sends one HTTP request. A protocol, so tests can answer without the network.
public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = ClaudeUsageAPI.timeout
        config.timeoutIntervalForResource = ClaudeUsageAPI.timeout
        config.httpCookieStorage = nil
        config.urlCache = nil
        session = URLSession(configuration: config)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

/// The Claude usage endpoint used by Claude Code. Internal and undocumented: it may change.
public enum ClaudeUsageAPI {
    public static let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    public static let timeout: TimeInterval = 15
    public static let betaHeader = "oauth-2025-04-20"
    /// Sightglass says who it is: it never presents itself as Claude Code.
    public static var userAgent: String { "Sightglass/\(SightglassVersion.current) (+\(Links.repository.absoluteString))" }

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
