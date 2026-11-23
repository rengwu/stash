import Foundation

private typealias Object = [String: Any]

private extension Dictionary where Key == String, Value == Any {
    func object(_ key: String) -> Object { self[key] as? Object ?? [:] }
    func string(_ key: String, fallback: String = "") -> String {
        guard let value = self[key] as? String, !value.isEmpty else { return fallback }
        return value
    }
    func objects(_ key: String) -> [Object] { self[key] as? [Object] ?? [] }
}

package enum Parse {
    package static func parse(_ data: Data) throws -> (posts: [Post], saves: [Save]) {
        var posts: [Post] = [], saves: [Save] = []
        let date = DateFormatter()
        date.locale = Locale(identifier: "en_US_POSIX")
        date.dateFormat = "EEE MMM dd HH:mm:ss Z yyyy"

        func post(_ result: Object) throws -> String {
            var tweet = result["tweet"] as? Object ?? result
            let id = tweet.string("rest_id")
            guard !id.isEmpty, let legacy = tweet["legacy"] as? Object else { return "" }
            let user = tweet.object("core").object("user_results").object("result")
            let old = user.object("legacy"), core = user.object("core")
            var p = Post(id: id, authorID: user.string("rest_id"),
                         name: core.string("name", fallback: old.string("name")),
                         handle: core.string("screen_name", fallback: old.string("screen_name")),
                         avatar: user.object("avatar").string("image_url", fallback: old.string("profile_image_url_https")))
            p.createdAt = date.date(from: legacy.string("created_at"))?.ISO8601Format() ?? ""
            let note = tweet.object("note_tweet").object("note_tweet_results").object("result")
            p.text = note.string("text", fallback: legacy.string("full_text"))
            let entities = note.string("text").isEmpty ? legacy.object("entities") : note.object("entity_set")
            for url in entities.objects("urls") {
                let short = url.string("url"), long = url.string("expanded_url")
                if !short.isEmpty && !long.isEmpty { p.text = p.text.replacingOccurrences(of: short, with: long) }
            }
            for item in legacy.object("extended_entities").objects("media") {
                let short = item.string("url")
                if !short.isEmpty { p.text = p.text.replacingOccurrences(of: short, with: "") }
                if let media = media(item) { p.media.append(media) }
            }
            p.text = unescape(p.text).trimmingCharacters(in: .whitespacesAndNewlines)
            p.quotedID = try post(tweet.object("quoted_status_result").object("result"))
            tweet.removeValue(forKey: "quoted_status_result")
            p.raw = String(decoding: try JSONSerialization.data(withJSONObject: tweet, options: .sortedKeys), as: UTF8.self)
            posts.append(p)
            return id
        }

        func walk(_ value: Any) throws {
            if let list = value as? [Any] { try list.forEach(walk) }
            guard let object = value as? Object else { return }
            if object.string("entryId").hasPrefix("tweet-") {
                let id = try post(object.object("content").object("itemContent").object("tweet_results").object("result"))
                if !id.isEmpty { saves.append(Save(postID: id, sort: Int64(object.string("sortIndex")) ?? 0)) }
            } else {
                try object.values.forEach(walk)
            }
        }
        try walk(JSONSerialization.jsonObject(with: data))
        return (posts, saves)
    }

    private static func media(_ item: Object) -> Media? {
        guard let type = MediaType(rawValue: item.string("type")) else { return nil }
        let still = item.string("media_url_https"), size = item.object("original_info")
        var result = Media(id: item.string("id_str"), type: type, width: size["width"] as? Int ?? 0, height: size["height"] as? Int ?? 0)
        if type == .photo {
            let ext = (still as NSString).pathExtension
            result.url = ext.isEmpty ? still : String(still.dropLast(ext.count + 1)) + "?format=\(ext)&name=orig"
        } else {
            result.poster = still
            let variants = item.object("video_info").objects("variants").filter { $0.string("content_type") == "video/mp4" }
            result.url = variants.max { ($0["bitrate"] as? Int ?? 0) < ($1["bitrate"] as? Int ?? 0) }?.string("url") ?? ""
        }
        return result
    }

    private static func unescape(_ text: String) -> String {
        let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'"]
        return text.replacing(/&(amp|lt|gt|quot|apos|#[0-9]+|#[xX][\da-fA-F]+);/) { match in
            let entity = String(match.1)
            if let replacement = named[entity] { return replacement }
            let hex = entity.lowercased().hasPrefix("#x")
            guard let code = UInt32(entity.dropFirst(hex ? 2 : 1), radix: hex ? 16 : 10),
                  let scalar = Unicode.Scalar(code) else { return String(match.0) }
            return String(scalar)
        }
    }
}
