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

    /// Full measurement for a background scan, including the tmutil probe.
    public static func capture(for url: URL = URL(fileURLWithPath: "/")) -> DiskSnapshot {
        captureSpace(for: url, snapshotCount: localSnapshotCount())
    }

    /// Capacity only: no subprocess. Preserve the last known snapshot count.
    public static func captureSpace(for url: URL = URL(fileURLWithPath: "/"), snapshotCount: Int = 0) -> DiskSnapshot {
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
            snapshotCount: snapshotCount
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
