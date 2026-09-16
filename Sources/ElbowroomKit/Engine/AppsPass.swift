import Foundation
import CoreServices

/// Applications as items: each app's size is its bundle plus everything it
/// keeps in `~/Library`, so the row tells the app's whole story. Residue is
/// matched conservatively — exact bundle id, bundle-id prefix, or the app's
/// exact name — because a false match here would offer someone else's data
/// for deletion. Uninstalling opens the ordinary trash-first Reclaim plan
/// with one row per piece, each uncheckable: the app deletes, its data is
/// the user's choice.
public enum AppsPass {

    /// Library locations that hold app leavings worth counting and, on
    /// uninstall, offering. Junk regenerates; data is settings and documents.
    static let junkLocations = ["Caches", "Logs", "Saved Application State", "WebKit", "HTTPStorages"]
    static let dataLocations = ["Application Support", "Containers", "Group Containers", "Application Scripts"]
    static var allLocations: [String] { dataLocations + junkLocations }

    /// Conservative residue match. Group Containers are team-prefixed, so
    /// only bundle-id containment counts there; everywhere else the child
    /// must be the bundle id, a bundle-id extension, or the app's exact name.
    static func matches(childName: String, bundleID: String?, appName: String, location: String) -> Bool {
        if location == "Group Containers" {
            guard let bundleID else { return false }
            return childName.contains(bundleID)
        }
        if let bundleID {
            if childName == bundleID { return true }
            if childName.hasPrefix(bundleID + ".") { return true }
        }
        return childName == appName
    }

    /// Explicit aliases are tied to bundle identities, never fuzzy folder names.
    static func supportAlias(bundleID: String?) -> String? {
        switch bundleID {
        case "com.google.Chrome": "Google/Chrome"
        case "com.microsoft.VSCode": "Code"
        case "com.hnc.Discord": "discord"
        default: nil
        }
    }

    /// Only known disposable component names in supported apps. Website
    /// storage, cookies, histories and VM disks deliberately stay with the app.
    static func cacheComponents(in node: ScanNodeBuilder, bundleID: String?, owner: String) -> [AtlasItem] {
        let supported: Set<String> = ["com.tinyspeck.slackmacgap", "com.anthropic.claudefordesktop",
                                      "com.hnc.Discord", "com.microsoft.VSCode", "com.openai.codex", "com.google.Chrome"]
        guard let bundleID, supported.contains(bundleID) else { return [] }
        let names: Set<String> = bundleID == "com.microsoft.VSCode"
            ? ["Cache", "Code Cache", "GPUCache", "CachedData", "CachedExtensionVSIXs"]
            : ["Cache", "Code Cache", "GPUCache"]
        return node.children.compactMap { child in
            guard child.isDirectory, child.atlasEntryID == nil, names.contains(child.name), child.allocatedBytes > 0 else { return nil }
            child.atlasEntryID = "storage.appCache"
            return AtlasItem(entryID: "storage.appCache", url: child.url, bytes: child.allocatedBytes,
                             lastTouched: child.lastTouched, projectName: owner)
        }
    }

    private static func namedBytes(in node: ScanNodeBuilder) -> Int64 {
        node.children.reduce(0) { total, child in
            total + (child.atlasEntryID == nil ? namedBytes(in: child) : child.allocatedBytes)
        }
    }

    /// Scan-time pass: builds one item per app in /Applications and
    /// ~/Applications from nodes the walk already sized, marking app and
    /// residue nodes so the Map tints them and the generic cache pass skips
    /// them. Runs before genericCacheItems by contract.
    static func items(root: ScanNodeBuilder, homePath: String) -> [AtlasItem] {
        var out: [AtlasItem] = []
        var bundleIDs: [String: String] = [:]
        let libraryNode = ScanEngine.staticFindNode(path: homePath + "/Library", under: root)
        for dir in ["/Applications", homePath + "/Applications"] {
            guard let appsNode = ScanEngine.staticFindNode(path: dir, under: root) else { continue }
            for app in appsNode.children where app.isDirectory && app.name.hasSuffix(".app") {
                let appName = String(app.name.dropLast(4))
                let bundleID = Bundle(path: app.path)?.bundleIdentifier
                if let bundleID { bundleIDs[appName] = bundleID }
                var bytes = app.allocatedBytes
                if let libraryNode {
                    for location in allLocations {
                        guard let locationNode = libraryNode.children.first(where: { $0.name == location }) else { continue }
                        var matches = locationNode.children.filter {
                            Self.matches(childName: $0.name, bundleID: bundleID, appName: appName, location: location)
                        }
                        if location == "Application Support", let alias = supportAlias(bundleID: bundleID),
                           let child = ScanEngine.staticFindNode(path: locationNode.path + "/" + alias, under: locationNode),
                           !matches.contains(where: { $0.path == child.path }) { matches.append(child) }
                        for child in matches where child.atlasEntryID == nil {
                            if location == "Caches" {
                                child.atlasEntryID = "storage.appCache"
                                out.append(AtlasItem(entryID: "storage.appCache", url: child.url,
                                                     bytes: child.allocatedBytes, lastTouched: child.lastTouched,
                                                     projectName: appName))
                            } else {
                                if location == "Application Support" {
                                    out += cacheComponents(in: child, bundleID: bundleID, owner: appName)
                                }
                                bytes += max(0, child.allocatedBytes - namedBytes(in: child))
                                child.atlasEntryID = "app.bundle"
                            }
                        }
                    }
                }
                app.atlasEntryID = "app.bundle"
                out.append(AtlasItem(
                    entryID: "app.bundle", url: app.url, bytes: bytes,
                    lastTouched: lastUsed(app.path), projectName: appName
                ))
            }
        }
        mergeNestedApps(libraryNode: libraryNode, into: &out, bundleIDs: bundleIDs)
        return out
    }

