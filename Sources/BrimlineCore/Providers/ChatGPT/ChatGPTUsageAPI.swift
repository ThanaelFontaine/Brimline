import Foundation

/// The usage endpoint that Codex itself calls for its limits (`wham/usage` of the ChatGPT backend).
/// Internal and undocumented by OpenAI: it may change. The same limits are documented by Codex
/// (`/status`, and `account/rateLimits/read` of `codex app-server`); Brimline does not launch it.
public enum ChatGPTUsageAPI {
    public static let url = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    public static let timeout: TimeInterval = URLSessionHTTPClient.timeout
    /// Brimline says who it is: it never presents itself as Codex.
    public static var userAgent: String { ClaudeUsageAPI.userAgent }

    /// `accountId` is nil when the sign-in file has none: the header is then left out.
    public static func request(accessToken: String, accountId: String?) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let accountId { request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id") }
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}
