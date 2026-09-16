import XCTest
@testable import AuthorizedAppMoveCore
@testable import ElbowroomKit

final class AdministratorMoveTests: XCTestCase {
    func testDescriptorMoveChecksIdentityAndNeverOverwrites() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let source = root.appendingPathComponent("source")
        let target = root.appendingPathComponent("target")
        let app = source.appendingPathComponent("Fake.app")
        try fm.createDirectory(at: app, withIntermediateDirectories: true)
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        let fromFD = open(source.path, O_RDONLY | O_DIRECTORY)
        let toFD = open(target.path, O_RDONLY | O_DIRECTORY)
        defer { close(fromFD); close(toFD) }
        var info = stat()
        XCTAssertEqual(lstat(app.path, &info), 0)
        XCTAssertThrowsError(try AuthorizedAppMove.moveApp(name: "Fake.app", source: fromFD, target: toFD,
                             device: info.st_dev, inode: info.st_ino + 1, owner: getuid()))
        let collision = target.appendingPathComponent("Fake.app")
        try fm.createDirectory(at: collision, withIntermediateDirectories: true)
        XCTAssertThrowsError(try AuthorizedAppMove.moveApp(name: "Fake.app", source: fromFD, target: toFD,
                             device: info.st_dev, inode: info.st_ino, owner: getuid()))
        XCTAssertTrue(fm.fileExists(atPath: app.path))
        try fm.removeItem(at: collision)
        try AuthorizedAppMove.moveApp(name: "Fake.app", source: fromFD, target: toFD,
                                      device: info.st_dev, inode: info.st_ino, owner: getuid())
        XCTAssertFalse(fm.fileExists(atPath: app.path))
        XCTAssertTrue(fm.fileExists(atPath: collision.path))
        try AuthorizedAppMove.moveApp(name: "Fake.app", source: toFD, target: fromFD,
                                      device: info.st_dev, inode: info.st_ino, owner: getuid())
        XCTAssertTrue(fm.fileExists(atPath: app.path))
    }

    func testHelperRejectsPathsAndMalformedTrashFolders() {
        for name in ["../iMovie.app", "/Applications/iMovie.app", "a/b.app", ".app", "foo\0.app"] {
            XCTAssertFalse(AuthorizedAppMove.validName(name))
        }
        XCTAssertTrue(AuthorizedAppMove.validName("Tom's App.app"))
        XCTAssertFalse(AuthorizedAppMove.validFolder("Elbowroom Authorized ../../tmp"))
        XCTAssertTrue(AuthorizedAppMove.validFolder("Elbowroom Authorized " + UUID().uuidString))
    }

    func testHelperNeverRunsWithoutRoot() throws {
        guard geteuid() != 0 else { throw XCTSkip("This check requires an unprivileged test runner") }
        XCTAssertThrowsError(try AuthorizedAppMove.move(arguments: []))
    }

    func testShellQuotingRoundTripsMetacharactersAsData() throws {
        let input = "a'\"$HOME`id`$(id)\\\nnext.app"
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "printf %s " + AdministratorAppMove.shellQuote(input)]
        process.standardOutput = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(String(decoding: output, as: UTF8.self), input)
        XCTAssertEqual(process.terminationStatus, 0)
    }

    func testAppleScriptQuotingRoundTripsCommandWithoutExecutingIt() throws {
        let input = "a'\"$HOME`id`$(id)\\\nnext.app"
        let command = AdministratorAppMove.shellQuote(input)
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "return " + AdministratorAppMove.appleScriptQuote(command)]
        process.standardOutput = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(String(decoding: output, as: UTF8.self), command + "\n")
        XCTAssertEqual(process.terminationStatus, 0)
    }

    func testPermissionFailureRequestsAuthorizationAndRecordsReturnedLocation() async throws {
        let app = URL(fileURLWithPath: "/Applications/Fake.app")
        let landed = URL(fileURLWithPath: "/tmp/authorized-fixture/Fake.app")
        let executor = ReclaimExecutor(recycle: { _ in throw CocoaError(.fileWriteNoPermission) },
                                      authorize: { url in XCTAssertEqual(url, app); return landed })
        let outcome = await executor.run(plan: ReclaimPlan(items: [
            AtlasItem(entryID: "app.bundle", url: app, bytes: 1, lastTouched: nil)
        ]), keepInTrash: true) { _, _ in }
        XCTAssertEqual(outcome.doneCount, 1)
        XCTAssertTrue(outcome.skipped.isEmpty)
        XCTAssertEqual(outcome.receipt?.items.first?.trashedTo, landed.path)
    }

    func testCancelledAuthorizationDoesNotBecomeSuccessOrPermissionLoop() async {
        let executor = ReclaimExecutor(recycle: { _ in throw CocoaError(.fileWriteNoPermission) },
                                      authorize: { _ in throw CocoaError(.userCancelled) })
        let outcome = await executor.run(plan: ReclaimPlan(items: [
            AtlasItem(entryID: "app.bundle", url: URL(fileURLWithPath: "/Applications/Fake.app"),
                      bytes: 1, lastTouched: nil)
        ]), keepInTrash: true) { _, _ in }
        XCTAssertTrue(outcome.cancelled)
        XCTAssertNil(outcome.receipt)
        XCTAssertTrue(outcome.accessDeniedAppPaths.isEmpty)
    }

    func testNonPermissionFailureNeverElevates() async {
        let executor = ReclaimExecutor(recycle: { _ in throw CocoaError(.fileNoSuchFile) },
                                      authorize: { _ in XCTFail("Missing apps must not request administrator approval"); return URL(fileURLWithPath: "/tmp/unused") })
        let outcome = await executor.run(plan: ReclaimPlan(items: [
            AtlasItem(entryID: "app.bundle", url: URL(fileURLWithPath: "/Applications/Fake.app"),
                      bytes: 1, lastTouched: nil)
        ]), keepInTrash: true) { _, _ in }
        XCTAssertEqual(outcome.doneCount, 0)
        XCTAssertEqual(outcome.skipped.count, 1)
    }
}
