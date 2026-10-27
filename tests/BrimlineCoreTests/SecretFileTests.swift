import Foundation
import Testing
@testable import BrimlineCore

@Suite("Reading a sign-in file safely")
struct SecretFileTests {
    struct Auth: Decodable, Equatable {
        struct Tokens: Decodable, Equatable { var access_token: String }
        var tokens: Tokens
    }

    @Test("A regular file of the user is read")
    func regular() throws {
        let home = try TemporaryHome()
        try home.write("auth.json", #"{"tokens":{"access_token":"abc"}}"#)
        let auth = try SecretFile.readJSON(Auth.self, url: home.url.appendingPathComponent("auth.json"))
        #expect(auth == Auth(tokens: .init(access_token: "abc")))
    }

    @Test("A file that is not there is notFound, also when its folder is not there")
    func missing() throws {
        let home = try TemporaryHome()
        #expect(throws: SecretFile.Failure.notFound) { try SecretFile.read(url: home.url.appendingPathComponent("none.json")) }
        #expect(throws: SecretFile.Failure.notFound) { try SecretFile.read(url: home.url.appendingPathComponent("none/auth.json")) }
    }

    @Test("A link is refused, never followed")
    func link() throws {
        let home = try TemporaryHome()
        try home.write("real.json", #"{"tokens":{"access_token":"abc"}}"#)
        try FileManager.default.createSymbolicLink(at: home.url.appendingPathComponent("auth.json"),
                                                   withDestinationURL: home.url.appendingPathComponent("real.json"))
        #expect(throws: SecretFile.Failure.notRegularFile) { try SecretFile.read(url: home.url.appendingPathComponent("auth.json")) }
    }

    @Test("A folder is refused")
    func folder() throws {
        let home = try TemporaryHome()
        try home.mkdir("auth.json")
        #expect(throws: SecretFile.Failure.notRegularFile) { try SecretFile.read(url: home.url.appendingPathComponent("auth.json")) }
    }

    @Test("A file that is too large is refused")
    func large() throws {
        let home = try TemporaryHome()
        try home.write("big.json", String(repeating: "a", count: 2048))
        #expect(throws: SecretFile.Failure.tooLarge) { try SecretFile.read(url: home.url.appendingPathComponent("big.json"), maxBytes: 1024) }
        // At the limit it passes.
        #expect(try SecretFile.read(url: home.url.appendingPathComponent("big.json"), maxBytes: 2048).count == 2048)
        #expect(SecretFile.defaultMaxBytes == 1024 * 1024)
    }

    @Test("A file of another user is refused")
    func otherOwner() throws {
        let home = try TemporaryHome()
        try home.write("auth.json", "{}")
        let me = getuid()
        #expect(throws: SecretFile.Failure.wrongOwner) {
            try SecretFile.read(url: home.url.appendingPathComponent("auth.json"), owner: me &+ 1)
        }
        #expect(try SecretFile.read(url: home.url.appendingPathComponent("auth.json"), owner: me) == Data("{}".utf8))
    }

    @Test("A file cut short is malformed and transient, not a signed out account")
    func truncated() throws {
        let home = try TemporaryHome()
        try home.write("auth.json", #"{"tokens":{"access_to"#)
        do {
            _ = try SecretFile.readJSON(Auth.self, url: home.url.appendingPathComponent("auth.json"))
            Issue.record("expected a failure")
        } catch {
            #expect(error == .malformed)
            #expect(error.isTransient)
        }
        #expect(!SecretFile.Failure.notFound.isTransient)
    }

    @Test("A named pipe does not make the read wait")
    func pipe() throws {
        let home = try TemporaryHome()
        let path = home.url.appendingPathComponent("auth.json").path
        #expect(mkfifo(path, 0o600) == 0)
        #expect(throws: SecretFile.Failure.notRegularFile) { try SecretFile.read(url: URL(fileURLWithPath: path)) }
    }
}
