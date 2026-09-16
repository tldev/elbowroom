import Foundation
import os

/// Scan engine, fast path. Same walk semantics as the serial FileManager
/// walk (kept for A/B under ELBOWROOM_SCAN_LEGACY=1), but:
///
///  - directories are read with `getattrlistbulk(2)`: name, type, mtime and
///    sizes for hundreds of entries per syscall, no URL/NSURL churn;
///  - independent subtrees walk in parallel on a small worker pool (APFS on
///    SSD serves concurrent readers well; metadata stays hot in the kernel).
///
/// No caching, no sampling, no skipped bytes: every scan is a full, honest
/// walk — the speed comes from doing the same reads with less overhead.

// MARK: - Bulk directory reading

/// One directory entry from getattrlistbulk. Sizes are zero for directories.
public struct BulkEntry {
    public var name: String
    public var isDirectory: Bool
    public var isSymlink: Bool
    public var mtime: Date?
    public var allocated: Int64
    public var logical: Int64
}

public enum BulkDir {
    // Kernel ABI constants (attr/attrlist packing is a stable public ABI).
    private static let cmnReturned: UInt32 = 0x8000_0000
    private static let cmnError: UInt32 = 0x2000_0000
    private static let cmnName: UInt32 = 0x0000_0001
    private static let cmnObjType: UInt32 = 0x0000_0008
    private static let cmnModTime: UInt32 = 0x0000_0400
    private static let fileAllocSize: UInt32 = 0x0000_0004
    private static let fileDataLength: UInt32 = 0x0000_0200
    private static let vdir: UInt32 = 2
    private static let vlnk: UInt32 = 5

    public static let bufferSize = 256 * 1024

    public enum ReadError: Error {
        case openFailed(errno: Int32)   // denied / vanished — caller records
        case unsupported                // odd filesystem — caller falls back
    }

    /// Read a directory in bulk. `buffer` is a reusable ≥ bufferSize scratch
    /// area owned by the calling worker. Entries with per-entry errors are
    /// skipped, matching the legacy walk's `try? resourceValues` skip.
    public static func read(path: String, buffer: UnsafeMutableRawBufferPointer,
                     into entries: inout [BulkEntry]) throws {
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 { throw ReadError.openFailed(errno: errno) }
        defer { close(fd) }

        var al = attrlist()
        al.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        al.commonattr = attrgroup_t(cmnReturned | cmnError | cmnName | cmnObjType | cmnModTime)
        al.fileattr = attrgroup_t(fileAllocSize | fileDataLength)

        while true {
            let n = withUnsafeMutablePointer(to: &al) {
                getattrlistbulk(fd, $0, buffer.baseAddress, buffer.count, 0)
            }
            if n < 0 {
                let err = errno
                if err == EINTR { continue }
                // ENOTSUP/EINVAL: filesystem without bulk support (some FUSE,
                // SMB). Caller re-reads via FileManager.
                if err == ENOTSUP || err == EINVAL { throw ReadError.unsupported }
                throw ReadError.openFailed(errno: err)
            }
            if n == 0 { return }

            var cursor = 0
            let base = buffer.baseAddress!
            for _ in 0..<Int(n) {
                let entryStart = cursor
                let entryLen = Int(base.loadUnaligned(fromByteOffset: entryStart, as: UInt32.self))
                guard entryLen >= 24, entryStart + entryLen <= buffer.count else { return }
                var field = entryStart + 4

                // attribute_set_t: five attrgroup_t words; we use common+file.
                let gotCommon = base.loadUnaligned(fromByteOffset: field, as: UInt32.self)
                let gotFile = base.loadUnaligned(fromByteOffset: field + 12, as: UInt32.self)
                field += 20

                // ATTR_CMN_ERROR rides directly after RETURNED_ATTRS.
                if gotCommon & cmnError != 0 {
                    let err = base.loadUnaligned(fromByteOffset: field, as: UInt32.self)
                    field += 4
                    if err != 0 { cursor = entryStart + entryLen; continue }
                }

                var name: String?
                if gotCommon & cmnName != 0 {
                    let off = Int(base.loadUnaligned(fromByteOffset: field, as: Int32.self))
                    let len = Int(base.loadUnaligned(fromByteOffset: field + 4, as: UInt32.self))
                    let nameStart = field + off
                    if len > 1, nameStart >= 0, nameStart + len <= buffer.count {
                        let bytes = UnsafeRawBufferPointer(start: base + nameStart, count: len - 1)
                        name = String(decoding: bytes, as: UTF8.self)
                    }
                    field += 8
                }

                var objType: UInt32 = 0
                if gotCommon & cmnObjType != 0 {
                    objType = base.loadUnaligned(fromByteOffset: field, as: UInt32.self)
                    field += 4
                }

                var mtime: Date?
                if gotCommon & cmnModTime != 0 {
                    let sec = base.loadUnaligned(fromByteOffset: field, as: Int64.self)
                    let nsec = base.loadUnaligned(fromByteOffset: field + 8, as: Int64.self)
                    mtime = Date(timeIntervalSince1970: Double(sec) + Double(nsec) / 1e9)
                    field += 16
                }

                var allocated: Int64 = 0
                var logical: Int64 = 0
                if gotFile & fileAllocSize != 0 {
                    allocated = base.loadUnaligned(fromByteOffset: field, as: Int64.self)
                    field += 8
                }
                if gotFile & fileDataLength != 0 {
                    logical = base.loadUnaligned(fromByteOffset: field, as: Int64.self)
                    field += 8
                }

                cursor = entryStart + entryLen
                guard let name, !name.isEmpty else { continue }
                entries.append(BulkEntry(
                    name: name,
                    isDirectory: objType == vdir,
                    isSymlink: objType == vlnk,
                    mtime: mtime, allocated: allocated, logical: logical
                ))
            }
        }
    }

