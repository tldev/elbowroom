import XCTest
@testable import ElbowroomKit

/// Tool-mediated cleanup: the tool's own listing becomes the plan, and
/// every argv shown is the argv run.
final class DevToolsTests: XCTestCase {
    func testRunnerDrainsStderrWhileStdoutIsOpen() async throws {
        let output = try await ToolRunner.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            args: ["-c", "i=0; while [ $i -lt 10000 ]; do printf 'error output filling the pipe\\n' >&2; i=$((i + 1)); done; printf done"],
            timeout: 10
        )
        XCTAssertEqual(output.status, 0)
        XCTAssertEqual(String(data: output.stdout, encoding: .utf8), "done")
        XCTAssertEqual(output.stderr.split(separator: "\n").count, 10000)
    }

    func testRunnerReportsTimeout() async throws {
        do {
            _ = try await ToolRunner.run(executable: URL(fileURLWithPath: "/bin/sleep"),
                                         args: ["10"], timeout: 0.1)
            XCTFail("expected a timeout")
        } catch ToolRunner.RunError.timedOut {
            // The deadline, rather than an arbitrary signal, caused the exit.
        }
    }

    func testRunnerDoesNotLabelEverySignalAsTimeout() async throws {
        let output = try await ToolRunner.run(executable: URL(fileURLWithPath: "/bin/sh"),
                                               args: ["-c", "kill -TERM $$"], timeout: 10)
        XCTAssertNotEqual(output.status, 0)
    }

    func testSimctlPlanFromToolJSON() throws {
        let devicesJSON = """
        {"devices": {
          "com.apple.CoreSimulator.SimRuntime.iOS-18-2": [
            {"udid": "AAA", "name": "iPhone 16", "isAvailable": true, "state": "Shutdown",
             "lastBootedAt": "2026-07-01T10:00:00Z", "dataPathSize": 2000000000},
            {"udid": "BBB", "name": "iPhone 12 mini", "isAvailable": true, "state": "Shutdown",
             "lastBootedAt": "2025-11-01T10:00:00Z", "dataPathSize": 1500000000},
            {"udid": "CCC", "name": "iPad (old)", "isAvailable": false, "state": "Shutdown",
             "dataPathSize": 900000000}
          ]
        }}
        """.data(using: .utf8)!
        let runtimesJSON = """
        {"11111111-1111": {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-17-5",
          "version": "17.5", "build": "21F79", "platformIdentifier": "com.apple.platform.iphonesimulator",
          "state": "Ready", "deletable": true, "sizeBytes": 7800000000},
         "22222222-2222": {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-18-2",
          "version": "18.2", "build": "22C150", "platformIdentifier": "com.apple.platform.iphonesimulator",
          "state": "Ready", "deletable": true, "sizeBytes": 8100000000}}
        """.data(using: .utf8)!

        let (deviceActions, keptCount) = SimCleanup.devicePlan(
            devices: SimctlParser.devices(fromJSON: devicesJSON)
        )
        let deviceIDs = deviceActions.map(\.id)
        XCTAssertTrue(deviceIDs.contains("sim.unavailable"), "unavailable devices roll into one action")
        XCTAssertTrue(deviceIDs.contains("sim.device.BBB"), "stale device gets a row")
        // Freedom: even a recently used device is offered, unchecked.
        XCTAssertTrue(deviceIDs.contains("sim.device.AAA"), "recent devices are offered too")
        XCTAssertFalse(deviceActions.first { $0.id == "sim.device.AAA" }!.checked)
        XCTAssertEqual(keptCount, 0, "only a booted device waits")
        XCTAssertFalse(deviceIDs.contains { $0.hasPrefix("sim.runtime") }, "device sheet never lists runtimes")

        let (runtimeActions, kept) = SimCleanup.runtimePlan(
            runtimes: SimctlParser.runtimes(fromJSON: runtimesJSON)
        )
        let runtimeIDs = runtimeActions.map(\.id)
        XCTAssertTrue(runtimeIDs.contains("sim.runtime.11111111-1111"), "superseded runtime gets a row")
        let current = runtimeActions.first { $0.id == "sim.runtime.current.22222222-2222" }
        XCTAssertNotNil(current, "the current runtime is offered, not locked away")
        XCTAssertFalse(current!.checked)
        XCTAssertNotNil(current!.warning)
        XCTAssertTrue(kept.isEmpty, "the offer replaces the kept note")

        let runtime = runtimeActions.first { $0.id == "sim.runtime.11111111-1111" }!
        XCTAssertEqual(runtime.argv, ["simctl", "runtime", "delete", "11111111-1111"])
        XCTAssertEqual(runtime.bytes, 7_800_000_000)
    }

    /// The sole runtime belongs to the user like everything else: offered
    /// for deletion, never pre-checked, warned with the re-download cost.
    func testSoleRuntimeOfferedUncheckedWithWarning() {
        let runtimesJSON = """
        {"AAA-1": {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-3",
          "version": "26.3.1", "build": "23D60", "platformIdentifier": "com.apple.platform.iphonesimulator",
          "state": "Ready", "deletable": true, "sizeBytes": 8000000000}}
        """.data(using: .utf8)!
        let (actions, kept) = SimCleanup.runtimePlan(runtimes: SimctlParser.runtimes(fromJSON: runtimesJSON))
        XCTAssertEqual(actions.count, 1)
        XCTAssertFalse(actions[0].checked, "the current runtime never pre-checks")
        XCTAssertNotNil(actions[0].warning, "and always carries its warning")
        XCTAssertEqual(actions[0].argv.prefix(3), ["simctl", "runtime", "delete"])
        XCTAssertTrue(kept.isEmpty, "the row replaces the kept note")
    }

    /// Modern simctl keys the human name as `runtimeIdentifier` and fills
    /// `identifier` with the image UUID; labels must never wear the UUID.
    func testRuntimeParserPrefersRuntimeIdentifier() {
        let json = """
        {"6F6BC83E-921A-4A38-A9BB-4E32B77C9F14": {
          "identifier": "6F6BC83E-921A-4A38-A9BB-4E32B77C9F14",
          "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-1",
          "platformIdentifier": "com.apple.platform.iphonesimulator",
          "version": "26.1", "build": "23B85", "state": "Ready",
          "deletable": true, "sizeBytes": 8300000000}}
        """.data(using: .utf8)!
        let runtimes = SimctlParser.runtimes(fromJSON: json)
        XCTAssertEqual(runtimes.count, 1)
        XCTAssertEqual(runtimes[0].identifier, "com.apple.CoreSimulator.SimRuntime.iOS-26-1")
        XCTAssertEqual(SimCleanup.shortPlatform(runtimes[0].identifier), "iOS")
    }

    func testDyldCacheRowUsesSimctlVerb() {
        let row = SimCleanup.dyldCacheRow(bytes: 3_840_000_000)
        XCTAssertEqual(row.argv, ["simctl", "runtime", "dyld_shared_cache", "remove", "--all"])
        XCTAssertFalse(row.checked, "cache removal opts in; the next boot pays a rebuild")
        XCTAssertEqual(row.bytes, 3_840_000_000)
    }

    func testDockerPlanFromDF() {
        XCTAssertEqual(DockerCleanup.parseHumanBytes("1.108GB (34%)"), 1_108_000_000)
        XCTAssertEqual(DockerCleanup.parseHumanBytes("512MB"), 512_000_000)
        XCTAssertEqual(DockerCleanup.parseHumanBytes("0B"), 0)

        let output = """
        {"Active":"2","Reclaimable":"4.2GB (60%)","Size":"7GB","TotalCount":"12","Type":"Images"}
        {"Active":"1","Reclaimable":"800MB (100%)","Size":"800MB","TotalCount":"3","Type":"Containers"}
        {"Active":"0","Reclaimable":"2.1GB","Size":"2.1GB","TotalCount":"9","Type":"Build Cache"}
        {"Active":"2","Reclaimable":"1.5GB (50%)","Size":"3GB","TotalCount":"4","Type":"Local Volumes"}
        """
        let actions = DockerCleanup.plan(dfRows: DockerCleanup.dfRows(fromOutput: output))
        let volumes = actions.first { $0.id == "docker.volumes" }!
        XCTAssertFalse(volumes.checked, "volumes never pre-checked: they can hold user data")
        // Docker 23+ prunes only anonymous volumes without --all; the summary
        // fallback must match what `system df` counts as reclaimable.
        XCTAssertEqual(volumes.argv, ["volume", "prune", "--all", "-f"])
        let images = actions.first { $0.id == "docker.images" }!
        XCTAssertFalse(images.checked, "unused images opt in")
        XCTAssertEqual(images.bytes, 4_200_000_000)
        let containers = actions.first { $0.id == "docker.containers" }!
        XCTAssertTrue(containers.checked)
    }

    func testDockerVolumesListPerVolume() {
        let verbose = """
        {"Images":[],"Containers":[],"BuildCache":[],"Volumes":[
          {"Name":"server_pgdata","Links":"0","Size":"970.1MB"},
          {"Name":"busy_data","Links":"2","Size":"9GB"},
          {"Name":"shelfrat_target","Links":"0","Size":"2.328GB"}]}
        """
        let volumes = DockerCleanup.volumeRows(fromVerboseOutput: verbose)
        XCTAssertEqual(volumes.map(\.name), ["shelfrat_target", "server_pgdata"],
                       "unused volumes only, largest first; in-use volumes never appear")

        let actions = DockerCleanup.plan(dfRows: ["Local Volumes": 3_298_100_000], volumes: volumes)
        let volActions = actions.filter { $0.id.hasPrefix("docker.volume.") }
        XCTAssertEqual(volActions.map(\.argv),
                       [["volume", "rm", "shelfrat_target"], ["volume", "rm", "server_pgdata"]])
        XCTAssertTrue(volActions.allSatisfy { !$0.checked }, "each volume is its own opt-in")
        XCTAssertTrue(volActions.allSatisfy { $0.groupTitle == Copy.dockerVolumes },
                      "volume rows share one tri-state group header")
        XCTAssertNil(actions.first { $0.id == "docker.volumes" },
                     "the summary prune row yields to the per-volume listing")
    }

    func testBrewPreviewParsing() {
        let output = """
        Would remove: /opt/homebrew/Cellar/node/20.1.0 (3,204 files, 51MB)
        ==> This operation would free approximately 1.2GB of disk space.
        """
        let actions = BrewCleanup.plan(previewOutput: output)
        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0].bytes, 1_200_000_000)
        XCTAssertEqual(actions[0].argv, ["cleanup", "--prune=all"])
    }

    func testCommandPreviewIsLiteral() {
        let plan = Fixtures.cleanupPlan()
        XCTAssertTrue(plan.commandPreview.contains("xcrun simctl runtime delete 8E2AE7C0-1A2B"))
        XCTAssertTrue(plan.commandPreview.contains("xcrun simctl delete unavailable"))
        XCTAssertFalse(plan.commandPreview.contains("51F1AA00"), "unchecked rows never enter the command")
    }
}

