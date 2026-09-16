import Foundation
import AppKit

/// Cache cleanup uses a grouped Trash folder. App uninstalls use the system
/// Trash service, which handles authorization and returns restore locations.

public struct ReclaimPlan: Sendable {
    public var items: [AtlasItem]
    public init(items: [AtlasItem]) {
        self.items = items
    }

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
    public var accessDeniedAppPaths: [String] = []
}

public final class ReclaimExecutor {
    private let fm = FileManager.default
    private let authorize: (@Sendable (URL) async throws -> URL)?
    private let recycle: @Sendable (URL) async throws -> URL

    public init() {
        recycle = { try await Self.recycleWithWorkspace($0) }
        authorize = { try await AdministratorAppMove.trash($0) }
    }

    /// Inject the system boundary so tests never touch the user's Trash.
    init(recycle: @escaping @Sendable (URL) async throws -> URL,
         authorize: (@Sendable (URL) async throws -> URL)? = nil) {
        self.recycle = recycle
        self.authorize = authorize
    }

    @MainActor
    private static func recycleWithWorkspace(_ url: URL) async throws -> URL {
        let destinations = try await NSWorkspace.shared.recycle([url])
        guard let destination = destinations[url] else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        return destination
    }

    /// Destination folder for one run: `~/.Trash/Elbowroom 2026-07-18 10.42/`.
    static func trashFolderName(date: Date = Date()) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH.mm.ss"
        df.locale = Locale(identifier: "en_US_POSIX")
        return "Elbowroom \(df.string(from: date)) \(UUID().uuidString)"
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
        var accessDeniedAppPaths: [String] = []

        // Installed apps can require system authorization that a plain move
        // cannot request. Route the whole uninstall through Finder-style Trash
        // so every receipt uses returned locations, including app residue.
        // Ordinary cache plans retain their grouped Trash folder. If creating
        // that folder is denied (e.g. sandbox), use the system service there too.
        var brokered = plan.items.contains { $0.entryID == "app.bundle" }
        if !brokered {
            do {
                try fm.createDirectory(at: dest, withIntermediateDirectories: true)
            } catch {
                brokered = true
            }
        }

        for (index, item) in plan.items.enumerated() {
            if Task.isCancelled { cancelled = true; break }
            await MainActor.run { progress(index, .moving) }

            do {
                let trashedTo: String?
                if brokered {
                    do {
                        trashedTo = try await recycle(item.url).path
                    } catch {
                        guard item.entryID == "app.bundle", Self.isAccessDenied(error as NSError),
                              item.url.deletingLastPathComponent().path == "/Applications",
                              let authorize else { throw error }
                        trashedTo = try await authorize(item.url).path
                    }
                } else {
                    // Preserve the path relative to home inside the run folder
                    // so a restore can put everything back where it was.
                    let target = dest.appendingPathComponent(Self.trashRelativePath(item.url.path, home: home))
                    try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.moveItem(at: item.url, to: target)
                    trashedTo = target.path
                }
                reclaimed += item.bytes
                receiptItems.append(ReceiptItem(
                    path: item.url.path, name: item.displayName,
                    bytes: item.bytes, tier: item.entry.tier, entryID: item.entryID,
                    trashedTo: trashedTo
                ))
                await MainActor.run { progress(index, .done) }
            } catch {
                if (error as NSError).domain == NSCocoaErrorDomain,
                   (error as NSError).code == CocoaError.userCancelled.rawValue {
                    cancelled = true
                    break
                }
                if item.entryID == "app.bundle", Self.isAccessDenied(error as NSError) {
                    accessDeniedAppPaths.append(item.url.path)
                }
                let reason = (error as NSError).localizedFailureReason ?? error.localizedDescription
                skipped.append((item.displayName, reason))
                await MainActor.run { progress(index, .skipped(reason: reason)) }
                // Keep supporting data when the app itself could not be removed.
                if item.entryID == "app.bundle" { break }
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
            let remains = fm.fileExists(atPath: dest.path)
            receipt = Receipt(items: receiptItems, restoreStatus: remains ? .inTrash : .deletedNow,
                              trashFolder: remains ? dest.path : nil)
        }

        return ReclaimOutcome(
            reclaimedBytes: reclaimed, doneCount: receiptItems.count,
            skipped: skipped.map { (name: $0.0, reason: $0.1) },
            receipt: receipt, cancelled: cancelled, accessDeniedAppPaths: accessDeniedAppPaths
        )
    }

    /// A permission error offers Settings, but does not claim TCC is its cause.
    static func isAccessDenied(_ error: NSError) -> Bool {
        if error.domain == NSPOSIXErrorDomain {
            return error.code == Int(EACCES) || error.code == Int(EPERM)
        }
        if error.domain == NSCocoaErrorDomain,
           error.code == CocoaError.fileWriteNoPermission.rawValue {
            return true
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isAccessDenied(underlying)
        }
        return false
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
                located = folder + "/" + Self.trashRelativePath(item.path, home: home)
            }
            guard let landed = located, fm.fileExists(atPath: landed) else {
                allBack = false
                continue
            }
            let original = URL(fileURLWithPath: item.path)
            do {
                try fm.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
                do {
                    try fm.moveItem(at: URL(fileURLWithPath: landed), to: original)
                } catch {
                    guard item.entryID == "app.bundle", Self.isAccessDenied(error as NSError) else { throw error }
                    try AdministratorAppMove.restore(source: URL(fileURLWithPath: landed), destination: original)
                }
            } catch {
                allBack = false
            }
        }
        if allBack, let folder = receipt.trashFolder {
            try? fm.removeItem(at: URL(fileURLWithPath: folder))
        }
        return allBack
    }

    private static func trashRelativePath(_ path: String, home: URL) -> String {
        if path.hasPrefix(home.path + "/") {
            return String(path.dropFirst(home.path.count + 1))
        }
        return "_" + path.split(separator: "/").joined(separator: "/")
    }
}