    /// Fallback for filesystems without bulk support: same entries via
    /// FileManager, same resource keys as the legacy walk.
    public static func readViaFileManager(path: String, into entries: inout [BulkEntry]) throws {
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .isSymbolicLinkKey,
            .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey,
            .contentModificationDateKey,
        ]
        let urls = try FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: path, isDirectory: true),
            includingPropertiesForKeys: keys, options: []
        )
        for url in urls {
            guard let rv = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            entries.append(BulkEntry(
                name: url.lastPathComponent,
                isDirectory: rv.isDirectory == true,
                isSymlink: rv.isSymbolicLink == true,
                mtime: rv.contentModificationDate,
                allocated: Int64(rv.totalFileAllocatedSize ?? rv.fileAllocatedSize ?? 0),
                logical: Int64(rv.fileSize ?? 0)
            ))
        }
    }
}

// MARK: - Parallel walk

/// One in-flight directory. Owned exclusively by the worker enumerating it;
/// parents are touched only under their own lock via `finalizeIntoParent`.
private final class DirTask {
    let node: ScanNode
    let depth: Int
    let colonyEntry: String?
    let lensEligible: Bool
    /// Nearest enclosing repo whose staleness this subtree's sources update.
    let repo: ParallelScanJob.RepoBox?
    let parent: DirTask?

    /// Guards pending-child count, the merged child mtime, and — for the
    /// parent role — mutation of `node.children` / collapsed tallies.
    let lock = OSAllocatedUnfairLock()
    var pending = 1          // own enumeration sentinel + one per child subtree
    var childrenMax: Date?   // max lastTouched over finalized children
    var fileMax: Date?       // max mtime over direct files (set pre-finalize)

    init(node: ScanNode, depth: Int, colonyEntry: String?, lensEligible: Bool,
         repo: ParallelScanJob.RepoBox?, parent: DirTask?) {
        self.node = node
        self.depth = depth
        self.colonyEntry = colonyEntry
        self.lensEligible = lensEligible
        self.repo = repo
        self.parent = parent
    }
}

final class ParallelScanJob: @unchecked Sendable {
    /// A repo context shared across the subtree's tasks; max source mtime
    /// accumulates under its own lock.
    final class RepoBox: @unchecked Sendable {
        let name: String
        let path: String
        let marker: String
        let node: ScanNode
        let lock = OSAllocatedUnfairLock()
        var maxSourceMTime: Date?
        init(name: String, path: String, marker: String, node: ScanNode) {
            self.name = name
            self.path = path
            self.marker = marker
            self.node = node
        }
        func bump(_ date: Date) {
            lock.lock()
            if maxSourceMTime == nil || date > maxSourceMTime! { maxSourceMTime = date }
            lock.unlock()
        }
    }

