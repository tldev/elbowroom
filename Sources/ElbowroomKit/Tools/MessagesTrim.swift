import Foundation

/// Trim Messages' local replica without touching iCloud. Research-backed
/// mechanics: with Messages in iCloud on, `~/Library/Messages` is a cache of
/// the CloudKit copy — deleting attachment files in Finder-space does not
/// propagate (only in-app deletion syncs), history stays on every other
/// device, and attachments re-download as old conversations open. Two hard
/// gates before the plan opens: CloudKitSyncingEnabled must be true (with
/// sync off, local is the only copy and Elbowroom refuses), and Messages must
/// not be running. Everything moves through the ordinary trash-first Reclaim
/// plan, so the receipt and 7-day Put Back apply like anywhere else.
public enum MessagesTrim {

    public static let messagesBundleID = "com.apple.MobileSMS"

    /// The one switch the whole flow hangs on. Read from Messages' own
    /// preference domain; absent means off, and off means refuse.
    public static func cloudSyncEnabled(
        read: (String, String) -> Bool? = { domain, key in
            CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? Bool
        }
    ) -> Bool {
        read("com.apple.madrid", "CloudKitSyncingEnabled") ?? false
    }

    /// The two trimmable pieces: received attachments (kept in iCloud) and
    /// the preview thumbnails Messages remakes as it browses. chat.db is
    /// never offered — the history database is not Elbowroom's to move.
    public static func planItems(homePath: String, sizer: (String) -> Int64) -> [AtlasItem] {
        let base = homePath + "/Library/Messages"
        let pieces: [(entryID: String, path: String)] = [
            ("sys.messagesAttachments", base + "/Attachments"),
            ("sys.messagesPreviews", base + "/Caches"),
        ]
        return pieces.compactMap { piece -> AtlasItem? in
            guard FileManager.default.fileExists(atPath: piece.path) else { return nil }
            let bytes = sizer(piece.path)
            guard bytes > 0 else { return nil }
            return AtlasItem(entryID: piece.entryID, url: URL(fileURLWithPath: piece.path), bytes: bytes, lastTouched: nil)
        }
    }
}
