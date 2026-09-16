import Foundation
import CryptoKit
import AppKit
import Observation

/// The move transaction state machine.
/// COPYING → VERIFYING → SWAPPING → CLEANING → DONE, with the manifest
/// journaled before each transition. Kill −9 at any boundary recovers to a
/// consistent state with zero data loss; unplug during COPYING harms nothing.
@Observable
public final class StashManager {
    public private(set) var manifest: StashManifest
    public let stashRoot: URL           // /<Volume>/Stash
    public var volumeURL: URL { stashRoot.deletingLastPathComponent() }
    public var volumeName: String { volumeURL.lastPathComponent }

    /// Per-entry live progress for the StashToggle ring (0...1).
    public var progress: [UUID: Double] = [:]
    public var lastError: String?

    private let fm = FileManager.default

    public static func hostUUID() -> String {
        let key = "elbowroom.hostUUID"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }

    // MARK: Setup

    /// Create `/<Volume>/Stash/` + manifest or open an existing one.
    public init(volume: URL) throws {
        stashRoot = volume.appendingPathComponent("Stash", isDirectory: true)
        let manifestURL = stashRoot.appendingPathComponent("manifest.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: manifestURL),
           let existing = try? decoder.decode(StashManifest.self, from: data) {
            manifest = existing
        } else {
            try fm.createDirectory(at: stashRoot, withIntermediateDirectories: true)
            manifest = StashManifest(hostUUID: Self.hostUUID(), hostName: Host.current().localizedName ?? "Mac")
        }
        try journal()
        recoverAfterCrash()
    }

    public var isBoundToThisMac: Bool { manifest.hostUUID == Self.hostUUID() }

    /// A second Mac gets read-only browsing until rebind is confirmed.
    public func rebindToThisMac() throws {
        manifest.hostUUID = Self.hostUUID()
        manifest.hostName = Host.current().localizedName ?? "Mac"
        try journal()
    }

    /// Cached presence. Views and the Guardian read this on the main thread,
    /// and a stalled volume must never hang a render pass, so the stat that
    /// updates it always runs detached. Seeded true: init just
    /// completed real IO against the volume.
    public private(set) var volumeIsPresent = true

    /// Re-stat the volume off-main; `completion` runs on the main actor after
    /// the cache updates. Callers react to mount/unmount notifications rather
    /// than polling.
    public func refreshVolumePresence(_ completion: (@MainActor () -> Void)? = nil) {
        let path = stashRoot.path
        Task.detached(priority: .utility) { [weak self] in
            let present = FileManager.default.fileExists(atPath: path)
            await MainActor.run {
                self?.volumeIsPresent = present
                completion?()
            }
        }
    }

    public var stashedBytes: Int64 {
        manifest.entries.filter { $0.status == .done || $0.status == .doneDirty || $0.status == .committed }
            .reduce(0) { $0 + $1.bytes }
    }

    // MARK: Journal

    private func journal() throws {
        let url = stashRoot.appendingPathComponent("manifest.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)
        try data.write(to: url, options: .atomic)
    }

    private func setStatus(_ id: UUID, _ status: StashEntryStatus) throws {
        guard let i = manifest.entries.firstIndex(where: { $0.id == id }) else { return }
        manifest.entries[i].status = status
        try journal()
    }

    // MARK: Crash recovery (acceptance)

    /// Walk every entry and settle interrupted transactions.
    public func recoverAfterCrash() {
        for entry in manifest.entries {
            switch entry.status {
            case .copying, .verifying:
                // Partial copy: delete it, keep the untouched original.
                try? fm.removeItem(atPath: entry.stashPath)
                remove(entryID: entry.id)
            case .swapping:
                // Crash before the committed journal line: restore the name.
                let orig = entry.sourcePath + ".elbowroom-orig"
                if fm.fileExists(atPath: orig) {
                    if (try? fm.destinationOfSymbolicLink(atPath: entry.sourcePath)) != nil {
                        try? fm.removeItem(atPath: entry.sourcePath)
                    }
                    try? fm.moveItem(atPath: orig, toPath: entry.sourcePath)
                }
                try? fm.removeItem(atPath: entry.stashPath)
                remove(entryID: entry.id)
            case .committed:
                // Journal says the swap held: roll forward to CLEANING.
                finishCleaning(entry.id)
            case .returning:
                // Reverse move interrupted: stash copy still whole, retry later.
                let restore = entry.sourcePath + ".elbowroom-restore"
                try? fm.removeItem(atPath: restore)
                try? setStatus(entry.id, .done)
            case .done, .doneDirty, .retired:
                break
            }
        }
    }

    private func remove(entryID: UUID) {
        manifest.entries.removeAll { $0.id == entryID }
        try? journal()
    }

    // MARK: Preflight

    public func preflight(item: AtlasItem) throws {
        guard volumeIsPresent else { throw StashError.volumeAbsent }
        let values = try? volumeURL.resourceValues(forKeys: [.volumeAvailableCapacityKey])
        let free = Int64(values?.volumeAvailableCapacity ?? 0)
        if free < Int64(Double(item.bytes) * 1.05) {
            throw StashError.destinationFull(drive: volumeName)
        }
        if let blocker = Self.runningBlocker(for: item.entryID) {
            throw StashError.appRunning(app: blocker)
        }
    }

    public static func runningBlocker(for entryID: String) -> String? {
        let apps = StashRules.blockingApps[entryID] ?? []
        let running = NSWorkspace.shared.runningApplications
        for app in apps where running.contains(where: { $0.bundleIdentifier == app.bundleID }) {
            return app.name
        }
        return nil
    }

    // MARK: Move out

    public func stash(item: AtlasItem, fullHash: Bool = false) async throws {
        try preflight(item: item)
        var entry = StashEntry(
            entryID: item.entryID,
            sourcePath: item.url.path,
            stashPath: stashRoot.appendingPathComponent(stashName(for: item)).path,
            bytes: item.bytes,
            displayName: item.displayName
        )
        entry.status = .copying
        manifest.entries.append(entry)
        try journal()
        let id = entry.id

        do {
            // COPYING: cancel = delete partial, revert, no harm.
            try await copyTree(from: entry.sourcePath, to: entry.stashPath, expectedBytes: entry.bytes, entryID: id)

            // VERIFYING: byte totals + sampled hashes; mismatch keeps the original.
            try setStatus(id, .verifying)
            let ok = try verify(source: entry.sourcePath, copy: entry.stashPath, fullHash: fullHash)
            guard ok else {
                try? fm.removeItem(atPath: entry.stashPath)
                remove(entryID: id)
                throw StashError.verifyMismatch
            }

            // SWAPPING: the commit dance. Cancel is disabled for this window.
            try setStatus(id, .swapping)
            let orig = entry.sourcePath + ".elbowroom-orig"
            try fm.moveItem(atPath: entry.sourcePath, toPath: orig)
            do {
                try fm.createSymbolicLink(atPath: entry.sourcePath, withDestinationPath: entry.stashPath)
            } catch {
                // Undo the rename; original is untouched.
                try? fm.moveItem(atPath: orig, toPath: entry.sourcePath)
                try? fm.removeItem(atPath: entry.stashPath)
                remove(entryID: id)
                throw StashError.moveFailed
            }
            try setStatus(id, .committed)

            // CLEANING: failure = DONE-DIRTY, space not counted as freed.
            finishCleaning(id)
        } catch is CancellationError {
            try? fm.removeItem(atPath: entry.stashPath)
            remove(entryID: id)
            throw CancellationError()
        }
        await MainActor.run { progress[id] = nil }
    }

    private func finishCleaning(_ id: UUID) {
        guard let entry = manifest.entries.first(where: { $0.id == id }) else { return }
        let orig = entry.sourcePath + ".elbowroom-orig"
        if fm.fileExists(atPath: orig) {
            do {
                try fm.removeItem(atPath: orig)
                try? setStatus(id, .done)
            } catch {
                try? setStatus(id, .doneDirty)
            }
        } else {
            try? setStatus(id, .done)
        }
    }

    /// Retry the CLEANING step of a DONE-DIRTY entry (banner).
    public func retryClean(_ id: UUID) { finishCleaning(id) }

    // MARK: Bring back (mirrored, offboarding)

    public func bringHome(_ id: UUID, fullHash: Bool = false) async throws {
        guard let entry = manifest.entries.first(where: { $0.id == id }),
              entry.status == .done || entry.status == .doneDirty else { return }
        guard volumeIsPresent else { throw StashError.volumeAbsent }
        if let blocker = Self.runningBlocker(for: entry.entryID) {
            throw StashError.appRunning(app: blocker)
        }
        try setStatus(id, .returning)
        let restore = entry.sourcePath + ".elbowroom-restore"

        do {
            try await copyTree(from: entry.stashPath, to: restore, expectedBytes: entry.bytes, entryID: id)
            guard try verify(source: entry.stashPath, copy: restore, fullHash: fullHash) else {
                try? fm.removeItem(atPath: restore)
                try setStatus(id, .done)
                throw StashError.verifyMismatch
            }
            // Swap back: drop the symlink, restore the real folder.
            if (try? fm.destinationOfSymbolicLink(atPath: entry.sourcePath)) != nil {
                try fm.removeItem(atPath: entry.sourcePath)
            }
            try fm.moveItem(atPath: restore, toPath: entry.sourcePath)
            try? fm.removeItem(atPath: entry.stashPath)
            remove(entryID: id)
        } catch is CancellationError {
            try? fm.removeItem(atPath: restore)
            try? setStatus(id, .done)
            throw CancellationError()
        }
        await MainActor.run { progress[id] = nil }
    }

    /// Offboarding: reverse every move sequentially.
    public func bringEverythingHome(progressLine: @escaping @Sendable (String) -> Void) async throws {
        let ids = manifest.entries
            .filter { $0.status == .done || $0.status == .doneDirty }
            .map { ($0.id, $0.displayName) }
        for (id, name) in ids {
            progressLine(name)
            try await bringHome(id)
        }
    }

    // MARK: Conflict detection & reconcile

    /// A tool recreated a real folder where the symlink lived.
    public func clobberedEntries() -> [StashEntry] {
        manifest.entries.filter { entry in
            guard entry.status == .done || entry.status == .doneDirty else { return false }
            guard fm.fileExists(atPath: entry.sourcePath) else { return false }
            return (try? fm.destinationOfSymbolicLink(atPath: entry.sourcePath)) == nil
        }
    }

    /// Entries whose symlink is intact.
    public func verifySymlinks() -> Bool { clobberedEntries().isEmpty }

    /// One-click `Merge newer into Stash and relink`: the newer local
    /// folder replaces the stash copy, then the link goes back in.
    public func reconcileMergingLocal(_ id: UUID) async throws {
        guard let entry = manifest.entries.first(where: { $0.id == id }) else { return }
        try? fm.removeItem(atPath: entry.stashPath)
        try setStatus(id, .copying)
        try await copyTree(from: entry.sourcePath, to: entry.stashPath, expectedBytes: entry.bytes, entryID: id)
        try setStatus(id, .verifying)
        guard try verify(source: entry.sourcePath, copy: entry.stashPath, fullHash: false) else {
            throw StashError.verifyMismatch
        }
        try setStatus(id, .swapping)
        let orig = entry.sourcePath + ".elbowroom-orig"
        try fm.moveItem(atPath: entry.sourcePath, toPath: orig)
        try fm.createSymbolicLink(atPath: entry.sourcePath, withDestinationPath: entry.stashPath)
        try setStatus(id, .committed)
        finishCleaning(id)
    }

    /// `Keep local`: the entry retires; the stash copy deletes.
    public func reconcileKeepLocal(_ id: UUID) {
        guard let entry = manifest.entries.first(where: { $0.id == id }) else { return }
        try? fm.removeItem(atPath: entry.stashPath)
        try? setStatus(id, .retired)
    }

    // MARK: Copy + verify plumbing

    private func stashName(for item: AtlasItem) -> String {
        let base = item.displayName.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " · ", with: "-")
        return "\(base)-\(String(item.id.hashValue, radix: 36, uppercase: false).suffix(6))"
    }

    /// The enumerator hands back fully resolved paths (/var → /private/var)
    /// while Foundation's own resolvers leave /var alone, so relative-path
    /// math must run on realpath() on both sides.
    static func realPath(_ path: String) -> String {
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        if let r = realpath(path, &buf) { return String(cString: r) }
        return path
    }

    private func relative(of childPath: String, under basePath: String) -> String {
        let child = childPath.hasPrefix(basePath) ? childPath : Self.realPath(childPath)
        return String(child.dropFirst(basePath.count).drop(while: { $0 == "/" }))
    }

    /// File-by-file copy so progress is real and cancellation is clean.
    private func copyTree(from source: String, to dest: String, expectedBytes: Int64, entryID: UUID) async throws {
        let sourceURL = URL(fileURLWithPath: Self.realPath(source))
        let destURL = URL(fileURLWithPath: dest)
        try fm.createDirectory(at: destURL, withIntermediateDirectories: true)

        var isDir: ObjCBool = false
        fm.fileExists(atPath: source, isDirectory: &isDir)
        if !isDir.boolValue {
            try fm.removeItem(at: destURL)
            try fm.copyItem(at: sourceURL, to: destURL)
            return
        }

        guard let enumerator = fm.enumerator(
            at: sourceURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey],
            options: []
        ) else { throw StashError.moveFailed }

        var copied: Int64 = 0
        var lastReport = Date.distantPast
        while let obj = enumerator.nextObject() {
            try Task.checkCancellation()
            guard let fileURL = obj as? URL else { continue }
            let rel = relative(of: fileURL.path, under: sourceURL.path)
            let target = destURL.appendingPathComponent(rel)
            let rv = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey])
            if rv?.isSymbolicLink == true {
                if let dest = try? fm.destinationOfSymbolicLink(atPath: fileURL.path) {
                    try? fm.createSymbolicLink(atPath: target.path, withDestinationPath: dest)
                }
            } else if rv?.isDirectory == true {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
            } else {
                try? fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                do {
                    try fm.copyItem(at: fileURL, to: target)
                } catch CocoaError.fileWriteFileExists {
                    try fm.removeItem(at: target)
                    try fm.copyItem(at: fileURL, to: target)
                }
                copied += Int64(rv?.totalFileAllocatedSize ?? 0)
            }
            if Date().timeIntervalSince(lastReport) > 0.2 {
                lastReport = Date()
                let fraction = expectedBytes > 0 ? min(1, Double(copied) / Double(expectedBytes)) : 0
                await MainActor.run { self.progress[entryID] = fraction }
            }
        }
    }

    /// VERIFYING: byte totals + sampled hashes; full-hash on request.
    /// A file that cannot be read counts as a mismatch, never as a match.
    func verify(source: String, copy: String, fullHash: Bool) throws -> Bool {
        let a = try inventory(path: source)
        let b = try inventory(path: copy)
        guard a.count == b.count, abs(a.bytes - b.bytes) <= a.bytes / 1000 else { return false }

        let aBase = Self.realPath(source)
        let bBase = Self.realPath(copy)
        let sample = fullHash ? a.files : Array(a.files.shuffled().prefix(20))
        for rel in sample {
            let sh = try? hashPrefix(URL(fileURLWithPath: rel.isEmpty ? aBase : aBase + "/" + rel))
            let ch = try? hashPrefix(URL(fileURLWithPath: rel.isEmpty ? bBase : bBase + "/" + rel))
            if sh == nil || ch == nil || sh != ch { return false }
        }
        return true
    }

    private func inventory(path: String) throws -> (count: Int, bytes: Int64, files: [String]) {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else { return (0, 0, []) }
        let base = URL(fileURLWithPath: Self.realPath(path))
        if !isDir.boolValue {
            let size = (try? base.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return (1, Int64(size), [""])
        }
        var count = 0
        var bytes: Int64 = 0
        var files: [String] = []
        let enumerator = fm.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [])
        while let obj = enumerator?.nextObject() {
            guard let url = obj as? URL,
                  let rv = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  rv.isRegularFile == true else { continue }
            count += 1
            bytes += Int64(rv.fileSize ?? 0)
            files.append(relative(of: url.path, under: base.path))
        }
        return (count, bytes, files)
    }

    /// Hash the first megabyte; enough to catch a torn copy without reading
    /// the whole tree twice.
    private func hashPrefix(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 1_048_576) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
