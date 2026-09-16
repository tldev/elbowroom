import Foundation

/// One node of the scanned tree. Directories aggregate allocated bytes of their
/// whole subtree; small children collapse into `collapsedCount`/`collapsedBytes`
/// so the tree stays bounded in memory on a full-disk scan.
final class ScanNodeBuilder: Identifiable, Hashable {
    let id: String // standardized path
    let url: URL
    let name: String
    let isDirectory: Bool
    var allocatedBytes: Int64 = 0
    var lastTouched: Date?
    var children: [ScanNodeBuilder] = []
    var collapsedCount: Int = 0
    var collapsedBytes: Int64 = 0
    weak var parent: ScanNodeBuilder?
    var atlasEntryID: String?
    var containsClassifiedStorage = false
    /// Set when this node sits inside a recognized project (nearest `.git` root).
    var projectName: String?
    var isDataless = false

    init(url: URL, isDirectory: Bool, parent: ScanNodeBuilder?) {
        self.url = url
        self.id = url.path
        self.name = url.lastPathComponent
        self.isDirectory = isDirectory
        self.parent = parent
    }

    /// Fast-path init for the bulk walk: builds the URL with the directory
    /// hint so Foundation never stats the path to find out.
    convenience init(path: String, isDirectory: Bool, parent: ScanNodeBuilder?) {
        self.init(url: URL(fileURLWithPath: path, isDirectory: isDirectory),
                  isDirectory: isDirectory, parent: parent)
    }

    var path: String { url.path }

    func snapshot() -> ScanNode {
        ScanNode(url: url, isDirectory: isDirectory, allocatedBytes: allocatedBytes,
                 lastTouched: lastTouched, children: children.map { $0.snapshot() },
                 collapsedCount: collapsedCount, collapsedBytes: collapsedBytes,
                 atlasEntryID: atlasEntryID, projectName: projectName, isDataless: isDataless)
    }

    /// Sort children biggest-first; deterministic tie-break by name (stability).
    func sortChildren() {
        children.sort {
            if $0.allocatedBytes != $1.allocatedBytes { return $0.allocatedBytes > $1.allocatedBytes }
            return $0.name < $1.name
        }
        for c in children { c.sortChildren() }
    }

    static func == (lhs: ScanNodeBuilder, rhs: ScanNodeBuilder) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