    /// Apps that install themselves into Application Support (Fusion's
    /// webdeploy tree): a vendor folder whose bytes are mostly one .app
    /// bundle is that app. When the same app also has an /Applications
    /// entry (a thin launcher), the vendor folder folds into that item —
    /// one row, whole footprint — matched by the nested app's exact name or
    /// bundle id, never by guessing at vendor names. Otherwise the folder
    /// stands as its own app item.
    static func mergeNestedApps(libraryNode: ScanNodeBuilder?, into items: inout [AtlasItem], bundleIDs: [String: String]) {
        guard let support = libraryNode?.children.first(where: { $0.name == "Application Support" }) else { return }
        for vendor in support.children
        where vendor.isDirectory && vendor.atlasEntryID == nil && vendor.allocatedBytes >= 1_000_000_000 {
            guard let app = largestApp(in: vendor.snapshot(), depth: 0),
                  app.allocatedBytes * 2 >= vendor.allocatedBytes
            else { continue }
            let name = String(app.name.dropLast(4))
            let nestedID = Bundle(path: app.path)?.bundleIdentifier
            vendor.atlasEntryID = "app.bundle"
            let existing = items.firstIndex { item in
                guard item.entryID == "app.bundle", let owner = item.projectName else { return false }
                if owner == name { return true }
                if let nestedID, bundleIDs[owner] == nestedID { return true }
                return false
            }
            if let existing {
                items[existing].bytes += vendor.allocatedBytes
            } else {
                items.append(AtlasItem(
                    entryID: "app.bundle", url: vendor.url, bytes: vendor.allocatedBytes,
                    lastTouched: lastUsed(app.path), projectName: name
                ))
            }
        }
    }

    /// Vendor folders that belong to this app (same nested-app identity),
    /// offered as uninstall rows so the installer tree leaves with the app.
    public static func vendorResidueItems(
        appName: String, bundleID: String?, appURL: URL, libraryNode: ScanNode?
    ) -> [AtlasItem] {
        guard let support = libraryNode?.children.first(where: { $0.name == "Application Support" }) else { return [] }
        var out: [AtlasItem] = []
        for vendor in support.children
        where vendor.isDirectory && vendor.allocatedBytes >= 1_000_000_000 && vendor.path != appURL.path {
            guard let app = largestApp(in: vendor, depth: 0),
                  app.allocatedBytes * 2 >= vendor.allocatedBytes
            else { continue }
            let name = String(app.name.dropLast(4))
            let nestedID = Bundle(path: app.path)?.bundleIdentifier
            guard name == appName || (nestedID != nil && nestedID == bundleID) else { continue }
            out.append(AtlasItem(
                entryID: "app.residue", url: vendor.url, bytes: vendor.allocatedBytes,
                lastTouched: nil, projectName: appName
            ))
        }
        return out
    }

    /// Biggest .app bundle in a shallow subtree; nil when none.
    static func largestApp(in node: ScanNode, depth: Int) -> ScanNode? {
        guard depth <= 5 else { return nil }
        var best: ScanNode?
        for child in node.children where child.isDirectory {
            let candidate = child.name.hasSuffix(".app")
                ? child
                : largestApp(in: child, depth: depth + 1)
            if let candidate, candidate.allocatedBytes > (best?.allocatedBytes ?? 0) {
                best = candidate
            }
        }
        return best
    }

    /// The .app inside a nested-app item's folder, for bundle-id lookup at
    /// uninstall time.
    public static func nestedAppPath(under node: ScanNode) -> String? {
        largestApp(in: node, depth: 0)?.path
    }

    /// Spotlight's last-used date; nil when the index does not know.
    static func lastUsed(_ path: String) -> Date? {
        guard let item = MDItemCreate(kCFAllocatorDefault, path as CFString) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    /// Uninstall-time listing against the live filesystem: the bundle first,
    /// then one row per residue location. Sizes come from the caller (the
    /// scan tree when it has the node, a direct walk when not).
    public static func uninstallItems(
        appURL: URL, appName: String, bundleID: String?,
        homePath: String, sizer: (String) -> Int64
    ) -> [AtlasItem] {
        var out = [AtlasItem(
            entryID: "app.bundle", url: appURL,
            bytes: sizer(appURL.path), lastTouched: nil, projectName: appName
        )]
        let fm = FileManager.default
        for location in allLocations {
            let locationPath = homePath + "/Library/" + location
            for child in (try? fm.contentsOfDirectory(atPath: locationPath)) ?? []
            where matches(childName: child, bundleID: bundleID, appName: appName, location: location) {
                let path = locationPath + "/" + child
                out.append(AtlasItem(
                    entryID: "app.residue", url: URL(fileURLWithPath: path),
                    bytes: sizer(path), lastTouched: nil, projectName: appName
                ))
            }
        }
        if let alias = supportAlias(bundleID: bundleID) {
            let path = homePath + "/Library/Application Support/" + alias
            if fm.fileExists(atPath: path), !out.contains(where: { $0.id == path }) {
                out.append(AtlasItem(entryID: "app.residue", url: URL(fileURLWithPath: path),
                                     bytes: sizer(path), lastTouched: nil, projectName: appName))
            }
        }
        return out
    }
}
