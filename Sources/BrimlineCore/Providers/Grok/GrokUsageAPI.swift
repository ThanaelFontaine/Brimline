import Foundation

/// The billing call that the Grok CLI itself makes for its credits (`x.ai/billing` of its shell,
/// `GET <cli proxy>/billing?format=credits`). Internal and undocumented by xAI: it may change. xAI's
/// reference of the CLI (https://docs.x.ai/build/cli/reference) documents no command that gives it.
public enum GrokUsageAPI {
    public static let url = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!
    public static let timeout: TimeInterval = URLSessionHTTPClient.timeout
    /// The header that tells the proxy this is a user token of the CLI, with the value the CLI sends.
    public static let tokenHeader = "X-XAI-Token-Auth"
    public static let tokenHeaderValue = "xai-grok-cli"
    /// Brimline says who it is: it never presents itself as the Grok CLI (the token header above is how
    /// the proxy tells a user token from a deployment key, not a name).
    public static var userAgent: String { ClaudeUsageAPI.userAgent }

    /// `userId` is nil when the sign-in file has none: the header is then left out.
    public static func request(token: String, userId: String?) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(tokenHeaderValue, forHTTPHeaderField: tokenHeader)
        if let userId { request.setValue(userId, forHTTPHeaderField: "x-userid") }
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}
