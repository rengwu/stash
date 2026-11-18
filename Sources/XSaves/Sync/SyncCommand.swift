import AppKit
import WebKit
import XSavesCore

func log(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

@MainActor final class SyncCommand: NSObject, WKScriptMessageHandler, WKScriptMessageHandlerWithReply, NSWindowDelegate, WKNavigationDelegate {
    private struct Capture: Sendable {
        let kind: Kind, status: Int, data: Data
    }
    private let store: Store, downloader: Downloader
    private var machine: SyncMachine
    private var progress = SyncProgress()
    private let captures = AsyncStream<Capture>.makeStream()
    private var window: SyncWindow!
    private var mediaTask: Task<Void, Never>?
    private var finishing = false

    static func run(login: Bool) throws {
        guard Bundle.main.bundleURL.pathExtension == "app" else { throw ArchiveError("Run sync from the xsaves app bundle.") }
        let dir = Paths.dataDir
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fd = open(dir.appending(path: "sync.lock").path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw ArchiveError("A sync is already running.") }
        let command = SyncCommand(store: try Store(dataDir: dir), login: login)
        let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Syncing X saves")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        command.start()
        NSApp.run()
    }
    private init(store: Store, login: Bool) {
        self.store = store
        downloader = Downloader(store: store)
        machine = SyncMachine(login: login)
    }
    private func start() {
        let config = WKWebViewConfiguration()
        config.preferences.inactiveSchedulingPolicy = .none
        let bridge = config.userContentController
        bridge.add(self, contentWorld: .page, name: "xsCapture")
        bridge.addScriptMessageHandler(self, contentWorld: .page, name: "xsTick")
        bridge.addUserScript(WKUserScript(source: InjectScript.source, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .page))
        window = SyncWindow(configuration: config)
        window.delegate = self
        window.web.navigationDelegate = self
        window.showLogin(false)
        window.web.load(URLRequest(url: URL(string: "https://x.com/i/bookmarks")!))
        Task {
            do {
                for await capture in captures.stream {
                    guard capture.status == 200 else { throw ArchiveError("X refused the request (status \(capture.status)). Try again later.") }
                    let page = try await Task.detached { try Parse.parse(capture.data) }.value
                    let kind = capture.kind
                    let added = try await store.addPage(kind, posts: page.posts, saves: page.saves)
                    let key = "complete:" + kind.rawValue
                    let complete = try await store.meta(key) == "1"
                    log("\(kind.rawValue) page: \(page.saves.count) saves, \(added) new")
                    if kind == .bookmark { progress.bookmarks += added } else { progress.likes += added }
                    progress.write()
                    if machine.captured(kind, saves: page.saves.count, added: added, complete: complete) {
                        try await store.setMeta(key, "1")
                    }
                }
            } catch { finish(error.localizedDescription) }
        }
        mediaTask = Task {
            while !finishing {
                do {
                    try await download()
                    if !finishing { try await Task.sleep(for: .seconds(3)) }
                } catch { if !Task.isCancelled { finish(error.localizedDescription) }; return }
            }
        }
    }
    private func download() async throws {
        try await downloader.runOnce { left in
            await MainActor.run {
                if self.progress.media != left { self.progress.media = left; self.progress.write() }
            }
        }
    }
    private func finish(_ error: String? = nil) {
        guard !finishing else { return }
        finishing = true
        if let error { progress.error = error; progress.write() }
        window.web.stopLoading()
        captures.continuation.finish()
        // Let in-flight downloads finish before taking the last snapshot of pending jobs.
        Task {
            await mediaTask?.value
            do { try await download() }
            catch { if progress.error == nil { progress.error = error.localizedDescription; progress.write() } }
            window.delegate = nil
            window.close()
            if let message = progress.error { log(message); exit(1) }
            exit(0)
        }
    }
    func windowWillClose(_ notification: Notification) { finish("Sync cancelled: the sign-in window was closed.") }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { finish(error.localizedDescription) }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { finish("X stopped loading. Try again later.") }

    private func body(_ message: WKScriptMessage) -> [String: Any]? {
        let origin = message.frameInfo.securityOrigin
        guard !finishing, message.frameInfo.isMainFrame, origin.protocol == "https", origin.host == "x.com" else { return nil }
        return message.body as? [String: Any]
    }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let fields = body(message), let op = fields["op"] as? String, ["Bookmarks", "Likes"].contains(op),
              let status = fields["status"] as? Int, let text = fields["body"] as? String else { return }
        captures.continuation.yield(Capture(kind: op == "Bookmarks" ? .bookmark : .like, status: status, data: Data(text.utf8)))
    }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        guard let fields = body(message), let path = fields["path"] as? String, let handle = fields["handle"] as? String,
              let signedIn = fields["signedIn"] as? Bool else { replyHandler([:], nil); return }
        let effects = machine.tick(path: path, handle: handle, signedIn: signedIn)
        if let line = effects.log { log(line) }
        if let visible = effects.visible { window.showLogin(visible) }
        var reply: [String: Any] = [:]
        if let go = effects.go { reply["go"] = go }
        if effects.scroll { reply["scroll"] = true }
        replyHandler(reply, nil)
        if effects.finished || effects.error != nil { finish(effects.error) }
    }
}
