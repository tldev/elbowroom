import Foundation

// Lenses: "Everything else" is not one thing, it is a set of recognizable
// shapes. Each lens is a pure detector over FileFact rows gathered by
// LensPass; each answers what it is, what removing costs, and where it goes.

/// One observed file or directory, cheap enough to hold hundreds of thousands.
public struct FileFact: Sendable {
    public let path: String
    public let name: String      // last component, lowercased
    public let ext: String       // lowercased, no dot
    public let bytes: Int64
    public let modified: Date
    public let isDirectory: Bool

    public init(path: String, bytes: Int64, modified: Date, isDirectory: Bool) {
        self.path = path
        let last = (path as NSString).lastPathComponent
        self.name = last.lowercased()
        self.ext = (last as NSString).pathExtension.lowercased()
        self.bytes = bytes
        self.modified = modified
        self.isDirectory = isDirectory
    }

    var parent: String { (path as NSString).deletingLastPathComponent }
}

public enum LensKind: String, CaseIterable, Sendable, Comparable, Codable {
    case mediaHoard, screenRecordings, installer, stratum, downloads, twin, zipShadow
    case project, ghost, vm, weights, game

    private var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    public static func < (l: LensKind, r: LensKind) -> Bool { l.order < r.order }
}

/// One named shape found inside "Everything else". Codable: findings live
/// in the ScanResult and its cache like every other part of the inventory.
public struct LensFinding: Identifiable, Sendable, Codable {
    public let kind: LensKind
    public let url: URL
    public let bytes: Int64
    /// Evidence, per kind: matched app, guest OS hint, parameter hint,
    /// machine name, stratum key ("week"/"month"/"year"/"ancient"), store.
    public let label: String
    /// Photos (media), files (stratum), games' last update year, etc.
    public let count: Int
    public let count2: Int
    /// Newest content date; last booted for VMs; last update for games.
    public let date: Date?
    public let oldest: Date?
    /// The other half of a pair: twin copy, or the zip's expanded folder.
    public let counterpart: URL?
    /// Up to 24 member paths (media samples for the thumbnail riffle).
    public let samples: [String]

    public var id: String { kind.rawValue + "|" + label + "|" + url.path }

    public init(kind: LensKind, url: URL, bytes: Int64, label: String = "",
                count: Int = 0, count2: Int = 0, date: Date? = nil, oldest: Date? = nil,
                counterpart: URL? = nil, samples: [String] = []) {
        self.kind = kind
        self.url = url
        self.bytes = bytes
        self.label = label
        self.count = count
        self.count2 = count2
        self.date = date
        self.oldest = oldest
        self.counterpart = counterpart
        self.samples = samples
    }
}

extension LensFinding {
    /// The name a person knows it by: the game's own title, the VM with its
    /// guest, otherwise the file or folder name.
    public var displayTitle: String {
        switch kind {
        case .game: label
        case .vm: [url.deletingPathExtension().lastPathComponent, label]
            .filter { !$0.isEmpty }.joined(separator: " · ")
        default: url.lastPathComponent
        }
    }

    /// The specific evidence, per kind: counts and years for media, the
    /// matched app for installers, verification for twins. Never generic.
    public var evidenceLine: String {
        switch kind {
        case .mediaHoard, .screenRecordings:
            return Copy.lensMediaLine(count, count2, yearSpan)
        case .installer:
            return Copy.lensInstallerHave(label)
        case .downloads:
            return Copy.lensDownloadsLine(count)
        case .twin:
            return Copy.lensTwinLine
        case .zipShadow:
            return Copy.lensZipLine
        case .project:
            return [Copy.lensProjectKind(label), RelativeDate.staleness(date)]
                .filter { !$0.isEmpty }.joined(separator: " · ")
        case .ghost:
            return Copy.lensGhostLine(RelativeDate.short(date))
        case .vm:
            return Copy.lensVMLine(RelativeDate.short(date))
        case .weights:
            return [label, Copy.lensWeightsLine].filter { !$0.isEmpty }.joined(separator: " · ")
        case .game:
            return Copy.lensGameLine(RelativeDate.short(date))
        case .stratum:
            return ""
        }
    }

