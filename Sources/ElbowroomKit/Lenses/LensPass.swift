import Foundation

/// The scan is the only walk. These are the lens post-pass's small data
/// sources — installed apps, the Mac's birth date, the twin hash, Steam's
/// manifests — called by ScanEngine.lensFindings. Zero writes.
public enum LensPass {
    /// Library bundles the walk never treats as lens territory: their apps
    /// own them.
    public static let sealedSuffixes = [".photoslibrary", ".musiclibrary", ".tvlibrary", ".aplibrary", ".imovielibrary", ".fcpbundle"]

    static func installedApps() -> [String] {
        let fm = FileManager.default
        let dirs = ["/Applications", NSHomeDirectory() + "/Applications"]
        return dirs.flatMap { dir in
            ((try? fm.contentsOfDirectory(atPath: dir)) ?? [])
                .filter { $0.hasSuffix(".app") }
                .map { String($0.dropLast(4)) }
        }
    }

    /// The boot volume's birth date stands in for "when this Mac began".
    static func installDate() -> Date {
        (try? URL(fileURLWithPath: "/Users").resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
    }

    /// 128 KB from each end; enough to separate same-size strangers.
    static func sampleHash(_ path: String) -> UInt64? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        var hash: UInt64 = 0xcbf29ce484222325
        func mix(_ data: Data) {
            for byte in data {
                hash ^= UInt64(byte)
                hash = hash &* 0x100000001b3
            }
        }
        guard let head = try? handle.read(upToCount: 131_072) else { return nil }
        mix(head)
        if let size = try? handle.seekToEnd(), size > 262_144 {
            try? handle.seek(toOffset: size - 131_072)
            if let tail = try? handle.read(upToCount: 131_072) { mix(tail) }
        }
        return hash
    }

    static func steamFindings(home: URL) -> [LensFinding] {
        let library = home.appendingPathComponent("Library/Application Support/Steam/steamapps").path
        let names = (try? FileManager.default.contentsOfDirectory(atPath: library)) ?? []
        return names
            .filter { $0.hasPrefix("appmanifest_") && $0.hasSuffix(".acf") }
            .compactMap { name in
                guard let text = try? String(contentsOfFile: library + "/" + name, encoding: .utf8) else { return nil }
                return Lens.steamGames(fromACF: text, libraryPath: library)
            }
    }
}
