import XCTest
@testable import ElbowroomKit

final class SystemAndAppsTests: XCTestCase {

    // MARK: Container parsing

    /// Two containers: an external drive (no System role) that must be
    /// skipped, then the boot container whose role volumes sum.
    func testContainerParsePicksBootContainerAndSumsRoles() throws {
        let plist: [String: Any] = ["Containers": [
            ["Volumes": [
                ["Roles": ["Data"], "CapacityInUse": 400_000_000_000],
            ]],
            ["Volumes": [
                ["Roles": ["System"], "CapacityInUse": 18_400_000_000],
                ["Roles": ["Preboot"], "CapacityInUse": 16_000_000_000],
                ["Roles": ["Recovery"], "CapacityInUse": 2_400_000_000],
                ["Roles": ["VM"], "CapacityInUse": 9_700_000_000],
                ["Roles": ["Update"], "CapacityInUse": 83_000_000],
                ["Roles": ["Data"], "CapacityInUse": 163_000_000_000],
            ]],
        ]]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let info = try XCTUnwrap(ContainerInfo.parse(plistData: data))
        XCTAssertEqual(info.osBytes, 20_800_000_000)
        XCTAssertEqual(info.prebootBytes, 16_000_000_000)
        XCTAssertEqual(info.vmBytes, 9_700_000_000)
        XCTAssertEqual(info.updateBytes, 83_000_000)
    }

    func testContainerParseNilWithoutBootContainer() throws {
        let plist: [String: Any] = ["Containers": [
            ["Volumes": [["Roles": ["Data"], "CapacityInUse": 1]]],
        ]]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        XCTAssertNil(ContainerInfo.parse(plistData: data))
    }

    func testSystemItemsCarryEntryAndTier() {
        let items = SystemSpace.items(container: ContainerInfo(
            osBytes: 20_800_000_000, prebootBytes: 16_000_000_000, vmBytes: 9_700_000_000
        ))
        XCTAssertEqual(items.map(\.entryID), ["sys.os", "sys.updateStaging", "sys.swap"])
        for item in items {
            XCTAssertEqual(item.entry.tier, .system)
        }
        XCTAssertTrue(SystemSpace.items(container: nil).isEmpty)
    }

    func testContainerAllocationIsTheMeasuredGapAcrossAllVolumes() throws {
        let plist: [String: Any] = ["Containers": [[
            "CapacityCeiling": 1000, "CapacityFree": 200,
            "Volumes": [["Roles": ["System"], "CapacityInUse": 100],
                        ["Roles": ["Data"], "CapacityInUse": 600],
                        ["Roles": [], "CapacityInUse": 70]]
        ]]]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let container = try XCTUnwrap(ContainerInfo.parse(plistData: data))
        XCTAssertEqual(container.containerBytes, 30)
        let item = try XCTUnwrap(SystemSpace.items(container: container).first { $0.entryID == "storage.container" })
        XCTAssertEqual(item.bytes, 30)
        XCTAssertNil(ItemAction.resolve(item, tools: []))
    }

    // MARK: Residue matching (conservative by design)

    func testResidueMatcherMatrix() {
        // Exact bundle id and bundle-id extensions match.
        XCTAssertTrue(AppsPass.matches(childName: "com.tinyspeck.slackmacgap", bundleID: "com.tinyspeck.slackmacgap", appName: "Slack", location: "Caches"))
        XCTAssertTrue(AppsPass.matches(childName: "com.tinyspeck.slackmacgap.helper", bundleID: "com.tinyspeck.slackmacgap", appName: "Slack", location: "Caches"))
        // Exact app name matches; near-names never do.
        XCTAssertTrue(AppsPass.matches(childName: "Slack", bundleID: "com.tinyspeck.slackmacgap", appName: "Slack", location: "Application Support"))
        XCTAssertFalse(AppsPass.matches(childName: "Slacker", bundleID: "com.tinyspeck.slackmacgap", appName: "Slack", location: "Application Support"))
        XCTAssertFalse(AppsPass.matches(childName: "com.other.app", bundleID: "com.tinyspeck.slackmacgap", appName: "Slack", location: "Caches"))
        // Group Containers: team-prefixed, so only bundle-id containment
        // counts, and names never do.
        XCTAssertTrue(AppsPass.matches(childName: "T12345.com.tinyspeck.slackmacgap", bundleID: "com.tinyspeck.slackmacgap", appName: "Slack", location: "Group Containers"))
        XCTAssertFalse(AppsPass.matches(childName: "Slack", bundleID: "com.tinyspeck.slackmacgap", appName: "Slack", location: "Group Containers"))
        XCTAssertFalse(AppsPass.matches(childName: "Slack", bundleID: nil, appName: "Slack", location: "Group Containers"))
    }

