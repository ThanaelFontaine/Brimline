import Foundation

/// The languages of the interface: English by default, French.
public enum Language: String, Sendable, CaseIterable {
    case en
    case fr

    /// The language of the user, or the `BRIMLINE_LANG` variable when it is set (tests, images).
    public static var current: Language {
        if let forced = ProcessInfo.processInfo.environment["BRIMLINE_LANG"], let l = Language(rawValue: forced) {
            return l
        }
        return Locale.preferredLanguages.first?.hasPrefix("fr") == true ? .fr : .en
    }

    public var locale: Locale { Locale(identifier: self == .fr ? "fr_FR" : "en_US") }
}

/// Time texts: "resets in 2 h 10 (14:30)", "repart dans 2 h 10 (14:30)", ages, clock times.
public struct TimeFormatter: Sendable {
    public var language: Language
    public var timeZone: TimeZone

    public init(language: Language = .current, timeZone: TimeZone = .current) {
        self.language = language
        self.timeZone = timeZone
    }

    /// "2 h 10", "45 min", "3 d 4 h" / "3 j 4 h", "less than a minute".
    public func duration(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int((max(0, seconds) / 60).rounded(.up))
        if totalMinutes < 1 { return language == .fr ? "moins d'une minute" : "less than a minute" }
        if totalMinutes < 60 { return "\(totalMinutes) min" }
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60
        if days > 0 {
            let d = language == .fr ? "j" : "d"
            return hours > 0 ? "\(days) \(d) \(hours) h" : "\(days) \(d)"
        }
        return minutes > 0 ? "\(hours) h \(String(format: "%02d", minutes))" : "\(hours) h"
    }

    /// "14:30", or "Mon 14:30" / "lun. 14:30" with the weekday when `withDay` is true.
    public func clock(_ date: Date, withDay: Bool = false) -> String {
        let f = DateFormatter()
        f.locale = language.locale
        f.timeZone = timeZone
        f.dateFormat = withDay ? "EEE HH:mm" : "HH:mm"
        return f.string(from: date)
    }

    /// "Sun Nov 8" / "dim. 8 nov.".
    public func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = language.locale
        f.timeZone = timeZone
        f.dateFormat = language == .fr ? "EEE d MMM" : "EEE MMM d"
        return f.string(from: date)
    }

    /// "resets in 2 h 10 (14:30)" / "repart dans 2 h 10 (14:30)"; "has reset" once the time is past.
    public func reset(_ resetsAt: Date, now: Date) -> String {
        let remaining = resetsAt.timeIntervalSince(now)
        if remaining <= 0 { return language == .fr ? "remis à zéro" : "has reset" }
        // Past 6 days a weekday alone is ambiguous: the reset says its date ("Sun Nov 8").
        let at = remaining > 6 * 24 * 3600 ? shortDate(resetsAt) : clock(resetsAt, withDay: remaining >= 24 * 3600)
        let prefix = language == .fr ? "repart dans" : "resets in"
        return "\(prefix) \(duration(remaining)) (\(at))"
    }

    /// "3 min ago" / "il y a 3 min".
    public func age(_ seconds: TimeInterval) -> String {
        let text = duration(seconds)
        return language == .fr ? "il y a \(text)" : "\(text) ago"
    }
}

/// Every text of the interface, in English and French.
public struct Strings: Sendable {
    public var language: Language

    public init(_ language: Language = .current) {
        self.language = language
    }

    private func t(_ en: String, _ fr: String) -> String { language == .fr ? fr : en }

    // Limits.
    public var session: String { t("5 h session", "Session 5 h") }
    public var week: String { t("Week", "Semaine") }
    public func weekModel(_ model: String) -> String { t("Week · \(model)", "Semaine · \(model)") }
    public func limitName(_ limit: UsageLimit) -> String {
        switch limit.kind {
        case .session: return session
        case .weekly: return week
        case .model: return limit.label ?? weekModel(limit.model ?? "?")
        case .daily: return t("Day", "Jour")
        case .monthly: return t("Month", "Mois")
        case .period: return limit.label ?? periodName(seconds: limit.windowSeconds)
        }
    }

