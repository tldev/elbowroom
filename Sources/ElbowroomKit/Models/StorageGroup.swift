import Foundation

/// Families for Overview recommendations; Items uses same-kind merged rows.
/// The original items still govern every action.
public enum StorageGroup: String, CaseIterable, Identifiable, Sendable {
    case caches, builds, models, appData, tools, applications, personal, system
    public var id: String { rawValue }
    public var title: String { Copy.storageGroupTitle(self) }
    public var explanation: String { Copy.storageGroupExplanation(self) }
    public var symbol: String {
        switch self {
        case .caches: "arrow.triangle.2.circlepath"
        case .builds: "hammer"
        case .models: "sparkles"
        case .appData: "externaldrive"
        case .tools: "wrench.and.screwdriver"
        case .applications: "square.grid.2x2"
        case .personal: "folder"
        case .system: "apple.logo"
        }
    }
    public static func forItem(_ item: AtlasItem) -> Self {
        let id = item.entryID
        if id == "storage.sharedData" { return .appData }
        if id.hasPrefix("storage.tool") { return .tools }
        if id.hasPrefix("storage.history") || id.hasPrefix("personal.") { return .personal }
        if id.hasPrefix("ml.") || id == "chrome.optGuide" { return .models }
        switch item.entry.tier {
        case .regenerable: return .caches
        case .rebuildable: return .builds
        case .managed: return .appData
        case .apps: return .applications
        case .yours: return .personal
        case .system: return .system
        }
    }
}