final class AtlasTests: XCTestCase {
    let home = "/Users/dev"

    func testExactPathClassification() {
        XCTAssertEqual(Atlas.classify(path: "/Users/dev/Library/Developer/Xcode/DerivedData", home: home), "xcode.derivedData")
        XCTAssertEqual(Atlas.classify(path: "/Users/dev/.npm", home: home), "js.npmCache")
        XCTAssertEqual(Atlas.classify(path: "/Users/dev/.cargo/registry", home: home), "rust.cargoRegistry")
        XCTAssertEqual(Atlas.classify(path: "/Users/dev/Library/Containers/com.docker.docker", home: home), "docker.data")
        XCTAssertEqual(Atlas.classify(path: "/Library/Developer/CoreSimulator", home: home), "xcode.simRuntimes")
        XCTAssertNil(Atlas.classify(path: "/Users/dev/Documents", home: home))
        XCTAssertNil(Atlas.classify(path: "/Users/other/.npm", home: home))
    }

    func testNodeModulesRule() {
        let home = "/Users/dev"
        XCTAssertEqual(Atlas.classify(name: "node_modules", parentPath: "/Users/dev/proj", home: home), "js.nodeModules")
        XCTAssertEqual(Atlas.classify(name: "node_modules", parentPath: home, home: home), "js.nodeModules")
        // Nested colonies are not separate finds.
        XCTAssertNil(Atlas.classify(name: "node_modules", parentPath: "/Users/dev/proj/node_modules/lib", home: home))
        XCTAssertNil(Atlas.classify(name: "node_modules", parentPath: "/Users/dev/proj/node_modules", home: home))
        // An app's bundled node_modules is the app, never a colony:
        // outside home, inside any .app bundle, or under ~/Library.
        XCTAssertNil(Atlas.classify(name: "node_modules", parentPath: "/Applications/Slack.app/Contents/Resources/app", home: home))
        XCTAssertNil(Atlas.classify(name: "node_modules", parentPath: "/usr/local/lib", home: home))
        XCTAssertNil(Atlas.classify(name: "node_modules", parentPath: "/Users/dev/Applications/Foo.app/Contents/Resources", home: home))
        XCTAssertNil(Atlas.classify(name: "node_modules", parentPath: "/Users/dev/Library/Application Support/SomeApp", home: home))
        XCTAssertNil(Atlas.classify(name: "node_modules", parentPath: "/Users/devious", home: home))
        // A plain folder that merely contains ".app" in a component is fine.
        XCTAssertEqual(Atlas.classify(name: "node_modules", parentPath: "/Users/dev/my.apps-experiments", home: home), "js.nodeModules")
        // Sibling-set variant applies the same scoping.
        XCTAssertNil(Atlas.classify(name: "node_modules", parentPath: "/Applications/Slack.app/Contents/Resources/app", home: home, siblings: nil))
        XCTAssertEqual(Atlas.classify(name: "node_modules", parentPath: "/Users/dev/proj", home: home, siblings: nil), "js.nodeModules")
    }

