import XCTest
@testable import ElbowroomKit

/// Real file-system tests in temp directories: the reclaim move, the stash
/// transaction, and crash matrix.
final class ReclaimExecutorTests: XCTestCase {
    var home: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        home = fm.temporaryDirectory.appendingPathComponent("elbowroom-home-\(UUID().uuidString)")
        try fm.createDirectory(at: home.appendingPathComponent(".Trash"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: home)
    }

    private func makeTree(_ rel: String, files: Int = 3) throws -> URL {
        let dir = home.appendingPathComponent(rel, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for i in 0..<files {
            try Data(repeating: UInt8(i), count: 4096)
                .write(to: dir.appendingPathComponent("file\(i).bin"))
        }
        return dir
    }

    /// Items move by rename into ~/.Trash/Elbowroom <date>/, preserving
    /// relative paths for restore.
    func testReclaimMovesToTrashPreservingPaths() async throws {
        let dir = try makeTree("Library/Caches/BigCache")
        let item = AtlasItem(entryID: "sys.appCache", url: dir, bytes: 12_288, lastTouched: nil)
        let outcome = await ReclaimExecutor().run(
            plan: ReclaimPlan(items: [item]), keepInTrash: true, home: home
        ) { _, _ in }

        XCTAssertEqual(outcome.doneCount, 1)
        XCTAssertFalse(fm.fileExists(atPath: dir.path), "original should be gone")
        let receipt = try XCTUnwrap(outcome.receipt)
        XCTAssertEqual(receipt.restoreStatus, .inTrash)
        let folder = try XCTUnwrap(receipt.trashFolder)
        XCTAssertTrue(folder.contains(".Trash/Elbowroom "))
        XCTAssertTrue(fm.fileExists(atPath: folder + "/Library/Caches/BigCache/file0.bin"))
    }

    func testRestorePutsEverythingBack() async throws {
        let dir = try makeTree("proj/node_modules")
        let item = AtlasItem(entryID: "js.nodeModules", url: dir, bytes: 12_288, lastTouched: nil)
        let outcome = await ReclaimExecutor().run(
            plan: ReclaimPlan(items: [item]), keepInTrash: true, home: home
        ) { _, _ in }
        let receipt = try XCTUnwrap(outcome.receipt)
        XCTAssertTrue(ReclaimExecutor().restore(receipt: receipt, home: home))
        XCTAssertTrue(fm.fileExists(atPath: dir.appendingPathComponent("file1.bin").path))
        XCTAssertFalse(fm.fileExists(atPath: receipt.trashFolder!))
    }

    /// A missing item is skipped and listed by name; the rest proceed.
    func testPartialFailureSkipsAndContinues() async throws {
        let good = try makeTree("ok")
        let missing = home.appendingPathComponent("not-there")
        let items = [
            AtlasItem(entryID: "sys.appCache", url: missing, bytes: 1, lastTouched: nil),
            AtlasItem(entryID: "sys.appCache", url: good, bytes: 12_288, lastTouched: nil),
        ]
        let outcome = await ReclaimExecutor().run(
            plan: ReclaimPlan(items: items), keepInTrash: true, home: home
        ) { _, _ in }
        XCTAssertEqual(outcome.doneCount, 1)
        XCTAssertEqual(outcome.skipped.count, 1)
        XCTAssertFalse(fm.fileExists(atPath: good.path))
    }

    func testDeleteNowLeavesNoTrashFolder() async throws {
        let dir = try makeTree("cache2")
        let item = AtlasItem(entryID: "sys.appCache", url: dir, bytes: 12_288, lastTouched: nil)
        let outcome = await ReclaimExecutor().run(
            plan: ReclaimPlan(items: [item]), keepInTrash: false, home: home
        ) { _, _ in }
        let receipt = try XCTUnwrap(outcome.receipt)
        XCTAssertEqual(receipt.restoreStatus, .deletedNow)
        XCTAssertNil(receipt.trashFolder)
        let trashContents = try fm.contentsOfDirectory(atPath: home.appendingPathComponent(".Trash").path)
        XCTAssertTrue(trashContents.filter { $0.hasPrefix("Elbowroom") }.isEmpty)
    }
}

@MainActor
final class StashManagerTests: XCTestCase {
    var volume: URL!
    var source: URL!
    let fm = FileManager.default

    override func setUp() async throws {
        volume = fm.temporaryDirectory.appendingPathComponent("elbowroom-vol-\(UUID().uuidString)")
        source = fm.temporaryDirectory.appendingPathComponent("elbowroom-src-\(UUID().uuidString)")
        try fm.createDirectory(at: volume, withIntermediateDirectories: true)
        try fm.createDirectory(at: source.appendingPathComponent("deep"), withIntermediateDirectories: true)
        for i in 0..<5 {
            try Data(repeating: UInt8(i), count: 8192)
                .write(to: source.appendingPathComponent(i < 3 ? "f\(i).bin" : "deep/f\(i).bin"))
        }
    }

