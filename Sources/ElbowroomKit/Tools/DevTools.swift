import Foundation
import os

// Tool-mediated cleanup. Where a teach flow's command can
// run safely as the logged-in user, Elbowroom runs it itself: preview first from
// the tool's own listing, the literal command shown in the sheet, execution
// off the main thread with a hard timeout, and a receipt after. Teach flows
// remain the fallback when the tool is absent.

public enum DevTool: String, Sendable, CaseIterable {
    case simctl
    case docker
    case brew
    case tmutil
}

/// One checkable line in the cleanup sheet: what goes, how big, the exact
/// argv that removes it. Titles carry data (device names, versions); the
/// surrounding copy comes from the deck.
public struct ToolAction: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String?
    public let bytes: Int64          // 0 = the tool did not say
    public let argv: [String]
    public var checked: Bool
    public var warning: String?
    /// Consecutive actions sharing a group title render under one tri-state
    /// header that checks the whole set at once; the warning then speaks once
    /// from the header instead of repeating per row.
    public var groupTitle: String?

    public init(id: String, title: String, detail: String?, bytes: Int64,
                argv: [String], checked: Bool, warning: String? = nil,
                groupTitle: String? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
        self.bytes = bytes
        self.argv = argv
        self.checked = checked
        self.warning = warning
        self.groupTitle = groupTitle
    }
}

public struct CleanupPlan: Sendable {
    public let tool: DevTool
    public let entryID: String
    public var actions: [ToolAction]
    public var blockedReason: String?
    /// What stays and why, so the sheet's total reconciles against the row
    /// that opened it instead of silently under-delivering.
    public var notes: [String]
    /// When rows carry no per-row size (bytes 0 = the tool did not say), the
    /// plan may still carry an honest upper bound; the Run button then says
    /// "up to" and the receipt records what measurement finds after.
    public var estimatedBytes: Int64?

    public init(tool: DevTool, entryID: String, actions: [ToolAction],
                blockedReason: String? = nil, notes: [String] = [],
                estimatedBytes: Int64? = nil) {
        self.tool = tool
        self.entryID = entryID
        self.actions = actions
        self.blockedReason = blockedReason
        self.notes = notes
        self.estimatedBytes = estimatedBytes
    }

    public var checkedActions: [ToolAction] { actions.filter(\.checked) }
    public var checkedBytes: Int64 { checkedActions.reduce(0) { $0 + $1.bytes } }
    /// The literal lines Elbowroom will run, exactly as a terminal would take them.
    public var commandPreview: String {
        checkedActions
            .map { ToolRunner.displayCommand(tool, $0.argv).joined(separator: " ") }
            .joined(separator: "\n")
    }
}

// MARK: - Runner

/// Allowlisted subprocess execution. Never on the main thread, always with a
/// deadline: a stalled daemon degrades like a stalled drive, it does not hang
/// the app.
public enum ToolRunner {
    public struct Output: Sendable {
        public let stdout: Data
        public let stderr: String
        public let status: Int32
    }

    public enum RunError: LocalizedError {
        case notInstalled
        case timedOut

        public var errorDescription: String? {
            switch self {
            case .notInstalled: Copy.toolMissing
            case .timedOut: Copy.toolTimedOut
            }
        }
    }

