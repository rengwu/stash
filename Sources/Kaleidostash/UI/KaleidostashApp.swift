import SwiftUI

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct KaleidostashApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let model = AppModel()
    var body: some Scene {
        Window("Kaleidostash", id: "main") { ContentView(model: model) }
            .defaultSize(width: 1200, height: 860)
            .commands {
                CommandGroup(replacing: .newItem) {
                    Button("Sync") { model.startSync() }.keyboardShortcut("r").disabled(model.sync != nil)
                    Button("New Board") { model.newBoardName = "" }.keyboardShortcut("n", modifiers: [.command, .shift])
                }
                SidebarCommands()
            }
        Settings { SettingsView(model: model) }
    }
}
