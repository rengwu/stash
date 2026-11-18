import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel
    var body: some View {
        NavigationSplitView {
            SidebarView(model: model).navigationSplitViewColumnWidth(min: 180, ideal: 212, max: 280)
        } detail: {
            Group {
                if model.posts.isEmpty { empty } else { GridView(model: model) }
            }
            .inspector(isPresented: $model.inspectorShown) {
                InspectorView(model: model).inspectorColumnWidth(min: 260, ideal: 300, max: 420)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if let p = model.sync {
                        let total = p.bookmarks + p.likes
                        HStack {
                            ProgressView().controlSize(.small)
                            Text(total == 0 ? "Syncing" : "\(total) new").monospacedDigit()
                        }.help("Syncing: \(total) new posts, \(p.media) files left to download")
                    } else {
                        Button("Sync", systemImage: "arrow.clockwise") { model.startSync() }.help("Sync")
                    }
                }
                ToolbarItemGroup {
                    if model.inspectorShown, let post = model.selected {
                        Button("Open on X", systemImage: "arrow.up.forward.square") {
                            if let url = URL(string: "https://x.com/\(post.content.handle)/status/\(post.id)") { NSWorkspace.shared.open(url) }
                        }
                    }
                    Button("Inspector", systemImage: "sidebar.trailing") { model.inspectorShown.toggle() }
                }
            }
            .navigationTitle(model.title)
            .navigationSubtitle(model.listCount == 0 ? "" : "\(model.listCount) \(model.listCount == 1 ? "save" : "saves")")
            .searchable(text: $model.search, placement: .toolbar, prompt: "Search")
        }
        .frame(minWidth: 760, minHeight: 480)
        .task { await model.open() }
        .onChange(of: model.sidebar) { if model.ready { Task { await model.reload() } } }
        .onChange(of: model.search) { model.searchChanged() }
        .alert(model.errorTitle, isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil; model.errorTitle = "xsaves" }
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
            case .board: ContentUnavailableView("No Posts in \(model.title)", systemImage: "rectangle.stack", description: Text("Select a post and tick \(model.title) in the inspector."))
            case .all: EmptyView()
            }
        }
    }
}
