import AppKit
import WebKit

@MainActor final class SyncWindow: NSWindow {
    let web: WKWebView
    init(configuration: WKWebViewConfiguration) {
        web = WKWebView(frame: .zero, configuration: configuration)
        super.init(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 900),
                   styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        title = "Sign in to X"
        isReleasedWhenClosed = false
        contentView = web
    }
    /// Key equivalents reach a web view through the menu bar: without an Edit menu, ⌘V, ⌘C and ⌘A do nothing in the sign-in page.
    static func editMenu() -> NSMenu {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let bar = NSMenu(), app = NSMenuItem(), editItem = NSMenuItem()
        app.submenu = NSMenu()
        editItem.submenu = edit
        bar.addItem(app)
        bar.addItem(editItem)
        return bar
    }
    func showLogin(_ visible: Bool) {
        NSApp.setActivationPolicy(visible ? .regular : .accessory)
        alphaValue = visible ? 1 : 0
        ignoresMouseEvents = !visible
        level = visible ? .normal : .floating
        collectionBehavior = visible ? [] : [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        if visible {
            center()
            makeKeyAndOrderFront(nil)
            NSApp.activate()
        } else { orderFrontRegardless() }
    }
}
