import AppKit
import SwiftUI
import ElbowroomKit

// Offscreen design-QA renderer: hosts each screen in a real NSWindow
// with fixture data and writes PNGs in both appearances.
// Usage: swift run ElbowroomSnapshots [outputDir]

let processStarted = DispatchTime.now().uptimeNanoseconds

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Design/snapshots")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

// Fixture rendering uses its own stores and never sweeps the user's Trash.
let fixtureSuite = "elbowroom-snapshots-" + UUID().uuidString
let fixtureDefaults = UserDefaults(suiteName: fixtureSuite)!
let fixtureDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(fixtureSuite)

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

@MainActor
func makeModel(reveal: Bool = false) -> AppModel {
    let model = AppModel(settings: SettingsStore(defaults: fixtureDefaults),
                         receipts: ReceiptStore(directory: fixtureDirectory),
                         changeLog: ChangeLog(directory: fixtureDirectory), startServices: false,
                         scanCacheURL: fixtureDirectory.appendingPathComponent("scan-cache.json"))
    model.result = Fixtures.scanResult()
    if reveal {
        model.inMain = false
        model.onboarding = .reveal
    } else {
        model.inMain = true
    }
    return model
}

@MainActor
func snap<V: View>(_ name: String, size: NSSize, dark: Bool, @ViewBuilder view: () -> V) {
    let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: [.borderless], backing: .buffered, defer: false
    )
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.colorSpace = .sRGB
    let hosting = NSHostingView(rootView: AnyView(view()).tint(BColor.ink).frame(width: size.width, height: size.height))
    hosting.frame = NSRect(origin: .zero, size: size)
    window.contentView = hosting
    window.orderBack(nil)
    window.displayIfNeeded()

    // Let async layout (tables, tasks) settle.
    for _ in 0..<8 {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    hosting.layoutSubtreeIfNeeded()
    guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
        print("FAILED bitmap: \(name)")
        return
    }
    hosting.cacheDisplay(in: hosting.bounds, to: rep)
    guard let png = rep.representation(using: .png, properties: [:]) else { return }
    let file = outDir.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png")
    try? png.write(to: file)
    print("wrote \(file.lastPathComponent)")
    window.orderOut(nil)
}

