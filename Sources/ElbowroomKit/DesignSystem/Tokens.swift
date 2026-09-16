import SwiftUI
import AppKit

// Design system "Warm Instrument" (claude.ai/design Elbowroom.dc, adopted
// wholesale): cream and espresso neutrals on a desk-toned window, one
// terracotta accent for actions, softened oklch tier colors for data.
// Tier still never appears as color alone: the dot always wears its word.

private func dynamicColor(light: String, dark: String) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        return NSColor(hex: hex)
    })
}

public extension NSColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = CGFloat((v >> 16) & 0xFF) / 255
        let g = CGFloat((v >> 8) & 0xFF) / 255
        let b = CGFloat(v & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}

public enum BColor {
    /// The desk the window sits on (window chrome edges, wells behind cards).
    public static let desk = dynamicColor(light: "#E9E6E1", dark: "#131110")
    public static let bg = dynamicColor(light: "#F7F6F4", dark: "#1E1C19")
    public static let surface = dynamicColor(light: "#FFFFFF", dark: "#282520")
    public static let ink = dynamicColor(light: "#211D19", dark: "#F2EFEB")
    public static let inkSoft = dynamicColor(light: "#8A847D", dark: "#A29B91")
    /// Fainter than inkSoft: captions, deselected marks.
    public static let faint = dynamicColor(light: "#B8B2AA", dark: "#6B655D")
    /// The one action color: terracotta.
    public static let brand = dynamicColor(light: "#A75F34", dark: "#DE8F57")
    public static let brandHover = dynamicColor(light: "#975124", dark: "#EF9F67")
    /// Label on an accent-filled control.
    public static let onBrand = dynamicColor(light: "#FFFFFF", dark: "#221D16")
    /// Selected-row wash and quiet accent fills.
    public static let brandSoft = brand.opacity(0.10)

    // Data colors: the four tiers (oklch-derived, softened).
    public static let tierRegen = dynamicColor(light: "#389560", dark: "#53AE77")     // Cache
    public static let tierRebuild = dynamicColor(light: "#C87F2C", dark: "#DC9242")   // Derived
    public static let tierManaged = dynamicColor(light: "#5182C1", dark: "#689BDB")   // App-managed
    public static let tierYours = dynamicColor(light: "#90847A", dark: "#9C9086")     // Personal: warm neutral
    /// Good news (shrinkage, headroom returned).
    public static let ok = dynamicColor(light: "#1C7F4C", dark: "#59B47D")

    public static let line = ink.opacity(0.10)
    /// Hairline row separators, softer than line.
    public static let hair = ink.opacity(0.06)
    /// Recessed wells (tracks, insets): one step off the background.
    public static let soil = dynamicColor(light: "#EDEBE7", dark: "#343029")
}

// 4-pt spacing scale.
public enum BSpace {
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
    public static let huge: CGFloat = 48
    public static let hero: CGFloat = 64
    public static let cardPadding: CGFloat = 16
    public static let sheetPadding: CGFloat = 24
    public static let sectionGap: CGFloat = 32
}

public enum BRadius {
    public static let card: CGFloat = 14
    public static let sheet: CGFloat = 14
    public static let control: CGFloat = 9
    public static let chamber: CGFloat = 8
    /// Full pill, for small actions and filter chips.
    public static let pill: CGFloat = 999
}

// Type: SF Pro straight, tabular figures everywhere digits align; SF Mono
// for paths and commands. No display whimsy; hierarchy from size and weight.
public enum BFont {
    public static let hero = Font.system(size: 64, weight: .semibold).monospacedDigit()
    public static let denHero = Font.system(size: 52, weight: .heavy).monospacedDigit()
    public static let title = Font.system(size: 22, weight: .semibold)
    public static let subtitle = Font.system(size: 15, weight: .medium)
    public static let body = Font.system(size: 13)
    public static let meta = Font.system(size: 12)
    public static let path = Font.system(size: 11, design: .monospaced)
    public static func rounded(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        Font.system(size: size, weight: weight).monospacedDigit()
    }
}

// Springs: unchanged mechanics, restrained by usage.
public enum BMotion {
    public static let standard = Animation.spring(response: 0.35, dampingFraction: 0.85)
    public static let heavy = Animation.spring(response: 0.5, dampingFraction: 0.8)
    public static let light = Animation.spring(response: 0.25, dampingFraction: 0.9)
}

public struct BCard: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .padding(BSpace.cardPadding)
            .background(BColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: BRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BRadius.card, style: .continuous)
                    .strokeBorder(BColor.line, lineWidth: 1)
            )
    }
}

public extension View {
    func bCard() -> some View { modifier(BCard()) }
}