    /// The name of a limit in a provider's card. A limit of one model reads "<window> · <model>" ("5 h · codex-mini",
    /// "Week · Fable", "Month · Auto"); Grok's credits read "Credits · week"; a period says its length ("30-day period").
    /// Without a provider this is `limitName(_:)`.
    public func limitName(_ limit: UsageLimit, provider: Provider) -> String {
        switch limit.kind {
        case .model:
            guard let model = limit.model else { return limitName(limit) }
            guard let seconds = limit.windowSeconds else { return limitName(limit) }
            return "\(windowName(seconds: seconds)) · \(model)"
        case .period:
            if provider == .grok {
                let credits = t("Credits", "Crédits")
                switch limit.windowSeconds {
                case 604_800?: return "\(credits) · \(t("week", "semaine"))"
                case let s? where (28 * 86_400...31 * 86_400).contains(s): return "\(credits) · \(t("month", "mois"))"
                default: return credits
                }
            }
            if let label = limit.label { return label }
            guard let seconds = limit.windowSeconds else { return t("Period", "Période") }
            if seconds == 604_800 { return week }
            if seconds % 86_400 == 0 { return t("\(seconds / 86_400)-day period", "Période de \(seconds / 86_400) j") }
            if seconds % 3_600 == 0 { return t("\(seconds / 3_600)-hour period", "Période de \(seconds / 3_600) h") }
            return t("Period", "Période")
        default:
            return limitName(limit)
        }
    }
    /// The length of a window as the first part of a sub-limit's name: "5 h", "Week", "Day", "Month", "3 d", "12 h".
    private func windowName(seconds: Int) -> String {
        switch seconds {
        case 18_000: return "5 h"
        case 604_800: return week
        case 86_400: return t("Day", "Jour")
        case (28 * 86_400)...(31 * 86_400): return t("Month", "Mois")
        default:
            let d = t("d", "j")
            if seconds % 86_400 == 0 { return "\(seconds / 86_400) \(d)" }
            if seconds % 3_600 == 0 { return "\(seconds / 3_600) h" }
            return "\(max(1, seconds / 60)) min"
        }
    }
    /// A week or a month by its length (Grok's credits renew weekly or monthly), "Period" otherwise.
    private func periodName(seconds: Int?) -> String {
        guard let seconds else { return t("Period", "Période") }
        if seconds == 604_800 { return week }
        if (28 * 86_400...31 * 86_400).contains(seconds) { return t("Month", "Mois") }
        return t("Period", "Période")
    }
    public var noGlobalWeekly: String { t("No weekly limit across all models", "Pas de limite hebdomadaire globale") }
    // States.
    public var expiredMessage: String {
        t("Session expired: open Claude Code with this account to sign it in again",
          "Session expirée : ouvrez Claude Code avec ce compte pour la reconnecter")
    }
    public var reconnectMessage: String {
        t("Sign-in refused: run /login in Claude Code with this account",
          "Connexion refusée : lancez /login dans Claude Code avec ce compte")
    }
    public var unavailableMessage: String {
        t("Usage unavailable for now, Brimline will try again", "Usage indisponible pour l'instant, nouvel essai plus tard")
    }
    public var signedOutMessage: String {
        t("Not signed in: run /login in Claude Code with this folder", "Pas connecté : lancez /login dans Claude Code avec ce dossier")
    }
    public var pendingMessage: String { t("Not read yet", "Pas encore lu") }
    public var formatChangedMessage: String {
        t("The provider changed its answer: update Brimline.", "Le fournisseur a changé sa réponse : mettez Brimline à jour.")
    }
    /// The generic sentence for an account with no readable limit. Each provider's own sentence (what
    /// to open, where the limits are) is added with its reader.
    public var notReadableMessage: String {
        t("Brimline cannot read the limits of this account.", "Brimline ne peut pas lire les limites de ce compte.")
    }
    /// What Google says about Gemini: the sentence of an account that has no readable limit.
    public var geminiNotReadableMessage: String {
        t("Google does not publish Gemini limits in a form Brimline can read. They are in the Gemini app (Settings, Usage limits) and in Gemini CLI (/stats model).",
          "Google ne publie pas les limites de Gemini sous une forme que Brimline peut lire. Elles sont dans l'app Gemini (Réglages, Limites d'utilisation) et dans Gemini CLI (/stats model).")
    }
    /// Antigravity's sign-in has expired or was refused: Google's program renews it itself when it is opened.
    public var geminiExpiredMessage: String {
        t("Open Antigravity to refresh the sign-in.", "Ouvrez Antigravity pour rafraîchir la connexion.")
    }
    /// An Antigravity that Brimline has not verified (a new version, another build): nothing is launched.
    public var geminiFormatChangedMessage: String {
        t("Antigravity was updated: update Brimline.", "Antigravity a été mis à jour : mettez Brimline à jour.")
    }
    /// Codex is signed in with an API key: there is no subscription limit.
    public var chatgptAPIKeyMessage: String {
        t("Codex is signed in with an API key: there is no subscription limit to show.",
          "Codex est connecté par une clé d'API : il n'a pas de limite d'abonnement à montrer.")
    }
    /// No `auth.json` in Codex's folder: its sign-in is in the Keychain, or it is signed out.
    public var chatgptSignedOutMessage: String {
        t("Codex keeps its sign-in in the Keychain or is signed out: Brimline only reads ~/.codex/auth.json.",
          "Codex range sa connexion dans le Trousseau ou n'est pas connecté : Brimline ne lit que ~/.codex/auth.json.")
    }
    public var chatgptExpiredMessage: String {
        t("Open Codex to refresh the sign-in.", "Ouvrez Codex pour rafraîchir la connexion.")
    }
    public var chatgptReconnectMessage: String {
        t("ChatGPT refused Codex's sign-in: open Codex and sign in again.",
          "ChatGPT a refusé la connexion de Codex : ouvrez Codex et reconnectez-vous.")
    }
    public func lastKnown(_ age: String) -> String { t("Last known values, \(age)", "Dernières valeurs connues, \(age)") }
    public func dataAge(_ age: String) -> String { t("Data from \(age)", "Données d'\(age)") }

