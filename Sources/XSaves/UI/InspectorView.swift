import SwiftUI
import XSavesCore

struct InspectorView: View {
    let model: AppModel
    var body: some View {
        if let post = model.selected {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        avatar(post.content, size: 36)
                        VStack(alignment: .leading) {
                            Text(post.content.name).font(.headline)
                            let date = post.content.createdAt.map { " · " + $0.formatted(.dateTime.month(.abbreviated).day().year()) } ?? ""
                            Text("@\(post.content.handle)\(date)").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
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
        } else { ContentUnavailableView("No Post Selected", systemImage: "sidebar.trailing") }
    }
    @ViewBuilder private func content(_ post: PostContent) -> some View {
        if !post.text.isEmpty {
            Text(Self.linked(post.text)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
        Gallery(items: post.media.filter { $0.file != nil })
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
