package main

import "testing"

// A hand-written response in the shape x.com returned for the Bookmarks
// timeline. It is not a recording of live data.
const sample = `{"data":{"bookmark_timeline_v2":{"timeline":{"instructions":[{"type":"TimelineAddEntries","entries":[
{"entryId":"tweet-100","sortIndex":"1900000000000000100","content":{"itemContent":{"tweet_results":{"result":{
  "__typename":"Tweet","rest_id":"100",
  "core":{"user_results":{"result":{"rest_id":"7","legacy":{"name":"Ada","screen_name":"ada","profile_image_url_https":"https://pbs.twimg.com/profile_images/7/a_normal.jpg"}}}},
  "legacy":{"full_text":"Tom &amp; Jerry https://t.co/link https://t.co/media","created_at":"Wed Oct 10 20:19:24 +0000 2018",
    "entities":{"urls":[{"url":"https://t.co/link","expanded_url":"https://example.com/a"}]},
    "extended_entities":{"media":[
      {"id_str":"m1","type":"photo","url":"https://t.co/media","media_url_https":"https://pbs.twimg.com/media/AAA.jpg","original_info":{"width":1200,"height":800}},
      {"id_str":"m2","type":"video","url":"https://t.co/media","media_url_https":"https://pbs.twimg.com/thumb/BBB.jpg","video_info":{"variants":[
        {"content_type":"application/x-mpegURL","url":"https://video.twimg.com/x.m3u8"},
        {"content_type":"video/mp4","bitrate":832000,"url":"https://video.twimg.com/low.mp4"},
        {"content_type":"video/mp4","bitrate":2176000,"url":"https://video.twimg.com/high.mp4"}]}}]}},
  "quoted_status_result":{"result":{"__typename":"TweetWithVisibilityResults","tweet":{"rest_id":"50",
    "core":{"user_results":{"result":{"rest_id":"8","core":{"name":"Bo","screen_name":"bo"},"avatar":{"image_url":"https://pbs.twimg.com/profile_images/8/b.jpg"}}}},
    "legacy":{"full_text":"short","created_at":"Wed Oct 10 20:19:24 +0000 2018"},
    "note_tweet":{"note_tweet_results":{"result":{"text":"the long version"}}}}}}
}}}}},
{"entryId":"tweet-101","sortIndex":"1900000000000000099","content":{"itemContent":{"tweet_results":{"result":{"__typename":"TweetTombstone"}}}}},
{"entryId":"cursor-bottom-1","sortIndex":"1","content":{"value":"abc"}}
]}]}}}}`

func TestParse(t *testing.T) {
	posts, saves, err := Parse([]byte(sample))
	if err != nil {
		t.Fatal(err)
	}
	if len(saves) != 1 || saves[0] != (Save{"100", 1900000000000000100}) {
		t.Fatalf("saves = %+v", saves)
	}
	if len(posts) != 2 {
		t.Fatalf("got %d posts, want the save and the post it quotes", len(posts))
	}
	q, p := posts[0], posts[1]
	if q.ID != "50" || q.Text != "the long version" || q.Handle != "bo" || q.Avatar == "" {
		t.Errorf("quoted = %+v", q)
	}
	if p.Text != "Tom & Jerry https://example.com/a" {
		t.Errorf("text = %q", p.Text)
	}
	if p.QuotedID != "50" || p.Handle != "ada" || p.CreatedAt != "2018-10-10T20:19:24Z" {
		t.Errorf("post = %+v", p)
	}
	if len(p.Media) != 2 {
		t.Fatalf("media = %+v", p.Media)
	}
	if got := p.Media[0].URL; got != "https://pbs.twimg.com/media/AAA?format=jpg&name=orig" {
		t.Errorf("photo url = %q", got)
	}
	if v := p.Media[1]; v.URL != "https://video.twimg.com/high.mp4" || v.Poster == "" {
		t.Errorf("video = %+v", v)
	}
}