    // MARK: Uninstall composition

    func testUninstallItemsListBundleFirstThenResidue() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("elbowroom-uninstall-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let fm = FileManager.default
        for dir in ["Library/Application Support/TestApp", "Library/Caches/com.example.testapp", "Library/Caches/com.unrelated.other"] {
            try fm.createDirectory(at: home.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
        let appURL = URL(fileURLWithPath: "/Applications/TestApp.app")

        let items = AppsPass.uninstallItems(
            appURL: appURL, appName: "TestApp", bundleID: "com.example.testapp",
            homePath: home.path, sizer: { _ in 1_000 }
        )

        XCTAssertEqual(items.first?.entryID, "app.bundle")
        XCTAssertEqual(items.first?.url, appURL)
        let residuePaths = items.dropFirst().map(\.url.lastPathComponent).sorted()
        XCTAssertEqual(residuePaths, ["TestApp", "com.example.testapp"])
        for item in items.dropFirst() {
            XCTAssertEqual(item.entryID, "app.residue")
            XCTAssertEqual(item.projectName, "TestApp")
        }
    }

    // MARK: New coverage (Messages, Photos, nested apps)

    func testLibraryCoverageClassifies() {
        let home = "/Users/dev"
        XCTAssertEqual(Atlas.classify(path: home + "/Library/Messages", home: home), "sys.messages")
        XCTAssertEqual(Atlas.classify(path: home + "/Library/Mail", home: home), "sys.mail")
        XCTAssertEqual(Atlas.classify(path: home + "/Library/Application Support/Google/Chrome/OptGuideOnDeviceModel", home: home), "chrome.optGuide")
        XCTAssertEqual(Atlas.classify(path: home + "/.cache/uv", home: home), "py.uvCache")
        XCTAssertNil(Atlas.classify(path: home + "/.local/share/uv", home: home))
        // Photos matches by suffix because the library is renamable.
        XCTAssertEqual(
            Atlas.classify(name: "Photos Library.photoslibrary", parentPath: home + "/Pictures", home: home, siblings: Set<String>?.none),
            "sys.photosLibrary"
        )
    }

    private func makeLibraryWithFusion() -> (library: ScanNodeBuilder, vendor: ScanNodeBuilder, mixed: ScanNodeBuilder) {
        func node(_ path: String, _ bytes: Int64, parent: ScanNodeBuilder?) -> ScanNodeBuilder {
            let n = ScanNodeBuilder(url: URL(fileURLWithPath: path), isDirectory: true, parent: parent)
            n.allocatedBytes = bytes
            parent?.children.append(n)
            return n
        }
        let library = node("/Users/dev/Library", 12_000_000_000, parent: nil)
        let support = node("/Users/dev/Library/Application Support", 12_000_000_000, parent: library)
        let vendor = node("/Users/dev/Library/Application Support/Autodesk", 10_600_000_000, parent: support)
        let deploy = node("/Users/dev/Library/Application Support/Autodesk/webdeploy", 10_300_000_000, parent: vendor)
        _ = node("/Users/dev/Library/Application Support/Autodesk/webdeploy/Autodesk Fusion.app", 10_100_000_000, parent: deploy)
        // A folder with only a small app inside stays unclaimed.
        let mixed = node("/Users/dev/Library/Application Support/BigData", 8_000_000_000, parent: support)
        _ = node("/Users/dev/Library/Application Support/BigData/Tiny.app", 500_000_000, parent: mixed)
        return (library, vendor, mixed)
    }

    func testNestedAppStandsAloneWithoutALauncher() {
        let (library, vendor, mixed) = makeLibraryWithFusion()
        var items: [AtlasItem] = []
        AppsPass.mergeNestedApps(libraryNode: library, into: &items, bundleIDs: [:])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.projectName, "Autodesk Fusion")
        XCTAssertEqual(items.first?.bytes, 10_600_000_000)
        XCTAssertEqual(items.first?.url.path, "/Users/dev/Library/Application Support/Autodesk")
        XCTAssertEqual(vendor.atlasEntryID, "app.bundle")
        XCTAssertNil(mixed.atlasEntryID)
        XCTAssertEqual(items.first.map { $0.displayName }, "Autodesk Fusion")
    }

    /// Fusion's /Applications launcher and its webdeploy tree are one app:
    /// the vendor folder folds into the launcher's item instead of standing
    /// as a second row.
    func testNestedAppMergesIntoLauncherByName() {
        let (library, vendor, _) = makeLibraryWithFusion()
        var items = [AtlasItem(
            entryID: "app.bundle", url: URL(fileURLWithPath: "/Applications/Autodesk Fusion.app"),
            bytes: 5_000_000, lastTouched: nil, projectName: "Autodesk Fusion"
        )]
        AppsPass.mergeNestedApps(libraryNode: library, into: &items, bundleIDs: [:])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.bytes, 10_605_000_000)
        XCTAssertEqual(items.first?.url.path, "/Applications/Autodesk Fusion.app")
        XCTAssertEqual(vendor.atlasEntryID, "app.bundle")
    }

