import Foundation
/// Copy deck. Every user-facing string ships from here; no string ships
/// that is not in, or amended into, this deck. House rules: plain, literal,
/// friendly, useful. Say each thing once. No marketing lines, no exclamation
/// points, and no em-dashes anywhere in the product. Buttons start with verbs.
/// English strings double as localization keys (`Loc`).
public enum Copy {
    public static var dockerStartPrompt: String { Loc.t("Open Docker Desktop to see what can be cleaned up. Elbowroom will refresh this list when Docker is ready.") }
    public static var dockerStarting: String { Loc.t("Waiting for Docker Desktop to be ready.") }
    public static var dockerStartupTimeout: String { Loc.t("Docker is not ready yet. Finish any setup in Docker Desktop, then try again.") }
    public static var dockerOpenFailed: String { Loc.t("Could not open Docker Desktop") }
    public static var dockerOpenHelp: String { Loc.t("Check that Docker Desktop is installed and can open on this Mac.") }
    // MARK: 11.1 Onboarding
    public static var b1Headline: String { Loc.t("Most of what fills a developer's disk is caches and build output.") }
    public static var b1Sub: String { Loc.t("Elbowroom separates them from your files, then cleans up.") }
    public static var b1Continue: String { Loc.t("Continue") }
    public static var b2Headline: String { Loc.t("Local processing") }
    public static var b2Body: String { Loc.t("Scanning, explanations, and AI answers all run on this Mac. Elbowroom does not touch the network while it scans. Usage statistics are anonymous, optional, and off by default.") }
    public static var b3Headline: String { Loc.t("Let Elbowroom see the whole disk") }
    public static var b3Body: String { Loc.t("One switch in System Settings lets Elbowroom count everything, with no permission pop-ups during the scan. What it reads never leaves this Mac.") }
    public static var b3StartScan: String { Loc.t("Start the scan") }
    public static var b3AlreadyOn: String { Loc.t("Full Disk Access is already on.") }
    public static var b3Fallback: String { Loc.t("Start with just my home folder") }
    public static var b3WaitTitle: String { Loc.t("Waiting for the switch") }
    public static var b3WaitNote: String { Loc.t("macOS may ask to quit and reopen Elbowroom. Let it: the scan starts right where you left off.") }
    public static var b3Relaunch: String { Loc.t("Relaunch Elbowroom") }
    public static var b3DragHint: String { Loc.t("Drag the Elbowroom icon above into the list, then turn it on.") }
    public static var b3GuidedTitle: String { Loc.t("A few folders need your OK") }
    public static var b3GuidedBody: String { Loc.t("macOS asks before Elbowroom can look inside these. Allow each one and nothing goes missing from the count.") }
    public static var b3HomeNote: String { Loc.t("Elbowroom won't see files outside your home folder.") }
    public static var b3ZoneSkipped: String { Loc.t("Not visible for now") }
    public static func b3Zone(_ zone: PromptZone) -> String {
        switch zone {
        case .desktop: Loc.t("Desktop")
        case .documents: Loc.t("Documents")
        case .downloads: Loc.t("Downloads")
        case .photos: Loc.t("Photos library")
        case .appData: Loc.t("Other apps' data")
        }
    }
    public static var b5HeroPrefix: String { Loc.t("You can safely get back") }
    public static var b5HeroSuffix: String { Loc.t("today.") }
    public static var b5Sub: String { Loc.t("Every item is identified and rated for safety.") }
    public static var b5Crisis: String { Loc.t("Low on space. Elbowroom picked the quickest safe items first.") }
    public static var b5ModestSub: String { Loc.t("Not much to reclaim right now. Elbowroom will watch for growth.") }
    public static var b5DoorReclaim: String { Loc.t("Reclaim now") }
    public static var b5DoorExplain: String { Loc.t("Open the map") }
    public static func b5CrisisDoor(_ n: String) -> String { Loc.f("Free up %@ in about a minute", n) }
    public static var b5PartialChip: String { Loc.t("Some areas weren't visible. Expand access") }
    // MARK: 11.2 Scan ticker templates
    public static func tickerXcode(_ n: String) -> String { Loc.f("Found %@ of Xcode build products", n) }
    public static func tickerSimulators(_ n: String, month: String) -> String { Loc.f("%1$@ of simulator devices, unused since %2$@", n, month) }
    public static func tickerRust(_ n: String) -> String { Loc.f("%@ of Rust build folders. Your next build remakes these.", n) }
    public static func tickerCaches(_ n: String) -> String { Loc.f("%@ of package caches. These download again when needed.", n) }
    public static func tickerBackups(_ n: String, year: String) -> String { Loc.f("%1$@ in iPhone backups from %2$@", n, year) }
    public static func tickerSnapshots(_ n: String) -> String { Loc.f("Snapshots hold %@. macOS thins them on its own.", n) }
    public static var tickerSlowDisk: String { Loc.t("Large disk. This can take a few minutes.") }
    public static func tickerNodeModules(_ n: String) -> String { Loc.f("%@ of JavaScript packages. These install again when needed.", n) }
    public static func tickerGeneric(_ name: String, _ n: String) -> String { Loc.f("Found %2$@ of %1$@", name, n) }
    // MARK: 11.3 Tiers
    public static var tierRegenerable: String { Loc.t("Deleted safely. It is re-created on demand.") }
    public static var tierRebuildable: String { Loc.t("Rebuilt from your project by its own tools.") }
    public static var tierManaged: String { Loc.t("Owned by another app. Elbowroom opens that app's controls.") }
    public static var tierApps: String { Loc.t("Installed applications and the data they keep. Uninstalling asks about both.") }
    public static var tierYours: String { Loc.t("Your files. Elbowroom never suggests changes here.") }
    public static var tierSystem: String { Loc.t("macOS itself. Elbowroom explains it and names the lever when one exists.") }
    public static var tierLabelRegenerable: String { Loc.t("Cache") }
    public static var tierLabelRebuildable: String { Loc.t("Derived") }
    public static var tierLabelManaged: String { Loc.t("App-managed") }
    public static var tierLabelApps: String { Loc.t("Apps") }
    public static var tierLabelYours: String { Loc.t("Personal") }
    public static var tierLabelSystem: String { Loc.t("System") }
    // MARK: 11.4 Reclaim
    public static var planTitle: String { Loc.t("Reclaim plan") }
    public static func costLine(tool: String, n: String, t: String) -> String {
        Loc.f("The next %1$@ run downloads about %2$@ again (%3$@ on your connection)", tool, n, t)
    }
    public static var trashToggle: String { Loc.t("Keep in Trash for 7 days") }
    /// The persistent default behind the plan's toggle: the trash beat
    /// decides it, Settings changes it, each plan can override one run.
    public static var keepInTrashLabel: String { Loc.t("Keep reclaimed items in the Trash for 7 days") }
    public static var keepInTrashNote: String { Loc.t("When off, a reclaim deletes items immediately. Each plan can change this for one run.") }
    // Uninstalls: macOS gates deleting another app behind App Management,
    // separate from Full Disk Access; the grant sheet teaches the switch.
    public static func amTitle(_ app: String) -> String { Loc.f("Deleting %@ needs one more switch", app) }
    public static var amBody: String { Loc.t("macOS keeps a separate switch for deleting other apps, called App Management. Full Disk Access does not cover it. Turn Elbowroom on there and this uninstall continues on its own.") }
    public static var uninstallRetry: String { Loc.t("Review and try again") }
    public static var uninstallPermissionHelp: String { Loc.t("macOS may ask for administrator approval to move this app to Trash. Elbowroom continues after approval.") }
    public static var amOpen: String { Loc.t("Open App Management settings") }
    public static var amRelaunchNote: String { Loc.t("macOS applies this switch when Elbowroom reopens. Quit and reopen, and the uninstall picks up where it left off.") }
    public static var trashBeatHeadline: String { Loc.t("Trash first") }
    public static var trashBeatBody: String { Loc.t("Reclaimed items move to a dated folder in the Trash and stay for 7 days. A receipt records every move and can put anything back. Turning this off deletes immediately instead.") }
    public static func reclaimPrimary(_ n: String) -> String { Loc.f("Reclaim %@", n) }
    public static func reclaimToast(_ n: String) -> String { Loc.f("%@ reclaimed. Receipt saved.", n) }
    public static func partialFail(_ n: Int) -> String {
        Loc.f(n == 1 ? "Elbowroom skipped %d item:" : "Elbowroom skipped %d items:", n)
    }
    public static func firstRebuildable(_ t: String) -> String { Loc.f("Rebuilding this next time takes about %@.", t) }
    public static var ok: String { Loc.t("OK") }
    public static var cancel: String { Loc.t("Cancel") }
    public static func headroom(_ n: String) -> String { Loc.f("%@ safely reclaimable", n) }
    public static var safelyReclaimable: String { Loc.t("safely reclaimable") }
    public static func trayCount(_ items: Int, _ n: String) -> String {
        Loc.f(items == 1 ? "%1$d item · %2$@" : "%1$d items · %2$@", items, n)
    }
    public static var trayReclaim: String { Loc.t("Reclaim") }
    public static var trayClear: String { Loc.t("Clear") }
    public static func reclaimStopped(_ n: Int) -> String {
        Loc.f(n == 1 ? "Stopped. %d item was already reclaimed and stays reclaimed." : "Stopped. %d items were already reclaimed and stay reclaimed.", n)
    }
    public static func ineligibleRunning(_ app: String) -> String { Loc.f("%@ is running. Quit it first.", app) }
    // MARK: 11.6 Explainers
    public static var purgeableExplainer: String { Loc.t("macOS keeps files it can delete on its own when space runs low. Finder often counts this space as available. Elbowroom lists it separately.") }
    // MARK: 11.8 Errors
    public static var moveFail: String { Loc.t("That move didn't finish. Nothing was lost. Try again?") }
    // MARK: 11.9 Kibi lines (empty states, short always)
    public static var kibiDenTidy: String { Loc.t("Nothing to clean right now.") }
    public static var kibiReceiptsEmpty: String { Loc.t("No receipts yet.") }
    public static var kibiChangesQuiet: String { Loc.t("No changes this week.") }
    public static var kibiSearchNone: String { Loc.t("No matches.") }
    // MARK: Steward
    public static var stewardOpen: String { Loc.t("Open Elbowroom") }
    public static func stewardReclaimable(_ n: String) -> String { Loc.f("Reclaimable now: %@", n) }
    public static var stewardPause: String { Loc.t("Pause a while") }
    public static var stewardQuit: String { Loc.t("Quit Elbowroom") }
    public static var plannerGenericTitle: String { Loc.t("Room for an update") }
    public static func plannerBody(need: String, promised: String, minutes: Int) -> String {
        Loc.f("The update needs %1$@ more than is free. This plan clears %2$@ in about %3$d minutes.", need, promised, minutes)
    }
    public static var plannerReclaimSection: String { Loc.t("Reclaim") }
    public static var plannerTeachSection: String { Loc.t("Also worth a look (through their own apps, not counted above)") }
    public static var planForUpdate: String { Loc.t("Plan for an update") }
    public static var planRoomForUpdate: String { Loc.t("Room for the update") }
    public static func freeAmount(_ n: String) -> String { Loc.f("%@ free", n) }
    public static var freeLabel: String { Loc.t("Free") }
    public static func freeOfTotal(_ free: String, _ total: String) -> String {
        Loc.f("%1$@ free of %2$@", free, total)
    }
    // MARK: Ask Kibi
    public static var kibiGuess: String { Loc.t("AI guess") }
    public static var kibiHedge: String { Loc.t("Double-check before acting.") }
    public static var kibiUnsure: String { Loc.t("Not confident. Contents:") }
    public static var kibiThinking: String { Loc.t("Analyzing") }
    public static var askKibi: String { Loc.t("Explain") }
    public static var askKibiReady: String { Loc.t("Explain is ready. Click the sparkle on an unrecognized folder in the Map.") }
    public static var askKibiOff: String { Loc.t("Explain appears once Apple Intelligence is on in System Settings.") }
    // MARK: Misc chrome
    public static var viewDen: String { Loc.t("Overview") }
    public static var viewCrossSection: String { Loc.t("Map") }
    public static var viewLedger: String { Loc.t("Items") }
    public static var viewChanges: String { Loc.t("History") }
    public static var copied: String { Loc.t("Copied") }
    public static var copyCommand: String { Loc.t("Copy Command") }
    public static var showMe: String { Loc.t("Show me") }
    public static var revealInFinder: String { Loc.t("Reveal in Finder") }
    public static func lifetime(_ n: String) -> String { Loc.f("Elbowroom has returned %@ to this Mac", n) }
    public static func legend(_ n: String) -> String { Loc.f("one square is about %@ at this zoom", n) }
    public static func pebblePile(count: Int, size: String) -> String { Loc.f("+ %1$d smaller · %2$@", count, size) }
    public static var scanningVerify: String { Loc.t("Checking what changed") }
    public static var searchPlaceholder: String { Loc.t("Search") }
    public static var scanAgain: String { Loc.t("Scan again") }
    public static var settingsLabel: String { Loc.t("Settings") }
    public static var everythingElse: String { Loc.t("Everything else") }
    public static var hollowBadgeHelp: String { Loc.t("Freed through the owning app, not by Elbowroom directly.") }
    public static var hideThirtyDays: String { Loc.t("Hide for 30 days") }
    // Tool-mediated cleanup
    public static var cleanUp: String { Loc.t("Clean Up") }
    public static var cleanupListing: String { Loc.t("Asking the tool what can go") }
    public static var cleanupWillRun: String { Loc.t("Elbowroom will run:") }
    public static func runIt(_ n: String) -> String { Loc.f("Run (%@)", n) }
    public static var cleanupNoUndo: String { Loc.t("These delete through the tool itself, not the Trash. Put Back does not apply.") }
    public static var toolMissing: String { Loc.t("The tool for this is not installed.") }
    public static var toolTimedOut: String { Loc.t("The tool did not answer in time.") }
    public static var containerAppStart: String { Loc.t("Start the container app first.") }
    public static func simUnavailable(_ n: Int) -> String { Loc.f("%d unavailable simulators", n) }
    public static var simUnavailableDetail: String { Loc.t("Their runtimes are gone. Xcode cannot boot them again.") }
    public static var simNeverBooted: String { Loc.t("never booted") }
    public static func simSuperseded(_ v: String) -> String { Loc.f("superseded by %@", v) }
    public static var dockerContainers: String { Loc.t("Stopped containers") }
    public static var dockerContainersDetail: String { Loc.t("Exited containers and their writable layers.") }
    public static var dockerImages: String { Loc.t("Unused images") }
    public static var dockerImagesDetail: String { Loc.t("Images no container is using.") }
    public static var dockerImagesWarning: String { Loc.t("Pulling them back takes time and bandwidth.") }
    public static var dockerBuildCache: String { Loc.t("Build cache") }
    public static var dockerBuildCacheDetail: String { Loc.t("Layers docker build keeps for reuse.") }
    public static var dockerVolumes: String { Loc.t("Unused volumes") }
    public static var dockerVolumesDetail: String { Loc.t("Volumes no container references.") }
    public static var dockerVolumesWarning: String { Loc.t("Volumes can hold data you created. Check this only if you are sure.") }
    public static var dockerSweep: String { Loc.t("Full sweep of everything unused") }
    public static var dockerSweepDetail: String { Loc.t("docker system prune removes every unused image, container, volume, and build cache in one pass.") }
    public static func cleanupStays(_ name: String, _ size: String) -> String {
        Loc.f("%1$@ (%2$@) is current and stays.", name, size)
    }
    public static var runtimeCurrentWarning: String {
        Loc.t("The current runtime. Simulators stop working until you add it back.")
    }
    public static func cleanupKeptDevices(_ n: Int) -> String { Loc.f("%d devices used recently stay.", n) }
    public static var simTestClones: String { Loc.t("Test-run simulator clones") }
    public static var simTestClonesDetail: String { Loc.t("Copies xcodebuild makes for parallel testing. Tests remake them when needed.") }
    public static var brewCleanupRow: String { Loc.t("Old versions and stale downloads") }
    public static var brewCleanupDetail: String { Loc.t("brew cleanup keeps what is linked and removes the rest.") }
    // Time Machine local snapshots
    public static var tmGroupTitle: String { Loc.t("Local safety snapshots") }
    public static func tmSnapshotMade(_ when: String) -> String { Loc.f("made %@", when) }
    public static var tmSnapshotWarning: String {
        Loc.t("These are this Mac's local restore points. The next backup runs longer while Time Machine takes fresh ones.")
    }
    public static func tmReassure(_ name: String) -> String {
        Loc.f("Your backup history on '%@' is separate and stays untouched.", name)
    }
    public static var tmNoDestination: String {
        Loc.t("No backup destination is set up, so these snapshots are this Mac's only file history. Deleting them removes the way back to recent versions.")
    }
    public static func tmEstimateNote(_ n: String) -> String {
        Loc.f("Up to %@ comes back. Elbowroom measures the exact amount after the run.", n)
    }
    public static var tmBackupRunning: String { Loc.t("A backup is running right now. Try again after it finishes.") }
    public static func tmOSUpdateStays(_ n: Int) -> String {
        Loc.f(n == 1 ? "%d update snapshot stays. The macOS updater owns it and clears it when the update finishes." : "%d update snapshots stay. The macOS updater owns them and clears them when the update finishes.", n)
    }
    public static var tmAutoTitle: String { Loc.t("Trim these automatically") }
    public static var tmAutoDetail: String {
        Loc.t("macOS has no off switch for local snapshots. When new ones appear, Elbowroom deletes them once the backup finishes. Backups start fresh and can run longer.")
    }
    public static func tmChangeLine(_ n: Int) -> String {
        Loc.f(n == 1 ? "Deleted %d local snapshot" : "Deleted %d local snapshots", n)
    }
    public static func runItUpTo(_ n: String) -> String { Loc.f("Run (up to %@)", n) }
    // Applications
    public static var uninstall: String { Loc.t("Uninstall") }
    public static func uninstallTitle(_ name: String) -> String { Loc.f("Uninstall %@", name) }
    // Messages local trim
    public static var trimLocally: String { Loc.t("Trim Locally") }
    public static var messagesTrimTitle: String { Loc.t("Trim Messages on this Mac") }
    public static var messagesCloudOff: String { Loc.t("Messages in iCloud is off, so this Mac holds the only copy. Elbowroom won't touch it.") }
    public static var photosTrimTitle: String { Loc.t("Trim Photos on this Mac") }
    public static var fdaTitle: String { Loc.t("Full Disk Access") }
    public static var fdaLine: String { Loc.t("Lets the scan read protected folders like Mail and Safari. macOS asks you to grant it in System Settings.") }
    public static var fdaOpen: String { Loc.t("Open System Settings") }
    public static var fdaGranted: String { Loc.t("Granted") }
    public static var hide: String { Loc.t("Hide") }
    public static func hiddenSuggestions(_ n: Int) -> String { Loc.f("%d hidden", n) }
    public static var showHidden: String { Loc.t("Show") }
    public static func appCacheTitle(_ app: String) -> String { Loc.f("%@ cache", app) }
    public static var clearFilter: String { Loc.t("Clear filter") }
    public static func itemCount(_ n: Int) -> String { Loc.f(n == 1 ? "%d item" : "%d items", n) }
    public static var colName: String { Loc.t("Name") }
    public static var colSize: String { Loc.t("Size") }
    public static var colTier: String { Loc.t("Tier") }
    public static var colLastTouched: String { Loc.t("Last touched") }
    public static var putBack: String { Loc.t("Put Back") }
    public static var exportCSV: String { Loc.t("Export CSV") }
    public static var roomToBuild: String { Loc.t("Room to build.") }
    // MARK: Lenses
    public static var lensHint: String { Loc.t("Click to look closer") }
    public static var reclaimAll: String { Loc.t("Reclaim All") }
    public static func remainingStorageBreakdown(_ readable: String, _ unmeasured: String) -> String {
        Loc.f("%@ in scanned files · %@ not matched to readable files", readable, unmeasured)
    }
    public static var remainingStorageDetail: String {
        Loc.t("Scanned files still need useful groups. The unmatched balance can include protected locations and filesystem accounting differences; it is not a cleanup estimate.")
    }
    public static var lensDenLine: String { Loc.t("Some space still needs an explanation. Explore the map for a closer look.") }
    public static func lensIdentified(_ n: String) -> String { Loc.f("%@ named so far", n) }
    public static var lensEmpty: String { Loc.t("No additional storage groups recognized yet. Everything else may still contain space you can reclaim.") }
    public static func lensMediaLine(_ photos: Int, _ videos: Int, _ span: String) -> String {
        Loc.f("%1$d photos, %2$d videos · %3$@", photos, videos, span)
    }
    public static func lensInstallerHave(_ app: String) -> String { Loc.f("%@ is already installed", app) }
    public static func lensDownloadsLine(_ n: Int) -> String {
        Loc.f(n == 1 ? "%d large file" : "%d large files", n)
    }
    public static var lensTwinLine: String { Loc.t("Byte-identical in both places, verified") }
    public static var lensZipLine: String { Loc.t("Its unpacked folder sits right beside it") }
    public static func lensProjectKind(_ marker: String) -> String { Loc.f("%@ project", marker) }
    public static func lensGhostLine(_ when: String) -> String { Loc.f("Nothing inside touched since %@", when) }
    public static func lensVMLine(_ when: String) -> String { Loc.f("Last used %@", when) }
    public static var lensWeightsLine: String { Loc.t("Re-downloadable from its hub") }
    public static func lensGameLine(_ when: String) -> String { Loc.f("Reinstalls from Steam · updated %@", when) }
    // MARK: Warm Instrument briefing (evolved)
    public static var readyToReclaim: String { Loc.t("Ready to reclaim") }
    public static var heroExplainer: String { Loc.t("Caches and derived data apps rebuild on their own. Nothing personal is touched without you choosing it.") }
    public static var biggestWins: String { Loc.t("Biggest wins right now") }
    public static func allItemsLink(_ n: Int) -> String { Loc.f("All %d items", n) }
    public static var addToPlan: String { Loc.t("Add to Plan") }
    public static var inPlan: String { Loc.t("In plan") }
    public static var openMapLink: String { Loc.t("Open the map") }
    public static var growingThisWeek: String { Loc.t("Growing this week") }
    public static var trimmedFootnote: String { Loc.t("↓ means Elbowroom already trimmed it back.") }
    public static func updateCovered(_ need: String, _ free: String) -> String {
        Loc.f("The next macOS update needs about %1$@ free. You have %2$@, so you are covered.", need, free)
    }
    public static var allTimeLabel: String { Loc.t("All time") }
    public static var returnedToMac: String { Loc.t("returned to this Mac.") }
    public static var sortedBySize: String { Loc.t("sorted by size") }
    public static var planSubtitle: String { Loc.t("Everything here is rebuilt or recoverable") }
    public static var clickRegionHint: String { Loc.t("click a region to dig in") }
    public static func scannedAndFree(_ scanned: String, _ free: String) -> String {
        Loc.f("%1$@ scanned · %2$@ free", scanned, free)
    }
    public static var tintTierAreaSize: String { Loc.t("tint = tier · area = size") }
    public static var themeToggleHelp: String { Loc.t("Switch light and dark") }
    public static var themeFollowSystem: String { Loc.t("Follow the system") }
    public static var simDyldTitle: String { Loc.t("Simulator dyld caches") }
    public static var simDyldDetail: String { Loc.t("Prebuilt loader caches. The next simulator boot remakes what it needs.") }
    public static func runtimeCurrentDetail(_ n: String) -> String {
        Loc.f("The current runtime. Xcode downloads about %@ again before simulators next run.", n)
    }
    // MARK: Staleness phrasing
    public static var touchedToday: String { Loc.t("touched today") }
    public static func untouchedDays(_ n: Int) -> String { Loc.f(n == 1 ? "untouched %d day" : "untouched %d days", n) }
    public static func untouchedWeeks(_ n: Int) -> String { Loc.f("untouched %d weeks", n) }
    public static func untouchedMonths(_ n: Int) -> String { Loc.f(n == 1 ? "untouched %d month" : "untouched %d months", n) }
    public static func untouchedYears(_ n: Int) -> String { Loc.f(n == 1 ? "untouched %d year" : "untouched %d years", n) }
    public static var dateToday: String { Loc.t("today") }
    public static var dateYesterday: String { Loc.t("yesterday") }
    public static func daysAgo(_ n: Int) -> String { Loc.f("%d days ago", n) }
    public static func weeksAgo(_ n: Int) -> String { Loc.f("%d weeks ago", n) }
    public static func monthsAgo(_ n: Int) -> String { Loc.f("%d months ago", n) }
    public static func yearsAgo(_ n: Int) -> String { Loc.f("%d years ago", n) }
    // MARK: Reveal door sublines
    public static var doorCrisisLine: String { Loc.t("The quickest safe items, pre-checked.") }
    public static var doorReclaimLine: String { Loc.t("A plan you approve first.") }
    public static var doorExplainLine: String { Loc.t("A treemap of the whole disk.") }
    // Recognized storage groups, mirrored by the Atlas localization keys.
    public static var pipCacheTitle: String { Loc.t("pip cache") }
    public static var pipCacheIdentity: String { Loc.t("Python packages downloaded or built by pip. Removing the cache leaves installed packages in place; future installs may download and build them again.") }
    public static var gradleCacheTitle: String { Loc.t("Gradle caches") }
    public static var gradleCacheIdentity: String { Loc.t("Downloaded dependencies and generated build files. Gradle downloads or rebuilds them when needed. Close Gradle builds before removing them.") }
    public static var musicLibraryTitle: String { Loc.t("Music library") }
    public static var musicLibraryIdentity: String { Loc.t("Music library metadata and playlists. Your music files may live elsewhere; this is personal library data, not a disposable cache.") }
    public static var tvLibraryTitle: String { Loc.t("TV library") }
    public static var tvLibraryIdentity: String { Loc.t("TV library metadata and organization. Downloaded videos may live elsewhere; review your library in TV before changing it.") }
    public static var videoLibraryTitle: String { Loc.t("Video editing library") }
    public static var videoLibraryIdentity: String { Loc.t("Video projects, source media, and generated files kept together. Some media may live elsewhere. Review the library in its editing app; it can contain your only originals.") }
    public static var apertureLibraryTitle: String { Loc.t("Aperture library") }
    public static var apertureLibraryIdentity: String { Loc.t("Photo originals and edits from Aperture. Keep this library until you have verified that its photos are preserved elsewhere.") }