    func testTargetNeedsCargoToml() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        XCTAssertNil(Atlas.classify(name: "target", parentPath: tmp.path, home: "/Users/dev"))
        FileManager.default.createFile(atPath: tmp.path + "/Cargo.toml", contents: Data())
        XCTAssertEqual(Atlas.classify(name: "target", parentPath: tmp.path, home: "/Users/dev"), "rust.target")
    }

    func testEveryEntryHasIdentity() {
        for entry in Atlas.entries.values {
            XCTAssertFalse(entry.title.isEmpty, entry.id)
            XCTAssertFalse(entry.identityLine.isEmpty, entry.id)
            XCTAssertFalse(entry.owner.isEmpty, entry.id)
        }
    }

    /// Managed entries either teach or are explainers; they never dangle.
    func testManagedEntriesTeach() {
        for entry in Atlas.entries.values where entry.tier == .managed {
            XCTAssertNotNil(entry.teachFlow, "\(entry.id) is Managed but has no teach flow")
        }
    }
}

final class AskKibiParseTests: XCTestCase {
    func testParseGuessWithTier() {
        let g = AskKibi.parse("This looks like a game engine cache. Tools rebuild it.\nTIER: regenerable")
        XCTAssertNotNil(g)
        XCTAssertEqual(g?.tier, .regenerable)
        XCTAssertTrue(g!.text.contains("game engine cache"))
    }

