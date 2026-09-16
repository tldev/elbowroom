import XCTest
@testable import ElbowroomKit

final class StorageGroupTests: XCTestCase {
    func item(_ id: String, _ path: String, _ bytes: Int64 = 300_000_000, old: Bool = true) -> AtlasItem {
        AtlasItem(entryID: id, url: URL(fileURLWithPath: path), bytes: bytes,
                  lastTouched: old ? .distantPast : Date())
    }

    func testSameStorageAcrossLocationsBecomesOneRow() throws {
        let items = [item("js.nodeModules", "/project-a/node_modules", 300),
                     item("js.nodeModules", "/project-b/node_modules", 700),
                     item("lens.found", "/personal", 500)]
        let rows = LedgerProjection.rows(items: items)
        XCTAssertEqual(rows.count, 2)
        let merged = try XCTUnwrap(rows.first { $0.isMerged })
        XCTAssertEqual(merged.bytes, 1_000)
        XCTAssertEqual(Set(merged.items.map(\.id)), Set(items.prefix(2).map(\.id)))
        XCTAssertEqual(merged.name, Atlas.entry("js.nodeModules").title)
        XCTAssertTrue(merged.path.isEmpty)
        XCTAssertEqual(rows.reduce(0) { $0 + $1.bytes }, 1_500)
        XCTAssertEqual(LedgerProjection.rows(items: items.reversed()).map(\.id), rows.map(\.id))
    }

    func testAppCachesMergeOnlyForTheSameApp() throws {
        let slackA = AtlasItem(entryID: "storage.appCache", url: URL(fileURLWithPath: "/support/Slack/Cache"), bytes: 300, lastTouched: nil, projectName: "Slack")
        let slackB = AtlasItem(entryID: "storage.appCache", url: URL(fileURLWithPath: "/caches/Slack"), bytes: 500, lastTouched: nil, projectName: "Slack")
        let code = AtlasItem(entryID: "storage.appCache", url: URL(fileURLWithPath: "/caches/Code"), bytes: 200, lastTouched: nil, projectName: "Code")
        let rows = LedgerProjection.rows(items: [slackA, slackB, code])
        XCTAssertEqual(rows.count, 2)
        let merged = try XCTUnwrap(rows.first { $0.isMerged })
        XCTAssertEqual(merged.name, Copy.appCacheTitle("Slack"))
        XCTAssertEqual(merged.bytes, 800)
        XCTAssertFalse(merged.items.contains(code))
    }

    @MainActor
    func testMergedSelectionReviewAndSearchUseActualLocations() throws {
        let model = makeModel()
        let items = [item("js.nodeModules", "/project-a/node_modules"), item("js.nodeModules", "/project-b/node_modules")]
        let row = try XCTUnwrap(LedgerProjection.rows(items: items).first)
        model.setTray(items: [items[0]], selected: true)
        XCTAssertEqual(row.selectedCount(in: Set(model.trayItems.map(\.id))), 1)
        model.setTray(items: row.items, selected: true)
        XCTAssertEqual(Set(model.trayItems.map(\.id)), Set(items.map(\.id)))
        model.openReclaimPlan(items: row.items)
        XCTAssertEqual(Set(model.planItems.map(\.id)), Set(items.map(\.id)))
        model.setTray(items: row.items, selected: false)
        XCTAssertTrue(model.trayItems.isEmpty)
        let matches = LedgerProjection.rows(items: items, search: "project-b")
        XCTAssertEqual(matches.flatMap(\.items).map(\.id), [items[1].id])
        XCTAssertEqual(matches.first?.bytes, items[1].bytes)
    }

    func testPersonalAndManagedItemsStayIndependentAndSystemMergeHasNoCleanup() {
        let items = [item("lens.found", "/a"), item("lens.found", "/b"),
                     item("sys.iosBackups", "/backup-a"), item("sys.iosBackups", "/backup-b")]
        XCTAssertEqual(LedgerProjection.rows(items: items).count, 4)
        let system = LedgerProjection.rows(items: [item("storage.intelligence", "/system-a"), item("storage.intelligence", "/system-b")])
        XCTAssertEqual(system.count, 1)
        XCTAssertTrue(system[0].isMerged)
        XCTAssertTrue(system[0].items.allSatisfy { !ItemAction.canBatch($0) && ItemAction.resolve($0, tools: []) == nil })
    }

    @MainActor
    func testRecommendationsCombineSmallCachesButNotRecentBuildsOrPersonalData() throws {
        let model = makeModel()
        var result = Fixtures.scanResult()
        result.lensFindings = []
        result.items = [item("sys.appCache", "/cache-a", 70_000_000), item("js.npmCache", "/cache-b", 80_000_000),
                        item("xcode.spmBuild", "/old-build"), item("xcode.spmBuild", "/recent-build", old: false),
                        item("storage.historyAssistant", "/history"), item("storage.toolRuntime", "/runtime"),
                        item("docker.data", "/docker", 10_000_000_000)]
        model.result = result
        XCTAssertEqual(model.headroomBytes, 750_000_000)
        XCTAssertFalse(try XCTUnwrap(model.suggestions.first).members.isEmpty)
        let cache = try XCTUnwrap(model.suggestions.first { $0.id == "group.caches" })
        XCTAssertEqual(cache.bytes, 150_000_000)
        XCTAssertEqual(Set(cache.members.map(\.id)), ["/cache-a", "/cache-b"])
        XCTAssertEqual(model.suggestions.first { $0.id == "group.builds" }?.members.map(\.id), ["/old-build"])
        model.openReclaimPlan(items: cache.members)
        XCTAssertEqual(Set(model.planItems.map(\.id)), ["/cache-a", "/cache-b"])
        model.dismissSuggestion(cache.id)
        XCTAssertFalse(model.suggestions.contains { $0.id == cache.id })
        XCTAssertEqual(model.hiddenSuggestionCount, 1)
        model.showHiddenSuggestions()
        XCTAssertTrue(model.suggestions.contains { $0.id == cache.id })
    }

