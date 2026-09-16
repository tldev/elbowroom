import Foundation
import Observation

/// The UI's sole owner of published scan state. Every update replaces a value;
/// background work can retain an older snapshot without sharing mutations.
@MainActor
@Observable
public final class Inventory {
    public private(set) var result: ScanResult?
    public private(set) var revision = 0
    public private(set) var items: [AtlasItem] = []

    public init() {}

    public func replace(with result: ScanResult?) {
        self.result = result
        items = (result?.items ?? []) + (result?.lensFindings ?? [])
            .filter { $0.kind != .stratum }
            .map { AtlasItem(entryID: "lens.found", url: $0.url, bytes: $0.bytes, lastTouched: $0.date) }
        revision += 1
    }

    public func setFindings(_ findings: [LensFinding]) {
        guard var updated = result else { return }
        updated.lensFindings = findings
        replace(with: updated)
    }

    public func updateBytes(_ bytes: Int64, itemID: String, expectedRevision: Int) {
        guard revision == expectedRevision, var updated = result,
              let index = updated.items.firstIndex(where: { $0.id == itemID }) else { return }
        updated.items[index].bytes = bytes
        replace(with: updated)
    }

    public func remove(paths: Set<String>) {
        guard var updated = result else { return }
        func removed(_ path: String) -> Bool {
            paths.contains { path == $0 || path.hasPrefix($0 + "/") }
        }
        updated.items.removeAll { removed($0.url.path) }
        updated.lensFindings.removeAll { removed($0.url.path) }
        updated.root = updated.root.removing(paths: paths)
        replace(with: updated)
    }
}
