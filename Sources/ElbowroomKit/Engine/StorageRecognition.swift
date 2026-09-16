import Foundation

/// Name established storage locations without inventing cleanup permission.
/// Run after app ownership and existing tool passes, before lenses. New parent
/// items count only the remainder; already named descendants keep their bytes.
enum StorageRecognition {
    static let homeGroups: [(String, String)] = [
        (".cache/codex-runtimes", "storage.toolRuntime"),
        (".local/share/claude", "storage.toolRuntime"),
        (".config", "storage.sharedData"),
        ("Library/Trial", "storage.intelligence"),
        ("Library/Mobile Documents", "storage.cloudFiles"),
        ("Library/Preferences", "storage.sharedData"),
        ("Library/HTTPStorages", "storage.sharedData"),
        ("Library/WebKit", "storage.sharedData"),
        ("Library/Cookies", "storage.sharedData"),
        ("Library/Saved Application State", "storage.sharedData"),
        ("Library/Application Scripts", "storage.sharedData"),
        (".pyenv", "storage.toolPython"),
        (".vscode/extensions", "storage.toolExtensions"),
        (".codex", "storage.historyAssistant"),
        (".claude", "storage.historyAssistant"),
        ("Library/Metadata/CoreSpotlight", "storage.search"),
        ("Library/Application Support/com.apple.wallpaper", "storage.wallpaper"),
        ("Library/Biome", "storage.intelligence"),
        ("Library/DuetExpertCenter", "storage.intelligence"),
        ("Library/IntelligencePlatform", "storage.intelligence"),
        ("Library/Daemon Containers", "storage.services"),
        ("Library/Group Containers", "storage.sharedData"),
        ("Library/Containers", "storage.sharedData"),
        ("Library/Roblox", "storage.sharedData"),
        ("Library/Application Support", "storage.sharedData"),
    ]
    static let absoluteGroups: [(String, String)] = [
        ("/private/var/db", "storage.databases"),
        ("/opt/homebrew", "storage.toolPackages"),
        ("/usr/local/Cellar", "storage.toolPackages"),
        ("/Library/Developer/CommandLineTools", "storage.toolSDK"),
        ("/Library/Developer", "storage.developer"),
        ("/Library/Logs", "storage.diagnostics"),
        ("/private/var/log", "storage.diagnostics"),
        ("/Applications", "storage.software"),
        ("/Library/Updates", "storage.update"),
        ("/Library/Application Support", "storage.sharedData"),
    ]

    /// Names alone are insufficient: inspect structural marker files already
    /// read by the directory walker. These identities never grant deletion.
    static func structuralIdentity(names: Set<String>, path: String, home: String) -> String? {
        guard path.hasPrefix(home + "/"), !path.hasPrefix(home + "/Library/") else { return nil }
        if names.contains("pyvenv.cfg"), names.contains("bin"), names.contains("lib") {
            return "storage.pythonEnvironments"
        }
        if names.contains(".runner"), names.contains(".credentials"), names.contains("bin"),
           names.contains(where: { $0 == "externals" || $0.hasPrefix("externals.") }) {
            return "storage.runners"
        }
        return nil
    }