    func testRuntimeDependenciesAreNeverOfferedAsProjectBuildFiles() {
        for path in [".cache/codex-runtimes/runtime/dependencies/node", ".codex/plugins/cache/plugin",
                     ".local/share/claude/versions", ".vscode/extensions/editor", "runner/externals.2.337/node24/lib"] {
            XCTAssertNil(Atlas.classify(name: "node_modules", parentPath: "/Users/dev/" + path, home: "/Users/dev", siblings: nil))
        }
        XCTAssertEqual(Atlas.classify(name: "node_modules", parentPath: "/Users/dev/projects/site", home: "/Users/dev", siblings: nil), "js.nodeModules")
    }

    func testRecognitionKeepsExistingChildrenAndNamesOnlyTheRemainder() {
        let root = ScanNodeBuilder(path: "/", isDirectory: true, parent: nil)
        func node(_ path: String, _ bytes: Int64, _ parent: ScanNodeBuilder) -> ScanNodeBuilder {
            let n = ScanNodeBuilder(path: path, isDirectory: true, parent: parent)
            n.allocatedBytes = bytes; parent.children.append(n); return n
        }
        let home = node("/home", 1_000, root)
        let lib = node("/home/Library", 1_000, home)
        let support = node("/home/Library/Application Support", 1_000, lib)
        let app = node(support.path + "/App", 700, support)
        app.atlasEntryID = "app.bundle"
        let wallpaper = node(support.path + "/com.apple.wallpaper", 200, support)
        let found = StorageRecognition.items(root: root, home: "/home", known: [item("app.bundle", "/Applications/App.app", 700)])
        XCTAssertEqual(found.first { $0.id == wallpaper.path }?.bytes, 200)
        XCTAssertEqual(found.first { $0.id == support.path }?.bytes, 100)
        XCTAssertEqual(found.reduce(700) { $0 + $1.bytes }, 1_000)
        for item in found {
            XCTAssertFalse(ItemAction.canBatch(item))
            XCTAssertNil(ItemAction.suggestion(item, tools: []))
            XCTAssertNil(ItemAction.resolve(item, tools: []))
        }
    }

    func testAppCacheExtractionPreservesWebsiteStorageAndUnknownApps() {
        let root = ScanNodeBuilder(path: "/support", isDirectory: true, parent: nil)
        for name in ["Cache", "GPUCache", "Service Worker", "IndexedDB", "Local Storage", "vm_bundles"] {
            let n = ScanNodeBuilder(path: "/support/" + name, isDirectory: true, parent: root)
            n.allocatedBytes = 100; root.children.append(n)
        }
        XCTAssertTrue(AppsPass.cacheComponents(in: root, bundleID: "unknown.app", owner: "Unknown").isEmpty)
        let found = AppsPass.cacheComponents(in: root, bundleID: "com.tinyspeck.slackmacgap", owner: "Slack")
        XCTAssertEqual(Set(found.map { $0.url.lastPathComponent }), ["Cache", "GPUCache"])
        XCTAssertTrue(root.children.filter { ["Service Worker", "IndexedDB", "Local Storage", "vm_bundles"].contains($0.name) }.allSatisfy { $0.atlasEntryID == nil })
    }

    func testAppAndCacheBytesReconcileWithNestedKnownModel() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: home) }
        let appURL = home.appendingPathComponent("Applications/Test.app")
        try fm.createDirectory(at: appURL.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.google.Chrome", "CFBundleName": "Test", "CFBundlePackageType": "APPL"], format: .xml, options: 0)
        try data.write(to: appURL.appendingPathComponent("Contents/Info.plist"))
        let root = ScanNodeBuilder(path: home.path, isDirectory: true, parent: nil)
        func node(_ relative: String, _ bytes: Int64, _ parent: ScanNodeBuilder) -> ScanNodeBuilder {
            let n = ScanNodeBuilder(path: home.path + "/" + relative, isDirectory: true, parent: parent)
            n.allocatedBytes = bytes; parent.children.append(n); return n
        }
        let apps = node("Applications", 1_000, root)
        _ = node("Applications/Test.app", 1_000, apps)
        let lib = node("Library", 1_200, root)
        let support = node("Library/Application Support", 1_000, lib)
        let google = node("Library/Application Support/Google", 1_000, support)
        let chrome = node("Library/Application Support/Google/Chrome", 1_000, google)
        _ = node("Library/Application Support/Google/Chrome/Cache", 300, chrome)
        let model = node("Library/Application Support/Google/Chrome/OptGuideOnDeviceModel", 100, chrome)
        model.atlasEntryID = "chrome.optGuide"
        let caches = node("Library/Caches", 200, lib)
        _ = node("Library/Caches/com.google.Chrome", 200, caches)
        let found = AppsPass.items(root: root, homePath: home.path)
        XCTAssertEqual(found.first { $0.entryID == "app.bundle" }?.bytes, 1_600)
        XCTAssertEqual(found.filter { $0.entryID == "storage.appCache" }.reduce(0) { $0 + $1.bytes }, 500)
        XCTAssertEqual(found.reduce(100) { $0 + $1.bytes }, 2_200)
    }
}
