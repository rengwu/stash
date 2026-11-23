import Foundation

package enum Paths {
    private static let archiveNames = ["Kaleidostash", "stash", "mosaic", "xsaves"]

    package static var dataDirOverride: String? {
        let env = ProcessInfo.processInfo.environment
        return [env["KALEIDOSTASH_DIR"], env["STASH_DIR"], env["MOSAIC_DIR"], env["XSAVES_DIR"]].compactMap { $0 }.first { !$0.isEmpty }
    }

    package static var dataDir: URL {
        if let path = dataDirOverride {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return defaultDataDir(in: .applicationSupportDirectory)
    }

    static func defaultDataDir(in applicationSupport: URL) -> URL {
        for name in archiveNames {
            let dir = applicationSupport.appending(path: name)
            if existingDatabase(in: dir) != nil { return dir }
        }
        return applicationSupport.appending(path: "Kaleidostash")
    }

    static func databaseURL(in dir: URL) -> URL {
        existingDatabase(in: dir) ?? dir.appending(path: "kaleidostash.db")
    }

    private static func existingDatabase(in dir: URL) -> URL? {
        archiveNames.lazy.map { dir.appending(path: $0.lowercased() + ".db") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func mediaFile(_ postID: String, _ media: Media) -> String {
        let format = URLComponents(string: media.url)?.queryItems?.first { $0.name == "format" }?.value
        return "\(postID)/\(media.id)." + (media.type == .photo ? format ?? "jpg" : "mp4")
    }

    static func posterFile(_ postID: String, _ media: Media) -> String { "\(postID)/\(media.id).poster.jpg" }
    package static func avatarFile(_ authorID: String) -> String { "avatars/\(authorID).jpg" }
    static func avatarURL(_ url: String) -> String {
        guard let range = url.range(of: "_normal.") else { return url }
        return url.replacingCharacters(in: range, with: "_400x400.")
    }
}