    /// Every representative string, audited in each language.
    // Purpose groups keep the first decision simple; paths remain in details.
    public static var allStorageItems: String { Loc.t("View all items") }
    public static func mergedStorageSummary(_ tier: Tier) -> String {
        switch tier {
        case .regenerable: Loc.t("Your apps can recreate these files.")
        case .rebuildable: Loc.t("Your tools can rebuild these files.")
        case .system: Loc.t("Managed by macOS.")
        default: Loc.t("App data kept in several places.")
        }
    }
    public static func locationCount(_ n: Int) -> String { Loc.f(n == 1 ? "%d location" : "%d locations", n) }
    public static var groupHideDetails: String { Loc.t("Hide details") }
    public static func groupCount(_ n: Int) -> String { Loc.f(n == 1 ? "%d group" : "%d groups", n) }
    public static func groupTotal(_ bytes: String) -> String { Loc.f("%@ total", bytes) }
    public static var reviewCleanup: String { Loc.t("Review cleanup") }
    public static var groupDetails: String { Loc.t("Show details") }
    public static var groupExpanded: String { Loc.t("Expanded") }
    public static var groupCollapsed: String { Loc.t("Collapsed") }
    public static var groupOlderBuilds: String { Loc.t("Build files from projects unchanged for at least 30 days. Your source files stay.") }
    public static func groupCleanupHelp(_ bytes: String) -> String { Loc.f("Review %@ of files your apps can recreate.", bytes) }
    public static func storageGroupTitle(_ group: StorageGroup) -> String {
        switch group {
        case .caches: Loc.t("App and download caches")
        case .builds: Loc.t("Build files")
        case .models: Loc.t("Downloaded models")
        case .appData: Loc.t("App-managed storage")
        case .tools: Loc.t("Developer tools")
        case .applications: Loc.t("Your apps")
        case .personal: Loc.t("Files and history")
        case .system: Loc.t("macOS and services")
        }
    }
    public static func storageGroupExplanation(_ group: StorageGroup) -> String {
        switch group {
        case .caches: Loc.t("Files your apps can fetch or create again.")
        case .builds: Loc.t("Generated files your development tools can rebuild.")
        case .models: Loc.t("Models for local AI features. Removing them means downloading them again.")
        case .appData: Loc.t("Backups, virtual disks and app data. Each app has its own cleanup options.")
        case .tools: Loc.t("Installed tools and extensions. Keep the ones your projects use.")
        case .applications: Loc.t("Apps and the data they keep. Review both before uninstalling.")
        case .personal: Loc.t("Your projects, libraries and saved work. Review individually.")
        case .system: Loc.t("System files and background services, explained without a cleanup recommendation.")
        }
    }
    private static var storageCopy: [String] { [
        Loc.t("Review cleanup"),
        Loc.t("Show details"),
        Loc.t("Expanded"),
        Loc.t("Collapsed"),
        Loc.t("Review %@ of files your apps can recreate."),
        Loc.t("Build files from projects unchanged for at least 30 days. Your source files stay."),
        Loc.t("App and download caches"),
        Loc.t("Files your apps can fetch or create again."),
        Loc.t("Build files"),
        Loc.t("Generated files your development tools can rebuild."),
        Loc.t("Downloaded models"),
        Loc.t("Models for local AI features. Removing them means downloading them again."),
        Loc.t("App-managed storage"),
        Loc.t("Backups, virtual disks and app data. Each app has its own cleanup options."),
        Loc.t("Developer tools"),
        Loc.t("Installed tools and extensions. Keep the ones your projects use."),
        Loc.t("Your apps"),
        Loc.t("Apps and the data they keep. Review both before uninstalling."),
        Loc.t("Files and history"),
        Loc.t("Your projects, libraries and saved work. Review individually."),
        Loc.t("macOS and services"),
        Loc.t("System files and background services, explained without a cleanup recommendation."),
        Loc.t("App cache"),
        Loc.t("Temporary files this app can recreate. Close the app before cleanup; your documents and account data stay."),
        Loc.t("Tool runtimes"),
        Loc.t("Installed dependencies used to run your tools. Keep active versions; their location does not make them disposable caches."),
        Loc.t("Python installations"),
        Loc.t("Python versions your projects may depend on. Remove a version only after checking which environments use it."),
        Loc.t("Editor extensions"),
        Loc.t("Installed editor features. Uninstall extensions in the editor so its settings stay consistent."),
        Loc.t("Assistant work and history"),
        Loc.t("Saved conversations, task files, plugins and settings. These can include work you cannot recreate; review them individually."),
        Loc.t("Search indexes"),
        Loc.t("Indexes macOS uses to find your content. They are separate from your original files and managed by the system."),
        Loc.t("Wallpaper downloads"),
        Loc.t("Desktop backgrounds downloaded by macOS. The system manages these assets."),
        Loc.t("Intelligence and suggestions"),
        Loc.t("Data used by macOS background intelligence and suggestion services. This is system-managed storage."),
        Loc.t("Background services"),
        Loc.t("Data and compiled models kept by system services. The system controls their lifecycle."),
        Loc.t("Shared app data"),
        Loc.t("Support files and shared containers not already counted with an app. They may contain documents and settings; recognition is not a deletion recommendation."),
        Loc.t("Installed packages"),
        Loc.t("Command-line tools and their dependencies. Use the package manager to remove software your projects no longer need."),
        Loc.t("Command Line Tools"),
        Loc.t("Installed compilers and SDKs used by development tools. These are software installations, not project build files."),
        Loc.t("Software update files"),
        Loc.t("Python environments"),
        Loc.t("Python installations and packages used by individual projects. Keep environments needed by active work."),
        Loc.t("Automation runner files"),
        Loc.t("Installed automation tools, updates and job files. These can include active jobs and credentials; they are not disposable caches."),
        Loc.t("Downloaded iCloud files"),
        Loc.t("Local copies of iCloud documents. Deleting a document can delete it from iCloud and your other devices too."),
        Loc.t("Developer support files"),
        Loc.t("Installed developer resources not already listed with a tool or project. Keep resources your development tools still use."),
        Loc.t("Application components"),
        Loc.t("Installed application files not already counted with an app. These can include shared components and supporting tools."),
        Loc.t("APFS container allocation"),
        Loc.t("Space used by the disk container outside the reported volume allocations. This is not a collection of files to delete."),

        Loc.t("Project source and files"),
        Loc.t("Source code and working files in detected projects, excluding separately listed builds and review items. Keep work you still need."),
        Loc.t("Documents and desktop files"),
        Loc.t("Files in Documents and Desktop, excluding items already listed separately. These are personal files to review before deleting."),
        Loc.t("Downloaded files"),
        Loc.t("Files in Downloads, excluding installers and other items already listed separately. Review which downloads you still need."),
        Loc.t("Photos, music and video files"),
        Loc.t("Photos, music and videos, excluding libraries and items already listed separately. These may be your only copies."),

        Loc.t("System diagnostics"),
        Loc.t("Logs and diagnostic databases maintained by macOS. The system manages their retention."),
        Loc.t("System temporary files"),
        Loc.t("Working files and caches used by macOS and apps. Some are in use; the system manages cleanup."),
        Loc.t("Downloaded system assets"),
        Loc.t("Speech, language and other resources downloaded for macOS features. The system manages these downloads."),
        Loc.t("System databases"),
        Loc.t("Settings, service records and other databases used by macOS. Keep these files in place."),
        Loc.t("Document versions"),
        Loc.t("Previous versions of documents kept by macOS. These may be needed to recover earlier work."),

        Loc.t("Downloaded macOS update files. Software Update manages installation and cleanup."),
        Loc.t("Boot support"),
        Loc.t("Files macOS needs to start up. This is not an estimate of space an update will free."),
        Loc.t("The app and its retained data. Caches the app can recreate are listed separately for cleanup."),
        Loc.t("Some space still needs an explanation. Explore the map for a closer look."),
    ] }

