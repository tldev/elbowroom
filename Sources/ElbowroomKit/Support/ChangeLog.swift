import Foundation

/// Changes: a weekly timeline of growth and shrink per owner, 12 weeks
/// retained, each expandable to its events. Data: one owner-totals snapshot
/// per scan (at most one a day kept) plus explicit events (reclaims, stashes).
public struct OwnerSnapshot: Codable, Sendable {
    public let date: Date
    public let owners: [String: Int64]
    public let freeBytes: Int64
}

public struct ChangeEvent: Codable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let text: String
    /// Positive = grew, negative = freed.
    public let delta: Int64
    public init(text: String, delta: Int64, date: Date = Date()) {
        self.id = UUID()
        self.date = date
        self.text = text
        self.delta = delta
    }
}

public struct WeekBar: Identifiable {
    public let id: Date          // week start
    public let grew: Int64
    public let shrank: Int64
    public let topOwnerDeltas: [(owner: String, delta: Int64)]
    public let events: [ChangeEvent]
}

public final class ChangeLog: @unchecked Sendable {
    public private(set) var snapshots: [OwnerSnapshot] = []
    public private(set) var events: [ChangeEvent] = []
    private let fileURL: URL
    private let queue = DispatchQueue(label: "elbowroom.changelog")

    public init(directory: URL? = nil) {
        let dir = directory ?? ReceiptStore.defaultDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("changes.json")
        load()
    }

    public func recordScan(items: [AtlasItem], disk: DiskSnapshot) {
        queue.sync {
            var owners: [String: Int64] = [:]
            for item in items {
                owners[item.entry.owner, default: 0] += item.bytes
            }
            let snap = OwnerSnapshot(date: Date(), owners: owners, freeBytes: disk.available)
            // Keep at most one snapshot per day, 13 weeks of history.
            if let last = snapshots.last, Calendar.current.isDate(last.date, inSameDayAs: snap.date) {
                snapshots[snapshots.count - 1] = snap
            } else {
                snapshots.append(snap)
            }
            let cutoff = Date().addingTimeInterval(-13 * 7 * 86_400)
            snapshots.removeAll { $0.date < cutoff }
            events.removeAll { $0.date < cutoff }
            save()
        }
    }

    public func append(_ event: ChangeEvent) {
        queue.sync {
            events.append(event)
            save()
        }
    }

    /// Top deltas since a week ago, for the Den's `This week` row.
    public func weekDeltas(limit: Int = 3) -> [(label: String, delta: Int64)] {
        let weekAgo = Date().addingTimeInterval(-7 * 86_400)
        guard let baseline = snapshots.last(where: { $0.date < weekAgo }) ?? snapshots.first,
              let current = snapshots.last,
              baseline.date < current.date else { return [] }
        var deltas: [(String, Int64)] = []
        let allOwners = Set(baseline.owners.keys).union(current.owners.keys)
        for owner in allOwners {
            let d = (current.owners[owner] ?? 0) - (baseline.owners[owner] ?? 0)
            if abs(d) > 500_000_000 { deltas.append((owner, d)) }
        }
        return deltas.sorted { abs($0.1) > abs($1.1) }.prefix(limit).map { (label: $0.0, delta: $0.1) }
    }

    /// The 12-week bar timeline.
    public func weekBars(now: Date = Date()) -> [WeekBar] {
        let calendar = Calendar.current
        var bars: [WeekBar] = []
        for weekOffset in (0..<12).reversed() {
            guard let end = calendar.date(byAdding: .day, value: -7 * weekOffset, to: now),
                  let start = calendar.date(byAdding: .day, value: -7, to: end) else { continue }
            let inWeek = snapshots.filter { $0.date >= start && $0.date < end }.sorted { $0.date < $1.date }
            let weekEvents = events.filter { $0.date >= start && $0.date < end }
            var grew: Int64 = 0
            var shrank: Int64 = 0
            var ownerDeltas: [(String, Int64)] = []
            if let first = inWeek.first, let last = inWeek.last, first.date < last.date {
                let owners = Set(first.owners.keys).union(last.owners.keys)
                for owner in owners {
                    let d = (last.owners[owner] ?? 0) - (first.owners[owner] ?? 0)
                    if d > 0 { grew += d } else { shrank += -d }
                    if abs(d) > 200_000_000 { ownerDeltas.append((owner, d)) }
                }
            }
            for e in weekEvents where e.delta < 0 { shrank += -e.delta }
            bars.append(WeekBar(
                id: start, grew: grew, shrank: shrank,
                topOwnerDeltas: ownerDeltas.sorted { abs($0.1) > abs($1.1) }.prefix(3)
                    .map { (owner: $0.0, delta: $0.1) },
                events: weekEvents
            ))
        }
        return bars
    }

    private func load() {
        struct Blob: Codable { var snapshots: [OwnerSnapshot]; var events: [ChangeEvent] }
        guard let data = try? Data(contentsOf: fileURL),
              let blob = try? JSONDecoder().decode(Blob.self, from: data) else { return }
        snapshots = blob.snapshots
        events = blob.events
    }

    private func save() {
        struct Blob: Codable { var snapshots: [OwnerSnapshot]; var events: [ChangeEvent] }
        if let data = try? JSONEncoder().encode(Blob(snapshots: snapshots, events: events)) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