    static func items(root: ScanNodeBuilder, home: String, known: [AtlasItem]) -> [AtlasItem] {
        var out: [AtlasItem] = []
        for (path, id) in homeGroups.map({ (home + "/" + $0.0, $0.1) }) + absoluteGroups {
            let named = known + out
            guard !named.contains(where: { path == $0.id || path.hasPrefix($0.id + "/") }),
                  let node = ScanEngine.staticFindNode(path: path, under: root), node.atlasEntryID == nil else { continue }
            // App data has ownership markers at its real locations even when
            // the app item itself lives in /Applications.
            func claimed(_ n: ScanNodeBuilder) -> Int64 {
                if n.atlasEntryID != nil { return n.allocatedBytes }
                if let item = named.first(where: { $0.id == n.path }) { return min(n.allocatedBytes, item.bytes) }
                return n.children.reduce(0) { $0 + claimed($1) }
            }
            let bytes = max(0, node.allocatedBytes - claimed(node))
            guard bytes > 0 else { continue }
            node.atlasEntryID = id
            out.append(AtlasItem(entryID: id, url: node.url, bytes: bytes,
                                 lastTouched: node.lastTouched))
        }
        return out
    }
    static func mediaItems(root: ScanNodeBuilder, facts: [FileFact], home: String,
                           excluding: [String]) -> [AtlasItem] {
        let extensions: Set<String> = ["mp4", "mov", "m4v", "mkv", "avi", "webm", "mp3", "m4a",
                                       "wav", "aiff", "flac", "jpg", "jpeg", "png", "heic", "tiff", "dng"]
        var covered = Set(excluding)
        func collect(_ node: ScanNodeBuilder) {
            if node.atlasEntryID != nil { covered.insert(node.path); return }
            node.children.forEach(collect)
        }
        collect(root)
        func isCovered(_ path: String) -> Bool {
            var cursor = path
            while cursor != "/" {
                if covered.contains(cursor) { return true }
                cursor = (cursor as NSString).deletingLastPathComponent
            }
            return false
        }
        var seen = Set<String>()
        return facts.compactMap { fact in
            guard !fact.isDirectory, fact.path.hasPrefix(home + "/"),
                  !fact.path.hasPrefix(home + "/Library/"),
                  extensions.contains((fact.path as NSString).pathExtension.lowercased()),
                  !isCovered(fact.path), seen.insert(fact.path).inserted else { return nil }
            return AtlasItem(entryID: "storage.media", url: URL(fileURLWithPath: fact.path),
                             bytes: fact.bytes, lastTouched: fact.modified)
        }
    }

    /// Give ordinary document folders and detected source projects an identity
    /// after lenses have selected reviewable files. Count only their remainder.
    static func personalItems(root: ScanNodeBuilder, home: String,
                              projects: [String], findings: [(String, Int64)]) -> [AtlasItem] {
        let folders = [("Documents", "documents"), ("Desktop", "documents"),
                       ("Downloads", "downloads"), ("Pictures", "media"),
                       ("Movies", "media"), ("Music", "media")]
        let targets = projects.filter { $0.hasPrefix(home + "/") && !$0.hasPrefix(home + "/Library/") }
            .sorted { $0.count > $1.count }.map { ($0, "storage.projects") }
            + folders.map { (home + "/" + $0.0, "storage." + $0.1) }
        var out: [AtlasItem] = []
        for (path, entryID) in targets {
            guard !findings.contains(where: { path == $0.0 || path.hasPrefix($0.0 + "/") }),
                  let node = ScanEngine.staticFindNode(path: path, under: root) else { continue }
            // A parent marker owns the whole subtree, even when its list item
            // is net of separately named descendants.
            var ancestor = node.parent
            var covered = false
            while let current = ancestor {
                if current.atlasEntryID != nil { covered = true; break }
                ancestor = current.parent
            }
            guard !covered else { continue }
            var claimedPaths: [String] = []
            func remaining(_ n: ScanNodeBuilder) -> Int64 {
                if n.atlasEntryID != nil { claimedPaths.append(n.path); return 0 }
                return n.allocatedBytes - n.children.reduce(0) { $0 + $1.allocatedBytes }
                    + n.children.reduce(0) { $0 + remaining($1) }
            }
            let readable = remaining(node)
            let reviewable = findings.filter { finding in
                finding.0.hasPrefix(path + "/") && !claimedPaths.contains {
                    finding.0 == $0 || finding.0.hasPrefix($0 + "/")
                }
            }.reduce(Int64(0)) { $0 + $1.1 }
            let bytes = max(0, readable - reviewable)
            guard bytes > 0 else { continue }
            node.atlasEntryID = entryID
            out.append(AtlasItem(entryID: entryID, url: node.url, bytes: bytes, lastTouched: node.lastTouched))
        }
        return out
    }

}
