import Foundation

/// Teach flows. One sheet, always: what Elbowroom found + size → why it won't
/// touch it directly (one honest sentence) → two doors: the app's own panel
/// (deep link) and a copyable command with a one-line gloss.
/// Stored strings are English (the localization keys); translation on read.
public struct TeachFlow: Identifiable, Sendable {
    public let id: TeachFlowID
    private let titleKey: String
    private let whyKey: String
    private let doorLabelKey: String?
    public let doorURL: String?
    /// Commands copy exactly; they never localize.
    public let command: String?
    private let commandGlossKey: String?
    private let warningKey: String?

    public var title: String { Loc.t(titleKey) }
    public var why: String { Loc.t(whyKey) }
    public var doorLabel: String? { doorLabelKey.map { Loc.t($0) } }
    public var commandGloss: String? { commandGlossKey.map { Loc.t($0) } }
    public var warning: String? { warningKey.map { Loc.t($0) } }

    init(id: TeachFlowID, title: String, why: String, doorLabel: String?,
         doorURL: String?, command: String?, commandGloss: String?, warning: String?) {
        self.id = id
        self.titleKey = title
        self.whyKey = why
        self.doorLabelKey = doorLabel
        self.doorURL = doorURL
        self.command = command
        self.commandGlossKey = commandGloss
        self.warningKey = warning
    }

    public static func flow(_ id: TeachFlowID) -> TeachFlow { flows[id]! }

    public static let flows: [TeachFlowID: TeachFlow] = [
        .simulatorRuntimes: TeachFlow(
            id: .simulatorRuntimes,
            title: "Simulator runtimes and devices",
            why: "Xcode owns these. Its own panel removes them safely and can download them again later.",
            doorLabel: "Open Xcode's Components panel",
            doorURL: nil,
            command: "xcrun simctl runtime list\nxcrun simctl runtime delete <id>",
            commandGloss: "List the installed runtimes, then delete one by its id.",
            warning: nil
        ),
        .docker: TeachFlow(
            id: .docker,
            title: "Docker Desktop data",
            why: "Docker owns this virtual disk. Removing files inside it by hand corrupts it.",
            doorLabel: "Open Docker Desktop",
            doorURL: "docker://",
            command: "docker system prune --all",
            commandGloss: "Removes stopped containers, unused networks, and all unused images.",
            warning: "Prune deletes every image no container is using. Pulling them back takes time and bandwidth."
        ),
        .orbstack: TeachFlow(
            id: .orbstack,
            title: "OrbStack data",
            why: "OrbStack owns this virtual disk. Its own settings reclaim space safely.",
            doorLabel: "Open OrbStack",
            doorURL: "orbstack://",
            command: "docker system prune --all",
            commandGloss: "Removes stopped containers, unused networks, and all unused images.",
            warning: "Prune deletes every image no container is using."
        ),
        .snapshots: TeachFlow(
            id: .snapshots,
            title: "Local Time Machine snapshots",
            why: "macOS makes these local backups and thins them on its own. The command below thins them now.",
            doorLabel: nil,
            doorURL: nil,
            command: "tmutil thinlocalsnapshots / 20000000000 4",
            commandGloss: "Asks macOS to thin snapshots until about 20 GB frees up.",
            warning: nil
        ),
        .purgeable: TeachFlow(
            id: .purgeable,
            title: "Purgeable space",
            why: "macOS keeps files it can delete on its own when space runs low. Finder often counts this space as available. Elbowroom lists it separately.",
            doorLabel: nil, doorURL: nil, command: nil, commandGloss: nil, warning: nil
        ),
        .deviceBackups: TeachFlow(
            id: .deviceBackups,
            title: "iPhone and iPad backups",
            why: "Finder owns these backups. Its own panel shows each one and deletes them safely.",
            doorLabel: "Open Finder's backup list",
            doorURL: nil,
            command: nil, commandGloss: nil, warning: nil
        ),
        .trash: TeachFlow(
            id: .trash,
            title: "Trash",
            why: "You already deleted these files. Emptying the Trash frees them for good.",
            doorLabel: "Open the Trash",
            doorURL: nil,
            command: nil, commandGloss: nil, warning: nil
        ),
        .timeMachine: TeachFlow(
            id: .timeMachine,
            title: "Time Machine",
            why: "Time Machine owns this. Its settings control what it keeps.",
            doorLabel: "Open Time Machine settings",
            doorURL: "x-apple.systempreferences:com.apple.Time-Machine-Settings.extension",
            command: nil, commandGloss: nil, warning: nil
        ),
        .brewCleanup: TeachFlow(
            id: .brewCleanup,
            title: "Homebrew old versions",
            why: "Homebrew owns the Cellar. brew cleanup removes old versions safely and keeps what is linked.",
            doorLabel: nil,
            doorURL: nil,
            command: "brew cleanup --prune=all",
            commandGloss: "Removes old versions and stale downloads of everything installed.",
            warning: nil
        ),
    ]
}
