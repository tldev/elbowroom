import Foundation

/// One node of the scanned tree. Directories aggregate allocated bytes of their
/// whole subtree; small children collapse into `collapsedCount`/`collapsedBytes`
/// so the tree stays bounded in memory on a full-disk scan.
public final class ScanNode: Identifiable, Hashable {
    public let id: String // standardized path
    public let url: URL
    public let name: String
    public let isDirectory: Bool
    public var allocatedBytes: Int64 = 0
    public var lastTouched: Date?
    public var children: [ScanNode] = []
    public var collapsedCount: Int = 0
    public var collapsedBytes: Int64 = 0
    public weak var parent: ScanNode?
    public var atlasEntryID: String?
    /// Set when this node sits inside a recognized project (nearest `.git` root).
    public var projectName: String?
    public var isDataless = false
    public var isStashed = false

    public init(url: URL, isDirectory: Bool, parent: ScanNode?) {
        self.url = url
        self.id = url.path
        self.name = url.lastPathComponent
        self.isDirectory = isDirectory
        self.parent = parent
    }

    /// Fast-path init for the bulk walk: builds the URL with the directory
    /// hint so Foundation never stats the path to find out.
    public convenience init(path: String, isDirectory: Bool, parent: ScanNode?) {
        self.init(url: URL(fileURLWithPath: path, isDirectory: isDirectory),
                  isDirectory: isDirectory, parent: parent)
    }

    public var path: String { url.path }

    /// Sort children biggest-first; deterministic tie-break by name (stability).
    public func sortChildren() {
        children.sort {
            if $0.allocatedBytes != $1.allocatedBytes { return $0.allocatedBytes > $1.allocatedBytes }
            return $0.name < $1.name
        }
        for c in children { c.sortChildren() }
    }

    public static func == (lhs: ScanNode, rhs: ScanNode) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
