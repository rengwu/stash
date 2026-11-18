import SwiftUI

struct SidebarView: View {
    @Bindable var model: AppModel
    var body: some View {
        List(selection: $model.sidebar) {
            Section("Library") {
                Label("All Saves", systemImage: "tray.full").badge(model.counts.all).tag(SidebarItem.all)
                Label("Bookmarks", systemImage: "bookmark").badge(model.counts.bookmarks).tag(SidebarItem.bookmarks)
                Label("Likes", systemImage: "heart").badge(model.counts.likes).tag(SidebarItem.likes)
            }
            Section("Boards") {
                ForEach(model.boards) { board in
                    Label(board.name, systemImage: "rectangle.stack").badge(board.count).tag(SidebarItem.board(board.id))
                }
            }
        }.listStyle(.sidebar)
    }
}
