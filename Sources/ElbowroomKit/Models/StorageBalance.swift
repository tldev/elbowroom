import Foundation

/// Separates missing identities from the difference between readable file
/// allocations and the disk total. The latter is not assumed to be all caches,
/// all protected files, or all filesystem metadata.
public struct StorageBalance: Equatable, Sendable {
    public let readable: Int64
    public let unmeasured: Int64

    public init(used: Int64, scanned: Int64, named: Int64, outsideWalk: Int64) {
        let remaining = max(0, used - named)
        let namedInWalk = max(0, named - outsideWalk)
        readable = min(remaining, max(0, scanned - namedInWalk))
        unmeasured = remaining - readable
    }
}