    /// The user's Downloads folder itself. Media piles up in it, but it is a
    /// waypoint, not an album: it wears a download face, never the photo fan.
    public static func isDownloadsRoot(_ url: URL?) -> Bool {
        url?.standardizedFileURL.path ==
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path
    }

    public var isDownloadsRoot: Bool { Self.isDownloadsRoot(url) }

    /// Media findings show the thumbnail riffle — except the Downloads root.
    public var wearsMediaFan: Bool {
        (kind == .mediaHoard || kind == .screenRecordings) && !isDownloadsRoot
    }

    public var yearSpan: String {
        guard let newest = date else { return "" }
        let calendar = Calendar.current
        let a = calendar.component(.year, from: oldest ?? newest)
        let b = calendar.component(.year, from: newest)
        return a == b ? String(a) : "\(a)–\(b)"
    }
}

public enum Lens {
    static let photoExts: Set<String> = ["jpg", "jpeg", "heic", "png", "raw", "cr2", "cr3", "nef", "arw", "dng", "tiff", "gif", "webp"]
    static let videoExts: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv", "webm", "mts"]
    static let weightExts: Set<String> = ["gguf", "safetensors", "ckpt", "pt", "mlmodel", "onnx"]
    static let vmFileExts: Set<String> = ["vmdk", "qcow2", "vdi", "iso", "vhdx"]
    static let vmBundleExts: Set<String> = ["utm", "pvm", "vmwarevm"]
    static let archiveExts: Set<String> = ["zip", "tgz", "gz", "tar", "7z", "rar", "xz"]
    static let recordingMarkers = ["screen recording", "screenshot", "zoom_", "obs-", "/zoom/", "meeting recording"]

    // MARK: Media

    /// Files at or over this count as "large" for the Downloads pile.
    static let downloadsLargeFloor: Int64 = 100_000_000

    /// The Downloads folder itself: a waypoint, not an album. It speaks in
    /// large files of any type — direct children only, so subfolder piles
    /// keep their own rows and no byte counts twice.
    public static func downloadsPile(_ facts: [FileFact], downloads: String) -> LensFinding? {
        let big = facts.filter { !$0.isDirectory && $0.parent == downloads && $0.bytes >= downloadsLargeFloor }
        let bytes = big.reduce(Int64(0)) { $0 + $1.bytes }
        guard bytes >= 1_000_000_000 else { return nil }
        return LensFinding(
            kind: .downloads, url: URL(fileURLWithPath: downloads), bytes: bytes,
            count: big.count, date: big.map(\.modified).max(),
            oldest: big.map(\.modified).min()
        )
    }

    /// Folders dense in photos and video: ≥ 60 media files or ≥ 1 GB of them.
    /// Screen-recording folders split out into their own lens. The Downloads
    /// root never qualifies — its story is the downloads pile, not an album.
    public static func mediaHoards(_ facts: [FileFact], downloads: String? = nil) -> [LensFinding] {
        struct Pile { var photos = 0; var videos = 0; var bytes: Int64 = 0
                      var newest = Date.distantPast; var oldest = Date.distantFuture
                      var members: [(path: String, bytes: Int64)] = []; var recording = false }
        var piles: [String: Pile] = [:]
        for f in facts where !f.isDirectory {
            let isPhoto = photoExts.contains(f.ext), isVideo = videoExts.contains(f.ext)
            guard isPhoto || isVideo else { continue }
            var pile = piles[f.parent, default: Pile()]
            if isPhoto { pile.photos += 1 } else { pile.videos += 1 }
            pile.bytes += f.bytes
            pile.newest = max(pile.newest, f.modified)
            pile.oldest = min(pile.oldest, f.modified)
            pile.members.append((f.path, f.bytes))
            if recordingMarkers.contains(where: { f.name.contains($0) || f.path.lowercased().contains($0) }) {
                pile.recording = true
            }
            piles[f.parent] = pile
        }
        return piles.compactMap { path, pile in
            if path == downloads { return nil }
            let count = pile.photos + pile.videos
            guard count >= 60 || pile.bytes >= 1_000_000_000 else { return nil }
            let recording = pile.recording && pile.videos >= pile.photos
            if recording { guard pile.bytes >= 300_000_000 else { return nil } }
            let samples = pile.members.sorted { $0.bytes > $1.bytes }.prefix(24).map(\.path)
            return LensFinding(
                kind: recording ? .screenRecordings : .mediaHoard,
                url: URL(fileURLWithPath: path), bytes: pile.bytes,
                count: pile.photos, count2: pile.videos,
                date: pile.newest, oldest: pile.oldest, samples: Array(samples)
            )
        }
    }