    override func tearDown() async throws {
        try? fm.removeItem(at: volume)
        try? fm.removeItem(at: source)
        try? fm.removeItem(atPath: source.path + ".elbowroom-orig")
    }

    private func makeItem() -> AtlasItem {
        AtlasItem(entryID: "rust.target", url: source, bytes: 40_960, lastTouched: nil)
    }

    /// The full dance: after a stash the source is a symlink into the
    /// Stash, content readable through it, manifest DONE.
    func testFullMoveLeavesWorkingSymlink() async throws {
        let manager = try StashManager(volume: volume)
        try await manager.stash(item: makeItem())

        let entry = try XCTUnwrap(manager.manifest.entries.first)
        XCTAssertEqual(entry.status, .done)
        let linkDest = try fm.destinationOfSymbolicLink(atPath: source.path)
        XCTAssertEqual(linkDest, entry.stashPath)
        // Content is reachable through the old address.
        let throughLink = try Data(contentsOf: source.appendingPathComponent("deep/f4.bin"))
        XCTAssertEqual(throughLink.count, 8192)
        // No .elbowroom-orig residue.
        XCTAssertFalse(fm.fileExists(atPath: source.path + ".elbowroom-orig"))
    }

    func testBringHomeRestoresRealFolder() async throws {
        let manager = try StashManager(volume: volume)
        try await manager.stash(item: makeItem())
        let id = manager.manifest.entries[0].id
        try await manager.bringHome(id)

        XCTAssertNil(try? fm.destinationOfSymbolicLink(atPath: source.path), "should be a real folder again")
        XCTAssertTrue(fm.fileExists(atPath: source.appendingPathComponent("f0.bin").path))
        XCTAssertTrue(manager.manifest.entries.isEmpty)
    }

    /// Crash matrix: kill −9 mid-COPYING (journal says copying, partial
    /// copy on the volume). Relaunch recovers: partial deleted, source intact.
    func testCrashDuringCopyingRecovers() throws {
        var manifest = StashManifest(hostUUID: StashManager.hostUUID(), hostName: "test")
        let stashRoot = volume.appendingPathComponent("Stash")
        try fm.createDirectory(at: stashRoot, withIntermediateDirectories: true)
        let partial = stashRoot.appendingPathComponent("partial-copy")
        try fm.createDirectory(at: partial, withIntermediateDirectories: true)
        var entry = StashEntry(entryID: "rust.target", sourcePath: source.path,
                               stashPath: partial.path, bytes: 40_960, displayName: "target")
        entry.status = .copying
        manifest.entries = [entry]
        try writeManifest(manifest, to: stashRoot)

        let manager = try StashManager(volume: volume) // recovery runs in init
        XCTAssertTrue(manager.manifest.entries.isEmpty, "interrupted copy entry should clear")
        XCTAssertFalse(fm.fileExists(atPath: partial.path), "partial copy should delete")
        XCTAssertTrue(fm.fileExists(atPath: source.appendingPathComponent("f0.bin").path), "source untouched")
    }

    /// Crash after the rename but before the committed journal line: the name
    /// comes back (SWAPPING semantics).
    func testCrashDuringSwappingRestoresName() throws {
        var manifest = StashManifest(hostUUID: StashManager.hostUUID(), hostName: "test")
        let stashRoot = volume.appendingPathComponent("Stash")
        try fm.createDirectory(at: stashRoot, withIntermediateDirectories: true)
        let copy = stashRoot.appendingPathComponent("full-copy")
        try fm.copyItem(at: source, to: copy)
        // Simulate: mv source source.elbowroom-orig; symlink in; crash pre-journal.
        let orig = source.path + ".elbowroom-orig"
        try fm.moveItem(atPath: source.path, toPath: orig)
        try fm.createSymbolicLink(atPath: source.path, withDestinationPath: copy.path)
        var entry = StashEntry(entryID: "rust.target", sourcePath: source.path,
                               stashPath: copy.path, bytes: 40_960, displayName: "target")
        entry.status = .swapping
        manifest.entries = [entry]
        try writeManifest(manifest, to: stashRoot)

        let manager = try StashManager(volume: volume)
        XCTAssertTrue(manager.manifest.entries.isEmpty)
        XCTAssertNil(try? fm.destinationOfSymbolicLink(atPath: source.path), "symlink should be gone")
        XCTAssertTrue(fm.fileExists(atPath: source.appendingPathComponent("f1.bin").path), "original restored")
        XCTAssertFalse(fm.fileExists(atPath: orig))
    }