    public func statusName(_ status: AccountStatus) -> String {
        switch status {
        case .ok: return t("Up to date", "À jour")
        case .expired: return t("Session expired", "Session expirée")
        case .reconnect: return t("Sign in again", "À reconnecter")
        case .unavailable: return t("Unavailable", "Indisponible")
        case .signedOut: return t("Not signed in", "Pas connecté")
        case .pending: return t("Not read yet", "Pas encore lu")
        case .notReadable: return t("Not readable", "Non lisible")
        case .formatChanged: return t("Format changed", "Format modifié")
        }
    }

    /// Grok limits exist for the Grok CLI only: no `~/.grok` sign-in, no limit to read.
    public var grokNoCLIMessage: String {
        t("xAI only publishes Grok limits for the Grok CLI. Without it, they are in your Grok account settings.",
          "xAI ne publie les limites de Grok que pour le CLI Grok. Sans lui, elles sont dans les réglages de votre compte Grok.")
    }
    /// The Grok CLI is signed in with an API key: there is no subscription limit.
    public var grokAPIKeyMessage: String {
        t("The Grok CLI is signed in with an API key: there is no subscription limit to show.",
          "Le CLI Grok est connecté par une clé d'API : il n'a pas de limite d'abonnement à montrer.")
    }
    public var grokExpiredMessage: String {
        t("Open the Grok CLI to refresh the sign-in.", "Ouvrez le CLI Grok pour rafraîchir la connexion.")
    }
    public var grokReconnectMessage: String {
        t("xAI refused the Grok CLI's sign-in: run grok login again.",
          "xAI a refusé la connexion du CLI Grok : relancez grok login.")
    }
    public var noFigureYetMessage: String {
        t("No number yet for this period.", "Pas encore de chiffre pour cette période.")
    }
    /// Under a Grok account's title when its credits are a pool shared by the Grok products.
    public var sharedPoolSubtitle: String { t("Credits shared across Grok products", "Crédits partagés entre les produits Grok") }
    public var resetNotPublishedMessage: String {
        t("Reset time not published by Google", "Remise à zéro non publiée par Google")
    }
    public var sharedPoolMessage: String {
        t("This limit is a pool shared by the Grok products.", "Cette limite est un pool partagé entre les produits Grok.")
    }

