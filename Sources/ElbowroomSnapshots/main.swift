import AppKit
import SwiftUI
import ElbowroomKit

// Offscreen design-QA renderer: hosts each screen in a real NSWindow
// with fixture data and writes PNGs in both appearances.
// Usage: swift run ElbowroomSnapshots [outputDir]

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Design/snapshots")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

@MainActor
func makeModel(reveal: Bool = false) -> AppModel {
    let model = AppModel()
    model.result = Fixtures.scanResult()
    // Mirror findings the way finishScan does, so Personal rows render.
    model.lensFindings = model.result?.lensFindings ?? []
    // Adopted drive fixture so offload surfaces render (card, Items scope).
    let vol = FileManager.default.temporaryDirectory
        .appendingPathComponent("elbowroom-snapshots", isDirectory: true)
        .appendingPathComponent("Dev Drive", isDirectory: true)
    try? FileManager.default.createDirectory(at: vol, withIntermediateDirectories: true)
    model.stash = try? StashManager(volume: vol)
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

@MainActor
func renderAll() {
let mainSize = NSSize(width: 1080, height: 720)
let onboardingSize = NSSize(width: 720, height: 560)

for dark in [false, true] {
    // Onboarding beats
    for (name, beat) in [("b1-welcome", OnboardingBeat.welcome), ("b2-privacy", .privacy)] {
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
    snap("stash-catalog", size: NSSize(width: 620, height: 540), dark: dark) {
        let m = makeModel()
        // A real (temp-dir) stash so the list renders; groups need no moves.
        let vol = FileManager.default.temporaryDirectory
            .appendingPathComponent("elbowroom-snapshots", isDirectory: true)
            .appendingPathComponent("Dev Drive", isDirectory: true)
        try? FileManager.default.createDirectory(at: vol, withIntermediateDirectories: true)
        m.stash = try? StashManager(volume: vol)
        return StashCatalogView(initiallyExpanded: ["js.nodeModules"]).environment(m)
    }
    snap("stash-setup", size: NSSize(width: 520, height: 500), dark: dark) {
        let vols = Fixtures.externalVolumes()
        return StashSetupSheet(fixtureVolumes: vols, picked: vols.first, speed: Fixtures.speedResult())
            .environment(makeModel())
    }
    snap("teach-docker", size: NSSize(width: 520, height: 420), dark: dark) {
        TeachFlowSheet(flowID: .docker, bytes: 61_400_000_000).environment(makeModel())
    }
    snap("cleanup-simctl", size: NSSize(width: 560, height: 580), dark: dark) {
        CleanupSheet(fixturePlan: Fixtures.cleanupPlan()).environment(makeModel())
    }
    // The tmutil sheet, reassurance note and "up to" estimate visible.
    snap("cleanup-tm-snapshots", size: NSSize(width: 560, height: 580), dark: dark) {
        CleanupSheet(fixturePlan: Fixtures.tmCleanupPlan()).environment(makeModel())
    }
    snap("paywall", size: NSSize(width: 420, height: 560), dark: dark) {
        PaywallSheet(trigger: "free_boundary").environment(makeModel())
    }
}
}

MainActor.assumeIsolated {
    renderAll()
}
print("done")
exit(0)
