import SwiftUI
import XSavesCore

struct PostGalleryView: View {
    let model: AppModel
    let post: PostView
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                avatar(post.content, size: 36)
                VStack(alignment: .leading) {
                    Text(post.content.name).font(.headline)
                    let date = post.content.createdAt.map { " · " + $0.formatted(.dateTime.month(.abbreviated).day().year()) } ?? ""
                    Text("@\(post.content.handle)\(date)").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if let url = URL(string: "https://x.com/\(post.content.handle)/status/\(post.id)") {
                    Link(destination: url) { Label("Open on X", systemImage: "arrow.up.forward.square") }
                        .labelStyle(.iconOnly).help("Open on X")
                }
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    content(post.content)
                    if let quote = post.quoted {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                avatar(quote, size: 20)
                                Text(quote.name).bold()
                                Text("@\(quote.handle)").foregroundStyle(.secondary)
                            }.lineLimit(1)
                            content(quote)
                        }.padding(.vertical, 10).padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay { RoundedRectangle(cornerRadius: 10).stroke(.separator) }
                    }
                    if !model.boards.isEmpty {
                        Text("Boards").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 6)
                        ForEach(model.boards) { board in
                            Toggle(board.name, isOn: Binding(get: { post.boards.contains(board.id) }, set: { on in
                                Task { await model.setBoard(board.id, post: post.id, on: on) }
                            })).toggleStyle(.checkbox)
                        }
                    }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }.id(post.id)
        }
        .frame(minWidth: 440, idealWidth: 640, minHeight: 180,
               idealHeight: post.content.media.isEmpty && post.quoted == nil ? 300 : 560)
        .presentationSizing(.fitted)
    }
    @ViewBuilder private func content(_ post: PostContent) -> some View {
        Gallery(items: post.media.filter { $0.file != nil })
        if !post.text.isEmpty {
            Text(Self.linked(post.text)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private static func linked(_ text: String) -> AttributedString {
        var result = AttributedString(), start = text.startIndex
        for match in text.matches(of: /https:\/\/\S+/) {
            result += AttributedString(text[start..<match.range.lowerBound])
            var link = AttributedString(match.output)
            link.link = URL(string: String(match.output))
            result += link
            start = match.range.upperBound
        }
        result += AttributedString(text[start...])
        return result
    }
    private func avatar(_ post: PostContent, size: CGFloat) -> some View {
        ZStack {
            Circle().fill(.fill.tertiary)
            Image(systemName: "person.fill").foregroundStyle(.secondary)
            if let root = model.store?.mediaDir {
                Thumbnail(url: root.appending(path: Paths.avatarFile(post.authorID)))
            }
        }.frame(width: size, height: size).clipShape(Circle())
    }
}
