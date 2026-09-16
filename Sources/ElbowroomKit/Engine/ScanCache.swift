import Foundation

/// The last scan persists to disk, so a relaunch restores instantly instead of
/// walking the volume again. A fresh scan runs only when the user asks or the
/// FSEvents watcher sees real changes settle.

extension ScanNode: Codable {
    private enum CodingKeys: String, CodingKey {
        case path, isDirectory, allocatedBytes, lastTouched, children
        case collapsedCount, collapsedBytes, atlasEntryID, projectName
        case isDataless
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let isDirectory = try c.decode(Bool.self, forKey: .isDirectory)
        self.init(
            url: URL(fileURLWithPath: try c.decode(String.self, forKey: .path), isDirectory: isDirectory),
            isDirectory: isDirectory,
            allocatedBytes: try c.decode(Int64.self, forKey: .allocatedBytes),
            lastTouched: try c.decodeIfPresent(Date.self, forKey: .lastTouched),
            children: try c.decode([ScanNode].self, forKey: .children),
            collapsedCount: try c.decode(Int.self, forKey: .collapsedCount),
            collapsedBytes: try c.decode(Int64.self, forKey: .collapsedBytes),
            atlasEntryID: try c.decodeIfPresent(String.self, forKey: .atlasEntryID),
            projectName: try c.decodeIfPresent(String.self, forKey: .projectName),
            isDataless: try c.decode(Bool.self, forKey: .isDataless)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(path, forKey: .path)
        try c.encode(isDirectory, forKey: .isDirectory)
        try c.encode(allocatedBytes, forKey: .allocatedBytes)
        try c.encodeIfPresent(lastTouched, forKey: .lastTouched)
        try c.encode(collapsedCount, forKey: .collapsedCount)
        try c.encode(collapsedBytes, forKey: .collapsedBytes)
        try c.encodeIfPresent(atlasEntryID, forKey: .atlasEntryID)
        try c.encodeIfPresent(projectName, forKey: .projectName)
        try c.encode(isDataless, forKey: .isDataless)
        try c.encode(children, forKey: .children)
    }
}

extension AtlasItem: Codable {
    private enum CodingKeys: String, CodingKey {
        case entryID, path, bytes, lastTouched, projectName
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            entryID: try c.decode(String.self, forKey: .entryID),
            url: URL(fileURLWithPath: try c.decode(String.self, forKey: .path)),
            bytes: try c.decode(Int64.self, forKey: .bytes),
            lastTouched: try c.decodeIfPresent(Date.self, forKey: .lastTouched),
            projectName: try c.decodeIfPresent(String.self, forKey: .projectName)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(entryID, forKey: .entryID)
        try c.encode(url.path, forKey: .path)
        try c.encode(bytes, forKey: .bytes)
        try c.encodeIfPresent(lastTouched, forKey: .lastTouched)
        try c.encodeIfPresent(projectName, forKey: .projectName)
    }
}

extension SystemInsight: Codable {
    private enum CodingKeys: String, CodingKey { case entryID, bytes, detail }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            entryID: try c.decode(String.self, forKey: .entryID),
            bytes: try c.decode(Int64.self, forKey: .bytes),
            detail: try c.decode(String.self, forKey: .detail)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(entryID, forKey: .entryID)
        try c.encode(bytes, forKey: .bytes)
        try c.encode(detail, forKey: .detail)
    }
}

extension ScanResult: Codable {
    private enum CodingKeys: String, CodingKey {
        case root, items, repoStaleness, deniedPaths, disk, duration
        case insights, scannedBytes, classifiedBytes, finishedAt, lensFindings, outsideWalkBytes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            root: try c.decode(ScanNode.self, forKey: .root),
            items: try c.decode([AtlasItem].self, forKey: .items),
            repoStaleness: try c.decode([String: Date].self, forKey: .repoStaleness),
            deniedPaths: try c.decode([String].self, forKey: .deniedPaths),
            disk: try c.decode(DiskSnapshot.self, forKey: .disk),
            duration: try c.decode(TimeInterval.self, forKey: .duration),
            insights: try c.decode([SystemInsight].self, forKey: .insights),
            scannedBytes: try c.decode(Int64.self, forKey: .scannedBytes),
            classifiedBytes: try c.decode(Int64.self, forKey: .classifiedBytes),
            finishedAt: try c.decodeIfPresent(Date.self, forKey: .finishedAt),
            lensFindings: try c.decodeIfPresent([LensFinding].self, forKey: .lensFindings) ?? [],
            outsideWalkBytes: try c.decodeIfPresent(Int64.self, forKey: .outsideWalkBytes) ?? 0
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(root, forKey: .root)
        try c.encode(items, forKey: .items)
        try c.encode(repoStaleness, forKey: .repoStaleness)
        try c.encode(deniedPaths, forKey: .deniedPaths)
        try c.encode(disk, forKey: .disk)
        try c.encode(duration, forKey: .duration)
        try c.encode(insights, forKey: .insights)
        try c.encode(scannedBytes, forKey: .scannedBytes)
        try c.encode(outsideWalkBytes, forKey: .outsideWalkBytes)
        try c.encode(classifiedBytes, forKey: .classifiedBytes)
        try c.encode(finishedAt, forKey: .finishedAt)
        try c.encode(lensFindings, forKey: .lensFindings)
    }
}

public enum ScanCache {
    private static let writes = DispatchQueue(label: "elbowroom.scan-cache", qos: .utility)

    /// Enqueued in publication order; each closure owns an independent value.
    public static func enqueueSave(_ result: ScanResult, rootPath: String, to destination: URL? = nil) {
        writes.async { save(result, rootPath: rootPath, to: destination) }
    }

    // 2: lens findings ride the result; older caches predate the
    // post-pass and would restore an inventory with no Personal rows.
    // 3: runtime mounts skipped, asset-store bytes on the runtimes item.
    // 4: one Simulator item.
    // 5: project lens; older caches would restore with no project rows.
    // 6: personal libraries and tool caches; uv data is no longer a cache.
    // 7: app cache components and storage groups.
    static let version = 10

    struct Envelope: Codable {
        let version: Int
        let rootPath: String
        let savedAt: Date
        let result: ScanResult
    }

    static var fileURL: URL {
        ReceiptStore.defaultDirectory().appendingPathComponent("scan-cache.json")
    }

    public static func save(_ result: ScanResult, rootPath: String, to destination: URL? = nil) {
        let fileURL = destination ?? Self.fileURL
        let envelope = Envelope(version: version, rootPath: rootPath, savedAt: Date(), result: result)
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    public static func load(rootPath: String, from source: URL? = nil) -> ScanResult? {
        let fileURL = source ?? Self.fileURL
        guard let data = try? Data(contentsOf: fileURL),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version == version,
              envelope.rootPath == rootPath
        else { return nil }
        return envelope.result
    }

    public static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
