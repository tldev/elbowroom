import Foundation
import Darwin

/// The elevated process only renames one identified app between /Applications
/// and a private, existing Trash folder. No shell commands, recursive deletion,
/// ownership changes, or arbitrary destinations are accepted.
public enum AuthorizedAppMove {
    public static func validName(_ name: String) -> Bool {
        name.hasSuffix(".app") && name != ".app" && !name.contains("/") && !name.contains("\0")
    }

    public static func validFolder(_ name: String) -> Bool {
        let prefix = "Elbowroom Authorized "
        return name.hasPrefix(prefix) && UUID(uuidString: String(name.dropFirst(prefix.count))) != nil
    }

    public static func move(arguments: [String]) throws {
        guard geteuid() == 0, arguments.count == 7,
              ["trash", "restore"].contains(arguments[0]),
              let uid = uid_t(arguments[1]), uid >= 501,
              validName(arguments[2]), validFolder(arguments[3]),
              let device = Int32(arguments[4]), let inode = UInt64(arguments[5]),
              arguments[6] == "v1", let account = getpwuid(uid),
              let homePointer = account.pointee.pw_dir else { throw failure(EINVAL) }
        let home = String(cString: homePointer)
        let apps = try openDirectory("/Applications")
        defer { close(apps) }
        let homeFD = try openDirectory(home)
        defer { close(homeFD) }
        let trash = openat(homeFD, ".Trash", O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard trash >= 0 else { throw failure(errno) }
        defer { close(trash) }
        let folder = openat(trash, arguments[3], O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard folder >= 0 else { throw failure(errno) }
        defer { close(folder) }
        for fd in [homeFD, trash, folder] {
            var info = stat()
            guard fstat(fd, &info) == 0, info.st_uid == uid else { throw failure(EACCES) }
        }
        var folderInfo = stat()
        guard fstat(folder, &folderInfo) == 0, folderInfo.st_mode & 0o077 == 0 else { throw failure(EACCES) }
        let source = arguments[0] == "trash" ? apps : folder
        let target = arguments[0] == "trash" ? folder : apps
        try moveApp(name: arguments[2], source: source, target: target,
                    device: device, inode: inode, owner: uid)
    }

    static func moveApp(name: String, source: Int32, target: Int32,
                        device: Int32, inode: UInt64, owner: uid_t) throws {
        guard validName(name) else { throw failure(EINVAL) }
        var appInfo = stat()
        guard fstatat(source, name, &appInfo, AT_SYMLINK_NOFOLLOW) == 0 else { throw failure(errno) }
        guard appInfo.st_mode & S_IFMT == S_IFDIR,
              appInfo.st_dev == device, appInfo.st_ino == inode,
              appInfo.st_uid == 0 || appInfo.st_uid == owner,
              appInfo.st_flags & UInt32(SF_IMMUTABLE | UF_IMMUTABLE | SF_RESTRICTED) == 0 else { throw failure(EACCES) }
        guard renameatx_np(source, name, target, name, UInt32(RENAME_EXCL)) == 0 else {
            throw failure(errno)
        }
    }

    /// Open every component without following symlinks; retain descriptors
    /// through the rename so path replacement cannot redirect the operation.
    private static func openDirectory(_ path: String) throws -> Int32 {
        guard path.hasPrefix("/") else { throw failure(EINVAL) }
        var fd = open("/", O_RDONLY | O_DIRECTORY)
        guard fd >= 0 else { throw failure(errno) }
        for component in path.split(separator: "/") {
            guard component != ".", component != ".." else { close(fd); throw failure(EINVAL) }
            let next = openat(fd, String(component), O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            let saved = errno
            close(fd)
            guard next >= 0 else { throw failure(saved) }
            fd = next
        }
        return fd
    }

    private static func failure(_ code: Int32) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(code))
    }
}
