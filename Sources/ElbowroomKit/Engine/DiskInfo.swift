import Foundation

/// Boot-volume numbers that must reconcile with Finder's, with purgeable
/// measured and labeled as such.
public struct DiskSnapshot: Sendable, Codable {
    public let volumeName: String
    public let totalCapacity: Int64
    /// Strict free space, `df` style.
    public let available: Int64
    /// Free space counting purgeable, Finder style.
    public let availableForImportant: Int64
    public let snapshotCount: Int
    public let capturedAt: Date

    public var purgeable: Int64 { max(0, availableForImportant - available) }
    public var used: Int64 { max(0, totalCapacity - available) }

    public init(volumeName: String, totalCapacity: Int64, available: Int64,
                availableForImportant: Int64, snapshotCount: Int, capturedAt: Date = Date()) {
        self.volumeName = volumeName
        self.totalCapacity = totalCapacity
        self.available = available
        self.availableForImportant = availableForImportant
        self.snapshotCount = snapshotCount
        self.capturedAt = capturedAt
    }

    public static func capture(for url: URL = URL(fileURLWithPath: "/")) -> DiskSnapshot {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey, .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
        ]
        let values = try? url.resourceValues(forKeys: keys)
        return DiskSnapshot(
            volumeName: values?.volumeName ?? "Macintosh HD",
            totalCapacity: Int64(values?.volumeTotalCapacity ?? 0),
            available: Int64(values?.volumeAvailableCapacity ?? 0),
            availableForImportant: values?.volumeAvailableCapacityForImportantUsage ?? 0,
            snapshotCount: localSnapshotCount()
        )
    }

    /// Count local Time Machine snapshots. Size needs entitlements we lack in
    /// v1, so snapshots surface as a count with a teach flow, never a promise.
    public static func localSnapshotCount() -> Int {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        p.arguments = ["listlocalsnapshots", "/"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
            // Read to EOF before waiting: waiting first deadlocks when the
            // child fills the pipe buffer.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let out = String(data: data, encoding: .utf8) ?? ""
            return out.split(separator: "\n").filter { $0.contains("com.apple.TimeMachine") }.count
        } catch {
            return 0
        }
    }
}

/// External volumes eligible as Stash destinations.
public struct ExternalVolume: Identifiable, Sendable {
    public let id: String
    public let url: URL
    public let name: String
    public let isAPFS: Bool
    public let isInternal: Bool
    public let isNetwork: Bool
    public let available: Int64
    public let totalCapacity: Int64

    public var eligible: Bool { isAPFS && !isInternal && !isNetwork }
    public var ineligibleReason: String? {
        if isNetwork { return Copy.volNetworkNo }
        if isInternal { return Copy.volInternalNo }
        if !isAPFS { return Copy.needsAPFS }
        return nil
    }

    public static func mounted() -> [ExternalVolume] {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeIsInternalKey, .volumeIsLocalKey, .volumeIsBrowsableKey,
            .volumeAvailableCapacityKey, .volumeTotalCapacityKey, .volumeIsRootFileSystemKey,
        ]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]
        ) ?? []
        return urls.compactMap { url in
            guard let v = try? url.resourceValues(forKeys: Set(keys)),
                  v.volumeIsRootFileSystem != true,
                  url.path.hasPrefix("/Volumes/")
            else { return nil }
            var isAPFS = false
            if let fsType = try? url.resourceValues(forKeys: [.volumeTypeNameKey]).volumeTypeName {
                isAPFS = fsType.lowercased().contains("apfs")
            }
            return ExternalVolume(
                id: url.path,
                url: url,
                name: v.volumeName ?? url.lastPathComponent,
                isAPFS: isAPFS,
                isInternal: v.volumeIsInternal ?? false,
                isNetwork: !(v.volumeIsLocal ?? true),
                available: Int64(v.volumeAvailableCapacity ?? 0),
                totalCapacity: Int64(v.volumeTotalCapacity ?? 0)
            )
        }
    }
}
