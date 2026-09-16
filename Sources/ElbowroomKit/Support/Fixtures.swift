import Foundation

/// Deterministic fixture data for design snapshots and demos: a plausible
/// 512 GB developer Mac.
public enum Fixtures {
    public static func deniedUninstall(_ item: AtlasItem) -> ReclaimOutcome {
        ReclaimOutcome(reclaimedBytes: 0, doneCount: 0,
                       skipped: [(item.displayName, CocoaError(.fileWriteNoPermission).localizedDescription)],
                       receipt: nil, cancelled: false, accessDeniedAppPaths: [item.url.path])
    }

    public static func scanResult() -> ScanResult {
        let root = ScanNodeBuilder(url: URL(fileURLWithPath: "/"), isDirectory: true, parent: nil)

        func node(_ path: String, _ bytes: Int64, parent: ScanNodeBuilder, touched: TimeInterval = -3 * 86_400) -> ScanNodeBuilder {
            let n = ScanNodeBuilder(url: URL(fileURLWithPath: path), isDirectory: true, parent: parent)
            n.allocatedBytes = bytes
            n.lastTouched = Date().addingTimeInterval(touched)
            parent.children.append(n)
            parent.allocatedBytes += bytes
            return n
        }

        let users = node("/Users", 0, parent: root)
        let home = node("/Users/dev", 0, parent: users)
        let lib = node("/Users/dev/Library", 0, parent: home)
        let dev = node("/Users/dev/Library/Developer", 0, parent: lib)
        let xcode = node("/Users/dev/Library/Developer/Xcode", 0, parent: dev)
        let dd = node("/Users/dev/Library/Developer/Xcode/DerivedData", 0, parent: xcode)
        for (name, bytes) in [("acme-web", Int64(9_800_000_000)), ("elbowroom", 6_300_000_000), ("client-app", 5_100_000_000), ("sandbox", 2_900_000_000)] {
            _ = node("/Users/dev/Library/Developer/Xcode/DerivedData/\(name)-gfxcbb", bytes, parent: dd)
        }
        let sim = node("/Users/dev/Library/Developer/CoreSimulator/Devices", 14_200_000_000, parent: dev, touched: -95 * 86_400)
        let projects = node("/Users/dev/projects", 0, parent: home)
        let acme = node("/Users/dev/projects/acme-web", 0, parent: projects)
        let nm = node("/Users/dev/projects/acme-web/node_modules", 4_200_000_000, parent: acme, touched: -150 * 86_400)
        let client = node("/Users/dev/projects/client-app", 0, parent: projects)
        let nmClient = node("/Users/dev/projects/client-app/node_modules", 2_100_000_000, parent: client, touched: -40 * 86_400)
        let sandbox = node("/Users/dev/projects/sandbox", 0, parent: projects)
        let nmSandbox = node("/Users/dev/projects/sandbox/node_modules", 1_300_000_000, parent: sandbox, touched: -200 * 86_400)
        let rusty = node("/Users/dev/projects/rusty-cli", 0, parent: projects)
        let target = node("/Users/dev/projects/rusty-cli/target", 6_100_000_000, parent: rusty, touched: -47 * 86_400)
        let caches = node("/Users/dev/Library/Caches", 0, parent: lib)
        let spm = node("/Users/dev/Library/Caches/org.swift.swiftpm", 3_100_000_000, parent: caches)
        let npmCache = node("/Users/dev/.npm", 2_400_000_000, parent: home)
        let cargoReg = node("/Users/dev/.cargo/registry", 3_800_000_000, parent: home, touched: -30 * 86_400)
        let docker = node("/Users/dev/Library/Containers/com.docker.docker", 61_400_000_000, parent: lib, touched: -12 * 86_400)
        let backups = node("/Users/dev/Library/Application Support/MobileSync/Backup", 8_100_000_000, parent: lib, touched: -400 * 86_400)
        let brewCache = node("/Users/dev/Library/Caches/Homebrew", 1_900_000_000, parent: caches)
        let spotifyCache = node("/Users/dev/Library/Caches/com.spotify.client", 1_400_000_000, parent: caches)
        let apps = node("/Applications", 38_000_000_000, parent: root)
        let slack = node("/Applications/Slack.app", 1_400_000_000, parent: apps, touched: -9 * 86_400)
        slack.atlasEntryID = "app.bundle"
        _ = node("/Users/dev/Documents", 92_000_000_000, parent: home)
        _ = node("/Users/dev/Pictures", 31_000_000_000, parent: home)
        let mlProject = node("/Users/dev/projects/ml-experiments", 7_800_000_000, parent: projects, touched: -240 * 86_400)
        for i in 0..<9 {
            _ = node("/Users/dev/projects/side-\(i)", Int64(400_000_000 + i * 130_000_000), parent: projects, touched: -Double(200 + i * 30) * 86_400)
        }

        func item(_ entry: String, _ n: ScanNodeBuilder, project: String? = nil) -> AtlasItem {
            let i = AtlasItem(entryID: entry, url: n.url, bytes: n.allocatedBytes, lastTouched: n.lastTouched, projectName: project)
            n.atlasEntryID = entry
            return i
        }

        var items = [
            item("xcode.derivedData", dd),
            item("xcode.simDevices", sim),
            item("js.nodeModules", nm, project: "acme-web"),
            item("js.nodeModules", nmClient, project: "client-app"),
            item("js.nodeModules", nmSandbox, project: "sandbox"),
            item("rust.target", target, project: "rusty-cli"),
            item("xcode.spmCache", spm),
            item("js.npmCache", npmCache),
            item("rust.cargoRegistry", cargoReg),
            item("docker.data", docker),
            item("sys.iosBackups", backups),
            item("brew.cache", brewCache),
            item("sys.appCache", spotifyCache),
        ]
        dd.allocatedBytes = 24_100_000_000
        items[0].bytes = 24_100_000_000
        // Snapshots as an ordinary item: bytes are the purgeable
        // measurement, path is the volume whose snapshots they are.
        items.append(AtlasItem(
            entryID: "sys.snapshots",
            url: URL(fileURLWithPath: "/System/Volumes/Data"),
            bytes: 13_500_000_000, lastTouched: nil
        ))
        // One app with its Library residue counted beside it, and the
        // container's sibling volumes as System rows.
        items.append(AtlasItem(
            entryID: "app.bundle", url: slack.url, bytes: 2_900_000_000,
            lastTouched: slack.lastTouched, projectName: "Slack"
        ))
        items.append(contentsOf: SystemSpace.items(container: ContainerInfo(
            osBytes: 20_800_000_000, prebootBytes: 16_000_000_000, vmBytes: 9_700_000_000
        )))
        items.append(contentsOf: [
            AtlasItem(entryID: "storage.appCache", url: URL(fileURLWithPath: "/Users/dev/Library/Caches/com.tinyspeck.slackmacgap"),
                      bytes: 200_000_000, lastTouched: Date(), projectName: "Slack"),
            AtlasItem(entryID: "storage.toolPackages", url: URL(fileURLWithPath: "/opt/homebrew"),
                      bytes: 5_600_000_000, lastTouched: nil),
            AtlasItem(entryID: "storage.search", url: URL(fileURLWithPath: "/Users/dev/Library/Metadata/CoreSpotlight"),
                      bytes: 1_900_000_000, lastTouched: nil),
            AtlasItem(entryID: "storage.appCache", url: URL(fileURLWithPath: "/Users/dev/Library/Application Support/Slack/Cache"),
                      bytes: 900_000_000, lastTouched: Date(), projectName: "Slack"),
            AtlasItem(entryID: "ml.ollama", url: URL(fileURLWithPath: "/Users/dev/.ollama/models"),
                      bytes: 4_600_000_000, lastTouched: nil),
        ])
        if let slackIndex = items.firstIndex(where: { $0.id == slack.path }) {
            items[slackIndex].bytes -= 1_100_000_000
        }
        items.sort { $0.bytes > $1.bytes }

        // Roll subtree sizes up: parents report the sum of their children,
        // exactly as the scan engine does while walking.
        @discardableResult
        func rollUp(_ n: ScanNodeBuilder) -> Int64 {
            guard !n.children.isEmpty else { return n.allocatedBytes }
            let sum = n.children.reduce(Int64(0)) { $0 + rollUp($1) }
            n.allocatedBytes = max(n.allocatedBytes, sum)
            return n.allocatedBytes
        }
        rollUp(root)
        root.sortChildren()

        let disk = DiskSnapshot(
            volumeName: "Macintosh HD",
            totalCapacity: 512_000_000_000,
            available: 61_300_000_000,
            availableForImportant: 74_800_000_000,
            snapshotCount: 3
        )
        let result = ScanResult(
            root: root.snapshot(),
            items: items,
            repoStaleness: [:],
            deniedPaths: [],
            disk: disk,
            duration: 74,
            insights: [],
            scannedBytes: 418_000_000_000,
            classifiedBytes: 128_000_000_000,
            lensFindings: [
                LensFinding(kind: .project, url: mlProject.url, bytes: mlProject.allocatedBytes,
                            label: "Git", date: mlProject.lastTouched),
            ]
        )
        return result
    }



