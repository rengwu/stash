import SwiftUI
import XSavesCore

/// One post in a sheet, laid out like a post on X: the avatar in its own column, then the byline, text, media and quoted post.
struct PostGalleryView: View {
    let model: AppModel
    let post: PostView
    /// The tallest the sheet may be: it grows with the window.
    let maxHeight: CGFloat
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @ViewState private var naming = false
    @ViewState private var contentHeight: CGFloat = 0
    @ViewState private var controlsWidth: CGFloat = 0
    @ViewState private var monitor: Any?

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 12) {
                avatar(post.content, size: 40)
                VStack(alignment: .leading, spacing: 12) {
                    // Keep the byline clear of the controls that float over the top trailing corner.
                    byline(post.content).font(.title3).padding(.trailing, controlsWidth)
                    content(post.content, font: .title3)
                    if let quote = post.quoted {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                avatar(quote, size: 20)
                                byline(quote)
                            }
                            content(quote, font: .body)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay { RoundedRectangle(cornerRadius: 16).stroke(.separator) }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        // As tall as the post, up to the room the window leaves.
        .frame(height: min(contentHeight, maxHeight))
        .id(post.id)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) {
                boardsMenu
                if let url = URL(string: "https://x.com/\(post.content.handle)/status/\(post.id)") {
                    circleButton("Open on X", systemImage: "arrow.up.forward") { openURL(url) }
                }
                circleButton("Close", systemImage: "xmark") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { controlsWidth = $0 }
            .padding(12)
        }
        // A fixed width keeps text wrapping, and so the measured height, the same in every layout pass.
        .frame(width: 640)
        .presentationSizing(.fitted)
        .onAppear {
            // The sheet blocks clicks on the window behind it. A click on that window's content closes the post instead;
            // the toolbar is left alone so the window can still be dragged.
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
                guard let window = event.window, window.sheetParent == nil, window.attachedSheet != nil,
                      event.locationInWindow.y < window.contentLayoutRect.maxY else { return event }
                MainActor.assumeIsolated { dismiss() }
                return nil
            }
        }
        .onDisappear { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
    /// Files the post: one checkmark item per board, and a new board that starts with this post.
    private var boardsMenu: some View {
        Menu {
            ForEach(model.boards) { board in
                Toggle(board.name, isOn: Binding(get: { post.boards.contains(board.id) }, set: { on in
                    Task { await model.setBoard(board.id, post: post.id, on: on) }
                }))
            }
            if !model.boards.isEmpty { Divider() }
            Button("New Board…") { naming = true }
        } label: {
            Label("Boards", systemImage: "rectangle.stack")
        }
        .buttonStyle(.glass)
        .fixedSize()
        .help("Add to a board")
        // A popover, not an alert: an alert's text field is an accessory that AppKit insets apart from the title and buttons.
        .popover(isPresented: $naming, arrowEdge: .bottom) {
            NewBoardField { name in Task { await model.createBoard(name, adding: post.id) } }
        }
    }
    private func circleButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: systemImage).frame(width: 16, height: 16) }
            .buttonStyle(.glass).buttonBorderShape(.circle)
            .help(title).accessibilityLabel(title)
    }
    /// The name in bold, then the handle and date in secondary, on one line.
    private func byline(_ post: PostContent) -> some View {
        let date = post.createdAt.map { " · " + $0.postStamp } ?? ""
        return Text("\(Text(post.name).bold()) \(Text("@\(post.handle)\(date)").foregroundStyle(.secondary))").lineLimit(1)
    }
    @ViewBuilder private func content(_ post: PostContent, font: Font) -> some View {
        if !post.text.isEmpty {
            Text(Self.linked(post.text)).font(font).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
        // Leave room beside the media for the byline and the start of the text.
        Gallery(items: post.media.filter { $0.file != nil }, maxHeight: max(240, maxHeight - 160))
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
        Avatar(authorID: post.authorID, mediaDir: model.store?.mediaDir, size: size)
    }
}

/// Names a new board in one row, focused on open. Return creates it; Esc or a click elsewhere cancels.
private struct NewBoardField: View {
    let create: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @ViewState private var name = ""
    @FocusState private var focused: Bool
    var body: some View {
        HStack {
            TextField("New board name", text: $name).focused($focused).frame(width: 200)
            Button("Create") {
                create(name)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(12)
        .onAppear { focused = true }
    }
}
