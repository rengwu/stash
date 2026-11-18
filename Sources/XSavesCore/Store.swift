import Foundation

package actor Store {
    private let db: Database
    package nonisolated let mediaDir: URL

    package init(dataDir: URL) throws {
        mediaDir = dataDir.appending(path: "media", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        db = try Database(dataDir.appending(path: "xsaves.db"))
        try db.execute(Self.schema)
    }

    package func addPage(_ kind: Kind, posts: [Post], saves: [Save]) throws -> Int {
        try db.transaction {
            for p in posts {
                let row = try db.run("INSERT OR IGNORE INTO posts VALUES(?,?,?,?,?,?,?,?,?)",
                                     [p.id,p.authorID,p.name,p.handle,p.avatar,p.text,p.createdAt,p.quotedID,p.raw].map(SQLValue.text))
                guard row.changes > 0 else { continue }
                try db.run("INSERT INTO posts_fts(rowid,text,name,handle) VALUES(?,?,?,?)",
                           [.int(row.lastRowID), .text(p.text), .text(p.name), .text(p.handle)])
                for m in p.media {
                    try db.run("INSERT OR IGNORE INTO media(id,post_id,type,url,poster,w,h) VALUES(?,?,?,?,?,?,?)",
                               [.text(m.id), .text(p.id), .text(m.type.rawValue), .text(m.url), .text(m.poster), .int(Int64(m.width)), .int(Int64(m.height))])
                }
            }
            return try saves.reduce(0) { total, save in
                try total + db.run("INSERT OR IGNORE INTO saves VALUES(?,?,?)",
                                   [.text(save.postID), .text(kind.rawValue), .int(save.sort)]).changes
            }
        }
    }

    package func meta(_ key: String) throws -> String {
        try db.query("SELECT v FROM meta WHERE k=?", [.text(key)]) { $0.text(0) }.first ?? ""
    }
    package func setMeta(_ key: String, _ value: String) throws {
        try db.run("INSERT INTO meta VALUES(?,?) ON CONFLICT(k) DO UPDATE SET v=excluded.v", [.text(key), .text(value)])
    }

    private func filter(_ query: PostQuery) -> (String, [SQLValue]) {
        var sql = " FROM saves s JOIN posts p ON p.id=s.post_id WHERE 1"
        var bindings: [SQLValue] = []
        if let kind = query.kind {
            sql += " AND s.kind=?"
            bindings.append(.text(kind.rawValue))
        }
        if let board = query.board {
            sql += " AND p.id IN (SELECT post_id FROM board_posts WHERE board_id=?)"
            bindings.append(.int(board))
        }
        let terms = query.text.split(whereSeparator: \.isWhitespace).map {
            "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"*"
        }.joined(separator: " ")
        if !terms.isEmpty {
            sql += " AND p.rowid IN (SELECT rowid FROM posts_fts WHERE posts_fts MATCH ?)"
            bindings.append(.text(terms))
        }
        return (sql, bindings)
    }

    package func posts(_ query: PostQuery, offset: Int, limit: Int = 60) throws -> [PostView] {
        let (sql, bindings) = filter(query)
        return try db.query("SELECT p.id,p.quoted_id" + sql + " GROUP BY p.id ORDER BY max(s.sort) DESC,p.id LIMIT ? OFFSET ?",
                            bindings + [.int(Int64(limit)), .int(Int64(offset))]) { row in
            let id = row.text(0), quote = row.text(1)
            guard let post = try content(id) else { throw ArchiveError("Missing post \(id).") }
            let boards = try db.query("SELECT board_id FROM board_posts WHERE post_id=?", [.text(id)]) { $0.int(0) }
            return PostView(content: post, boards: Set(boards), quoted: quote.isEmpty ? nil : try content(quote))
        }
    }

    private func content(_ id: String) throws -> PostContent? {
        try db.query("SELECT author_id,name,handle,text,created_at FROM posts WHERE id=?", [.text(id)]) { post in
            let items = try db.query("SELECT id,type,url,w,h,done FROM media WHERE post_id=? ORDER BY rowid", [.text(id)]) { row -> MediaView? in
                guard let type = MediaType(rawValue: row.text(1)) else { return nil }
                let media = Media(id: row.text(0), type: type, url: row.text(2))
                let done = row.int(5) != 0
                return MediaView(id: media.id, type: type, width: Int(row.int(3)), height: Int(row.int(4)),
                                 file: done ? mediaDir.appending(path: Paths.mediaFile(id, media)) : nil,
                                 poster: done && type != .photo ? mediaDir.appending(path: Paths.posterFile(id, media)) : nil)
            }.compactMap { $0 }
            return PostContent(id: id, authorID: post.text(0), name: post.text(1), handle: post.text(2),
                               text: post.text(3), createdAt: try? Date(post.text(4), strategy: .iso8601), media: items)
        }.first
    }

    package func count(_ query: PostQuery) throws -> Int {
        let (sql, bindings) = filter(query)
        return try db.query("SELECT count(DISTINCT p.id)" + sql, bindings) { Int($0.int(0)) }[0]
    }
    package func counts() throws -> Counts {
        try db.query("SELECT count(DISTINCT post_id),sum(kind='bookmark'),sum(kind='like') FROM saves") {
            Counts(all: Int($0.int(0)), bookmarks: Int($0.int(1)), likes: Int($0.int(2)))
        }[0]
    }
    package func boards() throws -> [Board] {
        try db.query("SELECT b.id,b.name,count(bp.post_id) FROM boards b LEFT JOIN board_posts bp ON bp.board_id=b.id GROUP BY b.id ORDER BY b.name COLLATE NOCASE") {
            Board(id: $0.int(0), name: $0.text(1), count: Int($0.int(2)))
        }
    }
    @discardableResult
    package func createBoard(_ name: String) throws -> Int64 {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ArchiveError("Enter a board name.") }
        return try db.transaction {
            try db.run("INSERT OR IGNORE INTO boards(name) VALUES(?)", [.text(name)])
            return try db.query("SELECT id FROM boards WHERE name=?", [.text(name)]) { $0.int(0) }[0]
        }
    }
    package func deleteBoard(_ id: Int64) throws {
        try db.transaction {
            try db.run("DELETE FROM board_posts WHERE board_id=?", [.int(id)])
            try db.run("DELETE FROM boards WHERE id=?", [.int(id)])
        }
    }
    package func setPost(_ id: String, inBoard board: Int64, _ on: Bool) throws {
        try db.run(on ? "INSERT OR IGNORE INTO board_posts VALUES(?,?)" : "DELETE FROM board_posts WHERE board_id=? AND post_id=?", [.int(board), .text(id)])
    }
    func pendingMedia() throws -> [(String, Media)] {
        try db.query("SELECT id,post_id,type,url,poster FROM media WHERE done=0 AND url!=''") { row -> (String, Media)? in
            guard let type = MediaType(rawValue: row.text(2)) else { return nil }
            return (row.text(1), Media(id: row.text(0), type: type, url: row.text(3), poster: row.text(4)))
        }.compactMap { $0 }
    }
    func avatars() throws -> [(String, String)] {
        try db.query("SELECT DISTINCT author_id,avatar FROM posts WHERE avatar!=''") { ($0.text(0), $0.text(1)) }
    }
    func markDone(_ id: String) throws {
        try db.run("UPDATE media SET done=1 WHERE id=?", [.text(id)])
    }
    private static let schema = """
CREATE TABLE IF NOT EXISTS posts(
	id TEXT PRIMARY KEY, author_id TEXT, name TEXT, handle TEXT, avatar TEXT,
	text TEXT, created_at TEXT, quoted_id TEXT, raw TEXT);
CREATE TABLE IF NOT EXISTS saves(
	post_id TEXT, kind TEXT, sort INTEGER, PRIMARY KEY(post_id, kind));
CREATE TABLE IF NOT EXISTS media(
	id TEXT PRIMARY KEY, post_id TEXT, type TEXT, url TEXT, poster TEXT,
	w INTEGER, h INTEGER, done INTEGER NOT NULL DEFAULT 0);
CREATE INDEX IF NOT EXISTS media_post ON media(post_id);
CREATE TABLE IF NOT EXISTS boards(id INTEGER PRIMARY KEY, name TEXT UNIQUE);
CREATE TABLE IF NOT EXISTS board_posts(
	board_id INTEGER, post_id TEXT, PRIMARY KEY(board_id, post_id));
CREATE TABLE IF NOT EXISTS meta(k TEXT PRIMARY KEY, v TEXT);
CREATE VIRTUAL TABLE IF NOT EXISTS posts_fts USING fts5(text, name, handle);
"""
}
