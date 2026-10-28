import AppKit
import BrimlineCore
import SwiftUI

/// The "Color" line under an account in Settings, Accounts (QUOTA-72): the ten colors of the palette, "Other color…"
/// (the system picker, without opacity), "Reset to default", and under it what is wrong with the color, if anything.
struct AccountColorRow: View {
    var account: Account
    var model: AppModel

    var body: some View {
        let s = model.strings
        let current = model.color(for: account)
        let warnings = model.colorWarnings(for: account)
        VStack(alignment: .leading, spacing: SGTheme.Space.xs) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: SGTheme.Space.m) { swatches(current); resetControls(current) }
                VStack(alignment: .leading, spacing: SGTheme.Space.s) { swatches(current); resetControls(current) }
            }
            ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                Label {
                    Text(model.text(for: warning))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(SGTheme.warn)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                // Same left edge as the swatches: past the word "Color".
                .padding(.leading, Self.labelWidth + SGTheme.Space.s)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(s.colorGroup(model.title(for: account)))
    }

    static let labelWidth: CGFloat = 56

    private func swatches(_ current: AccountColor) -> some View {
        let s = model.strings
        return HStack(spacing: SGTheme.Space.s) {
            Text(s.colorRow)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: Self.labelWidth, alignment: .leading)
                .accessibilityHidden(true)
            HStack(spacing: SGTheme.swatchSpacing) {
                HStack(spacing: SGTheme.swatchSpacing) {
                    ForEach(AccountPalette.entries.indices, id: \.self) { slot in
                        Swatch(color: .palette(slot), name: s.colorName(.palette(slot)), selected: current == .palette(slot)) {
                            model.setColor(.palette(slot), for: account)
                        }
                    }
                }
                // One group with one choice, as VoiceOver reads a set of radio buttons: "Color of Client", then each
                // name. "Other color…" stays outside it: the representation replaces what it covers, and the real
                // picker must stay reachable.
                .accessibilityRepresentation {
                    Picker(s.colorGroup(model.title(for: account)), selection: Binding(
                        get: { Self.choice(current) },
                        set: { choice in
                            if AccountPalette.entries.indices.contains(choice) { model.setColor(.palette(choice), for: account) }
                        }
                    )) {
                        ForEach(AccountPalette.entries.indices, id: \.self) { slot in
                            Text(s.colorName(.palette(slot))).tag(slot)
                        }
                        if case .custom = current { Text(s.colorName(current)).tag(AccountPalette.entries.count) }
                    }
                    .pickerStyle(.radioGroup)
                }
                OtherColor(account: account, model: model, current: current)
            }
        }
    }

    /// The index of the choice a color stands for: its slot, or one past the palette for a free color.
    static func choice(_ color: AccountColor) -> Int {
        if case .palette(let slot) = color { return slot }
        return AccountPalette.entries.count
    }

    private func resetControls(_ current: AccountColor) -> some View {
        let s = model.strings
        let isDefault = model.hasDefaultColor(account)
        return HStack(spacing: SGTheme.Space.s) {
            Button(s.resetColor) { model.resetColor(for: account) }
                .buttonStyle(.link)
                .foregroundStyle(isDefault ? Color.secondary : SGTheme.accent)
                .disabled(isDefault)
                .font(.system(size: 12))
            if isDefault {
                Text(s.defaultColor)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The ring of 1.5 pt, in the color of the text, 3 pt outside the dot of the color that is chosen.
private struct SelectionRing: View {
    var shown: Bool

    var body: some View {
        Circle()
            .inset(by: -3)
            .strokeBorder(shown ? Color.primary : Color.clear, lineWidth: 1.5)
            .allowsHitTesting(false)
    }
}

/// One color of the palette: a dot of 18 pt, ringed in the color of the text when it is the one chosen.
private struct Swatch: View {
    var color: AccountColor
    var name: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(SGTheme.account(color))
                .frame(width: SGTheme.swatch, height: SGTheme.swatch)
                .overlay(SelectionRing(shown: selected))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// "Other color…": a dashed dot marked "+" that opens the system color panel; once a free color is chosen it is
/// filled with it and ringed. A real button, so that the keyboard and VoiceOver reach it. (Up to 0.2.1 it was the
/// SwiftUI color picker laid invisibly over the dot, which did not open on a click.)
private struct OtherColor: View {
    var account: Account
    var model: AppModel
    var current: AccountColor

    var body: some View {
        let s = model.strings
        let custom: Bool = { if case .custom = current { return true } else { return false } }()
        Button {
            let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ColorPanel.shared.open(initial: NSColor(hex: current.rgb(dark: dark))) { picked in
                if let color = SystemColorPicker.accountColor(from: Color(nsColor: picked)) { model.setColor(color, for: account) }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(custom ? SGTheme.account(current) : Color.clear)
                    .frame(width: SGTheme.swatch, height: SGTheme.swatch)
                if !custom {
                    Circle()
                        .strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5]))
                        .frame(width: SGTheme.swatch, height: SGTheme.swatch)
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .overlay(SelectionRing(shown: custom))
        .help(s.otherColor)
        .accessibilityLabel(s.otherColor)
        .accessibilityAddTraits(custom ? .isSelected : [])
    }
}

/// The system color panel, shared by every account: each opening says which account the next colors go to.
@MainActor
final class ColorPanel: NSObject {
    static let shared = ColorPanel()
    private var onPick: ((NSColor) -> Void)?

    func open(initial: NSColor, onPick: @escaping (NSColor) -> Void) {
        let panel = NSColorPanel.shared
        // The color is set before the target, so that showing the current color changes nothing.
        self.onPick = nil
        panel.showsAlpha = false
        panel.color = initial
        self.onPick = onPick
        panel.setTarget(self)
        panel.setAction(#selector(changed(_:)))
        panel.isContinuous = true
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func changed(_ sender: NSColorPanel) {
        onPick?(sender.color)
    }
}

/// What the system color picker gives back, as an account color.
enum SystemColorPicker {
    /// The value the picker gave, in sRGB, as six digits; nil when it cannot be read as a color.
    static func accountColor(from color: Color) -> AccountColor? {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return .custom(red: Double(srgb.redComponent), green: Double(srgb.greenComponent), blue: Double(srgb.blueComponent))
    }
}
