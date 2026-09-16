import Foundation

/// The Update Planner. Plan composition is greedy in order:
/// (1) Regenerable, staleness desc; (2) Rebuildable with staleness > 30 d,
/// cost asc; stop at need × 1.15.
/// Managed items are listed with teach links but never counted in the promise.
public struct UpdatePlan {
    public let neededBytes: Int64
    public let reclaimItems: [AtlasItem]
    /// Managed items shown alongside, promise excluded.
    public let teachItems: [AtlasItem]

    public var promisedBytes: Int64 {
        reclaimItems.reduce(0) { $0 + $1.bytes }
    }
    public var meetsNeed: Bool { promisedBytes >= neededBytes }
    /// Rough runtime: a rename is instant, so the count is the cost.
    public func estimatedMinutes() -> Int {
        let seconds = Double(reclaimItems.count) * 2
        return max(1, Int((seconds / 60).rounded(.up)))
    }
}

public enum UpdatePlanner {
    public static func compose(
        need: Int64,
        items: [AtlasItem],
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
            .filter { $0.entry.tier == .regenerable }
            .sorted { ($0.lastTouched ?? .distantPast) < ($1.lastTouched ?? .distantPast) }
        take(regen)

        // (2) Rebuildable, stale > 30 days, cheapest to recreate first.
        if total < target {
            let cutoff = now.addingTimeInterval(-30 * 86_400)
            let rebuild = items
                .filter { $0.entry.tier == .rebuildable && ($0.lastTouched ?? .distantPast) < cutoff }
                .sorted { costRank($0) < costRank($1) }
            take(rebuild)
        }

        let teach = items
            .filter { $0.entry.tier == .managed && $0.entry.teachFlow != nil && $0.bytes > 1_000_000_000 }
            .sorted { $0.bytes > $1.bytes }

        return UpdatePlan(
            neededBytes: need,
            reclaimItems: picked,
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