    func testUnknownTierIsNil() {
        let g = AskKibi.parse("Something here.\nTIER: unknown")
        XCTAssertNotNil(g)
        XCTAssertNil(g?.tier)
    }

    /// The contract clips replies to two sentences.
    func testClipsToTwoSentences() {
        let g = AskKibi.parse("One. Two. Three. Four.\nTIER: yours")
        XCTAssertEqual(g?.text, "One. Two.")
    }

    func testEmptyReplyIsNil() {
        XCTAssertNil(AskKibi.parse("TIER: managed"))
        XCTAssertNil(AskKibi.parse(""))
    }
}

final class UpdatePlannerTests: XCTestCase {
    private func item(_ id: String, entry: String, bytes: Int64, daysStale: Int) -> AtlasItem {
        AtlasItem(
            entryID: entry, url: URL(fileURLWithPath: "/tmp/\(id)"), bytes: bytes,
            lastTouched: Date().addingTimeInterval(-Double(daysStale) * 86_400)
        )
    }

    /// Greedy order regen-stalest-first, then stale rebuildables, stop at
    /// need × 1.15; Managed bytes never count toward the promise.
    func testComposition() {
        let items = [
            item("cache1", entry: "js.npmCache", bytes: 5_000_000_000, daysStale: 100),
            item("cache2", entry: "brew.cache", bytes: 4_000_000_000, daysStale: 10),
            item("dd", entry: "xcode.derivedData", bytes: 20_000_000_000, daysStale: 60),
            item("fresh", entry: "xcode.derivedData", bytes: 30_000_000_000, daysStale: 2),
            item("docker", entry: "docker.data", bytes: 60_000_000_000, daysStale: 5),
        ]
        let plan = UpdatePlanner.compose(need: 22_000_000_000, items: items)
        // Regenerables first, stalest first.
        XCTAssertEqual(plan.reclaimItems.first?.id, "/tmp/cache1")
        // Fresh rebuildables (< 30 days) never picked.
        XCTAssertFalse(plan.reclaimItems.contains { $0.id == "/tmp/fresh" })
        // Managed listed but excluded from the promise.
        XCTAssertFalse(plan.reclaimItems.contains { $0.id == "/tmp/docker" })
        XCTAssertTrue(plan.teachItems.contains { $0.id == "/tmp/docker" })
        XCTAssertTrue(plan.meetsNeed)
        // Stop near need × 1.15: should not have grabbed everything.
        XCTAssertLessThanOrEqual(plan.promisedBytes, Int64(Double(22_000_000_000) * 1.15) + 20_000_000_000)
    }

}

