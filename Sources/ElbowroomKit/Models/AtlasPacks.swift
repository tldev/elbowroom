import Foundation

/// The v1.0 pack data: Xcode, JavaScript, Rust, Homebrew, Containers,
/// System residue, plus the ML-weights entries the Stash catalog needs.
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
            owner: "", tier: .yours, cost: .none
        )
    }

    private static let all: [AtlasEntry] = [
        // MARK: Xcode
        AtlasEntry(
            id: "xcode.derivedData", pack: .xcode,
            title: "Xcode build products",
            identityLine: "Intermediate build files. Xcode remakes them on the next build.",
            owner: "Xcode", tier: .rebuildable, stashable: true,
            cost: .rebuild(secondsPerGB: 150),
            ticker: { Copy.tickerXcode($0) }
        ),
        AtlasEntry(
            id: "xcode.archives", pack: .xcode,
            title: "Xcode archives",
            identityLine: "Past app builds and their debug symbols. Keep them if you shipped those builds.",
            owner: "Xcode", tier: .yours, stashable: true,
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
            owner: "Simulator", tier: .managed, stashable: true,
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
            owner: "Swift", tier: .rebuildable, stashable: true,
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
            owner: "npm", tier: .rebuildable, stashable: true,
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
            owner: "Rust", tier: .rebuildable, stashable: true,
            cost: .rebuild(secondsPerGB: 240),
            ticker: { Copy.tickerRust($0) }
        ),
        AtlasEntry(
            id: "rust.cargoRegistry", pack: .rust,
            title: "Cargo registry",
            identityLine: "Downloaded crate sources shared by your Rust projects. Cargo refills it on the next fetch.",
            owner: "Rust", tier: .regenerable, stashable: true,
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
            owner: "Homebrew", tier: .regenerable, stashable: true,
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
            owner: "macOS", tier: .managed, teachFlow: .purgeable,
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

        // MARK: ML weights (Stash catalog)
        AtlasEntry(
            id: "ml.huggingface", pack: .ml,
            title: "Hugging Face models",
            identityLine: "Downloaded model weights. They download again on the next use.",
            owner: "Hugging Face", tier: .regenerable, stashable: true,
            cost: .redownload(fraction: 1.0, tool: "model download")
        ),
        AtlasEntry(
            id: "ml.ollama", pack: .ml,
            title: "Ollama models",
            identityLine: "Downloaded model weights. ollama pull brings any of them back.",
            owner: "Ollama", tier: .regenerable, stashable: true,
            cost: .redownload(fraction: 1.0, tool: "ollama pull")
        ),
        AtlasEntry(
            id: "ml.lmstudio", pack: .ml,
            title: "LM Studio models",
            identityLine: "Downloaded model weights. They download again on the next use.",
            owner: "LM Studio", tier: .regenerable, stashable: true,
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
        ".cache/huggingface": "ml.huggingface",
        ".ollama/models": "ml.ollama",
        ".lmstudio": "ml.lmstudio",
    ]

    /// Absolute paths outside the home folder (need the full-disk grant).
    static let absolutePaths: [String: String] = [
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
        // Nested colonies are not separate finds.
        if parentPath.contains("/node_modules/") || parentPath.hasSuffix("/node_modules") { return false }
        return true
    }

    /// Name-based rules that need a look at the parent directory:
    /// node_modules in the home tree, `target/` beside a Cargo.toml, `.build`
    /// beside a Package.swift. `parentPath` must not itself be inside a
    /// matched colony.
    public static func classify(name: String, parentPath: String, home: String, fm: FileManager = .default) -> String? {
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

    /// True when children of this classified directory should not be classified
    /// again (a colony is one item; its insides are not separate finds).
    public static func isColony(_ entryID: String) -> Bool {
        entryID != "sys.appCacheParent"
    }
}
