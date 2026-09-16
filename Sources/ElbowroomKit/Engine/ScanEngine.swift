import Foundation

/// Scan engine. Enumerates from the granted root with bulk-attribute reads,
/// counts allocated size everywhere, never follows symlinks out of scope, never
/// writes. Builds a pruned tree (small children collapse into pebble counts),
/// classifies against the Atlas during descent, and tracks per-repo staleness.

public enum ScanEvent: Sendable {
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

public struct ScanResult: Sendable {
    public var root: ScanNode
    public var items: [AtlasItem]
    public let repoStaleness: [String: Date]
    public let deniedPaths: [String]
    /// Refreshed on cache restore so the free-space heartbeat stays current.
    public var disk: DiskSnapshot
    public let duration: TimeInterval
    public let insights: [SystemInsight]
    public let scannedBytes: Int64
    public let classifiedBytes: Int64
    /// Named allocations measured separately from the file walk.
    public let outsideWalkBytes: Int64
    public let finishedAt: Date
    /// What the lenses named, part of the one result and its cache.
    public var lensFindings: [LensFinding]

    public var coverage: Double {
        scannedBytes > 0 ? Double(classifiedBytes) / Double(scannedBytes) : 0
    }

    init(root: ScanNode, items: [AtlasItem], repoStaleness: [String: Date],
         deniedPaths: [String], disk: DiskSnapshot, duration: TimeInterval,
         insights: [SystemInsight], scannedBytes: Int64, classifiedBytes: Int64,
         finishedAt: Date? = nil, lensFindings: [LensFinding] = [], outsideWalkBytes: Int64 = 0) {
        self.lensFindings = lensFindings
        self.outsideWalkBytes = outsideWalkBytes
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

    /// Exclude external volumes, virtual filesystems and sibling volumes
    /// measured separately. Data-only system directories use the narrow
    /// traversal policy below so root firmlinks cannot double-count them.
    static let rootSkips: Set<String> = [
        "/Volumes", "/dev", "/Network", "/cores", "/bin", "/sbin",
        "/private/var/vm",
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
    /// Only Data-only locations are entered through /System. The normal root
    /// already exposes Applications, Library, Users and private via firmlinks.
    static let dataOnlyRoots: Set<String> = [
        "System", "macOS Install Data", "MobileSoftwareUpdate",
        ".PreviousSystemInformation", ".DocumentRevisions-V100",
        ".Spotlight-V100", ".fseventsd"
    ]

    static func shouldSkip(path: String) -> Bool {
        if rootSkips.contains(path) { return true }
        let parent = (path as NSString).deletingLastPathComponent
        switch parent {
        // Sealed /usr content is included in the measured System volume.
        // These are the Data firmlinks declared in /usr/share/firmlinks.
        case "/usr": return !["/usr/local", "/usr/libexec", "/usr/share"].contains(path)
        case "/usr/libexec": return path != "/usr/libexec/cups"
        case "/usr/share": return path != "/usr/share/snmp"
        case "/System": return path != "/System/Volumes"
        case "/System/Volumes": return path != "/System/Volumes/Data"
        case "/System/Volumes/Data":
            return !dataOnlyRoots.contains((path as NSString).lastPathComponent)
        default:
            // Runtime images have a separate measurement pass.
            return path == "/System/Volumes/Data" + runtimeAssetStore
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

    /// Run a scan. Events stream out; the stream finishes after `.finished`.
    public func scan(root: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> AsyncThrowingStream<ScanEvent, Error> {
        AsyncThrowingStream { continuation in
            let job = ParallelScanJob(root: root, home: home, continuation: continuation)
            continuation.onTermination = { _ in job.cancel() }
            job.start()
        }
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
    static func lensFindings(facts: [FileFact], homePath: String, root: ScanNodeBuilder,
                             projects: [Lens.ProjectSeed] = [],
                             classified: [(path: String, bytes: Int64)] = []) -> [LensFinding] {
        let namedPaths = Set(classified.map(\.path))
        let facts = facts.filter { fact in
            var path = fact.path
            while path != "/" && !path.isEmpty {
                if namedPaths.contains(path) { return false }
                path = (path as NSString).deletingLastPathComponent
            }
            return true
        }
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

    /// Post-pass (System residue): every retained unrecognized app cache
    /// under ~/Library/Caches becomes its own regenerable item.
    static func genericCacheItems(homePath: String, root: ScanNodeBuilder, known: [AtlasItem]) -> [AtlasItem] {
        let cachesPath = homePath + "/Library/Caches"
        guard let cachesNode = staticFindNode(path: cachesPath, under: root) else { return [] }
        let knownPaths = Set(known.map(\.id))
        return cachesNode.children.compactMap { child in
            guard child.isDirectory,
                  child.atlasEntryID == nil,
                  !knownPaths.contains(child.path),
                  child.allocatedBytes > 0
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
    static func brewOldVersionItems(root: ScanNodeBuilder) -> [AtlasItem] {
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

    static func staticFindNode(path: String, under node: ScanNodeBuilder) -> ScanNodeBuilder? {
        if node.path == path { return node }
        guard path.hasPrefix(node.path == "/" ? "/" : node.path + "/") else { return nil }
        for child in node.children {
            if let found = staticFindNode(path: path, under: child) { return found }
        }
        return nil
    }
}
