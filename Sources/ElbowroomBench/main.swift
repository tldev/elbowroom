import Foundation
import ElbowroomKit

/// Dev-only benchmark harness for the scan engine. Not shipped.
///
///   elbowroom-bench gen <path> [--files N]     build a synthetic dev-home fixture
///   elbowroom-bench scan <path> [--iters N]    time full scans of a tree
///   elbowroom-bench compare <path>             legacy vs current engine, diff results
///
/// The fixture mimics a developer home: repos with node_modules, DerivedData,
/// caches, downloads, deep chains, symlinks — so classification, repo
/// staleness, pruning, and lens fact gathering all exercise real code paths.

// MARK: - Deterministic RNG (stable fixture across runs)

struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

// MARK: - Fixture generation

struct FixtureGen {
    let root: URL
    var rng = SplitMix64(seed: 0xB0770)
    var filesWritten = 0
    let fm = FileManager.default
    /// One shared payload; per-file size comes from writing a prefix slice.
    let payload = Data((0..<8192).map { UInt8(truncatingIfNeeded: $0) })

    mutating func file(_ rel: String, _ bytes: Int) {
        let url = root.appendingPathComponent(rel)
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = Data()
        var remaining = bytes
        while remaining > 0 {
            let n = min(remaining, payload.count)
            data.append(payload.prefix(n))
            remaining -= n
        }
        fm.createFile(atPath: url.path, contents: data)
        filesWritten += 1
        if filesWritten % 20000 == 0 { print("  … \(filesWritten) files") }
    }

    mutating func smallFile(_ rel: String) {
        file(rel, Int(rng.next() % 6000) + 200)
    }

    mutating func run(targetFiles: Int) {
        let scale = max(1, targetFiles / 100_000)
        print("Generating fixture at \(root.path) (~\(targetFiles) files)")
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)

        // 1. Repos: .git, src, node_modules colonies, dist.
        for p in 0..<(12 * scale) {
            let proj = "projects/proj\(p)"
            file("\(proj)/package.json", 800)
            file("\(proj)/.git/config", 400)
            for g in 0..<30 { smallFile("\(proj)/.git/objects/\(g / 10)/obj\(g)") }
            for s in 0..<180 { smallFile("\(proj)/src/mod\(s / 20)/file\(s).ts") }
            for pkg in 0..<55 {
                let base = "\(proj)/node_modules/pkg\(pkg)"
                file("\(base)/package.json", 600)
                for f in 0..<38 { smallFile("\(base)/lib/f\(f).js") }
            }
        }
        // A Rust crate and a Swift package (marker-based classification).
        file("projects/crate/Cargo.toml", 300)
        for f in 0..<2500 { smallFile("projects/crate/target/debug/deps/d\(f).o") }
        file("projects/swifty/Package.swift", 300)
        for f in 0..<1800 { smallFile("projects/swifty/.build/arm64/s\(f).o") }

        // 2. DerivedData-ish builds.
        for app in 0..<(6 * scale) {
            let base = "Library/Developer/Xcode/DerivedData/App\(app)-abcdef\(app)"
            for f in 0..<2400 { smallFile("\(base)/Build/Intermediates.noindex/x\(f / 100)/o\(f).o") }
            file("\(base)/Build/Products/Debug/App\(app).app/bin", 900_000)
        }

        // 3. Caches, app support.
        for c in 0..<(25 * scale) {
            for f in 0..<420 { smallFile("Library/Caches/com.vendor.app\(c)/data/c\(f).db") }
        }
        for a in 0..<(15 * scale) {
            for f in 0..<260 { smallFile("Library/Application Support/App\(a)/store/f\(f)") }
        }

        // 4. Downloads with big files (lens fodder) and installers.
        for d in 0..<300 { smallFile("Downloads/misc/d\(d).txt") }
        for b in 0..<8 { file("Downloads/big-video-\(b).mov", 3_000_000) }
        file("Downloads/Tool.dmg", 2_500_000)
        file("Downloads/archive.zip", 1_200_000)

