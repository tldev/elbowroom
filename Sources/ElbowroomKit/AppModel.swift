import Foundation
import SwiftUI
import AppKit
import Observation

public enum OnboardingBeat: Int, Comparable {
    case welcome, privacy, grant, scanning, reveal
    public static func < (l: OnboardingBeat, r: OnboardingBeat) -> Bool { l.rawValue < r.rawValue }
}

/// B3 states: Full Disk Access first, guided folder consents as fallback.
public enum GrantPath: Equatable { case fdaIntro, fdaWaiting, guided }

public enum MainView: String, CaseIterable, Identifiable {
    case den, crossSection, ledger, changes
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .den: Copy.viewDen
        case .crossSection: Copy.viewCrossSection
        case .ledger: Copy.viewLedger
        case .changes: Copy.viewChanges
        }
    }
}

public struct Toast: Identifiable, Equatable {
    public let id = UUID()
    public let text: String
}

public enum ActiveSheet: Identifiable {
    case reclaimPlan(title: String)
    case stashSetup
    case stashCatalog
    case teach(TeachFlowID, bytes: Int64)
    case cleanup(entryID: String)
    case paywall(trigger: String)
    case reconcile(StashEntry)
    case updatePlanner
    case askKibi(name: String, path: String, bytes: Int64, children: [String])
    public var id: String {
        switch self {
        case .reclaimPlan: "plan"
        case .stashSetup: "stashSetup"
        case .stashCatalog: "stashCatalog"
        case .teach(let id, _): "teach-\(id.rawValue)"
        case .cleanup(let entryID): "cleanup-\(entryID)"
        case .paywall: "paywall"
        case .reconcile(let e): "reconcile-\(e.id)"
        case .updatePlanner: "planner"
        case .askKibi(_, let path, _, _): "kibi-\(path)"
        }
    }
}

@Observable
@MainActor
public final class AppModel {
    // MARK: Stores
    public let settings = SettingsStore.shared
    public let pro = ProStore()
    public let receipts = ReceiptStore()
    public let changeLog = ChangeLog()
    public let guardian = Guardian()
    public let purchases: PurchaseManager

    // MARK: Onboarding
    public var onboarding: OnboardingBeat = .welcome
    public var grantPath: GrantPath = .fdaIntro
    /// Last probe result; refreshed on B3 entry, app activation, scan end.
    public var fdaGranted = false
    /// Snapshot/test hook: render grant states without touching TCC or
    /// starting a real scan.
    public var fdaProbeDisabled = false
    public var guidedZones: [GuidedZone] = []
    private var fdaPollTask: Task<Void, Never>?
    private var guidedTask: Task<Void, Never>?
    public var isOnboarded: Bool { settings.onboardingComplete }
    /// The window swaps from the onboarding flow to the main app on the first
    /// Reveal door click, and starts there on every later launch.
    public var inMain = false

    public func enterMain(_ target: MainView = .den) {
        inMain = true
        view = target
    }

    // MARK: Scan
    public var scanRoot: URL?
    public var scanning = false
    public var scanProgressPath = ""
    public var scanItemsSeen = 0
    public var scanBytesSeen: Int64 = 0
    public var scanStartedAt: Date?
    public var slowDisk = false
    public var result: ScanResult?
    private var scanTask: Task<Void, Never>?

    // Ticker: min 900 ms dwell, max 5 visible, queued.
    public var tickerLines: [String] = []
    private var tickerQueue: [String] = []
    private var tickerDrainTask: Task<Void, Never>?

    // MARK: Main window
    public var view: MainView = .den
    public var searchText = ""
    /// Items narrowed to one tier; set by the Disk Strip's tier bands,
    /// cleared from the chip beside the Ledger's batch actions.
    public var ledgerTierFilter: Tier?
    public var sheet: ActiveSheet? {
        // Interactive dismissal (Esc, click-out) abandons the whole flow;
        // a stale stack must never resurface under a later sheet.
        didSet { if sheet == nil { sheetStack = [] } }
    }
    /// Sheets the current one slid over; closing returns here, so a flow
    /// like lenses → plan never dead-ends.
    public private(set) var sheetStack: [ActiveSheet] = []
    public var toast: Toast?
    public var zoomPath: [ScanNode] = []

    // MARK: Tray
    public var trayItems: [AtlasItem] = []
    public var trayMode: Tier? // nil until first add; batch rules by tier

    // MARK: Reclaim run
    public var reclaiming = false
    public var reclaimStatuses: [ReclaimItemStatus] = []
    public var reclaimOutcome: ReclaimOutcome?
    public var planKeepInTrash = true
    public var planItems: [AtlasItem] = []
    public var planTitle = Copy.planTitle
    private var reclaimTask: Task<Void, Never>?

    // MARK: Stash
    public var stash: StashManager? {
        didSet { guardian.stash = stash }
    }
    public var stashBusy: Set<String> = [] // AtlasItem ids mid-move

    // MARK: Tool-mediated cleanup
    public var toolsAvailable: Set<DevTool> = []

    // MARK: Update planner
    public var updatePlan: UpdatePlan?

    // MARK: Live deltas
    private var watcher: FSWatcher?
    public var changesPending = false
    private var quietRescanTask: Task<Void, Never>?

