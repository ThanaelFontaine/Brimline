import Foundation
import Testing
@testable import BrimlineCore

/// `--shape` and the fingerprint show field names, never data: a key that could be data (an address,
/// an id, a UUID, an account number used as a key) is written `<key>`.
@Suite("Response shape: keys are names, not data")
struct ResponseShapeTests {
    @Test("A key is shown only when it is a plain field name that does not look like an identifier")
    func shownKeys() {
        let shown = ["totalPercentUsed", "_x", "a", "plan2", "p95", "autoModelSelectedDisplayMessage", "isUnlimited", "A_B_c",
                     String(repeating: "x", count: 64), "deadbeef"]
        let hidden = ["", "1234", "9abc", "a-b", "a b", "a.b", "someone@example.com", "user_01234", "user_01JABCDEFG1234",
                      "550e8400-e29b-41d4-a716-446655440000", "0123456789abcdef", "deadbeefdeadbeef", "é", "a\nb",
                      String(repeating: "a", count: 65)]
        for key in shown { #expect(ResponseShape.isShownKey(key), "\(key)") }
        for key in hidden { #expect(!ResponseShape.isShownKey(key), "\(key)") }
    }

    @Test("An address, a UUID or a number sown as a key goes neither into the skeleton nor into the fingerprint")
    func sownKeys() throws {
        func body(_ address: String, _ uuid: String, _ number: String) -> Data {
            Data(#"{"plan":"free","someone":{"\#(address)":{"used":1},"\#(uuid)":{"used":2},"\#(number)":{"used":3}},"\#(address)":"x"}"#.utf8)
        }
        let a = body("someone@example.com", "550e8400-e29b-41d4-a716-446655440000", "4242424242")
        let b = body("other@example.org", "123e4567-e89b-12d3-a456-426614174000", "9999999999")
        let text = try #require(ResponseShape.skeleton(of: a))
        for seed in ["someone@example", "example.com", "550e8400", "4242424242"] { #expect(!text.contains(seed), "\(seed)") }
        #expect(text.contains("\"<key>\""))
        #expect(text.contains("\"plan\": \"string\""))
        // Several hidden keys of one object are one entry.
        #expect(text.components(separatedBy: "\"<key>\"").count == 3)
        // The fingerprint holds no such key either: two answers that differ only by them are the same shape.
        #expect(ResponseShape.fingerprint(of: a) == ResponseShape.fingerprint(of: b))
        #expect(!ResponseShape.fingerprint(of: a).isEmpty)
        // And it still moves when a real field name moves.
        let c = Data(#"{"plan2":"free"}"#.utf8)
        #expect(ResponseShape.fingerprint(of: c) != ResponseShape.fingerprint(of: Data(#"{"plan":"free"}"#.utf8)))
    }

    @Test("The recording client's skeleton hides such keys too")
    func recording() async throws {
        let body = Data(#"{"user_0123456789":{"used":1}}"#.utf8)
        let base = FakeHTTP(["": (200, body, [:])])
        let recorder = RecordingHTTPClient(base)
        _ = try await recorder.send(URLRequest(url: URL(string: "https://example.test/usage")!))
        let skeleton = try #require(recorder.skeletons.first?.skeleton)
        #expect(!skeleton.contains("0123456789") && skeleton.contains("<key>"))
    }
}
