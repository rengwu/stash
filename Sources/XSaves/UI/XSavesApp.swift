import SwiftUI

struct XSavesApp: App {
    var body: some Scene {
        Window("xsaves", id: "main") { Counter() }
            .defaultSize(width: 1040, height: 660)
    }
}

private struct Counter: View {
    @ViewState private var count = 0
    var body: some View {
        Button("Count \(count)") { count += 1 }
    }
}
