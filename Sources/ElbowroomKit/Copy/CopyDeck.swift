import Foundation

/// Copy deck. Every user-facing string ships from here; no string ships
/// that is not in, or amended into, this deck. House rules: plain, literal,
/// friendly, useful. Say each thing once. No marketing lines, no exclamation
/// points, and no em-dashes anywhere in the product. Buttons start with verbs.
/// English strings double as localization keys (`Loc`).
public enum Copy {

    // MARK: 11.1 Onboarding

    public static var b1Headline: String { Loc.t("Most of what fills a developer's disk is caches and build output.") }
    public static var b1Sub: String { Loc.t("Elbowroom separates them from your files, then cleans up or offloads.") }
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
    public static var b3DragHint: String { Loc.t("Drag Elbowroom into the list, then turn it on.") }
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
    public static func b5Hero(_ n: String) -> String { Loc.f("You can safely get back %@ today.", n) }
    public static var b5HeroPrefix: String { Loc.t("You can safely get back") }
    public static var b5HeroSuffix: String { Loc.t("today.") }
    public static var b5Sub: String { Loc.t("Every item is identified and rated for safety.") }
    public static var b5Crisis: String { Loc.t("Low on space. Elbowroom picked the quickest safe items first.") }
    public static var b5ModestSub: String { Loc.t("Not much to reclaim right now. Elbowroom will watch for growth.") }
    public static var b5DoorReclaim: String { Loc.t("Reclaim now") }
    public static var b5DoorExplain: String { Loc.t("Open the map") }
    public static var b5DoorStash: String { Loc.t("Set up an offload drive") }
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
    public static var tierYours: String { Loc.t("Your files. Elbowroom never suggests changes here.") }
    public static var tierLabelRegenerable: String { Loc.t("Cache") }
    public static var tierLabelRebuildable: String { Loc.t("Derived") }
    public static var tierLabelManaged: String { Loc.t("App-managed") }
    public static var tierLabelYours: String { Loc.t("Personal") }

    // MARK: 11.4 Reclaim

    public static var planTitle: String { Loc.t("Reclaim plan") }
    public static func costLine(tool: String, n: String, t: String) -> String {
        Loc.f("The next %1$@ run downloads about %2$@ again (%3$@ on your connection)", tool, n, t)
    }
    public static var trashToggle: String { Loc.t("Keep in Trash for 7 days") }
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
    public static var trayStash: String { Loc.t("Offload") }
    public static var trayClear: String { Loc.t("Clear") }
    public static func reclaimStopped(_ n: Int) -> String {
        Loc.f(n == 1 ? "Stopped. %d item was already reclaimed and stays reclaimed." : "Stopped. %d items were already reclaimed and stay reclaimed.", n)
    }

    // MARK: 11.5 Stash

