import Foundation

/// The v1.0 pack data: Xcode, JavaScript, Rust, Homebrew, Containers,
/// System residue, plus the ML-weights entries.
/// Packs are data; the classifier below matches scan nodes against them.
public enum Atlas {

    public static let entries: [String: AtlasEntry] = {
        var map: [String: AtlasEntry] = [:]
        for e in all { map[e.id] = e }
        return map
    }()

    public static func entry(_ id: String) -> AtlasEntry {
        entries[id] ?? AtlasEntry(
            id: id, pack: .systemResidue, title: id, identityLine: "",
            owner: "Personal", tier: .yours, cost: .none
        )
    }

    private static let all: [AtlasEntry] = [
        AtlasEntry(id: "storage.pythonEnvironments", pack: .systemResidue,
                   title: "Python environments", identityLine: "Python installations and packages used by individual projects. Keep environments needed by active work.",
                   owner: "Python", tier: .apps, cost: .none),
        AtlasEntry(id: "storage.runners", pack: .systemResidue,
                   title: "Automation runner files", identityLine: "Installed automation tools, updates and job files. These can include active jobs and credentials; they are not disposable caches.",
                   owner: "Apps", tier: .apps, cost: .none),
        AtlasEntry(id: "storage.cloudFiles", pack: .systemResidue,
                   title: "Downloaded iCloud files", identityLine: "Local copies of iCloud documents. Deleting a document can delete it from iCloud and your other devices too.",
                   owner: "iCloud", tier: .yours, cost: .none),
        AtlasEntry(id: "storage.developer", pack: .systemResidue,
                   title: "Developer support files", identityLine: "Installed developer resources not already listed with a tool or project. Keep resources your development tools still use.",
                   owner: "Apps", tier: .apps, cost: .none),
        AtlasEntry(id: "storage.software", pack: .systemResidue,
                   title: "Application components", identityLine: "Installed application files not already counted with an app. These can include shared components and supporting tools.",
                   owner: "Apps", tier: .apps, cost: .none),
        AtlasEntry(id: "storage.container", pack: .systemResidue,
                   title: "APFS container allocation", identityLine: "Space used by the disk container outside the reported volume allocations. This is not a collection of files to delete.",
                   owner: "macOS", tier: .system, cost: .none),

        AtlasEntry(id: "storage.projects", pack: .systemResidue,
                   title: "Project source and files", identityLine: "Source code and working files in detected projects, excluding separately listed builds and review items. Keep work you still need.",
                   owner: "Personal", tier: .yours, cost: .none),
        AtlasEntry(id: "storage.documents", pack: .systemResidue,
                   title: "Documents and desktop files", identityLine: "Files in Documents and Desktop, excluding items already listed separately. These are personal files to review before deleting.",
                   owner: "Personal", tier: .yours, cost: .none),
        AtlasEntry(id: "storage.downloads", pack: .systemResidue,
                   title: "Downloaded files", identityLine: "Files in Downloads, excluding installers and other items already listed separately. Review which downloads you still need.",
                   owner: "Personal", tier: .yours, cost: .none),
        AtlasEntry(id: "storage.media", pack: .systemResidue,
                   title: "Photos, music and video files", identityLine: "Photos, music and videos, excluding libraries and items already listed separately. These may be your only copies.",
                   owner: "Personal", tier: .yours, cost: .none),

        AtlasEntry(id: "storage.revisions", pack: .systemResidue,
                   title: "Document versions",
                   identityLine: "Previous versions of documents kept by macOS. These may be needed to recover earlier work.",
                   owner: "macOS", tier: .system, cost: .none),
        AtlasEntry(id: "storage.databases", pack: .systemResidue,
                   title: "System databases",
                   identityLine: "Settings, service records and other databases used by macOS. Keep these files in place.",
                   owner: "macOS", tier: .system, cost: .none),
        AtlasEntry(id: "storage.assets", pack: .systemResidue,
                   title: "Downloaded system assets",
                   identityLine: "Speech, language and other resources downloaded for macOS features. The system manages these downloads.",
                   owner: "macOS", tier: .system, cost: .none),
        AtlasEntry(id: "storage.temporary", pack: .systemResidue,
                   title: "System temporary files",
                   identityLine: "Working files and caches used by macOS and apps. Some are in use; the system manages cleanup.",
                   owner: "macOS", tier: .system, cost: .none),
        AtlasEntry(id: "storage.diagnostics", pack: .systemResidue,
                   title: "System diagnostics",
                   identityLine: "Logs and diagnostic databases maintained by macOS. The system manages their retention.",
                   owner: "macOS", tier: .system, cost: .none),
        AtlasEntry(id: "storage.appCache", pack: .systemResidue,
                   title: "App cache",
                   identityLine: "Temporary files this app can recreate. Close the app before cleanup; your documents and account data stay.",
                   owner: "Apps", tier: .regenerable, cost: .refills),
        AtlasEntry(id: "storage.toolRuntime", pack: .systemResidue,
                   title: "Tool runtimes",
                   identityLine: "Installed dependencies used to run your tools. Keep active versions; their location does not make them disposable caches.",
                   owner: "Apps", tier: .apps, cost: .none),
        AtlasEntry(id: "storage.toolPython", pack: .systemResidue,
                   title: "Python installations",
                   identityLine: "Python versions your projects may depend on. Remove a version only after checking which environments use it.",
                   owner: "Apps", tier: .apps, cost: .none),
        AtlasEntry(id: "storage.toolExtensions", pack: .systemResidue,
                   title: "Editor extensions",
                   identityLine: "Installed editor features. Uninstall extensions in the editor so its settings stay consistent.",
                   owner: "Apps", tier: .apps, cost: .none),
        AtlasEntry(id: "storage.historyAssistant", pack: .systemResidue,
                   title: "Assistant work and history",
                   identityLine: "Saved conversations, task files, plugins and settings. These can include work you cannot recreate; review them individually.",
                   owner: "Apps", tier: .yours, cost: .none),
        AtlasEntry(id: "storage.search", pack: .systemResidue,
                   title: "Search indexes",
                   identityLine: "Indexes macOS uses to find your content. They are separate from your original files and managed by the system.",
                   owner: "macOS", tier: .system, cost: .none),
        AtlasEntry(id: "storage.wallpaper", pack: .systemResidue,
                   title: "Wallpaper downloads",
                   identityLine: "Desktop backgrounds downloaded by macOS. The system manages these assets.",
                   owner: "macOS", tier: .system, cost: .none),
        AtlasEntry(id: "storage.intelligence", pack: .systemResidue,
                   title: "Intelligence and suggestions",
                   identityLine: "Data used by macOS background intelligence and suggestion services. This is system-managed storage.",
                   owner: "macOS", tier: .system, cost: .none),
        AtlasEntry(id: "storage.services", pack: .systemResidue,
                   title: "Background services",
                   identityLine: "Data and compiled models kept by system services. The system controls their lifecycle.",
                   owner: "macOS", tier: .system, cost: .none),
        AtlasEntry(id: "storage.sharedData", pack: .systemResidue,
                   title: "Shared app data",
                   identityLine: "Support files and shared containers not already counted with an app. They may contain documents and settings; recognition is not a deletion recommendation.",
                   owner: "Apps", tier: .apps, cost: .none),
        AtlasEntry(id: "storage.toolPackages", pack: .systemResidue,
                   title: "Installed packages",
                   identityLine: "Command-line tools and their dependencies. Use the package manager to remove software your projects no longer need.",
                   owner: "Apps", tier: .apps, cost: .none),
        AtlasEntry(id: "storage.toolSDK", pack: .systemResidue,
                   title: "Command Line Tools",
                   identityLine: "Installed compilers and SDKs used by development tools. These are software installations, not project build files.",
                   owner: "Apps", tier: .apps, cost: .none),
        AtlasEntry(id: "storage.update", pack: .systemResidue,
                   title: "Software update files",
                   identityLine: "Downloaded macOS update files. Software Update manages installation and cleanup.",
                   owner: "macOS", tier: .system, cost: .none),

        AtlasEntry(
            id: "py.pipCache", pack: .systemResidue,
            title: "pip cache",
            identityLine: "Python packages downloaded or built by pip. Removing the cache leaves installed packages in place; future installs may download and build them again.",
            owner: "pip", tier: .regenerable, cost: .redownload(fraction: 1.0, tool: "pip")
        ),
        AtlasEntry(
            id: "gradle.caches", pack: .systemResidue,
            title: "Gradle caches",
            identityLine: "Downloaded dependencies and generated build files. Gradle downloads or rebuilds them when needed. Close Gradle builds before removing them.",
            owner: "Gradle", tier: .rebuildable, cost: .rebuild(secondsPerGB: 150)
        ),
        AtlasEntry(
            id: "personal.musicLibrary", pack: .systemResidue,
            title: "Music library",
            identityLine: "Music library metadata and playlists. Your music files may live elsewhere; this is personal library data, not a disposable cache.",
            owner: "Music", tier: .yours, cost: .none
        ),
        AtlasEntry(
            id: "personal.tvLibrary", pack: .systemResidue,
            title: "TV library",
            identityLine: "TV library metadata and organization. Downloaded videos may live elsewhere; review your library in TV before changing it.",
            owner: "TV", tier: .yours, cost: .none
        ),
        AtlasEntry(
            id: "personal.videoLibrary", pack: .systemResidue,
            title: "Video editing library",
            identityLine: "Video projects, source media, and generated files kept together. Some media may live elsewhere. Review the library in its editing app; it can contain your only originals.",
            owner: "Video", tier: .yours, cost: .none
        ),
        AtlasEntry(
            id: "personal.apertureLibrary", pack: .systemResidue,
            title: "Aperture library",
            identityLine: "Photo originals and edits from Aperture. Keep this library until you have verified that its photos are preserved elsewhere.",
            owner: "Aperture", tier: .yours, cost: .none
        ),

        // MARK: Xcode
        AtlasEntry(
            id: "xcode.derivedData", pack: .xcode,
            title: "Xcode build products",
            identityLine: "Intermediate build files. Xcode remakes them on the next build.",
            owner: "Xcode", tier: .rebuildable,
            cost: .rebuild(secondsPerGB: 150),
            ticker: { Copy.tickerXcode($0) }
        ),
        AtlasEntry(
            id: "xcode.archives", pack: .xcode,
            title: "Xcode archives",
            identityLine: "Past app builds and their debug symbols. Keep them if you shipped those builds.",
            owner: "Xcode", tier: .yours,
            cost: .none
        ),
        AtlasEntry(
            id: "xcode.deviceSupport", pack: .xcode,
            title: "Device support files",
            identityLine: "Debug files copied from each iPhone or iPad you plugged in. They copy over again on the next connection.",
            owner: "Xcode", tier: .regenerable,
            cost: .redownload(fraction: 0.6, tool: "device connection"),
            ticker: { Copy.tickerGeneric("device support files", $0) }
        ),
        AtlasEntry(
            id: "xcode.simDevices", pack: .xcode,
            title: "Simulator devices",
            identityLine: "The simulated iPhones and iPads Xcode created, with their apps and data.",
            owner: "Simulator", tier: .managed,
            teachFlow: .simulatorRuntimes,
            cost: .none,
            ticker: { Copy.tickerSimulators($0, month: "a while") }
        ),
        // The one Simulator row (post-pass merges runtimes, devices, and
        // test clones into it); a single sheet lists everything.
        AtlasEntry(
            id: "xcode.simulator", pack: .xcode,
            title: "Simulator",
            identityLine: "Runtimes, simulated devices, and caches for Xcode's simulators, together.",
            owner: "Simulator", tier: .managed,
            teachFlow: .simulatorRuntimes,
            cost: .none
        ),
        // Parallel-testing clones pile up unseen; they clean through the
        // same simulator sheet as devices, never a second door.
        AtlasEntry(
            id: "xcode.testDevices", pack: .xcode,
            title: "Test-run simulator clones",
            identityLine: "Copies xcodebuild makes for parallel testing. Tests remake them when needed.",
            owner: "Simulator", tier: .managed,
            teachFlow: .simulatorRuntimes,
            cost: .none
        ),
        AtlasEntry(
            id: "xcode.simRuntimes", pack: .xcode,
            title: "Simulator runtimes",
            identityLine: "Re-downloadable OS images for the simulator. Xcode's own panel removes them safely.",
            owner: "Simulator", tier: .managed, teachFlow: .simulatorRuntimes,
            cost: .redownload(fraction: 1.0, tool: "runtime download")
        ),
        AtlasEntry(
            id: "xcode.simCaches", pack: .xcode,
            title: "Simulator caches",
            identityLine: "Scratch files the simulator refills as it runs.",
            owner: "Simulator", tier: .regenerable
        ),
        AtlasEntry(
            id: "xcode.spmCache", pack: .xcode,
            title: "Swift package caches",
            identityLine: "Downloaded package sources. They download again when a build needs them.",
            owner: "Xcode", tier: .regenerable,
            cost: .redownload(fraction: 0.6, tool: "package resolve"),
            ticker: { Copy.tickerCaches($0) }
        ),
        AtlasEntry(
            id: "xcode.spmBuild", pack: .xcode,
            title: "Swift package build folder",
            identityLine: "Build output for a Swift package. The next build remakes it.",
            owner: "Swift", tier: .rebuildable,
            cost: .rebuild(secondsPerGB: 180)
        ),
        AtlasEntry(
            id: "xcode.previews", pack: .xcode,
            title: "SwiftUI preview data",
            identityLine: "Simulators and caches used by Xcode previews. They rebuild on the next preview.",
            owner: "Xcode", tier: .regenerable
        ),
        AtlasEntry(
            id: "xcode.cache", pack: .xcode,
            title: "Xcode caches",
            identityLine: "Scratch files Xcode refills as it runs.",
            owner: "Xcode", tier: .regenerable
        ),

        // MARK: JavaScript
        AtlasEntry(
            id: "js.nodeModules", pack: .javascript,
            title: "JavaScript packages",
            identityLine: "Installed packages for one project. The next install remakes the folder.",
            owner: "npm", tier: .rebuildable,
            cost: .redownload(fraction: 0.35, tool: "npm install"),
            ticker: { Copy.tickerNodeModules($0) }
        ),
        AtlasEntry(
            id: "js.npmCache", pack: .javascript,
            title: "npm cache",
            identityLine: "Downloaded package archives. npm refills this as you install.",
            owner: "npm", tier: .regenerable,
            ticker: { Copy.tickerCaches($0) }
        ),
        AtlasEntry(
            id: "js.pnpmStore", pack: .javascript,
            title: "pnpm store",
            identityLine: "The shared package store pnpm links projects to. It refills on install.",
            owner: "pnpm", tier: .regenerable,
            ticker: { Copy.tickerCaches($0) }
        ),
        AtlasEntry(
            id: "js.yarnCache", pack: .javascript,
            title: "Yarn cache",
            identityLine: "Downloaded package archives. Yarn refills this as you install.",
            owner: "Yarn", tier: .regenerable
        ),
        AtlasEntry(
            id: "js.bunCache", pack: .javascript,
            title: "Bun cache",
            identityLine: "Downloaded package archives. Bun refills this as you install.",
            owner: "Bun", tier: .regenerable
        ),

        // MARK: Rust
        AtlasEntry(
            id: "rust.target", pack: .rust,
            title: "Rust build folder",
            identityLine: "Compiled output for one project. The next cargo build remakes it.",
            owner: "Rust", tier: .rebuildable,
            cost: .rebuild(secondsPerGB: 240),
            ticker: { Copy.tickerRust($0) }
        ),
        AtlasEntry(
            id: "rust.cargoRegistry", pack: .rust,
            title: "Cargo registry",
            identityLine: "Downloaded crate sources shared by your Rust projects. Cargo refills it on the next fetch.",
            owner: "Rust", tier: .regenerable,
            cost: .redownload(fraction: 0.5, tool: "cargo fetch"),
            ticker: { Copy.tickerCaches($0) }
        ),
        AtlasEntry(
            id: "rust.cargoGit", pack: .rust,
            title: "Cargo git checkouts",
            identityLine: "Git dependencies cargo cloned. They clone again when needed.",
            owner: "Rust", tier: .regenerable
        ),

        // MARK: Homebrew
        AtlasEntry(
            id: "brew.cache", pack: .homebrew,
            title: "Homebrew downloads",
            identityLine: "Installer archives Homebrew already used. It downloads fresh ones when needed.",
            owner: "Homebrew", tier: .regenerable,
            ticker: { Copy.tickerCaches($0) }
        ),
        AtlasEntry(
            id: "brew.cellarOld", pack: .homebrew,
            title: "Homebrew old versions",
            identityLine: "Older versions kept beside the current ones. brew cleanup removes them safely.",
            owner: "Homebrew", tier: .managed, teachFlow: .brewCleanup,
            cost: .none
        ),

        // MARK: Containers
        AtlasEntry(
            id: "docker.data", pack: .containers,
            title: "Docker Desktop data",
            identityLine: "Docker's virtual disk with your images, containers, and volumes.",
            owner: "Docker", tier: .managed, teachFlow: .docker,
            cost: .none,
            ticker: { Copy.tickerGeneric("Docker data", $0) }
        ),
        AtlasEntry(
            id: "orbstack.data", pack: .containers,
            title: "OrbStack data",
            identityLine: "OrbStack's virtual disk with your machines, images, and volumes.",
            owner: "OrbStack", tier: .managed, teachFlow: .orbstack,
            cost: .none
        ),

        // MARK: System residue
        AtlasEntry(
            id: "sys.iosBackups", pack: .systemResidue,
            title: "iPhone and iPad backups",
            identityLine: "Full device backups Finder made. Finder's own panel manages them.",
            owner: "Finder", tier: .managed, teachFlow: .deviceBackups,
            cost: .none,
            ticker: { Copy.tickerBackups($0, year: "past years") }
        ),
        AtlasEntry(
            id: "sys.trash", pack: .systemResidue,
            title: "Trash",
            identityLine: "Files you already deleted. Emptying the Trash frees them for good.",
            owner: "Finder", tier: .managed, teachFlow: .trash,
            cost: .none
        ),
        AtlasEntry(
            id: "sys.appCache", pack: .systemResidue,
            title: "App cache",
            identityLine: "Scratch files this app refills as it runs.",
            owner: "macOS", tier: .regenerable
        ),
        AtlasEntry(
            id: "sys.purgeable", pack: .systemResidue,
            title: "Purgeable space",
            identityLine: "macOS keeps files it can delete on its own when space runs low. Finder often counts this space as available. Elbowroom lists it separately.",
            owner: "macOS", tier: .system, teachFlow: .purgeable,
            cost: .none
        ),
        AtlasEntry(
            id: "sys.messages", pack: .systemResidue,
            title: "Messages history",
            identityLine: "Every conversation and attachment Messages ever received. Its own settings trim them safely.",
            owner: "Messages", tier: .managed, teachFlow: .messages,
            cost: .none
        ),
        AtlasEntry(
            id: "sys.messagesAttachments", pack: .systemResidue,
            title: "Message attachments",
            identityLine: "Received attachments. They stay in iCloud and on your other devices, and download again when you open old conversations. Ones not yet uploaded to iCloud would be lost.",
            owner: "Messages", tier: .managed, teachFlow: .messages,
            cost: .none
        ),
        AtlasEntry(
            id: "sys.messagesPreviews", pack: .systemResidue,
            title: "Message preview caches",
            identityLine: "Thumbnails Messages remakes as you browse.",
            owner: "Messages", tier: .managed, teachFlow: .messages,
            cost: .none
        ),
        AtlasEntry(
            id: "sys.mail", pack: .systemResidue,
            title: "Mail downloads",
            identityLine: "Local copies of mail and attachments. Mail re-downloads what you open.",
            owner: "Mail", tier: .managed, teachFlow: .mail,
            cost: .none
        ),
        AtlasEntry(
            id: "sys.photosLibrary", pack: .systemResidue,
            title: "Photos library",
            identityLine: "Your photo library and its indexes. Photos manages it, and iCloud can keep originals in the cloud.",
            owner: "Photos", tier: .yours, teachFlow: .photos,
            cost: .none
        ),
        // Plan-only entry: never matched by the scan, offered inside the
        // Photos trim plan when the library verifiably syncs with iCloud.
        AtlasEntry(
            id: "sys.photosLibraryWhole", pack: .systemResidue,
            title: "Entire Photos library",
            identityLine: "The whole library. Deleting the local copy does not delete photos from iCloud. Any photos not yet uploaded from this Mac would be lost. If this Mac never imports photos, nothing is waiting to upload. Photos makes a new empty library the next time it opens.",
            owner: "Photos", tier: .yours,
            cost: .none, planDefaultOff: true
        ),
        AtlasEntry(
            id: "sys.photosSyndication", pack: .systemResidue,
            title: "Shared with You photos",
            identityLine: "Photos from Messages conversations, kept by macOS for Shared with You. It manages its own size.",
            owner: "Photos", tier: .managed, teachFlow: .sharedWithYou,
            cost: .none
        ),
        AtlasEntry(
            id: "sys.photosDerivatives", pack: .systemResidue,
            title: "Photo thumbnails",
            identityLine: "Thumbnails Photos remakes as you browse. With iCloud optimizing storage, remaking them can download photos again.",
            owner: "Photos", tier: .managed, teachFlow: .photos,
            cost: .none
        ),
        AtlasEntry(
            id: "chrome.optGuide", pack: .systemResidue,
            title: "Chrome's on-device AI model",
            identityLine: "Chrome downloads this model for its built-in AI features and fetches it again when needed.",
            owner: "Google Chrome", tier: .regenerable,
            cost: .redownload(fraction: 1.0, tool: "Chrome")
        ),
        AtlasEntry(
            id: "py.uvCache", pack: .ml,
            title: "uv cache",
            identityLine: "Python packages uv keeps for reuse. The next install refetches what a project needs.",
            owner: "uv", tier: .regenerable,
            cost: .redownload(fraction: 0.4, tool: "uv")
        ),
        AtlasEntry(
            id: "app.bundle", pack: .applications,
            title: "Application",
            identityLine: "The app and its retained data. Caches the app can recreate are listed separately for cleanup.",
            owner: "Applications", tier: .apps,
            cost: .none
        ),
        AtlasEntry(
            id: "app.residue", pack: .applications,
            title: "App data",
            identityLine: "Settings, caches, and documents this app kept in your Library.",
            owner: "Applications", tier: .apps,
            cost: .none
        ),
        AtlasEntry(
            id: "sys.os", pack: .systemResidue,
            title: "macOS",
            identityLine: "The operating system itself, sealed and signed. Updates replace it in place.",
            owner: "macOS", tier: .system,
            cost: .none
        ),
        AtlasEntry(
            id: "sys.updateStaging", pack: .systemResidue,
            title: "Boot support",
            identityLine: "Files macOS needs to start up. This is not an estimate of space an update will free.",
            owner: "macOS", tier: .system,
            cost: .none
        ),
        AtlasEntry(
            id: "sys.swap", pack: .systemResidue,
            title: "Memory swap",
            identityLine: "Memory that spilled to disk. A restart drains it, and it grows back under load.",
            owner: "macOS", tier: .system,
            cost: .none
        ),
        AtlasEntry(
            id: "sys.snapshots", pack: .systemResidue,
            title: "Local Time Machine snapshots",
            identityLine: "macOS keeps a few local snapshots beside your real backups and thins them on its own. Deleting them frees the space they pin.",
            owner: "macOS", tier: .managed, teachFlow: .snapshots,
            cost: .none,
            ticker: { Copy.tickerSnapshots($0) }
        ),

        // The one entry every lens finding rides to the Reclaim plan.
        AtlasEntry(
            id: "lens.found", pack: .systemResidue,
            title: "Named by a lens",
            identityLine: "Found inside Everything else. You saw what it is; you decide.",
            owner: "You", tier: .yours,
            cost: .none
        ),

        // MARK: ML weights
        AtlasEntry(
            id: "ml.huggingface", pack: .ml,
            title: "Hugging Face models",
            identityLine: "Downloaded model weights. They download again on the next use.",
            owner: "Hugging Face", tier: .regenerable,
            cost: .redownload(fraction: 1.0, tool: "model download")
        ),
        AtlasEntry(
            id: "ml.ollama", pack: .ml,
            title: "Ollama models",
            identityLine: "Downloaded model weights. ollama pull brings any of them back.",
            owner: "Ollama", tier: .regenerable,
            cost: .redownload(fraction: 1.0, tool: "ollama pull")
        ),
        AtlasEntry(
            id: "ml.lmstudio", pack: .ml,
            title: "LM Studio models",
            identityLine: "Downloaded model weights. They download again on the next use.",
            owner: "LM Studio", tier: .regenerable,
            cost: .redownload(fraction: 1.0, tool: "model download")
        ),
    ]

