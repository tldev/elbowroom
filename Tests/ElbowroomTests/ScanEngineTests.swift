import XCTest
@testable import ElbowroomKit

/// Acceptance pieces that run headless: zero writes, totals, colony
/// classification, pruning, and cancellation leaving no artifacts.
final class ScanEngineTests: XCTestCase {
    var root: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("elbowroom-scan-\(UUID().uuidString)")
        // A little dev world: a repo with node_modules, a cargo target, a cache.
        try fm.createDirectory(at: root.appendingPathComponent("proj/node_modules/lib"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("proj/src"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("proj/.git"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("crate/target/debug"), withIntermediateDirectories: true)
        fm.createFile(atPath: root.appendingPathComponent("crate/Cargo.toml").path, contents: Data("[package]".utf8))
        try fm.createDirectory(at: root.appendingPathComponent("docs"), withIntermediateDirectories: true)

        func write(_ rel: String, _ bytes: Int) throws {
            try Data(count: bytes).write(to: root.appendingPathComponent(rel))
        }
        try write("proj/node_modules/lib/big.js", 300_000)
        try write("proj/node_modules/lib/more.js", 200_000)
        try write("proj/src/main.ts", 10_000)
        try write("crate/target/debug/binary", 400_000)
        try write("crate/src.rs", 5_000)
        try write("docs/notes.txt", 20_000)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
    }

    private func runScan() async throws -> ScanResult {
        let engine = ScanEngine()
        for try await event in engine.scan(root: root, home: root) {
            if case .finished(let result) = event { return result }
        }
        XCTFail("scan never finished")
        throw CancellationError()
    }

    func testFindsColoniesAndCountsBytes() async throws {
        let result = try await runScan()
        let entryIDs = Set(result.items.map(\.entryID))
        XCTAssertTrue(entryIDs.contains("js.nodeModules"))
        XCTAssertTrue(entryIDs.contains("rust.target"))

        // Allocated sizes are block-rounded: at least the content, within one
        // block per file above it.
        let nm = result.items.first { $0.entryID == "js.nodeModules" }!
        XCTAssertGreaterThanOrEqual(nm.bytes, 500_000)
        XCTAssertLessThan(nm.bytes, 520_000)
    }

    /// Rebuildables group under their repo root and take the repo's source
    /// staleness, not their own mtime.
    func testRepoGroupingAndStaleness() async throws {
        let result = try await runScan()
        let nm = result.items.first { $0.entryID == "js.nodeModules" }!
        XCTAssertEqual(nm.projectName, "proj")
        XCTAssertEqual(nm.displayName, "proj · node_modules")
    }

    /// A manifest alone marks a project root: the git-less crate still
    /// groups its target and registers for the project lens.
    func testManifestsMarkProjectsWithoutGit() async throws {
        let result = try await runScan()
        let target = result.items.first { $0.entryID == "rust.target" }!
        XCTAssertEqual(target.projectName, "crate")
        XCTAssertEqual(target.displayName, "crate · target")
        // The walk keys repos by canonical path (/private/var under the test
        // root), so match by suffix rather than respelling the quirk here.
        XCTAssertNotNil(result.repoStaleness.first { $0.key.hasSuffix("/crate") })
    }

    /// Dot directories churn without a human working there: .git activity
    /// never counts as touching the project's sources.
    func testDotDirsDoNotPoisonSourceStaleness() async throws {
        let old = Date(timeIntervalSinceNow: -200 * 86_400)
        for rel in ["proj/src/main.ts", "proj/src", "proj"] {
            try fm.setAttributes([.modificationDate: old], ofItemAtPath: root.appendingPathComponent(rel).path)
        }
        fm.createFile(atPath: root.appendingPathComponent("proj/.git/config").path,
                      contents: Data("[core]".utf8))
        let result = try await runScan()
        let touched = try XCTUnwrap(result.repoStaleness.first { $0.key.hasSuffix("/proj") }?.value)
        XCTAssertEqual(touched.timeIntervalSince1970, old.timeIntervalSince1970, accuracy: 5,
                       "fresh .git churn must not make a sleeping project look awake")
    }

    /// The scan writes nothing.
    func testScanIsReadOnly() async throws {
        let before = try snapshot()
        _ = try await runScan()
        let after = try snapshot()
        XCTAssertEqual(before, after, "scan must not create, delete, or touch files")
    }

    func testCancelLeavesNoArtifacts() async throws {
        let engine = ScanEngine()
        let before = try snapshot()
        let task = Task {
            for try await _ in engine.scan(root: root, home: root) {}
        }
        task.cancel()
        _ = try? await task.value
        let after = try snapshot()
        XCTAssertEqual(before, after)
    }

    /// The tree aggregates parents from children.
    func testTreeAggregation() async throws {
        let result = try await runScan()
        let total = result.root.allocatedBytes
        XCTAssertGreaterThanOrEqual(total, 935_000)
        let childSum = result.root.children.reduce(Int64(0)) { $0 + $1.allocatedBytes }
        XCTAssertLessThanOrEqual(childSum, total)
    }

    private func snapshot() throws -> [String] {
        var lines: [String] = []
        let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey])
        while let obj = enumerator?.nextObject() {
            guard let url = obj as? URL else { continue }
            lines.append(url.path)
        }
        return lines.sorted()
    }
}

