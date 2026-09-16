import Foundation

/// Scan engine. Enumerates from the granted root with bulk-attribute reads,
/// counts allocated size everywhere, never follows symlinks out of scope, never
/// writes. Builds a pruned tree (small children collapse into pebble counts),
/// classifies against the Atlas during descent, and tracks per-repo staleness.

public enum ScanEvent: @unchecked Sendable {
    case progress(itemsScanned: Int, bytesSeen: Int64, currentPath: String)
    case ticker(String)
    case finished(ScanResult)
}

/// A recognized fact about the disk that is not a scannable folder
/// (purgeable space, snapshots). Rendered as explainer items.
public struct SystemInsight: Identifiable, Sendable {
    public let id: String
    public let entryID: String
    public let bytes: Int64
    public let detail: String
    public init(entryID: String, bytes: Int64, detail: String) {
        self.id = entryID
        self.entryID = entryID
        self.bytes = bytes
        self.detail = detail
    }
}

public final class ScanResult: @unchecked Sendable {
    public let root: ScanNode
    public var items: [AtlasItem]
    public let repoStaleness: [String: Date]
    public let deniedPaths: [String]
    /// Refreshed on cache restore so the free-space heartbeat stays current.
    public var disk: DiskSnapshot
    public let duration: TimeInterval
    public let insights: [SystemInsight]
    public let scannedBytes: Int64
    public let classifiedBytes: Int64
    public let finishedAt: Date
    /// What the lenses named, part of the one result and its cache.
    public var lensFindings: [LensFinding]

    public var coverage: Double {
        scannedBytes > 0 ? Double(classifiedBytes) / Double(scannedBytes) : 0
    }

    init(root: ScanNode, items: [AtlasItem], repoStaleness: [String: Date],
         deniedPaths: [String], disk: DiskSnapshot, duration: TimeInterval,
         insights: [SystemInsight], scannedBytes: Int64, classifiedBytes: Int64,
         finishedAt: Date? = nil, lensFindings: [LensFinding] = []) {
        self.lensFindings = lensFindings
        self.root = root
        self.items = items
        self.repoStaleness = repoStaleness
        self.deniedPaths = deniedPaths
        self.disk = disk
        self.duration = duration
        self.insights = insights
        self.scannedBytes = scannedBytes
        self.classifiedBytes = classifiedBytes
        self.finishedAt = finishedAt ?? Date()
    }
}

public final class ScanEngine {
    public init() {}

    /// Directories never entered when scanning from `/`. `/System/Volumes`
    /// firmlinks would double-count the Data volume; external volumes are v1
    /// out of scope; the rest is kernel noise that only yields denials.
    static let rootSkips: Set<String> = [
        "/System", "/Volumes", "/dev", "/Network", "/cores",
        "/private/var/vm", "/private/var/db", "/private/var/folders",
        "/private/var/networkd", "/private/var/protected",
        // Mounted simulator runtime images: their uncompressed contents are
        // not local blocks; the real bytes live in the OS asset store and
        // are measured by the runtime post-pass instead.
        "/Library/Developer/CoreSimulator/Volumes",
        "/Library/Developer/CoreSimulator/Cryptex",
    ]

    /// Where macOS keeps downloaded simulator runtime images (cryptexes).
    /// Under the /System firmlink, so the walk never reaches it; the
    /// post-pass adds its real bytes to the runtimes item.
    static let runtimeAssetStore = "/System/Library/AssetsV2/com_apple_MobileAsset_iOSSimulatorRuntime"

    /// Bytes below which a child collapses into its parent's pebble count.
    static let keepThreshold: Int64 = 20 * 1_000_000
    static let maxDepth = 24

    private final class RepoContext {
        let name: String
        let path: String
        let marker: String
        let node: ScanNode
        var maxSourceMTime: Date?
        init(name: String, path: String, marker: String, node: ScanNode) {
            self.name = name
            self.path = path
            self.marker = marker
            self.node = node
        }
    }

    /// Project markers by telling power: version control first, then build
    /// manifests. Matched against the directory listing the walk already
    /// fetched — no extra stat per directory.
    static let projectMarkerIndex: [String: Int] = [
        ".git": 0, "Cargo.toml": 2, "Package.swift": 3,
        "go.mod": 4, "pyproject.toml": 5, "package.json": 6,
    ]
    static let projectMarkerLabels = ["Git", "Xcode", "Rust", "Swift", "Go", "Python", "JavaScript"]

