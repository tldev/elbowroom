import Foundation

/// The APFS container's non-Data volumes: space no file walk can see. The OS
/// itself, the update staging area, and swap live on sibling volumes inside
/// the same container, so they count against the disk while staying invisible
/// to enumeration. Parsed from `diskutil apfs list -plist`, no privileges.
public struct ContainerInfo: Sendable {
    /// Sealed OS (System role) plus Recovery.
    public let osBytes: Int64
    /// Preboot: data macOS needs to boot its system volumes.
    public let prebootBytes: Int64
    /// VM volume: swap files.
    public let vmBytes: Int64
    public let updateBytes: Int64
    public let containerBytes: Int64

    public init(osBytes: Int64, prebootBytes: Int64, vmBytes: Int64, updateBytes: Int64 = 0, containerBytes: Int64 = 0) {
        self.osBytes = osBytes
        self.prebootBytes = prebootBytes
        self.vmBytes = vmBytes
        self.updateBytes = updateBytes
        self.containerBytes = containerBytes
    }

    /// The boot container is the one holding a System-role volume; external
    /// APFS drives have none.
    public static func parse(plistData: Data) -> ContainerInfo? {
        guard let root = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let containers = root["Containers"] as? [[String: Any]]
        else { return nil }
        for container in containers {
            guard let volumes = container["Volumes"] as? [[String: Any]] else { continue }
            var byRole: [String: Int64] = [:]
            for volume in volumes {
                guard let roles = volume["Roles"] as? [String],
                      let used = (volume["CapacityInUse"] as? NSNumber)?.int64Value
                else { continue }
                for role in roles {
                    byRole[role, default: 0] += used
                }
            }
            guard byRole["System"] != nil else { continue }
            let volumeBytes = volumes.reduce(Int64(0)) { $0 + (($1["CapacityInUse"] as? NSNumber)?.int64Value ?? 0) }
            let containerBytes: Int64
            if let capacity = (container["CapacityCeiling"] as? NSNumber)?.int64Value,
               let free = (container["CapacityFree"] as? NSNumber)?.int64Value {
                containerBytes = max(0, capacity - free - volumeBytes)
            } else { containerBytes = 0 }
            return ContainerInfo(
                osBytes: (byRole["System"] ?? 0) + (byRole["Recovery"] ?? 0),
                prebootBytes: byRole["Preboot"] ?? 0,
                vmBytes: byRole["VM"] ?? 0,
                updateBytes: byRole["Update"] ?? 0, containerBytes: containerBytes
            )
        }
        return nil
    }

    public static func capture() -> ContainerInfo? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        p.arguments = ["apfs", "list", "-plist"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
            // Read to EOF before waiting, or the child fills the pipe buffer.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { return nil }
            return parse(plistData: data)
        } catch {
            return nil
        }
    }
}

/// System-tier items from the container measurements. Their bytes were part
/// of "used" all along; naming them moves ~40 GB from the gray band into the
/// System band, which is the whole point.
public enum SystemSpace {
    public static func items(container: ContainerInfo?) -> [AtlasItem] {
        guard let container else { return [] }
        var out: [AtlasItem] = []
        if container.osBytes > 0 {
            out.append(AtlasItem(entryID: "sys.os",
                                 url: URL(fileURLWithPath: "/System"),
                                 bytes: container.osBytes, lastTouched: nil))
        }
        if container.prebootBytes > 0 {
            out.append(AtlasItem(entryID: "sys.updateStaging",
                                 url: URL(fileURLWithPath: "/System/Volumes/Preboot"),
                                 bytes: container.prebootBytes, lastTouched: nil))
        }
        if container.vmBytes > 0 {
            out.append(AtlasItem(entryID: "sys.swap",
                                 url: URL(fileURLWithPath: "/System/Volumes/VM"),
                                 bytes: container.vmBytes, lastTouched: nil))
        }
        if container.updateBytes > 0 {
            out.append(AtlasItem(entryID: "storage.update",
                                 url: URL(fileURLWithPath: "/System/Volumes/Update"),
                                 bytes: container.updateBytes, lastTouched: nil))
        }
        if container.containerBytes > 0 {
            out.append(AtlasItem(entryID: "storage.container", url: URL(fileURLWithPath: "/System/Volumes"),
                                 bytes: container.containerBytes, lastTouched: nil))
        }
        return out
    }
}
