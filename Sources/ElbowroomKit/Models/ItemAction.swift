import Foundation

/// Domain actions are independent of their localized labels and presentation.
public enum ItemAction: Equatable, Sendable {
    case reclaim, uninstall, trimMessages, trimPhotos, cleanup
    case teach(TeachFlowID)

    public var title: String {
        switch self {
        case .reclaim: Copy.trayReclaim
        case .uninstall: Copy.uninstall
        case .trimMessages, .trimPhotos: Copy.trimLocally
        case .cleanup: Copy.cleanUp
        case .teach: Copy.showMe
        }
    }

    public static func canBatch(_ item: AtlasItem) -> Bool {
        switch item.entry.tier {
        case .regenerable, .rebuildable: true
        case .yours: item.entryID == "lens.found"
        case .managed, .apps, .system: false
        }
    }

    public static func resolve(_ item: AtlasItem, tools: Set<DevTool>) -> ItemAction? {
        if canBatch(item) { return .reclaim }
        switch item.entryID {
        case "app.bundle": return .uninstall
        case "sys.messages": return .trimMessages
        case "sys.photosLibrary": return .trimPhotos
        case "docker.data": return .cleanup
        default: break
        }
        if let tool = ToolCleanup.tool(for: item.entryID), tools.contains(tool) { return .cleanup }
        if ToolCleanup.directReclaimEntryIDs.contains(item.entryID) { return .reclaim }
        return item.entry.teachFlow.map(ItemAction.teach)
    }

    public static func suggestion(_ item: AtlasItem, tools: Set<DevTool>, now: Date = Date()) -> ItemAction? {
        guard item.bytes > 1_000_000_000 else { return nil }
        switch item.entry.tier {
        case .apps, .yours: return nil
        case .rebuildable:
            guard (item.lastTouched ?? .distantPast) < now.addingTimeInterval(-30 * 86_400) else { return nil }
        default: break
        }
        return resolve(item, tools: tools)
    }
}