    /// Crash after the committed journal line: roll forward, clean the orig,
    /// end at DONE.
    func testCrashAfterCommitRollsForward() throws {
        var manifest = StashManifest(hostUUID: StashManager.hostUUID(), hostName: "test")
        let stashRoot = volume.appendingPathComponent("Stash")
        try fm.createDirectory(at: stashRoot, withIntermediateDirectories: true)
        let copy = stashRoot.appendingPathComponent("full-copy")
        try fm.copyItem(at: source, to: copy)
        let orig = source.path + ".elbowroom-orig"
        try fm.moveItem(atPath: source.path, toPath: orig)
        try fm.createSymbolicLink(atPath: source.path, withDestinationPath: copy.path)
        var entry = StashEntry(entryID: "rust.target", sourcePath: source.path,
                               stashPath: copy.path, bytes: 40_960, displayName: "target")
        entry.status = .committed
        manifest.entries = [entry]
        try writeManifest(manifest, to: stashRoot)

        let manager = try StashManager(volume: volume)
        XCTAssertEqual(manager.manifest.entries.first?.status, .done)
        XCTAssertFalse(fm.fileExists(atPath: orig), "orig cleans on roll-forward")
        XCTAssertNotNil(try? fm.destinationOfSymbolicLink(atPath: source.path), "symlink survives")
    }

    /// A clobbered symlink (tool recreated a real folder) reads as CONFLICT
    /// material.
    func testClobberDetection() async throws {
        let manager = try StashManager(volume: volume)
        try await manager.stash(item: makeItem())
        XCTAssertTrue(manager.clobberedEntries().isEmpty)
        // A tool clobbers the link with a real folder.
        try fm.removeItem(at: source)
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        XCTAssertEqual(manager.clobberedEntries().count, 1)
    }

    func testVerifyCatchesMismatch() throws {
        let manager = try StashManager(volume: volume)
        let copy = volume.appendingPathComponent("copy")
        try fm.copyItem(at: source, to: copy)
        XCTAssertTrue(try manager.verify(source: source.path, copy: copy.path, fullHash: true))
        // Corrupt one byte range.
        try Data(repeating: 0xFF, count: 8192).write(to: copy.appendingPathComponent("f0.bin"))
        XCTAssertFalse(try manager.verify(source: source.path, copy: copy.path, fullHash: true))
    }

    /// hostUUID binding: a manifest from another Mac reads but does not bind
    /// until rebind is confirmed.
    func testSecondMacReadOnlyUntilRebind() throws {
        var manifest = StashManifest(hostUUID: "OTHER-MAC", hostName: "old mac")
        let stashRoot = volume.appendingPathComponent("Stash")
        try fm.createDirectory(at: stashRoot, withIntermediateDirectories: true)
        manifest.entries = []
        try writeManifest(manifest, to: stashRoot)

        let manager = try StashManager(volume: volume)
        XCTAssertFalse(manager.isBoundToThisMac)
        try manager.rebindToThisMac()
        XCTAssertTrue(manager.isBoundToThisMac)
    }

    private func writeManifest(_ manifest: StashManifest, to stashRoot: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: stashRoot.appendingPathComponent("manifest.json"))
    }
}

final class ReceiptStoreTests: XCTestCase {
    func testAppendAndLifetime() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ReceiptStore(directory: dir)
        store.append(Receipt(
            items: [ReceiptItem(path: "/a", name: "a", bytes: 5, tier: .regenerable, entryID: "x")],
            restoreStatus: .inTrash, trashFolder: "/nonexistent-trash-folder"
        ))
        XCTAssertEqual(store.lifetimeBytes, 5)
        // Reload from disk.
        let store2 = ReceiptStore(directory: dir)
        XCTAssertEqual(store2.receipts.count, 1)
        // Sweep marks the receipt emptied when its folder is already gone.
        store2.sweepExpired()
        XCTAssertEqual(store2.receipts[0].restoreStatus, .emptied)
    }

    func testCSVExport() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ReceiptStore(directory: dir)
        store.append(Receipt(
            items: [ReceiptItem(path: "/a", name: "npm cache", bytes: 7, tier: .regenerable, entryID: "js.npmCache")],
            restoreStatus: .deletedNow, trashFolder: nil
        ))
        let csv = store.exportCSV()
        XCTAssertTrue(csv.hasPrefix("date,name,path,bytes,tier"))
        XCTAssertTrue(csv.contains("npm cache"))
    }
}

