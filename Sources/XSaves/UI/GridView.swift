import SwiftUI
import XSavesCore

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
                                CardView(post: post)
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
        .onExitCommand { model.selection = nil }
    }
}

struct CardView: View {
    let post: PostView
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let media = post.content.media.filter { $0.file != nil }
            if let first = media.first {
                Group {
                    if first.type == .animatedGIF, let url = first.file {
                        MediaPlayer(url: url, looping: true).id(url).allowsHitTesting(false)
                    } else { Thumbnail(url: first.type == .photo ? first.file : first.poster) }
                }
                    .aspectRatio(1 / first.heightRatio, contentMode: .fit)
                    .overlay {
                        if first.type == .video {
                            Image(systemName: "play.fill").foregroundStyle(.white)
                                .frame(width: 40, height: 40).background(.black.opacity(0.5), in: Circle())
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if media.count > 1 {
                            Label("\(media.count)", systemImage: "square.on.square").font(.caption.weight(.medium))
                                .padding(5).foregroundStyle(.white).background(.black.opacity(0.5), in: Capsule()).padding(7)
                        }
                    }
            }
            VStack(alignment: .leading, spacing: 6) {
                if !post.content.text.isEmpty { Text(post.content.text).lineLimit(5) }
                if let quote = post.quoted {
                    VStack(alignment: .leading) {
                        HStack { Text(quote.name).bold(); Text("@\(quote.handle)").foregroundStyle(.secondary) }.lineLimit(1)
                        Text(quote.text).lineLimit(3)
                    }
                    .font(.subheadline).frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    .overlay { RoundedRectangle(cornerRadius: 9).stroke(.separator) }
                }
                Text("\(post.content.name) @\(post.content.handle)").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }.padding(.horizontal, 11).padding(.top, 9).padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12)).contentShape(Rectangle())
    }
}