        // 5. Documents and desktop clutter.
        for f in 0..<2200 { smallFile("Documents/notes/n\(f / 80)/note\(f).md") }
        for f in 0..<200 { smallFile("Desktop/shot\(f).png") }

        // 6. Deep chain (maxDepth exercise) and symlinks.
        var deep = "deep"
        for i in 0..<28 { deep += "/level\(i)" }
        file("\(deep)/bottom.bin", 50_000)
        try? fm.createSymbolicLink(
            at: root.appendingPathComponent("Downloads/link-out"),
            withDestinationURL: URL(fileURLWithPath: "/usr/share/dict")
        )
        try? fm.createSymbolicLink(
            at: root.appendingPathComponent("projects/link-cycle"),
            withDestinationURL: root.appendingPathComponent("projects")
        )

        print("Done: \(filesWritten) files.")
    }
}

// MARK: - Scan timing

@discardableResult
func timedScan(root: URL, quiet: Bool = false) async throws -> (ScanResult, Double) {
    let engine = ScanEngine()
    let t0 = DispatchTime.now()
    var result: ScanResult?
    var events = 0
    for try await event in engine.scan(root: root, home: root) {
        if case .finished(let r) = event { result = r }
        events += 1
    }
    let dt = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e9
    guard let result else { fatalError("scan never finished") }
    if !quiet {
        let mb = Double(result.scannedBytes) / 1e6
        print(String(format: "  %.3fs  bytes=%.1fMB items=%d findings=%d denied=%d events=%d",
                     dt, mb, result.items.count, result.lensFindings.count,
                     result.deniedPaths.count, events))
    }
    return (result, dt)
}

func summarize(_ label: String, _ times: [Double]) {
    let best = times.min() ?? 0
    let avg = times.reduce(0, +) / Double(max(1, times.count))
    print(String(format: "%@: best %.3fs  avg %.3fs  (n=%d)", label, best, avg, times.count))
}

// MARK: - Result fingerprint (equivalence checks between engines)

/// /private/tmp and /tmp (same for /var) are one place with two spellings;
/// legacy FileManager children come back canonical while the standardized
/// root does not. Normalize so the diff shows real divergence only.
func normalizePrefix(_ s: String) -> String {
    s.replacingOccurrences(of: "/private/tmp/", with: "/tmp/")
        .replacingOccurrences(of: "/private/var/", with: "/var/")
}

func fingerprint(_ r: ScanResult) -> [String] {
    var lines: [String] = []
    lines.append("scannedBytes=\(r.scannedBytes)")
    for item in r.items.sorted(by: { ($0.id, $0.entryID) < ($1.id, $1.entryID) }) {
        lines.append("item \(item.entryID) \(item.id) bytes=\(item.bytes) proj=\(item.projectName ?? "-")")
    }
    for f in r.lensFindings.sorted(by: { $0.id < $1.id }) {
        lines.append("lens \(f.kind.rawValue) \(f.url.path) bytes=\(f.bytes) n=\(f.count)")
    }
    for d in r.deniedPaths.sorted() {
        lines.append("denied \(d)")
    }
    func walk(_ n: ScanNode, depth: Int) {
        lines.append("node \(n.path) b=\(n.allocatedBytes) c=\(n.collapsedCount) cb=\(n.collapsedBytes) atlas=\(n.atlasEntryID ?? "-") dl=\(n.isDataless)")
        for c in n.children { walk(c, depth: depth + 1) }
    }
    walk(r.root, depth: 0)
    return lines.map(normalizePrefix)
}

// MARK: - Main

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: elbowroom-bench gen|scan|compare <path> [--files N] [--iters N]")
    exit(1)
}
let mode = args[1]
let path = (args[2] as NSString).expandingTildeInPath
let root = URL(fileURLWithPath: path)

func flag(_ name: String, default def: Int) -> Int {
    if let i = args.firstIndex(of: name), i + 1 < args.count, let v = Int(args[i + 1]) { return v }
    return def
}