    static func candidates(for tool: DevTool) -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        switch tool {
        case .simctl:
            return ["/usr/bin/xcrun"]
        case .docker:
            return [
                "/usr/local/bin/docker",
                "/opt/homebrew/bin/docker",
                home + "/.orbstack/bin/docker",
                "/Applications/Docker.app/Contents/Resources/bin/docker",
            ]
        case .brew:
            return ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        case .tmutil:
            return ["/usr/bin/tmutil"]
        }
    }

    public static func binary(for tool: DevTool) -> String? {
        candidates(for: tool).first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Fast availability probe; no subprocess for docker/brew, one cheap
    /// `xcode-select -p` for simctl (xcrun alone would offer to install the
    /// command-line tools).
    public static func isAvailable(_ tool: DevTool) -> Bool {
        guard let bin = binary(for: tool) else { return false }
        switch tool {
        case .simctl:
            let probe = Process()
            probe.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
            probe.arguments = ["-p"]
            probe.standardOutput = Pipe()
            probe.standardError = Pipe()
            guard (try? probe.run()) != nil else { return false }
            probe.waitUntilExit()
            return probe.terminationStatus == 0
        case .docker:
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let sockets = [
                home + "/.docker/run/docker.sock",
                home + "/.orbstack/run/docker.sock",
                "/var/run/docker.sock",
            ]
            return sockets.contains { FileManager.default.fileExists(atPath: $0) }
        case .brew, .tmutil:
            return !bin.isEmpty
        }
    }

    public static func run(_ tool: DevTool, _ args: [String], timeout: TimeInterval) async throws -> Output {
        guard let bin = binary(for: tool) else { throw RunError.notInstalled }
        return try await run(executable: URL(fileURLWithPath: bin), args: args, timeout: timeout)
    }

    static func run(executable: URL, args: [String], timeout: TimeInterval) async throws -> Output {
        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = executable
            process.arguments = args
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            try process.run()

            let timedOut = OSAllocatedUnfairLock(initialState: false)
            let deadline = DispatchWorkItem {
                guard process.isRunning else { return }
                timedOut.withLock { $0 = true }
                process.terminate()
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
            defer { deadline.cancel() }

            // Drain concurrently: stderr can fill while stdout is still open.
            async let stdoutData = readOutput(from: out)
            async let stderrData = readOutput(from: err)
            let (stdout, stderr) = await (stdoutData, stderrData)
            process.waitUntilExit()

            if timedOut.withLock({ $0 }) { throw RunError.timedOut }
            return Output(
                stdout: stdout,
                stderr: String(data: stderr, encoding: .utf8) ?? "",
                status: process.terminationStatus
            )
        }.value
    }

    private static func readOutput(from pipe: Pipe) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: pipe.fileHandleForReading.readDataToEndOfFile())
            }
        }
    }

    /// The literal command a preview shows for an argv this runner executes.
    public static func displayCommand(_ tool: DevTool, _ args: [String]) -> [String] {
        switch tool {
        case .simctl: ["xcrun"] + args
        case .docker: ["docker"] + args
        case .brew: ["brew"] + args
        case .tmutil: ["tmutil"] + args
        }
    }

}

// MARK: - simctl

public enum SimctlParser {
    public struct Device: Sendable {
        public let udid: String
        public let name: String
        public let isAvailable: Bool
        public let state: String
        public let lastBootedAt: Date?
        public let dataPathSize: Int64?
        public let runtimeIdentifier: String
    }

    public struct Runtime: Sendable {
        public let identifier: String
        public let uuid: String?
        public let version: String
        public let build: String
        public let platform: String
        public let sizeBytes: Int64?
        public let deletable: Bool
        public let state: String
        /// Backing disk image in the OS asset store, when the tool names one.
        public let imagePath: String?
    }

    private static func date(_ s: String?) -> Date? {
        guard let s else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        return fractional.date(from: s) ?? plain.date(from: s)
    }

    /// `xcrun simctl list devices -j`
    public static func devices(fromJSON data: Data) -> [Device] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let byRuntime = root["devices"] as? [String: [[String: Any]]]
        else { return [] }
        var out: [Device] = []
        for (runtime, list) in byRuntime {
            for raw in list {
                guard let udid = raw["udid"] as? String,
                      let name = raw["name"] as? String else { continue }
                out.append(Device(
                    udid: udid,
                    name: name,
                    isAvailable: raw["isAvailable"] as? Bool ?? false,
                    state: raw["state"] as? String ?? "Shutdown",
                    lastBootedAt: date(raw["lastBootedAt"] as? String),
                    dataPathSize: (raw["dataPathSize"] as? NSNumber)?.int64Value,
                    runtimeIdentifier: runtime
                ))
            }
        }
        return out
    }

    /// `xcrun simctl runtime list -j` (dictionary keyed by image UUID)
    public static func runtimes(fromJSON data: Data) -> [Runtime] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var out: [Runtime] = []
        for (uuid, value) in root {
            // Modern simctl puts the image UUID in `identifier` and the
            // human name in `runtimeIdentifier`; older output had only the
            // name. Prefer the name — it feeds every label.
            guard let raw = value as? [String: Any],
                  let identifier = (raw["runtimeIdentifier"] as? String) ?? (raw["identifier"] as? String)
            else { continue }
            let platform = (raw["platformIdentifier"] as? String) ?? identifier
            out.append(Runtime(
                identifier: identifier,
                uuid: uuid,
                version: raw["version"] as? String ?? "",
                build: raw["build"] as? String ?? "",
                platform: platform,
                sizeBytes: (raw["sizeBytes"] as? NSNumber)?.int64Value,
                deletable: raw["deletable"] as? Bool ?? true,
                state: raw["state"] as? String ?? "",
                imagePath: raw["path"] as? String
            ))
        }
        return out
    }
}