    // MARK: - Classification

    /// Home-relative paths that map straight to an entry.
    static let homeRelativePaths: [String: String] = [
        "Library/Developer/Xcode/DerivedData": "xcode.derivedData",
        "Library/Developer/Xcode/Archives": "xcode.archives",
        "Library/Developer/Xcode/iOS DeviceSupport": "xcode.deviceSupport",
        "Library/Developer/Xcode/watchOS DeviceSupport": "xcode.deviceSupport",
        "Library/Developer/Xcode/tvOS DeviceSupport": "xcode.deviceSupport",
        "Library/Developer/CoreSimulator/Devices": "xcode.simDevices",
        "Library/Developer/XCTestDevices": "xcode.testDevices",
        "Library/Developer/CoreSimulator/Caches": "xcode.simCaches",
        "Library/Developer/Xcode/UserData/Previews": "xcode.previews",
        "Library/Caches/org.swift.swiftpm": "xcode.spmCache",
        "Library/Caches/com.apple.dt.Xcode": "xcode.cache",
        ".npm": "js.npmCache",
        "Library/pnpm": "js.pnpmStore",
        "Library/Caches/Yarn": "js.yarnCache",
        ".bun/install/cache": "js.bunCache",
        ".cargo/registry": "rust.cargoRegistry",
        ".cargo/git": "rust.cargoGit",
        "Library/Caches/Homebrew": "brew.cache",
        "Library/Containers/com.docker.docker": "docker.data",
        ".orbstack": "orbstack.data",
        "Library/Application Support/MobileSync/Backup": "sys.iosBackups",
        ".Trash": "sys.trash",
        "Library/Messages": "sys.messages",
        "Library/Mail": "sys.mail",
        "Library/Application Support/Google/Chrome/OptGuideOnDeviceModel": "chrome.optGuide",
        ".cache/uv": "py.uvCache",
        "Library/Caches/pip": "py.pipCache",
        ".cache/pip": "py.pipCache",
        ".gradle/caches": "gradle.caches",
        ".cache/huggingface": "ml.huggingface",
        ".ollama/models": "ml.ollama",
        ".lmstudio": "ml.lmstudio",
    ]

