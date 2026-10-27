import Foundation

/// The providers Brimline has a reader for: Claude, and Gemini (a sentence only, nothing is read).
///
/// Having a reader here does not mean it runs: every provider is off until the user turns it on
/// (`BrimlineSettings.enabledProviders`, Claude on by default), and `discover` and the service
/// check that before touching anything of the provider.
public enum Providers {
    /// The readers with their real Keychain and network access.
    public static var all: [any ProviderReader] { make() }

    /// The readers, with the Keychain and the network replaced (tests).
    public static func make(credentials: any CredentialReading = SecurityToolCredentialReader(),
                            http: any HTTPClient = URLSessionHTTPClient()) -> [any ProviderReader] {
        [ClaudeReader(credentials: credentials, http: http), GeminiReader()]
    }

    /// Whether Brimline has a reader for this provider.
    public static func isSupported(_ provider: Provider, readers: [any ProviderReader] = all) -> Bool {
        readers.contains { $0.provider == provider }
    }

    /// Every account found by the readers of the providers that are on, in the readers' order.
    /// A provider that is off is not even looked for: no folder, no file is opened.
    public static func discover(readers: [any ProviderReader] = all,
                                home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                settings: BrimlineSettings) -> [Account] {
        readers.filter { settings.isEnabled($0.provider) }
            .flatMap { $0.discover(home: home, settings: settings) }
    }
}
