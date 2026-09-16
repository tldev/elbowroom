import Foundation

/// Trim a Photos library's local thumbnails. Research-backed mechanics:
/// `resources/derivatives` holds only derived data — Photos regenerates
/// thumbnails from originals (or from iCloud on an optimized library), so
/// there is no loss case, only regeneration cost: browsing is slower until
/// thumbnails rebuild, and an optimized library may re-download photos to
/// rebuild them. The database and analysis caches are never offered; their
/// regeneration is expensive and they are not Elbowroom's to move. One gate:
/// Photos must not be running. Trash-first like every reclaim.
///
/// The whole library appears as a second, never-pre-checked plan item, but
/// only when the library verifiably syncs with iCloud Photos. Deleting the
/// local library never deletes from iCloud (only in-app deletion syncs);
/// the loss case is photos not yet uploaded, and the entry's identity line
/// says so. With no sync, the library is the only copy and the option
/// never appears.
public enum PhotosTrim {

    public static let photosBundleID = "com.apple.Photos"

    /// Library-scoped iCloud gate: fresh CPL sync state means the library
    /// syncs. The account plist is not trusted for this: on a Mac whose
    /// library was syncing live (cloudsync.noindex touched the same hour),
    /// MobileMeAccounts still read Enabled=false for the Photos dataclass
    /// (July 2026). Absent or stale state means refuse.
    public static func cloudSyncActive(libraryURL: URL, now: Date = Date(), fm: FileManager = .default) -> Bool {
        let sync = libraryURL.appendingPathComponent("resources/cpl/cloudsync.noindex")
        guard let attrs = try? fm.attributesOfItem(atPath: sync.path),
              let modified = attrs[.modificationDate] as? Date else { return false }
        return now.timeIntervalSince(modified) < 30 * 86_400
    }

    /// The trimmable piece, plus the whole library where the gate allows.
    /// `wholeLibraryEligible` defaults to false so nothing destructive is
    /// offered unless the caller checked the gate.
    public static func planItems(libraryURL: URL, sizer: (String) -> Int64,
                                 wholeLibraryEligible: Bool = false) -> [AtlasItem] {
        var out: [AtlasItem] = []
        let derivatives = libraryURL.appendingPathComponent("resources/derivatives", isDirectory: true)
        if FileManager.default.fileExists(atPath: derivatives.path) {
            let bytes = sizer(derivatives.path)
            if bytes > 0 {
                out.append(AtlasItem(entryID: "sys.photosDerivatives", url: derivatives, bytes: bytes, lastTouched: nil))
            }
        }
        if wholeLibraryEligible {
            let bytes = sizer(libraryURL.path)
            if bytes > 0 {
                out.append(AtlasItem(entryID: "sys.photosLibraryWhole", url: libraryURL, bytes: bytes, lastTouched: nil))
            }
        }
        return out
    }
}
