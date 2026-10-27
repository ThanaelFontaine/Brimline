import AppKit
import BrimlineCore
import SwiftUI

/// The window that opens from the menu bar: one card per account, then the footer.
public struct PanelView: View {
    @Bindable var model: AppModel
    /// The images of the documentation draw a plain background instead of the system material.
    var opaqueBackground: Bool
    /// The cards scroll past this height; the images of the QA lift it to show every card.
    var maxCardsHeight: CGFloat

    public init(model: AppModel, opaqueBackground: Bool = false, maxCardsHeight: CGFloat = 760) {
        self.model = model
        self.opaqueBackground = opaqueBackground
        self.maxCardsHeight = maxCardsHeight
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            // As tall as the cards, up to 760 pt (the window then stays under 860 pt); past that the cards scroll.
            ScrollView { cards }
                .frame(maxHeight: maxCardsHeight)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            footer
        }
        .frame(width: SGTheme.windowWidth)
        .background(opaqueBackground ? Color(nsColor: .windowBackgroundColor) : Color.clear)
    }

    private var header: some View {
        HStack(spacing: SGTheme.Space.s) {
            Image(nsImage: BrimlineGlyph.image(level: model.menuBarLevel.percent.map { $0 / 100 },
                                                 dimmed: model.menuBarLevel.dimmed))
                .accessibilityHidden(true)
            Text("Brimline")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if model.isRefreshing {
                ProgressView().controlSize(.small)
                    .accessibilityLabel(model.strings.refreshing)
            }
        }
        .padding(.horizontal, SGTheme.Space.l)
        .padding(.top, SGTheme.Space.m)
        .padding(.bottom, SGTheme.Space.s)
    }

    @ViewBuilder
    private var cards: some View {
        VStack(spacing: SGTheme.Space.s) {
            let visible = model.visibleUsages
            let groups = model.groups
            if model.enabledProviders.isEmpty {
                emptyState(title: nil, body: model.strings.allProvidersOff)
            } else if model.allUsages.isEmpty && model.enabledProviders == [.claude] {
                emptyState(title: model.strings.noAccountTitle, body: model.strings.noAccountBody)
            } else if visible.isEmpty && !model.allUsages.isEmpty {
                emptyState(title: nil, body: model.strings.allHidden)
            } else {
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    GroupHeader(provider: group.provider, strings: model.strings)
                        .padding(.top, index == 0 ? 0 : SGTheme.Space.s)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if group.usages.isEmpty {
                        NoAccountCard(provider: group.provider, model: model)
                    }
                    ForEach(group.usages) { usage in
                        AccountCard(usage: usage, model: model)
                    }
                }
                if model.showsProviderHint {
                    hintCard
                }
            }
        }
        .padding(.horizontal, SGTheme.Space.s)
        .padding(.bottom, SGTheme.Space.s)
    }

    /// Shown once, while only Claude is on: other providers exist, and none is read until turned on.
    private var hintCard: some View {
        VStack(alignment: .leading, spacing: SGTheme.Space.s) {
            Label {
                Text(model.strings.providerHint)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "sparkles")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            HStack(spacing: SGTheme.Space.m) {
                Button(model.strings.settingsEllipsis) { model.openSettings() }
                    .foregroundStyle(SGTheme.accent)
                Button(model.strings.dismiss) { model.dismissProviderHint() }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SGTheme.Space.m)
        .background(
            RoundedRectangle(cornerRadius: SGTheme.Radius.card, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.15))
        )
    }

    private func emptyState(title: String?, body: String) -> some View {
        VStack(spacing: SGTheme.Space.xs) {
            if let title {
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            Text(body)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(model.strings.settingsEllipsis) { model.openSettings() }
                .buttonStyle(.link)
                .tint(SGTheme.accent)
                .foregroundStyle(SGTheme.accent)
                .font(.system(size: 12))
                .padding(.top, SGTheme.Space.xs)
        }
        .frame(maxWidth: .infinity)
        .padding(SGTheme.Space.l)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: SGTheme.Radius.card, style: .continuous)
            .fill(Color.primary.opacity(0.045))
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Text(updatedText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: SGTheme.Space.xs)
            Button(model.strings.refresh) { model.refreshNow() }
                .foregroundStyle(SGTheme.accent)
                .disabled(model.isRefreshing)
                .keyboardShortcut("r")
            Button(model.strings.settingsEllipsis) { model.openSettings() }
                .keyboardShortcut(",")
            Button(model.strings.quit) { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 12))
        .padding(.horizontal, SGTheme.Space.l)
        .padding(.vertical, SGTheme.Space.m - 2)
    }

    private var updatedText: String {
        guard let last = model.lastUpdate else { return model.strings.neverUpdated }
        return model.strings.updatedAt(model.time.clock(last))
    }
}

