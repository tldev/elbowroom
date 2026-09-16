import XCTest
@testable import ElbowroomKit

extension XCTestCase {
    @MainActor
    func makeModel() -> AppModel {
        let suite = "elbowroom-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        return AppModel(settings: SettingsStore(defaults: defaults),
                        receipts: ReceiptStore(directory: directory), changeLog: ChangeLog(directory: directory),
                        startServices: false, scanCacheURL: directory.appendingPathComponent("scan-cache.json"))
    }
}
