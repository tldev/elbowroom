import Foundation
import XCTest
@testable import ElbowroomKit

final class AppResourcesTests: XCTestCase {
    func testInstalledBundleLoadsWithoutBuildDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Elbowroom.app")
        let contents = app.appendingPathComponent("Contents")
        let resources = contents.appendingPathComponent("Resources/Elbowroom_ElbowroomKit.bundle")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let appInfo: [String: Any] = ["CFBundleIdentifier": "test.elbowroom", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: appInfo, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        let resourceInfo = ["CFBundleIdentifier": "test.elbowroom.resources"]
        try PropertyListSerialization.data(fromPropertyList: resourceInfo, format: .xml, options: 0)
            .write(to: resources.appendingPathComponent("Info.plist"))
        try Data("installed".utf8).write(to: resources.appendingPathComponent("fixture.txt"))
        let bundle = try XCTUnwrap(Bundle(url: app))
        let installed = try XCTUnwrap(AppResources.installedBundle(in: bundle))
        let fixture = try XCTUnwrap(installed.url(forResource: "fixture", withExtension: "txt"))
        XCTAssertEqual(try String(contentsOf: fixture), "installed")
    }

    func testDevelopmentResourcesStillResolve() {
        XCTAssertNotNil(SoundPlayer.resourceURL(.whoosh))
        XCTAssertNotNil(TeachFigures.url("teach-shared-with-you"))
    }
}
