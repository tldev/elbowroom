import XCTest
@testable import ElbowroomKit

final class RecognizedStorageTests: XCTestCase {
    func testStructuralIdentitiesRequireMarkersAndHaveNoDeletionActions() {
        let environment: Set<String> = ["pyvenv.cfg", "lib", "bin"]
        let runner: Set<String> = [".runner", ".credentials", "bin", "externals.1"]
        for (names, id) in [(environment, "storage.pythonEnvironments"), (runner, "storage.runners")] {
            XCTAssertEqual(StorageRecognition.structuralIdentity(names: names, path: "/home/arbitrary", home: "/home"), id)
            XCTAssertNil(StorageRecognition.structuralIdentity(names: names, path: "/home/Library/app", home: "/home"))
            XCTAssertNil(StorageRecognition.structuralIdentity(names: names, path: "/home-other/arbitrary", home: "/home"))
            let item = AtlasItem(entryID: id, url: URL(fileURLWithPath: "/home/arbitrary"), bytes: 100, lastTouched: nil)
            XCTAssertNil(ItemAction.resolve(item, tools: []))
            XCTAssertFalse(ItemAction.canBatch(item))
        }
        XCTAssertNil(StorageRecognition.structuralIdentity(names: ["bin", "lib"], path: "/home/.venv", home: "/home"))
    }