    public static func speedFast(_ n: String) -> String { Loc.f("%@/s. Fast enough for build folders.", n) }
    public static func speedSlow(_ n: String) -> String { Loc.f("%@/s. Fine for archives and model weights, too slow for build folders.", n) }
    public static var tmCard: String { Loc.t("Include the offload folder in Time Machine? Everything in it can be rebuilt, so skipping it is fine.") }
    public static var tmExclude: String { Loc.t("Skip It") }
    public static var tmInclude: String { Loc.t("Include It") }
    public static var toggleTooltip: String { Loc.t("Moves back the same way, any time.") }
    public static func ineligibleRunning(_ app: String) -> String { Loc.f("%@ is running. Quit it first.", app) }
    public static func moveDoneToast(_ n: String) -> String { Loc.f("Offloaded. %@ freed.", n) }
    public static func guardianAbsent(item: String, drive: String) -> String {
        Loc.f("%1$@ is on '%2$@'. Connect it before building.", item, drive)
    }
    public static func guardianEscalation(app: String, item: String, drive: String) -> String {
        Loc.f("%1$@ just opened. Its %2$@ is on '%3$@'.", app, item, drive)
    }
    public static func reconcileTitle(_ item: String) -> String { Loc.f("Two versions of %@", item) }
    public static var reconcilePrimary: String { Loc.t("Merge newer onto the drive and relink") }
    public static var reconcileKeepLocal: String { Loc.t("Keep local") }
    public static func ejectBlocked(_ app: String) -> String { Loc.f("%@ is still using the drive.", app) }
    public static var migrationOffer: String { Loc.t("Set up this Mac like your last one?") }
    public static var offboarding: String { Loc.t("Move everything back") }
    public static var offboardingDone: String { Loc.t("Everything is back on the internal disk. Elbowroom can be removed cleanly now.") }
    public static var needsAPFS: String { Loc.t("Elbowroom needs APFS to move things safely") }
    public static var eraseFormat: String { Loc.t("Erase & Format") }
    public static var stashTitle: String { Loc.t("Offload") }
    public static var stashSetupTitle: String { Loc.t("Set up offloading") }
    public static var stashSetupBody: String { Loc.t("Pick an external drive. Elbowroom moves large derived folders there and leaves a working link in place.") }
    public static var stashNoDrives: String { Loc.t("No external drives found. Plug one in and it appears here.") }
    public static var stashMeasuring: String { Loc.t("Measuring the drive") }
    public static var stashCreate: String { Loc.t("Use This Drive") }
    public static var stashNotConnected: String { Loc.t("not connected") }
    public static func stashConnectFirst(_ drive: String) -> String { Loc.f("Connect '%@' first.", drive) }
    public static func stashOn(_ drive: String, _ n: String) -> String { Loc.f("on '%1$@' · %2$@ offloaded", drive, n) }
    public static func stashMovedAgo(_ when: String) -> String { Loc.f("moved %@", when) }
    public static func stashGroupCount(_ n: Int) -> String { Loc.f("%d locations", n) }
    public static func stashGroupPartial(_ done: String, _ total: String) -> String {
        Loc.f("%1$@ of %2$@ offloaded", done, total)
    }
    public static func stashDirtyBanner(_ name: String) -> String {
        Loc.f("%@ moved, but the old copy is still on the internal disk. Its space is not freed yet.", name)
    }
    public static var tryAgain: String { Loc.t("Try Again") }
    public static func bringingHome(_ name: String) -> String { Loc.f("Moving back %@", name) }
    public static var volNetworkNo: String { Loc.t("Network volumes are not supported yet.") }
    public static var volInternalNo: String { Loc.t("This is an internal partition.") }
    public static var toggleInternal: String { Loc.t("Local") }
    public static var toggleStash: String { Loc.t("Offloaded") }
    public static var reconcileBody: String { Loc.t("A tool rebuilt this folder on the internal disk while the drive was away. Both versions exist now.") }
    public static var reconcileLocalSide: String { Loc.t("On this Mac") }
    public static var reconcileStashSide: String { Loc.t("On the drive") }
    public static var reconcileNewer: String { Loc.t("newer") }
    public static var reconcileMerging: String { Loc.t("Merging") }
    public static var stashDatalessNo: String { Loc.t("Part of this folder is still in iCloud. Download it first.") }
    public static var stashVolumeAbsent: String { Loc.t("The Stash drive is not connected.") }

    // MARK: 11.6 Explainers

    public static var purgeableExplainer: String { Loc.t("macOS keeps files it can delete on its own when space runs low. Finder often counts this space as available. Elbowroom lists it separately.") }
    public static var snapshotsExplainer: String { Loc.t("macOS makes these local backups and thins them on its own. The command below thins them now.") }
    public static func systemDataExplainer(_ topThree: String) -> String {
        Loc.f("What macOS groups under System Data, item by item. The largest parts here: %@.", topThree)
    }

    // MARK: 11.7 Paywall

