import Foundation

/// The Atlas: the semantic layer. Every recognized item resolves to identity,
/// owner, tier, cost to recreate, and actions.

public enum PackID: String, Codable, CaseIterable, Sendable {
    case xcode, javascript, rust, homebrew, containers, systemResidue, ml
}

public enum TeachFlowID: String, Codable, Sendable, CaseIterable {
    case simulatorRuntimes
    case docker
    case orbstack
    case snapshots
    case purgeable
    case deviceBackups
    case trash
    case timeMachine
    case brewCleanup
}

/// How to phrase what it costs to get an item back. The worst honest case.
public enum CostPolicy: Sendable {
    /// Nothing to say; it just refills (small caches).
    case refills
    /// Tools rebuild it locally; estimate minutes from size.
    case rebuild(secondsPerGB: Double)
    /// It re-downloads; fraction of its size comes over the network.
    case redownload(fraction: Double, tool: String)
    /// Elbowroom never touches it, so no cost line.
    case none
}

public struct AtlasEntry: Identifiable, Sendable {
    public let id: String
    public let pack: PackID
    /// English is the localization key; translation happens on read.
    private let titleKey: String
    private let identityKey: String
    /// Plain-language identity, e.g. "Xcode build products".
    public var title: String { Loc.t(titleKey) }
    /// The one-line explanation a non-expert can read.
    public var identityLine: String { Loc.t(identityKey) }
    public let owner: String
    public let tier: Tier
    /// Appears in the Stash catalog.
    public let stashable: Bool
    public let teachFlow: TeachFlowID?
    public let cost: CostPolicy
    /// Ticker template used during the first scan.
    public let ticker: (@Sendable (String) -> String)?

    public init(
        id: String, pack: PackID, title: String, identityLine: String, owner: String,
        tier: Tier, stashable: Bool = false, teachFlow: TeachFlowID? = nil,
        cost: CostPolicy = .refills, ticker: (@Sendable (String) -> String)? = nil
    ) {
        self.id = id
        self.pack = pack
        self.titleKey = title
        self.identityKey = identityLine
        self.owner = owner
        self.tier = tier
        self.stashable = stashable
        self.teachFlow = teachFlow
        self.cost = cost
        self.ticker = ticker
    }
}

/// A concrete found instance of an Atlas entry: an entry plus a place and a size.
public struct AtlasItem: Identifiable, Hashable {
    public let id: String // path
    public let entryID: String
    public let url: URL
    public var bytes: Int64
    public var lastTouched: Date?
    /// Project (repo) name for rebuildables grouped under a repo root.
    public var projectName: String?
    public var isStashed = false

    public init(entryID: String, url: URL, bytes: Int64, lastTouched: Date?, projectName: String? = nil) {
        self.id = url.path
        self.entryID = entryID
        self.url = url
        self.bytes = bytes
        self.lastTouched = lastTouched
        self.projectName = projectName
    }

    public var entry: AtlasEntry { Atlas.entry(entryID) }

    /// Display name: "acme-web · target" for project-grouped items, the app's
    /// own name for generic caches ("Docker cache"), else the entry title.
    public var displayName: String {
        if let projectName { return "\(projectName) · \(url.lastPathComponent)" }
        if entryID == "sys.appCache" {
            return Copy.appCacheTitle(AppNames.human(fromCacheFolder: url.lastPathComponent))
        }
        // Lens items wear the thing's own name; the generic entry title
        // ("Named by a lens") is a rail, never a face.
        if entryID == "lens.found" { return url.lastPathComponent }
        return entry.title
    }

    /// The honest cost line, or nil when there is nothing to say.
    public func costLine(bytesPerSecond: Double) -> String? {
        switch entry.cost {
        case .refills, .none:
            return nil
        case .rebuild(let secondsPerGB):
            let secs = Double(bytes) / 1_000_000_000 * secondsPerGB
            return Copy.firstRebuildable(ByteFormat.minutes(max(30, secs)))
        case .redownload(let fraction, let tool):
            let dl = Int64(Double(bytes) * fraction)
            let secs = Double(dl) / max(bytesPerSecond, 1_000_000)
            return Copy.costLine(tool: tool, n: ByteFormat.string(dl), t: ByteFormat.minutes(secs))
        }
    }

    public static func == (l: AtlasItem, r: AtlasItem) -> Bool { l.id == r.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
