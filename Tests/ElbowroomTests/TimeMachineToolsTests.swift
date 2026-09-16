import XCTest
@testable import ElbowroomKit

final class TimeMachineToolsTests: XCTestCase {

    // MARK: Parser

    func testSnapshotTokensIgnoreOSUpdateAndHeaderLines() {
        let out = """
        Snapshots for volume group containing disk /:
        com.apple.TimeMachine.2026-07-21-222000.local
        com.apple.TimeMachine.2026-07-22-222659.local
        com.apple.os.update-2A1B3A6887F49B150BBDBEB3FADA453426E5218B.local
        com.apple.os.update-MSUPrepareUpdate
        """
        XCTAssertEqual(
            TMSnapshotParser.snapshotTokens(fromOutput: out),
            ["2026-07-21-222000", "2026-07-22-222659"]
        )
    }

    func testSnapshotTokensSortOldestFirst() {
        let out = """
        com.apple.TimeMachine.2026-07-22-222659.local
        com.apple.TimeMachine.2026-07-20-221141.local
        """
        XCTAssertEqual(
            TMSnapshotParser.snapshotTokens(fromOutput: out),
            ["2026-07-20-221141", "2026-07-22-222659"]
        )
    }

    func testTokenDateParses() {
        let date = TMSnapshotParser.date(fromToken: "2026-07-22-222659")
        XCTAssertNotNil(date)
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date!)
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 7)
        XCTAssertEqual(parts.day, 22)
        XCTAssertEqual(parts.hour, 22)
        XCTAssertEqual(parts.minute, 26)
        XCTAssertNil(TMSnapshotParser.date(fromToken: "not-a-token"))
    }

    func testDestinationParsesNetworkHostFromURL() {
        let out = """
        ====================================================
        Name          : TimeMachine
        Kind          : Network
        URL           : smb://tjohnell@goose-nas._smb._tcp.local./TimeMachine
        ID            : F797B745-0D53-48F7-96D3-1032B1552F6F
        """
        let dest = TMSnapshotParser.destination(fromOutput: out)
        XCTAssertEqual(dest?.name, "goose-nas")
        XCTAssertEqual(dest?.isNetwork, true)
    }

    func testDestinationParsesLocalDriveByName() {
        let out = """
        Name          : Backup HD
        Kind          : Local
        Mount Point   : /Volumes/Backup HD
        ID            : AAA
        """
        let dest = TMSnapshotParser.destination(fromOutput: out)
        XCTAssertEqual(dest?.name, "Backup HD")
        XCTAssertEqual(dest?.isNetwork, false)
    }

    func testDestinationNilWhenNoneConfigured() {
        XCTAssertNil(TMSnapshotParser.destination(fromOutput: "tmutil: No destinations configured.\n"))
        XCTAssertNil(TMSnapshotParser.destination(fromOutput: ""))
    }

    func testBackupRunningFlag() {
        XCTAssertTrue(TMSnapshotParser.backupRunning(fromOutput: "{\n    Running = 1;\n}"))
        XCTAssertFalse(TMSnapshotParser.backupRunning(fromOutput: "{\n    Running = 0;\n}"))
    }

    func testOSUpdateSnapshotsCountedForReconciliation() {
        let out = """
        Snapshots for volume group containing disk /:
        com.apple.TimeMachine.2026-07-22-222659.local
        com.apple.os.update-2A1B3A6887F49B150BBDBEB3FADA453426E5218B.local
        com.apple.os.update-MSUPrepareUpdate
        """
        XCTAssertEqual(TMSnapshotParser.osUpdateCount(fromOutput: out), 2)
        let (_, notes, _) = TMSnapshotCleanup.plan(
            tokens: ["2026-07-22-222659"], destination: nil,
            purgeableBytes: 0, osUpdateCount: 2
        )
        XCTAssertTrue(notes.contains(Copy.tmOSUpdateStays(2)))
    }

    // MARK: Plan

    func testPlanRowsAreCheckedGroupedAndLiteral() {
        let (actions, notes, estimate) = TMSnapshotCleanup.plan(
            tokens: ["2026-07-21-222000", "2026-07-22-222659"],
            destination: TMSnapshotParser.Destination(name: "goose-nas", isNetwork: true),
            purgeableBytes: 38_000_000_000
        )
        XCTAssertEqual(actions.count, 2)
        for action in actions {
            XCTAssertTrue(action.checked)
            XCTAssertEqual(action.bytes, 0)
            XCTAssertEqual(action.groupTitle, Copy.tmGroupTitle)
            XCTAssertEqual(action.warning, Copy.tmSnapshotWarning)
        }
        XCTAssertEqual(actions[0].argv, ["deletelocalsnapshots", "2026-07-21-222000"])
        XCTAssertEqual(actions[1].argv, ["deletelocalsnapshots", "2026-07-22-222659"])
        XCTAssertEqual(estimate, 38_000_000_000)
        XCTAssertTrue(notes.contains(Copy.tmReassure("goose-nas")))
        XCTAssertTrue(notes.contains(Copy.tmEstimateNote(ByteFormat.string(38_000_000_000))))
    }

    func testPlanWarnsWithoutDestinationAndSkipsZeroEstimate() {
        let (actions, notes, estimate) = TMSnapshotCleanup.plan(
            tokens: ["2026-07-22-222659"],
            destination: nil,
            purgeableBytes: 0
        )
        XCTAssertEqual(actions.count, 1)
        XCTAssertNil(estimate)
        XCTAssertEqual(notes, [Copy.tmNoDestination])
    }

    func testPlanCommandPreviewReadsAsTerminalLines() {
        let (actions, _, _) = TMSnapshotCleanup.plan(
            tokens: ["2026-07-22-222659"], destination: nil, purgeableBytes: 0
        )
        let plan = CleanupPlan(tool: .tmutil, entryID: "sys.snapshots", actions: actions)
        XCTAssertEqual(plan.commandPreview, "tmutil deletelocalsnapshots 2026-07-22-222659")
    }

    // MARK: Scan artifacts (item, not card)

    func testSnapshotsBecomeAnItemAndClaimPurgeable() {
        let disk = DiskSnapshot(volumeName: "T", totalCapacity: 500, available: 100,
                                availableForImportant: 100 + 9_000_000_000, snapshotCount: 1)
        let (item, insights) = TMSnapshotCleanup.scanArtifacts(disk: disk)
        XCTAssertEqual(item?.entryID, "sys.snapshots")
        XCTAssertEqual(item?.bytes, 9_000_000_000)
        // No separate purgeable row: those bytes are already on the item.
        XCTAssertTrue(insights.isEmpty)
    }

    func testPurgeableKeepsItsExplainerWithoutSnapshots() {
        let disk = DiskSnapshot(volumeName: "T", totalCapacity: 500, available: 100,
                                availableForImportant: 100 + 2_000_000_000, snapshotCount: 0)
        let (item, insights) = TMSnapshotCleanup.scanArtifacts(disk: disk)
        XCTAssertNil(item)
        XCTAssertEqual(insights.map(\.entryID), ["sys.purgeable"])
    }

    func testQuietDiskProducesNeither() {
        let disk = DiskSnapshot(volumeName: "T", totalCapacity: 500, available: 100,
                                availableForImportant: 100, snapshotCount: 0)
        let (item, insights) = TMSnapshotCleanup.scanArtifacts(disk: disk)
        XCTAssertNil(item)
        XCTAssertTrue(insights.isEmpty)
    }

    // MARK: Auto-trim policy

    func testShouldAutoThinTruthTable() {
        // Disabled never fires.
        XCTAssertFalse(TMSnapshotCleanup.shouldAutoThin(
            enabled: false, snapshotCount: 2, purgeableBytes: 40_000_000_000, backupRunning: false))
        // Nothing to trim.
        XCTAssertFalse(TMSnapshotCleanup.shouldAutoThin(
            enabled: true, snapshotCount: 0, purgeableBytes: 40_000_000_000, backupRunning: false))
        // Below the floor: not worth a deep-traversal backup.
        XCTAssertFalse(TMSnapshotCleanup.shouldAutoThin(
            enabled: true, snapshotCount: 2, purgeableBytes: 500_000_000, backupRunning: false))
        // Mid-backup: never.
        XCTAssertFalse(TMSnapshotCleanup.shouldAutoThin(
            enabled: true, snapshotCount: 2, purgeableBytes: 40_000_000_000, backupRunning: true))
        // The firing case.
        XCTAssertTrue(TMSnapshotCleanup.shouldAutoThin(
            enabled: true, snapshotCount: 2, purgeableBytes: 40_000_000_000, backupRunning: false))
    }

    // MARK: Wiring

    func testSnapshotsEntryRoutesToTmutil() {
        XCTAssertEqual(ToolCleanup.tool(for: "sys.snapshots"), .tmutil)
    }

    func testReceiptCountsMeasuredBytes() {
        let item = ReceiptItem(path: "tmutil deletelocalsnapshots 2026-07-22-222659",
                               name: "July 22", bytes: 0, tier: .managed, entryID: "sys.snapshots")
        let receipt = Receipt(items: [item], restoreStatus: .deletedNow,
                              trashFolder: nil, measuredBytes: 38_000_000_000)
        XCTAssertEqual(receipt.totalBytes, 38_000_000_000)
        // Old receipts without the field still decode and keep their totals.
        let plain = Receipt(items: [item], restoreStatus: .deletedNow, trashFolder: nil)
        XCTAssertEqual(plain.totalBytes, 0)
    }
}
