import Foundation

package enum Kind: String, Sendable { case bookmark, like }
package enum MediaType: String, Sendable { case photo, video, animatedGIF = "animated_gif" }

package struct Media: Sendable {
    package let id: String
    package let type: MediaType
    package var url = "", poster = ""
    package var width = 0, height = 0
}

package struct Post: Sendable {
    package let id: String
    package var authorID = "", name = "", handle = "", avatar = ""
    package var text = "", createdAt = "", quotedID = "", raw = ""
    package var media: [Media] = []
}

package struct Save: Sendable, Equatable {
    package let postID: String
    package let sort: Int64
}

package struct MediaView: Sendable, Hashable, Identifiable {
    package let id: String
    package let type: MediaType
    package let width: Int, height: Int
    package let file: URL?, poster: URL?
}

package struct PostContent: Sendable, Hashable {
    package let id: String, authorID: String, name: String, handle: String, text: String
    package let createdAt: Date?
    package let media: [MediaView]
}

package struct PostView: Sendable, Hashable, Identifiable {
    package var id: String { content.id }
    package let content: PostContent
    package var boards: Set<Int64>
    package let quoted: PostContent?
}

package struct Board: Sendable, Hashable, Identifiable {
    package let id: Int64, name: String, count: Int
}

package struct Counts: Sendable, Equatable {
    package let all: Int, bookmarks: Int, likes: Int
    package static let empty = Counts(all: 0, bookmarks: 0, likes: 0)
}

package struct PostQuery: Sendable, Equatable {
    package var kind: Kind?, board: Int64?, text: String
    package init(kind: Kind? = nil, board: Int64? = nil, text: String = "") {
        self.kind = kind
        self.board = board
        self.text = text
    }
}
