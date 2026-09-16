import Foundation
import Darwin

/// On-demand administrator approval for the direct-download build. The bundled
/// helper accepts a fixed rename operation, not an arbitrary shell command.
enum AdministratorAppMove {
    static func trash(_ url: URL) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            guard url.deletingLastPathComponent().path == "/Applications" else {
                throw CocoaError(.fileWriteNoPermission)
            }
            let folder = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".Trash/Elbowroom Authorized " + UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            do {
                try execute(operation: "trash", source: url, folder: folder)
                return folder.appendingPathComponent(url.lastPathComponent)
            } catch {
                // Remove only an empty folder, never a partially completed move.
                _ = rmdir(folder.path)
                throw error
            }
        }.value
    }

    static func restore(source: URL, destination: URL) throws {
        guard destination.deletingLastPathComponent().path == "/Applications",
              source.lastPathComponent == destination.lastPathComponent,
              source.deletingLastPathComponent().deletingLastPathComponent().path ==
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash").path else {
            throw CocoaError(.fileWriteNoPermission)
        }
        try execute(operation: "restore", source: source, folder: source.deletingLastPathComponent())
        _ = rmdir(source.deletingLastPathComponent().path)
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func appleScriptQuote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n") + "\""
    }

    private static func execute(operation: String, source: URL, folder: URL) throws {
        guard let helper = Bundle.main.url(forAuxiliaryExecutable: "ElbowroomAppMover") else {
            throw CocoaError(.featureUnsupported)
        }
        var info = stat()
        guard lstat(source.path, &info) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        let arguments = [helper.path, operation, String(getuid()), source.lastPathComponent,
                         folder.lastPathComponent, String(info.st_dev), String(info.st_ino), "v1"]
        let command = arguments.map(shellQuote).joined(separator: " ")
        let script = "do shell script " + appleScriptQuote(command) + " with administrator privileges"
        let process = Process()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        try process.run()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errorData, as: UTF8.self)
            if message.contains("(-128)") { throw CocoaError(.userCancelled) }
            throw CocoaError(.fileWriteNoPermission, userInfo: [NSUnderlyingErrorKey:
                NSError(domain: "Elbowroom.AdministratorAppMove", code: Int(process.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: message])])
        }
    }
}