    // MARK: Downloads

    /// Installers whose app is already in /Applications: name tokens of the
    /// dmg/pkg must all appear in some installed app's name.
    public static func installers(_ facts: [FileFact], downloads: String, installedApps: [String]) -> [LensFinding] {
        let apps = installedApps.map { $0.lowercased() }
        let noise: Set<String> = ["installer", "setup", "mac", "macos", "osx", "arm", "amd", "aarch", "universal", "apple", "silicon", "intel", "latest", "install", "release", "stable", "build", "darwin", "final"]
        return facts.compactMap { f in
            guard !f.isDirectory, ["dmg", "pkg"].contains(f.ext), f.parent.hasPrefix(downloads) else { return nil }
            let tokens = f.name.dropLast(f.ext.count + 1)
                .split(whereSeparator: { !$0.isLetter })
                .map(String.init)
                .filter { $0.count > 2 && !noise.contains($0) }
            guard !tokens.isEmpty,
                  let app = apps.first(where: { app in tokens.allSatisfy { app.contains($0) } })
            else { return nil }
            return LensFinding(kind: .installer, url: URL(fileURLWithPath: f.path),
                               bytes: f.bytes, label: displayAppName(app, from: installedApps),
                               date: f.modified)
        }
    }

    private static func displayAppName(_ lowered: String, from apps: [String]) -> String {
        apps.first { $0.lowercased() == lowered } ?? lowered
    }

    /// Downloads by age stratum: week, month, year, ancient.
    public static func strata(_ facts: [FileFact], downloads: String, now: Date) -> [LensFinding] {
        var buckets: [String: (bytes: Int64, count: Int)] = [:]
        for f in facts where !f.isDirectory && f.parent == downloads {
            let age = now.timeIntervalSince(f.modified)
            let key = age <= 7 * 86_400 ? "week" : age <= 30 * 86_400 ? "month"
                    : age <= 365 * 86_400 ? "year" : "ancient"
            buckets[key, default: (0, 0)].bytes += f.bytes
            buckets[key, default: (0, 0)].count += 1
        }
        return buckets.map { key, agg in
            LensFinding(kind: .stratum, url: URL(fileURLWithPath: downloads),
                        bytes: agg.bytes, label: key, count: agg.count)
        }
    }

    // MARK: Pairs

    /// Byte-identical large files in two places. The hash is injected so the
    /// detector stays pure; the real one samples head and tail.
    public static func twins(_ facts: [FileFact], hash: (String) -> UInt64?) -> [LensFinding] {
        let big = facts.filter { !$0.isDirectory && $0.bytes >= 200_000_000 }
        let bySize = Dictionary(grouping: big, by: \.bytes).values.filter { $0.count > 1 }
        var out: [LensFinding] = []
        for group in bySize {
            let hashed = group.compactMap { f in hash(f.path).map { (f, $0) } }
            let byHash = Dictionary(grouping: hashed, by: \.1).values.filter { $0.count > 1 }
            for pair in byHash {
                let sorted = pair.map(\.0).sorted { $0.path < $1.path }
                out.append(LensFinding(kind: .twin, url: URL(fileURLWithPath: sorted[0].path),
                                       bytes: sorted[0].bytes, count: sorted.count,
                                       counterpart: URL(fileURLWithPath: sorted[1].path)))
            }
        }
        return out
    }

