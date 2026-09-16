import Foundation
import AuthorizedAppMoveCore

do {
    try AuthorizedAppMove.move(arguments: Array(CommandLine.arguments.dropFirst()))
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}