    public static var auditableStrings: [String] {
        var all: [String] = storageCopy + [
            allStorageItems, mergedStorageSummary(.regenerable), mergedStorageSummary(.rebuildable),
            mergedStorageSummary(.system), mergedStorageSummary(.apps), locationCount(1), locationCount(3), groupHideDetails, groupCount(1), groupCount(8), groupTotal("12 GB"),
            pipCacheTitle, pipCacheIdentity, gradleCacheTitle, gradleCacheIdentity,
            musicLibraryTitle, musicLibraryIdentity, tvLibraryTitle, tvLibraryIdentity,
            videoLibraryTitle, videoLibraryIdentity, apertureLibraryTitle, apertureLibraryIdentity,
            b1Headline, b1Sub, b1Continue, b2Headline, b2Body, b3Headline, b3Body,
            b3StartScan, b3AlreadyOn, b3Fallback, b3WaitTitle, b3WaitNote,
            b3Relaunch, b3DragHint, b3GuidedTitle, b3GuidedBody, b3HomeNote,
            b3ZoneSkipped, b3Zone(.desktop), b3Zone(.documents), b3Zone(.downloads),
            b3Zone(.photos), b3Zone(.appData),
            b5Sub, b5Crisis, b5ModestSub, b5DoorReclaim,
            b5DoorExplain, b5CrisisDoor("12.4 GB"), b5PartialChip,
            tickerXcode("9.1 GB"), tickerSimulators("14 GB", month: "March"),
            tickerRust("6 GB"), tickerCaches("3 GB"), tickerBackups("8 GB", year: "2023"),
            tickerSnapshots("11 GB"), tickerSlowDisk, tickerNodeModules("4 GB"),
            tierRegenerable, tierRebuildable, tierManaged, tierYours,
            tierLabelRegenerable, tierLabelRebuildable, tierLabelManaged, tierLabelYours,
            planTitle, costLine(tool: "cargo", n: "1.1 GB", t: "2 min"), trashToggle,
            keepInTrashLabel, keepInTrashNote, trashBeatHeadline, trashBeatBody,
            amTitle("iMovie"), amBody, amOpen, amRelaunchNote, uninstallPermissionHelp, uninstallRetry,
            reclaimPrimary("18.2 GB"), reclaimToast("18.2 GB"), partialFail(2),
            firstRebuildable("2 min"), ok, cancel, headroom("41.3 GB"),
            trayCount(3, "18.2 GB"), trayReclaim, trayClear, reclaimStopped(2),
            ineligibleRunning("Xcode"), purgeableExplainer,
            moveFail,
            kibiDenTidy, kibiReceiptsEmpty, kibiChangesQuiet, kibiSearchNone,
            stewardOpen, stewardReclaimable("12.4 GB"), stewardPause, stewardQuit,
            plannerGenericTitle, plannerBody(need: "22 GB", promised: "25 GB", minutes: 4),
            plannerReclaimSection, plannerTeachSection,
            planForUpdate, planRoomForUpdate, freeAmount("24.5 GB"), freeLabel,
            kibiGuess, kibiHedge, kibiUnsure, kibiThinking, askKibi, askKibiReady, askKibiOff,
            viewDen, viewCrossSection, viewLedger, viewChanges, copied, copyCommand,
            showMe, revealInFinder, lifetime("312 GB"), legend("2.1 GB"),
            pebblePile(count: 23, size: "3.1 GB"), scanningVerify,
            searchPlaceholder, scanAgain, settingsLabel,
            everythingElse,
            hollowBadgeHelp,
            hideThirtyDays, hide, hiddenSuggestions(2), showHidden,
            appCacheTitle("Docker"), clearFilter, itemCount(5),
            cleanUp, cleanupListing, cleanupWillRun, runIt("12.4 GB"), copyCommand,
            cleanupNoUndo, toolMissing, toolTimedOut, containerAppStart,
            simUnavailable(4), simUnavailableDetail, simNeverBooted, simSuperseded("iOS 18.2"),
            dockerContainers, dockerContainersDetail, dockerImages, dockerImagesDetail,
            dockerImagesWarning, dockerBuildCache, dockerBuildCacheDetail,
            dockerVolumes, dockerVolumesDetail, dockerVolumesWarning,
            dockerSweep, dockerSweepDetail,
            brewCleanupRow, brewCleanupDetail, fdaTitle, fdaLine, fdaOpen, fdaGranted,
            tmGroupTitle, tmSnapshotMade("yesterday"),
            tmSnapshotWarning, tmReassure("goose-nas"), tmNoDestination,
            tmEstimateNote("38 GB"), tmBackupRunning, tmChangeLine(2), runItUpTo("38 GB"),
            tmAutoTitle, tmAutoDetail, tmOSUpdateStays(1), tmOSUpdateStays(3),
            tierApps, tierSystem, tierLabelApps, tierLabelSystem,
            uninstall, uninstallTitle("Slack"), themeFollowSystem,
            trimLocally, messagesTrimTitle, messagesCloudOff, photosTrimTitle,
            cleanupStays("iOS 26.3", "8.1 GB"), cleanupKeptDevices(7),
            simTestClones, simTestClonesDetail,
            runtimeCurrentWarning,
            colName, colSize, colTier, colLastTouched, putBack, exportCSV,
            doorCrisisLine, doorReclaimLine, doorExplainLine, lensHint, reclaimAll, lensDenLine, lensIdentified("62 GB"), lensEmpty, remainingStorageBreakdown("2 GB", "18 GB"), remainingStorageDetail,
            readyToReclaim, heroExplainer, biggestWins, allItemsLink(39),
            addToPlan, inPlan, openMapLink, growingThisWeek, trimmedFootnote,
            updateCovered("24 GB", "461 GB"), allTimeLabel, returnedToMac, sortedBySize,
            planSubtitle, freeOfTotal("461 GB", "1 TB"),
            clickRegionHint, scannedAndFree("300 GB", "461 GB"), tintTierAreaSize, themeToggleHelp,
            runtimeCurrentDetail("8.3 GB"), simDyldTitle, simDyldDetail,
            lensMediaLine(2431, 12, "2019"), lensInstallerHave("Docker"),
            lensDownloadsLine(41), lensTwinLine, lensZipLine, lensProjectKind("Git"),
            lensGhostLine("2021"), lensVMLine("last year"),
            lensWeightsLine, lensGameLine("2022"),
            roomToBuild, touchedToday, untouchedDays(3), untouchedWeeks(2),
            untouchedMonths(5), untouchedYears(1), dateToday, dateYesterday,
            daysAgo(3), weeksAgo(2), monthsAgo(5), yearsAgo(1)]
        all.append(contentsOf: [dockerOpenFailed, dockerOpenHelp, dockerStartPrompt, dockerStarting, dockerStartupTimeout])
        return all
    }
}
