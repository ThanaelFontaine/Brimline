// SightglassTheme.swift
// The design tokens of Sightglass for the SwiftUI app, and the gauge.
// Values come from design/tokens.json. Light and dark follow the appearance of the Mac.
// Body text keeps system colors (.primary, .secondary) on system materials:
// only the accent and the gauge colors belong to Sightglass.

import SwiftUI
import AppKit
import SightglassCore

public enum SGTheme {

    // MARK: Colors

    static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }

    public static let accent    = dynamic(0x0B6E7A, 0x5CC8D0)
    public static let track     = dynamic(0xE7EAED, 0x2B3035)
    public static let trackLine = dynamic(0xD3D8DD, 0x30353A)
    public static let ok        = dynamic(0x127A82, 0x3BBDC2)   // room left, under 70%
    public static let warn      = dynamic(0x9A5800, 0xEFA63A)   // warning, from 70% to under 90%
    public static let crit      = dynamic(0xC0302B, 0xFF6F64)   // critical, 90% and over
    public static let muted     = dynamic(0x56606A, 0x9BA5AF)   // expired (last known value)

    // MARK: Thresholds

    public static let warnThreshold = 0.70
    public static let critThreshold = 0.90

    public enum Level { case ok, warn, crit }

    public static func level(for fraction: Double) -> Level {
        if fraction >= critThreshold { return .crit }
        if fraction >= warnThreshold { return .warn }
        return .ok
    }

    public static func color(for fraction: Double) -> Color {
        switch level(for: fraction) {
        case .ok: ok
        case .warn: warn
        case .crit: crit
        }
    }

    // MARK: Sizes (points)

    public enum Space {
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 8
        public static let m: CGFloat = 12
        public static let l: CGFloat = 16
        public static let xl: CGFloat = 24
    }

    public enum Radius {
        public static let card: CGFloat = 10
        public static let control: CGFloat = 6
    }

    public static let gaugeHeight: CGFloat = 6
    public static let windowWidth: CGFloat = 340
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

// MARK: - Gauge

/// The state of a gauge.
public enum SGGaugeState: Equatable {
    case value(Double)            // share used, 0 to 1 (fresh or old: the gauge is the same)
    case expired(last: Double?)   // expired session: last known value, in gray
    case unavailable              // no value: empty dashed tube
}

/// The tube: a 6 pt capsule, track and outline, liquid colored by threshold,
/// two thin marks at 70% and 90%. The percentage is always shown next to it as text:
/// color is never the only signal.
public struct SGGauge: View {
    public var state: SGGaugeState
    public var accessibilityName: String
    /// The value VoiceOver reads, already localized by the app (by default: the percentage).
    public var accessibilityValueText: String?

    public init(_ state: SGGaugeState, accessibilityName: String, accessibilityValue: String? = nil) {
        self.state = state
        self.accessibilityName = accessibilityName
        self.accessibilityValueText = accessibilityValue
    }

    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = SGTheme.gaugeHeight
            ZStack(alignment: .leading) {
                Capsule().fill(SGTheme.track)
                // Threshold marks, under the liquid.
                ForEach([SGTheme.warnThreshold, SGTheme.critThreshold], id: \.self) { t in
                    Rectangle().fill(SGTheme.trackLine)
                        .frame(width: 1, height: h)
                        .offset(x: (w * t).rounded() - 0.5)
                }
                if let (fraction, color) = fill {
                    Capsule().fill(color)
                        .frame(width: fraction <= 0 ? 0 : max(h, w * min(fraction, 1)))
                        .opacity(fraction <= 0 ? 0 : 1)
                }
                if case .unavailable = state {
                    Capsule().strokeBorder(SGTheme.trackLine, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                } else {
                    Capsule().strokeBorder(SGTheme.trackLine, lineWidth: 0.5)
                }
            }
            .frame(height: h)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: SGTheme.gaugeHeight)
        .accessibilityElement()
        .accessibilityLabel(accessibilityName)
        .accessibilityValue(accessibilityValue)
    }

    private var fill: (Double, Color)? {
        switch state {
        case .value(let f): (f, SGTheme.color(for: f))
        case .expired(let last): last.map { ($0, SGTheme.muted.opacity(0.55)) }
        case .unavailable: nil
        }
    }

    private var accessibilityValue: String {
        if let accessibilityValueText { return accessibilityValueText }
        let strings = Strings()
        return switch state {
        case .value(let f): strings.percentText(f * 100)
        case .expired(let last): last.map { strings.accessibilityPercent($0 * 100, expired: true) } ?? strings.expiredShort
        case .unavailable: strings.unavailableShort
        }
    }
}
