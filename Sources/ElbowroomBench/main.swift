import Foundation
import ElbowroomKit

/// Dev-only benchmark harness for the scan engine. Not shipped.
///
///   elbowroom-bench gen <path> [--files N]     build a synthetic dev-home fixture
///   elbowroom-bench scan <path> [--iters N]    time full scans of a tree
///   elbowroom-bench dircheck <path>            compare bulk and FileManager reads
///   elbowroom-bench scanfp <path> <outfile>     write a scan fingerprint
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

func timedScan(root: URL) async throws -> (ScanResult, Double) {
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
    let mb = Double(result.scannedBytes) / 1e6
    print(String(format: "  %.3fs  bytes=%.1fMB items=%d findings=%d denied=%d events=%d",
                 dt, mb, result.items.count, result.lensFindings.count,
                 result.deniedPaths.count, events))
    return (result, dt)
}

func summarize(_ label: String, _ times: [Double]) {
    let best = times.min() ?? 0
    let avg = times.reduce(0, +) / Double(max(1, times.count))
    print(String(format: "%@: best %.3fs  avg %.3fs  (n=%d)", label, best, avg, times.count))
}

// MARK: - Result fingerprint (regression comparisons)

/// /private/tmp and /tmp (same for /var) are one place with two spellings;
/// FileManager children can come back canonical while the standardized
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
    func walk(_ n: ScanNode) {
        lines.append("node \(n.path) b=\(n.allocatedBytes) c=\(n.collapsedCount) cb=\(n.collapsedBytes) atlas=\(n.atlasEntryID ?? "-") dl=\(n.isDataless)")
        for c in n.children { walk(c) }
    }
    walk(r.root)
    return lines.map(normalizePrefix)
}

// MARK: - Main

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: elbowroom-bench gen|scan|dircheck|scanfp|metrics <path> [--files N] [--iters N]")
    exit(1)
}
let mode = args[1]
let path = (args[2] as NSString).expandingTildeInPath
let root = URL(fileURLWithPath: path)

func flag(_ name: String, default def: Int) -> Int {
    if let i = args.firstIndex(of: name), i + 1 < args.count, let v = Int(args[i + 1]) { return v }
    return def
}

do {
    switch mode {
    case "gen":
        var gen = FixtureGen(root: root)
        gen.run(targetFiles: flag("--files", default: 100_000))
    case "scan":
        let iters = max(1, flag("--iters", default: 3))
        var times: [Double] = []
        for i in 0..<iters {
            print("iter \(i + 1)/\(iters)")
            let (_, dt) = try await timedScan(root: root)
            times.append(dt)
        }
        summarize("scan \(root.path)", times)
    case "metrics":
        let iterations = max(1, flag("--iters", default: 5))
        let count = max(1, flag("--items", default: 10_000))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("elbowroom-metrics-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = directory.appendingPathComponent("scan-cache.json")
        var fixture = Fixtures.scanResult()
        fixture.items = (0..<count).map { index in
            AtlasItem(entryID: "js.nodeModules", url: URL(fileURLWithPath: "/fixture/project-\(index)/node_modules"),
                      bytes: Int64(count - index) * 4096, lastTouched: .distantPast, projectName: "project-\(index)")
        }
        func measure(_ phase: String, _ work: () -> Void) {
            var times: [Double] = []
            for _ in 0..<iterations {
                let start = DispatchTime.now().uptimeNanoseconds
                work()
                times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
            }
            times.sort()
            print(String(format: "%@: median %.3fms p95 %.3fms (n=%d)", phase,
                         times[times.count / 2], times[min(times.count - 1, Int(Double(times.count) * 0.95))], times.count))
        }
        print("inventory rows: \(count)")
        measure("cache.save") { ScanCache.save(fixture, rootPath: root.path, to: cache) }
        measure("cache.load") { precondition(ScanCache.load(rootPath: root.path, from: cache)?.items.count == count) }
        measure("ledger.project-sort") { precondition(LedgerProjection.rows(items: fixture.items).count == count) }
        measure("ledger.search-sort") { precondition(!LedgerProjection.rows(items: fixture.items, search: "project-1").isEmpty || count == 1) }
        measure("treemap.layout") {
            let slices = Treemap.slices(of: fixture.root)
            _ = Treemap.layout(items: slices.map { ($0.id, $0.bytes) }, in: CGRect(x: 0, y: 0, width: 1080, height: 600))
        }
        print("scan (first run, then warm repeats; OS caches are not flushed):")
        for _ in 0..<iterations { _ = try await timedScan(root: root) }
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        print(String(format: "peak RSS: %.1f MiB", Double(usage.ru_maxrss) / 1_048_576))
    case "dircheck":
        // Per-entry compare: BulkDir.read vs FileManager, recursively.
        var dirs = [root.path]
        var badEntries = 0
        var checkedDirs = 0
        let buf = UnsafeMutableRawBufferPointer.allocate(byteCount: BulkDir.bufferSize, alignment: 16)
        defer { buf.deallocate() }
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
        // Full fingerprint to a file for regression comparisons.
        guard args.count >= 4 else { print("scanfp <path> <outfile>"); exit(1) }
        let (result, dt) = try await timedScan(root: root)
        let out = fingerprint(result).joined(separator: "\n") + "\n"
        try out.write(toFile: args[3], atomically: true, encoding: .utf8)
        print(String(format: "%.3fs → %@", dt, args[3]))
    default:
        print("unknown mode \(mode)")
        exit(1)
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
