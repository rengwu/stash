package main

import (
	"database/sql"
	_ "embed"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"

	webview "github.com/webview/webview_go"
)

//go:embed inject.js
var injectJS string

// Progress is printed as one JSON line per change, for the window to read.
type Progress struct {
	Bookmarks int    `json:"bookmarks"` // new saves found this run
	Likes     int    `json:"likes"`
	Media     int    `json:"media"` // files still to download
	Error     string `json:"error,omitempty"`
}

var phases = []struct{ op, kind string }{{"Bookmarks", "bookmark"}, {"Likes", "like"}}

type syncer struct {
	db       *sql.DB
	w        webview.WebView
	login    bool // may show the window for the user to sign in
	phase    int
	handle   string
	stop     bool      // this phase has reached saves it already holds
	started  time.Time // when this phase began
	opened   bool      // this phase's page has been requested
	gotData  bool      // this phase's timeline has answered
	lastData time.Time // its latest answer
	path     string
	shown    bool
	mu       sync.Mutex // guards p, which the downloader also updates
	p        Progress
}

// runSync opens x.com in an invisible window, scrolls the bookmarks and likes
// timelines, stores what the site loads, then downloads the media.
func runSync(login bool) error {
	lock, err := os.OpenFile(filepath.Join(dataDir(), "sync.lock"), os.O_CREATE|os.O_RDWR, 0o644)
	if err != nil {
		return err
	}
	defer lock.Close()
	if syscall.Flock(int(lock.Fd()), syscall.LOCK_EX|syscall.LOCK_NB) != nil {
		return errors.New("a sync is already running")
	}
	db, err := openStore()
	if err != nil {
		return err
	}
	defer db.Close()

	s := &syncer{db: db, w: webview.New(false), login: login, started: time.Now(), opened: true}
	defer s.w.Destroy()
	s.w.SetTitle("Sign in to X")
	s.w.SetSize(1280, 900, webview.HintNone) // wide enough for x.com's sidebar, which names the account
	windowInvisible(s.w.Window())
	s.w.Bind("xsCapture", s.capture)
	s.w.Bind("xsTick", s.tick)
	s.w.Init(injectJS)
	s.w.Navigate("https://x.com/i/bookmarks")

	// Media downloads while the page scrolls, then once more for the last of it.
	quit, finished := make(chan struct{}), make(chan struct{})
	media := func() {
		downloadMedia(db, func(left int) { s.update(func(p *Progress) { p.Media = left }) })
	}
	go func() {
		defer close(finished)
		for {
			media()
			select {
			case <-quit:
				media()
				return
			case <-time.After(3 * time.Second):
			}
		}
	}()
	s.w.Run()
	close(quit)
	<-finished
	if s.p.Error != "" {
		return errors.New(s.p.Error)
	}
	return nil
}

// update changes the progress and prints it.
func (s *syncer) update(change func(*Progress)) {
	s.mu.Lock()
	defer s.mu.Unlock()
	change(&s.p)
	json.NewEncoder(os.Stdout).Encode(s.p)
}

func (s *syncer) fail(msg string) {
	s.update(func(p *Progress) { p.Error = msg })
	s.w.Terminate()
}

// capture stores one timeline response from x.com.
func (s *syncer) capture(op string, status int, body string) {
	kind := phases[0].kind
	if op == phases[1].op {
		kind = phases[1].kind
	}
	if status != 200 {
		s.fail(fmt.Sprintf("X refused the request (status %d). Try again later.", status))
		return
	}
	posts, saves, err := Parse([]byte(body))
	if err == nil {
		var added int
		if added, err = addPage(s.db, kind, posts, saves); err == nil {
			fmt.Fprintf(os.Stderr, "%s page: %d saves, %d new\n", kind, len(saves), added)
			s.update(func(p *Progress) {
				if kind == "bookmark" {
					p.Bookmarks += added
				} else {
					p.Likes += added
				}
			})
			if s.phase == len(phases) || kind != phases[s.phase].kind {
				return
			}
			s.gotData, s.lastData = true, time.Now()
			switch {
			case len(saves) == 0:
				// X ends a timeline with an empty page: the whole history is now held.
				setMeta(s.db, "complete:"+kind, "1")
				s.stop = true
			case added == 0 && getMeta(s.db, "complete:"+kind) == "1":
				s.stop = true // everything older is already held
			}
		}
	}
	if err != nil {
		s.fail(err.Error())
	}
}

type action struct {
	Go     string `json:"go,omitempty"`
	Scroll bool   `json:"scroll,omitempty"`
}

