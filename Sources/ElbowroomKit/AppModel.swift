import Foundation
import SwiftUI
import AppKit
import Observation

public enum OnboardingBeat: Int, Comparable {
    case welcome, privacy, trashFirst, grant, scanning, reveal
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
    case teach(TeachFlowID, bytes: Int64)
    case cleanup(entryID: String)
    case updatePlanner
    case askKibi(name: String, path: String, bytes: Int64, children: [String])
    public var id: String {
        switch self {
        case .reclaimPlan: "plan"
        case .teach(let id, _): "teach-\(id.rawValue)"
        case .cleanup(let entryID): "cleanup-\(entryID)"
        case .updatePlanner: "planner"
        case .askKibi(_, let path, _, _): "kibi-\(path)"
        }
    }
}

@Observable
@MainActor
public final class AppModel {
    // MARK: Stores
    public let settings: SettingsStore
    public let receipts: ReceiptStore
    public let changeLog: ChangeLog

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
    public let inventory = Inventory()
    public var result: ScanResult? {
        get { inventory.result }
        set {
            inventory.replace(with: newValue)
            zoomPath = zoomPath.compactMap { newValue?.root.find(path: $0.path) }
        }
    }
    private var scanTask: Task<Void, Never>?
    private var scanGeneration = 0
    private let scanCacheURL: URL?

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
        didSet { if sheet == nil { sheetStack = []; actionTask?.cancel() } }
    }
    /// Sheets the current one slid over; closing returns here, so a flow
    /// like lenses → plan never dead-ends.
    public private(set) var sheetStack: [ActiveSheet] = []
    public var toast: Toast?
    public var zoomPath: [ScanNode] = []

    // MARK: Tray
    public var trayItems: [AtlasItem] = []

    // MARK: Reclaim run
    public var reclaiming = false
    public var reclaimStatuses: [ReclaimItemStatus] = []
    public var reclaimOutcome: ReclaimOutcome?
    public var planKeepInTrash = true
    public var planItems: [AtlasItem] = []
    public var planTitle = Copy.planTitle
    private var reclaimTask: Task<Void, Never>?
    private var actionTask: Task<Void, Never>?

    // MARK: Tool-mediated cleanup
    public var toolsAvailable: Set<DevTool> = []

    // MARK: Update planner
    public var updatePlan: UpdatePlan?

    // MARK: Live deltas
    private var watcher: FSWatcher?
    public var changesPending = false
    private var quietRescanTask: Task<Void, Never>?

    @ObservationIgnored private var activationObserver: NSObjectProtocol?

    public init(settings: SettingsStore = .shared,
                receipts: ReceiptStore? = nil, changeLog: ChangeLog? = nil,
                startServices: Bool = true, scanCacheURL: URL? = nil) {
        let receipts = receipts ?? ReceiptStore()
        let changeLog = changeLog ?? ChangeLog()
        self.scanCacheURL = scanCacheURL
        self.settings = settings
        self.receipts = receipts
        self.changeLog = changeLog
        if startServices {
            refreshToolCapabilities()
            Task {
                await receipts.loadFromDisk()
                await changeLog.loadFromDisk()
                await receipts.sweepExpired()
            }
        }
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
        guard startServices else { return }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshFDAStatus() }
        }
    }

    deinit {
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
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
                    GrantHelperPanel.shared.markGranted()
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

    /// The pending uninstall survives, so the new launch resumes it.
    public func relaunchApp() {
        prepareForRelaunch()
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
        scanGeneration += 1
        let generation = scanGeneration
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
                    guard generation == self.scanGeneration, !Task.isCancelled else { return }
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
                guard generation == self.scanGeneration else { return }
                self.scanning = false
            }
        }
    }

    public func cancelScan() {
        scanGeneration += 1
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
        self.result = result
        scanning = false
        changesPending = false
        refreshFDAStatus() // the B5 chip hides when FDA already covers everything
        startWatching()
        if let rootPath = scanRoot?.standardizedFileURL.path {
            ScanCache.enqueueSave(result, rootPath: rootPath, to: scanCacheURL)
        }
        changeLog.recordScan(items: result.items, disk: result.disk)
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

    public var items: [AtlasItem] { inventory.items }

    /// Solid headroom: bytes Elbowroom can move to the Trash itself.
    public var solidReclaimable: Int64 {
        items.filter { $0.entry.tier == .regenerable || $0.entry.tier == .rebuildable }
            .reduce(0) { $0 + $1.bytes }
    }

    /// Teach-flow bytes count toward headroom with a hollow badge.
    public var teachBytes: Int64 {
        items.filter { $0.entry.tier == .managed && $0.entry.teachFlow != nil }
            .reduce(0) { $0 + $1.bytes }
    }

    /// Managed footprints need inspection before they become a savings estimate.
    public var headroomBytes: Int64 { solidReclaimable }

    public var isCrisis: Bool { (result?.disk.available ?? .max) < 10 * 1_000_000_000 }
    public var isModest: Bool { solidReclaimable < 3 * 1_000_000_000 }
    public var revealMode: String { isCrisis ? "crisis" : (isModest ? "modest" : "default") }

    /// Tier proportions for the Disk Strip.
    public var stripSegments: [(tier: Tier?, bytes: Int64)] {
        guard let result else { return [] }
        var byTier: [Tier: Int64] = [:]
        for item in items {
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

    public var lensFindings: [LensFinding] {
        get { inventory.result?.lensFindings ?? [] }
        set { inventory.setFindings(newValue) }
    }

    public var lensIdentifiedBytes: Int64 {
        // Strata describe Downloads' age layers, not new space on top of it.
        lensFindings.filter { $0.kind != .stratum }.reduce(0) { $0 + $1.bytes }
    }

    public var everythingElseBytes: Int64 {
        stripSegments.first { $0.tier == nil }?.bytes ?? 0
    }

    public var remainingStorageExplanation: String {
        guard let result, result.root.path == "/" else { return Copy.lensDenLine }
        let balance = StorageBalance(used: result.disk.used, scanned: result.root.allocatedBytes,
                                     named: items.reduce(0) { $0 + $1.bytes }, outsideWalk: result.outsideWalkBytes)
        return Copy.remainingStorageBreakdown(ByteFormat.string(balance.readable), ByteFormat.string(balance.unmeasured))
    }

    public func pushSheet(_ next: ActiveSheet) {
        if let current = sheet { sheetStack.append(current) }
        sheet = next
    }

    public func closeSheet() {
        sheet = sheetStack.popLast()
        if sheet == nil && !lensFindings.isEmpty {
            let findings = lensFindings
            let revision = inventory.revision
            Task {
                let remaining = await Task.detached(priority: .utility) {
                    findings.filter { FileManager.default.fileExists(atPath: $0.url.path) }
                }.value
                guard revision == inventory.revision, remaining.count != findings.count else { return }
                inventory.setFindings(remaining)
            }
        }
    }

    /// The Items row for a container engine shows what its tool can clear
    /// right now, not the virtual disk's total: the row and its sheet agree.
    public func refreshDockerBytes() {
        guard let item = items.first(where: { $0.entryID == "docker.data" || $0.entryID == "orbstack.data" }) else { return }
        let revision = inventory.revision
        Task {
            guard let out = try? await ToolRunner.run(.docker, ["system", "df", "--format", "{{json .}}"], timeout: 15),
                  out.status == 0 else { return }
            let bytes = DockerCleanup.dfRows(fromOutput: String(data: out.stdout, encoding: .utf8) ?? "")
                .values.reduce(0, +)
            inventory.updateBytes(bytes, itemID: item.id, expectedRevision: revision)
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

    public func canSelect(_ item: AtlasItem) -> Bool { ItemAction.canBatch(item) }

    public func action(for item: AtlasItem) -> ItemAction? {
        ItemAction.resolve(item, tools: toolsAvailable)
    }

    public func perform(_ action: ItemAction, on item: AtlasItem) {
        actionTask?.cancel()
        switch action {
        case .reclaim: openReclaimPlan(items: [item])
        case .cleanup: sheet = .cleanup(entryID: item.entryID)
        case .teach(let flow): sheet = .teach(flow, bytes: item.bytes)
        case .uninstall: actionTask = Task { await openUninstallPlan(item) }
        case .trimMessages: actionTask = Task { await openMessagesTrim(bytes: item.bytes) }
        case .trimPhotos: actionTask = Task { await openPhotosTrim(item) }
        }
    }

    public func setTray(items: [AtlasItem], selected: Bool) {
        for item in items where canSelect(item) && trayItems.contains(item) != selected {
            toggleTray(item)
        }
    }

    public func toggleTray(_ item: AtlasItem) {
        if let i = trayItems.firstIndex(of: item) {
            trayItems.remove(at: i)
            return
        }
        guard canSelect(item) else {
            if let action = action(for: item) { perform(action, on: item) }
            return
        }
        // No confirmation here: checking a box is reversible, and the
        // plan sheet carries each Rebuildable's computed rebuild-time line.
        trayItems.append(item)
    }

    public var trayBytes: Int64 { trayItems.reduce(0) { $0 + $1.bytes } }

    public func clearTray() { trayItems = [] }

    // MARK: - Reclaim

    /// A no-op filesystem probe cannot establish App Management permission.
    /// Open the review first; only the user's confirmed operation tests access.
    public func openUninstallPlan(_ item: AtlasItem) async {
        await prepareUninstallPlan(item)
    }

    /// Offer Settings after a real access failure. Remember only the app to
    /// review after reopening; never resume destructive work automatically.
    public func beginAppManagementWait(for item: AtlasItem) {
        settings.pendingUninstallPath = item.url.path
        // The sheet closes before Settings opens. A modal sheet makes the
        // app unquittable, and this flow ends in a quit: with one up, macOS
        // refuses its own Quit & Reopen with a beep, which is exactly the
        // remedy the grant needs. The floating panel carries the wait.
        sheet = nil
        sheetStack = []
        AppManagement.openSettings()
        GrantHelperPanel.shared.show { [weak self] in self?.relaunchApp() }
        Analytics.shared.log("app_management_settings_opened")
    }

    /// Backing out: the uninstall is abandoned, so the panel and
    /// the pending resume all go with it.
    public func cancelAppManagementWait() {
        hideAppManagementHelper()
        settings.pendingUninstallPath = nil
    }

    /// Teardown that keeps the pending uninstall: the relaunch runs this,
    /// and the next launch resumes what the sheet started.
    public func hideAppManagementHelper() {
        GrantHelperPanel.shared.hide()
    }

    /// The relaunch dismisses whatever is on screen first: a modal defers
    /// termination, which is how a relaunch used to leave the old instance
    /// running beside the new one.
    func prepareForRelaunch() {
        hideAppManagementHelper()
        sheet = nil
        sheetStack = []
    }

    /// Resume at review regardless of the old probe's result. A missing app
    /// is dropped, and the user still has to confirm the new plan.
    public func resumePendingUninstall() async {
        guard let path = settings.pendingUninstallPath else { return }
        settings.pendingUninstallPath = nil
        let exists = await Task.detached { FileManager.default.fileExists(atPath: path) }.value
        guard exists, !Task.isCancelled else { return }
        let item = items.first { $0.entryID == "app.bundle" && $0.url.path == path }
            ?? AtlasItem(entryID: "app.bundle", url: URL(fileURLWithPath: path),
                         bytes: 0, lastTouched: nil)
        await prepareUninstallPlan(item)
    }

    private func prepareUninstallPlan(_ item: AtlasItem) async {
        let plan = await ReclaimPlanner.uninstall(item, root: result?.root)
        guard !Task.isCancelled else { return }
        if let bundleID = plan.bundleID,
           NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == bundleID }) {
            toast = Toast(text: Copy.ineligibleRunning(item.displayName))
            return
        }
        openReclaimPlan(items: plan.items, title: Copy.uninstallTitle(item.displayName))
    }

    public func openMessagesTrim(bytes: Int64) async {
        let items = await ReclaimPlanner.messages(root: result?.root)
        guard !Task.isCancelled else { return }
        if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == MessagesTrim.messagesBundleID }) {
            toast = Toast(text: Copy.ineligibleRunning("Messages"))
            return
        }
        guard let items else {
            toast = Toast(text: Copy.messagesCloudOff)
            sheet = .teach(.messages, bytes: bytes)
            return
        }
        guard !items.isEmpty else { toast = Toast(text: Copy.kibiDenTidy); return }
        openReclaimPlan(items: items, title: Copy.messagesTrimTitle)
    }

    public func openPhotosTrim(_ item: AtlasItem) async {
        let items = await ReclaimPlanner.photos(item, root: result?.root)
        guard !Task.isCancelled else { return }
        if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == PhotosTrim.photosBundleID }) {
            toast = Toast(text: Copy.ineligibleRunning("Photos"))
            return
        }
        guard !items.isEmpty else { toast = Toast(text: Copy.kibiDenTidy); return }
        openReclaimPlan(items: items, title: Copy.photosTrimTitle)
    }

    public func openReclaimPlan(items: [AtlasItem]? = nil, title: String = Copy.planTitle) {
        let source = items ?? trayItems
        guard !source.isEmpty else { return }
        if !reclaiming {
            // A clean finish closes the sheet without an OK press, so the
            // last run's outcome may still be here. A fresh plan opens
            // fresh; only a run still in flight keeps its live view.
            reclaimOutcome = nil
            reclaimStatuses = []
            planKeepInTrash = settings.keepInTrashDefault
        }
        planItems = source
        planTitle = title
        pushSheet(.reclaimPlan(title: title))
    }

    /// Pre-composed crisis plan: quickest safe items first.
    public func crisisPlan() -> [AtlasItem] {
        items.filter { $0.entry.tier == .regenerable }
            .sorted { $0.bytes > $1.bytes }
    }

    public func runReclaim(selected: [AtlasItem]) {
        let toRun = selected
        guard !toRun.isEmpty else { return }
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
            self.completeReclaim(outcome: outcome)
        }
    }

    public func cancelReclaim() {
        reclaimTask?.cancel()
    }

    private func completeReclaim(outcome: ReclaimOutcome) {
        reclaiming = false
        reclaimOutcome = outcome
        if let receipt = outcome.receipt {
            receipts.append(receipt)
            changeLog.append(ChangeEvent(
                text: "Reclaimed \(ByteFormat.string(outcome.reclaimedBytes))",
                delta: -outcome.reclaimedBytes
            ))
        }
        if outcome.doneCount > 0 {
            SoundPlayer.shared.play(.whoosh)
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
    }

    private func removeReclaimedFromModel(outcome: ReclaimOutcome) {
        guard let receipt = outcome.receipt else { return }
        let gone = Set(receipt.items.map(\.path))
        inventory.remove(paths: gone)
        planItems.removeAll { gone.contains($0.url.path) }
        trayItems.removeAll { gone.contains($0.url.path) }
        zoomPath = zoomPath.compactMap { result?.root.find(path: $0.path) }
    }

    public func rescanSoon() {
        guard !scanning else { return }
        startScan()
    }

    /// Restore the last scan from disk. Relaunches land here; the volume is
    /// walked again only on the refresh button or when the watcher sees real
    /// changes settle.
    public func loadCachedScan() async -> Bool {
        guard result == nil, !scanning else { return result != nil }
        guard let root = scanRoot ?? restoreGrant() else { return false }
        scanRoot = root
        let revision = inventory.revision
        let generation = scanGeneration
        let cacheURL = scanCacheURL
        let cached = await Task.detached(priority: .userInitiated) { () -> ScanResult? in
            guard var cached = ScanCache.load(rootPath: root.standardizedFileURL.path, from: cacheURL) else { return nil }
            cached.disk = DiskSnapshot.captureSpace(snapshotCount: cached.disk.snapshotCount)
            cached.lensFindings.removeAll { !FileManager.default.fileExists(atPath: $0.url.path) }
            return cached
        }.value
        guard !Task.isCancelled, !scanning, generation == scanGeneration, revision == inventory.revision, scanRoot == root else { return result != nil }
        guard let cached else { return false }
        result = cached
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
        updatePlan = UpdatePlanner.compose(need: neededBytes, items: items)
        sheet = .updatePlanner
    }

    // MARK: - Suggestions

    public struct Suggestion: Identifiable {
        public let id: String
        public let item: AtlasItem?
        public let action: ItemAction
        public let line: String
        public var members: [AtlasItem] = []
        public var title: String { members.isEmpty ? (item?.displayName ?? "") : StorageGroup.forItem(members[0]).title }
        public var bytes: Int64 { members.isEmpty ? (item?.bytes ?? 0) : members.reduce(0) { $0 + $1.bytes } }
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
        let cutoff = Date().addingTimeInterval(-30 * 86_400)
        let reproducible = items.filter {
            guard !$0.entry.planDefaultOff else { return false }
            return $0.entry.tier == .regenerable ||
                ($0.entry.tier == .rebuildable && ($0.lastTouched ?? .distantPast) < cutoff)
        }
        var out = Dictionary(grouping: reproducible, by: StorageGroup.forItem).compactMap { kind, members -> Suggestion? in
            guard members.reduce(Int64(0), { $0 + $1.bytes }) >= 100_000_000 else { return nil }
            let sorted = members.sorted { $0.bytes == $1.bytes ? $0.id < $1.id : $0.bytes > $1.bytes }
            return Suggestion(id: "group." + kind.rawValue, item: sorted.first, action: .reclaim,
                              line: kind == .builds ? Copy.groupOlderBuilds : kind.explanation, members: sorted)
        }
        out += items.compactMap { item in
            guard item.entry.tier != .regenerable && item.entry.tier != .rebuildable,
                  let action = ItemAction.suggestion(item, tools: toolsAvailable) else { return nil }
            return Suggestion(id: item.id, item: item, action: action, line: item.entry.identityLine)
        }
        return out.sorted {
            if $0.members.isEmpty != $1.members.isEmpty { return !$0.members.isEmpty }
            return $0.bytes == $1.bytes ? $0.id < $1.id : $0.bytes > $1.bytes
        }
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

    public func composeCleanupPlan(entryID: String) async -> CleanupPlan {
        await CleanupPlanner.compose(entryID: entryID)
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
        let diskBefore = plan.tool == .tmutil ? await Task.detached { DiskSnapshot.captureSpace() }.value : nil
        for action in plan.checkedActions {
            do {
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
                let after = await Task.detached { DiskSnapshot.captureSpace() }.value
                measured = max(0, after.available - diskBefore.available)
                changeLog.append(ChangeEvent(
                    text: Copy.tmChangeLine(doneItems.count), delta: -(measured ?? 0)
                ))
            }
            receipts.append(Receipt(items: doneItems, restoreStatus: .deletedNow,
                                    trashFolder: nil, measuredBytes: measured))
            let total = doneItems.reduce(Int64(0)) { $0 + $1.bytes } + (measured ?? 0)
            SoundPlayer.shared.play(.whoosh)
            toast = Toast(text: Copy.reclaimToast(ByteFormat.string(total)))
            Analytics.shared.log("tool_cleanup", [
                "tool": plan.tool.rawValue, "bytes": String(total), "actions": String(doneItems.count),
            ])
            rescanSoon()
        }
        return failures
    }
}