// Repeatable, isolated UI timings. These include offscreen AppKit layout, not
// display-server frame presentation; the live application is never touched.
@MainActor
func renderPerformance() {
    let args = CommandLine.arguments
    let index = args.firstIndex(of: "--items")
    let count = max(1, index.flatMap { $0 + 1 < args.count ? Int(args[$0 + 1]) : nil } ?? 10_000)
    var lines: [String] = ["rows: \(count)"]
    func elapsed(_ start: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
    }
    func record(_ name: String, _ ms: Double) {
        let line = String(format: "%@: %.3fms", name, ms)
        lines.append(line)
        print(line)
    }
    func settle(until ready: () -> Bool) {
        let deadline = Date().addingTimeInterval(15)
        repeat { RunLoop.main.run(until: Date().addingTimeInterval(0.001)) }
        while !ready() && Date() < deadline
        precondition(ready(), "UI benchmark did not settle")
    }
    let modelStart = DispatchTime.now().uptimeNanoseconds
    let model = makeModel()
    var fixture = model.result!
    fixture.items = (0..<max(1, count)).map { index in
        AtlasItem(entryID: "js.nodeModules", url: URL(fileURLWithPath: "/fixture/project-\(index)/node_modules"),
                  bytes: Int64(count - index) * 4096, lastTouched: .distantPast, projectName: "project-\(index)")
    }
    fixture.lensFindings = []
    model.result = fixture
    record("model-and-fixture", elapsed(modelStart))

    let projection = LedgerModel()
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    let hosting = NSHostingView(rootView: LedgerView(projection: projection).environment(model)
        .frame(width: 1080, height: 720))
    window.contentView = hosting
    window.orderBack(nil)
    settle { projection.completedQuery != nil }
    hosting.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
    record("process-entry-to-first-fixture-layout", elapsed(processStarted))

    var searchTimes: [Double] = []
    for search in ["project-1", "project-22", "project-333", "node_modules", ""] {
        let start = DispatchTime.now().uptimeNanoseconds
        model.searchText = search
        settle { projection.completedQuery?.search == search }
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        searchTimes.append(elapsed(start))
    }
    searchTimes.sort()
    record("search-to-layout.median", searchTimes[searchTimes.count / 2])
    record("search-to-layout.max", searchTimes.last!)

    func scrollView(_ view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for child in view.subviews {
            if let scroll = scrollView(child) { return scroll }
        }
        return nil
    }
    // Allow SwiftUI to install and lay out its scroll host after projection.
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    if let scroll = scrollView(hosting), let document = scroll.documentView {
        for jumping in [false, true] {
            var times: [Double] = []
        for step in 0..<30 {
            let start = DispatchTime.now().uptimeNanoseconds
            let maxY = max(0, document.bounds.height - scroll.contentView.bounds.height)
            let y = jumping ? maxY * CGFloat(step) / 29 : min(maxY, CGFloat(step) * 60)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
            RunLoop.main.run(until: Date().addingTimeInterval(0.001))
            hosting.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            times.append(elapsed(start))
        }
        times.sort()
        record(jumping ? "scroll-jump.median" : "scroll-step.median", times[times.count / 2])
        record(jumping ? "scroll-jump.p95" : "scroll-step.p95", times[28])
        }
    } else {
        preconditionFailure("No scroll view found for UI benchmark")
    }
    window.orderOut(nil)

    let cache = fixtureDirectory.appendingPathComponent("scan-cache.json")
    ScanCache.save(fixture, rootPath: fixtureDirectory.path, to: cache)
    let cachedStart = DispatchTime.now().uptimeNanoseconds
    let cachedModel = makeModel()
    cachedModel.result = nil
    cachedModel.scanRoot = fixtureDirectory
    var restored = false
    Task { restored = await cachedModel.loadCachedScan() }
    settle { restored }
    record("cached-model-restore", elapsed(cachedStart))
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    lines.append(String(format: "peak RSS: %.1f MiB", Double(usage.ru_maxrss) / 1_048_576))
    try? lines.joined(separator: "\n").write(to: outDir.appendingPathComponent("performance.txt"), atomically: true, encoding: .utf8)
}

