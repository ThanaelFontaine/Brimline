import AppKit
import SightglassCore
import SwiftUI

/// The window that opens from the menu bar: one card per account, then the footer.
public struct PanelView: View {
    @Bindable var model: AppModel
    /// The images of the documentation draw a plain background instead of the system material.
    var opaqueBackground: Bool

    public init(model: AppModel, opaqueBackground: Bool = false) {
        self.model = model
        self.opaqueBackground = opaqueBackground
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            // As tall as the cards, up to 760 pt (the window then stays under 860 pt); past that the cards scroll.
            ScrollView { cards }
                .frame(maxHeight: 760)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            footer
        }
        .frame(width: SGTheme.windowWidth)
        .background(opaqueBackground ? Color(nsColor: .windowBackgroundColor) : Color.clear)
    }

    private var header: some View {
        HStack(spacing: SGTheme.Space.s) {
            Image(nsImage: SightglassGlyph.image(level: model.menuBarLevel.percent.map { $0 / 100 },
                                                 dimmed: model.menuBarLevel.dimmed))
                .accessibilityHidden(true)
            Text("Sightglass")
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
            if model.allUsages.isEmpty {
                emptyState(title: model.strings.noAccountTitle, body: model.strings.noAccountBody)
            } else if visible.isEmpty {
                emptyState(title: nil, body: model.strings.allHidden)
            } else {
                ForEach(visible) { usage in
                    AccountCard(usage: usage, model: model)
                }
            }
        }
        .padding(.horizontal, SGTheme.Space.s)
        .padding(.bottom, SGTheme.Space.s)
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

/// One account: its address, its organization, one row per limit, then its state.
struct AccountCard: View {
    var usage: AccountUsage
    var model: AppModel

    var body: some View {
        let strings = model.strings
        VStack(alignment: .leading, spacing: 0) {
            // Identity. The address wraps rather than being cut; past two lines it is shortened
            // in the middle and stays whole in the tooltip.
            Text(model.title(for: usage.account))
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
                .help(usage.account.email ?? usage.account.configDir)
            if let subtitle = model.subtitle(for: usage.account) {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 1)
            }

            if !usage.limits.isEmpty {
                VStack(alignment: .leading, spacing: SGTheme.Space.m) {
                    ForEach(rows, id: \.self) { row in
                        switch row {
                        case .limit(let limit):
                            LimitRow(limit: limit, usage: usage, model: model)
                        case .noGlobalWeekly:
                            Text(strings.noGlobalWeekly)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SGTheme.Space.m)
        .background(
            RoundedRectangle(cornerRadius: SGTheme.Radius.card, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
        .accessibilityElement(children: .contain)
    }

    enum Row: Hashable {
        case limit(UsageLimit)
        case noGlobalWeekly
    }

    /// Session, then the week (or the team seat sentence), then each model's week.
    var rows: [Row] {
        var rows: [Row] = []
        if let s = usage.sessionLimit { rows.append(.limit(s)) }
        if let w = usage.weeklyLimit {
            rows.append(.limit(w))
        } else if usage.hasNoGlobalWeeklyLimit {
            rows.append(.noGlobalWeekly)
        }
        rows += usage.modelLimits.map(Row.limit)
        return rows
    }

    var stateNote: String? {
        let strings = model.strings
        switch usage.status {
        case .ok:
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
            return strings.statusMessage(usage.status)
        }
    }

    var noteSymbol: String {
        switch usage.status {
        case .ok: return "clock"
        case .unavailable: return "icloud.slash"
        case .expired, .reconnect: return "person.crop.circle.badge.exclamationmark"
        case .signedOut: return "person.crop.circle.badge.questionmark"
        case .pending: return "hourglass"
        }
    }
}

/// One limit: its name and percentage, the gauge, then when it resets.
struct LimitRow: View {
    var limit: UsageLimit
    var usage: AccountUsage
    var model: AppModel

    var body: some View {
        let strings = model.strings
        let now = model.now
        let percent = limit.effectivePercent(at: now)
        // Unavailable: the number is not shown (it could be wrong), the gauge is an empty dotted tube.
        let unavailable = usage.status == .unavailable
        // Expired or refused sign-in: the last known number, in grey, with its age.
        let muted = usage.status == .expired || usage.status == .reconnect

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(strings.limitName(limit))
                    .font(.system(size: 12))
                    .lineLimit(1)
                Spacer(minLength: SGTheme.Space.s)
                Text(unavailable ? strings.unavailableShort : strings.percentText(limit.resetsAt.map { $0 <= now } == true ? 0 : limit.percent))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(muted ? .secondary : .primary)
            }
            SGGauge(gaugeState(percent: percent, muted: muted, unavailable: unavailable),
                    accessibilityName: strings.limitName(limit),
                    accessibilityValue: unavailable ? strings.unavailableShort
                        : strings.accessibilityPercent(percent, expired: muted))
                .padding(.top, SGTheme.Space.s)
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
        if let resets = limit.resetsAt {
            // A past reset is said for grey values ("has reset"), so a 0 % reads as reset, not as unused.
            if resets > model.now || !unavailable { parts.append(model.time.reset(resets, now: model.now)) }
        }
        if percent >= 100 && !muted && !unavailable && !parts.isEmpty {
            return "\(strings.limitReached) · " + parts.joined(separator: " · ")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
