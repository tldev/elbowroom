import Foundation
import AppKit

/// Full Disk Access plumbing for B3 Grant. FDA has no request API and
/// no query API: granting happens in System Settings, and reading an
/// FDA-class folder is the honest probe (it never raises a consent dialog;
/// it just succeeds or fails).
public enum DiskAccess {
    /// FDA-class folders present on every stock account. Any one readable
    /// means the grant is on.
    public static func fdaGranted(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let canaries = ["Library/Safari", "Library/Mail", "Library/Messages"]
        return canaries.contains {
            (try? FileManager.default.contentsOfDirectory(atPath: home.appendingPathComponent($0).path)) != nil
        }
    }

    public static let settingsPane = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"

    @MainActor
    public static func openFullDiskSettings() {
        if let url = URL(string: settingsPane) { NSWorkspace.shared.open(url) }
    }

    /// macOS applies a Full Disk Access grant to an already-running app only
    /// after a relaunch; System Settings offers "Quit & Reopen" itself, this
    /// is the in-app equivalent.
    ///
    /// A helper waits for this process to die and only then reopens, so
    /// exactly one instance exists at every moment. `open -n` cannot do
    /// this: it launches the second copy immediately, and when the quit is
    /// deferred (a modal sheet defers it) the instances pile up. Terminate
    /// can be deferred here too, so a grace period backs it with exit();
    /// every store writes through on change, so there is nothing to lose.
    @MainActor
    public static func relaunch(afterSeconds grace: TimeInterval = 1.5) {
        let path = Bundle.main.bundleURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let pid = ProcessInfo.processInfo.processIdentifier
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = [
            "-c",
            "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.1; done; /usr/bin/open '\(path)'",
        ]
        try? helper.run()
        NSApp.terminate(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + grace) { exit(0) }
    }
}

/// App Management settings. There is no supported permission query here:
/// rename-to-self can fail for unrelated reasons or skip authorization entirely.
/// Access failures are handled after a user-confirmed operation instead.
public enum AppManagement {
    public static let settingsPane = "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles"

    @MainActor
    public static func openSettings() {
        if let url = URL(string: settingsPane) { NSWorkspace.shared.open(url) }
    }
}

/// The five consent classes the first scan would otherwise trip one by one,
/// mid-dig. The home-folder fallback touches them deliberately, in this
/// order, before the scan starts.
public enum PromptZone: String, CaseIterable, Sendable {
    case desktop, documents, downloads, photos, appData

    public enum TouchResult: Sendable { case allowed, denied, absent }

    var relativePath: String {
        switch self {
        case .desktop: "Desktop"
        case .documents: "Documents"
        case .downloads: "Downloads"
        case .photos: "Pictures/Photos Library.photoslibrary"
        case .appData: "Library/Containers"
        }
    }

    /// Zones that exist on this account; a Mac without a Photos library gets
    /// no Photos dialog and needs no row for one.
    public static func present(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> [PromptZone] {
        allCases.filter { exists(home.appendingPathComponent($0.relativePath).path) }
    }

    /// Reads just enough of the zone to raise its consent dialog, then reports
    /// how the user answered. Blocks until the dialog is dismissed; run off
    /// the main thread.
    public func touch(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> TouchResult {
        let fm = FileManager.default
        let base = home.appendingPathComponent(relativePath)
        switch self {
        case .desktop, .documents, .downloads:
            return Self.classify { try fm.contentsOfDirectory(atPath: base.path) }
        case .photos:
            // The database folder is unambiguously inside the protected
            // package; fall back to the package root for older layouts.
            let deep = Self.classify { try fm.contentsOfDirectory(atPath: base.appendingPathComponent("database").path) }
            return deep == .absent ? Self.classify { try fm.contentsOfDirectory(atPath: base.path) } : deep
        case .appData:
            // Another app's container Data folder is what the "data from
            // other apps" consent guards. One attempt raises the dialog for
            // all of them.
            guard let kids = try? fm.contentsOfDirectory(atPath: base.path) else { return .absent }
            let own = Bundle.main.bundleIdentifier ?? ""
            for kid in kids.prefix(40) where kid != own {
                let data = base.appendingPathComponent(kid).appendingPathComponent("Data")
                switch Self.classify({ try fm.contentsOfDirectory(atPath: data.path) }) {
                case .allowed: return .allowed
                case .denied: return .denied
                case .absent: continue
                }
            }
            return .absent
        }
    }

    private static func classify(_ read: () throws -> [String]) -> TouchResult {
        do {
            _ = try read()
            return .allowed
        } catch let error as NSError {
            let missing = error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError.rawValue
            return missing ? .absent : .denied
        }
    }
}

private let NSFileReadNoSuchFileError = CocoaError.Code.fileReadNoSuchFile

/// One row of the B3 guided checklist.
public struct GuidedZone: Identifiable, Equatable, Sendable {
    public enum Status: Equatable, Sendable { case pending, asking, allowed, denied }
    public let zone: PromptZone
    public var status: Status
    public var id: String { zone.rawValue }
    public init(zone: PromptZone, status: Status = .pending) {
        self.zone = zone
        self.status = status
    }
}
