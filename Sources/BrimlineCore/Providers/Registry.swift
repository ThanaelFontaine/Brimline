import Foundation

/// The providers Brimline has a reader for: Claude, ChatGPT (through Codex), Gemini (through the Antigravity CLI),
/// Grok (through the Grok CLI) and Cursor (through the sign-in of its app).
///
/// Having a reader here does not mean it runs: every provider is off until the user turns it on
/// (`BrimlineSettings.enabledProviders`, Claude on by default), and `discover` and the service
/// check that before touching anything of the provider.
public enum Providers {
    /// The readers with their real Keychain and network access.
    public static var all: [any ProviderReader] { make() }

    /// The readers, with the Keychain and the network replaced (tests). The registry, not each reader, holds the
    /// closed list of URLs: every reader gets a client limited to its own `allowedURLs` (see `limited`), so a
    /// reader that forgets to restrict its client still cannot send a token anywhere it did not declare.
    public static func make(credentials: any CredentialReading = SecurityToolCredentialReader(),
                            http: any HTTPClient = URLSessionHTTPClient()) -> [any ProviderReader] {
        [limited { ClaudeReader(credentials: credentials, http: $0) }(http),
         limited { ChatGPTReader(http: $0) }(http),
         GeminiReader(),
         limited { GrokReader(http: $0) }(http),
         limited { CursorReader(http: $0) }(http)]
    }

    /// Builds a reader twice: once with the raw client to learn its `allowedURLs`, then with the client limited to
    /// them. A reader's list never depends on its client, so the two are the same reader.
    static func limited<R: ProviderReader>(_ build: @escaping @Sendable (any HTTPClient) -> R) -> (any HTTPClient) -> R {
        { http in build(http.restricted(to: build(http).allowedURLs)) }
    }

    /// Whether Brimline has a reader for this provider.
    public static func isSupported(_ provider: Provider, readers: [any ProviderReader] = all) -> Bool {
        readers.contains { $0.provider == provider }
    }

    /// Every account found by the readers of the providers that are on, in the readers' order.
    /// A provider that is off is not even looked for: no folder, no file is opened. An account marked "Do not read"
    /// is found by the existence of its path only: each reader gets the consent in `settings` and opens no file
    /// of such an account (see `ProviderReader.discover`).
    public static func discover(readers: [any ProviderReader] = all,
                                home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                settings: BrimlineSettings) -> [Account] {
        readers.filter { settings.isEnabled($0.provider) }
            .flatMap { $0.discover(home: home, settings: settings) }
    }
}
