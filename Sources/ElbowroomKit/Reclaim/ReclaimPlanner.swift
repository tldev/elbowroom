import Foundation

/// Read-only inspection for file-based plans. No UI state or destructive work.
public enum ReclaimPlanner {
    public struct Uninstall: Sendable {
        public let bundleID: String?
        public let items: [AtlasItem]
    }

    public static func uninstall(_ item: AtlasItem, root: ScanNode?, home: String = NSHomeDirectory()) async -> Uninstall {
        await Task.detached(priority: .userInitiated) {
            let name = item.displayName
            var bundleID = Bundle(path: item.url.path)?.bundleIdentifier
            if bundleID == nil, let node = root?.find(path: item.url.path),
               let nested = AppsPass.nestedAppPath(under: node) {
                bundleID = Bundle(path: nested)?.bundleIdentifier
            }
            var items = AppsPass.uninstallItems(appURL: item.url, appName: name, bundleID: bundleID,
                                               homePath: home, sizer: sizer(root))
            if let library = root?.find(path: home + "/Library") {
                items += AppsPass.vendorResidueItems(appName: name, bundleID: bundleID,
                                                    appURL: item.url, libraryNode: library)
            }
            return Uninstall(bundleID: bundleID, items: items)
        }.value
    }

    /// nil means the cloud-copy requirement was not met; [] means no work.
    public static func messages(root: ScanNode?, home: String = NSHomeDirectory()) async -> [AtlasItem]? {
        await Task.detached(priority: .userInitiated) {
            guard MessagesTrim.cloudSyncEnabled() else { return nil }
            return MessagesTrim.planItems(homePath: home, sizer: sizer(root))
        }.value
    }

    public static func photos(_ item: AtlasItem, root: ScanNode?) async -> [AtlasItem] {
        await Task.detached(priority: .userInitiated) {
            PhotosTrim.planItems(libraryURL: item.url, sizer: sizer(root),
                                 wholeLibraryEligible: PhotosTrim.cloudSyncActive(libraryURL: item.url))
        }.value
    }

    private static func sizer(_ root: ScanNode?) -> (String) -> Int64 {
        { path in root?.find(path: path)?.allocatedBytes ?? SimCleanup.directorySize(path) }
    }
}
