import Foundation

// Local Time Machine snapshots graduate from an
// explainer into a tool-mediated cleanup. tmutil lists them, the sheet shows
// one row per snapshot with the literal delete command, and the notes say
// where the real backup history lives before anything runs. APFS never says
// which snapshot pins how many bytes, so rows carry no per-row size: the
// plan carries the purgeable estimate as "up to", and the receipt records
// the free-space delta actually measured after the run.

public enum TMSnapshotParser {
    /// `tmutil listlocalsnapshots /` → date tokens, oldest first. Lines look
    /// like `com.apple.TimeMachine.2026-07-22-222659.local`. OS-update
    /// snapshots (`com.apple.os.update-…`) belong to the updater, not Time
    /// Machine, and never become rows.
    public static func snapshotTokens(fromOutput text: String) -> [String] {
        text.split(separator: "\n").compactMap { line in
            let s = line.trimmingCharacters(in: .whitespaces)
            guard s.hasPrefix("com.apple.TimeMachine."), s.hasSuffix(".local") else { return nil }
            return String(s.dropFirst("com.apple.TimeMachine.".count).dropLast(".local".count))
        }
        .sorted()
    }

    /// `2026-07-22-222659` → a date in the Mac's own zone, tmutil's format.
    public static func date(fromToken token: String) -> Date? {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd-HHmmss"
        df.locale = Locale(identifier: "en_US_POSIX")
        return df.date(from: token)
    }

    public struct Destination: Sendable {
        public let name: String
        public let isNetwork: Bool
        public init(name: String, isNetwork: Bool) {
            self.name = name
            self.isNetwork = isNetwork
        }
    }

    /// First destination from `tmutil destinationinfo`. A network destination
    /// reads its host from the URL: the NAS's own name says more than the
    /// share name. A local drive reads `Name`. No destination → nil.
    public static func destination(fromOutput text: String) -> Destination? {
        var name: String?, kind: String?, url: String?
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, !parts[1].isEmpty else { continue }
            switch parts[0] {
            case "Name": if name == nil { name = parts[1] }
            case "Kind": if kind == nil { kind = parts[1] }
            case "URL": if url == nil { url = parts[1] }
            default: break
            }
        }
        guard name != nil || url != nil else { return nil }
        let isNetwork = kind == "Network"
        if isNetwork, let url, let host = URL(string: url)?.host {
            // Bonjour hosts read like `goose-nas._smb._tcp.local`; the first
            // label is the human name.
            let short = host.split(separator: ".").first.map(String.init) ?? host
            return Destination(name: short, isNetwork: true)
        }
        return Destination(name: name ?? "", isNetwork: isNetwork)
    }

    /// `tmutil status` → whether a backup is copying right now. Deleting the
    /// reference snapshot mid-backup is the one moment to refuse.
    public static func backupRunning(fromOutput text: String) -> Bool {
        text.contains("Running = 1")
    }

    /// Updater-owned snapshots in the same listing (`com.apple.os.update-…`).
    /// Never rows, but counted so the sheet can say why they stay: nothing
    /// missing without a reason.
    public static func osUpdateCount(fromOutput text: String) -> Int {
        text.split(separator: "\n")
            .count { $0.trimmingCharacters(in: .whitespaces).hasPrefix("com.apple.os.update-") }
    }
}

public enum TMSnapshotCleanup {
    /// One checked row per snapshot under one group header. Every row's argv
    /// is the literal `tmutil deletelocalsnapshots <date>`; bytes stay 0
    /// because the tool does not say, and the estimate rides the plan.
    public static func plan(
        tokens: [String],
        destination: TMSnapshotParser.Destination?,
        purgeableBytes: Int64,
        osUpdateCount: Int = 0,
        now: Date = Date()
    ) -> (actions: [ToolAction], notes: [String], estimatedBytes: Int64?) {
        let actions = tokens.map { token -> ToolAction in
            let made = TMSnapshotParser.date(fromToken: token)
            return ToolAction(
                id: "tm.snapshot.\(token)",
                title: made.map { titleFormatter.string(from: $0) } ?? token,
                detail: made.map { Copy.tmSnapshotMade(RelativeDate.short($0, now: now)) },
                bytes: 0,
                argv: ["deletelocalsnapshots", token],
                checked: true,
                warning: Copy.tmSnapshotWarning,
                groupTitle: Copy.tmGroupTitle
            )
        }
        var notes: [String] = []
        notes.append(destination.map { Copy.tmReassure($0.name) } ?? Copy.tmNoDestination)
        let estimate: Int64? = purgeableBytes > 0 ? purgeableBytes : nil
        if let estimate {
            notes.append(Copy.tmEstimateNote(ByteFormat.string(estimate)))
        }
        if osUpdateCount > 0 {
            notes.append(Copy.tmOSUpdateStays(osUpdateCount))
        }
        return (actions, notes, estimate)
    }

    /// Snapshots are an item like any other, never a special card.
    /// When snapshots exist they claim the purgeable measurement as their
    /// size (the same "up to" the sheet states) and the separate purgeable
    /// explainer stays out, so no byte is counted twice. With no snapshots,
    /// purgeable keeps its own explainer row as before.
    public static func scanArtifacts(disk: DiskSnapshot) -> (item: AtlasItem?, insights: [SystemInsight]) {
        if disk.snapshotCount > 0 {
            let item = AtlasItem(
                entryID: "sys.snapshots",
                url: URL(fileURLWithPath: "/System/Volumes/Data"),
                bytes: max(disk.purgeable, 0),
                lastTouched: nil
            )
            return (item, [])
        }
        if disk.purgeable > 500 * 1_000_000 {
            return (nil, [SystemInsight(entryID: "sys.purgeable", bytes: disk.purgeable, detail: Copy.purgeableExplainer)])
        }
        return (nil, [])
    }

    /// Whether the standing auto-trim should fire: the user asked for it,
    /// snapshots exist and hold meaningful space, and no backup is copying.
    /// macOS has no off switch for local snapshots, so "disabled" is Elbowroom
    /// deleting them each time they reappear.
    public static func shouldAutoThin(
        enabled: Bool,
        snapshotCount: Int,
        purgeableBytes: Int64,
        backupRunning: Bool,
        floorBytes: Int64 = 1_000_000_000
    ) -> Bool {
        enabled && snapshotCount > 0 && purgeableBytes >= floorBytes && !backupRunning
    }

    /// "July 22 at 10:26 PM": the snapshot's moment, in the user's locale.
    static let titleFormatter: DateFormatter = {
        let df = DateFormatter()
        df.setLocalizedDateFormatFromTemplate("MMMM d jm")
        return df
    }()
}