// tick is called by the page every second or two and decides its next move.
func (s *syncer) tick(path, handle string, signedIn bool) action {
	if s.phase == len(phases) {
		return action{} // finished; the window is closing
	}
	now := time.Now()
	if handle != "" {
		s.handle = handle
	}
	if path != s.path {
		s.path = path
		fmt.Fprintln(os.Stderr, "x.com is showing", path)
	}
	if !signedIn {
		s.started = now
		if !s.login {
			s.fail("Sign in to X: press Sync in the xsaves window.")
		} else if !s.shown {
			s.shown = true
			windowVisible(s.w.Window())
			return action{Go: "https://x.com/i/flow/login"}
		}
		return action{}
	}
	if s.shown {
		s.shown, s.opened = false, false
		windowInvisible(s.w.Window())
	}

	// X redirects these addresses as its site changes, so the phase's own data
	// arriving is what shows that the right page opened.
	if !s.gotData {
		want := "/i/bookmarks"
		if s.phase == 1 {
			want = "/" + s.handle + "/likes"
		}
		switch {
		case now.Sub(s.started) > 45*time.Second:
			s.fail("X did not load your " + phases[s.phase].kind + "s. It showed " + path + ".")
		case s.phase == 1 && s.handle == "":
			// Wait for the sidebar, which names the account.
		case !s.opened:
			s.opened = true
			return action{Go: "https://x.com" + want}
		}
		return action{}
	}

	// A phase also ends when x.com stops loading, without being marked complete.
	if s.stop || now.Sub(s.lastData) > 30*time.Second {
		if !s.stop {
			fmt.Fprintln(os.Stderr, phases[s.phase].kind+"s stopped loading before the end")
		}
		s.phase++
		s.stop, s.gotData, s.opened, s.started = false, false, false, now
		if s.phase == len(phases) {
			s.w.Terminate()
		}
		return action{}
	}
	return action{Scroll: true}
}

// failed holds downloads that failed in this run, so one run tries each once.
var failed = map[string]bool{}

// downloadMedia fetches every media file and avatar not yet on disk. Failed
// downloads are left for the next sync.
func downloadMedia(db *sql.DB, progress func(left int)) {
	type job struct {
		url, file string
		mediaID   string // set on the file that completes a media row
	}
	var jobs []job
	rows, err := db.Query(`SELECT id, post_id, type, url, poster FROM media WHERE done = 0 AND url != ''`)
	if err != nil {
		return
	}
	for rows.Next() {
		var m Media
		var post string
		rows.Scan(&m.ID, &post, &m.Type, &m.URL, &m.Poster)
		if m.Poster != "" {
			jobs = append(jobs, job{url: m.Poster, file: posterFile(post, m)})
		}
		jobs = append(jobs, job{m.URL, mediaFile(post, m), m.ID})
	}
	rows.Close()
	rows, err = db.Query(`SELECT DISTINCT author_id, avatar FROM posts WHERE avatar != ''`)
	if err != nil {
		return
	}
	for rows.Next() {
		var id, url string
		rows.Scan(&id, &url)
		jobs = append(jobs, job{url: strings.Replace(url, "_normal.", "_400x400.", 1), file: avatarFile(id)})
	}
	rows.Close()

	dir := filepath.Join(dataDir(), "media")
	todo := jobs[:0]
	for _, j := range jobs {
		if failed[j.file] {
			continue
		}
		if _, err := os.Stat(filepath.Join(dir, j.file)); err != nil || j.mediaID != "" {
			todo = append(todo, j)
		}
	}

	var wg sync.WaitGroup
	var mu sync.Mutex
	left := len(todo)
	progress(left)
	slots := make(chan struct{}, 4)
	for _, j := range todo {
		wg.Add(1)
		slots <- struct{}{}
		go func() {
			defer func() { <-slots; wg.Done() }()
			err := fetch(j.url, filepath.Join(dir, j.file))
			mu.Lock()
			defer mu.Unlock()
			if err != nil {
				failed[j.file] = true
			} else if j.mediaID != "" {
				db.Exec(`UPDATE media SET done = 1 WHERE id = ?`, j.mediaID)
			}
			left--
			progress(left)
		}()
	}
	wg.Wait()
}

var client = &http.Client{Timeout: 10 * time.Minute}

func fetch(url, dest string) error {
	res, err := client.Get(url)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	if res.StatusCode != 200 {
		return fmt.Errorf("%s: %s", url, res.Status)
	}
	if err := os.MkdirAll(filepath.Dir(dest), 0o755); err != nil {
		return err
	}
	tmp := dest + ".part"
	f, err := os.Create(tmp)
	if err != nil {
		return err
	}
	_, err = io.Copy(f, res.Body)
	if cerr := f.Close(); err == nil {
		err = cerr
	}
	if err != nil {
		os.Remove(tmp)
		return err
	}
	return os.Rename(tmp, dest)
}
