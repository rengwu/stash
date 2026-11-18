package main

import (
	"bufio"
	"database/sql"
	"embed"
	"encoding/json"
	"fmt"
	"io/fs"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"sync"
)

//go:embed ui
var uiFS embed.FS

type syncStatus struct {
	Running bool `json:"running"`
	Progress
}

type server struct {
	db   *sql.DB
	mu   sync.Mutex
	sync syncStatus
}

// serve starts the local server behind the window and returns its address.
func serve(db *sql.DB) (string, error) {
	s := &server{db: db}
	mux := http.NewServeMux()
	ui, _ := fs.Sub(uiFS, "ui")
	mux.Handle("GET /", http.FileServerFS(ui))
	mux.Handle("GET /media/", http.StripPrefix("/media/", http.FileServer(http.Dir(filepath.Join(dataDir(), "media")))))

	mux.HandleFunc("GET /api/posts", func(w http.ResponseWriter, r *http.Request) {
		q := r.URL.Query()
		board, _ := strconv.ParseInt(q.Get("board"), 10, 64)
		offset, _ := strconv.Atoi(q.Get("offset"))
		posts, err := listPosts(db, q.Get("q"), q.Get("kind"), board, offset)
		reply(w, posts, err)
	})

	mux.HandleFunc("GET /api/boards", func(w http.ResponseWriter, r *http.Request) {
		type board struct {
			ID   int64  `json:"id"`
			Name string `json:"name"`
		}
		boards := []board{}
		rows, err := db.Query(`SELECT id, name FROM boards ORDER BY name COLLATE NOCASE`)
		if err == nil {
			for rows.Next() {
				var b board
				rows.Scan(&b.ID, &b.Name)
				boards = append(boards, b)
			}
			err = rows.Close()
		}
		reply(w, boards, err)
	})
	mux.HandleFunc("POST /api/boards", func(w http.ResponseWriter, r *http.Request) {
		var in struct{ Name string }
		json.NewDecoder(r.Body).Decode(&in)
		if in.Name == "" {
			http.Error(w, "A board needs a name.", 400)
			return
		}
		_, err := db.Exec(`INSERT OR IGNORE INTO boards(name) VALUES(?)`, in.Name)
		reply(w, nil, err)
	})
	mux.HandleFunc("DELETE /api/boards/{board}", func(w http.ResponseWriter, r *http.Request) {
		_, err := db.Exec(`DELETE FROM board_posts WHERE board_id = ?`, r.PathValue("board"))
		if err == nil {
			_, err = db.Exec(`DELETE FROM boards WHERE id = ?`, r.PathValue("board"))
		}
		reply(w, nil, err)
	})
	mux.HandleFunc("PUT /api/boards/{board}/posts/{post}", func(w http.ResponseWriter, r *http.Request) {
		_, err := db.Exec(`INSERT OR IGNORE INTO board_posts VALUES(?, ?)`, r.PathValue("board"), r.PathValue("post"))
		reply(w, nil, err)
	})
	mux.HandleFunc("DELETE /api/boards/{board}/posts/{post}", func(w http.ResponseWriter, r *http.Request) {
		_, err := db.Exec(`DELETE FROM board_posts WHERE board_id = ? AND post_id = ?`, r.PathValue("board"), r.PathValue("post"))
		reply(w, nil, err)
	})

	mux.HandleFunc("GET /api/sync", func(w http.ResponseWriter, r *http.Request) {
		s.mu.Lock()
		defer s.mu.Unlock()
		reply(w, s.sync, nil)
	})
	mux.HandleFunc("POST /api/sync", func(w http.ResponseWriter, r *http.Request) {
		reply(w, nil, s.startSync())
	})

	mux.HandleFunc("GET /api/schedule", func(w http.ResponseWriter, r *http.Request) {
		reply(w, map[string]bool{"on": scheduled()}, nil)
	})
	mux.HandleFunc("POST /api/schedule", func(w http.ResponseWriter, r *http.Request) {
		var in struct{ On bool }
		json.NewDecoder(r.Body).Decode(&in)
		reply(w, nil, setSchedule(in.On))
	})

	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return "", err
	}
	go http.Serve(l, mux)
	return "http://" + l.Addr().String(), nil
}

func reply(w http.ResponseWriter, v any, err error) {
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(v)
}

// startSync runs "xsaves sync --login" as its own process, the same way the
// background schedule does, and follows the progress it prints.
func (s *server) startSync() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.sync.Running {
		return nil
	}
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	cmd := exec.Command(exe, "sync", "--login")
	out, err := cmd.StdoutPipe()
	if err != nil {
		return err
	}
	if err := cmd.Start(); err != nil {
		return err
	}
	s.sync = syncStatus{Running: true}
	go func() {
		lines := bufio.NewScanner(out)
		lines.Buffer(nil, 1<<20)
		for lines.Scan() {
			var p Progress
			if json.Unmarshal(lines.Bytes(), &p) == nil {
				s.mu.Lock()
				s.sync.Progress = p
				s.mu.Unlock()
			}
		}
		err := cmd.Wait()
		s.mu.Lock()
		defer s.mu.Unlock()
		s.sync.Running = false
		if err != nil && s.sync.Error == "" {
			s.sync.Error = fmt.Sprint("Sync stopped: ", err)
		}
	}()
	return nil
}
