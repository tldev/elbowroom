import Foundation

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
public final class ReceiptStore: @unchecked Sendable {
    public private(set) var receipts: [Receipt] = []
    private let fileURL: URL
    private let queue = DispatchQueue(label: "elbowroom.receipts")

    public init(directory: URL? = nil) {
        let dir = directory ?? Self.defaultDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("receipts.json")
        load()
    }

    public static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Elbowroom", isDirectory: true)
    }

    public var lifetimeBytes: Int64 { receipts.reduce(0) { $0 + $1.totalBytes } }

    public func append(_ receipt: Receipt) {
        queue.sync {
            receipts.append(receipt)
            save()
        }
    }

    public func update(_ receipt: Receipt) {
        queue.sync {
            if let i = receipts.firstIndex(where: { $0.id == receipt.id }) {
                receipts[i] = receipt
                save()
            }
        }
    }

    /// The 7-day auto-empty: remove Elbowroom trash folders whose window ran
    /// out, and reconcile receipts whose folder the user already emptied.
    public func sweepExpired(now: Date = Date()) {
        queue.sync {
            var changed = false
            for i in receipts.indices where receipts[i].restoreStatus == .inTrash {
                if let folder = receipts[i].trashFolder {
                    let exists = FileManager.default.fileExists(atPath: folder)
                    if !exists {
                        receipts[i].restoreStatus = .emptied
                        changed = true
                    } else if now.timeIntervalSince(receipts[i].date) > 7 * 86_400 {
                        try? FileManager.default.removeItem(atPath: folder)
                        receipts[i].restoreStatus = .emptied
                        changed = true
                    }
                } else if now.timeIntervalSince(receipts[i].date) > 7 * 86_400 {
                    // Brokered trash: remove the recorded items where allowed;
                    // the receipt flips only when none remain on disk.
                    let paths = receipts[i].items.compactMap(\.trashedTo)
                    for path in paths {
                        try? FileManager.default.removeItem(atPath: path)
                    }
                    let remaining = paths.filter { FileManager.default.fileExists(atPath: $0) }
                    if remaining.isEmpty {
                        receipts[i].restoreStatus = .emptied
                        changed = true
                    }
                }
            }
            if changed { save() }
        }
    }

    public func exportCSV() -> String {
        var lines = ["date,name,path,bytes,tier"]
        let df = ISO8601DateFormatter()
        for r in receipts {
            for item in r.items {
                let name = item.name.replacingOccurrences(of: ",", with: " ")
                lines.append("\(df.string(from: r.date)),\(name),\(item.path),\(item.bytes),\(item.tier.rawValue)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        receipts = (try? JSONDecoder().decode([Receipt].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(receipts) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