    private let rootURL: URL
    private let homePath: String
    private let continuation: AsyncThrowingStream<ScanEvent, Error>.Continuation
    private let started = Date()
    private let workerCount: Int

    // Work queue: LIFO for locality, condition-signalled.
    private let queueCond = NSCondition()
    private var stack: [DirTask] = []
    private var outstanding = 0
    private var cancelled = false
    private var workersAlive = 0
    private var finished = false

    // Shared scan state, each behind its own lock (low-contention groups).
    private let countersLock = OSAllocatedUnfairLock()
    private var itemsScanned = 0
    private var bytesSeen: Int64 = 0
    private var lastProgressReport = 0

    private let stateLock = OSAllocatedUnfairLock()
    private var denied: [String] = []
    private var items: [AtlasItem] = []
    private var repos: [String: RepoBox] = [:]
    private var itemRepo: [String: String] = [:]
    private var tickeredEntries: Set<String> = []

    private let factsLock = OSAllocatedUnfairLock()
    private var facts: [FileFact] = []
    static let factsCap = 400_000

    private var rootTask: DirTask?

    init(root: URL, home: URL,
         continuation: AsyncThrowingStream<ScanEvent, Error>.Continuation) {
        self.rootURL = root.standardizedFileURL
        self.homePath = home.standardizedFileURL.path
        self.continuation = continuation
        // Empirically 4–6 workers saturate APFS metadata reads on Apple
        // Silicon; beyond that kernel-side contention makes scans SLOWER
        // (measured: 6 workers 2.8s over a warm 1.3M-entry home, 8 workers
        // 5.3s, 12 workers 6.6s). More is not better here.
        let env = ProcessInfo.processInfo.environment["ELBOWROOM_SCAN_WORKERS"].flatMap(Int.init)
        self.workerCount = env ?? max(2, min(6, ProcessInfo.processInfo.activeProcessorCount))
    }

    func start() {
        let rootNode = ScanNode(url: rootURL, isDirectory: true, parent: nil)
        let task = DirTask(
            node: rootNode, depth: 0, colonyEntry: nil,
            lensEligible: rootURL.path == homePath, repo: nil, parent: nil
        )
        rootTask = task
        push(task)
        queueCond.lock()
        workersAlive = workerCount
        queueCond.unlock()
        for i in 0..<workerCount {
            let t = Thread { [weak self] in self?.workerLoop() }
            t.name = "elbowroom.scan.\(i)"
            t.qualityOfService = .userInitiated
            t.start()
        }
    }

    func cancel() {
        queueCond.lock()
        cancelled = true
        queueCond.broadcast()
        queueCond.unlock()
    }

    // MARK: Queue

    private func push(_ task: DirTask) {
        queueCond.lock()
        outstanding += 1
        stack.append(task)
        queueCond.signal()
        queueCond.unlock()
    }

    private func pop() -> DirTask? {
        queueCond.lock()
        defer { queueCond.unlock() }
        while true {
            if cancelled { return nil }
            if let task = stack.popLast() { return task }
            if outstanding == 0 { return nil }
            queueCond.wait()
        }
    }

    private func taskDone() {
        queueCond.lock()
        outstanding -= 1
        if outstanding == 0 { queueCond.broadcast() }
        queueCond.unlock()
    }

    private func workerLoop() {
        let buffer = UnsafeMutableRawBufferPointer.allocate(
            byteCount: BulkDir.bufferSize, alignment: 16
        )
        defer { buffer.deallocate() }
        while let task = pop() {
            process(task, buffer: buffer)
            taskDone()
        }
        // Last worker out assembles the result (or reports cancellation).
        queueCond.lock()
        workersAlive -= 1
        let last = workersAlive == 0
        let wasCancelled = cancelled
        queueCond.unlock()
        if last { complete(cancelled: wasCancelled) }
    }

    // MARK: Directory processing (mirrors ScanEngine.walk case by case)

