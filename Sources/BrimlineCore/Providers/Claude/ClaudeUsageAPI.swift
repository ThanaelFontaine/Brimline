import Foundation

/// The Claude usage endpoint used by Claude Code. Internal and undocumented: it may change.
public enum ClaudeUsageAPI {
    public static let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    public static let timeout: TimeInterval = URLSessionHTTPClient.timeout
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