public enum SimCleanup {
    static func versionKey(_ v: String) -> [Int] {
        v.split(separator: ".").map { Int($0) ?? 0 }
    }

    /// Runtime rows only (the `xcode.simRuntimes` entry). Superseded runtimes
    /// get plain delete rows (re-downloadable, nothing worth keeping). The
    /// current runtime per platform is still the user's to delete: offered
    /// unchecked with the cost stated plainly, never a locked door. `kept`
    /// names what stays with no row at all, so the sheet reconciles against
    /// the scanned size instead of silently under-delivering.
    public static func runtimePlan(
        runtimes: [SimctlParser.Runtime]
    ) -> (actions: [ToolAction], kept: [SimctlParser.Runtime]) {
        var actions: [ToolAction] = []
        var kept: [SimctlParser.Runtime] = []
        let byPlatform = Dictionary(grouping: runtimes.filter(\.deletable), by: \.platform)
        for (_, group) in byPlatform {
            let sorted = group.sorted { versionKey($0.version).lexicographicallyPrecedes(versionKey($1.version)) }
            guard let newest = sorted.last else { continue }
            for old in sorted.dropLast() {
                actions.append(ToolAction(
                    id: "sim.runtime.\(old.uuid ?? old.identifier)",
                    title: "\(shortPlatform(old.identifier)) \(old.version) (\(old.build))",
                    detail: Copy.simSuperseded("\(shortPlatform(newest.identifier)) \(newest.version)"),
                    bytes: old.sizeBytes ?? 0,
                    argv: ["simctl", "runtime", "delete", old.uuid ?? old.identifier],
                    checked: true
                ))
            }
            actions.append(ToolAction(
                id: "sim.runtime.current.\(newest.uuid ?? newest.identifier)",
                title: "\(shortPlatform(newest.identifier)) \(newest.version) (\(newest.build))",
                detail: Copy.runtimeCurrentDetail(ByteFormat.string(newest.sizeBytes ?? 0)),
                bytes: newest.sizeBytes ?? 0,
                argv: ["simctl", "runtime", "delete", newest.uuid ?? newest.identifier],
                checked: false,
                warning: Copy.runtimeCurrentWarning
            ))
        }
        kept.append(contentsOf: runtimes.filter { !$0.deletable })
        return (actions.sorted { $0.bytes > $1.bytes }, kept)
    }

    /// The runtimes' dyld shared caches: rebuilt automatically on the next
    /// simulator boot, removable through simctl's own verb. Everything under
    /// the row is offered.
    public static func dyldCacheRow(bytes: Int64) -> ToolAction {
        ToolAction(
            id: "sim.dyldCaches", title: Copy.simDyldTitle,
            detail: Copy.simDyldDetail, bytes: bytes,
            argv: ["simctl", "runtime", "dyld_shared_cache", "remove", "--all"],
            checked: false
        )
    }

