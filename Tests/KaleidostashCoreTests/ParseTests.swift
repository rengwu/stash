import Foundation
import Testing
@testable import KaleidostashCore

let sample = #"""
{"data":{"bookmark_timeline_v2":{"timeline":{"instructions":[{"type":"TimelineAddEntries","entries":[
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
]}]}}}}
"""#

@Test func timeline() throws {
    let (posts, saves) = try Parse.parse(Data(sample.utf8))
    #expect(saves == [Save(postID: "100", sort: 1900000000000000100)])
    #expect(posts.map(\.id) == ["50","100"])
    let quote = try #require(posts.first), post = try #require(posts.last)
    #expect(quote.text == "the long version" && quote.handle == "bo" && !quote.avatar.isEmpty)
    #expect(post.text == "Tom & Jerry https://example.com/a")
    #expect(post.quotedID == "50" && post.handle == "ada" && post.createdAt == "2018-10-10T20:19:24Z")
    #expect(post.media.map(\.url) == ["https://pbs.twimg.com/media/AAA?format=jpg&name=orig","https://video.twimg.com/high.mp4"])
    #expect(post.media.last?.poster.isEmpty == false)
}