    /// Uninstalling the launcher offers the vendor folder as a residue row.
    func testVendorResidueJoinsUninstall() {
        let (library, vendor, _) = makeLibraryWithFusion()
        let rows = AppsPass.vendorResidueItems(
            appName: "Autodesk Fusion", bundleID: nil,
            appURL: URL(fileURLWithPath: "/Applications/Autodesk Fusion.app"),
            libraryNode: library.snapshot()
        )
        XCTAssertEqual(rows.map(\.url.path), [vendor.path])
        XCTAssertEqual(rows.first?.entryID, "app.residue")
        // The standalone nested case never lists itself twice: the vendor
        // folder is already the bundle row.
        let standalone = AppsPass.vendorResidueItems(
            appName: "Autodesk Fusion", bundleID: nil,
            appURL: vendor.url, libraryNode: library.snapshot()
        )
        XCTAssertTrue(standalone.isEmpty)
    }

    // MARK: Photos

    /// The user's library and the hidden Shared with You store never read
    /// alike: suffix matching splits on location.
    func testPhotosLibrariesSplitByLocation() {
        let home = "/Users/dev"
        XCTAssertEqual(
            Atlas.classify(name: "Photos Library.photoslibrary", parentPath: home + "/Pictures", home: home, siblings: Set<String>?.none),
            "sys.photosLibrary"
        )
        XCTAssertEqual(
            Atlas.classify(name: "Syndication.photoslibrary", parentPath: home + "/Library/Photos/Libraries", home: home, siblings: Set<String>?.none),
            "sys.photosSyndication"
        )
    }

    func testPhotosTrimOffersDerivativesOnly() throws {
        let lib = FileManager.default.temporaryDirectory
            .appendingPathComponent("elbowroom-photos-test-\(UUID().uuidString).photoslibrary", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: lib) }
        try FileManager.default.createDirectory(
            at: lib.appendingPathComponent("resources/derivatives"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: lib.appendingPathComponent("database"), withIntermediateDirectories: true)

        let items = PhotosTrim.planItems(libraryURL: lib, sizer: { _ in 750_000_000 })
        XCTAssertEqual(items.map(\.entryID), ["sys.photosDerivatives"])
        XCTAssertTrue(items.allSatisfy { $0.url.path.hasSuffix("resources/derivatives") })
        // The database is never offered, and empty derivatives drop out.
        XCTAssertFalse(items.contains { $0.url.path.contains("database") })
        XCTAssertTrue(PhotosTrim.planItems(libraryURL: lib, sizer: { _ in 0 }).isEmpty)
    }

