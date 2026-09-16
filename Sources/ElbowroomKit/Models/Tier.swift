import SwiftUI

/// The four-tier safety gauge that governs everything.
/// Order is depth order in the Cross-Section: safe things sit near the surface,
/// precious things sleep deep.
public enum Tier: String, Codable, CaseIterable, Sendable, Comparable, Identifiable {
    case regenerable
    case rebuildable
    case managed
    case yours

    public var id: String { rawValue }

    private var depth: Int {
        switch self {
        case .regenerable: 0
        case .rebuildable: 1
        case .managed: 2
        case .yours: 3
        }
    }

    public static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.depth < rhs.depth }

    public var label: String {
        switch self {
        case .regenerable: Copy.tierLabelRegenerable
        case .rebuildable: Copy.tierLabelRebuildable
        case .managed: Copy.tierLabelManaged
        case .yours: Copy.tierLabelYours
        }
    }

    /// Tier is always icon + color + label, never color alone.
    public var systemImage: String {
        switch self {
        case .regenerable: "arrow.triangle.2.circlepath"
        case .rebuildable: "hammer"
        case .managed: "app.badge.checkmark"
        case .yours: "lock"
        }
    }

    public var color: Color {
        switch self {
        case .regenerable: BColor.tierRegen
        case .rebuildable: BColor.tierRebuild
        case .managed: BColor.tierManaged
        case .yours: BColor.tierYours
        }
    }

    /// Chip tooltips.
    public var tooltip: String {
        switch self {
        case .regenerable: Copy.tierRegenerable
        case .rebuildable: Copy.tierRebuildable
        case .managed: Copy.tierManaged
        case .yours: Copy.tierYours
        }
    }
}