    /// Fixture plan for tmutil sheet: two snapshots, a network
    /// destination to reassure about, and the "up to" estimate.
    public static func tmCleanupPlan() -> CleanupPlan {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd-HHmmss"
        df.locale = Locale(identifier: "en_US_POSIX")
        let tokens = [
            df.string(from: Date().addingTimeInterval(-2 * 86_400 - 3_600)),
            df.string(from: Date().addingTimeInterval(-86_400 - 3_000)),
        ]
        let (actions, notes, estimate) = TMSnapshotCleanup.plan(
            tokens: tokens,
            destination: TMSnapshotParser.Destination(name: "goose-nas", isNetwork: true),
            purgeableBytes: 13_500_000_000,
            osUpdateCount: 2
        )
        return CleanupPlan(tool: .tmutil, entryID: "sys.snapshots", actions: actions,
                           notes: notes, estimatedBytes: estimate)
    }

    /// Fixture plan for cleanup sheet snapshots.
    public static func cleanupPlan() -> CleanupPlan {
        CleanupPlan(tool: .simctl, entryID: "xcode.simRuntimes", actions: [
            ToolAction(
                id: "sim.runtime.old", title: "iOS 17.5 (21F79)",
                detail: Copy.simSuperseded("iOS 18.2"), bytes: 7_800_000_000,
                argv: ["simctl", "runtime", "delete", "8E2AE7C0-1A2B"], checked: true
            ),
            ToolAction(
                id: "sim.unavailable", title: Copy.simUnavailable(4),
                detail: Copy.simUnavailableDetail, bytes: 3_400_000_000,
                argv: ["simctl", "delete", "unavailable"], checked: true
            ),
            ToolAction(
                id: "sim.device.mini", title: "iPhone 12 mini",
                detail: RelativeDate.staleness(Date().addingTimeInterval(-190 * 86_400)),
                bytes: 1_900_000_000,
                argv: ["simctl", "delete", "51F1AA00-9C3D"], checked: false
            ),
            ToolAction(
                id: "sim.runtime.current", title: "iOS 18.2 (22C150)",
                detail: Copy.runtimeCurrentDetail("8.1 GB"), bytes: 8_100_000_000,
                argv: ["simctl", "runtime", "delete", "9F3BB1D2-4C5E"], checked: false,
                warning: Copy.runtimeCurrentWarning
            ),
        ])
    }
}
