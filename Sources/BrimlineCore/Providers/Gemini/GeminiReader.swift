import Foundation

/// Gemini: a sentence only. Google publishes no limit of a Gemini subscription in a form Brimline
/// can read, so the reader opens nothing and asks nothing: it notes that Gemini CLI's folder is
/// there (its presence, never its content) so the account card can say so in words.
///
/// Rules: no file is opened or listed, no Keychain item, no request, no program launched. The
/// provider is off until the user turns it on, like every provider but Claude.
public struct GeminiReader: ProviderReader {
    public init() {}

    public var provider: Provider { .gemini }
    /// Nothing is ever requested.
    public var allowedURLs: [URL] { [] }

    /// `~/.gemini` and nothing else: one card when the folder exists (and is a folder).
    public func discover(home: URL, settings: BrimlineSettings) -> [Account] {
        let folder = KeychainServiceName.normalize(home.appendingPathComponent(".gemini").path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder, isDirectory: &isDirectory), isDirectory.boolValue else {
            return []
        }
        return [Account(provider: .gemini, source: folder, email: nil, organization: nil, seatTier: nil,
                        keychainService: nil)]
    }

    public func read(account: Account, now: Date) async -> ProviderReading {
        .notReadable(reason: .consumerPlan)
    }
}
