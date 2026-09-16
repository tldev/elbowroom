import Foundation

/// A published tree has no mutable references or parent cycles. The scanner
/// freezes its private builders once; UI edits copy only affected branches.
public struct ScanNode: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let url: URL
    public var name: String { url.lastPathComponent }
    public var path: String { url.path }
    public let isDirectory: Bool
    public let allocatedBytes: Int64
    public let lastTouched: Date?
    public let children: [ScanNode]
    public let collapsedCount: Int
    public let collapsedBytes: Int64
    public let atlasEntryID: String?
    public let projectName: String?
    public let isDataless: Bool

    public init(url: URL, isDirectory: Bool, allocatedBytes: Int64 = 0,
                lastTouched: Date? = nil, children: [ScanNode] = [],
                collapsedCount: Int = 0, collapsedBytes: Int64 = 0,
                atlasEntryID: String? = nil, projectName: String? = nil, isDataless: Bool = false) {
        self.url = url
        self.isDirectory = isDirectory
        self.allocatedBytes = allocatedBytes
        self.lastTouched = lastTouched
        self.children = children
        self.collapsedCount = collapsedCount
        self.collapsedBytes = collapsedBytes
        self.atlasEntryID = atlasEntryID
        self.projectName = projectName
        self.isDataless = isDataless
    }

    public func find(path: String) -> ScanNode? {
        if self.path == path { return self }
        guard path.hasPrefix(self.path == "/" ? "/" : self.path + "/") else { return nil }
        for child in children {
            if let found = child.find(path: path) { return found }
        }
        return nil
    }

    func removing(paths: Set<String>) -> ScanNode {
        var remaining: [ScanNode] = []
        var removed: Int64 = 0
        for child in children {
            if paths.contains(child.path) {
                removed += child.allocatedBytes
            } else if paths.contains(where: { $0.hasPrefix(child.path + "/") }) {
                let updated = child.removing(paths: paths)
                removed += child.allocatedBytes - updated.allocatedBytes
                remaining.append(updated)
            } else {
                remaining.append(child)
            }
        }
        return ScanNode(url: url, isDirectory: isDirectory, allocatedBytes: max(0, allocatedBytes - removed),
                        lastTouched: lastTouched, children: remaining, collapsedCount: collapsedCount,
                        collapsedBytes: collapsedBytes, atlasEntryID: atlasEntryID,
                        projectName: projectName, isDataless: isDataless)
    }

    public static func == (lhs: ScanNode, rhs: ScanNode) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