    /// Absolute paths outside the home folder (need the full-disk grant).
    static let absolutePaths: [String: String] = [
        "/private/var/folders": "storage.temporary",
        "/private/var/db/diagnostics": "storage.diagnostics",
        "/private/var/db/uuidtext": "storage.diagnostics",
        "/private/var/db/powerlog": "storage.diagnostics",
        "/private/var/db/DiagnosticPipeline": "storage.diagnostics",
        "/System/Volumes/Data/System": "storage.assets",
        "/System/Volumes/Data/macOS Install Data": "storage.update",
        "/System/Volumes/Data/MobileSoftwareUpdate": "storage.update",
        "/System/Volumes/Data/.PreviousSystemInformation": "storage.update",
        "/System/Volumes/Data/.DocumentRevisions-V100": "storage.revisions",
        "/System/Volumes/Data/.Spotlight-V100": "storage.search",
        "/System/Volumes/Data/.fseventsd": "storage.services",

        "/Library/Developer/CoreSimulator": "xcode.simRuntimes",
    ]

    /// Match a directory by its standardized path. `home` has no trailing slash.
    public static func classify(path: String, home: String) -> String? {
        if let id = absolutePaths[path] { return id }
        guard path.hasPrefix(home + "/") else { return nil }
        let rel = String(path.dropFirst(home.count + 1))
        return homeRelativePaths[rel]
    }