    private func process(_ task: DirTask, buffer: UnsafeMutableRawBufferPointer) {
        let node = task.node
        let path = node.path
        var entries: [BulkEntry] = []
        entries.reserveCapacity(64)
        do {
            do {
                try BulkDir.read(path: path, buffer: buffer, into: &entries)
            } catch BulkDir.ReadError.unsupported {
                entries.removeAll(keepingCapacity: true)
                try BulkDir.readViaFileManager(path: path, into: &entries)
            }
        } catch {
            // A dir that vanished between listing and open is not a denial:
            // there is nothing there to read. Real denials (EACCES/EPERM)
            // drive the FDA chip, so keep them honest.
            if case BulkDir.ReadError.openFailed(let err) = error,
               err == ENOENT || err == ENOTDIR {
                finalizeSelf(task)
                return
            }
            stateLock.lock()
            denied.append(path)
            stateLock.unlock()
            finalizeSelf(task)
            return
        }

        // Repo marker from the listing already in hand — no extra stat.
        var repo = task.repo
        if task.depth > 0, task.colonyEntry == nil,
           let marker = ScanEngine.projectMarker(names: entries.lazy.map(\.name)) {
            let box = RepoBox(name: node.name, path: path, marker: marker, node: node)
            stateLock.lock()
            repos[path] = box
            stateLock.unlock()
            repo = box
        }

        var siblingNames: Set<String>?
        var directBytes: Int64 = 0
        var localScanned = 0
        var localBytes: Int64 = 0
        var localFacts: [FileFact] = []
        var lastPath = path
        var checkCounter = 0

        for entry in entries {
            checkCounter += 1
            if checkCounter & 1023 == 0, isCancelled() { break }

            let childPath = path == "/" ? "/" + entry.name : path + "/" + entry.name
            if task.depth == 0 {
                if path == "/" && entry.name.hasPrefix(".") { continue }
            }
            if ScanEngine.rootSkips.contains(childPath) { continue }
            lastPath = childPath

            if entry.isSymlink {
                // Never follow symlinks out of scope; counts as an item.
                localScanned += 1
                continue
            }

            if entry.isDirectory {
                let childNode = ScanNode(path: childPath, isDirectory: true, parent: node)
                var childColony = task.colonyEntry
                if childColony == nil {
                    if siblingNames == nil, Atlas.needsSiblings(entry.name) {
                        siblingNames = Set(entries.lazy.map(\.name))
                    }
                    let matched = Atlas.classify(path: childPath, home: homePath)
                        ?? Atlas.classify(name: entry.name, parentPath: path, home: homePath, siblings: siblingNames)
                    if let matched {
                        childNode.atlasEntryID = matched
                        childColony = matched
                    }
                }
                let lowerName = entry.name.lowercased()
                let childEligible: Bool
                if task.lensEligible {
                    childEligible = childColony == nil
                        && !(path == homePath && (lowerName == "library" || lowerName == ".trash"))
                        && !LensPass.sealedSuffixes.contains { lowerName.hasSuffix($0) }
                } else {
                    childEligible = childPath == homePath
                }
                let carriesStaleness = childNode.atlasEntryID == nil && !lowerName.hasPrefix(".")
                let childTask = DirTask(
                    node: childNode, depth: task.depth + 1, colonyEntry: childColony,
                    lensEligible: childEligible,
                    repo: carriesStaleness ? repo : nil, parent: task
                )
                task.lock.lock()
                task.pending += 1
                task.lock.unlock()
                if task.depth < ScanEngine.maxDepth {
                    push(childTask)
                } else {
                    // Beyond max depth the child exists but is not entered.
                    finalizeSelf(childTask)
                }
            } else {
                let logical = entry.logical
                let allocated = entry.allocated
                // Dataless (cloud-evicted) files: large logical size, near-zero
                // allocation; mark the folder, count local bytes only.
                if logical > 65_536, allocated < logical / 8 {
                    node.isDataless = true
                }
                // Direct-file bytes accumulate in `directBytes` and land on the
                // node under its lock below: child subtrees finalize into this
                // node concurrently, so an unlocked += here would drop updates.
                directBytes += allocated
                localBytes += allocated
                localScanned += 1
                if task.lensEligible, task.colonyEntry == nil, allocated >= 262_144 {
                    localFacts.append(FileFact(
                        path: childPath, bytes: allocated,
                        modified: entry.mtime ?? .distantPast, isDirectory: false
                    ))
                }
                if let mt = entry.mtime {
                    if task.fileMax == nil || mt > task.fileMax! { task.fileMax = mt }
                    // Source files update repo staleness; artifact colonies don't.
                    if let repo, task.colonyEntry == nil { repo.bump(mt) }
                }
            }

            if localScanned >= 2048 {
                flushCounters(scanned: localScanned, bytes: localBytes, currentPath: childPath)
                localScanned = 0
                localBytes = 0
            }
        }

        if localScanned > 0 || localBytes > 0 {
            flushCounters(scanned: localScanned, bytes: localBytes, currentPath: lastPath)
        }
        if !localFacts.isEmpty { flushFacts(localFacts) }
        if directBytes > 0 {
            task.lock.lock()
            node.allocatedBytes += directBytes
            task.lock.unlock()
        }
        finalizeSelf(task)
    }

