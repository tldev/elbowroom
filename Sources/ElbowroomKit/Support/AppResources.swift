import Foundation

/// SwiftPM's generated accessor looks beside the .app or in the checkout.
/// Installed macOS apps keep their resource bundle in Contents/Resources.
enum AppResources {
    static let bundle: Bundle = installedBundle(in: .main) ?? .module

    static func installedBundle(in application: Bundle) -> Bundle? {
        guard let resources = application.resourceURL else { return nil }
        return Bundle(url: resources.appendingPathComponent("Elbowroom_ElbowroomKit.bundle"))
    }
}
