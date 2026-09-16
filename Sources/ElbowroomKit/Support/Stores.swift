import Foundation
import Observation

/// User-tunable settings and the free-tier ledger. UserDefaults-backed.
@Observable
public final class SettingsStore {
    public static let shared = SettingsStore()
    private let d: UserDefaults

    public var soundsOn: Bool { didSet { d.set(soundsOn, forKey: "soundsOn") } }
    public var analyticsOptIn: Bool { didSet { d.set(analyticsOptIn, forKey: "analyticsOptIn") } }
    /// Red-line free-space alert threshold, GB.
    public var freeSpaceThresholdGB: Int { didSet { d.set(freeSpaceThresholdGB, forKey: "freeThresholdGB") } }
    /// Measured once during onboarding, refreshed monthly, overridable.
    public var connectionBytesPerSecond: Double { didSet { d.set(connectionBytesPerSecond, forKey: "connBps") } }
    public var connectionMeasuredAt: Date? { didSet { d.set(connectionMeasuredAt, forKey: "connAt") } }
    public var onboardingComplete: Bool { didSet { d.set(onboardingComplete, forKey: "onboarded") } }
    /// "light" or "dark" pins the appearance; nil follows the system.
    public var themeOverride: String? { didSet { d.set(themeOverride, forKey: "theme") } }
    /// Suggestion-card dismissals: entry id -> date (30-day suppression).
    public var dismissedSuggestions: [String: Date] {
        didSet { d.set(dismissedSuggestions.mapValues { $0.timeIntervalSince1970 }, forKey: "dismissed") }
    }
    /// Security-scoped bookmark for the granted scan root.
    public var grantBookmark: Data? { didSet { d.set(grantBookmark, forKey: "grantBookmark") } }
    public var grantIsFullDisk: Bool { didSet { d.set(grantIsFullDisk, forKey: "grantFullDisk") } }
    /// B3: set the moment the user is sent to System Settings for Full
    /// Disk Access, so the quit-and-reopen round trip lands back mid-Grant.
    public var fdaRequested: Bool { didSet { d.set(fdaRequested, forKey: "fdaRequested") } }
    public var stewardPausedUntil: Date? { didSet { d.set(stewardPausedUntil, forKey: "stewardPaused") } }
    /// Evolved: standing consent to delete local Time Machine snapshots
    /// whenever they hold space again. macOS has no off switch of its own.
    public var autoThinSnapshots: Bool { didSet { d.set(autoThinSnapshots, forKey: "autoThinSnapshots") } }
    /// Whether the reclaim plan's Keep in Trash checkbox starts checked.
    /// Chosen during onboarding, changeable in Settings; each plan can
    /// still override it for that run.
    public var keepInTrashDefault: Bool { didSet { d.set(keepInTrashDefault, forKey: "keepInTrashDefault") } }
    /// The app bundle waiting on an App Management grant. macOS applies that
    /// switch only at launch, so the uninstall has to survive the relaunch
    /// and pick itself back up.
    public var pendingUninstallPath: String? { didSet { d.set(pendingUninstallPath, forKey: "pendingUninstall") } }

    public init(defaults: UserDefaults = .standard) {
        d = defaults
        soundsOn = d.object(forKey: "soundsOn") as? Bool ?? true
        analyticsOptIn = d.object(forKey: "analyticsOptIn") as? Bool ?? false
        freeSpaceThresholdGB = d.object(forKey: "freeThresholdGB") as? Int ?? 15
        connectionBytesPerSecond = d.object(forKey: "connBps") as? Double ?? 12_500_000 // 100 Mbit fallback
        connectionMeasuredAt = d.object(forKey: "connAt") as? Date
        onboardingComplete = d.object(forKey: "onboarded") as? Bool ?? false
        themeOverride = d.string(forKey: "theme")
        let raw = d.object(forKey: "dismissed") as? [String: Double] ?? [:]
        dismissedSuggestions = raw.mapValues { Date(timeIntervalSince1970: $0) }
        grantBookmark = d.data(forKey: "grantBookmark")
        grantIsFullDisk = d.object(forKey: "grantFullDisk") as? Bool ?? false
        fdaRequested = d.object(forKey: "fdaRequested") as? Bool ?? false
        stewardPausedUntil = d.object(forKey: "stewardPaused") as? Date
        autoThinSnapshots = d.object(forKey: "autoThinSnapshots") as? Bool ?? false
        keepInTrashDefault = d.object(forKey: "keepInTrashDefault") as? Bool ?? true
        pendingUninstallPath = d.string(forKey: "pendingUninstall")
    }
}
