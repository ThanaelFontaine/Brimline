import Foundation
@testable import BrimlineCore

/// A temporary home folder, removed at the end of the test.
final class TemporaryHome {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brimline-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    func write(_ relative: String, _ text: String) throws {
        let file = url.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
    }

    func mkdir(_ relative: String) throws {
        try FileManager.default.createDirectory(at: url.appendingPathComponent(relative), withIntermediateDirectories: true)
    }

    func path(_ relative: String) -> String {
        KeychainServiceName.normalize(url.appendingPathComponent(relative).path)
    }
}

func claudeJSON(email: String, organization: String? = nil, seat: String? = nil) -> String {
    var account: [String: Any] = ["emailAddress": email, "accountUuid": "00000000-0000-0000-0000-000000000000"]
    account["organizationName"] = organization
    account["seatTier"] = seat
    let data = try! JSONSerialization.data(withJSONObject: ["numStartups": 3, "oauthAccount": account])
    return String(decoding: data, as: UTF8.self)
}

func fixture(_ name: String) throws -> Data {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
        throw CocoaError(.fileNoSuchFile)
    }
    return try Data(contentsOf: url)
}

/// Fake Keychain: service name to stored value, and a record of the services read.
final class FakeCredentials: CredentialReading, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Result<ClaudeCredential, CredentialError>]
    private(set) var reads: [String] = []

    init(_ values: [String: Result<ClaudeCredential, CredentialError>]) {
        self.values = values
    }

    func readCredential(service: String) throws(CredentialError) -> ClaudeCredential {
        lock.lock()
        reads.append(service)
        let value = values[service]
        lock.unlock()
        guard let value else { throw .notFound }
        return try value.get()
    }
}

/// Fake HTTP client: answers by access token, records every request.
final class FakeHTTP: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [String: (Int, Data, [String: String])]
    private(set) var requests: [URLRequest] = []

    init(_ answers: [String: (Int, Data, [String: String])]) {
        self.answers = answers
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let token = request.value(forHTTPHeaderField: "Authorization")?.replacingOccurrences(of: "Bearer ", with: "") ?? ""
        let answer = lock.withLock {
            requests.append(request)
            return answers[token]
        }
        guard let (status, body, headers) = answer else { throw URLError(.notConnectedToInternet) }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        return (body, response)
    }
}

let utc = TimeZone(identifier: "UTC")!

func date(_ iso: String) -> Date { ISODate.parse(iso)! }

func account(_ email: String, dir: String = "/opt/team/.claude-work") -> Account {
    Account(source: dir, email: email, organization: nil, seatTier: nil,
            keychainService: KeychainServiceName.forConfigDir(dir, isDefault: false))
}

/// Settings with every provider on, for the tests that are not about consent.
let allOn: BrimlineSettings = {
    var s = BrimlineSettings()
    s.enabledProviders = Provider.allCases.map(\.rawValue)
    return s
}()
