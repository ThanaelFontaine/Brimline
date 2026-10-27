import Foundation

/// The text `brimline status` prints for one account: its title, its sentence, one row per limit.
/// In Core so that a test reads what the command says (the command itself is only the plumbing).
public enum StatusText {
    /// The title is the one of the panel: Claude's address, or the provider and its plan ("ChatGPT Plus"), or the
    /// label the user gave with the provider and plan after it. `visible` is every account shown in this answer: with
    /// several of one provider, the place of each connection goes after the title.
    public static func lines(for usage: AccountUsage, among visible: [AccountUsage], settings: BrimlineSettings,
                             strings: Strings, time: TimeFormatter, now: Date, home: URL,
                             refreshMinutes: Int) -> [String] {
        var out: [String] = []
        let account = usage.account
        let siblings = visible.filter { $0.account.provider == account.provider }.count
        var title = AccountNames.title(for: account, settings: settings)
        if let subtitle = AccountNames.subtitle(for: account, settings: settings, siblings: siblings, home: home) {
            title += " · \(subtitle)"
        }
        out.append(title)
        if let message = strings.message(for: usage), usage.status != .ok || usage.note != nil {
            out.append("  \(message)")
        }
        var rows: [(String, String, String)] = []
        for limit in usage.limits {
            let percent = strings.percentText(limit.effectivePercent(at: now))
            let reset = limit.resetsAt.map { time.reset($0, now: now) } ?? ""
            // The provider is passed: a Cursor pool of a month is "Month · Auto", not "Week · Auto".
            rows.append((strings.limitName(limit, provider: account.provider), percent, reset))
        }
        if usage.hasNoGlobalWeeklyLimit { rows.insert((strings.noGlobalWeekly, "", ""), at: min(1, rows.count)) }
        let width = rows.filter { !$0.1.isEmpty }.map(\.0.count).max() ?? 0
        for (name, percent, reset) in rows {
            if percent.isEmpty {
                out.append("  \(name)")
            } else {
                let padded = name.padding(toLength: width, withPad: " ", startingAt: 0)
                let pct = String(repeating: " ", count: max(0, 5 - percent.count)) + percent
                out.append("  \(padded)  \(pct)   \(reset)")
            }
        }
        if let age = usage.age(at: now), usage.status == .ok, age > TimeInterval(refreshMinutes * 120 + 60) {
            out.append("  " + strings.dataAge(time.age(age)))
        }
        return out
    }
}
