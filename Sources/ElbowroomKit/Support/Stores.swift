import Foundation
import Observation

/// User-tunable settings and the free-tier ledger. UserDefaults-backed.
@Observable
public final class SettingsStore {
    public static let shared = SettingsStore()
    private let d = UserDefaults.standard

    public var soundsOn: Bool { didSet { d.set(soundsOn, forKey: "soundsOn") } }
    public var analyticsOptIn: Bool { didSet { d.set(analyticsOptIn, forKey: "analyticsOptIn") } }
    /// Red-line free-space alert threshold, GB.
    public var freeSpaceThresholdGB: Int { didSet { d.set(freeSpaceThresholdGB, forKey: "freeThresholdGB") } }
    /// Measured once during onboarding, refreshed monthly, overridable.
    public var connectionBytesPerSecond: Double { didSet { d.set(connectionBytesPerSecond, forKey: "connBps") } }
    public var connectionMeasuredAt: Date? { didSet { d.set(connectionMeasuredAt, forKey: "connAt") } }
    /// Full-hash verification for stash moves, off by default.
    public var fullHashVerify: Bool { didSet { d.set(fullHashVerify, forKey: "fullHashVerify") } }
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
    public var paywallDeclinedAt: Date? { didSet { d.set(paywallDeclinedAt, forKey: "paywallDeclined") } }
    /// The review prompt fires once, ever.
    public var reviewAsked: Bool { didSet { d.set(reviewAsked, forKey: "reviewAsked") } }
    public var stewardPausedUntil: Date? { didSet { d.set(stewardPausedUntil, forKey: "stewardPaused") } }
    public var lastProactiveNotification: Date? { didSet { d.set(lastProactiveNotification, forKey: "lastNotif") } }
    /// Evolved: standing consent to delete local Time Machine snapshots
    /// whenever they hold space again. macOS has no off switch of its own.
    public var autoThinSnapshots: Bool { didSet { d.set(autoThinSnapshots, forKey: "autoThinSnapshots") } }

    public init() {
        soundsOn = d.object(forKey: "soundsOn") as? Bool ?? true
        analyticsOptIn = d.object(forKey: "analyticsOptIn") as? Bool ?? false
        freeSpaceThresholdGB = d.object(forKey: "freeThresholdGB") as? Int ?? 15
        connectionBytesPerSecond = d.object(forKey: "connBps") as? Double ?? 12_500_000 // 100 Mbit fallback
        connectionMeasuredAt = d.object(forKey: "connAt") as? Date
        fullHashVerify = d.object(forKey: "fullHashVerify") as? Bool ?? false
        onboardingComplete = d.object(forKey: "onboarded") as? Bool ?? false
        themeOverride = d.string(forKey: "theme")
        let raw = d.object(forKey: "dismissed") as? [String: Double] ?? [:]
        dismissedSuggestions = raw.mapValues { Date(timeIntervalSince1970: $0) }
        grantBookmark = d.data(forKey: "grantBookmark")
        grantIsFullDisk = d.object(forKey: "grantFullDisk") as? Bool ?? false
        fdaRequested = d.object(forKey: "fdaRequested") as? Bool ?? false
        paywallDeclinedAt = d.object(forKey: "paywallDeclined") as? Date
        reviewAsked = d.object(forKey: "reviewAsked") as? Bool ?? false
        stewardPausedUntil = d.object(forKey: "stewardPaused") as? Date
        lastProactiveNotification = d.object(forKey: "lastNotif") as? Date
        autoThinSnapshots = d.object(forKey: "autoThinSnapshots") as? Bool ?? false
    }
}

/// Monetization. Free: 10 GB lifetime reclaim. Pro: one-time unlock.
/// StoreKit wiring is a later pass; the ledger and boundary logic are real.
@Observable
public final class ProStore {
    public static let freeAllowance: Int64 = 10 * 1_000_000_000
    private let d = UserDefaults.standard

    public var isPro: Bool { didSet { d.set(isPro, forKey: "isPro") } }
    public var freeUsedBytes: Int64 { didSet { d.set(freeUsedBytes, forKey: "freeUsed") } }

    public var remainingAllowance: Int64 {
        isPro ? .max : max(0, Self.freeAllowance - freeUsedBytes)
    }
    public var boundaryReached: Bool { !isPro && remainingAllowance <= 0 }

    public init() {
        isPro = d.object(forKey: "isPro") as? Bool ?? false
        freeUsedBytes = (d.object(forKey: "freeUsed") as? NSNumber)?.int64Value ?? 0
    }

    public func recordReclaim(bytes: Int64) {
        if !isPro { freeUsedBytes += bytes }
    }

    public func unlock() { isPro = true }
}
