import Foundation

/// The call that cursor.com's own dashboard makes for the usage of a plan: `GET /api/usage-summary`,
/// with the session cookie of the web app. Internal and undocumented by Cursor (its documented APIs
/// are for Enterprise teams only, https://cursor.com/docs/api): it may change.
public enum CursorUsageAPI {
    public static let url = URL(string: "https://cursor.com/api/usage-summary")!
    public static let timeout: TimeInterval = URLSessionHTTPClient.timeout
    static let cookieName = "WorkosCursorSessionToken"
    /// Brimline says who it is: the call is not the dashboard's.
    public static var userAgent: String { ClaudeUsageAPI.userAgent }

    /// The cookie of the web app: the user id, `::` written as `%3A%3A`, and the access token.
    static func cookie(userID: String, token: String) -> String {
        "\(cookieName)=\(userID)%3A%3A\(token)"
    }

    static func request(token: CursorToken) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue(cookie(userID: token.userID, token: token.value), forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }
}
