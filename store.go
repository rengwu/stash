package main

import (
	"database/sql"
	"os"
	"path/filepath"
	"strings"

	_ "modernc.org/sqlite"
)

const schema = `
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
`

// dataDir holds the database and downloaded media.
func dataDir() string {
	if d := os.Getenv("XSAVES_DIR"); d != "" {
		return d
	}
	base, _ := os.UserConfigDir() // ~/Library/Application Support on macOS
	return filepath.Join(base, "xsaves")
}

func openStore() (*sql.DB, error) {
	if err := os.MkdirAll(filepath.Join(dataDir(), "media"), 0o755); err != nil {
		return nil, err
	}
	// The window and a background sync can have the database open together.
	db, err := sql.Open("sqlite", "file:"+filepath.Join(dataDir(), "xsaves.db")+
		"?_pragma=journal_mode(WAL)&_pragma=busy_timeout(10000)")
	if err != nil {
		return nil, err
	}
	if _, err := db.Exec(schema); err != nil {
		return nil, err
	}
	return db, nil
}

// addPage stores one parsed timeline response and reports how many of its
// saves were not already recorded for this kind.
func addPage(db *sql.DB, kind string, posts []Post, saves []Save) (added int, err error) {
	tx, err := db.Begin()
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()
	for _, p := range posts {
		res, err := tx.Exec(`INSERT OR IGNORE INTO posts VALUES(?,?,?,?,?,?,?,?,?)`,
			p.ID, p.AuthorID, p.Name, p.Handle, p.Avatar, p.Text, p.CreatedAt, p.QuotedID, p.Raw)
		if err != nil {
			return 0, err
		}
		if n, _ := res.RowsAffected(); n == 0 {
			continue
		}
		rowid, _ := res.LastInsertId()
		if _, err := tx.Exec(`INSERT INTO posts_fts(rowid, text, name, handle) VALUES(?,?,?,?)`,
			rowid, p.Text, p.Name, p.Handle); err != nil {
			return 0, err
		}
		for _, m := range p.Media {
			if _, err := tx.Exec(`INSERT OR IGNORE INTO media(id, post_id, type, url, poster, w, h) VALUES(?,?,?,?,?,?,?)`,
				m.ID, p.ID, m.Type, m.URL, m.Poster, m.W, m.H); err != nil {
				return 0, err
			}
		}
	}
	for _, s := range saves {
		res, err := tx.Exec(`INSERT OR IGNORE INTO saves VALUES(?,?,?)`, s.PostID, kind, s.Sort)
		if err != nil {
			return 0, err
		}
		n, _ := res.RowsAffected()
		added += int(n)
	}
	return added, tx.Commit()
}

func getMeta(db *sql.DB, k string) (v string) {
	db.QueryRow(`SELECT v FROM meta WHERE k=?`, k).Scan(&v)
	return v
}

func setMeta(db *sql.DB, k, v string) {
	db.Exec(`INSERT INTO meta VALUES(?,?) ON CONFLICT(k) DO UPDATE SET v=excluded.v`, k, v)
}

type MediaView struct {
	Media
	File   string `json:"file,omitempty"`   // path under /media/, set once downloaded
	Poster string `json:"poster,omitempty"` // likewise
}

type PostView struct {
	ID        string      `json:"id"`
	AuthorID  string      `json:"authorId"`
	Name      string      `json:"name"`
	Handle    string      `json:"handle"`
	Text      string      `json:"text"`
	CreatedAt string      `json:"createdAt"`
	Kinds     []string    `json:"kinds,omitempty"`
	Boards    []int64     `json:"boards,omitempty"`
	Media     []MediaView `json:"media,omitempty"`
	Quoted    *PostView   `json:"quoted,omitempty"`
}

const pageSize = 60

// listPosts returns saved posts, most recently saved first. q is a free-text
// search, kind is "bookmark", "like" or "", and board is a board ID or 0.
func listPosts(db *sql.DB, q, kind string, board int64, offset int) ([]PostView, error) {
	where, args := []string{"1"}, []any{}
	if kind != "" {
		where, args = append(where, "s.kind = ?"), append(args, kind)
	}
	if board != 0 {
		where = append(where, "p.id IN (SELECT post_id FROM board_posts WHERE board_id = ?)")
		args = append(args, board)
	}
	if match := ftsQuery(q); match != "" {
		where = append(where, "p.rowid IN (SELECT rowid FROM posts_fts WHERE posts_fts MATCH ?)")
		args = append(args, match)
	}
	rows, err := db.Query(`
		SELECT p.id, p.quoted_id, group_concat(DISTINCT s.kind)
		FROM saves s JOIN posts p ON p.id = s.post_id
		WHERE `+strings.Join(where, " AND ")+`
		GROUP BY p.id ORDER BY max(s.sort) DESC LIMIT ? OFFSET ?`,
		append(args, pageSize, offset)...)
	if err != nil {
		return nil, err
	}
	type row struct{ id, quoted, kinds string }
	var found []row
	for rows.Next() {
		var r row
		if err := rows.Scan(&r.id, &r.quoted, &r.kinds); err != nil {
			return nil, err
		}
		found = append(found, r)
	}
	if err := rows.Close(); err != nil {
		return nil, err
	}
	out := make([]PostView, 0, len(found))
	for _, r := range found {
		v := loadPost(db, r.id)
		v.Kinds = strings.Split(r.kinds, ",")
		if r.quoted != "" {
			quoted := loadPost(db, r.quoted)
			v.Quoted = &quoted
		}
		out = append(out, v)
	}
	return out, nil
}

func loadPost(db *sql.DB, id string) PostView {
	v := PostView{ID: id}
	db.QueryRow(`SELECT author_id, name, handle, text, created_at FROM posts WHERE id=?`, id).
		Scan(&v.AuthorID, &v.Name, &v.Handle, &v.Text, &v.CreatedAt)
	rows, err := db.Query(`SELECT id, type, url, w, h, done FROM media WHERE post_id=? ORDER BY rowid`, id)
	if err == nil {
		for rows.Next() {
			var m MediaView
			var done bool
			rows.Scan(&m.ID, &m.Type, &m.URL, &m.W, &m.H, &done)
			if done {
				m.File = mediaFile(id, m.Media)
				if m.Type != "photo" {
					m.Poster = posterFile(id, m.Media)
				}
			}
			v.Media = append(v.Media, m)
		}
		rows.Close()
	}
	rows, err = db.Query(`SELECT board_id FROM board_posts WHERE post_id=?`, id)
	if err == nil {
		for rows.Next() {
			var b int64
			rows.Scan(&b)
			v.Boards = append(v.Boards, b)
		}
		rows.Close()
	}
	return v
}

// ftsQuery turns typed words into a prefix search on every word, quoting each
// so that punctuation is never read as search syntax.
func ftsQuery(q string) string {
	var terms []string
	for _, w := range strings.Fields(q) {
		terms = append(terms, `"`+strings.ReplaceAll(w, `"`, `""`)+`"*`)
	}
	return strings.Join(terms, " ")
}

// Media paths, relative to the media directory.
func mediaFile(postID string, m Media) string {
	ext := ".mp4"
	if m.Type == "photo" {
		ext = ".jpg"
		if i := strings.Index(m.URL, "format="); i >= 0 {
			ext = "." + strings.SplitN(m.URL[i+len("format="):], "&", 2)[0]
		}
	}
	return postID + "/" + m.ID + ext
}

func posterFile(postID string, m Media) string { return postID + "/" + m.ID + ".poster.jpg" }

func avatarFile(authorID string) string { return "avatars/" + authorID + ".jpg" }
