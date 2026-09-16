import Foundation

/// Reclaim flow. Items move by same-volume rename into
/// `~/.Trash/Elbowroom <date>/`, preserving relative paths for restore. A rename
/// needs no free space, which matters in a crisis.

public struct ReclaimPlan {
    public var items: [AtlasItem]
    public init(items: [AtlasItem]) {
        self.items = items
    }
    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }

    /// Grouped by owner for the plan sheet.
    public var byOwner: [(owner: String, items: [AtlasItem])] {
        let groups = Dictionary(grouping: items) { $0.projectName ?? $0.entry.owner }
        return groups
            .map { (owner: $0.key, items: $0.value.sorted { $0.bytes > $1.bytes }) }
            .sorted { l, r in
                let lb = l.items.reduce(Int64(0)) { $0 + $1.bytes }
                let rb = r.items.reduce(Int64(0)) { $0 + $1.bytes }
                return lb > rb
            }
    }

    /// The free-tier boundary: the free portion always reclaims; the
    /// paywall never blocks it. Greedy in given order.
    public func freeSplit(remainingAllowance: Int64) -> (now: [AtlasItem], withPro: [AtlasItem]) {
        var now: [AtlasItem] = []
        var locked: [AtlasItem] = []
        var used: Int64 = 0
        for item in items {
            if used + item.bytes <= remainingAllowance {
                now.append(item)
                used += item.bytes
            } else {
                locked.append(item)
            }
        }
        return (now, locked)
    }
}

public enum ReclaimItemStatus: Equatable, Sendable {
    case pending, moving, done
    case skipped(reason: String)
}

public struct ReclaimOutcome: Sendable {
    public let reclaimedBytes: Int64
    public let doneCount: Int
    public let skipped: [(name: String, reason: String)]
    public let receipt: Receipt?
    public let cancelled: Bool
}

public final class ReclaimExecutor {
    private let fm = FileManager.default
    public init() {}

    /// Destination folder for one run: `~/.Trash/Elbowroom 2026-07-18 10.42/`.
    static func trashFolderName(date: Date = Date()) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH.mm.ss"
        df.locale = Locale(identifier: "en_US_POSIX")
        return "Elbowroom \(df.string(from: date))"
    }

    /// Run the plan. `progress` fires on the main actor per item.
    /// Cancel keeps completed items reclaimed, restores none silently, and the
    /// outcome says which.
    public func run(
        plan: ReclaimPlan,
        keepInTrash: Bool,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        progress: @escaping @Sendable (Int, ReclaimItemStatus) -> Void
    ) async -> ReclaimOutcome {
        let trash = home.appendingPathComponent(".Trash", isDirectory: true)
        let folderName = Self.trashFolderName()
        let dest = trash.appendingPathComponent(folderName, isDirectory: true)

        var receiptItems: [ReceiptItem] = []
        var skipped: [(String, String)] = []
        var reclaimed: Int64 = 0
        var cancelled = false

        // The sandbox denies direct writes into ~/.Trash outright, with no
        // prompt to offer. When the dated run folder cannot be created, every
        // move routes through the system trash service instead, which needs
        // no direct access and records put-back information.
        var brokered = false
        do {
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        } catch {
            brokered = true
        }

        for (index, item) in plan.items.enumerated() {
            if Task.isCancelled { cancelled = true; break }
            await MainActor.run { progress(index, .moving) }

            do {
                if brokered {
                    var landed: NSURL?
                    try fm.trashItem(at: item.url, resultingItemURL: &landed)
                    reclaimed += item.bytes
                    receiptItems.append(ReceiptItem(
                        path: item.url.path, name: item.displayName,
                        bytes: item.bytes, tier: item.entry.tier, entryID: item.entryID,
                        trashedTo: landed?.path
                    ))
                } else {
                    // Preserve the path relative to home inside the run folder
                    // so a restore can put everything back where it was.
                    let relative: String
                    if item.url.path.hasPrefix(home.path + "/") {
                        relative = String(item.url.path.dropFirst(home.path.count + 1))
                    } else {
                        relative = "_" + item.url.path.split(separator: "/").joined(separator: "/")
                    }
                    let target = dest.appendingPathComponent(relative)
                    try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.moveItem(at: item.url, to: target)
                    reclaimed += item.bytes
                    receiptItems.append(ReceiptItem(
                        path: item.url.path, name: item.displayName,
                        bytes: item.bytes, tier: item.entry.tier, entryID: item.entryID,
                        trashedTo: target.path
                    ))
                }
                await MainActor.run { progress(index, .done) }
            } catch {
                let reason = (error as NSError).localizedFailureReason ?? error.localizedDescription
                skipped.append((item.displayName, reason))
                await MainActor.run { progress(index, .skipped(reason: reason)) }
            }
        }

        var receipt: Receipt?
        if receiptItems.isEmpty {
            if !brokered { try? fm.removeItem(at: dest) }
        } else if keepInTrash {
            receipt = Receipt(
                items: receiptItems, restoreStatus: .inTrash,
                trashFolder: brokered ? nil : dest.path
            )
        } else if brokered {
            // Delete-now: clear each trashed item where the sandbox allows;
            // anything that stays gets swept later, and the receipt says so.
            var allGone = true
            for item in receiptItems {
                guard let landed = item.trashedTo else { continue }
                try? fm.removeItem(atPath: landed)
                if fm.fileExists(atPath: landed) { allGone = false }
            }
            receipt = Receipt(
                items: receiptItems,
                restoreStatus: allGone ? .deletedNow : .inTrash,
                trashFolder: nil
            )
        } else {
            try? fm.removeItem(at: dest)
            receipt = Receipt(items: receiptItems, restoreStatus: .deletedNow, trashFolder: nil)
        }

        return ReclaimOutcome(
            reclaimedBytes: reclaimed, doneCount: receiptItems.count,
            skipped: skipped.map { (name: $0.0, reason: $0.1) },
            receipt: receipt, cancelled: cancelled
        )
    }

    /// Bring a receipt's items back from the Trash while they still exist.
    /// Each item recorded where it landed, so both modes restore the same way.
    public func restore(receipt: Receipt, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        guard receipt.restoreStatus == .inTrash else { return false }
        var allBack = true
        for item in receipt.items {
            // Receipts from before the landing path was recorded fall back to
            // the dated-folder layout.
            var located = item.trashedTo
            if located == nil, let folder = receipt.trashFolder {
                let relative: String
                if item.path.hasPrefix(home.path + "/") {
                    relative = String(item.path.dropFirst(home.path.count + 1))
                } else {
                    relative = "_" + item.path.split(separator: "/").joined(separator: "/")
                }
                located = folder + "/" + relative
            }
            guard let landed = located, fm.fileExists(atPath: landed) else {
                allBack = false
                continue
            }
            let original = URL(fileURLWithPath: item.path)
            do {
                try fm.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: URL(fileURLWithPath: landed), to: original)
            } catch {
                allBack = false
            }
        }
        if let folder = receipt.trashFolder {
            try? fm.removeItem(at: URL(fileURLWithPath: folder))
        }
        return allBack
    }
}
