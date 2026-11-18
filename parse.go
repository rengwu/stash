package main

import (
	"encoding/json"
	"html"
	"path"
	"strconv"
	"strings"
	"time"
)

type Media struct {
	ID     string `json:"id"`
	Type   string `json:"type"` // photo, video, animated_gif
	URL    string `json:"-"`
	Poster string `json:"-"` // still image for video and animated_gif
	W      int    `json:"w"`
	H      int    `json:"h"`
}

type Post struct {
	ID        string
	AuthorID  string
	Name      string
	Handle    string
	Avatar    string
	Text      string
	CreatedAt string
	QuotedID  string
	Media     []Media
	Raw       string
}

// Save is one timeline entry: a post the user bookmarked or liked.
// Sort is X's own ordering key; larger means saved more recently.
type Save struct {
	PostID string
	Sort   int64
}

type obj = map[string]any

func get(v any, keys ...string) any {
	for _, k := range keys {
		m, ok := v.(obj)
		if !ok {
			return nil
		}
		v = m[k]
	}
	return v
}

func str(v any, keys ...string) string {
	s, _ := get(v, keys...).(string)
	return s
}

func list(v any, keys ...string) []any {
	l, _ := get(v, keys...).([]any)
	return l
}

// Parse reads one Bookmarks or Likes timeline response from x.com. It finds
// timeline entries wherever they sit, because the wrapper around them differs
// between the two timelines and has changed over time.
func Parse(body []byte) (posts []Post, saves []Save, err error) {
	var root any
	if err = json.Unmarshal(body, &root); err != nil {
		return nil, nil, err
	}
	var walk func(v any)
	walk = func(v any) {
		switch t := v.(type) {
		case []any:
			for _, e := range t {
				walk(e)
			}
		case obj:
			if id := str(t, "entryId"); strings.HasPrefix(id, "tweet-") {
				if p := parsePost(get(t, "content", "itemContent", "tweet_results", "result"), &posts); p != "" {
					sort, _ := strconv.ParseInt(str(t, "sortIndex"), 10, 64)
					saves = append(saves, Save{p, sort})
				}
				return
			}
			for _, e := range t {
				walk(e)
			}
		}
	}
	walk(root)
	return posts, saves, nil
}

// parsePost appends the post and any post it quotes, and returns its ID.
// It returns "" for tombstones and other results without post content.
func parsePost(r any, out *[]Post) string {
	if t := get(r, "tweet"); t != nil { // TweetWithVisibilityResults
		r = t
	}
	legacy := get(r, "legacy")
	id := str(r, "rest_id")
	if id == "" || legacy == nil {
		return ""
	}
	user := get(r, "core", "user_results", "result")
	p := Post{
		ID:       id,
		AuthorID: str(user, "rest_id"),
		Name:     first(str(user, "core", "name"), str(user, "legacy", "name")),
		Handle:   first(str(user, "core", "screen_name"), str(user, "legacy", "screen_name")),
		Avatar:   first(str(user, "avatar", "image_url"), str(user, "legacy", "profile_image_url_https")),
		Text:     str(legacy, "full_text"),
	}
	if t, err := time.Parse(time.RubyDate, str(legacy, "created_at")); err == nil {
		p.CreatedAt = t.UTC().Format(time.RFC3339)
	}
	urls := list(legacy, "entities", "urls")
	if note := get(r, "note_tweet", "note_tweet_results", "result"); str(note, "text") != "" {
		p.Text = str(note, "text")
		urls = list(note, "entity_set", "urls")
	}
	for _, u := range urls {
		if short, long := str(u, "url"), str(u, "expanded_url"); short != "" && long != "" {
			p.Text = strings.ReplaceAll(p.Text, short, long)
		}
	}
	for _, m := range list(legacy, "extended_entities", "media") {
		p.Text = strings.ReplaceAll(p.Text, str(m, "url"), "")
		p.Media = append(p.Media, parseMedia(m))
	}
	p.Text = strings.TrimSpace(html.UnescapeString(p.Text))
	p.QuotedID = parsePost(get(r, "quoted_status_result", "result"), out)

	if m, ok := r.(obj); ok { // the quoted post is stored as its own row
		delete(m, "quoted_status_result")
	}
	raw, _ := json.Marshal(r)
	p.Raw = string(raw)
	*out = append(*out, p)
	return id
}

func parseMedia(m any) Media {
	w, _ := get(m, "original_info", "width").(float64)
	h, _ := get(m, "original_info", "height").(float64)
	out := Media{ID: str(m, "id_str"), Type: str(m, "type"), W: int(w), H: int(h)}
	still := str(m, "media_url_https")
	if out.Type == "photo" {
		// Ask for the original size rather than the default downscaled one.
		if ext := path.Ext(still); ext != "" {
			still = strings.TrimSuffix(still, ext) + "?format=" + ext[1:] + "&name=orig"
		}
		out.URL = still
		return out
	}
	out.Poster = still
	best := -1.0
	for _, v := range list(m, "video_info", "variants") {
		if str(v, "content_type") != "video/mp4" {
			continue
		}
		if rate, _ := get(v, "bitrate").(float64); rate > best {
			best, out.URL = rate, str(v, "url")
		}
	}
	return out
}

func first(a, b string) string {
	if a != "" {
		return a
	}
	return b
}