    public static var paywallTitle: String { Loc.t("Elbowroom Pro") }
    public static var paywallLines: [String] {
        [
            Loc.t("Unlimited reclaim"),
            Loc.t("Offloading to external drives"),
            Loc.t("Background monitoring and update planning"),
            Loc.t("New-Mac migration"),
        ]
    }
    public static var paywallPrice: String { Loc.t("$19.99, one time. No subscription.") }
    public static var paywallButton: String { Loc.t("Unlock Elbowroom Pro") }
    public static var paywallDecline: String { Loc.t("Keep the free tools") }
    public static var paywallBoundary: String { Loc.t("You've used your free 10 GB.") }
    public static var paywallUnavailable: String { Loc.t("The App Store is not reachable from this build.") }
    public static var devUnlock: String { Loc.t("Enable Pro on this Mac") }
    public static var devUnlockDone: String { Loc.t("Pro is enabled on this Mac.") }
    public static var devUnlockNote: String { Loc.t("This build did not come from the App Store, so Pro unlocks locally and free.") }
    public static var paywallRestore: String { Loc.t("Restore Purchase") }

    // MARK: 11.8 Errors

    public static var moveFail: String { Loc.t("That move didn't finish. Nothing was lost. Try again?") }
    public static var verifyFail: String { Loc.t("The copy didn't match, so Elbowroom kept the original. Try again?") }
    public static func driveFull(_ drive: String) -> String { Loc.f("'%@' ran out of room mid-move. The original is untouched.", drive) }
    public static var scanDenied: String { Loc.t("macOS blocked a few areas. Everything else is accurate.") }

    // MARK: 11.9 Kibi lines (empty states, short always)

    public static var kibiDenTidy: String { Loc.t("Nothing to clean right now.") }
    public static var kibiReceiptsEmpty: String { Loc.t("No receipts yet.") }
    public static var kibiStashEmpty: String { Loc.t("Nothing offloaded yet.") }
    public static var kibiChangesQuiet: String { Loc.t("No changes this week.") }
    public static var kibiSearchNone: String { Loc.t("No matches.") }

    // MARK: Steward