let sema = DispatchSemaphore(value: 0)
Task {
    switch mode {
    case "gen":
        var gen = FixtureGen(root: root)
        gen.run(targetFiles: flag("--files", default: 100_000))
    case "scan":
        let iters = flag("--iters", default: 3)
        var times: [Double] = []
        for i in 0..<iters {
            print("iter \(i + 1)/\(iters)")
            let (_, dt) = try await timedScan(root: root)
            times.append(dt)
        }
        summarize("scan \(root.path)", times)
    case "compare":
        setenv("ELBOWROOM_SCAN_LEGACY", "1", 1)
        print("legacy engine:")
        let (legacy, lt) = try await timedScan(root: root)
        unsetenv("ELBOWROOM_SCAN_LEGACY")
        print("current engine:")
        let (fast, ft) = try await timedScan(root: root)
        let a = fingerprint(legacy), b = fingerprint(fast)
        let sa = Set(a), sb = Set(b)
        let onlyA = a.filter { !sb.contains($0) }, onlyB = b.filter { !sa.contains($0) }
        print(String(format: "legacy %.3fs → current %.3fs  (%.2fx)", lt, ft, lt / ft))
        if onlyA.isEmpty && onlyB.isEmpty {
            print("results IDENTICAL (\(a.count) fingerprint lines)")
        } else {
            print("DIFFERENCES — only in legacy: \(onlyA.count), only in current: \(onlyB.count)")
            for l in onlyA.prefix(40) { print("  L \(l)") }
            for l in onlyB.prefix(40) { print("  C \(l)") }
        }
    case "dircheck":
        // Per-entry compare: BulkDir.read vs FileManager, recursively.
        var dirs = [root.path]
        var badEntries = 0
        var checkedDirs = 0
        let buf = UnsafeMutableRawBufferPointer.allocate(byteCount: BulkDir.bufferSize, alignment: 16)
        while let dir = dirs.popLast() {
            checkedDirs += 1
            var bulk: [BulkEntry] = []
            var fmgr: [BulkEntry] = []
            try? BulkDir.read(path: dir, buffer: buf, into: &bulk)
            try? BulkDir.readViaFileManager(path: dir, into: &fmgr)
            let bulkByName = Dictionary(uniqueKeysWithValues: bulk.map { ($0.name, $0) })
            let fmByName = Dictionary(uniqueKeysWithValues: fmgr.map { ($0.name, $0) })
            for name in Set(bulkByName.keys).union(fmByName.keys).sorted() {
                let b = bulkByName[name]
                let f = fmByName[name]
                if b == nil || f == nil || b!.allocated != f!.allocated || b!.isDirectory != f!.isDirectory || b!.isSymlink != f!.isSymlink {
                    badEntries += 1
                    if badEntries <= 25 {
                        func d(_ e: BulkEntry?) -> String {
                            guard let e else { return "MISSING" }
                            return "dir=\(e.isDirectory) ln=\(e.isSymlink) alloc=\(e.allocated) logical=\(e.logical)"
                        }
                        print("ENTRY \(dir)/\(name)\n  bulk: \(d(b))\n  fmgr: \(d(f))")
                    }
                }
                if let b, b.isDirectory, !b.isSymlink { dirs.append(dir + "/" + name) }
            }
        }
        print("checked \(checkedDirs) dirs, \(badEntries) differing entries")
    case "scanfp":
        // Full fingerprint to a file (engine picked via ELBOWROOM_SCAN_LEGACY).
        guard args.count >= 4 else { print("scanfp <path> <outfile>"); exit(1) }
        let (result, dt) = try await timedScan(root: root)
        let out = fingerprint(result).joined(separator: "\n") + "\n"
        try out.write(toFile: args[3], atomically: true, encoding: .utf8)
        print(String(format: "%.3fs → %@", dt, args[3]))
    default:
        print("unknown mode \(mode)")
        exit(1)
    }
    sema.signal()
}
sema.wait()