@MainActor
func renderAll() {
let mainSize = NSSize(width: 1080, height: 720)
let onboardingSize = NSSize(width: 720, height: 560)

for dark in [false, true] {
    // Onboarding beats
    for (name, beat) in [("b1-welcome", OnboardingBeat.welcome), ("b2-privacy", .privacy), ("b3-trash-first", .trashFirst)] {
        snap(name, size: onboardingSize, dark: dark) {
            let m = makeModel()
            m.inMain = false
            m.onboarding = beat
            return OnboardingView().environment(m)
        }
    }
    // B3 in its three states; probe disabled so no TCC reads, no scan.
    for (name, path) in [("b3-grant", GrantPath.fdaIntro), ("b3-grant-waiting", .fdaWaiting), ("b3-grant-guided", .guided)] {
        snap(name, size: onboardingSize, dark: dark) {
            let m = makeModel()
            m.inMain = false
            m.onboarding = .grant
            m.fdaProbeDisabled = true
            m.grantPath = path
            if path == .guided {
                m.guidedZones = [
                    GuidedZone(zone: .desktop, status: .allowed),
                    GuidedZone(zone: .documents, status: .allowed),
                    GuidedZone(zone: .downloads, status: .asking),
                    GuidedZone(zone: .photos, status: .pending),
                    GuidedZone(zone: .appData, status: .pending),
                ]
            }
            return OnboardingView().environment(m)
        }
    }
    snap("b4-scan", size: onboardingSize, dark: dark) {
        let m = makeModel()
        m.inMain = false
        m.onboarding = .scanning
        m.scanning = true
        m.scanItemsSeen = 481_223
        m.scanBytesSeen = 213_000_000_000
        m.tickerLines = [
            Copy.tickerXcode("24.1 GB"),
            Copy.tickerSimulators("14.2 GB", month: "April"),
            Copy.tickerNodeModules("4.2 GB"),
        ]
        return OnboardingView().environment(m)
    }
    snap("b5-reveal", size: NSSize(width: 720, height: 560), dark: dark) {
        OnboardingView().environment(makeModel(reveal: true))
    }

    // Flat merged rows and localized text wrapping.
    snap("ledger-merged", size: mainSize, dark: dark) {
        LedgerView().environment(makeModel())
    }
    let priorLanguage = Loc.lang
    Loc.lang = "ja"
    snap("ledger-merged-ja", size: mainSize, dark: dark) {
        LedgerView().environment(makeModel())
    }
    Loc.lang = priorLanguage

    // Main views
    snap("ledger-selected", size: mainSize, dark: dark) {
        let m = makeModel()
        m.view = .ledger
        return VStack(spacing: 0) {
            LedgerView(initialSelection: "/Users/dev/Library/Containers/com.docker.docker")
        }.environment(m)
    }
    ///: a strip tier band narrows Items; the chip sits with the batch actions.
    snap("ledger-filtered", size: mainSize, dark: dark) {
        let m = makeModel()
        m.view = .ledger
        m.ledgerTierFilter = .regenerable
        return MainWindow().environment(m)
    }
    // The strip's hover legend card, pinned open via the snapshot hook.
    snap("disk-strip-breakdown", size: NSSize(width: 720, height: 240), dark: dark) {
        VStack(spacing: 0) {
            DiskStrip(pinBreakdown: true)
                .padding(.top, BSpace.m)
                .zIndex(1)
            Spacer()
        }
        .background(BColor.bg)
        .environment(makeModel())
    }
    // Keep the storage reconciliation copy visible in an isolated full-height render.
    snap("den-storage-balance", size: NSSize(width: 1080, height: 1120), dark: dark) {
        let m = makeModel()
        m.view = .den
        return MainWindow().environment(m)
    }
    for (name, tab) in [("den", MainView.den), ("cross-section", .crossSection), ("ledger", .ledger), ("changes", .changes)] {
        snap(name, size: mainSize, dark: dark) {
            let m = makeModel()
            m.view = tab
            if tab == .crossSection, let root = m.result?.root,
               let users = root.children.first(where: { $0.name == "Users" }),
               let dev = users.children.first(where: { $0.name == "dev" }) {
                m.zoomPath = [users, dev]
            }
            return MainWindow().environment(m)
        }
    }

    snap("cleanup-docker-start", size: NSSize(width: 560, height: 580), dark: dark) {
        CleanupSheet(fixturePlan: CleanupPlan(tool: .docker, entryID: "docker.data", actions: [],
                                            blockedReason: Copy.containerAppStart)).environment(makeModel())
    }

    // Docker sheet with the volumes group in its mixed state.
    snap("cleanup-docker", size: NSSize(width: 560, height: 580), dark: dark) {
        CleanupSheet(fixturePlan: CleanupPlan(tool: .docker, entryID: "docker.data", actions: [
            ToolAction(id: "docker.containers", title: Copy.dockerContainers,
                       detail: Copy.dockerContainersDetail, bytes: 800_000_000,
                       argv: ["container", "prune", "-f"], checked: true),
            ToolAction(id: "docker.volume.shelfrat_target", title: "shelfrat_target",
                       detail: nil, bytes: 2_328_000_000,
                       argv: ["volume", "rm", "shelfrat_target"], checked: true,
                       warning: Copy.dockerVolumesWarning, groupTitle: Copy.dockerVolumes),
            ToolAction(id: "docker.volume.server_pgdata", title: "server_pgdata",
                       detail: nil, bytes: 970_100_000,
                       argv: ["volume", "rm", "server_pgdata"], checked: false,
                       warning: Copy.dockerVolumesWarning, groupTitle: Copy.dockerVolumes),
        ])).environment(makeModel())
    }

    // Lens findings as ordinary Items rows, Personal filter on, the
    // Personal band carrying their share of the strip (thumbnails stay
    // soil-blank offscreen; layout and copy are what this frame checks).
    snap("lenses", size: mainSize, dark: dark) {
        let day = 86_400.0
        let m = makeModel()
        m.view = .ledger
        m.ledgerTierFilter = .yours
        m.lensFindings = [
            LensFinding(kind: .mediaHoard, url: URL(fileURLWithPath: "/Users/dev/Pictures/GoPro Trip"),
                        bytes: 12_400_000_000, count: 2_431, count2: 12,
                        date: Date(timeIntervalSinceNow: -700 * day), oldest: Date(timeIntervalSinceNow: -2_100 * day),
                        samples: ["/tmp/none.jpg"]),
            LensFinding(kind: .screenRecordings, url: URL(fileURLWithPath: "/Users/dev/Desktop/Recordings"),
                        bytes: 6_100_000_000, count: 0, count2: 14, date: Date(timeIntervalSinceNow: -30 * day)),
            LensFinding(kind: .installer, url: URL(fileURLWithPath: "/Users/dev/Downloads/Docker-4.30-arm64.dmg"),
                        bytes: 620_000_000, label: "Docker", date: Date(timeIntervalSinceNow: -90 * day)),
            LensFinding(kind: .stratum, url: URL(fileURLWithPath: "/Users/dev/Downloads"), bytes: 1_200_000_000, label: "week", count: 8),
            LensFinding(kind: .stratum, url: URL(fileURLWithPath: "/Users/dev/Downloads"), bytes: 2_800_000_000, label: "month", count: 21),
            LensFinding(kind: .stratum, url: URL(fileURLWithPath: "/Users/dev/Downloads"), bytes: 9_500_000_000, label: "year", count: 130),
            LensFinding(kind: .stratum, url: URL(fileURLWithPath: "/Users/dev/Downloads"), bytes: 14_200_000_000, label: "ancient", count: 260),
            LensFinding(kind: .twin, url: URL(fileURLWithPath: "/Users/dev/Desktop/keynote-final.mov"),
                        bytes: 3_900_000_000, count: 2,
                        counterpart: URL(fileURLWithPath: "/Users/dev/Downloads/keynote-final.mov")),
            LensFinding(kind: .zipShadow, url: URL(fileURLWithPath: "/Users/dev/Downloads/dataset-2024.zip"),
                        bytes: 4_100_000_000, counterpart: URL(fileURLWithPath: "/Users/dev/Downloads/dataset-2024")),
            LensFinding(kind: .ghost, url: URL(fileURLWithPath: "/Users/dev/Relocated Items"),
                        bytes: 8_800_000_000, date: Date(timeIntervalSinceNow: -1_900 * day)),
            LensFinding(kind: .vm, url: URL(fileURLWithPath: "/Users/dev/VMs/Windows 11.utm"),
                        bytes: 62_000_000_000, label: "Windows", date: Date(timeIntervalSinceNow: -420 * day)),
            LensFinding(kind: .weights, url: URL(fileURLWithPath: "/Users/dev/models/llama-3-70b.gguf"),
                        bytes: 39_000_000_000, label: "70B", date: Date(timeIntervalSinceNow: -200 * day)),
            LensFinding(kind: .game, url: URL(fileURLWithPath: "/Users/dev/Library/Application Support/Steam/steamapps/common/Cities_Skylines"),
                        bytes: 41_000_000_000, label: "Cities: Skylines", date: Date(timeIntervalSinceNow: -900 * day)),
        ]
        return MainWindow().environment(m)
    }

    // A lens finding riding the plan wears its face, not the rail's name.
    snap("reclaim-plan-lens", size: NSSize(width: 640, height: 540), dark: dark) {
        let m = makeModel()
        let day = 86_400.0
        m.lensFindings = [
            LensFinding(kind: .mediaHoard, url: URL(fileURLWithPath: "/Users/dev/Pictures/GoPro Trip"),
                        bytes: 11_300_000_000, count: 2_431, count2: 12,
                        date: Date(timeIntervalSinceNow: -700 * day), oldest: Date(timeIntervalSinceNow: -2_100 * day),
                        samples: ["/tmp/none.jpg"]),
        ]
        m.openReclaimPlan(items: [
            AtlasItem(entryID: "lens.found", url: URL(fileURLWithPath: "/Users/dev/Pictures/GoPro Trip"),
                      bytes: 11_300_000_000, lastTouched: Date(timeIntervalSinceNow: -700 * day)),
        ])
        return ReclaimPlanSheet().environment(m)
    }

    // Sheets
    snap("reclaim-plan", size: NSSize(width: 640, height: 540), dark: dark) {
        let m = makeModel()
        m.planItems = m.items.filter { $0.entry.tier == .regenerable || $0.entry.tier == .rebuildable }
        return ReclaimPlanSheet().environment(m)
    }
    snap("teach-docker", size: NSSize(width: 520, height: 420), dark: dark) {
        TeachFlowSheet(flowID: .docker, bytes: 61_400_000_000).environment(makeModel())
    }

    // Uninstall review opens without a speculative permission gate.
    let iMovie = AtlasItem(
        entryID: "app.bundle",
        url: URL(fileURLWithPath: "/Applications/iMovie.app"),
        bytes: 3_100_000_000, lastTouched: nil, projectName: "iMovie"
    )
    snap("uninstall-plan", size: NSSize(width: 640, height: 540), dark: dark) {
        let m = makeModel()
        m.planItems = [iMovie]
        m.planTitle = Copy.uninstallTitle(iMovie.displayName)
        return ReclaimPlanSheet().environment(m)
    }

    snap("uninstall-denied", size: NSSize(width: 640, height: 540), dark: dark) {
        let m = makeModel()
        m.planItems = [iMovie]
        m.planTitle = Copy.uninstallTitle(iMovie.displayName)
        m.reclaimOutcome = Fixtures.deniedUninstall(iMovie)
        return ReclaimPlanSheet().environment(m)
    }

    // The figure-bearing teach sheet: annotated Messages settings capture.
    snap("teach-shared-with-you", size: NSSize(width: 520, height: 641), dark: dark) {
        TeachFlowSheet(flowID: .sharedWithYou, bytes: 2_100_000_000).environment(makeModel())
    }
    snap("cleanup-simctl", size: NSSize(width: 560, height: 580), dark: dark) {
        CleanupSheet(fixturePlan: Fixtures.cleanupPlan()).environment(makeModel())
    }
    // The tmutil sheet, reassurance note and "up to" estimate visible.
    snap("cleanup-tm-snapshots", size: NSSize(width: 560, height: 580), dark: dark) {
        CleanupSheet(fixturePlan: Fixtures.tmCleanupPlan()).environment(makeModel())
    }
    // B3: the PermissionFlow-style drag helper, waiting and granted.
    let helperWaiting = GrantHelperState()
    let helperGranted = GrantHelperState()
    helperGranted.granted = true
    snap("grant-helper", size: NSSize(width: 620, height: 320), dark: dark) {
        HStack(spacing: BSpace.l) {
            GrantHelperCard(state: helperWaiting)
            GrantHelperCard(state: helperGranted)
        }
        .padding(BSpace.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BColor.desk)
    }
}
}

MainActor.assumeIsolated {
    if CommandLine.arguments.contains("--performance") { renderPerformance() }
    else { renderAll() }
}
fixtureDefaults.removePersistentDomain(forName: fixtureSuite)
try? FileManager.default.removeItem(at: fixtureDirectory)
print("done")
exit(0)
