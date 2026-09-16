import Foundation
import AppKit
import Observation
import UserNotifications

/// The Guardian: watches the Stash volume, keeps symlinks honest, and
/// speaks by the notification rules: one notification per ABSENT transition
/// with a 24 h cooldown, plus one immediate escalation if a dependent app
/// launches while the drive is away.
public enum GuardianState: String, Sendable {
    case noStash
    case allPresent
    case absent
    case reconciling
    case conflict
    case ejecting

    public var menuSymbol: String {
        switch self {
        case .noStash: "circle.dashed"
        case .allPresent: "door.left.hand.closed"
        case .absent: "door.left.hand.open"
        case .reconciling: "arrow.triangle.2.circlepath"
        case .conflict: "exclamationmark.triangle"
        case .ejecting: "eject"
        }
    }
}

@Observable
public final class Guardian {
    public private(set) var state: GuardianState = .noStash
    public var stash: StashManager? {
        didSet { refresh() }
    }
    public var conflicts: [StashEntry] = []
    public var lastAbsentNotification: Date?
    public var escalatedThisAbsence = false

    private var observers: [NSObjectProtocol] = []
    public var notify: (String, String) -> Void = Notifier.post

    public init() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.didMountNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            guard let stash = self.stash else { return self.volumeReturned() }
            stash.refreshVolumePresence { [weak self] in self?.volumeReturned() }
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            guard let stash = self.stash else { return self.refresh() }
            stash.refreshVolumePresence { [weak self] in self?.refresh() }
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.appLaunched(bundleID: app.bundleIdentifier ?? "", name: app.localizedName ?? "An app")
        })
    }

    deinit {
        for o in observers { NSWorkspace.shared.notificationCenter.removeObserver(o) }
    }

    public func refresh() {
        guard let stash else { state = .noStash; return }
        if state == .ejecting { return }
        if stash.volumeIsPresent {
            conflicts = stash.clobberedEntries()
            if !conflicts.isEmpty {
                state = .conflict
            } else {
                state = .allPresent
                escalatedThisAbsence = false
            }
        } else {
            transitionToAbsent()
        }
    }

    private func transitionToAbsent() {
        let wasAbsent = state == .absent
        state = .absent
        guard !wasAbsent, let stash else { return }
        // Exactly one notification per transition, 24 h cooldown.
        let cooledDown = lastAbsentNotification.map { Date().timeIntervalSince($0) > 86_400 } ?? true
        guard cooledDown else { return }
        if let biggest = stash.manifest.entries
            .filter({ $0.status == .done })
            .max(by: { $0.bytes < $1.bytes }) {
            lastAbsentNotification = Date()
            notify("Elbowroom", Copy.guardianAbsent(item: biggest.displayName, drive: stash.volumeName))
        }
    }

    private func volumeReturned() {
        guard let stash, stash.volumeIsPresent else { refresh(); return }
        state = .reconciling
        // Verify every symlink on return; a clobbered link means CONFLICT.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let clobbered = stash.clobberedEntries()
            DispatchQueue.main.async {
                guard let self else { return }
                self.conflicts = clobbered
                self.state = clobbered.isEmpty ? .allPresent : .conflict
                self.escalatedThisAbsence = false
            }
        }
    }

    private func appLaunched(bundleID: String, name: String) {
        // The one allowed escalation: a dependent app opened while the drive
        // is away.
        guard state == .absent, !escalatedThisAbsence, let stash else { return }
        for entry in stash.manifest.entries where entry.status == .done {
            let dependents = StashRules.dependentApps(for: entry.entryID)
            if dependents.contains(where: { $0.bundleID == bundleID }) {
                escalatedThisAbsence = true
                notify("Elbowroom", Copy.guardianEscalation(app: name, item: entry.displayName, drive: stash.volumeName))
                return
            }
        }
    }

    /// Safe Eject: try to unmount; if something holds the volume, say who.
    public func safeEject(completion: @escaping (String?) -> Void) {
        guard let stash else { completion(nil); return }
        state = .ejecting
        let volume = stash.volumeURL
        FileManager.default.unmountVolume(at: volume, options: [.allPartitionsAndEjectDisk]) { [weak self] error in
            DispatchQueue.main.async {
                if error != nil {
                    self?.refresh()
                    let holder = Self.processHolding(volume: volume) ?? "Another app"
                    completion(Copy.ejectBlocked(holder))
                } else {
                    self?.state = .absent
                    completion(nil)
                }
            }
        }
    }

    /// Best-effort `lsof` to name who is holding the volume.
    static func processHolding(volume: URL) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        p.arguments = ["-Fc", "+D", volume.path]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let names = out.split(separator: "\n").filter { $0.hasPrefix("c") }.map { String($0.dropFirst()) }
            return names.first { $0 != "lsof" }
        } catch {
            return nil
        }
    }
}

/// Notification plumbing. UNUserNotificationCenter needs a real app bundle;
/// when running as a bare binary the fallback is a log line, never a crash.
public enum Notifier {
    public static var requested = false

    public static func post(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else {
            NSLog("[Elbowroom notification] %@: %@", title, body)
            return
        }
        let center = UNUserNotificationCenter.current()
        let fire = {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(request)
        }
        if requested { fire() } else {
            requested = true
            center.requestAuthorization(options: [.alert]) { granted, _ in
                if granted { fire() }
            }
        }
    }
}