    private func isCancelled() -> Bool {
        queueCond.lock()
        defer { queueCond.unlock() }
        return cancelled
    }

    private func flushCounters(scanned: Int, bytes: Int64, currentPath: String) {
        countersLock.lock()
        itemsScanned += scanned
        bytesSeen += bytes
        let emit = itemsScanned - lastProgressReport >= 3000
        if emit { lastProgressReport = itemsScanned }
        let snapshotItems = itemsScanned
        let snapshotBytes = bytesSeen
        countersLock.unlock()
        if emit {
            continuation.yield(.progress(
                itemsScanned: snapshotItems, bytesSeen: snapshotBytes, currentPath: currentPath
            ))
        }
    }

    private func flushFacts(_ newFacts: [FileFact]) {
        factsLock.lock()
        let room = Self.factsCap - facts.count
        if room > 0 { facts.append(contentsOf: newFacts.prefix(room)) }
        factsLock.unlock()
    }

    /// A task's own enumeration is complete (or was skipped): drop the
    /// sentinel; if the subtree is already quiet, seal the node upward.
    private func finalizeSelf(_ task: DirTask) {
        task.lock.lock()
        task.pending -= 1
        let done = task.pending == 0
        task.lock.unlock()
        if done { seal(task) }
    }

    /// Node complete: fix lastTouched, then merge into the parent under the
    /// parent's lock — aggregation, atlas item, prune-or-attach — and
    /// propagate completion up the spine iteratively.
    private func seal(_ start: DirTask) {
        var task: DirTask? = start
        while let t = task {
            t.node.lastTouched = maxDate(t.fileMax, t.childrenMax)
            guard let parent = t.parent else { rootSealed(); return }

            let node = t.node
            parent.lock.lock()
            parent.node.allocatedBytes += node.allocatedBytes
            if let ct = node.lastTouched {
                if parent.childrenMax == nil || ct > parent.childrenMax! {
                    parent.childrenMax = ct
                }
            }
            // Prune: small children collapse into the pebble pile.
            if node.allocatedBytes >= ScanEngine.keepThreshold || parent.depth < 1 || node.atlasEntryID != nil {
                parent.node.children.append(node)
            } else {
                parent.node.collapsedCount += 1 + node.collapsedCount + node.children.count
                parent.node.collapsedBytes += node.allocatedBytes
            }
            parent.lock.unlock()

            if t.lensEligible {
                factsLock.lock()
                if facts.count < Self.factsCap {
                    facts.append(FileFact(
                        path: node.path, bytes: node.allocatedBytes,
                        modified: node.lastTouched ?? .distantPast, isDirectory: true
                    ))
                }
                factsLock.unlock()
            }

            if let entryID = node.atlasEntryID {
                let repo = parent === rootTask ? nil : effectiveRepo(of: parent)
                var item = AtlasItem(
                    entryID: entryID, url: node.url, bytes: node.allocatedBytes,
                    lastTouched: node.lastTouched, projectName: repo?.name
                )
                node.projectName = repo?.name
                stateLock.lock()
                if let repo { itemRepo[item.id] = repo.path }
                items.append(item)
                let ticker = tickerLine(for: &item)
                stateLock.unlock()
                if let ticker { continuation.yield(.ticker(ticker)) }
            }

            parent.lock.lock()
            parent.pending -= 1
            let parentDone = parent.pending == 0
            parent.lock.unlock()
            task = parentDone ? parent : nil
        }
    }

