import Foundation

public struct LedgerRow: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let path: String
    public let bytes: Int64
    public let tier: Tier
    public let owner: String
    public let lastTouched: Date?
    public let item: AtlasItem?
    public let insight: SystemInsight?
    public var members: [AtlasItem] = []
    public var items: [AtlasItem] { members.isEmpty ? item.map { [$0] } ?? [] : members }
    public var isMerged: Bool { members.count > 1 }
    public var mergedSummary: String { Copy.mergedStorageSummary(tier) }
    public func selectedCount(in ids: Set<String>) -> Int { items.filter { ids.contains($0.id) }.count }
}


public enum LedgerSort: String, Sendable, CaseIterable { case name, size, tier, touched }

public enum LedgerProjection {
    /// Pure projection used by the view and by the performance harness.
    public static func rows(items: [AtlasItem], insights: [SystemInsight] = [],
                            tier: Tier? = nil, search: String = "", sort: LedgerSort = .size,
                            ascending: Bool = false) -> [LedgerRow] {
        var out: [LedgerRow] = []
        out.reserveCapacity(items.count + insights.count)
        for (index, item) in items.enumerated() {
            if index % 256 == 0 && Task.isCancelled { return [] }
            out.append(LedgerRow(
                id: item.id, name: item.displayName, path: item.url.path,
                bytes: item.bytes, tier: item.entry.tier,
                owner: item.projectName ?? item.entry.owner,
                lastTouched: item.lastTouched, item: item, insight: nil
            ))
        }
        for insight in insights {
            let entry = Atlas.entry(insight.entryID)
            out.append(LedgerRow(
                id: insight.id, name: entry.title, path: "",
                bytes: insight.bytes, tier: entry.tier, owner: entry.owner,
                lastTouched: nil, item: nil, insight: insight
            ))
        }
        if let tier {
            out = out.filter { $0.tier == tier }
        }
        if !search.isEmpty {
            out = out.filter {
                $0.name.localizedCaseInsensitiveContains(search)
                    || $0.owner.localizedCaseInsensitiveContains(search)
                    || $0.path.localizedCaseInsensitiveContains(search)
            }
        }
        out = merge(out)
        let base: [LedgerRow]
        switch sort {
        case .size:
            base = out.sorted { $0.bytes == $1.bytes ? $0.id < $1.id : $0.bytes > $1.bytes }
        case .name:
            base = out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .tier:
            base = out.sorted { $0.tier == $1.tier ? $0.bytes > $1.bytes : $0.tier < $1.tier }
        case .touched:
            base = out.sorted { ($0.lastTouched ?? .distantPast) > ($1.lastTouched ?? .distantPast) }
        }
        return ascending ? base.reversed() : base
    }
    /// Combine the same kind of reproducible storage across locations. App
    /// caches additionally share an owner. Personal files and managed actions
    /// retain individual identities, because equal labels do not make them
    /// interchangeable. Filtering happens first: search actions only include
    /// locations matching the query.
    private static func merge(_ rows: [LedgerRow]) -> [LedgerRow] {
        var groups: [String: [LedgerRow]] = [:]
        var singles: [LedgerRow] = []
        for row in rows {
            guard let item = row.item else { singles.append(row); continue }
            let key: String
            if item.entryID == "storage.appCache" || item.entryID == "sys.appCache" {
                let owner = item.entryID == "storage.appCache" ? (item.projectName ?? item.url.lastPathComponent)
                    : AppNames.human(fromCacheFolder: item.url.lastPathComponent)
                key = "appCache|" + owner.lowercased()
            } else if item.entry.tier == .regenerable || item.entry.tier == .rebuildable ||
                        (item.entry.tier == .system && item.entry.teachFlow == nil) || item.entryID == "storage.sharedData" ||
                        ["storage.projects", "storage.documents", "storage.media", "storage.pythonEnvironments", "storage.runners"].contains(item.entryID) {
                key = item.entryID
            } else {
                singles.append(row); continue
            }
            groups[key, default: []].append(row)
        }
        for (key, group) in groups {
            guard group.count > 1 else { singles += group; continue }
            let ordered = group.sorted { $0.id < $1.id }
            let first = ordered[0]
            let members = ordered.flatMap(\.items)
            let title = key.hasPrefix("appCache|") ? first.name : first.item!.entry.title
            singles.append(LedgerRow(id: "merged|" + key, name: title, path: "",
                bytes: members.reduce(0) { $0 + $1.bytes }, tier: first.tier, owner: key.hasPrefix("appCache|") ? first.owner : first.item!.entry.owner,
                lastTouched: members.contains(where: { $0.lastTouched == nil }) ? nil : members.compactMap(\.lastTouched).max(),
                item: first.item, insight: nil, members: members))
        }
        return singles
    }

}
