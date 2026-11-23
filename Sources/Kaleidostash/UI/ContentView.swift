import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel
    @ViewState private var height: CGFloat = 860
    var body: some View {
        NavigationSplitView {
            SidebarView(model: model).navigationSplitViewColumnWidth(min: 180, ideal: 212, max: 280)
        } detail: {
            Group {
                if model.posts.isEmpty { empty } else { GridView(model: model).id(model.generation) }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if let p = model.sync {
                        let total = p.bookmarks + p.likes
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(total == 0 ? "Syncing" : "\(total) new").monospacedDigit()
                        }
                        .padding(.horizontal, 8)
                        .fixedSize()
                        .help("Syncing: \(total) new posts, \(p.media) files left to download")
                    } else {
                        Button("Sync", systemImage: "arrow.clockwise") { model.startSync() }.help("Sync")
                    }
                }
            }
            .navigationTitle(model.title)
            .navigationSubtitle(model.listCount == 0 ? "" : "\(model.listCount) \(model.listCount == 1 ? "save" : "saves")")
            .searchable(text: $model.search, placement: .toolbar, prompt: "Search")
        }
        .frame(minWidth: 760, minHeight: 480)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .sheet(isPresented: Binding(get: { model.selection != nil }, set: { if !$0 { model.selection = nil } }),
               onDismiss: { Task { await model.galleryClosed() } }) {
            // The sheet hangs below the toolbar; leave a margin under it.
            if let post = model.selected { PostGalleryView(model: model, post: post, maxHeight: max(300, height - 100)) }
        }
        .task { await model.open() }
        .onChange(of: model.sidebar) { if model.ready { Task { await model.reload() } } }
        .onChange(of: model.search) { model.searchChanged() }
        .alert(model.errorTitle, isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil; model.errorTitle = "Kaleidostash" }
        } message: { Text(model.error ?? "") }
    }
    @ViewBuilder var empty: some View {
        if !model.search.isEmpty { ContentUnavailableView.search(text: model.search) }
        else if model.counts.all == 0 {
            ContentUnavailableView {
                Label("No Saves Yet", systemImage: "bookmark")
            } description: {
                Text("Sync signs you in to X and fetches your bookmarks and likes.")
            } actions: {
                Button("Sync") { model.startSync() }.disabled(model.sync != nil)
            }
        } else {
            switch model.sidebar {
            case .bookmarks: ContentUnavailableView("No Bookmarks", systemImage: "bookmark", description: Text("Sync fetches the posts you bookmark on X."))
            case .likes: ContentUnavailableView("No Likes", systemImage: "heart", description: Text("Sync fetches the posts you like on X."))
            case .board: ContentUnavailableView("No Posts in \(model.title)", systemImage: "rectangle.stack", description: Text("Open a post and choose “\(model.title)” from its Boards menu."))
            case .all: EmptyView()
            }
        }
    }
}
