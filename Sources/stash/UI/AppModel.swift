import SwiftUI
import StashCore

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
    var errorTitle = "stash"
    var scheduleError: String?
    var scheduleOn = false
    var scheduling = false
    var sync: SyncProgress?
    var ready = false
    private var searchTask: Task<Void, Never>?

    var newBoardName: String?
    var deleting: Board?
    var columns: [[Int]] = [[]]
    /// Changes when the grid shows a different list, so the grid starts again at the top.
    var generation = 0
    private var heights: [CGFloat] = [0]
    private var width: CGFloat = 260
    private var version = 0
    /// Rows read from the store for the current list. A sync can shift rows between pages, so this can exceed `posts.count`.
    private var fetched = 0
    /// The open post left the shown board; the list reloads when the gallery closes.
    private var staleList = false
    private static let pageSize = 60

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
            // Repoint only an agent whose program is gone, such as a moved app. A dev build never takes over a working agent.
            if Bundle.main.bundleURL.pathExtension == "app", Paths.dataDirOverride == nil,
               scheduleOn, !FileManager.default.isExecutableFile(atPath: schedule.programPath ?? "") {
                do { try await Task.detached { try schedule.set(on: true) }.value }
                catch { errorTitle = "Couldn't Change the Schedule"; self.error = error.localizedDescription }
                scheduleOn = schedule.isOn
            }
            await DebugHooks.apply(self)
            ready = true
        }
        catch { self.error = error.localizedDescription }
    }
    /// Loads the list from the top. `keepingPlace` reloads as many posts as are loaded, so the grid and an open post stay put.
    func reload(keepingPlace: Bool = false) async {
        guard let store else { return }
        version += 1
        let token = version, filter = query, limit = keepingPlace ? max(Self.pageSize, fetched) : Self.pageSize
        loading = true
        defer { if version == token { loading = false } }
        do {
            let page = try await store.posts(filter, offset: 0, limit: limit)
            let total = try await store.count(filter)
            let counts = try await store.counts(), boards = try await store.boards()
            guard version == token, filter == query, !Task.isCancelled else { return }
            self.counts = counts
            self.boards = boards
            listCount = total
            if !keepingPlace { generation += 1 }
            posts = page
            fetched = page.count
            staleList = false
            rebuild()
            if selected == nil { selection = nil }
            reachedEnd = page.count < limit
        } catch { self.error = error.localizedDescription }
    }
    func more(after index: Int) async {
        guard let store, !loading, !reachedEnd, index >= posts.count - 20 else { return }
        loading = true
        let token = version, offset = fetched, filter = query
        defer { if version == token { loading = false } }
        do {
            let page = try await store.posts(filter, offset: offset, limit: Self.pageSize)
            guard version == token, query == filter else { return }
            // A sync since the last page moves older posts down, so the new page can repeat posts already shown.
            let shown = Set(posts.map(\.id)), start = posts.count
            posts.append(contentsOf: page.filter { !shown.contains($0.id) })
            fetched += page.count
            place(start..<posts.count)
            reachedEnd = page.count < Self.pageSize
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
            let column = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            heights[column] += CardView.height(of: posts[i], width: width)
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
            if let i = posts.firstIndex(where: { $0.id == id }) {
                if on { posts[i].boards.insert(board) } else { posts[i].boards.remove(board) }
            }
            // Removing the open post from the shown board would close its gallery, so the list waits until it closes.
            if sidebar == .board(board) && !on { staleList = true }
            boards = try await store.boards()
        } catch { self.error = error.localizedDescription }
    }
    func galleryClosed() async {
        if staleList { await reload(keepingPlace: true) }
    }
    /// Creates a board, or finds the one with that name, and optionally adds a post to it.
    func createBoard(_ name: String, adding post: String? = nil) async {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let store else { return }
        do {
            let board = try await store.createBoard(name)
            boards = try await store.boards()
            if let post { await setBoard(board, post: post, on: true) }
        } catch { self.error = error.localizedDescription }
    }
    func finishBoard() {
        guard let name = newBoardName else { return }
        newBoardName = nil
        Task { await createBoard(name) }
    }
    func deleteBoard(_ board: Board) async {
        guard let store else { return }
        do {
            try await store.deleteBoard(board.id)
            if sidebar == .board(board.id) { sidebar = .all }
            await reload(keepingPlace: true)
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
            await reload(keepingPlace: true)
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
