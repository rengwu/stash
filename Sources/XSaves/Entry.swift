import SwiftUI

@main
enum Entry {
    @MainActor static func main() {
        guard CommandLine.arguments.dropFirst().allSatisfy({ $0.hasPrefix("-psn_") }) else {
            FileHandle.standardError.write(Data("usage: xsaves [sync [--login] | schedule on|off]\n".utf8))
            exit(1)
        }
        XSavesApp.main()
    }
}