    /// The whole library joins the plan only through the explicit gate, and
    /// never arrives pre-checked.
    func testPhotosTrimWholeLibraryGated() throws {
        let lib = FileManager.default.temporaryDirectory
            .appendingPathComponent("elbowroom-photos-whole-\(UUID().uuidString).photoslibrary", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: lib) }
        try FileManager.default.createDirectory(
            at: lib.appendingPathComponent("resources/derivatives"), withIntermediateDirectories: true)

        let closed = PhotosTrim.planItems(libraryURL: lib, sizer: { _ in 1_000 })
        XCTAssertEqual(closed.map(\.entryID), ["sys.photosDerivatives"])

        let open = PhotosTrim.planItems(libraryURL: lib, sizer: { _ in 1_000 }, wholeLibraryEligible: true)
        XCTAssertEqual(open.map(\.entryID), ["sys.photosDerivatives", "sys.photosLibraryWhole"])
        XCTAssertEqual(open.last?.url, lib)

        XCTAssertTrue(Atlas.entry("sys.photosLibraryWhole").planDefaultOff)
        XCTAssertFalse(Atlas.entry("sys.photosDerivatives").planDefaultOff)
    }

    /// The iCloud gate reads the library's own CPL sync state: fresh means
    /// syncing, stale or absent means the library may be the only copy.
    func testPhotosCloudGateReadsCPLFreshness() throws {
        let lib = FileManager.default.temporaryDirectory
            .appendingPathComponent("elbowroom-photos-cpl-\(UUID().uuidString).photoslibrary", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: lib) }

        // Absent: refuse.
        XCTAssertFalse(PhotosTrim.cloudSyncActive(libraryURL: lib))

        let sync = lib.appendingPathComponent("resources/cpl/cloudsync.noindex")
        try FileManager.default.createDirectory(at: sync, withIntermediateDirectories: true)
        XCTAssertTrue(PhotosTrim.cloudSyncActive(libraryURL: lib))

        // Stale (45 days): refuse.
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-45 * 86_400)], ofItemAtPath: sync.path)
        XCTAssertFalse(PhotosTrim.cloudSyncActive(libraryURL: lib))
    }

    // MARK: Messages local trim

    func testMessagesTrimGateReadsCloudKitSwitch() {
        XCTAssertTrue(MessagesTrim.cloudSyncEnabled(read: { _, _ in true }))
        XCTAssertFalse(MessagesTrim.cloudSyncEnabled(read: { _, _ in false }))
        // Absent preference means off, and off means refuse.
        XCTAssertFalse(MessagesTrim.cloudSyncEnabled(read: { _, _ in nil }))
    }

    func testMessagesTrimPlanOffersAttachmentsAndPreviewsOnly() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("elbowroom-messages-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent("Library/Messages/Attachments"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent("Library/Messages/Caches"), withIntermediateDirectories: true)

        let items = MessagesTrim.planItems(homePath: home.path, sizer: { path in
            path.hasSuffix("Attachments") ? 20_500_000_000 : 1_200_000_000
        })
        XCTAssertEqual(items.map(\.entryID), ["sys.messagesAttachments", "sys.messagesPreviews"])
        XCTAssertEqual(items.map(\.bytes), [20_500_000_000, 1_200_000_000])
        // chat.db is never in the plan.
        XCTAssertFalse(items.contains { $0.url.path.contains("chat.db") })

        // Empty pieces drop out instead of offering 0 B rows.
        let empty = MessagesTrim.planItems(homePath: home.path, sizer: { _ in 0 })
        XCTAssertTrue(empty.isEmpty)
    }

    // MARK: Display

    func testAppDisplayNames() {
        let bundle = AtlasItem(
            entryID: "app.bundle", url: URL(fileURLWithPath: "/Applications/Slack.app"),
            bytes: 1, lastTouched: nil, projectName: "Slack"
        )
        XCTAssertEqual(bundle.displayName, "Slack")
        let residue = AtlasItem(
            entryID: "app.residue",
            url: URL(fileURLWithPath: "/Users/dev/Library/Application Support/Slack"),
            bytes: 1, lastTouched: nil, projectName: "Slack"
        )
        XCTAssertEqual(residue.displayName, "Slack · Application Support")
    }

    /// New tiers stay out of every promise: not selectable, not headroom.
    func testNewTiersAreDepthOrderedAndLabeled() {
        XCTAssertLessThan(Tier.managed, Tier.apps)
        XCTAssertLessThan(Tier.apps, Tier.yours)
        XCTAssertLessThan(Tier.yours, Tier.system)
        XCTAssertEqual(Tier.allCases.count, 6)
    }
}