    public func statusMessage(_ status: AccountStatus) -> String? {
        switch status {
        case .ok: return nil
        case .expired: return expiredMessage
        case .reconnect: return reconnectMessage
        case .unavailable: return unavailableMessage
        case .signedOut: return signedOutMessage
        case .pending: return pendingMessage
        case .notReadable: return notReadableMessage
        case .formatChanged: return formatChangedMessage
        }
    }

    /// The message of an account: the sentence of its provider when it is not readable by design, the
    /// message of its status otherwise.
    public func message(for usage: AccountUsage) -> String? {
        if usage.status == .ok, let note = usage.note { return noteMessage(note) }
        switch (usage.account.provider, usage.status, usage.reason) {
        case (.gemini, .notReadable, .consumerPlan?): return geminiNotReadableMessage
        case (.gemini, .expired, _): return geminiExpiredMessage
        case (.gemini, .formatChanged, _): return geminiFormatChangedMessage
        case (.chatgpt, .notReadable, .apiKey?): return chatgptAPIKeyMessage
        case (.chatgpt, .notReadable, .keychainOrSignedOut?): return chatgptSignedOutMessage
        case (.chatgpt, .expired, _): return chatgptExpiredMessage
        case (.chatgpt, .reconnect, _): return chatgptReconnectMessage
        case (.grok, .notReadable, .noCLI?): return grokNoCLIMessage
        case (.grok, .notReadable, .apiKey?): return grokAPIKeyMessage
        case (.grok, .expired, _): return grokExpiredMessage
        case (.grok, .reconnect, _): return grokReconnectMessage
        default: return statusMessage(usage.status)
        }
    }

    public func noteMessage(_ note: AccountNote) -> String {
        switch note {
        case .noFigureYet: return noFigureYetMessage
        case .sharedPool: return sharedPoolMessage
        case .resetNotPublished: return resetNotPublishedMessage
        }
    }

    // Panel.
    public func updatedAt(_ time: String) -> String { t("Updated at \(time)", "Actualisé à \(time)") }
    public var neverUpdated: String { t("Not updated yet", "Pas encore actualisé") }
    public var refresh: String { t("Refresh", "Actualiser") }
    public var refreshing: String { t("Refreshing…", "Actualisation…") }
    public var settingsEllipsis: String { t("Settings…", "Réglages…") }
    public var quit: String { t("Quit", "Quitter") }
    public var noAccountTitle: String { t("No account found", "Aucun compte trouvé") }
    public var noAccountBody: String {
        t("Sign in to Claude Code, or add its folder in the settings.",
          "Connectez-vous à Claude Code, ou ajoutez son dossier dans les réglages.")
    }
    public var allProvidersOff: String {
        t("Every provider is off. Turn one on in the settings.", "Tous les fournisseurs sont coupés. Allumez-en un dans les réglages.")
    }
    public var allHidden: String { t("Every account is hidden in the settings.", "Tous les comptes sont masqués dans les réglages.") }