/// Catalog grouping: several locations of one Atlas category collapse
/// into one group row; singletons stay single rows.
final class CatalogGroupTests: XCTestCase {
    private func jsItem(_ path: String, bytes: Int64, project: String? = nil, stashed: Bool = false) -> AtlasItem {
        var item = AtlasItem(
            entryID: "js.nodeModules", url: URL(fileURLWithPath: path),
            bytes: bytes, lastTouched: nil, projectName: project
        )
        item.isStashed = stashed
        return item
    }

    func testGroupingCollapsesSameCategory() {
        let rust = AtlasItem(
            entryID: "rust.target", url: URL(fileURLWithPath: "/p/rusty/target"),
            bytes: 6_000, lastTouched: nil, projectName: "rusty"
        )
        let groups = CatalogGroup.build(
            items: [jsItem("/p/a/node_modules", bytes: 4_000), rust,
                    jsItem("/p/b/node_modules", bytes: 2_000), jsItem("/p/c/node_modules", bytes: 1_000)],
            ghosts: []
        )
        XCTAssertEqual(groups.map(\.entryID), ["js.nodeModules", "rust.target"])
        XCTAssertEqual(groups[0].count, 3)
        XCTAssertEqual(groups[0].totalBytes, 7_000)
        XCTAssertNil(groups[0].soleItem, "multi-location categories have no sole row")
        XCTAssertNotNil(groups[1].soleItem, "singletons render as plain rows")
    }

    func testPartialAndAllStashed() {
        let partial = CatalogGroup.build(
            items: [jsItem("/p/a/node_modules", bytes: 4_000, stashed: true),
                    jsItem("/p/b/node_modules", bytes: 2_000)],
            ghosts: []
        )[0]
        XCTAssertFalse(partial.allStashed)
        XCTAssertEqual(partial.stashedBytes, 4_000)

        let full = CatalogGroup.build(
            items: [jsItem("/p/a/node_modules", bytes: 4_000, stashed: true),
                    jsItem("/p/b/node_modules", bytes: 2_000, stashed: true)],
            ghosts: []
        )[0]
        XCTAssertTrue(full.allStashed)
    }

    func testGhostsJoinTheirGroup() {
        var ghost = StashEntry(
            entryID: "js.nodeModules", sourcePath: "/p/c/node_modules",
            stashPath: "/V/Stash/node_modules", bytes: 3_000, displayName: "JavaScript packages"
        )
        ghost.status = .done
        let groups = CatalogGroup.build(
            items: [jsItem("/p/a/node_modules", bytes: 4_000)],
            ghosts: [ghost]
        )
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].count, 2)
        XCTAssertEqual(groups[0].stashedBytes, 3_000)

        let ghostOnly = CatalogGroup.build(items: [], ghosts: [ghost])[0]
        XCTAssertTrue(ghostOnly.allStashed, "a category living entirely on the drive reads as offloaded")
    }
}

/// System residue: generic cache folders surface under the app's own name,
/// so three caches never read as three anonymous `App cache` rows.
final class AppNamesTests: XCTestCase {
    func testBundleIDsResolveToAppNames() {
        XCTAssertEqual(AppNames.human(fromCacheFolder: "com.docker.docker"), "Docker")
        XCTAssertEqual(AppNames.human(fromCacheFolder: "com.google.Chrome"), "Chrome")
        XCTAssertEqual(AppNames.human(fromCacheFolder: "com.apple.dt.Xcode"), "Xcode")
        XCTAssertEqual(AppNames.human(fromCacheFolder: "io.orbstack.docker"), "Docker")
    }

    func testOverridesCoverAwkwardBundleIDs() {
        XCTAssertEqual(AppNames.human(fromCacheFolder: "com.tinyspeck.slackmacgap"), "Slack")
        XCTAssertEqual(AppNames.human(fromCacheFolder: "com.microsoft.VSCode"), "VS Code")
        XCTAssertEqual(AppNames.human(fromCacheFolder: "com.googlecode.iterm2"), "iTerm2")
    }

    func testPlainFolderNamesPassThrough() {
        XCTAssertEqual(AppNames.human(fromCacheFolder: "Google"), "Google")
        XCTAssertEqual(AppNames.human(fromCacheFolder: "pip"), "pip")
        XCTAssertEqual(AppNames.human(fromCacheFolder: "node-gyp"), "node-gyp")
    }

    func testCacheItemDisplayNameCarriesTheAppName() {
        let item = AtlasItem(
            entryID: "sys.appCache",
            url: URL(fileURLWithPath: "/Users/dev/Library/Caches/com.spotify.client"),
            bytes: 2_000_000_000, lastTouched: nil
        )
        XCTAssertEqual(item.displayName, "Spotify cache")
        XCTAssertNotEqual(item.displayName, Atlas.entry("sys.appCache").title)
    }
}
