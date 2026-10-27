import Foundation
@testable import BrimlineCore

/// Fake HTTP client for the Cursor reader: one answer for the one URL, every request recorded. It
/// never reaches the network, whatever the token. (`FakeHTTP` answers by `Authorization` token, and
/// Cursor sends its token in a cookie.)
final class CursorFakeHTTP: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private let status: Int
    private let body: Data
    private let headers: [String: String]
    private let failure: URLError?
    private var recorded: [URLRequest] = []

    var requests: [URLRequest] { lock.withLock { recorded } }

    init(status: Int = 200, body: Data = Data(), headers: [String: String] = [:], failure: URLError? = nil) {
        self.status = status
        self.body = body
        self.headers = headers
        self.failure = failure
    }

    /// No answer: the network is down.
    static func offline() -> CursorFakeHTTP { CursorFakeHTTP(failure: URLError(.notConnectedToInternet)) }

    /// The answer of a fixture (`cursor-usage-summary-<name>.json`).
    static func answering(_ name: String = "pro", status: Int = 200, headers: [String: String] = [:]) throws -> CursorFakeHTTP {
        CursorFakeHTTP(status: status, body: try fixture("cursor-usage-summary-\(name)"), headers: headers)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { recorded.append(request) }
        if let failure { throw failure }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        return (body, response)
    }
}
