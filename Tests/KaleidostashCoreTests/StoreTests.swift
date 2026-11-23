import Foundation
import Testing
@testable import KaleidostashCore

@Test func archive() async throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = try Store(dataDir: dir)
    let page = try Parse.parse(Data(sample.utf8))
    let other = Post(id: "2", text: "Swift C++")
    #expect(try await store.addPage(.bookmark, posts: page.posts, saves: page.saves) == 1)
    #expect(try await store.addPage(.bookmark, posts: page.posts, saves: page.saves) == 0)
    #expect(try await store.addPage(.like, posts: [other], saves: [.init(postID: "2", sort: 1)] + page.saves) == 2)
    #expect(try await store.counts() == Counts(all: 2, bookmarks: 1, likes: 2))
    let db = try Database(dir.appending(path: "kaleidostash.db"))
    for (table, expected) in [("posts",3), ("posts_fts",3), ("media",2)] {
        #expect(try db.query("SELECT count(*) FROM \(table)") { Int($0.int(0)) } == [expected])
    }
    #expect(try await store.posts(.init(), offset: 1, limit: 1).map(\.id) == ["2"])
    #expect(try await store.count(.init(kind: .bookmark)) == 1)
    #expect(try await store.posts(.init(text: "swi"), offset: 0).map(\.id) == ["2"])
    // FTS5 tokenizes C++ as c. The other post also contains a .com URL.
    #expect(try await store.count(.init(text: "c++")) == 2)
    for text in ["\"","-","*"] { #expect(try await store.count(.init(text: text)) == 0) }
    for item in try await store.pendingMedia() { try await store.markDone(item.1.id) }
    let post = try #require(try await store.posts(.init(), offset: 0).first)
    #expect(post.quoted?.id == "50")
    #expect(post.content.media.allSatisfy { $0.file != nil })
    #expect(post.content.media[0].poster == nil && post.content.media[1].poster != nil)
    let board = try await store.createBoard(" Test ")
    #expect(try await store.createBoard("Test") == board)
    try await store.setPost("2", inBoard: board, true)
    #expect(try await store.boards().first?.count == 1)
    #expect(try await store.posts(.init(board: board), offset: 0).map(\.id) == ["2"])
    try await store.deleteBoard(board)
    #expect(try await store.boards().isEmpty)
    #expect(try await store.count(.init(board: board)) == 0)
}

@Test(arguments: ["stash", "mosaic", "xsaves"])
func existingArchiveOpensInPlace(previousName: String) async throws {
    let files = FileManager.default
    let support = files.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? files.removeItem(at: support) }
    let current = support.appending(path: "Kaleidostash")
    let legacy = support.appending(path: previousName)
    #expect(Paths.defaultDataDir(in: support).path == current.path)

    try files.createDirectory(at: legacy, withIntermediateDirectories: true)
    let db = try Database(legacy.appending(path: previousName + ".db"))
    try db.execute("CREATE TABLE meta(k TEXT PRIMARY KEY, v TEXT); INSERT INTO meta VALUES('marker','existing')")
    let resolved = Paths.defaultDataDir(in: support)
    #expect(resolved.path == legacy.path)
    let store = try Store(dataDir: resolved)
    #expect(try await store.meta("marker") == "existing")
    #expect(!files.fileExists(atPath: legacy.appending(path: "kaleidostash.db").path))

    _ = try Store(dataDir: current)
    #expect(Paths.defaultDataDir(in: support).path == current.path)
}

@Test func pathsAndProgress() throws {
    var photo = Media(id: "m", type: .photo, url: "https://pbs.twimg.com/a?format=png&name=orig")
    #expect(Paths.mediaFile("p", photo) == "p/m.png")
    photo.url = ""
    #expect(Paths.mediaFile("p", photo) == "p/m.jpg")
    for type in [MediaType.video, .animatedGIF] {
        #expect(Paths.mediaFile("p", Media(id: "m", type: type)) == "p/m.mp4")
    }
    #expect(Paths.posterFile("p", photo) == "p/m.poster.jpg")
    #expect(Paths.avatarFile("a") == "avatars/a.jpg")
    #expect(Paths.avatarURL("a_normal.jpg") == "a_400x400.jpg")
    #expect(!String(decoding: try JSONEncoder().encode(SyncProgress()), as: UTF8.self).contains("error"))
    #expect(try JSONDecoder().decode(SyncProgress.self, from: Data(#"{"bookmarks":2,"likes":0,"media":1}"#.utf8)).bookmarks == 2)
}