    static func directorySize(_ path: String) -> Int64 {
        var total: Int64 = 0
        let walk = FileManager.default.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey]
        )
        while case let url as URL = walk?.nextObject() {
            total += Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    /// Device rows only (the `xcode.simDevices` entry): unavailable devices
    /// roll into one `delete unavailable`; available, shut-down devices
    /// get their own unchecked rows. `keptCount` = devices left alone.
    public static func devicePlan(
        devices: [SimctlParser.Device]
    ) -> (actions: [ToolAction], keptCount: Int) {
        var actions: [ToolAction] = []
        var keptCount = 0

        let unavailable = devices.filter { !$0.isAvailable }
        if !unavailable.isEmpty {
            let bytes = unavailable.reduce(Int64(0)) { $0 + ($1.dataPathSize ?? 0) }
            actions.append(ToolAction(
                id: "sim.unavailable",
                title: Copy.simUnavailable(unavailable.count),
                detail: Copy.simUnavailableDetail,
                bytes: bytes,
                argv: ["simctl", "delete", "unavailable"],
                checked: true
            ))
        }

        for device in devices where device.isAvailable {
            let detail = device.lastBootedAt.map { RelativeDate.staleness($0) } ?? Copy.simNeverBooted
            // Every device is offered; only a booted one waits,
            // since simctl cannot delete it mid-run.
            guard device.state != "Booted" else {
                keptCount += 1
                continue
            }
            actions.append(ToolAction(
                id: "sim.device.\(device.udid)",
                title: device.name,
                detail: detail,
                bytes: device.dataPathSize ?? 0,
                argv: ["simctl", "delete", device.udid],
                checked: false
            ))
        }

        let sorted = actions.sorted { $0.bytes > $1.bytes }
        return (sorted, keptCount)
    }

    /// One row for the whole testing device set: clones are byproducts, so
    /// the row ships checked.
    public static func testCloneRow(bytes: Int64) -> ToolAction {
        ToolAction(
            id: "sim.testClones", title: Copy.simTestClones,
            detail: Copy.simTestClonesDetail, bytes: bytes,
            argv: ["simctl", "--set", "testing", "delete", "all"], checked: true
        )
    }

    static func shortPlatform(_ identifier: String) -> String {
        let last = identifier.split(separator: ".").last.map(String.init) ?? identifier
        return last.replacingOccurrences(of: "SimRuntime.", with: "")
            .split(separator: "-").first.map(String.init) ?? last
    }
}

// MARK: - docker