    func testStructuralScanKeepsInstalledDependenciesAndSmallCachesDistinct() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for path in ["env/pyvenv.cfg", "env/bin/python", "env/lib/node_modules/pkg/file",
                     "runner/.runner", "runner/.credentials", "runner/bin/file", "runner/externals/node_modules/pkg/file",
                     "Library/Caches/small-app/file"] {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 42, count: 300_000).write(to: url)
        }
        var result: ScanResult?
        for try await event in ScanEngine().scan(root: root, home: root) {
            if case .finished(let value) = event { result = value }
        }
        let scan = try XCTUnwrap(result)
        XCTAssertEqual(scan.items.filter { $0.entryID == "storage.pythonEnvironments" }.count, 1)
        XCTAssertEqual(scan.items.filter { $0.entryID == "storage.runners" }.count, 1)
        XCTAssertFalse(scan.items.contains { $0.entryID == "js.nodeModules" })
        XCTAssertEqual(scan.items.filter { $0.entryID == "sys.appCache" }.count, 1)
        let restored = try JSONDecoder().decode(ScanResult.self, from: JSONEncoder().encode(scan))
        XCTAssertEqual(restored.outsideWalkBytes, scan.outsideWalkBytes)
    }

    func testMediaRecognitionDoesNotDoubleCountLibrariesOrReviewItems() {
        let root = ScanNodeBuilder(path: "/home", isDirectory: true, parent: nil)
        let library = ScanNodeBuilder(path: "/home/library", isDirectory: true, parent: root)
        library.atlasEntryID = "personal.videoLibrary"
        root.children = [library]
        let paths = ["/home/clips/clip.MOV", "/home/library/clip.mov", "/home/review/clip.mp4", "/home/file.txt"]
        let facts = paths.map { FileFact(path: $0, bytes: 300_000, modified: .distantPast, isDirectory: false) }
        let items = StorageRecognition.mediaItems(root: root, facts: facts + facts, home: "/home", excluding: ["/home/review"])
        XCTAssertEqual(items.map(\.id), [paths[0]])
        XCTAssertFalse(ItemAction.canBatch(items[0]))
    }

    func testRemainingBalanceKeepsUnmeasuredSpaceExplicit() {
        let balance = StorageBalance(used: 100, scanned: 70, named: 80, outsideWalk: 15)
        XCTAssertEqual(balance.readable, 5)
        XCTAssertEqual(balance.unmeasured, 15)
        XCTAssertEqual(StorageBalance(used: 100, scanned: 120, named: 80, outsideWalk: 15).readable, 20)
        XCTAssertEqual(StorageBalance(used: 100, scanned: 70, named: 110, outsideWalk: 15).unmeasured, 0)
    }

    func testPersonalRemaindersExcludeCachesReviewFilesAndNestedProjects() throws {
        let root = ScanNodeBuilder(path: "/home", isDirectory: true, parent: nil)
        let docs = ScanNodeBuilder(path: "/home/Documents", isDirectory: true, parent: root)
        let project = ScanNodeBuilder(path: "/home/Documents/project", isDirectory: true, parent: docs)
        let cache = ScanNodeBuilder(path: project.path + "/node_modules", isDirectory: true, parent: project)
        cache.allocatedBytes = 100
        cache.atlasEntryID = "js.nodeModules"
        project.children = [cache]; project.allocatedBytes = 400
        docs.children = [project]; docs.allocatedBytes = 450
        root.children = [docs]; root.allocatedBytes = 450
        let result = StorageRecognition.personalItems(root: root, home: "/home", projects: [project.path],
            findings: [(project.path + "/archive.zip", 200)])
        XCTAssertEqual(result.first { $0.entryID == "storage.projects" }?.bytes, 100)
        XCTAssertEqual(result.first { $0.entryID == "storage.documents" }?.bytes, 50)
        XCTAssertEqual(result.reduce(0) { $0 + $1.bytes } + 100 + 200, root.allocatedBytes)
        for item in result {
            XCTAssertNil(ItemAction.resolve(item, tools: []))
            XCTAssertFalse(ItemAction.canBatch(item))
        }
    }

    func testSystemTraversalIncludesDataOnlyLocationsWithoutAliasesOrMountedImages() {
        for path in ["/System", "/System/Volumes", "/System/Volumes/Data",
                     "/System/Volumes/Data/System", "/System/Volumes/Data/macOS Install Data",
                     "/System/Volumes/Data/.Spotlight-V100", "/private/var/db", "/private/var/folders",
                     "/usr/local", "/usr/libexec/cups", "/usr/share/snmp"] {
            XCTAssertFalse(ScanEngine.shouldSkip(path: path), path)
        }
        for path in ["/System/Library", "/System/Volumes/Preboot", "/System/Volumes/VM",
                     "/System/Volumes/Data/Users", "/System/Volumes/Data/private",
                     "/System/Volumes/Data/Applications", "/Volumes",
                     "/System/Volumes/Data" + ScanEngine.runtimeAssetStore, "/bin", "/sbin",
                     "/usr/bin", "/usr/lib", "/usr/share/man", "/usr/libexec/other"] {
            XCTAssertTrue(ScanEngine.shouldSkip(path: path), path)
        }
        for path in ["/private/var/folders", "/private/var/db/diagnostics",
                     "/System/Volumes/Data/System", "/System/Volumes/Data/macOS Install Data"] {
            let id = Atlas.classify(path: path, home: "/Users/test")!
            let item = AtlasItem(entryID: id, url: URL(fileURLWithPath: path), bytes: 1_000_000, lastTouched: nil)
            XCTAssertEqual(item.entry.tier, .system)
            XCTAssertNil(ItemAction.resolve(item, tools: []))
            XCTAssertFalse(ItemAction.canBatch(item))
        }
    }

    func testDeepFilesAreMeasuredBeyondFormerDepthLimit() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent(Array(repeating: "nested", count: 32).joined(separator: "/") + "/file")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 42, count: 300_000).write(to: file)
        var result: ScanResult?
        for try await event in ScanEngine().scan(root: root, home: root) {
            if case .finished(let value) = event { result = value }
        }
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(result).scannedBytes, 300_000)
    }

    func testCachePathsDoNotClaimInstalledToolsOrConfiguration() {
        let home = "/Users/test"
        let caches = [".cache/uv": "py.uvCache", "Library/Caches/pip": "py.pipCache",
                      ".cache/pip": "py.pipCache", ".gradle/caches": "gradle.caches"]
        for (path, id) in caches {
            XCTAssertEqual(Atlas.classify(path: home + "/" + path, home: home), id)
            XCTAssertNil(Atlas.classify(path: home + "-other/" + path, home: home))
        }
        for path in [".local/share/uv", ".local/share/uv/python", ".local/share/uv/tools",
                     ".gradle", ".gradle/gradle.properties", ".gradle/init.d"] {
            XCTAssertNil(Atlas.classify(path: home + "/" + path, home: home))
        }
    }

    func testLibrariesHaveIdentityWithoutDeletionActions() {
        let libraries = ["Mix.musiclibrary": "personal.musicLibrary", "Shows.tvlibrary": "personal.tvLibrary",
                         "Film.imovielibrary": "personal.videoLibrary", "Film.FCPBUNDLE": "personal.videoLibrary",
                         "Photos.aplibrary": "personal.apertureLibrary"]
        for (name, id) in libraries {
            XCTAssertEqual(Atlas.classify(name: name, parentPath: "/Users/test/Movies", home: "/Users/test"), id)
            XCTAssertEqual(Atlas.classify(name: name, parentPath: "/Users/test/Movies", home: "/Users/test", siblings: nil), id)
            let item = AtlasItem(entryID: id, url: URL(fileURLWithPath: "/Users/test/Movies/" + name),
                                 bytes: 5_000_000_000, lastTouched: .distantPast)
            XCTAssertEqual(item.entry.tier, .yours)
            XCTAssertNil(ItemAction.resolve(item, tools: []))
            XCTAssertNil(ItemAction.suggestion(item, tools: []))
            XCTAssertFalse(ItemAction.canBatch(item))
        }
        XCTAssertNil(Atlas.classify(name: "Film.fcpbundle.backup", parentPath: "/Users/test", home: "/Users/test", siblings: nil))
    }

    func testScanCountsLibraryOnceAndFindsSmallKnownCaches() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = ["Movies/Film.fcpbundle/node_modules/data", "Movies/Film.fcpbundle/clip.mov",
                     ".cache/uv/data", "Library/Caches/pip/data", ".gradle/caches/data"]
        for path in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 42, count: 300_000).write(to: url)
        }
        var scanned: ScanResult?
        for try await event in ScanEngine().scan(root: root, home: root) {
            if case .finished(let result) = event { scanned = result }
        }
        let result = try XCTUnwrap(scanned)
        let libraryPath = root.appendingPathComponent("Movies/Film.fcpbundle").path
        let library = try XCTUnwrap(result.items.first { $0.id == libraryPath })
        XCTAssertEqual(library.entryID, "personal.videoLibrary")
        XCTAssertGreaterThanOrEqual(library.bytes, 600_000)
        XCTAssertFalse(result.items.contains { $0.id.hasPrefix(libraryPath + "/") })
        XCTAssertFalse(result.lensFindings.contains { $0.url.path.hasPrefix(libraryPath) })
        for id in ["py.uvCache", "py.pipCache", "gradle.caches"] {
            XCTAssertEqual(result.items.filter { $0.entryID == id }.count, 1)
        }
    }
}
