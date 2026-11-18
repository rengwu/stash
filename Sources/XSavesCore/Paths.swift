import Foundation

package enum Paths {
    package static var dataDir: URL {
        if let path = ProcessInfo.processInfo.environment["XSAVES_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return URL.applicationSupportDirectory.appending(path: "xsaves")
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
