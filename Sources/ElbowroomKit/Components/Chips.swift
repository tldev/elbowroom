import SwiftUI

/// TierChip (Warm Instrument): a small tier-colored dot wearing its
/// word — quieter than the old capsule, still never color alone. Kibi
/// guesses keep a dashed ring around the dot.
public struct TierChip: View {
    let tier: Tier
    var guessed = false

    public init(_ tier: Tier, guessed: Bool = false) {
        self.tier = tier
        self.guessed = guessed
    }

    public var body: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 3)
                .fill(tier.color)
                .frame(width: 8, height: 8)
                .overlay {
                    if guessed {
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(tier.color, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                            .padding(-3)
                    }
                }
            Text(guessed ? Copy.kibiGuess : tier.label)
                .font(.system(size: 12.5))
                .foregroundStyle(BColor.inkSoft)
        }
        .help(tier.tooltip)
        .accessibilityLabel("\(tier.label). \(tier.tooltip)")
    }
}

/// Hollow badge for teach-flow bytes: counted in headroom but visibly
/// different from what Elbowroom moves itself.
public struct HollowBadge: View {
    public init() {}
    public var body: some View {
        Circle()
            .strokeBorder(BColor.inkSoft, lineWidth: 1.5)
            .frame(width: 8, height: 8)
            .help(Copy.hollowBadgeHelp)
    }
}

/// ByteCounter: odometer-style rolling digits; the unit sits on the
/// same baseline at 55% of the digit size, in soft ink.
public struct ByteCounter: View {
    let bytes: Int64
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(bytes: Int64, size: CGFloat = 96) {
        self.bytes = bytes
        self.size = size
    }

    public var body: some View {
        let split = ByteFormat.split(bytes)
        HStack(alignment: .firstTextBaseline, spacing: size * 0.08) {
            Text(split.value)
                .font(BFont.rounded(size, .bold))
                .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(bytes)))
            Text(split.unit)
                .font(BFont.rounded(size * 0.55, .semibold))
                .foregroundStyle(BColor.inkSoft)
        }
        .foregroundStyle(BColor.ink)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(split.joined)
    }
}

/// Toast (M4): light spring up, 2.4 s dwell. The caller clears it.
public struct ToastView: View {
    let toast: Toast
    public init(_ toast: Toast) { self.toast = toast }
    public var body: some View {
        Text(toast.text)
            .font(BFont.meta)
            .foregroundStyle(BColor.ink)
            .padding(.horizontal, BSpace.l)
            .padding(.vertical, 10)
            .background(BColor.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(BColor.line, lineWidth: 1))
            .shadow(color: BColor.ink.opacity(0.1), radius: 24, y: 8)
    }
}

/// Empty state: one plain sentence under a quiet symbol.
public struct EmptyStateView: View {
    let line: String
    let symbol: String
    public init(_ line: String, symbol: String = "checkmark.circle") {
        self.line = line
        self.symbol = symbol
    }
    public var body: some View {
        VStack(spacing: BSpace.m) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(BColor.inkSoft.opacity(0.7))
            Text(line)
                .font(BFont.subtitle)
                .foregroundStyle(BColor.inkSoft)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