final class BrewCellarTests: XCTestCase {
    /// Two kept versions → the older one's bytes aggregate; single-version
    /// formulas contribute nothing (Homebrew pack).
    func testOldVersionsAggregate() {
        let root = ScanNode(url: URL(fileURLWithPath: "/"), isDirectory: true, parent: nil)
        func dir(_ path: String, _ bytes: Int64, parent: ScanNode) -> ScanNode {
            let n = ScanNode(url: URL(fileURLWithPath: path), isDirectory: true, parent: parent)
            n.allocatedBytes = bytes
            parent.children.append(n)
            return n
        }
        let opt = dir("/opt", 0, parent: root)
        let brew = dir("/opt/homebrew", 0, parent: opt)
        let cellar = dir("/opt/homebrew/Cellar", 0, parent: brew)
        let node = dir("/opt/homebrew/Cellar/node", 900_000_000, parent: cellar)
        _ = dir("/opt/homebrew/Cellar/node/22.1.0", 500_000_000, parent: node)
        _ = dir("/opt/homebrew/Cellar/node/21.7.0", 400_000_000, parent: node)
        let jq = dir("/opt/homebrew/Cellar/jq", 5_000_000, parent: cellar)
        _ = dir("/opt/homebrew/Cellar/jq/1.7", 5_000_000, parent: jq)

        let items = ScanEngine.brewOldVersionItems(root: root)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].entryID, "brew.cellarOld")
        XCTAssertEqual(items[0].bytes, 400_000_000, "only the non-newest version counts")
        XCTAssertEqual(items[0].entry.teachFlow, .brewCleanup)
    }

    func testBelowThresholdIgnored() {
        let root = ScanNode(url: URL(fileURLWithPath: "/"), isDirectory: true, parent: nil)
        XCTAssertTrue(ScanEngine.brewOldVersionItems(root: root).isEmpty)
    }
}

final class ScanCacheTests: XCTestCase {
    /// The whole result round-trips: tree, parents, items, disk, dates.
    func testRoundTrip() throws {
        let original = Fixtures.scanResult()
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(ScanResult.self, from: data)

        XCTAssertEqual(restored.root.allocatedBytes, original.root.allocatedBytes)
        XCTAssertEqual(restored.items.count, original.items.count)
        XCTAssertEqual(restored.items.first?.entryID, original.items.first?.entryID)
        XCTAssertEqual(restored.scannedBytes, original.scannedBytes)
        XCTAssertEqual(restored.disk.available, original.disk.available)
        XCTAssertEqual(restored.finishedAt.timeIntervalSince1970,
                       original.finishedAt.timeIntervalSince1970, accuracy: 0.001)
        // Parent wiring rebuilt on decode.
        let users = restored.root.children.first { $0.name == "Users" }
        XCTAssertNotNil(users)
        XCTAssertTrue(users?.parent === restored.root)
        XCTAssertTrue(users?.children.first?.parent === users)
    }
}

final class BrokeredTrashTests: XCTestCase {
    /// When the dated folder cannot be created, items route through the system
    /// trash service, record where they landed, and restore from there.
    func testBrokeredTrashAndRestore() async throws {
        let fm = FileManager.default
        let source = fm.temporaryDirectory.appendingPathComponent("elbowroom-brokered-\(UUID().uuidString)")
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try Data(count: 4096).write(to: source.appendingPathComponent("f.bin"))

        // A home whose .Trash is an existing FILE: folder creation fails, so
        // the executor must fall back to the brokered path.
        let home = fm.temporaryDirectory.appendingPathComponent("elbowroom-home-\(UUID().uuidString)")
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        fm.createFile(atPath: home.appendingPathComponent(".Trash").path, contents: Data())
        defer {
            try? fm.removeItem(at: home)
            try? fm.removeItem(at: source)
        }

        let item = AtlasItem(entryID: "js.nodeModules", url: source, bytes: 4096, lastTouched: nil)
        let outcome = await ReclaimExecutor().run(
            plan: ReclaimPlan(items: [item]), keepInTrash: true, home: home
        ) { _, _ in }

        XCTAssertEqual(outcome.doneCount, 1, "brokered fallback should succeed: \(outcome.skipped)")
        XCTAssertFalse(fm.fileExists(atPath: source.path))
        let receipt = try XCTUnwrap(outcome.receipt)
        XCTAssertNil(receipt.trashFolder)
        let landed = try XCTUnwrap(receipt.items.first?.trashedTo)
        XCTAssertTrue(fm.fileExists(atPath: landed), "item should sit in the real Trash")

        // Restore brings it back from the recorded landing path.
        XCTAssertTrue(ReclaimExecutor().restore(receipt: receipt, home: home))
        XCTAssertTrue(fm.fileExists(atPath: source.appendingPathComponent("f.bin").path))
        XCTAssertFalse(fm.fileExists(atPath: landed))
    }
}

final class ChangeLogTests: XCTestCase {
    func testWeekDeltasNeedTwoSnapshots() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = ChangeLog(directory: dir)
        XCTAssertTrue(log.weekDeltas().isEmpty)
        log.append(ChangeEvent(text: "Reclaimed 5 GB", delta: -5_000_000_000))
        let bars = log.weekBars()
        XCTAssertEqual(bars.count, 12)
        XCTAssertEqual(bars.last!.events.count, 1)
        XCTAssertEqual(bars.last!.shrank, 5_000_000_000)
    }
}
