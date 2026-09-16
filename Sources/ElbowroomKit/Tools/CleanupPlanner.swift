import Foundation

/// Tool inspection and directory sizing execute outside the UI actor.
public enum CleanupPlanner {
    /// Ask the tool what can go; every row carries the exact argv it would run.
    public static func compose(entryID: String) async -> CleanupPlan {
        guard let tool = ToolCleanup.tool(for: entryID) else {
            return CleanupPlan(tool: .simctl, entryID: entryID, actions: [], blockedReason: Copy.toolMissing)
        }
        func blocked(_ reason: String) -> CleanupPlan {
            CleanupPlan(tool: tool, entryID: entryID, actions: [], blockedReason: reason)
        }
        do {
            switch tool {
            case .simctl:
                let runtimes = try await ToolRunner.run(.simctl, ["simctl", "runtime", "list", "-j"], timeout: 30)
                guard runtimes.status == 0 else { return blocked(Copy.toolMissing) }
                var (actions, kept) = SimCleanup.runtimePlan(
                    runtimes: SimctlParser.runtimes(fromJSON: runtimes.stdout)
                )
                // The row's total also holds the dyld caches; offer them too
                // so the sheet reconciles and everything is deletable.
                let dyldBytes = SimCleanup.directorySize("/Library/Developer/CoreSimulator/Caches/dyld")
                if dyldBytes > 100_000_000 {
                    actions.append(SimCleanup.dyldCacheRow(bytes: dyldBytes))
                }
                var notes = kept.map { runtime in
                    Copy.cleanupStays(
                        "\(SimCleanup.shortPlatform(runtime.identifier)) \(runtime.version)",
                        ByteFormat.string(runtime.sizeBytes ?? 0)
                    )
                }
                // One Simulator sheet: devices and test clones join
                // the runtime rows.
                let devices = try await ToolRunner.run(.simctl, ["simctl", "list", "devices", "-j"], timeout: 30)
                guard devices.status == 0 else { return blocked(Copy.toolMissing) }
                var (deviceActions, keptCount) = SimCleanup.devicePlan(
                    devices: SimctlParser.devices(fromJSON: devices.stdout)
                )
                // Parallel-testing clones ride this same sheet; the
                // scan already measured them.
                let cloneBytes = SimCleanup.directorySize(NSHomeDirectory() + "/Library/Developer/XCTestDevices")
                if cloneBytes > 0 {
                    deviceActions.insert(SimCleanup.testCloneRow(bytes: cloneBytes), at: 0)
                }
                if keptCount > 0 { notes.append(Copy.cleanupKeptDevices(keptCount)) }
                return CleanupPlan(tool: .simctl, entryID: entryID, actions: actions + deviceActions, notes: notes)
            case .docker:
                let df = try await ToolRunner.run(.docker, ["system", "df", "--format", "{{json .}}"], timeout: 15)
                guard df.status == 0 else { return blocked(Copy.containerAppStart) }
                let rows = DockerCleanup.dfRows(fromOutput: String(data: df.stdout, encoding: .utf8) ?? "")
                // The verbose listing names each unused volume; without it the
                // plan falls back to one summary prune row.
                var volumes: [(name: String, bytes: Int64)] = []
                if rows["Local Volumes", default: 0] > 0,
                   let verbose = try? await ToolRunner.run(.docker, ["system", "df", "-v", "--format", "{{json .}}"], timeout: 30),
                   verbose.status == 0 {
                    volumes = DockerCleanup.volumeRows(
                        fromVerboseOutput: String(data: verbose.stdout, encoding: .utf8) ?? ""
                    )
                }
                // Reconciliation: the Items row measures the VM disk
                // file; these rows free space inside it. Say so.
                return CleanupPlan(tool: .docker, entryID: entryID,
                                   actions: DockerCleanup.plan(dfRows: rows, volumes: volumes))
            case .brew:
                let preview = try await ToolRunner.run(.brew, ["cleanup", "-n", "--prune=all"], timeout: 60)
                let text = String(data: preview.stdout, encoding: .utf8) ?? ""
                return CleanupPlan(tool: .brew, entryID: entryID, actions: BrewCleanup.plan(previewOutput: text))
            case .tmutil:
                // Deleting the reference snapshot mid-backup is the one
                // moment to refuse; everything else is the user's call.
                let status = try await ToolRunner.run(.tmutil, ["status"], timeout: 15)
                if TMSnapshotParser.backupRunning(fromOutput: String(data: status.stdout, encoding: .utf8) ?? "") {
                    return blocked(Copy.tmBackupRunning)
                }
                let list = try await ToolRunner.run(.tmutil, ["listlocalsnapshots", "/"], timeout: 15)
                guard list.status == 0 else { return blocked(Copy.toolMissing) }
                let listText = String(data: list.stdout, encoding: .utf8) ?? ""
                let tokens = TMSnapshotParser.snapshotTokens(fromOutput: listText)
                // No destination configured is an answer, not a failure: the
                // notes then warn instead of reassure.
                let dest = try? await ToolRunner.run(.tmutil, ["destinationinfo"], timeout: 15)
                let destination = dest.flatMap {
                    TMSnapshotParser.destination(fromOutput: String(data: $0.stdout, encoding: .utf8) ?? "")
                }
                let (actions, notes, estimate) = TMSnapshotCleanup.plan(
                    tokens: tokens,
                    destination: destination,
                    purgeableBytes: DiskSnapshot.captureSpace().purgeable,
                    osUpdateCount: TMSnapshotParser.osUpdateCount(fromOutput: listText)
                )
                return CleanupPlan(tool: .tmutil, entryID: entryID, actions: actions,
                                   notes: notes, estimatedBytes: estimate)
            }
        } catch {
            return blocked((error as? LocalizedError)?.errorDescription ?? Copy.toolMissing)
        }
    }

}