    /// node_modules is a rebuildable only where a person builds: inside the
    /// home folder, outside ~/Library, never inside an app bundle. An app's
    /// bundled node_modules (Electron in /Applications or ~/Applications,
    /// helpers under Application Support) IS the app — deleting it breaks
    /// the app, so it is never named as a colony.
    static func nodeModulesEligible(parentPath: String, home: String) -> Bool {
        guard parentPath == home || parentPath.hasPrefix(home + "/") else { return false }
        let library = home + "/Library"
        if parentPath == library || parentPath.hasPrefix(library + "/") { return false }
        if parentPath.hasSuffix(".app") || parentPath.contains(".app/") { return false }
        // Bundled dependencies belong to the installed tool, not a project
        // whose package manager can recreate them independently.
        let tools = [".cache/codex-runtimes", ".local/share/claude", ".codex", ".claude/plugins", ".vscode/extensions"]
        if tools.contains(where: { parentPath == home + "/" + $0 || parentPath.hasPrefix(home + "/" + $0 + "/") }) { return false }
        if parentPath.split(separator: "/").contains(where: { $0 == "externals" || $0.hasPrefix("externals.") }) { return false }
        // Nested colonies are not separate finds.
        if parentPath.contains("/node_modules/") || parentPath.hasSuffix("/node_modules") { return false }
        return true
    }

