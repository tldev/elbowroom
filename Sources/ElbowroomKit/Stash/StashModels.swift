import Foundation

/// Manifest schema: version, hostUUID, entries[id, sourcePath, stashPath,
/// bytes, movedAt, status]. The manifest lives at `/<Volume>/Stash/manifest.json`
/// and is journaled before every state transition.

public enum StashEntryStatus: String, Codable, Sendable {
    case copying
    case verifying
    case swapping
    /// The symlink is in; `.elbowroom-orig` still holds the original.
    case committed
    case done
    /// CLEANING failed: space is not freed until the orig deletes.
    case doneDirty
    /// Mirrored bring-back in flight.
    case returning
    /// User kept a local version in a conflict; entry no longer tracked.
    case retired
}

public struct StashEntry: Codable, Identifiable, Sendable {
    public let id: UUID
    public let entryID: String        // Atlas entry
    public let sourcePath: String
    public let stashPath: String
    public var bytes: Int64
    public var movedAt: Date
    public var status: StashEntryStatus
    public var displayName: String

    public init(entryID: String, sourcePath: String, stashPath: String, bytes: Int64, displayName: String) {
        self.id = UUID()
        self.entryID = entryID
        self.sourcePath = sourcePath
        self.stashPath = stashPath
        self.bytes = bytes
        self.movedAt = Date()
        self.status = .copying
        self.displayName = displayName
    }
}

public struct StashManifest: Codable, Sendable {
    public var version: Int
    public var hostUUID: String
    public var hostName: String
    public var entries: [StashEntry]

    public init(hostUUID: String, hostName: String) {
        self.version = 1
        self.hostUUID = hostUUID
        self.hostName = hostName
        self.entries = []
    }
}

public enum StashError: LocalizedError, Equatable {
    case destinationFull(drive: String)
    case appRunning(app: String)
    case sourceDataless
    case verifyMismatch
    case moveFailed
    case notAPFS
    case volumeAbsent

    public var errorDescription: String? {
        switch self {
        case .destinationFull(let drive): Copy.driveFull(drive)
        case .appRunning(let app): Copy.ineligibleRunning(app)
        case .sourceDataless: Copy.stashDatalessNo
        case .verifyMismatch: Copy.verifyFail
        case .moveFailed: Copy.moveFail
        case .notAPFS: Copy.needsAPFS
        case .volumeAbsent: Copy.stashVolumeAbsent
        }
    }
}

/// Which running apps block a move, per Atlas entry (live-checked).
public enum StashRules {
    public static let blockingApps: [String: [(bundleID: String, name: String)]] = [
        "xcode.derivedData": [("com.apple.dt.Xcode", "Xcode")],
        "xcode.spmBuild": [("com.apple.dt.Xcode", "Xcode")],
        "xcode.archives": [("com.apple.dt.Xcode", "Xcode")],
        "xcode.simDevices": [("com.apple.dt.Xcode", "Xcode"), ("com.apple.iphonesimulator", "Simulator")],
        "rust.target": [],
        "rust.cargoRegistry": [],
        "js.nodeModules": [],
        "brew.cache": [],
        "ml.huggingface": [],
        "ml.ollama": [("com.electron.ollama", "Ollama")],
        "ml.lmstudio": [("ai.elementlabs.lmstudio", "LM Studio")],
    ]

    /// Apps whose launch while the drive is absent earns the one allowed
    /// escalation.
    public static func dependentApps(for entryID: String) -> [(bundleID: String, name: String)] {
        blockingApps[entryID] ?? []
    }
}
