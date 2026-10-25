import Foundation

/// The languages of the interface: English by default, French.
public enum Language: String, Sendable, CaseIterable {
    case en
    case fr

    /// The language of the user, or the `SIGHTGLASS_LANG` variable when it is set (tests, images).
    public static var current: Language {
        if let forced = ProcessInfo.processInfo.environment["SIGHTGLASS_LANG"], let l = Language(rawValue: forced) {
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

    /// "resets in 2 h 10 (14:30)" / "repart dans 2 h 10 (14:30)"; "has reset" once the time is past.
    public func reset(_ resetsAt: Date, now: Date) -> String {
        let remaining = resetsAt.timeIntervalSince(now)
        if remaining <= 0 { return language == .fr ? "remis à zéro" : "has reset" }
        let at = clock(resetsAt, withDay: remaining >= 24 * 3600)
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
        case .weeklyModel: return weekModel(limit.model ?? "?")
        }
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
        t("Usage unavailable for now, Sightglass will try again", "Usage indisponible pour l'instant, nouvel essai plus tard")
    }
    public var signedOutMessage: String {
        t("Not signed in: run /login in Claude Code with this folder", "Pas connecté : lancez /login dans Claude Code avec ce dossier")
    }
    public var pendingMessage: String { t("Not read yet", "Pas encore lu") }
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
        }
    }

    public func statusMessage(_ status: AccountStatus) -> String? {
        switch status {
        case .ok: return nil
        case .expired: return expiredMessage
        case .reconnect: return reconnectMessage
        case .unavailable: return unavailableMessage
        case .signedOut: return signedOutMessage
        case .pending: return pendingMessage
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
    public var allHidden: String { t("Every account is hidden in the settings.", "Tous les comptes sont masqués dans les réglages.") }

    // Settings.
    public var settingsTitle: String { t("Sightglass Settings", "Réglages de Sightglass") }
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
    public var otherProviders: String { t("Other providers", "Autres fournisseurs") }
    public var accountsIntro: String {
        t("Sightglass finds each Claude Code configuration folder by itself: ~/.claude, and every ~/.claude-\u{2060}* folder.",
          "Sightglass trouve seul chaque dossier de configuration de Claude Code : ~/.claude, et chaque dossier ~/.claude-\u{2060}*.")
    }
    public var chooseFolderMessage: String {
        t("Choose a Claude Code configuration folder (the one CLAUDE_CONFIG_DIR points to).",
          "Choisissez un dossier de configuration de Claude Code (celui que désigne CLAUDE_CONFIG_DIR).")
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
        t("Read only: Sightglass never refreshes, rewrites or moves a token.",
          "Lecture seule : Sightglass ne renouvelle, ne réécrit et ne déplace jamais un jeton.")
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
        percent.map { "Sightglass, \(percentText($0))" } ?? "Sightglass"
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
    public static let documentationBase = URL(string: "https://github.com/ThanaelFontaine/Sightglass/blob/main/docs/")!
    /// The guide to linking an account, in French when the interface is in French.
    public static func accountsDoc(_ language: Language) -> URL {
        documentationBase.appendingPathComponent(language == .fr ? "accounts.fr.md" : "accounts.md")
    }
    public static var agentsDoc: URL { documentationBase.appendingPathComponent("agents.md") }
    public static var faq: URL { documentationBase.appendingPathComponent("faq.md") }
    public static let repository = URL(string: "https://github.com/ThanaelFontaine/Sightglass")!
}
