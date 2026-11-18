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