    static func projectMarker(in contents: [URL]) -> String? {
        projectMarker(names: contents.lazy.map { $0.lastPathComponent })
    }

    static func projectMarker(names: some Sequence<String>) -> String? {
        var best = Int.max
        for name in names {
            if let index = projectMarkerIndex[name] {
                if index == 0 { return projectMarkerLabels[0] }
                best = min(best, index)
            } else if name.hasSuffix(".xcodeproj") {
                best = min(best, 1)
            }
        }
        return best == .max ? nil : projectMarkerLabels[best]
    }

    private final class ScanState {
        var itemsScanned = 0
        var bytesSeen: Int64 = 0
        var denied: [String] = []
        var items: [AtlasItem] = []
        var repos: [String: RepoContext] = [:]
        var itemRepo: [String: String] = [:] // item path -> repo path
        var tickeredEntries: Set<String> = []
        /// Lens facts gathered during the same walk, capped; the lens
        /// detectors run as a post-pass, never a second walk.
        var facts: [FileFact] = []
        var lastProgressReport = 0
    }

    /// Run a scan. Events stream out; the stream finishes after `.finished`.
    ///
    /// The default path is the parallel bulk walk (BulkWalk.swift): same
    /// semantics, several times faster. ELBOWROOM_SCAN_LEGACY=1 selects this
    /// serial walk, kept as the reference for A/B equivalence checks.
    public func scan(root: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> AsyncThrowingStream<ScanEvent, Error> {
        if ProcessInfo.processInfo.environment["ELBOWROOM_SCAN_LEGACY"] != "1" {
            return AsyncThrowingStream { continuation in
                let job = ParallelScanJob(root: root, home: home, continuation: continuation)
                job.start()
                continuation.onTermination = { _ in job.cancel() }
            }
        }
        return AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                let started = Date()
                let state = ScanState()
                let rootPath = root.standardizedFileURL.path
                let homePath = home.standardizedFileURL.path
                let rootNode = ScanNode(url: root.standardizedFileURL, isDirectory: true, parent: nil)
                do {
                    try self.walk(
                        node: rootNode, depth: 0, homePath: homePath,
                        repo: nil, colonyEntry: nil, lensEligible: rootPath == homePath,
                        state: state, continuation: continuation
                    )
                    rootNode.sortChildren()
                    var items = state.items
                    self.applyRepoStaleness(&items, state: state)
                    items.append(contentsOf: Self.genericCacheItems(homePath: homePath, root: rootNode, known: items))
                    items.append(contentsOf: Self.brewOldVersionItems(root: rootNode))
                    Self.addRuntimeAssetBytes(to: &items)
                    Self.mergeSimulatorItems(&items, homePath: homePath)
                    let disk = DiskSnapshot.capture()
                    // Snapshots ride the items list like everything else;
                    // the insight remains only for snapshot-free purgeable
                    // space.
                    let (snapshotItem, insights) = TMSnapshotCleanup.scanArtifacts(disk: disk)
                    if let snapshotItem { items.append(snapshotItem) }
                    items.sort { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.id < $1.id }
                    let classified = items.reduce(Int64(0)) { $0 + $1.bytes }
                    let seeds = state.repos.values.map {
                        Lens.ProjectSeed(path: $0.path, marker: $0.marker,
                                         bytes: $0.node.allocatedBytes,
                                         sourceTouched: $0.maxSourceMTime,
                                         fallbackTouched: $0.node.lastTouched)
                    }
                    let findings = Self.lensFindings(
                        facts: state.facts, homePath: homePath, root: rootNode,
                        projects: seeds, classified: items.map { ($0.id, $0.bytes) }
                    )
                    let result = ScanResult(
                        root: rootNode, items: items,
                        repoStaleness: state.repos.mapValues { $0.maxSourceMTime ?? Date.distantPast }
                            .reduce(into: [:]) { $0[$1.key] = $1.value },
                        deniedPaths: state.denied, disk: disk,
                        duration: Date().timeIntervalSince(started),
                        insights: insights,
                        scannedBytes: state.bytesSeen,
                        classifiedBytes: min(classified, state.bytesSeen),
                        lensFindings: findings
                    )
                    _ = rootPath
                    continuation.yield(.finished(result))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Keep this set lean: `.isUbiquitousItemKey` (and friends) drag the
    /// FileProvider framework into EVERY item lookup, a statfs per file that
    /// multiplies scan time by an order of magnitude on real disks. Dataless
    /// detection uses the allocated-vs-logical gap instead, which is free.
    private static let childKeys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey,
        .contentModificationDateKey,
    ]

    private func walk(
        node: ScanNode, depth: Int, homePath: String,
        repo: RepoContext?, colonyEntry: String?, lensEligible: Bool = false,
        state: ScanState, continuation: AsyncThrowingStream<ScanEvent, Error>.Continuation
    ) throws {
        try Task.checkCancellation()
        let fm = FileManager.default
        let path = node.path

        let contents: [URL]
        do {
            contents = try fm.contentsOfDirectory(
                at: node.url, includingPropertiesForKeys: Self.childKeys,
                options: []
            )
        } catch {
            state.denied.append(path)
            return
        }

        var repo = repo
        if depth > 0, colonyEntry == nil, let marker = Self.projectMarker(in: contents) {
            let ctx = RepoContext(name: node.name, path: path, marker: marker, node: node)
            state.repos[path] = ctx
            repo = ctx
        }

        var maxMTime: Date?
        for child in contents {
            try Task.checkCancellation()
            let childPath = child.path
            if depth == 0 {
                if Self.rootSkips.contains(childPath) { continue }
                if node.path == "/" && child.lastPathComponent.hasPrefix(".") { continue }
            }
            if Self.rootSkips.contains(childPath) { continue }

            guard let rv = try? child.resourceValues(forKeys: Set(Self.childKeys)) else { continue }

            if rv.isSymbolicLink == true {
                // Never follow symlinks out of scope. A stashed folder is a
                // symlink at its old address; it counts on the Stash side, not here.
                state.itemsScanned += 1
                continue
            }

            if rv.isDirectory == true {
                let childNode = ScanNode(url: child, isDirectory: true, parent: node)
                var childColony = colonyEntry
                if childColony == nil {
                    let matched = Atlas.classify(path: childPath, home: homePath)
                        ?? Atlas.classify(name: child.lastPathComponent, parentPath: path, home: homePath)
                    if let matched {
                        childNode.atlasEntryID = matched
                        childColony = matched
                    }
                }
                // Lens territory is the unclassified home tree: on at the
                // home folder, off inside ~/Library, .Trash, app-sealed
                // libraries, and anything the Atlas claims.
                let lowerName = child.lastPathComponent.lowercased()
                let childEligible: Bool
                if lensEligible {
                    childEligible = childColony == nil
                        && !(node.path == homePath && (lowerName == "library" || lowerName == ".trash"))
                        && !LensPass.sealedSuffixes.contains { lowerName.hasSuffix($0) }
                } else {
                    childEligible = childPath == homePath
                }
                if depth < Self.maxDepth {
                    // Dot directories (.git, .vscode, .venv) churn without a
                    // human working there; their mtimes never speak for the
                    // project's sources.
                    let carriesStaleness = childNode.atlasEntryID == nil && !lowerName.hasPrefix(".")
                    try walk(node: childNode, depth: depth + 1, homePath: homePath,
                             repo: carriesStaleness ? repo : nil,
                             colonyEntry: childColony, lensEligible: childEligible,
                             state: state, continuation: continuation)
                }
                if childEligible, state.facts.count < 400_000 {
                    state.facts.append(FileFact(
                        path: childPath, bytes: childNode.allocatedBytes,
                        modified: childNode.lastTouched ?? .distantPast, isDirectory: true
                    ))
                }
                node.allocatedBytes += childNode.allocatedBytes
                node.collapsedCount += 0

                if let entryID = childNode.atlasEntryID {
                    var item = AtlasItem(
                        entryID: entryID, url: child, bytes: childNode.allocatedBytes,
                        lastTouched: childNode.lastTouched,
                        projectName: repo?.name
                    )
                    if let repo { state.itemRepo[item.id] = repo.path }
                    if let dot = childNode.lastTouched, let m = maxMTime, dot > m { maxMTime = dot }
                    state.items.append(item)
                    childNode.projectName = repo?.name
                    self.emitTickerIfNeeded(for: &item, state: state, continuation: continuation)
                }

                // Prune: small children collapse into the pebble pile.
                if childNode.allocatedBytes >= Self.keepThreshold || depth < 1 || childNode.atlasEntryID != nil {
                    node.children.append(childNode)
                } else {
                    node.collapsedCount += 1 + childNode.collapsedCount + childNode.children.count
                    node.collapsedBytes += childNode.allocatedBytes
                }
                if let ct = childNode.lastTouched {
                    if maxMTime == nil || ct > maxMTime! { maxMTime = ct }
                }
            } else {
                let logical = Int64(rv.fileSize ?? 0)
                let allocated = Int64(rv.totalFileAllocatedSize ?? rv.fileAllocatedSize ?? 0)
                // Dataless (cloud-evicted) files show a large logical size but
                // near-zero allocation; they count at local bytes and are never
                // suggested for reclaim (edge matrix).
                if logical > 65_536, allocated < logical / 8 {
                    node.isDataless = true
                }
                node.allocatedBytes += allocated
                state.bytesSeen += allocated
                state.itemsScanned += 1
                if lensEligible, colonyEntry == nil, allocated >= 262_144, state.facts.count < 400_000 {
                    state.facts.append(FileFact(
                        path: childPath, bytes: allocated,
                        modified: rv.contentModificationDate ?? .distantPast, isDirectory: false
                    ))
                }
                if let mt = rv.contentModificationDate {
                    if maxMTime == nil || mt > maxMTime! { maxMTime = mt }
                    // Source files update repo staleness; artifact colonies do not.
                    if let repo, colonyEntry == nil {
                        if repo.maxSourceMTime == nil || mt > repo.maxSourceMTime! {
                            repo.maxSourceMTime = mt
                        }
                    }
                }
            }

            if state.itemsScanned - state.lastProgressReport >= 3000 {
                state.lastProgressReport = state.itemsScanned
                continuation.yield(.progress(
                    itemsScanned: state.itemsScanned,
                    bytesSeen: state.bytesSeen,
                    currentPath: childPath
                ))
            }
        }
        node.lastTouched = maxMTime
    }

    private func emitTickerIfNeeded(
        for item: inout AtlasItem, state: ScanState,
        continuation: AsyncThrowingStream<ScanEvent, Error>.Continuation
    ) {
        guard item.bytes >= 500 * 1_000_000,
              !state.tickeredEntries.contains(item.entryID),
              let template = item.entry.ticker
        else { return }
        state.tickeredEntries.insert(item.entryID)
        continuation.yield(.ticker(template(ByteFormat.string(item.bytes))))
    }

    /// Post-pass: the runtimes row tells the whole truth — dyld caches the
    /// walk measured plus the images resting in the OS asset store, so the
    /// row and the cleanup sheet reconcile.
    static func addRuntimeAssetBytes(to items: inout [AtlasItem]) {
        var assetBytes: Int64 = 0
        let walk = FileManager.default.enumerator(
            at: URL(fileURLWithPath: runtimeAssetStore),
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey]
        )
        while case let url as URL = walk?.nextObject() {
            assetBytes += Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
        }
        guard assetBytes > 0 else { return }
        if let index = items.firstIndex(where: { $0.entryID == "xcode.simRuntimes" }) {
            items[index].bytes += assetBytes
        } else {
            items.append(AtlasItem(
                entryID: "xcode.simRuntimes",
                url: URL(fileURLWithPath: "/Library/Developer/CoreSimulator"),
                bytes: assetBytes, lastTouched: nil
            ))
        }
    }

    /// Post-pass: runtimes, devices, and test clones fold into one
    /// Simulator item; a single row, a single sheet.
    static func mergeSimulatorItems(_ items: inout [AtlasItem], homePath: String) {
        let ids: Set<String> = ["xcode.simRuntimes", "xcode.simDevices", "xcode.testDevices"]
        let parts = items.filter { ids.contains($0.entryID) }
        guard !parts.isEmpty else { return }
        items.removeAll { ids.contains($0.entryID) }
        items.append(AtlasItem(
            entryID: "xcode.simulator",
            url: URL(fileURLWithPath: homePath + "/Library/Developer/CoreSimulator"),
            bytes: parts.reduce(0) { $0 + $1.bytes },
            lastTouched: parts.compactMap(\.lastTouched).max()
        ))
    }

    /// Post-pass: the lens detectors over facts the walk gathered.
    /// Pure functions; the walk is the only disk pass. Ghost aggregates come
    /// straight from the tree's home children.
    static func lensFindings(facts: [FileFact], homePath: String, root: ScanNode,
                             projects: [Lens.ProjectSeed] = [],
                             classified: [(path: String, bytes: Int64)] = []) -> [LensFinding] {
        let downloads = homePath + "/Downloads"
        var findings: [LensFinding] = []
        findings += Lens.mediaHoards(facts, downloads: downloads)
        if let pile = Lens.downloadsPile(facts, downloads: downloads) { findings.append(pile) }
        findings += Lens.installers(facts, downloads: downloads, installedApps: LensPass.installedApps())
        findings += Lens.twins(facts, hash: LensPass.sampleHash)
        findings += Lens.zipShadows(facts)
        findings += Lens.vms(facts)
        findings += Lens.weights(facts)
        // A byte named once is named for good: projects list net of the
        // colonies and findings inside them, ghosts net of all of those.
        let named = classified + findings.map { ($0.url.path, $0.bytes) }
        let projectFindings = Lens.projects(projects, home: homePath, excluding: named)
        findings += projectFindings
        if let home = staticFindNode(path: homePath, under: root) {
            var aggregates: [String: (bytes: Int64, newest: Date)] = [:]
            for child in home.children where child.isDirectory && child.atlasEntryID == nil {
                aggregates[child.path] = (child.allocatedBytes, child.lastTouched ?? .distantPast)
            }
            findings += Lens.ghosts(dirNewest: aggregates, installDate: LensPass.installDate(),
                                    excluding: named + projectFindings.map { ($0.url.path, $0.bytes) })
        }
        findings += LensPass.steamFindings(home: URL(fileURLWithPath: homePath))
        return findings.sorted { $0.kind == $1.kind ? $0.bytes > $1.bytes : $0.kind < $1.kind }
    }

    /// Post-pass (System residue): any unrecognized app cache over 1 GB
    /// under ~/Library/Caches becomes its own regenerable item.
    static func genericCacheItems(homePath: String, root: ScanNode, known: [AtlasItem]) -> [AtlasItem] {
        let cachesPath = homePath + "/Library/Caches"
        guard let cachesNode = staticFindNode(path: cachesPath, under: root) else { return [] }
        let knownPaths = Set(known.map(\.id))
        return cachesNode.children.compactMap { child in
            guard child.isDirectory,
                  child.atlasEntryID == nil,
                  !knownPaths.contains(child.path),
                  child.allocatedBytes >= 1_000_000_000
            else { return nil }
            child.atlasEntryID = "sys.appCache"
            return AtlasItem(
                entryID: "sys.appCache", url: child.url,
                bytes: child.allocatedBytes, lastTouched: child.lastTouched
            )
        }
    }

    /// Homebrew pack completion: formulas keeping more than one version in
    /// the Cellar. The old versions aggregate into one Managed item whose
    /// teach flow is `brew cleanup`; Elbowroom never deletes inside the Cellar.
    /// Version ordering is numeric on the directory name; bytes are a lower
    /// bound (versions small enough to be pruned from the tree are unseen).
    static func brewOldVersionItems(root: ScanNode) -> [AtlasItem] {
        var out: [AtlasItem] = []
        for cellarPath in ["/opt/homebrew/Cellar", "/usr/local/Cellar"] {
            guard let cellar = staticFindNode(path: cellarPath, under: root) else { continue }
            var oldBytes: Int64 = 0
            var latestTouch: Date?
            for formula in cellar.children where formula.isDirectory {
                let versions = formula.children.filter { $0.isDirectory }
                guard versions.count >= 2 else { continue }
                let newest = versions.max { a, b in
                    a.name.compare(b.name, options: .numeric) == .orderedAscending
                }
                for version in versions where version !== newest {
                    oldBytes += version.allocatedBytes
                    if let t = version.lastTouched {
                        latestTouch = max(latestTouch ?? t, t)
                    }
                }
            }
            if oldBytes > 100 * 1_000_000 {
                out.append(AtlasItem(
                    entryID: "brew.cellarOld", url: cellar.url,
                    bytes: oldBytes, lastTouched: latestTouch
                ))
            }
        }
        return out
    }

    static func staticFindNode(path: String, under node: ScanNode) -> ScanNode? {
        if node.path == path { return node }
        guard path.hasPrefix(node.path == "/" ? "/" : node.path + "/") else { return nil }
        for child in node.children {
            if let found = staticFindNode(path: path, under: child) { return found }
        }
        return nil
    }

    private func findNode(path: String, under node: ScanNode) -> ScanNode? {
        if node.path == path { return node }
        guard path.hasPrefix(node.path) else { return nil }
        for child in node.children {
            if let found = findNode(path: path, under: child) { return found }
        }
        return nil
    }

    private func applyRepoStaleness(_ items: inout [AtlasItem], state: ScanState) {
        for i in items.indices {
            if let repoPath = state.itemRepo[items[i].id],
               let repo = state.repos[repoPath],
               let stale = repo.maxSourceMTime {
                items[i].lastTouched = stale
            }
        }
    }
}