/// The heading of a provider's group: its dot, its name, and what it goes through ("via Codex").
struct GroupHeader: View {
    var provider: Provider
    var strings: Strings

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            SGProviderDot(provider)
            Text(provider.displayName)
                .font(.system(size: 12, weight: .semibold))
            if let qualifier = strings.qualifier(for: provider) {
                Text(qualifier)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, SGTheme.Space.xs)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

private extension View {
    func cardStyle() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SGTheme.Space.m)
            .background(
                RoundedRectangle(cornerRadius: SGTheme.Radius.card, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
    }
}

/// A provider that is on but has no account on this Mac: one sentence says what to do.
struct NoAccountCard: View {
    var provider: Provider
    var model: AppModel

    var body: some View {
        let sentence = model.strings.noSignIn(provider)
        let parts = Strings.splitSentence(sentence)
        HStack(alignment: .top, spacing: SGTheme.Space.s) {
            Image(systemName: provider == .gemini ? "info.circle" : "person.crop.circle.badge.questionmark")
            VStack(alignment: .leading, spacing: SGTheme.Space.xs) {
                Text(provider == .gemini ? parts.first : sentence)
                    .fixedSize(horizontal: false, vertical: true)
                if provider == .gemini { MoreText(key: "provider:\(provider.rawValue)", rest: parts.rest, model: model) }
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .cardStyle()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(provider.displayName), \(sentence)")
        .help(sentence)
    }
}

/// "Learn more", which opens the rest of a sentence in place.
struct MoreText: View {
    var key: String
    var rest: String?
    var model: AppModel

    var body: some View {
        if let rest {
            if model.expandedNotes.contains(key) {
                Text(rest)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Button(model.strings.learnMore) { model.toggleNote(accountID: key) }
                    .buttonStyle(.link)
                    .foregroundStyle(SGTheme.accent)
            }
        }
    }
}

/// One account: its name, its plan, one row per limit, then its state. An account that gives no limit shows
/// its sentence instead of any gauge.
struct AccountCard: View {
    var usage: AccountUsage
    var model: AppModel

    /// "Do not read": the numbers are the last ones, in grey, and the card says reading is off.
    var unread: Bool { model.settings.isUnread(usage.account.id) }

    /// An account Brimline cannot read by design: no number, no gauge, only its sentence.
    var isSentenceOnly: Bool { usage.status == .notReadable && usage.limits.isEmpty && !unread }

    var body: some View {
        let strings = model.strings
        let account = usage.account
        let labelled = model.settings.label(for: account.id) != nil
        VStack(alignment: .leading, spacing: 0) {
            // A card that holds a sentence only has no title unless the user named it: the group says whose it is.
            if !isSentenceOnly || labelled {
                identity
            }
            if isSentenceOnly {
                sentence.padding(.top, labelled ? SGTheme.Space.s : 0)
            }
            if !usage.limits.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        switch row {
                        case .limit(let limit, let sub, let showReset):
                            LimitRow(limit: limit, usage: usage, model: model, sub: sub, showReset: showReset)
                                .padding(.top, index == 0 ? 0 : (sub ? SGTheme.Space.s : SGTheme.Space.m))
                        case .noGlobalWeekly:
                            Text(strings.noGlobalWeekly)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, index == 0 ? 0 : SGTheme.Space.m)
                        }
                    }
                }
                .padding(.top, SGTheme.Space.m)
            }