    public static func plannerNotification(version: String, need: String, minutes: Int) -> String {
        Loc.f("macOS %1$@ needs %2$@. Elbowroom has a %3$d-minute plan. Review it?", version, need, minutes)
    }
    public static func plannerSheetTitle(_ version: String) -> String { Loc.f("Room for macOS %@", version) }
    public static func plannerDone(_ free: String) -> String { Loc.f("Ready to update. %@ free.", free) }
    public static var stewardOpen: String { Loc.t("Open Elbowroom") }
    public static func stewardReclaimable(_ n: String) -> String { Loc.f("Reclaimable now: %@", n) }
    public static var stewardEject: String { Loc.t("Safe Eject") }
    public static var stewardPause: String { Loc.t("Pause a while") }
    public static var stewardQuit: String { Loc.t("Quit Elbowroom") }
    public static var plannerGenericTitle: String { Loc.t("Room for an update") }
    public static func plannerBody(need: String, promised: String, minutes: Int) -> String {
        Loc.f("The update needs %1$@ more than is free. This plan clears %2$@ in about %3$d minutes.", need, promised, minutes)
    }
    public static var plannerReclaimSection: String { Loc.t("Reclaim") }
    public static var plannerStashSection: String { Loc.t("Move to the Stash") }
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
    public static var whatIsThis: String { Loc.t("What is this?") }
    public static func lifetime(_ n: String) -> String { Loc.f("Elbowroom has returned %@ to this Mac", n) }
    public static func legend(_ n: String) -> String { Loc.f("one square is about %@ at this zoom", n) }
    public static func pebblePile(count: Int, size: String) -> String { Loc.f("+ %1$d smaller · %2$@", count, size) }
    public static var scanningVerify: String { Loc.t("Checking what changed") }
    public static var thisWeek: String { Loc.t("This week") }
    public static var expandAccess: String { Loc.t("Expand access") }
    public static var searchPlaceholder: String { Loc.t("Search") }
    public static var scanAgain: String { Loc.t("Scan again") }
    public static var settingsLabel: String { Loc.t("Settings") }
    public static func insideOf(_ name: String) -> String { Loc.f("Inside %@", name) }
    public static var everythingElse: String { Loc.t("Everything else") }
    public static var yourFilesAndApps: String { Loc.t("Your files and apps") }
    public static var smallFilesLine: String { Loc.t("Files too small to draw one by one.") }
    public static var smallerItemsPile: String { Loc.t("Smaller items, one pile.") }
    public static var backToWholeDisk: String { Loc.t("Back to the whole disk") }
    public static var returnOpens: String { Loc.t("Return key opens") }
    public static var inStashBadge: String { Loc.t("Offloaded. Size counts on the drive.") }
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
    public static var dockerImagesInUse: String { Loc.t("Images your containers use") }
    public static var dockerVolumesInUse: String { Loc.t("Volumes in use") }
    public static var dockerContainersRunning: String { Loc.t("Running containers") }
    public static var dockerSystemOverhead: String { Loc.t("Docker's Linux system") }
    public static var dockerSweep: String { Loc.t("Full sweep of everything unused") }
    public static var dockerSweepDetail: String { Loc.t("docker system prune removes every unused image, container, volume, and build cache in one pass.") }
    public static func dockerVMNote(_ n: String) -> String {
        Loc.f("The row's %@ is Docker's virtual disk: your images and volumes plus the small Linux system they run in. These rows free space inside it, and Docker hands freed space back to macOS automatically.", n)
    }
    public static func cleanupStays(_ name: String, _ size: String) -> String {
        Loc.f("%1$@ (%2$@) is current and stays.", name, size)
    }
    public static func runtimeOffloadDetail(_ drive: String) -> String {
        Loc.f("Copies the image to '%@' first, then deletes it here. Adding back needs no download.", drive)
    }
    public static var runtimeCurrentWarning: String {
        Loc.t("The current runtime. Simulators stop working until you add it back.")
    }
    public static func runtimeAddBack(_ drive: String) -> String {
        Loc.f("On '%@'. Adds back without downloading.", drive)
    }
    public static var runtimeCatalogLine: String { Loc.t("Sealed by macOS. Offloads through Xcode's tool instead.") }
    public static func ledgerOffloaded(_ n: Int, _ size: String, _ drive: String) -> String {
        Loc.f("%1$d offloaded · %2$@ on '%3$@'", n, size, drive)
    }
    public static var addBack: String { Loc.t("Add Back") }
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
    public static var fdaTitle: String { Loc.t("Full Disk Access") }
    public static var fdaLine: String { Loc.t("Lets the scan read protected folders like Mail and Safari. macOS asks you to grant it in System Settings.") }
    public static var fdaOpen: String { Loc.t("Open System Settings") }
    public static var fdaGranted: String { Loc.t("Granted") }
    public static var hide: String { Loc.t("Hide") }
    public static var suggestedMoves: String { Loc.t("Suggested moves") }
    public static func hiddenSuggestions(_ n: Int) -> String { Loc.f("%d hidden", n) }
    public static var showHidden: String { Loc.t("Show") }
    public static func appCacheTitle(_ app: String) -> String { Loc.f("%@ cache", app) }
    public static var selectAllRegenerable: String { Loc.t("Select all caches") }
    public static var selectStale: String { Loc.t("Select stale > 90 days") }
    public static var clearFilter: String { Loc.t("Clear filter") }
    public static func itemCount(_ n: Int) -> String { Loc.f(n == 1 ? "%d item" : "%d items", n) }
    public static var colName: String { Loc.t("Name") }
    public static var colSize: String { Loc.t("Size") }
    public static var colTier: String { Loc.t("Tier") }
    public static var colOwner: String { Loc.t("Owner") }
    public static var colLastTouched: String { Loc.t("Last touched") }
    public static var putBack: String { Loc.t("Put Back") }
    public static var exportCSV: String { Loc.t("Export CSV") }
    public static var roomToBuild: String { Loc.t("Room to build.") }

    // MARK: Lenses

