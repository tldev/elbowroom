import AppKit
import Sparkle
import SwiftUI
import ElbowroomKit

/// Only the real app owns an updater; snapshots and tests never start it.
@MainActor
final class Updater: ObservableObject {
    private let controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil
    )
    @Published private(set) var canCheck = false
    private var observation: NSKeyValueObservation?
    private var started = false

    func start() {
        guard !started,
              Bundle.main.object(forInfoDictionaryKey: "ElbowroomDistributionBuild") as? Bool == true
        else { return }
        started = true
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            let value = updater.canCheckForUpdates
            Task { @MainActor [weak self] in self?.canCheck = value }
        }
        controller.startUpdater()
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set {
            objectWillChange.send()
            controller.updater.automaticallyChecksForUpdates = newValue
        }
    }

    func check() { controller.checkForUpdates(nil) }
}