/// Deleting another app's bundle sits behind macOS's App Management switch.
/// Review must open without guessing the grant from a filesystem no-op.
@MainActor
final class AppManagementGateTests: XCTestCase {
    private func makeApp() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("elbowroom-am-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Fake.app", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testUninstallOpensReviewWithoutAPermissionProbe() async throws {
        let app = try makeApp()
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        let model = makeModel()
        let item = AtlasItem(entryID: "app.bundle", url: app, bytes: 1_000, lastTouched: nil)
        await model.openUninstallPlan(item)
        XCTAssertEqual(model.sheet?.id, "plan")
    }
}

/// macOS applies App Management at launch, so the grant sheet's real exit
/// is a relaunch: the pending uninstall must survive it and resume.
@MainActor
final class AppManagementResumeTests: XCTestCase {
    private func makeApp() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("elbowroom-resume-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Fake.app", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testResumeOpensThePlanAfterTheGrantLands() async throws {
        let app = try makeApp()
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        let model = makeModel()
        model.settings.pendingUninstallPath = app.path

        await model.resumePendingUninstall()

        XCTAssertEqual(model.sheet?.id, "plan", "the interrupted uninstall reopens itself")
        XCTAssertNil(model.settings.pendingUninstallPath, "and is claimed exactly once")
    }

    func testResumeRequiresReviewAndNeverExecutesDeletion() async throws {
        let app = try makeApp()
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        let model = makeModel()
        model.settings.pendingUninstallPath = app.path

        await model.resumePendingUninstall()

        XCTAssertEqual(model.sheet?.id, "plan")
        XCTAssertFalse(model.reclaiming)
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.path))
        XCTAssertNil(model.settings.pendingUninstallPath)
    }

    func testResumeDropsAnAppThatIsAlreadyGone() async {
        let model = makeModel()
        model.settings.pendingUninstallPath = "/Applications/NeverExisted.app"

        await model.resumePendingUninstall()

        XCTAssertNil(model.sheet)
        XCTAssertNil(model.settings.pendingUninstallPath)
    }
}

/// Only Cancel drops the pending uninstall. The relaunch tears down the
/// same surfaces on its way out, and that path must keep the resume, or
/// the launch that finally has the grant has nothing to pick up.
@MainActor
final class AppManagementDismissTests: XCTestCase {
    func testRelaunchTeardownKeepsThePendingUninstall() {
        let model = makeModel()
        model.settings.pendingUninstallPath = "/Applications/Fake.app"
        model.prepareForRelaunch()
        XCTAssertEqual(model.settings.pendingUninstallPath, "/Applications/Fake.app",
                       "the relaunch is how the grant lands; its teardown must not drop the resume")
        XCTAssertNil(model.sheet, "and nothing modal is left to defer the quit")
    }

    func testCancelDropsThePendingUninstall() {
        let model = makeModel()
        model.settings.pendingUninstallPath = "/Applications/Fake.app"
        model.cancelAppManagementWait()
        XCTAssertNil(model.settings.pendingUninstallPath)
    }
}
