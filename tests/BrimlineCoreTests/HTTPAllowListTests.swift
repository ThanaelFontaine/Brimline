import Foundation
import Testing
@testable import BrimlineCore

@Suite("A reader only calls its own closed list of URLs")
struct HTTPAllowListTests {
    let listed = URL(string: "https://example.test/usage?format=credits")!

    func request(_ url: String) -> URLRequest { URLRequest(url: URL(string: url)!) }

    @Test("The listed URL passes, whole")
    func listedPasses() async throws {
        let http = FakeHTTP(["": (200, Data("{}".utf8), [:])])
        let client = http.restricted(to: [listed])
        let (_, response) = try await client.send(request(listed.absoluteString))
        #expect(response.statusCode == 200)
        #expect(http.requests.count == 1)
    }

    @Test("Another host, path, query or scheme is refused before anything is sent")
    func unlistedRefused() async {
        let http = FakeHTTP(["": (200, Data("{}".utf8), [:])])
        let client = http.restricted(to: [listed])
        for url in ["https://other.test/usage?format=credits", "https://example.test/other?format=credits",
                    "https://example.test/usage", "https://example.test/usage?format=credits&x=1",
                    "http://example.test/usage?format=credits", "https://example.test.evil.test/usage?format=credits"] {
            await #expect(throws: URLError.self) { try await client.send(request(url)) }
        }
        #expect(http.requests.isEmpty)
    }

    @Test("An answer that does not come from a listed URL is refused")
    func answerFromElsewhere() async {
        struct Elsewhere: HTTPClient {
            func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
                (Data(), HTTPURLResponse(url: URL(string: "https://evil.test/")!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
        }
        let client = Elsewhere().restricted(to: [listed])
        await #expect(throws: URLError.self) { try await client.send(request(listed.absoluteString)) }
    }

    @Test("The real client refuses a URL that is not https")
    func realClientNeedsHTTPS() async {
        await #expect(throws: URLError.self) { try await URLSessionHTTPClient().send(request("http://example.test/")) }
    }

    @Test("Every reader of the registry declares https URLs, with no secret in them (Gemini and Cursor none: they call nothing yet)")
    func registryLists() {
        for reader in Providers.all {
            #expect(reader.allowedURLs.isEmpty == (reader.provider == .gemini || reader.provider == .cursor), "\(reader.provider)")
            for url in reader.allowedURLs {
                #expect(url.scheme == "https")
                #expect(url.user == nil && url.password == nil)
            }
        }
    }

    @Test("Claude calls its usage URL and nothing else")
    func claudeOnlyItsURL() async throws {
        let a = account("a@example.com")
        let http = FakeHTTP(["tok": (200, try fixture("usage-contact-np"), [:])])
        let reader = ClaudeReader(credentials: FakeCredentials([a.keychainService!: .success(ClaudeCredential(accessToken: "tok", expiresAt: nil))]), http: http)
        _ = await reader.read(account: a, now: date("2026-10-27T01:00:00Z"))
        #expect(http.requests.map { $0.url } == [ClaudeUsageAPI.url])
        #expect(reader.allowedURLs == [ClaudeUsageAPI.url])
    }

    @Test("A token with a line break or a space is never sent")
    func headerValue() async {
        let a = account("a@example.com")
        let bad = "tok\r\nX-Injected: 1"
        let http = FakeHTTP([bad: (200, Data("{}".utf8), [:])])
        let reader = ClaudeReader(credentials: FakeCredentials([a.keychainService!: .success(ClaudeCredential(accessToken: bad, expiresAt: nil))]), http: http)
        let reading = await reader.read(account: a, now: date("2026-10-27T01:00:00Z"))
        guard case .failure(.reconnect, _, _) = reading else {
            Issue.record("expected reconnect")
            return
        }
        #expect(http.requests.isEmpty)
    }
}