    public static var lensHint: String { Loc.t("Click to look closer") }
    public static var lookCloser: String { Loc.t("Look Closer") }
    public static var reclaimAll: String { Loc.t("Reclaim All") }
    public static var lensDenLine: String { Loc.t("Photos, VMs, installers, and old downloads hide in here. Lenses name them.") }
    public static func lensIdentified(_ n: String) -> String { Loc.f("%@ named so far", n) }
    public static var lensEmpty: String { Loc.t("Nothing recognizable in Everything else. It is genuinely yours.") }
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
    public static var offloadInstead: String { Loc.t("Offload instead") }
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
    public static var doorStashLine: String { Loc.t("Move big folders to an external drive.") }
    public static var doorStashModestLine: String { Loc.t("Keep them one link away.") }
    public static var offboardHelp: String { Loc.t("Reverses every move, then Elbowroom can be deleted cleanly.") }

    /// Every representative string, for the copy-rule tests (: no em-dashes,
    /// no exclamation points; audited per language).
    public static var auditableStrings: [String] {
        var all: [String] = [
            b1Headline, b1Sub, b1Continue, b2Headline, b2Body, b3Headline, b3Body,
            b3StartScan, b3AlreadyOn, b3Fallback, b3WaitTitle, b3WaitNote,
            b3Relaunch, b3DragHint, b3GuidedTitle, b3GuidedBody, b3HomeNote,
            b3ZoneSkipped, b3Zone(.desktop), b3Zone(.documents), b3Zone(.downloads),
            b3Zone(.photos), b3Zone(.appData),
            b5Hero("41.3 GB"), b5Sub, b5Crisis, b5ModestSub, b5DoorReclaim,
            b5DoorExplain, b5DoorStash, b5CrisisDoor("12.4 GB"), b5PartialChip,
            tickerXcode("9.1 GB"), tickerSimulators("14 GB", month: "March"),
            tickerRust("6 GB"), tickerCaches("3 GB"), tickerBackups("8 GB", year: "2023"),
            tickerSnapshots("11 GB"), tickerSlowDisk, tickerNodeModules("4 GB"),
            tierRegenerable, tierRebuildable, tierManaged, tierYours,
            tierLabelRegenerable, tierLabelRebuildable, tierLabelManaged, tierLabelYours,
            planTitle, costLine(tool: "cargo", n: "1.1 GB", t: "2 min"), trashToggle,
            reclaimPrimary("18.2 GB"), reclaimToast("18.2 GB"), partialFail(2),
            firstRebuildable("2 min"), ok, cancel, headroom("41.3 GB"),
            trayCount(3, "18.2 GB"), trayReclaim, trayStash, trayClear, reclaimStopped(2),
            speedFast("780 MB"), speedSlow("140 MB"), tmCard, tmExclude, tmInclude,
            toggleTooltip, ineligibleRunning("Xcode"), moveDoneToast("12 GB"),
            guardianAbsent(item: "Simulators", drive: "Dev Drive"),
            guardianEscalation(app: "Xcode", item: "build folder", drive: "Dev Drive"),
            reconcileTitle("DerivedData"), reconcilePrimary, reconcileKeepLocal,
            ejectBlocked("Xcode"), migrationOffer, offboarding, offboardingDone,
            needsAPFS, eraseFormat, stashTitle, stashSetupTitle, stashSetupBody,
            stashNoDrives, stashMeasuring, stashCreate, stashNotConnected,
            stashConnectFirst("Dev Drive"), stashOn("Dev Drive", "122 GB"),
            stashDirtyBanner("DerivedData"), tryAgain, bringingHome("DerivedData"),
            stashGroupCount(3), stashGroupPartial("1.2 GB", "5.2 GB"),
            volNetworkNo, volInternalNo, toggleInternal, toggleStash,
            reconcileBody, reconcileLocalSide, reconcileStashSide, reconcileNewer,
            reconcileMerging, stashDatalessNo, stashVolumeAbsent,
            purgeableExplainer, snapshotsExplainer, systemDataExplainer("Xcode, Docker, caches"),
            paywallTitle, paywallPrice, paywallButton, paywallDecline, paywallBoundary,
            paywallUnavailable, paywallRestore, devUnlock, devUnlockDone, devUnlockNote,
            moveFail, verifyFail, driveFull("Dev Drive"), scanDenied,
            kibiDenTidy, kibiReceiptsEmpty, kibiStashEmpty, kibiChangesQuiet, kibiSearchNone,
            plannerNotification(version: "27.1", need: "22 GB", minutes: 4),
            plannerSheetTitle("27.1"), plannerDone("24.5 GB"),
            stewardOpen, stewardReclaimable("12.4 GB"), stewardEject, stewardPause, stewardQuit,
            plannerGenericTitle, plannerBody(need: "22 GB", promised: "25 GB", minutes: 4),
            plannerReclaimSection, plannerStashSection, plannerTeachSection,
            planForUpdate, planRoomForUpdate, freeAmount("24.5 GB"), freeLabel,
            kibiGuess, kibiHedge, kibiUnsure, kibiThinking, askKibi, askKibiReady, askKibiOff,
            viewDen, viewCrossSection, viewLedger, viewChanges, copied, copyCommand,
            showMe, revealInFinder, whatIsThis, lifetime("312 GB"), legend("2.1 GB"),
            pebblePile(count: 23, size: "3.1 GB"), scanningVerify, thisWeek, expandAccess,
            searchPlaceholder, scanAgain, settingsLabel, insideOf("DerivedData"),
            everythingElse, yourFilesAndApps, smallFilesLine, smallerItemsPile,
            backToWholeDisk, returnOpens, inStashBadge, hollowBadgeHelp,
            hideThirtyDays, hide, suggestedMoves, hiddenSuggestions(2), showHidden,
            appCacheTitle("Docker"), selectAllRegenerable, selectStale, clearFilter, itemCount(5),
            cleanUp, cleanupListing, cleanupWillRun, runIt("12.4 GB"), copyCommand,
            cleanupNoUndo, toolMissing, toolTimedOut, containerAppStart,
            simUnavailable(4), simUnavailableDetail, simNeverBooted, simSuperseded("iOS 18.2"),
            dockerContainers, dockerContainersDetail, dockerImages, dockerImagesDetail,
            dockerImagesWarning, dockerBuildCache, dockerBuildCacheDetail,
            dockerVolumes, dockerVolumesDetail, dockerVolumesWarning, dockerVMNote("4.8 GB"),
            dockerSweep, dockerSweepDetail, dockerImagesInUse, dockerVolumesInUse,
            dockerContainersRunning, dockerSystemOverhead,
            brewCleanupRow, brewCleanupDetail, fdaTitle, fdaLine, fdaOpen, fdaGranted,
            tmGroupTitle, tmSnapshotMade("yesterday"),
            tmSnapshotWarning, tmReassure("goose-nas"), tmNoDestination,
            tmEstimateNote("38 GB"), tmBackupRunning, tmChangeLine(2), runItUpTo("38 GB"),
            tmAutoTitle, tmAutoDetail, tmOSUpdateStays(1), tmOSUpdateStays(3),
            cleanupStays("iOS 26.3", "8.1 GB"), cleanupKeptDevices(7),
            simTestClones, simTestClonesDetail,
            runtimeOffloadDetail("Dev Drive"), runtimeCurrentWarning,
            runtimeAddBack("Dev Drive"), runtimeCatalogLine,
            ledgerOffloaded(3, "12.4 GB", "Dev Drive"), addBack,
            colName, colSize, colTier, colOwner, colLastTouched, putBack, exportCSV,
            doorCrisisLine, doorReclaimLine, doorExplainLine, doorStashLine,
            doorStashModestLine, offboardHelp,
            lensHint, lookCloser, reclaimAll, lensDenLine, lensIdentified("62 GB"), lensEmpty,
            readyToReclaim, heroExplainer, offloadInstead, biggestWins, allItemsLink(39),
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
            daysAgo(3), weeksAgo(2), monthsAgo(5), yearsAgo(1),
        ]
        all.append(contentsOf: paywallLines)
        return all
    }
}
