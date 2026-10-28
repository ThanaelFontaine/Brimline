import Foundation

/// One part of the menu bar gauge: one account that has a number.
public struct GaugeSegment: Sendable, Equatable {
    public var accountID: String
    public var provider: Provider
    /// The account's tightest limit at `now`, from 0 to 100 (a window whose reset time has passed counts as 0).
    public var percent: Double
    /// The part of the whole gauge, from 0 to 1: `percent / 100 / N`, with `N` the number of counted accounts.
    public var share: Double
    /// The numbers are the last known ones (expired, unavailable, format changed): drawn dimmed.
    public var stale: Bool

    public init(accountID: String, provider: Provider, percent: Double, share: Double, stale: Bool) {
        self.accountID = accountID
        self.provider = provider
        self.percent = percent
        self.share = share
        self.stale = stale
    }
}

/// What the menu bar gauge shows, computed from the usages and nothing else (QUOTA-70, QUOTA-72).
public struct GaugeModel: Sendable, Equatable {
    /// One part per counted account, in the panel's order (never sorted by size, so a color never jumps).
    public var segments: [GaugeSegment]
    /// The sum of the parts, from 0 to 1: the average of the accounts' percentages.
    public var total: Double
    /// The counted account closest to its limit, up-to-date accounts first: the one the written percentage follows.
    public var mostLoaded: GaugeSegment?
    /// The counted accounts at `MenuBarGauge.alertThreshold` or above, the highest first.
    public var alerts: [GaugeSegment]
    /// The visible accounts that have no number to show (a sentence only, never read, signed out, no cap):
    /// outside the gauge so they do not dilute the others. Account ids, in the panel's order.
    public var withoutFigure: [String]

    public init(segments: [GaugeSegment] = [], total: Double = 0, mostLoaded: GaugeSegment? = nil,
                alerts: [GaugeSegment] = [], withoutFigure: [String] = []) {
        self.segments = segments
        self.total = total
        self.mostLoaded = mostLoaded
        self.alerts = alerts
        self.withoutFigure = withoutFigure
    }
}

public enum MenuBarGauge {
    /// From this share used, an account raises the alert mark in the menu bar, whatever the average is.
    /// Equal to the critical threshold of the gauges (`SGTheme.critThreshold`, a test checks it).
    public static let alertThreshold = 90.0

    /// The gauge of the menu bar.
    ///
    /// - Counted: the accounts of a provider that is on, neither hidden nor "Do not read", with at least one
    ///   limit that has a number (up to date, or the last known one). An account whose sign-in is missing, refused
    ///   or not readable is not counted even when it keeps old numbers (as `Ranking.rank` leaves it out).
    /// - `percent`: their tightest limit now (`AccountUsage.highestPercent(at:)`).
    /// - `share`: `percent / 100 / N`, so the total is the average and never goes over 100 %.
    public static func model(_ usages: [AccountUsage], settings: BrimlineSettings,
                             providers: Set<Provider>, now: Date) -> GaugeModel {
        let candidates = ordered(usages.filter { usage in
            providers.contains(usage.account.provider)
                && !settings.isHidden(usage.account.id)
                && !settings.isUnread(usage.account.id)
        })
        let counted = candidates.compactMap { usage in
            figure(usage, at: now).map { (usage, $0) }
        }
        let n = Double(counted.count)
        let segments = counted.map { usage, percent in
            GaugeSegment(accountID: usage.account.id, provider: usage.account.provider, percent: percent,
                         share: min(max(percent, 0), 100) / 100 / n, stale: usage.status != .ok)
        }
        let withoutFigure = candidates.filter { figure($0, at: now) == nil }.map(\.account.id)
        let fresh = segments.filter { !$0.stale }
        let alerts = segments.filter { $0.percent >= alertThreshold }
            .enumerated()
            .sorted { ($0.element.percent, $1.offset) > ($1.element.percent, $0.offset) }
            .map(\.element)
        return GaugeModel(segments: segments, total: min(1, segments.reduce(0) { $0 + $1.share }),
                          mostLoaded: highest(fresh) ?? highest(segments), alerts: alerts, withoutFigure: withoutFigure)
    }

    /// The account's tightest percentage now, or nil when it counts for nothing: no number, or a sign-in that is
    /// missing, refused or not readable (its old numbers are not a reading of today).
    private static func figure(_ usage: AccountUsage, at now: Date) -> Double? {
        switch usage.status {
        case .signedOut, .reconnect, .notReadable: return nil
        default: return usage.highestPercent(at: now)
        }
    }

    /// The panel's order: providers in `PanelLayout.providerOrder`, then the accounts as they came.
    private static func ordered(_ usages: [AccountUsage]) -> [AccountUsage] {
        usages.enumerated().sorted { a, b in
            let pa = PanelLayout.providerOrder.firstIndex(of: a.element.account.provider) ?? Int.max
            let pb = PanelLayout.providerOrder.firstIndex(of: b.element.account.provider) ?? Int.max
            return pa != pb ? pa < pb : a.offset < b.offset
        }.map(\.element)
    }

    /// The highest percentage; the first of the panel's order when two are equal.
    private static func highest(_ segments: [GaugeSegment]) -> GaugeSegment? {
        var best: GaugeSegment?
        for segment in segments where segment.percent > (best?.percent ?? -1) { best = segment }
        return best
    }
}