final class TreemapTests: XCTestCase {
    /// Area is strictly proportional to bytes; the layout tiles the rect.
    func testAreasProportionalAndFilling() {
        let rect = CGRect(x: 0, y: 0, width: 900, height: 560)
        let items = [(id: "a", bytes: Int64(60)), (id: "b", bytes: 30), (id: "c", bytes: 10)]
        let placed = Treemap.layout(items: items, in: rect)
        XCTAssertEqual(placed.count, 3)
        let total = rect.width * rect.height
        let areas = Dictionary(uniqueKeysWithValues: placed.map { ($0.id, $0.rect.width * $0.rect.height) })
        XCTAssertEqual(Double(areas["a"]! / total), 0.6, accuracy: 0.01)
        XCTAssertEqual(Double(areas["b"]! / total), 0.3, accuracy: 0.01)
        XCTAssertEqual(Double(areas["a"]! / areas["c"]!), 6, accuracy: 0.1)
        XCTAssertEqual(Double(areas.values.reduce(0, +)), Double(total), accuracy: 1)
        for tile in placed {
            XCTAssertTrue(rect.insetBy(dx: -0.5, dy: -0.5).contains(tile.rect.insetBy(dx: 0.1, dy: 0.1)), "tile escapes: \(tile)")
        }
    }

    /// Tiles never overlap.
    func testNoOverlap() {
        let rect = CGRect(x: 0, y: 0, width: 640, height: 400)
        let items = (0..<12).map { (id: "i\($0)", bytes: Int64(100 - $0 * 7)) }
        let placed = Treemap.layout(items: items, in: rect)
        for i in 0..<placed.count {
            for j in (i + 1)..<placed.count {
                let inter = placed[i].rect.insetBy(dx: 0.01, dy: 0.01)
                    .intersection(placed[j].rect.insetBy(dx: 0.01, dy: 0.01))
                XCTAssertTrue(inter.isNull || inter.width * inter.height < 1,
                              "tiles overlap: \(placed[i].id) x \(placed[j].id)")
            }
        }
    }

    /// Squarified quality: with even-ish inputs, no absurd slivers.
    func testAspectRatiosReasonable() {
        let rect = CGRect(x: 0, y: 0, width: 800, height: 500)
        let items = (0..<8).map { (id: "i\($0)", bytes: Int64(50 + $0 * 10)) }
        for tile in Treemap.layout(items: items, in: rect) {
            let ratio = max(tile.rect.width / tile.rect.height, tile.rect.height / tile.rect.width)
            XCTAssertLessThan(ratio, 4.5, "sliver: \(tile)")
        }
    }

    /// The rest of a big directory folds into one aggregate slice.
    func testSlicesAggregateTail() {
        let root = ScanNodeBuilder(url: URL(fileURLWithPath: "/x"), isDirectory: true, parent: nil)
        for i in 0..<50 {
            let n = ScanNodeBuilder(url: URL(fileURLWithPath: "/x/c\(i)"), isDirectory: true, parent: root)
            n.allocatedBytes = Int64(1000 - i)
            root.children.append(n)
            root.allocatedBytes += n.allocatedBytes
        }
        let slices = Treemap.slices(of: root.snapshot(), limit: 40)
        XCTAssertEqual(slices.count, 41)
        XCTAssertNil(slices.last!.node)
        let sum = slices.reduce(Int64(0)) { $0 + $1.bytes }
        XCTAssertEqual(sum, root.allocatedBytes)
    }
}