    // Settings.
    public var settingsTitle: String { t("Brimline Settings", "Réglages de Brimline") }
    public var tabAccounts: String { t("Accounts", "Comptes") }
    public var tabGeneral: String { t("General", "Général") }
    public var tabAgents: String { t("Agents", "Agents") }
    public var tabAbout: String { t("About", "À propos") }
    public var howToLink: String { t("How do I link an account?", "Comment associer un compte ?") }
    public var addFolder: String { t("Add a Claude Code folder…", "Ajouter un dossier Claude Code…") }
    public var rescan: String { t("Search again", "Rechercher à nouveau") }
    public var show: String { t("Show", "Afficher") }
    public var customLabel: String { t("Custom label", "Libellé personnalisé") }
    public var folder: String { t("Folder", "Dossier") }
    public var removeFolder: String { t("Remove", "Retirer") }
    public var comingSoon: String { t("Coming soon", "Bientôt") }
    public var doNotRead: String { t("Don't read this account", "Ne pas lire ce compte") }
    public var doNotReadHelp: String {
        t("Brimline keeps its last numbers and no longer opens its sign-in.",
          "Brimline garde ses derniers chiffres et n'ouvre plus sa connexion.")
    }
    public var whatIsRead: String { t("What is read", "Ce qui est lu") }
    public func readProvider(_ name: String) -> String { t("Read \(name)", "Lire \(name)") }
    public var addCodexFolder: String { t("Add a Codex folder…", "Ajouter un dossier Codex…") }
    public var learnMore: String { t("Learn more", "En savoir plus") }
    /// The line under a provider's name in a group header ("ChatGPT via Codex").
    public func qualifier(for provider: Provider) -> String? {
        provider == .chatgpt ? t("via Codex", "par Codex") : nil
    }
    /// What Brimline reads for a provider and where it asks, as the settings say it. Off, the same thing
    /// is said as a promise: nothing is read until the switch is turned on.
    public func providerCaption(_ provider: Provider, on: Bool) -> String {
        let verb: String
        switch provider {
        case .claude:
            verb = t("reads the Claude Code sign-in from the Keychain and asks api.anthropic.com for usage.",
                     "lit la connexion de Claude Code dans le Trousseau et demande l'usage à api.anthropic.com.")
        case .chatgpt:
            verb = t("reads ~/.codex/auth.json and asks chatgpt.com for usage.",
                     "lit ~/.codex/auth.json et demande l'usage à chatgpt.com.")
        case .gemini:
            verb = t("launches Antigravity (agy --print /usage) when it is installed and shows the limits it reports; without it, Brimline says where to see them.",
                     "lance Antigravity (agy --print /usage) quand il est installé et montre les limites qu'il donne ; sans lui, Brimline dit où les voir.")
        case .grok:
            verb = t("reads ~/.grok/auth.json and asks cli-chat-proxy.grok.com for usage.",
                     "lit ~/.grok/auth.json et demande l'usage à cli-chat-proxy.grok.com.")
        case .cursor:
            verb = t("looks for the Cursor app sign-in, read only. Brimline does not read Cursor usage yet.",
                     "cherche la connexion de l'app Cursor, en lecture seule. Brimline ne lit pas encore l'usage de Cursor.")
        }
        if on { return verb.prefix(1).uppercased() + verb.dropFirst() }
        return t("Off: Brimline reads nothing. When on, it \(verb)", "Coupé : Brimline ne lit rien. Allumé, il \(verb)")
    }
    /// An account the user marked "Do not read", in the panel and in the settings.
    public var readingOffNote: String { t("Reading turned off in Settings", "Lecture coupée dans les Réglages") }
    public var readingOffStatus: String { t("Reading off", "Lecture coupée") }
    /// A provider that is on but has no account on this Mac.
    public func noSignIn(_ provider: Provider) -> String {
        switch provider {
        case .claude: return noAccountBody
        case .chatgpt:
            return t("No Codex sign-in found on this Mac. Sign in to Codex, then refresh.",
                     "Aucune connexion de Codex trouvée sur ce Mac. Connectez-vous à Codex, puis actualisez.")
        case .gemini: return geminiNotReadableMessage
        case .grok:
            return t("No Grok CLI sign-in found on this Mac. Run grok login, then refresh.",
                     "Aucune connexion du CLI Grok trouvée sur ce Mac. Lancez grok login, puis actualisez.")
        case .cursor:
            return t("No Cursor app found on this Mac. Sign in to Cursor, then refresh.",
                     "Aucune app Cursor trouvée sur ce Mac. Connectez-vous à Cursor, puis actualisez.")
        }
    }
    /// Shown once, under the cards, while only Claude is on.
    public var providerHint: String {
        t("Brimline can also read ChatGPT (via Codex) and Grok, and tell you where to see Gemini limits. Each stays off until you turn it on.",
          "Brimline peut aussi lire ChatGPT (par Codex) et Grok, et vous dire où voir les limites de Gemini. Chacun reste coupé tant que vous ne l'allumez pas.")
    }
    public var dismiss: String { t("Dismiss", "Masquer") }
    /// A sentence cut after its first full stop: the first part, then the rest ("Learn more" shows it).
    /// A text with a single sentence has no rest.
    public static func splitSentence(_ text: String) -> (first: String, rest: String?) {
        guard let range = text.range(of: ". ") else { return (text, nil) }
        let first = String(text[..<range.upperBound]).trimmingCharacters(in: .whitespaces)
        let rest = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        return (first, rest.isEmpty ? nil : rest)
    }
    public var accountsIntro: String {
        t("Brimline only reads the providers you turn on here. A provider that is off is never read: no file opened, no request sent.",
          "Brimline ne lit que les fournisseurs que vous allumez ici. Un fournisseur coupé n'est jamais lu : aucun fichier ouvert, aucune requête.")
    }
    public var chooseFolderMessage: String {
        t("Choose a Claude Code configuration folder (the one CLAUDE_CONFIG_DIR points to).",
          "Choisissez un dossier de configuration de Claude Code (celui que désigne CLAUDE_CONFIG_DIR).")
    }
    public var chooseCodexFolderMessage: String {
        t("Choose a Codex folder (the one CODEX_HOME points to). Only its auth.json is read.",
          "Choisissez un dossier de Codex (celui que désigne CODEX_HOME). Seul son auth.json est lu.")
    }
    public var refreshEvery: String { t("Refresh every", "Actualiser toutes les") }
    public func minutes(_ n: Int) -> String { "\(n) min" }
    public var percentInMenuBar: String { t("Show the percentage in the menu bar", "Afficher le pourcentage dans la barre des menus") }
    public var openAtLogin: String { t("Open at login", "Ouvrir à la connexion") }
    public var openAtLoginHelp: String {
        t("Writes a LaunchAgent in ~/Library/LaunchAgents, removed when you turn this off.",
          "Écrit un LaunchAgent dans ~/Library/LaunchAgents, retiré quand vous désactivez l'option.")
    }
    public var menuBarHelp: String {
        t("The menu bar glyph follows the account closest to its limit.",
          "Le glyphe de la barre des menus suit le compte le plus proche de sa limite.")
    }
    public var agentsIntro: String {
        t("Your agents read the same numbers: a command with JSON output and a local MCP server. They read the cache written by the app and never see a token.",
          "Vos agents lisent les mêmes chiffres : une commande à sortie JSON et un serveur MCP local. Ils lisent le cache écrit par l'app et ne voient jamais de jeton.")
    }
    public var commandPath: String { t("Command", "Commande") }
    public var mcpClaudeCode: String { t("Add to Claude Code", "Ajouter à Claude Code") }
    public var mcpJSON: String { t("MCP configuration (JSON)", "Configuration MCP (JSON)") }
    public var cachePath: String { t("Cache", "Cache") }
    public var copy: String { t("Copy", "Copier") }
    public var copied: String { t("Copied", "Copié") }
    public var agentsDoc: String { t("Agents documentation", "Documentation pour les agents") }
    public var version: String { t("Version", "Version") }
    public var development: String { t("development version", "version de développement") }
    public var licenseLine: String {
        t("Public source code under the PolyForm Shield 1.0.0 license",
          "Code source public sous licence PolyForm Shield 1.0.0")
    }
    public var tagline: String {
        t("Your AI subscription limits, account by account, in the menu bar.",
          "Les limites de vos abonnements IA, compte par compte, dans la barre des menus.")
    }
    public var documentation: String { t("Documentation", "Documentation") }
    public var readOnlyNote: String {
        t("Read only: Brimline never refreshes, rewrites or moves a token.",
          "Lecture seule : Brimline ne renouvelle, ne réécrit et ne déplace jamais un jeton.")
    }
    public var gaugeLabel: String { t("Usage", "Utilisation") }
    /// "Head: rest" in English, "Head : rest" in French.
    public func colon(_ head: String, _ rest: String) -> String { t("\(head): \(rest)", "\(head) : \(rest)") }
    public var limitReached: String { t("Limit reached", "Limite atteinte") }
    public func retryAt(_ time: String) -> String { t("next try at \(time)", "nouvel essai à \(time)") }
    public func valueFrom(_ age: String) -> String { t("value from \(age)", "valeur d'\(age)") }
    public var unavailableShort: String { t("Unavailable", "Indisponible") }
    public var expiredShort: String { t("expired", "expiré") }
    /// "72%" in English, "72 %" in French.
    public func percentText(_ value: Double) -> String {
        let n = Int(value.rounded())
        return t("\(n)%", "\(n) %")
    }
    public func accessibilityPercent(_ value: Double, expired: Bool) -> String {
        expired ? "\(percentText(value)), \(expiredShort)" : percentText(value)
    }
    public func menuBarAccessibility(_ percent: Double?) -> String {
        percent.map { "Brimline, \(percentText($0))" } ?? "Brimline"
    }
    /// "Brimline, 91%, Claude, Research lab": the number, then whose it is.
    public func menuBarAccessibility(_ percent: Double?, provider: Provider?, account: String?) -> String {
        guard percent != nil else { return "Brimline" }
        return ([menuBarAccessibility(percent)] + [provider?.displayName, account].compactMap { $0 }).joined(separator: ", ")
    }
    public func reason(_ detail: String?) -> String? {
        guard let detail else { return nil }
        switch detail {
        case "network": return t("no network answer", "pas de réponse du réseau")
        case "unknown answer": return t("answer not understood (the endpoint may have changed)", "réponse non comprise (le point d'accès a peut-être changé)")
        default:
            if detail.hasPrefix("HTTP 429") { return t("rate limited (HTTP 429)", "trop de requêtes (HTTP 429)") }
            if detail.hasPrefix("HTTP 5") { return t("provider error (\(detail))", "erreur du fournisseur (\(detail))") }
            if detail.hasPrefix("security") { return t("Keychain not readable", "Trousseau illisible") }
            return detail
        }
    }
}

/// Fixed links. The documentation base is the single place to change when the site goes live;
/// until then the app links to the documentation in the repository and shows no website link.
public enum Links {
    public static let documentationBase = URL(string: "https://github.com/ThanaelFontaine/Brimline/blob/main/docs/")!
    /// The guide to linking an account, in French when the interface is in French.
    public static func accountsDoc(_ language: Language) -> URL {
        documentationBase.appendingPathComponent(language == .fr ? "accounts.fr.md" : "accounts.md")
    }
    /// What Brimline reads for each provider (the "What is read" link of the settings).
    public static var providersDoc: URL { documentationBase.appendingPathComponent("providers.md") }
    public static var agentsDoc: URL { documentationBase.appendingPathComponent("agents.md") }
    public static var faq: URL { documentationBase.appendingPathComponent("faq.md") }
    public static let repository = URL(string: "https://github.com/ThanaelFontaine/Brimline")!
}
