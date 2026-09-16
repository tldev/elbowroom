import SwiftUI

/// The safety gauge that governs everything.
/// Order is depth order: safe things sit near the surface, precious things
/// sleep deep, and the OS itself is bedrock.
public enum Tier: String, Codable, CaseIterable, Sendable, Comparable, Identifiable {
    case regenerable
    case rebuildable
    case managed
    case apps
    case yours
    case system

    public var id: String { rawValue }

    private var depth: Int {
        switch self {
        case .regenerable: 0
        case .rebuildable: 1
        case .managed: 2
        case .apps: 3
        case .yours: 4
        case .system: 5
        }
    }

    public static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.depth < rhs.depth }

    public var label: String {
        switch self {
        case .regenerable: Copy.tierLabelRegenerable
        case .rebuildable: Copy.tierLabelRebuildable
        case .managed: Copy.tierLabelManaged
        case .apps: Copy.tierLabelApps
        case .yours: Copy.tierLabelYours
        case .system: Copy.tierLabelSystem
        }
    }

    /// Tier is always icon + color + label, never color alone.
    public var systemImage: String {
        switch self {
        case .regenerable: "arrow.triangle.2.circlepath"
        case .rebuildable: "hammer"
        case .managed: "app.badge.checkmark"
        case .apps: "square.grid.2x2"
        case .yours: "lock"
        case .system: "apple.logo"
        }
    }

    public var color: Color {
        switch self {
        case .regenerable: BColor.tierRegen
        case .rebuildable: BColor.tierRebuild
        case .managed: BColor.tierManaged
        case .apps: BColor.tierApps
        case .yours: BColor.tierYours
        case .system: BColor.tierSystem
        }
    }

    /// Chip tooltips.
    public var tooltip: String {
        switch self {
        case .regenerable: Copy.tierRegenerable
        case .rebuildable: Copy.tierRebuildable
        case .managed: Copy.tierManaged
        case .apps: Copy.tierApps
        case .yours: Copy.tierYours
        case .system: Copy.tierSystem
        }
    }
}