    /// An archive still sitting next to its own expanded folder.
    public static func zipShadows(_ facts: [FileFact]) -> [LensFinding] {
        let dirs = Set(facts.filter(\.isDirectory).map(\.path))
        return facts.compactMap { f in
            guard !f.isDirectory, archiveExts.contains(f.ext), f.bytes >= 20_000_000 else { return nil }
            var stem = (f.path as NSString).deletingPathExtension
            if (stem as NSString).pathExtension.lowercased() == "tar" {
                stem = (stem as NSString).deletingPathExtension
            }
            guard dirs.contains(stem) else { return nil }
            return LensFinding(kind: .zipShadow, url: URL(fileURLWithPath: f.path),
                               bytes: f.bytes, counterpart: URL(fileURLWithPath: stem))
        }
    }

    // MARK: Projects

    /// One project root the walk registered: where, which marker named it,
    /// its whole-folder bytes, and when sources (not artifacts) last changed.
    public struct ProjectSeed: Sendable {
        public let path: String
        public let marker: String
        public let bytes: Int64
        public let sourceTouched: Date?
        public let fallbackTouched: Date?

        public init(path: String, marker: String, bytes: Int64,
                    sourceTouched: Date?, fallbackTouched: Date? = nil) {
            self.path = path
            self.marker = marker
            self.bytes = bytes
            self.sourceTouched = sourceTouched
            self.fallbackTouched = fallbackTouched
        }
    }

    /// Home folders a stray manifest must not turn into a "project" wholesale;
    /// repos cloned inside them still qualify.
    static let homeTopNonProjects: Set<String> = [
        "Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures",
        "Public", "Applications",
    ]

    /// Large project folders in the visible home tree. Bytes are net of what
    /// other rows already name inside — build colonies, weights, media piles —
    /// so no byte counts twice in the strip; staleness is the sources', so
    /// artifact churn can't hide a dead project. Nested repos fold into their
    /// outermost root.
    public static func projects(_ seeds: [ProjectSeed], home: String,
                                excluding: [(path: String, bytes: Int64)]) -> [LensFinding] {
        let eligible = seeds.filter { seed in
            guard seed.path.hasPrefix(home + "/") else { return false }
            let parts = seed.path.dropFirst(home.count + 1).split(separator: "/")
            if parts.first == "Library" { return false }
            if parts.count == 1, homeTopNonProjects.contains(String(parts[0])) { return false }
            return !parts.contains { part in
                part.hasPrefix(".") || sealedPart(String(part))
            }
        }.sorted { $0.path < $1.path }

        var out: [LensFinding] = []
        // Roots collected explicitly: "pike-old" sorts between "pike" and
        // "pike/server" ('-' < '/'), so adjacency alone cannot fold nests.
        var roots: [String] = []
        for seed in eligible {
            if roots.contains(where: { seed.path.hasPrefix($0 + "/") }) { continue }
            roots.append(seed.path)
            let itemized = excluding.filter { $0.path.hasPrefix(seed.path + "/") }
                .reduce(Int64(0)) { $0 + $1.bytes }
            let bytes = seed.bytes - itemized
            guard bytes >= 500_000_000 else { continue }
            out.append(LensFinding(
                kind: .project, url: URL(fileURLWithPath: seed.path), bytes: bytes,
                label: seed.marker, date: seed.sourceTouched ?? seed.fallbackTouched
            ))
        }
        return out
    }

    private static func sealedPart(_ part: String) -> Bool {
        let lower = part.lowercased()
        return LensPass.sealedSuffixes.contains { lower.hasSuffix($0) }
    }