    /// Name-based rules that need a look at the parent directory:
    /// node_modules in the home tree, `target/` beside a Cargo.toml, `.build`
    /// beside a Package.swift. `parentPath` must not itself be inside a
    /// matched colony.
    /// The user's own libraries match by suffix (renamable); the hidden
    /// Syndication library under ~/Library/Photos is macOS's Shared with You
    /// store and gets its own name so the two never read alike.
    static func photosLibraryEntry(parentPath: String, home: String) -> String {
        parentPath.hasPrefix(home + "/Library/") ? "sys.photosSyndication" : "sys.photosLibrary"
    }

    /// Bundles are recognized as a whole, before lens traversal. Their contents
    /// remain personal even when they contain generated files or dependencies.
    private static func personalLibraryEntry(name: String) -> String? {
        switch (name as NSString).pathExtension.lowercased() {
        case "musiclibrary": "personal.musicLibrary"
        case "tvlibrary": "personal.tvLibrary"
        case "imovielibrary", "fcpbundle": "personal.videoLibrary"
        case "aplibrary": "personal.apertureLibrary"
        default: nil
        }
    }

    public static func classify(name: String, parentPath: String, home: String, fm: FileManager = .default) -> String? {
        if name.hasSuffix(".photoslibrary") { return photosLibraryEntry(parentPath: parentPath, home: home) }
        if let library = personalLibraryEntry(name: name) { return library }
        switch name {
        case "node_modules":
            return nodeModulesEligible(parentPath: parentPath, home: home) ? "js.nodeModules" : nil
        case "target":
            return fm.fileExists(atPath: parentPath + "/Cargo.toml") ? "rust.target" : nil
        case ".build":
            return fm.fileExists(atPath: parentPath + "/Package.swift") ? "xcode.spmBuild" : nil
        default:
            return nil
        }
    }

    /// True when `classify(name:parentPath:home:siblings:)` needs the sibling
    /// listing for this name — lets the walk build the set lazily.
    public static func needsSiblings(_ name: String) -> Bool {
        name == "target" || name == ".build"
    }

    /// Same rules, answered from the directory listing the walk already
    /// holds — no stat. `siblings` are the names beside `name`.
    public static func classify(name: String, parentPath: String, home: String, siblings: Set<String>?) -> String? {
        if name.hasSuffix(".photoslibrary") { return photosLibraryEntry(parentPath: parentPath, home: home) }
        if let library = personalLibraryEntry(name: name) { return library }
        switch name {
        case "node_modules":
            return nodeModulesEligible(parentPath: parentPath, home: home) ? "js.nodeModules" : nil
        case "target":
            return siblings?.contains("Cargo.toml") == true ? "rust.target" : nil
        case ".build":
            return siblings?.contains("Package.swift") == true ? "xcode.spmBuild" : nil
        default:
            return nil
        }
    }
}
