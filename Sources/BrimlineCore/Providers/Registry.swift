import Foundation

/// The providers Brimline reads. Claude only for now.
public enum Providers {
    /// The readers with their real Keychain and network access.
    public static var all: [any ProviderReader] { make() }

    /// The readers, with the Keychain and the network replaced (tests).
    public static func make(credentials: any CredentialReading = SecurityToolCredentialReader(),
                            http: any HTTPClient = URLSessionHTTPClient()) -> [any ProviderReader] {
        [ClaudeReader(credentials: credentials, http: http)]
    }

    /// Every account found by every reader, in the readers' order.
    public static func discover(readers: [any ProviderReader] = all,
                                home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                settings: BrimlineSettings) -> [Account] {
        readers.flatMap { $0.discover(home: home, settings: settings) }
    }
}
