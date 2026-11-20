import AppKit
import StashCore

@MainActor enum DebugHooks {
    private struct Options: Decodable {
        var sidebar: String?, search: String?, select: String?, inspector: Bool?
    }
    static func apply(_ model: AppModel) async {
        let env = ProcessInfo.processInfo.environment
        if let input = env["STASH_UI"] ?? env["MOSAIC_UI"] ?? env["XSAVES_UI"], let options = try? JSONDecoder().decode(Options.self, from: Data(input.utf8)) {
            switch options.sidebar {
            case "bookmarks": model.sidebar = .bookmarks
            case "likes": model.sidebar = .likes
            case let name? where name.hasPrefix("board:"):
                if let board = model.boards.first(where: { $0.name == name.dropFirst(6) }) { model.sidebar = .board(board.id) }
            default: model.sidebar = .all
            }
            model.search = options.search ?? ""
            await model.reload()
            if let id = options.select {
                while !model.reachedEnd && !model.posts.contains(where: { $0.id == id }) {
                    let before = model.posts.count
                    await model.more(after: before)
                    if model.posts.count == before { break }
                }
                if model.posts.contains(where: { $0.id == id }) { model.select(id) }
            }
            if options.inspector == false { model.selection = nil }
        }
        if let path = env["STASH_SNAPSHOT"] ?? env["MOSAIC_SNAPSHOT"] ?? env["XSAVES_SNAPSHOT"] {
            try? await Task.sleep(for: .seconds(2))
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
                  let view = window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
            else { log("Could not capture the window."); NSApp.terminate(nil); return }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            do { try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path)) }
            catch { log(error.localizedDescription) }
            NSApp.terminate(nil)
        }
    }
}
