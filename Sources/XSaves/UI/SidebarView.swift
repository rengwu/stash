import SwiftUI

struct SidebarView: View {
    @Bindable var model: AppModel
    @FocusState private var editing: Bool
    var body: some View {
        List(selection: $model.sidebar) {
            Section("Library") {
                Label("All Saves", systemImage: "tray.full").badge(model.counts.all).tag(SidebarItem.all)
                Label("Bookmarks", systemImage: "bookmark").badge(model.counts.bookmarks).tag(SidebarItem.bookmarks)
                Label("Likes", systemImage: "heart").badge(model.counts.likes).tag(SidebarItem.likes)
            }
            Section {
                ForEach(model.boards) { board in
                    Label(board.name, systemImage: "rectangle.stack").badge(board.count).tag(SidebarItem.board(board.id))
                        .contextMenu { Button("Delete Board…", role: .destructive) { model.deleting = board } }
                }
                if model.newBoardName != nil {
                    TextField("Board name", text: Binding(get: { model.newBoardName ?? "" }, set: { model.newBoardName = $0 }))
                        .focused($editing).onAppear { editing = true }
                        .onSubmit { model.finishBoard() }
                        .onExitCommand { model.newBoardName = nil }
                        .onChange(of: editing) { if !editing { model.finishBoard() } }
                }
            } header: {
                HStack {
                    Text("Boards")
                    Spacer()
                    Button("New Board", systemImage: "plus") { model.newBoardName = "" }
                        .labelStyle(.iconOnly).buttonStyle(.borderless).help("New Board")
                }
            }
        }.listStyle(.sidebar)
        .confirmationDialog("Delete the board “\(model.deleting?.name ?? "")”?", isPresented: Binding(
            get: { model.deleting != nil }, set: { if !$0 { model.deleting = nil } }
        ), titleVisibility: .visible, presenting: model.deleting) { board in
            Button("Delete", role: .destructive) { Task { await model.deleteBoard(board) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in Text("Its posts stay saved.") }
    }
}
