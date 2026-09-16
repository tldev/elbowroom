import XCTest
@testable import ElbowroomKit

@MainActor
final class InventoryTests: XCTestCase {
    func testPublishedSnapshotIsIndependentOfBuilder() {
        let builder = ScanNodeBuilder(path: "/fixture", isDirectory: true, parent: nil)
        builder.allocatedBytes = 4096
        let snapshot = builder.snapshot()
        builder.allocatedBytes = 8192
        XCTAssertEqual(snapshot.allocatedBytes, 4096)
    }

    func testBackgroundEncodingRetainsOriginalSnapshot() async throws {
        let inventory = Inventory()
        inventory.replace(with: Fixtures.scanResult())
        let original = try XCTUnwrap(inventory.result)
        let first = try XCTUnwrap(original.items.first)
        let encoding = Task.detached { try JSONEncoder().encode(original) }
        inventory.updateBytes(1, itemID: first.id, expectedRevision: inventory.revision)
        let decoded = try JSONDecoder().decode(ScanResult.self, from: await encoding.value)
        XCTAssertEqual(decoded.items.first?.bytes, first.bytes)
        XCTAssertEqual(inventory.result?.items.first?.bytes, 1)
    }

    func testOldEnrichmentCannotOverwriteNewInventory() throws {
        let inventory = Inventory()
        inventory.replace(with: Fixtures.scanResult())
        let revision = inventory.revision
        let item = try XCTUnwrap(inventory.items.first)
        inventory.replace(with: Fixtures.scanResult())
        inventory.updateBytes(1, itemID: item.id, expectedRevision: revision)
        XCTAssertEqual(inventory.items.first?.bytes, item.bytes)
    }

    func testRemovalUpdatesTreeAndFindingsWithoutChangingOldSnapshot() throws {
        let inventory = Inventory()
        var original = Fixtures.scanResult()
        let finding = LensFinding(kind: .weights, url: URL(fileURLWithPath: "/fixture/weights"),
                                  bytes: 42, count: 1, date: nil)
        original.lensFindings = [finding]
        inventory.replace(with: original)
        inventory.remove(paths: ["/fixture"])
        XCTAssertTrue(inventory.result!.lensFindings.isEmpty)
        XCTAssertFalse(inventory.items.contains { $0.entryID == "lens.found" })
        XCTAssertEqual(original.lensFindings.count, 1)
    }

    func testStoreLoadPreservesChangesMadeDuringStartup() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = Receipt(items: [], restoreStatus: .deletedNow, trashFolder: nil)
        let second = Receipt(items: [], restoreStatus: .deletedNow, trashFolder: nil)
        let writer = ReceiptStore(directory: directory)
        writer.append(first)
        await writer.flush()
        let reader = ReceiptStore(directory: directory)
        reader.append(second)
        await reader.loadFromDisk()
        XCTAssertEqual(Set(reader.receipts.map(\.id)), [first.id, second.id])
        await reader.flush()
    }

    func testTreeRemovalCopiesOnlyThePublishedValue() throws {
        let inventory = Inventory()
        let original = Fixtures.scanResult()
        let child = try XCTUnwrap(original.root.children.first)
        inventory.replace(with: original)
        inventory.remove(paths: [child.path])
        XCTAssertNil(inventory.result?.root.find(path: child.path))
        XCTAssertNotNil(original.root.find(path: child.path))
        XCTAssertEqual(inventory.result?.root.allocatedBytes, original.root.allocatedBytes - child.allocatedBytes)
    }

    func testCancelledProjectionDoesNotReplaceDisplayedRows() async {
        let projection = LedgerModel()
        let items = Fixtures.scanResult().items
        let initial = LedgerQuery(revision: 1)
        await projection.update(items: items, insights: [], query: initial)
        let before = projection.rows.map(\.id)
        let task = Task {
            await projection.update(items: [], insights: [], query: LedgerQuery(revision: 2))
        }
        task.cancel()
        await task.value
        XCTAssertEqual(projection.completedQuery, initial)
        XCTAssertEqual(projection.rows.map(\.id), before)
    }

    func testNewerQueryWinsOverAnInFlightProjection() async {
        let projection = LedgerModel()
        let items = Fixtures.scanResult().items
        let first = Task {
            await projection.update(items: Array(repeating: items, count: 500).flatMap { $0 },
                                    insights: [], query: LedgerQuery(revision: 1))
        }
        await Task.yield()
        let latest = LedgerQuery(revision: 2, search: "no-matching-item")
        await projection.update(items: items, insights: [], query: latest)
        await first.value
        XCTAssertEqual(projection.completedQuery, latest)
        XCTAssertTrue(projection.rows.isEmpty)
    }
}

final class ItemActionTests: XCTestCase {
    private func item(_ entry: String) -> AtlasItem {
        AtlasItem(entryID: entry, url: URL(fileURLWithPath: "/fixture/" + entry),
                  bytes: 2_000_000_000, lastTouched: .distantPast)
    }

    func testToolAvailabilityChoosesCleanupOrLesson() {
        let docker = item("docker.data")
        XCTAssertEqual(ItemAction.resolve(docker, tools: [.docker]), .cleanup)
        // A stopped engine must still enter the cleanup sheet, which owns
        // launching Docker and refreshing once its daemon is ready.
        XCTAssertEqual(ItemAction.resolve(docker, tools: []), .cleanup)
    }

    func testPersonalAndAppItemsAreNeverSuggestedOrBatched() {
        XCTAssertNil(ItemAction.suggestion(item("app.bundle"), tools: []))
        XCTAssertNil(ItemAction.suggestion(item("lens.found"), tools: []))
        XCTAssertFalse(ItemAction.canBatch(item("app.bundle")))
        XCTAssertTrue(ItemAction.canBatch(item("lens.found")))
        XCTAssertEqual(ItemAction.resolve(item("app.bundle"), tools: []), .uninstall)
    }

    func testSpecializedTrimsAndDirectManagedReclaim() {
        XCTAssertEqual(ItemAction.resolve(item("sys.messages"), tools: []), .trimMessages)
        XCTAssertEqual(ItemAction.resolve(item("sys.photosLibrary"), tools: []), .trimPhotos)
        XCTAssertEqual(ItemAction.resolve(item("sys.iosBackups"), tools: []), .reclaim)
        XCTAssertFalse(ItemAction.canBatch(item("sys.iosBackups")))
    }

    func testProjectionFiltersAndSorts() {
        let items = [item("sys.messages"), item("js.nodeModules"), item("app.bundle")]
        let rows = LedgerProjection.rows(items: items, tier: .rebuildable, search: "nodeModules")
        XCTAssertEqual(rows.map(\.id), [items[1].id])
        let sorted = LedgerProjection.rows(items: items, sort: .name)
        XCTAssertEqual(LedgerProjection.rows(items: items, sort: .name, ascending: true).map(\.id), sorted.reversed().map(\.id))
    }
}