    // MARK: Ghosts, VMs, weights

    /// Migration leftovers: telltale names, or folders whose newest content
    /// predates this Mac itself. `excluding` carries what other rows already
    /// name inside these trees (projects, colonies) so no byte counts twice.
    public static func ghosts(dirNewest: [String: (bytes: Int64, newest: Date)], installDate: Date,
                              excluding: [(path: String, bytes: Int64)] = []) -> [LensFinding] {
        let markers = ["relocated items", "from old mac", "(old mac)", "old mac backup", "migrated"]
        return dirNewest.compactMap { path, agg in
            let name = (path as NSString).lastPathComponent.lowercased()
            let marked = markers.contains { name.contains($0) }
            let named = excluding.filter { $0.path.hasPrefix(path + "/") }
                .reduce(Int64(0)) { $0 + $1.bytes }
            let bytes = max(0, agg.bytes - named)
            guard marked || agg.newest < installDate, bytes >= 500_000_000 || marked else { return nil }
            return LensFinding(kind: .ghost, url: URL(fileURLWithPath: path),
                               bytes: bytes, date: agg.newest)
        }
    }

    /// Virtual machines and raw disk images; bundle mtime stands in for the
    /// last boot.
    public static func vms(_ facts: [FileFact]) -> [LensFinding] {
        facts.compactMap { f in
            let bundle = f.isDirectory && vmBundleExts.contains(f.ext)
            let image = !f.isDirectory && vmFileExts.contains(f.ext) && f.bytes >= 2_000_000_000
            guard bundle || image else { return nil }
            let n = f.name
            let guest = n.contains("win") ? "Windows" : n.contains("ubuntu") || n.contains("linux") || n.contains("debian") || n.contains("fedora") ? "Linux"
                      : n.contains("macos") || n.contains("sequoia") || n.contains("sonoma") ? "macOS" : ""
            return LensFinding(kind: .vm, url: URL(fileURLWithPath: f.path),
                               bytes: f.bytes, label: guest, date: f.modified)
        }
    }

    /// Model weights outside any known cache; the parameter count hints from
    /// the filename ("7b", "70b").
    public static func weights(_ facts: [FileFact]) -> [LensFinding] {
        facts.compactMap { f in
            guard !f.isDirectory, weightExts.contains(f.ext), f.bytes >= 500_000_000 else { return nil }
            let param = f.name.split(whereSeparator: { !$0.isNumber && !$0.isLetter })
                .first { $0.count >= 2 && $0.hasSuffix("b") && $0.dropLast().allSatisfy(\.isNumber) }
                .map { $0.uppercased() } ?? ""
            return LensFinding(kind: .weights, url: URL(fileURLWithPath: f.path),
                               bytes: f.bytes, label: param, date: f.modified)
        }
    }

    // MARK: Steam

    /// `appmanifest_*.acf` is Valve KeyValues; name, SizeOnDisk and
    /// LastUpdated read fine with a line scan.
    public static func steamGames(fromACF text: String, libraryPath: String) -> LensFinding? {
        func field(_ key: String) -> String? {
            guard let range = text.range(of: "\"\(key)\"") else { return nil }
            let tail = text[range.upperBound...]
            guard let open = tail.firstIndex(of: "\""),
                  let close = tail[tail.index(after: open)...].firstIndex(of: "\"") else { return nil }
            return String(tail[tail.index(after: open)..<close])
        }
        guard let name = field("name"), let size = field("SizeOnDisk").flatMap({ Int64($0) }),
              size > 0, let dir = field("installdir") else { return nil }
        let updated = field("LastUpdated").flatMap { Double($0) }.map { Date(timeIntervalSince1970: $0) }
        return LensFinding(
            kind: .game,
            url: URL(fileURLWithPath: libraryPath + "/common/" + dir),
            bytes: size, label: name, date: updated
        )
    }
}
