import Foundation

package struct SyncMachine {
    package struct Effects: Equatable {
        package var visible: Bool?
        package var go: String?
        package var scroll = false, finished = false
        package var error: String?, log: String?
    }

    private let login: Bool
    private var kind: Kind? = .bookmark
    private var handle = "", path = ""
    private var shown = false, opened = true, stop = false
    private var started: Date, lastData: Date?

    package init(login: Bool, now: Date = .now) {
        self.login = login
        started = now
    }

    package mutating func captured(_ kind: Kind, saves: Int, added: Int, complete: Bool, now: Date = .now) -> Bool {
        guard kind == self.kind else { return false }
        lastData = now
        if saves == 0 || (added == 0 && complete) { stop = true }
        return saves == 0
    }

    package mutating func tick(path: String, handle: String, signedIn: Bool, now: Date = .now) -> Effects {
        var effects = Effects()
        guard let kind else { return effects }
        if !handle.isEmpty { self.handle = handle }
        if self.path != path { self.path = path; effects.log = "x.com is showing \(path)" }
        guard signedIn else {
            started = now
            if !login { effects.error = "Sign in to X: press Sync in the xsaves window." }
            else if !shown {
                shown = true
                effects.visible = true
                effects.go = "https://x.com/i/flow/login"
            }
            return effects
        }
        if shown {
            shown = false
            opened = false
            effects.visible = false
        }
        guard let lastData else {
            if now.timeIntervalSince(started) > 45 {
                effects.error = "X did not load your \(kind.rawValue)s. It showed \(path)."
            } else if !opened && (kind == .bookmark || !self.handle.isEmpty) {
                opened = true
                effects.go = kind == .bookmark ? "https://x.com/i/bookmarks" : "https://x.com/\(self.handle)/likes"
            }
            return effects
        }
        if stop || now.timeIntervalSince(lastData) > 30 {
            if !stop { effects.log = "\(kind.rawValue)s stopped loading before the end" }
            self.kind = kind == .bookmark ? .like : nil
            effects.finished = self.kind == nil
            started = now
            self.lastData = nil
            opened = false
            stop = false
        } else { effects.scroll = true }
        return effects
    }
}