    public init() {
        purchases = PurchaseManager(pro: pro)
        restoreStashIfKnown()
        refreshToolCapabilities()
        receipts.sweepExpired()
        purchases.start()
        if isOnboarded {
            onboarding = .reveal
            inMain = true
        } else if settings.grantBookmark != nil {
            // The grant survives a relaunch mid-onboarding (cancel and
            // restarts keep the grant intact); resume straight at the scan.
            onboarding = .scanning
        } else if settings.fdaRequested {
            // Relaunched mid-Grant: macOS applies Full Disk Access only after
            // quit-and-reopen. Land on B3 waiting; the first probe advances
            // it, so the round trip ends in the dig.
            onboarding = .grant
            grantPath = .fdaWaiting
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshFDAStatus() }
        }
    }

    /// After a decline, proactive paywalls stay quiet for 14 days.
    /// Feature taps the user makes personally still open it.
    public var paywallCoolingDown: Bool {
        guard let declined = settings.paywallDeclinedAt else { return false }
        return Date().timeIntervalSince(declined) < 14 * 86_400
    }

    // MARK: - Grant

    /// B3 entry: refresh the probe and, after a mid-grant relaunch, resume
    /// the wait so the first probe advances straight into the scan.
    public func grantBeatAppeared() {
        refreshFDAStatus()
        startFDAPollIfWaiting()
    }

    public func refreshFDAStatus() {
        guard !fdaProbeDisabled else { return }
        Task.detached(priority: .utility) {
            let granted = DiskAccess.fdaGranted()
            await MainActor.run { self.fdaGranted = granted }
        }
    }

    /// Primary path: deep-link to the Full Disk Access pane, float the drag
    /// helper beside it, and watch for the switch.
    public func beginFDAWait() {
        settings.fdaRequested = true
        grantPath = .fdaWaiting
        DiskAccess.openFullDiskSettings()
        GrantHelperPanel.shared.show()
        Analytics.shared.log("fda_settings_opened")
        startFDAPollIfWaiting()
    }

    private func startFDAPollIfWaiting() {
        guard grantPath == .fdaWaiting, fdaPollTask == nil, !fdaProbeDisabled else { return }
        fdaPollTask = Task {
            while !Task.isCancelled {
                let granted = await Task.detached(priority: .utility) { DiskAccess.fdaGranted() }.value
                guard !Task.isCancelled else { return }
                if granted {
                    self.fdaGranted = true
                    self.acceptGrant(url: URL(fileURLWithPath: "/"))
                    return
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    /// Already-granted B3 state: one click, no ambush.
    public func startScanFromGrant() {
        acceptGrant(url: URL(fileURLWithPath: "/"))
    }

    /// The B5 partial-permission chip re-opens B3 in-window.
    public func expandAccessFromReveal() {
        grantPath = .fdaIntro
        onboarding = .grant
    }

    public func relaunchApp() {
        DiskAccess.relaunch()
    }

    /// Fallback: scan the home folder, but raise every consent dialog as a
    /// paced checklist here, before the dig, never over it (the scan promises
    /// "never modal mid-scan"; this keeps the OS honest too).
    public func startGuidedHomeGrant() {
        guard guidedTask == nil else { return }
        fdaPollTask?.cancel()
        fdaPollTask = nil
        settings.fdaRequested = false
        GrantHelperPanel.shared.hide()
        let home = FileManager.default.homeDirectoryForCurrentUser
        let zones = PromptZone.present(home: home)
        guidedZones = zones.map { GuidedZone(zone: $0) }
        grantPath = .guided
        Analytics.shared.log("grant_guided_started", ["zones": String(zones.count)])
        guidedTask = Task {
            for (i, zone) in zones.enumerated() {
                guard !Task.isCancelled else { return }
                self.guidedZones[i].status = .asking
                let outcome = await Task.detached(priority: .userInitiated) { zone.touch(home: home) }.value
                guard !Task.isCancelled else { return }
                self.guidedZones[i].status = outcome == .allowed ? .allowed : .denied
                Analytics.shared.log("grant_zone_result", ["zone": zone.rawValue, "allowed": String(outcome == .allowed)])
            }
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            self.acceptGrant(url: home)
        }
    }

    private func acceptGrant(url: URL) {
        fdaPollTask?.cancel()
        fdaPollTask = nil
        guidedTask?.cancel()
        guidedTask = nil
        GrantHelperPanel.shared.hide()
        settings.fdaRequested = false
        scanRoot = url
        settings.grantIsFullDisk = url.path == "/"
        if let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            settings.grantBookmark = bookmark
        }
        Analytics.shared.log("grant_result", ["outcome": "granted", "fullDisk": String(settings.grantIsFullDisk)])
        SoundPlayer.shared.play(.whoomp)
        onboarding = .scanning
        startScan()
    }

    public func restoreGrant() -> URL? {
        guard let bookmark = settings.grantBookmark else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark, options: [.withSecurityScope],
            relativeTo: nil, bookmarkDataIsStale: &stale
        ) else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        return url
    }

    // MARK: - Scan lifecycle

    public func startScan() {
        guard !scanning else { return }
        guard let root = scanRoot ?? restoreGrant() else { return }
        scanRoot = root
        scanning = true
        scanStartedAt = Date()
        slowDisk = false
        scanItemsSeen = 0
        scanBytesSeen = 0
        tickerLines = []
        tickerQueue = []
        startTickerDrain()

        let engine = ScanEngine()
        scanTask = Task {
            do {
                for try await event in engine.scan(root: root) {
                    switch event {
                    case .progress(let items, let bytes, let path):
                        self.scanItemsSeen = items
                        self.scanBytesSeen = bytes
                        self.scanProgressPath = path
                        if let started = self.scanStartedAt, Date().timeIntervalSince(started) > 180 {
                            if !self.slowDisk {
                                self.slowDisk = true
                                self.enqueueTicker(Copy.tickerSlowDisk)
                            }
                        }
                    case .ticker(let line):
                        self.enqueueTicker(line)
                    case .finished(let result):
                        self.finishScan(result)
                    }
                }
            } catch {
                self.scanning = false
            }
        }
    }

    public func cancelScan() {
        scanTask?.cancel()
        scanning = false
        if onboarding == .scanning {
            // B4: returns to B3 with the grant intact. The intro state
            // shows "Start the scan" rather than re-scanning by surprise.
            grantPath = .fdaIntro
            onboarding = .grant
            refreshFDAStatus()
        }
    }

    private func finishScan(_ result: ScanResult) {
        markStashedItems(in: result)
        self.result = result
        scanning = false
        changesPending = false
        refreshFDAStatus() // the B5 chip hides when FDA already covers everything
        startWatching()
        if let rootPath = scanRoot?.standardizedFileURL.path {
            Task.detached(priority: .utility) {
                ScanCache.save(result, rootPath: rootPath)
            }
        }
        changeLog.recordScan(items: result.items, disk: result.disk)
        // The scan carried the lens post-pass; mirror its findings.
        lensFindings = result.lensFindings
        refreshDockerBytes()
        autoThinSnapshotsIfNeeded()
        Analytics.shared.log("scan_complete", [
            "duration": String(Int(result.duration)),
            "coverage": String(Int(result.coverage * 100)),
        ])
        if onboarding == .scanning {
            onboarding = .reveal
            settings.onboardingComplete = true
            Analytics.shared.log("reveal_shown", ["headroom": String(headroomBytes), "mode": revealMode])
            if settings.connectionMeasuredAt == nil {
                Task {
                    if let bps = await SpeedTest.sampleConnection() {
                        self.settings.connectionBytesPerSecond = bps
                        self.settings.connectionMeasuredAt = Date()
                    }
                }
            }
        }
    }

    private func markStashedItems(in result: ScanResult) {
        guard let stash else { return }
        let stashedPaths = Set(stash.manifest.entries
            .filter { $0.status == .done || $0.status == .doneDirty || $0.status == .committed }
            .map(\.sourcePath))
        for i in result.items.indices where stashedPaths.contains(result.items[i].url.path) {
            result.items[i].isStashed = true
        }
    }

    // MARK: - Ticker plumbing

    private func enqueueTicker(_ line: String) {
        tickerQueue.append(line)
    }

    private func startTickerDrain() {
        tickerDrainTask?.cancel()
        tickerDrainTask = Task {
            while !Task.isCancelled {
                if !self.tickerQueue.isEmpty {
                    let line = self.tickerQueue.removeFirst()
                    withAnimation(BMotion.light) {
                        self.tickerLines.append(line)
                        if self.tickerLines.count > 5 { self.tickerLines.removeFirst() }
                    }
                }
                try? await Task.sleep(nanoseconds: 900_000_000)
                if self.tickerQueue.isEmpty && !self.scanning { break }
            }
        }
    }

    // MARK: - Derived numbers

    /// One inventory: lens findings are ordinary items, merged
    /// computed-side so a rescan can never orphan them. They carry the
    /// Personal band's share of the Disk Strip like any other tier.
    public var items: [AtlasItem] { (result?.items ?? []) + lensItems }

    /// Derived once per findings change, not on every `items` access: the
    /// inventory is read many times per render.
    private var lensItems: [AtlasItem] = []

    private func rebuildLensItems() {
        lensItems = lensFindings.filter { $0.kind != .stratum }.map {
            AtlasItem(entryID: "lens.found", url: $0.url, bytes: $0.bytes, lastTouched: $0.date)
        }
    }

    /// Solid headroom: bytes Elbowroom can move to the Trash itself.
    public var solidReclaimable: Int64 {
        items.filter { !$0.isStashed && ($0.entry.tier == .regenerable || $0.entry.tier == .rebuildable) }
            .reduce(0) { $0 + $1.bytes }
    }

    /// Teach-flow bytes count toward headroom with a hollow badge.
    public var teachBytes: Int64 {
        items.filter { $0.entry.tier == .managed && $0.entry.teachFlow != nil }
            .reduce(0) { $0 + $1.bytes }
    }

    public var headroomBytes: Int64 { solidReclaimable + teachBytes }

    public var isCrisis: Bool { (result?.disk.available ?? .max) < 10 * 1_000_000_000 }
    public var isModest: Bool { solidReclaimable < 3 * 1_000_000_000 }
    public var revealMode: String { isCrisis ? "crisis" : (isModest ? "modest" : "default") }

    /// Tier proportions for the Disk Strip.
    public var stripSegments: [(tier: Tier?, bytes: Int64)] {
        guard let result else { return [] }
        var byTier: [Tier: Int64] = [:]
        for item in items where !item.isStashed {
            byTier[item.entry.tier, default: 0] += item.bytes
        }
        let classified = byTier.values.reduce(0, +)
        let other = max(0, result.disk.used - classified)
        var segments: [(Tier?, Int64)] = Tier.allCases.compactMap { tier in
            guard let b = byTier[tier], b > 0 else { return nil }
            return (tier, b)
        }
        segments.append((nil, other))
        return segments.map { (tier: $0.0, bytes: $0.1) }
    }

    // MARK: - Lenses

    /// Observable mirror of `result.lensFindings` (class mutation is
    /// invisible to Observation); finishScan and loadCachedScan sync it,
    /// prunes write back through syncLensFindings().
    public var lensFindings: [LensFinding] = [] {
        didSet { rebuildLensItems() }
    }

    func syncLensFindings() {
        result?.lensFindings = lensFindings
    }

    public var lensIdentifiedBytes: Int64 {
        // Strata describe Downloads' age layers, not new space on top of it.
        lensFindings.filter { $0.kind != .stratum }.reduce(0) { $0 + $1.bytes }
    }

    public var everythingElseBytes: Int64 {
        stripSegments.first { $0.tier == nil }?.bytes ?? 0
    }

    public func pushSheet(_ next: ActiveSheet) {
        if let current = sheet { sheetStack.append(current) }
        sheet = next
    }

    public func closeSheet() {
        sheet = sheetStack.popLast()
        if sheet == nil && !lensFindings.isEmpty {
            // Reclaimed or hand-deleted findings leave the inventory the
            // moment the window is visible again; no row for something gone.
            lensFindings.removeAll { !FileManager.default.fileExists(atPath: $0.url.path) }
            syncLensFindings()
        }
    }

    /// The Items row for a container engine shows what its tool can clear
    /// right now, not the virtual disk's total: the row and its sheet agree.
    public func refreshDockerBytes() {
        guard ToolRunner.isAvailable(.docker) else { return }
        Task { [weak self] in
            guard let out = try? await ToolRunner.run(.docker, ["system", "df", "--format", "{{json .}}"], timeout: 15),
                  out.status == 0 else { return }
            let clearable = DockerCleanup.dfRows(fromOutput: String(data: out.stdout, encoding: .utf8) ?? "")
                .values.reduce(0, +)
            await MainActor.run {
                guard let self,
                      let index = self.result?.items.firstIndex(where: { $0.entryID == "docker.data" || $0.entryID == "orbstack.data" })
                else { return }
                self.result?.items[index].bytes = clearable
                self.result = self.result  // class mutation; poke observation
            }
        }
    }

    /// The gray band's verb is navigation only: Items filtered to Personal,
    /// where the scan already put the findings.
    public func openLenses() {
        view = .ledger
        ledgerTierFilter = .yours
    }

    /// Findings ride the ordinary trash-first Reclaim rails as items of the
    /// one lens entry; the plan sheet stays the approval step, one checkable
    /// row per finding.
    public func reclaimFindings(_ findings: [LensFinding]) {
        guard !findings.isEmpty else { return }
        openReclaimPlan(items: findings.map {
            AtlasItem(entryID: "lens.found", url: $0.url, bytes: $0.bytes, lastTouched: $0.date)
        })
    }

    public func reclaimFinding(_ finding: LensFinding) {
        reclaimFindings([finding])
    }

    /// A tier band in the Disk Strip drills into Items filtered to that tier;
    /// clicking the active band again clears the filter.
    public func focusLedger(tier: Tier) {
        if view == .ledger && ledgerTierFilter == tier {
            ledgerTierFilter = nil
        } else {
            ledgerTierFilter = tier
            view = .ledger
        }
    }

    // MARK: - Tray

    public func canSelect(_ item: AtlasItem) -> Bool {
        switch item.entry.tier {
        case .regenerable, .rebuildable: return !item.isStashed
        case .managed: return false
        // Yours stays untouchable except lens-named items: each was
        // individually witnessed, so the tray may take it.
        case .yours: return item.entryID == "lens.found"
        }
    }

    public func toggleTray(_ item: AtlasItem) {
        if let i = trayItems.firstIndex(of: item) {
            trayItems.remove(at: i)
            return
        }
        guard canSelect(item) else {
            if let flow = item.entry.teachFlow {
                sheet = .teach(flow, bytes: item.bytes)
            }
            return
        }
        // No confirmation here: checking a box is reversible, and the
        // plan sheet carries each Rebuildable's computed rebuild-time line.
        trayItems.append(item)
    }

    public var trayBytes: Int64 { trayItems.reduce(0) { $0 + $1.bytes } }
    public var trayAllStashable: Bool { !trayItems.isEmpty && trayItems.allSatisfy { $0.entry.stashable } }

    public func clearTray() { trayItems = [] }

    // MARK: - Reclaim

    public func openReclaimPlan(items: [AtlasItem]? = nil, title: String = Copy.planTitle) {
        let source = items ?? trayItems
        guard !source.isEmpty else { return }
        planItems = source
        planTitle = title
        pushSheet(.reclaimPlan(title: title))
    }

    /// Pre-composed crisis plan: quickest safe items first.
    public func crisisPlan() -> [AtlasItem] {
        items.filter { $0.entry.tier == .regenerable && !$0.isStashed }
            .sorted { $0.bytes > $1.bytes }
    }

    public func runReclaim(selected: [AtlasItem]) {
        let split = ReclaimPlan(items: selected).freeSplit(remainingAllowance: pro.remainingAllowance)
        let toRun = split.now
        guard !toRun.isEmpty else {
            // Boundary reached with nothing free to run: the paywall may show,
            // unless a recent decline put it on cooldown.
            if paywallCoolingDown {
                toast = Toast(text: Copy.paywallBoundary)
            } else {
                sheet = .paywall(trigger: "free_boundary")
            }
            return
        }
        reclaiming = true
        reclaimStatuses = Array(repeating: .pending, count: toRun.count)
        let keep = planKeepInTrash
        let plan = ReclaimPlan(items: toRun)
        reclaimTask = Task {
            let outcome = await ReclaimExecutor().run(plan: plan, keepInTrash: keep) { index, status in
                Task { @MainActor in
                    if index < self.reclaimStatuses.count { self.reclaimStatuses[index] = status }
                }
            }
            self.completeReclaim(outcome: outcome, lockedCount: split.withPro.count)
        }
    }

    public func cancelReclaim() {
        reclaimTask?.cancel()
    }

    private func completeReclaim(outcome: ReclaimOutcome, lockedCount: Int) {
        reclaiming = false
        reclaimOutcome = outcome
        if let receipt = outcome.receipt {
            receipts.append(receipt)
            pro.recordReclaim(bytes: outcome.reclaimedBytes)
            changeLog.append(ChangeEvent(
                text: "Reclaimed \(ByteFormat.string(outcome.reclaimedBytes))",
                delta: -outcome.reclaimedBytes
            ))
        }
        if outcome.doneCount > 0 {
            SoundPlayer.shared.play(.pour)
            toast = Toast(text: Copy.reclaimToast(ByteFormat.string(outcome.reclaimedBytes)))
            removeReclaimedFromModel(outcome: outcome)
        }
        Analytics.shared.log("reclaim_run", [
            "bytes": String(outcome.reclaimedBytes),
            "items": String(outcome.doneCount),
        ])
        if outcome.skipped.isEmpty {
            sheet = nil
            trayItems = []
        }
        if lockedCount > 0 && !pro.isPro {
            Analytics.shared.log("free_boundary_hit")
        }
    }

    private func removeReclaimedFromModel(outcome: ReclaimOutcome) {
        guard let result, let receipt = outcome.receipt else { return }
        let gone = Set(receipt.items.map(\.path))
        result.items.removeAll { gone.contains($0.url.path) }
        planItems.removeAll { gone.contains($0.url.path) }
        trayItems.removeAll { gone.contains($0.url.path) }
        pruneNodes(paths: gone, under: result.root)
    }

    private func pruneNodes(paths: Set<String>, under node: ScanNode) {
        var removedBytes: Int64 = 0
        node.children.removeAll { child in
            if paths.contains(child.path) {
                removedBytes += child.allocatedBytes
                return true
            }
            return false
        }
        for child in node.children {
            if paths.contains(where: { $0.hasPrefix(child.path + "/") }) {
                pruneNodes(paths: paths, under: child)
            }
        }
        if removedBytes > 0 {
            var current: ScanNode? = node
            while let n = current {
                n.allocatedBytes -= removedBytes
                current = n.parent
            }
        }
    }

    // MARK: - Stash

    private func restoreStashIfKnown() {
        guard let path = UserDefaults.standard.string(forKey: "stashVolumePath") else { return }
        let url = URL(fileURLWithPath: path)
        // All volume IO stays off the main thread: a stalled drive holds
        // open() indefinitely and would brick launch before the first window.
        // The fileExists guard also keeps StashManager.init from creating a
        // phantom /Volumes folder on the internal disk when the drive is away.
        Task.detached(priority: .utility) { [weak self] in
            let manager: StashManager? = FileManager.default.fileExists(atPath: path)
                ? (try? StashManager(volume: url)) : nil
            await MainActor.run {
                guard let self, let manager else { return }
                self.stash = manager
                self.guardian.refresh()
            }
        }
        guardian.refresh()
    }

    public func adoptStash(volume: URL) throws {
        let manager = try StashManager(volume: volume)
        UserDefaults.standard.set(volume.path, forKey: "stashVolumePath")
        stash = manager
        guardian.refresh()
    }

    public func stashItem(_ item: AtlasItem) {
        stashItems([item])
    }

    /// Moves run one at a time: the manifest is a single journal, so a
    /// group toggle must not start concurrent transactions.
    public func stashItems(_ items: [AtlasItem]) {
        let movable = items.filter { !$0.isStashed }
        guard !movable.isEmpty else { return }
        guard pro.isPro else {
            sheet = .paywall(trigger: "stash_toggle")
            return
        }
        guard stash != nil else {
            sheet = .stashSetup
            return
        }
        for item in movable { stashBusy.insert(item.id) }
        Task {
            for item in movable {
                await self.performStash(item)
            }
        }
    }

    private func performStash(_ item: AtlasItem) async {
        guard let stash else {
            stashBusy.remove(item.id)
            return
        }
        do {
            try await stash.stash(item: item, fullHash: settings.fullHashVerify)
            stashBusy.remove(item.id)
            markStashDone(item: item)
            SoundPlayer.shared.play(.tuck)
            toast = Toast(text: Copy.moveDoneToast(ByteFormat.string(item.bytes)))
            changeLog.append(ChangeEvent(
                text: "Moved \(item.displayName) to the Stash",
                delta: -item.bytes
            ))
            Analytics.shared.log("stash_move", ["bytes": String(item.bytes), "direction": "out", "result": "ok"])
        } catch {
            stashBusy.remove(item.id)
            self.stash?.lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            toast = Toast(text: self.stash?.lastError ?? Copy.moveFail)
            Analytics.shared.log("stash_move", ["direction": "out", "result": "fail"])
        }
    }

    public func bringHome(entryID: UUID) {
        bringHomeEntries([entryID])
    }

    public func bringHomeEntries(_ ids: [UUID]) {
        guard let stash else { return }
        Task {
            var anySucceeded = false
            for id in ids {
                do {
                    try await stash.bringHome(id, fullHash: settings.fullHashVerify)
                    anySucceeded = true
                } catch {
                    self.toast = Toast(text: (error as? LocalizedError)?.errorDescription ?? Copy.moveFail)
                }
            }
            if anySucceeded { self.rescanSoon() }
        }
    }

    private func markStashDone(item: AtlasItem) {
        guard let result else { return }
        if let i = result.items.firstIndex(where: { $0.id == item.id }) {
            result.items[i].isStashed = true
        }
        trayItems.removeAll { $0.id == item.id }
    }

    public func rescanSoon() {
        guard !scanning else { return }
        startScan()
    }

    /// Restore the last scan from disk. Relaunches land here; the volume is
    /// walked again only on the refresh button or when the watcher sees real
    /// changes settle.
    public func loadCachedScan() -> Bool {
        guard result == nil, !scanning else { return false }
        guard let root = scanRoot ?? restoreGrant() else { return false }
        scanRoot = root
        guard let cached = ScanCache.load(rootPath: root.standardizedFileURL.path) else { return false }
        cached.disk = DiskSnapshot.capture()
        markStashedItems(in: cached)
        result = cached
        // Findings restored with the cache like every other item;
        // prune what vanished since.
        lensFindings = cached.lensFindings.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        startWatching()
        refreshDockerBytes()
        return true
    }

    // MARK: - FSEvents

    private func startWatching() {
        watcher?.stop()
        guard let root = scanRoot else { return }
        let paths: [String]
        if root.path == "/" {
            // Watching all of / floods with system noise; the places dev bytes
            // actually move cover the ground.
            paths = [
                FileManager.default.homeDirectoryForCurrentUser.path,
                "/opt", "/Library/Developer",
            ].filter { FileManager.default.fileExists(atPath: $0) }
        } else {
            paths = [root.path]
        }
        watcher = FSWatcher(paths: paths) { [weak self] in
            Task { @MainActor in self?.fsEventArrived() }
        }
    }

    private func fsEventArrived() {
        changesPending = true
        quietRescanTask?.cancel()
        quietRescanTask = Task {
            // Rescan only after the disk has been quiet for a while (:
            // deltas settle; Elbowroom never churns mid-build).
            try? await Task.sleep(nanoseconds: 45_000_000_000)
            guard !Task.isCancelled else { return }
            self.rescanIfSensible()
        }
    }

    /// Called on quiet timeout and on app activation.
    public func rescanIfSensible() {
        guard changesPending, !scanning, inMain else { return }
        guard NSApplication.shared.isActive else { return }
        if let last = result?.finishedAt, Date().timeIntervalSince(last) < 60 { return }
        changesPending = false
        startScan()
    }

    // MARK: - Update planner

    public func composeUpdatePlan(neededBytes: Int64) {
        updatePlan = UpdatePlanner.compose(need: neededBytes, items: items, hasStash: stash != nil)
        sheet = .updatePlanner
    }

    // MARK: - Suggestions

    public struct Suggestion: Identifiable {
        public let id: String
        public let item: AtlasItem?
        public let verb: String   // Reclaim / Stash / Show me
        public let line: String
    }

    /// (evolved): the briefing lists every recommended move, named and
    /// ranked by size; nothing is sampled away. Hiding a row never summons a
    /// replacement, because the list was already complete.
    public var suggestions: [Suggestion] {
        suggestionCandidates.filter { !isSuggestionHidden($0.id) }
    }

    /// Hidden-but-otherwise-eligible rows, for the reveal line under the list.
    public var hiddenSuggestionCount: Int {
        suggestionCandidates.filter { isSuggestionHidden($0.id) }.count
    }

    private func isSuggestionHidden(_ id: String) -> Bool {
        guard let at = settings.dismissedSuggestions[id] else { return false }
        return at > Date().addingTimeInterval(-30 * 86_400)
    }

    private var suggestionCandidates: [Suggestion] {
        let staleCutoff = Date().addingTimeInterval(-30 * 86_400)
        var out: [Suggestion] = []
        for item in items where !item.isStashed && item.bytes > 1_000_000_000 {
            switch item.entry.tier {
            case .regenerable:
                out.append(Suggestion(id: item.id, item: item, verb: Copy.trayReclaim, line: item.entry.identityLine))
            case .rebuildable:
                if (item.lastTouched ?? .distantPast) < staleCutoff {
                    let verb = item.entry.stashable && stash != nil ? Copy.trayStash : Copy.trayReclaim
                    out.append(Suggestion(id: item.id, item: item, verb: verb, line: item.entry.identityLine))
                }
            case .managed:
                if let tool = ToolCleanup.tool(for: item.entryID), toolsAvailable.contains(tool) {
                    out.append(Suggestion(id: item.id, item: item, verb: Copy.cleanUp, line: item.entry.identityLine))
                } else if ToolCleanup.directReclaimEntryIDs.contains(item.entryID) {
                    out.append(Suggestion(id: item.id, item: item, verb: Copy.trayReclaim, line: item.entry.identityLine))
                } else if item.entry.teachFlow != nil {
                    out.append(Suggestion(id: item.id, item: item, verb: Copy.showMe, line: item.entry.identityLine))
                }
            case .yours:
                continue
            }
        }
        return out.sorted { ($0.item?.bytes ?? 0) > ($1.item?.bytes ?? 0) }
    }

    public func dismissSuggestion(_ id: String) {
        settings.dismissedSuggestions[id] = Date()
    }

    public func showHiddenSuggestions() {
        settings.dismissedSuggestions = [:]
    }

    // MARK: - Tool-mediated cleanup

    /// Probe which developer tools answer, off-main; verbs pick from the cache.
    public func refreshToolCapabilities() {
        Task.detached(priority: .utility) {
            let available = Set(DevTool.allCases.filter { ToolRunner.isAvailable($0) })
            await MainActor.run { self.toolsAvailable = available }
        }
    }

    /// Ask the tool what can go; every row carries the exact argv it would run.
    public func composeCleanupPlan(entryID: String) async -> CleanupPlan {
        guard let tool = ToolCleanup.tool(for: entryID) else {
            return CleanupPlan(tool: .simctl, entryID: entryID, actions: [], blockedReason: Copy.toolMissing)
        }
        func blocked(_ reason: String) -> CleanupPlan {
            CleanupPlan(tool: tool, entryID: entryID, actions: [], blockedReason: reason)
        }
        do {
            switch tool {
            case .simctl:
                let runtimes = try await ToolRunner.run(.simctl, ["simctl", "runtime", "list", "-j"], timeout: 30)
                guard runtimes.status == 0 else { return blocked(Copy.toolMissing) }
                // A connected offload drive turns current runtimes into
                // copy-then-delete rows and surfaces images already resting
                // there as add-back rows.
                var offloadDir: String?
                var driveName: String?
                if let stash, stash.volumeIsPresent {
                    offloadDir = stash.stashRoot.appendingPathComponent("Runtimes", isDirectory: true).path
                    driveName = stash.volumeName
                }
                var (actions, kept) = SimCleanup.runtimePlan(
                    runtimes: SimctlParser.runtimes(fromJSON: runtimes.stdout),
                    offloadDir: offloadDir,
                    driveName: driveName
                )
                if let offloadDir, let driveName {
                    let resting = ((try? FileManager.default.contentsOfDirectory(atPath: offloadDir)) ?? [])
                        .filter { $0.hasSuffix(".dmg") }
                        .map { offloadDir + "/" + $0 }
                    actions += SimCleanup.addBackActions(imagePaths: resting, driveName: driveName)
                }
                // The row's total also holds the dyld caches; offer them too
                // so the sheet reconciles and everything is deletable.
                let dyldBytes = SimCleanup.directorySize("/Library/Developer/CoreSimulator/Caches/dyld")
                if dyldBytes > 100_000_000 {
                    actions.append(SimCleanup.dyldCacheRow(bytes: dyldBytes))
                }
                var notes = kept.map { runtime in
                    Copy.cleanupStays(
                        "\(SimCleanup.shortPlatform(runtime.identifier)) \(runtime.version)",
                        ByteFormat.string(runtime.sizeBytes ?? 0)
                    )
                }
                // One Simulator sheet: devices and test clones join
                // the runtime rows.
                let devices = try await ToolRunner.run(.simctl, ["simctl", "list", "devices", "-j"], timeout: 30)
                guard devices.status == 0 else { return blocked(Copy.toolMissing) }
                var (deviceActions, keptCount) = SimCleanup.devicePlan(
                    devices: SimctlParser.devices(fromJSON: devices.stdout),
                    staleCutoff: Date().addingTimeInterval(-90 * 86_400)
                )
                // Parallel-testing clones ride this same sheet; the
                // scan already measured them.
                let cloneBytes = SimCleanup.directorySize(NSHomeDirectory() + "/Library/Developer/XCTestDevices")
                if cloneBytes > 0 {
                    deviceActions.insert(SimCleanup.testCloneRow(bytes: cloneBytes), at: 0)
                }
                if keptCount > 0 { notes.append(Copy.cleanupKeptDevices(keptCount)) }
                return CleanupPlan(tool: .simctl, entryID: entryID, actions: actions + deviceActions, notes: notes)
            case .docker:
                let df = try await ToolRunner.run(.docker, ["system", "df", "--format", "{{json .}}"], timeout: 15)
                guard df.status == 0 else { return blocked(Copy.containerAppStart) }
                let rows = DockerCleanup.dfRows(fromOutput: String(data: df.stdout, encoding: .utf8) ?? "")
                // The verbose listing names each unused volume; without it the
                // plan falls back to one summary prune row.
                var volumes: [(name: String, bytes: Int64)] = []
                if rows["Local Volumes", default: 0] > 0,
                   let verbose = try? await ToolRunner.run(.docker, ["system", "df", "-v", "--format", "{{json .}}"], timeout: 30),
                   verbose.status == 0 {
                    volumes = DockerCleanup.volumeRows(
                        fromVerboseOutput: String(data: verbose.stdout, encoding: .utf8) ?? ""
                    )
                }
                // Reconciliation: the Items row measures the VM disk
                // file; these rows free space inside it. Say so.
                return CleanupPlan(tool: .docker, entryID: entryID,
                                   actions: DockerCleanup.plan(dfRows: rows, volumes: volumes))
            case .brew:
                let preview = try await ToolRunner.run(.brew, ["cleanup", "-n", "--prune=all"], timeout: 60)
                let text = String(data: preview.stdout, encoding: .utf8) ?? ""
                return CleanupPlan(tool: .brew, entryID: entryID, actions: BrewCleanup.plan(previewOutput: text))
            case .tmutil:
                // Deleting the reference snapshot mid-backup is the one
                // moment to refuse; everything else is the user's call.
                let status = try await ToolRunner.run(.tmutil, ["status"], timeout: 15)
                if TMSnapshotParser.backupRunning(fromOutput: String(data: status.stdout, encoding: .utf8) ?? "") {
                    return blocked(Copy.tmBackupRunning)
                }
                let list = try await ToolRunner.run(.tmutil, ["listlocalsnapshots", "/"], timeout: 15)
                guard list.status == 0 else { return blocked(Copy.toolMissing) }
                let listText = String(data: list.stdout, encoding: .utf8) ?? ""
                let tokens = TMSnapshotParser.snapshotTokens(fromOutput: listText)
                // No destination configured is an answer, not a failure: the
                // notes then warn instead of reassure.
                let dest = try? await ToolRunner.run(.tmutil, ["destinationinfo"], timeout: 15)
                let destination = dest.flatMap {
                    TMSnapshotParser.destination(fromOutput: String(data: $0.stdout, encoding: .utf8) ?? "")
                }
                let (actions, notes, estimate) = TMSnapshotCleanup.plan(
                    tokens: tokens,
                    destination: destination,
                    purgeableBytes: DiskSnapshot.capture().purgeable,
                    osUpdateCount: TMSnapshotParser.osUpdateCount(fromOutput: listText)
                )
                return CleanupPlan(tool: .tmutil, entryID: entryID, actions: actions,
                                   notes: notes, estimatedBytes: estimate)
            }
        } catch {
            return blocked((error as? LocalizedError)?.errorDescription ?? Copy.toolMissing)
        }
    }

    /// Evolved: the standing trim. macOS has no off switch for local
    /// snapshots, so with the user's consent Elbowroom deletes them whenever a
    /// scan finds them holding space again. The live backup check runs
    /// off-main right before anything deletes; the receipt records the
    /// measured return like any other run. The loop is self-limiting: the
    /// post-cleanup rescan finds zero snapshots until the next backup.
    private func autoThinSnapshotsIfNeeded() {
        guard let disk = result?.disk,
              TMSnapshotCleanup.shouldAutoThin(
                  enabled: settings.autoThinSnapshots,
                  snapshotCount: disk.snapshotCount,
                  purgeableBytes: disk.purgeable,
                  backupRunning: false
              )
        else { return }
        Task { [weak self] in
            guard let self else { return }
            guard let status = try? await ToolRunner.run(.tmutil, ["status"], timeout: 15),
                  !TMSnapshotParser.backupRunning(fromOutput: String(data: status.stdout, encoding: .utf8) ?? ""),
                  let list = try? await ToolRunner.run(.tmutil, ["listlocalsnapshots", "/"], timeout: 15)
            else { return }
            let tokens = TMSnapshotParser.snapshotTokens(fromOutput: String(data: list.stdout, encoding: .utf8) ?? "")
            guard !tokens.isEmpty else { return }
            let (actions, _, _) = TMSnapshotCleanup.plan(tokens: tokens, destination: nil, purgeableBytes: 0)
            _ = await self.runCleanup(CleanupPlan(tool: .tmutil, entryID: "sys.snapshots", actions: actions))
        }
    }

    /// Run the checked rows one at a time; receipt, changelog, and rescan on
    /// completion. Returns per-action failure lines for the sheet to show.
    public func runCleanup(_ plan: CleanupPlan) async -> [String: String] {
        var failures: [String: String] = [:]
        var doneItems: [ReceiptItem] = []
        // Snapshot rows carry no per-row size, so the freed space is measured
        // as a free-space delta around the whole run (: measured, never
        // promised).
        let diskBefore = plan.tool == .tmutil ? DiskSnapshot.capture() : nil
        for action in plan.checkedActions {
            do {
                // The copy must land verified before anything is destroyed.
                if let copy = action.preCopy {
                    try await ToolRunner.copyFileVerified(from: copy.from, to: copy.to)
                }
                let out = try await ToolRunner.run(plan.tool, action.argv, timeout: 600)
                if out.status == 0 {
                    doneItems.append(ReceiptItem(
                        path: ToolRunner.displayCommand(plan.tool, action.argv).joined(separator: " "),
                        name: action.title, bytes: action.bytes, tier: .managed, entryID: plan.entryID
                    ))
                    changeLog.append(ChangeEvent(text: "Cleaned up \(action.title)", delta: -action.bytes))
                } else {
                    let line = out.stderr.split(separator: "\n").last.map(String.init)
                    failures[action.id] = line ?? Copy.moveFail
                }
            } catch {
                failures[action.id] = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
        if !doneItems.isEmpty {
            var measured: Int64?
            if let diskBefore {
                let after = DiskSnapshot.capture()
                measured = max(0, after.available - diskBefore.available)
                changeLog.append(ChangeEvent(
                    text: Copy.tmChangeLine(doneItems.count), delta: -(measured ?? 0)
                ))
            }
            receipts.append(Receipt(items: doneItems, restoreStatus: .deletedNow,
                                    trashFolder: nil, measuredBytes: measured))
            let total = doneItems.reduce(Int64(0)) { $0 + $1.bytes } + (measured ?? 0)
            SoundPlayer.shared.play(.pour)
            toast = Toast(text: Copy.reclaimToast(ByteFormat.string(total)))
            Analytics.shared.log("tool_cleanup", [
                "tool": plan.tool.rawValue, "bytes": String(total), "actions": String(doneItems.count),
            ])
            rescanSoon()
        }
        return failures
    }
}
