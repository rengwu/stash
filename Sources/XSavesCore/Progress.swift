import Foundation

package struct SyncProgress: Codable, Sendable, Equatable {
    package var bookmarks = 0, likes = 0, media = 0
    package var error: String?
    package init() {}

    package func write() {
        guard var line = try? JSONEncoder().encode(self) else { return }
        line.append(10)
        FileHandle.standardOutput.write(line)
    }
}
