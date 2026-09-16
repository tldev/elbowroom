import XCTest
@testable import ElbowroomKit

/// Real file-system tests in temp directories: the reclaim move and
/// receipts.
final class ReclaimExecutorTests: XCTestCase {
    func testAccessDeniedRecognizesCocoaWritePermission() {
        XCTAssertTrue(ReclaimExecutor.isAccessDenied(NSError(
            domain: NSCocoaErrorDomain, code: CocoaError.fileWriteNoPermission.rawValue)))
    }

    func testAccessDeniedRecognizesUnderlyingPOSIXErrors() {
        for code in [EACCES, EPERM] {
            let underlying = NSError(domain: NSPOSIXErrorDomain, code: Int(code))
            let wrapped = NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteUnknown.rawValue,
                                  userInfo: [NSUnderlyingErrorKey: underlying])
            XCTAssertTrue(ReclaimExecutor.isAccessDenied(wrapped))
        }
    }

    func testMissingFileDoesNotSuggestPermissionSettings() {
        XCTAssertFalse(ReclaimExecutor.isAccessDenied(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT))))
    }

    func testFullDiskDoesNotSuggestPermissionSettings() {
        XCTAssertFalse(ReclaimExecutor.isAccessDenied(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))))
    }

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

    func testReclaimHasNoLifetimeOrPerRunByteLimit() async throws {
        // Small fixtures carry large scan estimates; no large files are needed.
        for run in 0..<2 {
            let urls = try (0..<2).map { try makeTree("run-\(run)/cache-\($0)") }
            let items = urls.map {
                AtlasItem(entryID: "js.npmCache", url: $0, bytes: 11_000_000_000, lastTouched: nil)
            }
            let outcome = await ReclaimExecutor().run(
                plan: ReclaimPlan(items: items), keepInTrash: true, home: home
            ) { _, _ in }
            XCTAssertEqual(outcome.doneCount, 2)
            XCTAssertEqual(outcome.reclaimedBytes, 22_000_000_000)
            XCTAssertTrue(outcome.skipped.isEmpty)
            let receipt = try XCTUnwrap(outcome.receipt)
            XCTAssertTrue(ReclaimExecutor().restore(receipt: receipt, home: home))
            for url in urls { XCTAssertTrue(fm.fileExists(atPath: url.path)) }
        }
    }

    func testUninstallUsesSystemTrashLocationsForBundleAndResidue() async throws {
        let app = try makeTree("Applications/Fake.app")
        let residue = try makeTree("Library/Caches/Fake")
        let systemTrash = home.appendingPathComponent("SystemTrash")
        try fm.createDirectory(at: systemTrash, withIntermediateDirectories: true)
        let executor = ReclaimExecutor(recycle: { url in
            let landed = systemTrash.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: landed)
            return landed
        })
        let outcome = await executor.run(plan: ReclaimPlan(items: [
            AtlasItem(entryID: "app.bundle", url: app, bytes: 12_288, lastTouched: nil),
            AtlasItem(entryID: "sys.appCache", url: residue, bytes: 12_288, lastTouched: nil),
        ]), keepInTrash: true, home: home) { _, _ in }
        XCTAssertEqual(outcome.doneCount, 2)
        let receipt = try XCTUnwrap(outcome.receipt)
        XCTAssertNil(receipt.trashFolder, "system destinations must not be swept as one custom folder")
        XCTAssertEqual(receipt.items.map(\.trashedTo), [
            systemTrash.appendingPathComponent("Fake.app").path,
            systemTrash.appendingPathComponent("Fake").path,
        ])
        XCTAssertTrue(executor.restore(receipt: receipt, home: home))
        XCTAssertTrue(fm.fileExists(atPath: app.appendingPathComponent("file0.bin").path))
        XCTAssertTrue(fm.fileExists(atPath: residue.appendingPathComponent("file0.bin").path))
    }

    func testSystemTrashDenialPreservesAppAndReportsFailure() async throws {
        let app = try makeTree("Applications/Fake.app")
        let residue = try makeTree("Library/Caches/Fake")
        let executor = ReclaimExecutor(recycle: { url in
            XCTAssertEqual(url, app, "failed app removal must preserve supporting data")
            throw CocoaError(.fileWriteNoPermission)
        })
        let outcome = await executor.run(plan: ReclaimPlan(items: [
            AtlasItem(entryID: "app.bundle", url: app, bytes: 12_288, lastTouched: nil),
            AtlasItem(entryID: "sys.appCache", url: residue, bytes: 12_288, lastTouched: nil),
        ]), keepInTrash: true, home: home) { _, _ in }
        XCTAssertEqual(outcome.doneCount, 0)
        XCTAssertEqual(outcome.accessDeniedAppPaths, [app.path])
        XCTAssertEqual(outcome.skipped.count, 1)
        XCTAssertNil(outcome.receipt)
        XCTAssertTrue(fm.fileExists(atPath: app.path))
        XCTAssertTrue(fm.fileExists(atPath: residue.path))
    }

    func testCancellingSystemTrashStopsBeforeResidue() async throws {
        let app = try makeTree("Applications/Fake.app")
        let residue = try makeTree("Library/Caches/Fake")
        let executor = ReclaimExecutor(recycle: { url in
            XCTAssertEqual(url, app, "cancellation must not continue into residue")
            throw CocoaError(.userCancelled)
        })
        let outcome = await executor.run(plan: ReclaimPlan(items: [
            AtlasItem(entryID: "app.bundle", url: app, bytes: 12_288, lastTouched: nil),
            AtlasItem(entryID: "sys.appCache", url: residue, bytes: 12_288, lastTouched: nil),
        ]), keepInTrash: true, home: home) { _, _ in }
        XCTAssertTrue(outcome.cancelled)
        XCTAssertTrue(outcome.skipped.isEmpty)
        XCTAssertTrue(outcome.accessDeniedAppPaths.isEmpty)
        XCTAssertNil(outcome.receipt)
        XCTAssertTrue(fm.fileExists(atPath: app.path))
        XCTAssertTrue(fm.fileExists(atPath: residue.path))
    }

    func testSystemTrashDeleteNowUsesReturnedDestination() async throws {
        let app = try makeTree("Applications/Fake.app")
        let landed = home.appendingPathComponent("SystemTrashApp")
        let executor = ReclaimExecutor(recycle: { url in
            try FileManager.default.moveItem(at: url, to: landed)
            return landed
        })
        let outcome = await executor.run(plan: ReclaimPlan(items: [
            AtlasItem(entryID: "app.bundle", url: app, bytes: 12_288, lastTouched: nil),
        ]), keepInTrash: false, home: home) { _, _ in }
        XCTAssertEqual(outcome.doneCount, 1)
        XCTAssertEqual(outcome.receipt?.restoreStatus, .deletedNow)
        XCTAssertFalse(fm.fileExists(atPath: landed.path))
        XCTAssertFalse(fm.fileExists(atPath: app.path))
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

    func testFailedRestorePreservesTrashedFiles() async throws {
        let first = try makeTree("first")
        let second = try makeTree("second")
        let items = [first, second].map {
            AtlasItem(entryID: "sys.appCache", url: $0, bytes: 12_288, lastTouched: nil)
        }
        let executor = ReclaimExecutor()
        let outcome = await executor.run(plan: ReclaimPlan(items: items), keepInTrash: true, home: home) { _, _ in }
        let receipt = try XCTUnwrap(outcome.receipt)
        // The app recreated one cache before Put Back was clicked.
        try Data("replacement".utf8).write(to: second)

        XCTAssertFalse(executor.restore(receipt: receipt, home: home))
        XCTAssertTrue(fm.fileExists(atPath: first.appendingPathComponent("file0.bin").path))
        let landed = try XCTUnwrap(receipt.items.last?.trashedTo)
        XCTAssertTrue(fm.fileExists(atPath: landed + "/file0.bin"), "failed restores must remain recoverable")
        XCTAssertEqual(try String(contentsOf: second), "replacement")
    }

    func testRunsAtSameTimeHaveSeparateTrashFolders() {
        let date = Date(timeIntervalSince1970: 1_000)
        XCTAssertNotEqual(ReclaimExecutor.trashFolderName(date: date),
                          ReclaimExecutor.trashFolderName(date: date))
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
final class ReceiptStoreTests: XCTestCase {
    func testAppendAndLifetime() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ReceiptStore(directory: dir)
        store.append(Receipt(
            items: [ReceiptItem(path: "/a", name: "a", bytes: 5, tier: .regenerable, entryID: "x")],
            restoreStatus: .inTrash, trashFolder: "/nonexistent-trash-folder"
        ))
        XCTAssertEqual(store.lifetimeBytes, 5)
        // Reload from disk.
        await store.flush()
        let store2 = ReceiptStore(directory: dir)
        await store2.loadFromDisk()
        XCTAssertEqual(store2.receipts.count, 1)
        // Sweep marks the receipt emptied when its folder is already gone.
        await store2.sweepExpired()
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

    func testCSVPreservesCommasQuotesAndNewlines() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ReceiptStore(directory: dir)
        store.append(Receipt(
            items: [ReceiptItem(path: "/cache/a,b", name: "a,\"b\"\nc", bytes: 7,
                                tier: .regenerable, entryID: "js.npmCache")],
            restoreStatus: .deletedNow, trashFolder: nil
        ))
        XCTAssertTrue(store.exportCSV().contains(",\"a,\"\"b\"\"\nc\",\"/cache/a,b\",7,"))
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

/// A clean reclaim closes the plan sheet itself, with no OK press to clear
/// run state. The next plan must open on the plan list, never on the last
/// run's finished progress view.
@MainActor
final class ReclaimPlanStateTests: XCTestCase {
    private func makeItem() -> AtlasItem {
        AtlasItem(entryID: "sys.appCache",
                  url: URL(fileURLWithPath: "/tmp/elbowroom-test-cache"),
                  bytes: 1_000, lastTouched: nil)
    }

    func testCleanOutcomeDoesNotLeakIntoNextPlan() {
        let model = makeModel()
        model.reclaimOutcome = ReclaimOutcome(
            reclaimedBytes: 1_000, doneCount: 1, skipped: [], receipt: nil, cancelled: false
        )
        model.reclaimStatuses = [.done]

        model.openReclaimPlan(items: [makeItem()])

        XCTAssertNil(model.reclaimOutcome, "stale outcome must clear on open")
        XCTAssertTrue(model.reclaimStatuses.isEmpty, "stale statuses must clear on open")
        XCTAssertEqual(model.sheet?.id, "plan")
    }

    func testLiveRunKeepsItsViewOnReopen() {
        let model = makeModel()
        model.reclaiming = true
        model.reclaimStatuses = [.moving]

        model.openReclaimPlan(items: [makeItem()])

        XCTAssertEqual(model.reclaimStatuses, [.moving], "a run in flight keeps its live state")
    }

    /// The plan's Keep in Trash checkbox starts from the settings default,
    /// not from wherever the last run left it.
    func testKeepInTrashStartsFromSettingsDefault() {
        let model = makeModel()
        let saved = model.settings.keepInTrashDefault
        defer { model.settings.keepInTrashDefault = saved }

        model.settings.keepInTrashDefault = false
        model.planKeepInTrash = true
        model.openReclaimPlan(items: [makeItem()])
        XCTAssertFalse(model.planKeepInTrash)

        model.settings.keepInTrashDefault = true
        model.planKeepInTrash = false
        model.openReclaimPlan(items: [makeItem()])
        XCTAssertTrue(model.planKeepInTrash)
    }
}