    /// The repo context the parent's walk frame would hold: the repo rooted
    /// at the parent itself if its listing carried a marker, else the one it
    /// inherited down the spine.
    private func effectiveRepo(of parent: DirTask) -> RepoBox? {
        stateLock.lock()
        let own = repos[parent.node.path]
        stateLock.unlock()
        return own ?? parent.repo
    }

    /// Must be called with stateLock held.
    private func tickerLine(for item: inout AtlasItem) -> String? {
        guard item.bytes >= 500 * 1_000_000,
              !tickeredEntries.contains(item.entryID),
              let template = item.entry.ticker
        else { return nil }
        tickeredEntries.insert(item.entryID)
        return template(ByteFormat.string(item.bytes))
    }

    private func maxDate(_ a: Date?, _ b: Date?) -> Date? {
        switch (a, b) {
        case let (x?, y?): return max(x, y)
        case let (x?, nil): return x
        case let (nil, y?): return y
        default: return nil
        }
    }

    private func rootSealed() {}

    // MARK: Completion (matches the legacy scan()'s post-passes exactly)

    private func complete(cancelled: Bool) {
        queueCond.lock()
        if finished { queueCond.unlock(); return }
        finished = true
        queueCond.unlock()

        if cancelled {
            continuation.finish(throwing: CancellationError())
            return
        }
        guard let rootTask else {
            continuation.finish(throwing: CancellationError())
            return
        }
        let phaseLog = ProcessInfo.processInfo.environment["ELBOWROOM_SCAN_PHASES"] == "1"
        var phaseMark = Date()
        func phase(_ name: String) {
            guard phaseLog else { return }
            let now = Date()
            FileHandle.standardError.write(Data("  [phase] \(name): \(String(format: "%.3f", now.timeIntervalSince(phaseMark)))s\n".utf8))
            phaseMark = now
        }
        if phaseLog {
            FileHandle.standardError.write(Data("  [phase] walk: \(String(format: "%.3f", Date().timeIntervalSince(started)))s (facts=\(facts.count))\n".utf8))
        }
        let rootNode = rootTask.node
        rootNode.sortChildren()
        phase("sortChildren")

        var finalItems = items
        // Rebuildables inherit their repo's source staleness.
        for i in finalItems.indices {
            if let repoPath = itemRepo[finalItems[i].id],
               let repo = repos[repoPath],
               let stale = repo.maxSourceMTime {
                finalItems[i].lastTouched = stale
            }
        }
        finalItems.append(contentsOf: ScanEngine.genericCacheItems(
            homePath: homePath, root: rootNode, known: finalItems
        ))
        finalItems.append(contentsOf: ScanEngine.brewOldVersionItems(root: rootNode))
        phase("cache+brew items")
        ScanEngine.addRuntimeAssetBytes(to: &finalItems)
        phase("runtimeAssets")
        ScanEngine.mergeSimulatorItems(&finalItems, homePath: homePath)
        let disk = DiskSnapshot.capture()
        phase("diskSnapshot")
        // Snapshots ride the items list like everything else; the
        // insight remains only for snapshot-free purgeable space.
        let (snapshotItem, insights) = TMSnapshotCleanup.scanArtifacts(disk: disk)
        if let snapshotItem { finalItems.append(snapshotItem) }
        finalItems.sort {
            $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.id < $1.id
        }
        let classified = finalItems.reduce(Int64(0)) { $0 + $1.bytes }
        let seeds = repos.values.map {
            Lens.ProjectSeed(path: $0.path, marker: $0.marker,
                             bytes: $0.node.allocatedBytes,
                             sourceTouched: $0.maxSourceMTime,
                             fallbackTouched: $0.node.lastTouched)
        }
        let findings = ScanEngine.lensFindings(
            facts: facts, homePath: homePath, root: rootNode,
            projects: seeds, classified: finalItems.map { ($0.id, $0.bytes) }
        )
        phase("lensFindings")
        let result = ScanResult(
            root: rootNode, items: finalItems,
            repoStaleness: repos.mapValues { $0.maxSourceMTime ?? Date.distantPast },
            deniedPaths: denied, disk: disk,
            duration: Date().timeIntervalSince(started),
            insights: insights,
            scannedBytes: bytesSeen,
            classifiedBytes: min(classified, bytesSeen),
            lensFindings: findings
        )
        continuation.yield(.finished(result))
        continuation.finish()
    }
}