            if let note = stateNote {
                Label {
                    Text(note)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: noteSymbol)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, SGTheme.Space.s + 2)
            }
        }
        .cardStyle()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityTitle)
    }

    /// The title and what goes under it (organization and plan, or the provider and plan under a label, the pool).
    private var identity: some View {
        let strings = model.strings
        let account = usage.account
        let subtitle = [model.subtitle(for: account), usage.note == .sharedPool ? strings.sharedPoolSubtitle : nil]
            .compactMap { $0 }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 0) {
            // The title wraps rather than being cut; past two lines it is shortened in the middle and
            // stays whole in the tooltip.
            Text(model.title(for: account))
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
                .help(account.provider == .claude ? (account.email ?? account.source) : model.displayPath(account.source))
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 1)
            }
        }
    }

    /// The sentence of an account with no readable limit: its first sentence, then "Learn more" for the rest.
    private var sentence: some View {
        let full = model.strings.message(for: usage) ?? model.strings.notReadableMessage
        let parts = Strings.splitSentence(full)
        return HStack(alignment: .top, spacing: SGTheme.Space.s) {
            Image(systemName: noteSymbol)
            VStack(alignment: .leading, spacing: SGTheme.Space.xs) {
                Text(parts.first)
                    .fixedSize(horizontal: false, vertical: true)
                MoreText(key: usage.account.id, rest: parts.rest, model: model)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        // The whole sentence stays readable whatever is folded: tooltip and VoiceOver carry it.
        .help(full)
    }

    /// VoiceOver starts every card with its provider ("ChatGPT, ChatGPT Plus"); a sentence-only card reads whole.
    private var accessibilityTitle: String {
        let provider = usage.account.provider.displayName
        if isSentenceOnly {
            return "\(provider), \(model.strings.message(for: usage) ?? model.strings.notReadableMessage)"
        }
        let title = model.title(for: usage.account)
        return title == provider ? provider : "\(provider), \(title)"
    }

    enum Row: Hashable {
        case limit(UsageLimit, sub: Bool, showReset: Bool)
        case noGlobalWeekly
    }

    /// Session, then the week (or the team seat sentence), then every other limit in the provider's order.
    /// A limit of one model is a sub-limit: a compact line, whose reset is written only when it differs from the
    /// line above.
    var rows: [Row] {
        var limits: [UsageLimit] = []
        if let s = usage.sessionLimit { limits.append(s) }
        if let w = usage.weeklyLimit { limits.append(w) }
        limits += usage.limits.filter { $0.kind != .session && $0.kind != .weekly }

        var rows: [Row] = []
        var above: UsageLimit?
        for limit in limits {
            let sub = limit.kind == .model
            var showReset = true
            if sub, let above, let a = above.resetsAt, let r = limit.resetsAt, abs(a.timeIntervalSince(r)) < 60 {
                showReset = false
            }
            rows.append(.limit(limit, sub: sub, showReset: showReset))
            above = limit
        }
        // The team seat sentence comes right after the session, where the week would be.
        if usage.weeklyLimit == nil, usage.hasNoGlobalWeeklyLimit {
            rows.insert(.noGlobalWeekly, at: usage.sessionLimit == nil ? 0 : 1)
        }
        return rows
    }

    var stateNote: String? {
        let strings = model.strings
        if unread { return strings.readingOffNote }
        if isSentenceOnly { return nil }
        switch usage.status {
        case .ok:
            // The shared pool is said under the title; the other note stays here.
            if let note = usage.note, note != .sharedPool { return strings.noteMessage(note) }
            if let age = usage.age(at: model.now), age > model.staleAfter {
                return strings.dataAge(model.time.age(age))
            }
            return nil
        case .unavailable:
            var parts: [String] = []
            if let reason = strings.reason(usage.detail) { parts.append(reason) }
            if let retry = usage.retryAfter, retry > model.now { parts.append(strings.retryAt(model.time.clock(retry))) }
            let head = strings.unavailableShort
            return parts.isEmpty ? head : strings.colon(head, parts.joined(separator: ", "))
        default:
            return strings.message(for: usage)
        }
    }

    var noteSymbol: String {
        if unread { return "pause.circle" }
        switch usage.status {
        case .ok: return usage.note == nil || usage.note == .sharedPool ? "clock" : "info.circle"
        case .unavailable: return "icloud.slash"
        case .expired, .reconnect: return "person.crop.circle.badge.exclamationmark"
        case .signedOut: return "person.crop.circle.badge.questionmark"
        case .pending: return "hourglass"
        case .notReadable: return "info.circle"
        case .formatChanged: return "exclamationmark.triangle"
        }
    }
}

/// One limit: its name and percentage, the gauge, then when it resets. A sub-limit (one model, one pool) is
/// a compact line: 11 pt text, a 4 pt gauge.
struct LimitRow: View {
    var limit: UsageLimit
    var usage: AccountUsage
    var model: AppModel
    var sub = false
    var showReset = true

    var body: some View {
        let strings = model.strings
        let now = model.now
        let name = strings.limitName(limit, provider: usage.account.provider)
        let percent = limit.effectivePercent(at: now)
        // Unavailable: the number is not shown (it could be wrong), the gauge is an empty dotted tube.
        let unavailable = usage.status == .unavailable
        // Expired or refused sign-in, an answer Brimline no longer understands, or "Do not read": the last known
        // number, in grey, with its age.
        let muted = usage.status == .expired || usage.status == .reconnect || usage.status == .formatChanged
            || model.settings.isUnread(usage.account.id)

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(name)
                    .font(.system(size: sub ? 11 : 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(name)
                Spacer(minLength: SGTheme.Space.s)
                Text(unavailable ? strings.unavailableShort : strings.percentText(limit.resetsAt.map { $0 <= now } == true ? 0 : limit.percent))
                    .font(.system(size: sub ? 11 : 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(muted ? .secondary : .primary)
            }
            SGGauge(gaugeState(percent: percent, muted: muted, unavailable: unavailable),
                    accessibilityName: name,
                    accessibilityValue: unavailable ? strings.unavailableShort
                        : strings.accessibilityPercent(percent, expired: muted),
                    compact: sub)
                .padding(.top, sub ? SGTheme.Space.xs : SGTheme.Space.s)
            if let detail = detailText(percent: percent, muted: muted) {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, SGTheme.Space.xs)
            }
        }
    }

    func gaugeState(percent: Double, muted: Bool, unavailable: Bool) -> SGGaugeState {
        if unavailable { return .unavailable }
        if muted { return .expired(last: percent / 100) }
        return .value(percent / 100)
    }

    func detailText(percent: Double, muted: Bool) -> String? {
        let strings = model.strings
        var parts: [String] = []
        let unavailable = usage.status == .unavailable
        if muted, let age = usage.age(at: model.now) {
            parts.append(strings.valueFrom(model.time.age(age)))
        }
        if showReset, let resets = limit.resetsAt {
            // A past reset is said for grey values ("has reset"), so a 0 % reads as reset, not as unused.
            if resets > model.now || !unavailable { parts.append(model.time.reset(resets, now: model.now)) }
        }
        if percent >= 100 && !muted && !unavailable && !parts.isEmpty {
            return "\(strings.limitReached) · " + parts.joined(separator: " · ")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
