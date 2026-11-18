import SwiftUI
import XSavesCore

enum SidebarItem: Hashable {
    case all, bookmarks, likes, board(Int64)
}

@MainActor @Observable final class AppModel {
    var store: Store?
    var sidebar = SidebarItem.all
    var search = ""
    var posts: [PostView] = []
    var selection: String?
    var selected: PostView? { posts.first { $0.id == selection } }
    var boards: [Board] = []
    var counts = Counts.empty
    var listCount = 0
    var loading = false
    var reachedEnd = false
    var error: String?
    var errorTitle = "xsaves"
    var scheduleError: String?
    var scheduleOn = false
    var scheduling = false
    var sync: SyncProgress?
    var ready = false
    private var searchTask: Task<Void, Never>?

    var newBoardName: String?
    var deleting: Board?
    var columns: [[Int]] = [[]]
    private var heights: [CGFloat] = [0]
    private var width: CGFloat = 260
    private var version = 0

    var title: String {
        switch sidebar {
        case .all: "All Saves"
        case .bookmarks: "Bookmarks"
        case .likes: "Likes"
        case .board(let id): boards.first { $0.id == id }?.name ?? "Board"
        }
    }
    private var query: PostQuery {
        switch sidebar {
        case .all: .init(text: search)
        case .bookmarks: .init(kind: .bookmark, text: search)
        case .likes: .init(kind: .like, text: search)
        case .board(let id): .init(board: id, text: search)
        }
    }
    func open() async {
        guard store == nil else { return }
        do {
            store = try Store(dataDir: Paths.dataDir)
            await reload()
            let schedule = Schedule()
            scheduleOn = schedule.isOn
            if Bundle.main.bundleURL.pathExtension == "app", ProcessInfo.processInfo.environment["XSAVES_DIR"] == nil,
               scheduleOn, schedule.programPath != Bundle.main.executableURL?.path {
                do { try await Task.detached { try schedule.set(on: true) }.value }
                catch { errorTitle = "Couldn't Change the Schedule"; self.error = error.localizedDescription }
                scheduleOn = schedule.isOn
            }
            await DebugHooks.apply(self)
            ready = true
        }
        catch { self.error = error.localizedDescription }
    }
    func reload() async {
        guard let store else { return }
        version += 1
        let token = version, filter = query
        loading = true
        defer { if version == token { loading = false } }
        do {
            let page = try await store.posts(filter, offset: 0)
            let total = try await store.count(filter)
            let counts = try await store.counts(), boards = try await store.boards()
            guard version == token, filter == query, !Task.isCancelled else { return }
            self.counts = counts
            self.boards = boards
            listCount = total
            posts = page
            rebuild()
            if selected == nil { selection = nil }
            reachedEnd = posts.count >= total
        } catch { self.error = error.localizedDescription }
    }
    func more(after index: Int) async {
        guard let store, !loading, !reachedEnd, index >= posts.count - 20 else { return }
        loading = true
        let token = version, offset = posts.count, filter = query
        defer { if version == token { loading = false } }
        do {
            let page = try await store.posts(filter, offset: offset)
            guard version == token, query == filter else { return }
            posts.append(contentsOf: page)
            place(offset..<posts.count)
            reachedEnd = posts.count >= listCount || page.isEmpty
        } catch { self.error = error.localizedDescription }
    }
    func resize(_ available: CGFloat) {
        let count = max(1, Int((available - 20) / 272))
        width = max(1, (available - 32 - CGFloat(count - 1) * 12) / CGFloat(count))
        if count != columns.count { columns = Array(repeating: [], count: count); rebuild() }
    }
    private func rebuild() {
        columns = Array(repeating: [], count: columns.count)
        heights = Array(repeating: 0, count: columns.count)
        place(posts.indices)
    }
    private func place(_ indices: Range<Int>) {
        for i in indices {
            let post = posts[i], content = post.content
            let column = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            let image = content.media.first { $0.file != nil }
            let lines = min(5, ceil(CGFloat(content.text.count) * 7 / max(1, width - 22)))
            let quote: CGFloat = post.quoted.map { quoted in
                let lines = ceil(CGFloat(quoted.text.count) * 6.5 / max(1, width - 42))
                return 20 + min(3, lines) * 15
            } ?? 0
            heights[column] += 52 + lines * 17 + quote + (image?.heightRatio ?? 0) * width
            columns[column].append(i)
        }
    }
    func select(_ id: String) { selection = id }
}

extension MediaView {
    var heightRatio: CGFloat {
        guard width > 0, height > 0 else { return 1 }
        return min(1.6, max(0.4, CGFloat(height) / CGFloat(width)))
    }
}

extension AppModel {
    func setBoard(_ board: Int64, post id: String, on: Bool) async {
        guard let store else { return }
        do {
            try await store.setPost(id, inBoard: board, on)
            if sidebar == .board(board) && !on { await reload(); return }
            if let i = posts.firstIndex(where: { $0.id == id }) {
                if on { posts[i].boards.insert(board) } else { posts[i].boards.remove(board) }
            }
            boards = try await store.boards()
        } catch { self.error = error.localizedDescription }
    }
    func finishBoard() {
        guard let name = newBoardName?.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        newBoardName = nil
        guard !name.isEmpty, let store else { return }
        Task {
            do { try await store.createBoard(name); boards = try await store.boards() }
            catch { self.error = error.localizedDescription }
        }
    }
    func deleteBoard(_ board: Board) async {
        guard let store else { return }
        do {
            try await store.deleteBoard(board.id)
            if sidebar == .board(board.id) { sidebar = .all }
            await reload()
        } catch { self.error = error.localizedDescription }
    }
}

extension AppModel {
    func searchChanged() {
        guard ready else { return }
        searchTask?.cancel()
        searchTask = Task {
            do { try await Task.sleep(for: .milliseconds(200)); await reload() } catch {}
        }
    }
    func startSync() {
        guard sync == nil, let executable = Bundle.main.executableURL else { return }
        sync = SyncProgress()
        Task {
            do { try await SyncController.run(executable: executable) { self.sync = $0 } }
            catch { errorTitle = "Sync Stopped"; self.error = error.localizedDescription }
            sync = nil
            await reload()
        }
    }
    func setSchedule(_ on: Bool) {
        guard !scheduling else { return }
        scheduling = true
        scheduleOn = on
        Task {
            let schedule = Schedule()
            do { try await Task.detached { try schedule.set(on: on) }.value }
            catch { scheduleError = error.localizedDescription }
            scheduleOn = schedule.isOn
            scheduling = false
        }
    }
}