public enum DockerCleanup {
    /// One `{"Type":"Images","Size":"3.2GB","Reclaimable":"1.1GB (34%)"}`
    /// object per line from `docker system df --format {{json .}}`.
    public static func dfRows(fromOutput text: String) -> [String: Int64] {
        var out: [String: Int64] = [:]
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = raw["Type"] as? String,
                  let reclaimable = raw["Reclaimable"] as? String
            else { continue }
            out[type] = parseHumanBytes(reclaimable)
        }
        return out
    }

    /// "1.108GB (34%)" → bytes. Docker prints decimal units.
    public static func parseHumanBytes(_ s: String) -> Int64 {
        let scanner = Scanner(string: s)
        guard let value = scanner.scanDouble() else { return 0 }
        let unit = scanner.scanCharacters(from: .letters)?.uppercased() ?? "B"
        let multiplier: Double
        switch unit {
        case "KB": multiplier = 1_000
        case "MB": multiplier = 1_000_000
        case "GB": multiplier = 1_000_000_000
        case "TB": multiplier = 1_000_000_000_000
        default: multiplier = 1
        }
        return Int64(value * multiplier)
    }

    /// Per-volume rows from `docker system df -v --format {{json .}}`: one
    /// JSON object whose Volumes array carries Name, human Size, and Links;
    /// Links "0" marks a volume no container references. Largest first.
    public static func volumeRows(fromVerboseOutput text: String) -> [(name: String, bytes: Int64)] {
        guard let data = text.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let volumes = raw["Volumes"] as? [[String: Any]]
        else { return [] }
        return volumes.compactMap { volume -> (name: String, bytes: Int64)? in
            guard let name = volume["Name"] as? String,
                  volume["Links"] as? String == "0" else { return nil }
            return (name, parseHumanBytes(volume["Size"] as? String ?? "0B"))
        }
        .sorted { $0.bytes > $1.bytes }
    }

    public static func plan(dfRows rows: [String: Int64], volumes: [(name: String, bytes: Int64)] = []) -> [ToolAction] {
        var actions: [ToolAction] = []
        if let bytes = rows["Containers"] {
            actions.append(ToolAction(
                id: "docker.containers", title: Copy.dockerContainers,
                detail: Copy.dockerContainersDetail, bytes: bytes,
                argv: ["container", "prune", "-f"], checked: bytes > 0
            ))
        }
        if let bytes = rows["Images"] {
            actions.append(ToolAction(
                id: "docker.images", title: Copy.dockerImages,
                detail: Copy.dockerImagesDetail, bytes: bytes,
                argv: ["image", "prune", "--all", "-f"], checked: false,
                warning: Copy.dockerImagesWarning
            ))
        }
        if let bytes = rows["Build Cache"] {
            actions.append(ToolAction(
                id: "docker.builder", title: Copy.dockerBuildCache,
                detail: Copy.dockerBuildCacheDetail, bytes: bytes,
                argv: ["builder", "prune", "-f"], checked: bytes > 0
            ))
        }
        // Volumes are one row each (`volume rm <name>`), never one blanket
        // prune: they carry per-project data and deserve per-project consent.
        // Docker 23+ `volume prune` skips named volumes without --all, which
        // is also why the summary fallback must say --all to match what
        // `system df` promises as reclaimable.
        if volumes.isEmpty, let bytes = rows["Local Volumes"], bytes > 0 {
            actions.append(ToolAction(
                id: "docker.volumes", title: Copy.dockerVolumes,
                detail: Copy.dockerVolumesDetail, bytes: bytes,
                argv: ["volume", "prune", "--all", "-f"], checked: false,
                warning: Copy.dockerVolumesWarning
            ))
        }
        for volume in volumes {
            actions.append(ToolAction(
                id: "docker.volume.\(volume.name)", title: volume.name,
                detail: nil, bytes: volume.bytes,
                argv: ["volume", "rm", volume.name], checked: false,
                warning: Copy.dockerVolumesWarning,
                groupTitle: Copy.dockerVolumes
            ))
        }
        // The maximal lever: docker's own full sweep of everything
        // unused. Never pre-checked; the per-row offers above stay the
        // precise path.
        let sweepBytes = rows.values.reduce(0, +)
        if sweepBytes > 0 {
            actions.append(ToolAction(
                id: "docker.sweep", title: Copy.dockerSweep,
                detail: Copy.dockerSweepDetail, bytes: sweepBytes,
                argv: ["system", "prune", "--all", "--volumes", "--force"],
                checked: false, warning: Copy.dockerVolumesWarning
            ))
        }
        return actions
    }
}

// MARK: - brew

public enum BrewCleanup {
    /// `brew cleanup -n --prune=all` ends with
    /// "==> This operation would free approximately 1.2GB of disk space."
    public static func approximateBytes(fromOutput text: String) -> Int64 {
        guard let range = text.range(of: "free approximately ") else { return 0 }
        let tail = text[range.upperBound...]
        return DockerCleanup.parseHumanBytes(String(tail))
    }

    public static func plan(previewOutput: String) -> [ToolAction] {
        let bytes = approximateBytes(fromOutput: previewOutput)
        guard bytes > 0 || previewOutput.contains("Would remove") else { return [] }
        return [ToolAction(
            id: "brew.cleanup", title: Copy.brewCleanupRow,
            detail: Copy.brewCleanupDetail, bytes: bytes,
            argv: ["cleanup", "--prune=all"], checked: true
        )]
    }
}

// MARK: - Entry mapping

public enum ToolCleanup {
    /// Which tool serves an Atlas entry's cleanup, when installed.
    public static func tool(for entryID: String) -> DevTool? {
        switch entryID {
        case "xcode.simDevices", "xcode.simRuntimes", "xcode.testDevices", "xcode.simulator": .simctl
        case "docker.data", "orbstack.data": .docker
        case "brew.cellarOld": .brew
        case "sys.snapshots": .tmutil
        default: nil
        }
    }

    /// Managed entries that are safe to route through the ordinary trash-first
    /// reclaim plan instead of a teach flow: self-contained files Finder can
    /// put back.
    public static let directReclaimEntryIDs: Set<String> = ["sys.iosBackups"]
}
