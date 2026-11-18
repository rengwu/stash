import SwiftUI
import XSavesCore

@main
enum Entry {
    @MainActor static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-psn_") })
        do {
            switch arguments {
            case []: XSavesApp.main()
            case ["sync"], ["sync", "--login"]: try SyncCommand.run(login: arguments.count == 2)
            case ["schedule", "on"], ["schedule", "off"]: try Schedule().set(on: arguments[1] == "on")
            default: throw ArchiveError("usage: xsaves [sync [--login] | schedule on|off]")
            }
        } catch {
            if arguments.first == "sync" {
                var progress = SyncProgress()
                progress.error = error.localizedDescription
                progress.write()
            }
            log(error.localizedDescription)
            exit(1)
        }
    }
}
