import SwiftUI
import StashCore

struct GridView: View {
    let model: AppModel
    var body: some View {
        let columns = model.columns, posts = model.posts
        ScrollView {
            HStack(alignment: .top, spacing: 12) {
                ForEach(columns.indices, id: \.self) { col in
                    LazyVStack(spacing: 12) {
                        ForEach(columns[col].map { (index: $0, post: posts[$0]) }, id: \.post.id) { index, post in
                            Button { model.select(post.id) } label: {
                                CardView(post: post, mediaDir: model.store?.mediaDir)
                            }
                            .buttonStyle(.plain)
                            .overlay {
                                if model.selection == post.id {
                                    RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, lineWidth: 3)
                                }
                            }
                            .accessibilityLabel("\(post.content.name), \(post.content.text.prefix(80))")
                            .onAppear { Task { await model.more(after: index) } }
                        }
                    }.frame(maxWidth: .infinity)
                }
            }.padding(.horizontal, 16).padding(.vertical, 12)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { model.resize($0) }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.visibleRect.maxY >= geometry.contentSize.height - 600 ? geometry.contentSize.height : 0
        } action: { _, nearEnd in
            if nearEnd > 0 { Task { await model.more(after: model.posts.count) } }
        }
        .onExitCommand { model.selection = nil }
    }
}

/// A grid card laid out like a post on X, kept compact: the byline with a small avatar, then text,
/// media inset with rounded corners, and the quoted post in a box with its media as a short strip.
struct CardView: View {
    let post: PostView
    let mediaDir: URL?
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Byline(post: post.content, mediaDir: mediaDir, avatar: 18)
            if !post.content.text.isEmpty { Text(post.content.text).lineLimit(5) }
            let media = post.content.media.filter { $0.file != nil }
            if !media.isEmpty {
                CardMedia(items: media)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay { RoundedRectangle(cornerRadius: 12).stroke(.separator, lineWidth: 0.5) }
                    .padding(.top, 5)
            }
            if let quote = post.quoted {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Byline(post: quote, mediaDir: mediaDir, avatar: 16)
                        if !quote.text.isEmpty { Text(quote.text).lineLimit(3) }
                    }
                    .font(.callout).padding(.horizontal, 10).padding(.vertical, 8)
                    let media = quote.media.filter { $0.file != nil }
                    if !media.isEmpty {
                        Divider()
                        CardMedia(items: media, strip: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).stroke(.separator) }
                .padding(.top, 5)
            }
        }
        .padding(.horizontal, 11).padding(.top, 10).padding(.bottom, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
    }

    /// Estimates a card's height at a column width, for balancing masonry columns. SwiftUI measures the real height.
    static func height(of post: PostView, width: CGFloat) -> CGFloat {
        let inner = max(1, width - 22)
        func lines(_ text: String, perCharacter: CGFloat, width: CGFloat, max limit: CGFloat) -> CGFloat {
            min(limit, ceil(CGFloat(text.count) * perCharacter / max(1, width)))
        }
        // Padding, byline and the 12-point gap to the next card.
        var height: CGFloat = 10 + 17 + 11 + 12
        height += lines(post.content.text, perCharacter: 7, width: inner, max: 5) * 17
        height += mediaHeight(post.content.media, width: inner, strip: false).map { $0 + 8 } ?? 0
        if let quote = post.quoted {
            height += 5 + 16 + 15 + lines(quote.text, perCharacter: 6.5, width: inner - 20, max: 3) * 15
            height += mediaHeight(quote.media, width: inner, strip: true) ?? 0
        }
        return height
    }
    private static func mediaHeight(_ media: [MediaView], width: CGFloat, strip: Bool) -> CGFloat? {
        let shown = media.filter { $0.file != nil }
        guard let first = shown.first else { return nil }
        if shown.count > 1 { return width * 9 / 16 }
        return width * (strip ? min(first.heightRatio, 9 / 16) : first.heightRatio)
    }
}

/// The name in bold, then the handle and date in secondary, after a small avatar, on one line.
struct Byline: View {
    let post: PostContent
    let mediaDir: URL?
    let avatar: CGFloat
    var body: some View {
        // As on X, the handle gives way first, then the name; the date always shows.
        HStack(spacing: 4) {
            Avatar(authorID: post.authorID, mediaDir: mediaDir, size: avatar).padding(.trailing, 2)
            Text(post.name).bold().layoutPriority(1)
            Text("@\(post.handle)").foregroundStyle(.secondary)
            if let date = post.createdAt { Text("· \(date.postStamp)").foregroundStyle(.secondary).fixedSize() }
        }
        .lineLimit(1)
    }
}

/// A card's media: one item at its own shape, or 2–4 as X's mosaic. A strip caps a single item at 16:9.
struct CardMedia: View {
    let items: [MediaView]
    var strip = false
    var body: some View {
        if items.count > 1 {
            Color.clear.aspectRatio(16 / 9, contentMode: .fit).overlay { mosaic }
        } else if let item = items.first {
            tile(item, autoplay: true)
                .aspectRatio(strip ? max(16 / 9, 1 / item.heightRatio) : 1 / item.heightRatio, contentMode: .fit)
        }
    }
    /// Side by side, one large plus two stacked, or a 2×2 grid.
    @ViewBuilder private var mosaic: some View {
        let t = items.prefix(4).map { tile($0, autoplay: false) }
        switch t.count {
        case 2: HStack(spacing: 2) { t[0]; t[1] }
        case 3: HStack(spacing: 2) { t[0]; VStack(spacing: 2) { t[1]; t[2] } }
        default: VStack(spacing: 2) { HStack(spacing: 2) { t[0]; t[1] }; HStack(spacing: 2) { t[2]; t[3] } }
        }
    }
    /// Photos as thumbnails; videos as their poster with a play glyph. A lone GIF plays muted and looped.
    private func tile(_ item: MediaView, autoplay: Bool) -> some View {
        Group {
            if item.type == .animatedGIF, autoplay, let url = item.file {
                MediaPlayer(url: url, looping: true).id(url).allowsHitTesting(false)
            } else {
                Thumbnail(url: item.type == .photo ? item.file : item.poster)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .overlay {
            if item.type == .video {
                Image(systemName: "play.fill").foregroundStyle(.white)
                    .frame(width: 36, height: 36).background(.black.opacity(0.5), in: Circle())
            }
        }
    }
}

extension Date {
    /// Like X: "20h" within a day, "Nov 17" this year, "Nov 17, 2024" before.
    var postStamp: String {
        let seconds = max(0, Date.now.timeIntervalSince(self))
        if seconds < 60 { return "\(Int(seconds))s" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h" }
        let sameYear = Calendar.current.isDate(self, equalTo: .now, toGranularity: .year)
        return formatted(Date.VerbatimFormatStyle(
            format: sameYear ? "\(month: .abbreviated) \(day: .defaultDigits)" : "\(month: .abbreviated) \(day: .defaultDigits), \(year: .defaultDigits)",
            locale: .current, timeZone: .current, calendar: .current))
    }
}
