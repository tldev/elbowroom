import Foundation
import Observation

/// The permanent, append-only receipt of everything Elbowroom ever removed.

public struct ReceiptItem: Codable, Identifiable, Sendable {
    public var id: String { path }
    public let path: String
    public let name: String
    public let bytes: Int64
    public let tier: Tier
    public let entryID: String
    /// Where the system trash service put the item (brokered mode). Nil when
    /// the run used its own dated folder inside the Trash.
    public var trashedTo: String?

    public init(path: String, name: String, bytes: Int64, tier: Tier, entryID: String, trashedTo: String? = nil) {
        self.path = path
        self.name = name
        self.bytes = bytes
        self.tier = tier
        self.entryID = entryID
        self.trashedTo = trashedTo
    }
}

public struct Receipt: Codable, Identifiable, Sendable {
    public enum RestoreStatus: String, Codable, Sendable {
        case inTrash          // still sitting in ~/.Trash/Elbowroom <date>/
        case emptied          // the 7-day window ran out, or the user emptied
        case restored
        case deletedNow       // user unchecked "Keep in Trash"
    }

    public let id: UUID
    public let date: Date
    public let items: [ReceiptItem]
    public let totalBytes: Int64
    public var restoreStatus: RestoreStatus
    /// Folder inside the Trash that holds these items, while `inTrash`.
    public var trashFolder: String?
    /// Free-space delta measured around the run, for cleanups whose rows
    /// carry no per-row size (snapshot deletion). Counted into totalBytes.
    public var measuredBytes: Int64?

    public init(items: [ReceiptItem], restoreStatus: RestoreStatus, trashFolder: String?,
                measuredBytes: Int64? = nil) {
        self.id = UUID()
        self.date = Date()
        self.items = items
        self.totalBytes = items.reduce(0) { $0 + $1.bytes } + (measuredBytes ?? 0)
        self.restoreStatus = restoreStatus
        self.trashFolder = trashFolder
        self.measuredBytes = measuredBytes
    }
}

/// Receipts persist under Application Support so they survive reinstall.
@MainActor
@Observable
public final class ReceiptStore {
    public private(set) var receipts: [Receipt] = []
    private let fileURL: URL
    @ObservationIgnored private let queue = DispatchQueue(label: "elbowroom.receipts")

    public init(directory: URL? = nil) {
        let dir = directory ?? Self.defaultDirectory()
        fileURL = dir.appendingPathComponent("receipts.json")
    }

    nonisolated public static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Elbowroom", isDirectory: true)
    }

    public var lifetimeBytes: Int64 { receipts.reduce(0) { $0 + $1.totalBytes } }

    public func append(_ receipt: Receipt) {
        receipts.append(receipt)
        save()
    }

    public func update(_ receipt: Receipt) {
        if let index = receipts.firstIndex(where: { $0.id == receipt.id }) {
            receipts[index] = receipt
            save()
        }
    }

    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var loadTask: Task<[Receipt], Never>?

    public func loadFromDisk() async {
        guard !loaded else { return }
        if loadTask == nil {
            let file = fileURL, queue = queue
            loadTask = Task {
                await withCheckedContinuation { continuation in
                    queue.async {
                        let values = (try? JSONDecoder().decode([Receipt].self, from: Data(contentsOf: file))) ?? []
                        continuation.resume(returning: values)
                    }
                }
            }
        }
        let stored = await loadTask!.value
        guard !loaded else { return }
        let pending = Set(receipts.map(\.id))
        receipts = stored.filter { !pending.contains($0.id) } + receipts
        loaded = true
        loadTask = nil
        save()
    }

    /// Deletion and restore share the persistence queue so they cannot race.
    public func sweepExpired(now: Date = Date()) async {
        await loadFromDisk()
        let snapshot = receipts
        let expired: Set<UUID> = await withCheckedContinuation { continuation in
            queue.async {
                let fm = FileManager.default
                var expired: Set<UUID> = []
                for receipt in snapshot where receipt.restoreStatus == .inTrash {
                    let paths = receipt.trashFolder.map { [$0] } ?? receipt.items.compactMap(\.trashedTo)
                    if now.timeIntervalSince(receipt.date) > 7 * 86_400 {
                        for path in paths { try? fm.removeItem(atPath: path) }
                    }
                    if !paths.isEmpty && paths.allSatisfy({ !fm.fileExists(atPath: $0) }) {
                        expired.insert(receipt.id)
                    }
                }
                continuation.resume(returning: expired)
            }
        }
        for index in receipts.indices where receipts[index].restoreStatus == .inTrash && expired.contains(receipts[index].id) {
            receipts[index].restoreStatus = .emptied
        }
        if !expired.isEmpty { save() }
    }

    public func restore(_ receipt: Receipt) async -> Bool {
        await loadFromDisk()
        let restored: Bool = await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: ReclaimExecutor().restore(receipt: receipt))
            }
        }
        if restored {
            var updated = receipt
            updated.restoreStatus = .restored
            update(updated)
        }
        return restored
    }

    /// Await writes for tests and explicit persistence checkpoints.
    public func flush() async {
        await loadFromDisk()
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume() }
        }
    }

    public func exportCSV() -> String {
        var lines = ["date,name,path,bytes,tier"]
        let df = ISO8601DateFormatter()
        for r in receipts {
            for item in r.items {
                lines.append([df.string(from: r.date), item.name, item.path,
                              String(item.bytes), item.tier.rawValue]
                    .map(Self.csvField).joined(separator: ","))
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func csvField(_ value: String) -> String {
        guard value.contains(where: { ",\"\r\n".contains($0) }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private func save() {
        guard loaded else { return }
        let snapshot = receipts, file = fileURL
        queue.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
    }
}
