import Foundation

/// The Update Planner. Plan composition is greedy in order:
/// (1) Regenerable, staleness desc; (2) Rebuildable with staleness > 30 d,
/// cost asc; (3) Stash suggestions if a Stash exists; stop at need × 1.15.
/// Managed items are listed with teach links but never counted in the promise.
public struct UpdatePlan {
    public let neededBytes: Int64
    public let reclaimItems: [AtlasItem]
    public let stashSuggestions: [AtlasItem]
    /// Managed items shown alongside, promise excluded.
    public let teachItems: [AtlasItem]

    public var promisedBytes: Int64 {
        reclaimItems.reduce(0) { $0 + $1.bytes } + stashSuggestions.reduce(0) { $0 + $1.bytes }
    }
    public var meetsNeed: Bool { promisedBytes >= neededBytes }
    /// Rough runtime: a rename is instant; a stash move runs at drive speed.
    public func estimatedMinutes(stashBytesPerSecond: Double = 400_000_000) -> Int {
        let stashBytes = stashSuggestions.reduce(Int64(0)) { $0 + $1.bytes }
        let seconds = Double(stashBytes) / max(stashBytesPerSecond, 50_000_000) + Double(reclaimItems.count) * 2
        return max(1, Int((seconds / 60).rounded(.up)))
    }
}

public enum UpdatePlanner {
    public static func compose(
        need: Int64,
        items: [AtlasItem],
        hasStash: Bool,
        now: Date = Date()
    ) -> UpdatePlan {
        let target = Int64(Double(need) * 1.15)
        var picked: [AtlasItem] = []
        var total: Int64 = 0

        func take(_ candidates: [AtlasItem]) {
            for item in candidates {
                guard total < target else { return }
                picked.append(item)
                total += item.bytes
            }
        }

        // (1) Regenerable, stalest first.
        let regen = items
            .filter { $0.entry.tier == .regenerable && !$0.isStashed }
            .sorted { ($0.lastTouched ?? .distantPast) < ($1.lastTouched ?? .distantPast) }
        take(regen)

        // (2) Rebuildable, stale > 30 days, cheapest to recreate first.
        if total < target {
            let cutoff = now.addingTimeInterval(-30 * 86_400)
            let rebuild = items
                .filter { $0.entry.tier == .rebuildable && !$0.isStashed && ($0.lastTouched ?? .distantPast) < cutoff }
                .sorted { costRank($0) < costRank($1) }
            take(rebuild)
        }

        // (3) Stash suggestions when a Stash exists.
        var stashPicks: [AtlasItem] = []
        if total < target, hasStash {
            let pickedIDs = Set(picked.map(\.id))
            let stashable = items
                .filter { $0.entry.stashable && !$0.isStashed && !pickedIDs.contains($0.id) }
                .sorted { $0.bytes > $1.bytes }
            for item in stashable {
                guard total < target else { break }
                stashPicks.append(item)
                total += item.bytes
            }
        }

        let teach = items
            .filter { $0.entry.tier == .managed && $0.entry.teachFlow != nil && $0.bytes > 1_000_000_000 }
            .sorted { $0.bytes > $1.bytes }

        return UpdatePlan(
            neededBytes: need,
            reclaimItems: picked,
            stashSuggestions: stashPicks,
            teachItems: Array(teach.prefix(3))
        )
    }

    /// Cost ordering: pure rebuild minutes when known, else size as a proxy.
    static func costRank(_ item: AtlasItem) -> Double {
        switch item.entry.cost {
        case .rebuild(let secondsPerGB):
            return Double(item.bytes) / 1_000_000_000 * secondsPerGB
        case .redownload(let fraction, _):
            return Double(item.bytes) * fraction / 5_000_000
        case .refills, .none:
            return Double(item.bytes) / 1_000_000_000
        }
    }
}
