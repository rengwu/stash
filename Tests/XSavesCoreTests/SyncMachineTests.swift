import Foundation
import Testing
@testable import XSavesCore

@Test func signIn() {
    var background = SyncMachine(login: false)
    #expect(background.tick(path: "/login", handle: "", signedIn: false).error == "Sign in to X: press Sync in the xsaves window.")
    var interactive = SyncMachine(login: true)
    let first = interactive.tick(path: "/login", handle: "", signedIn: false)
    #expect(first.visible == true && first.go == "https://x.com/i/flow/login")
    #expect(interactive.tick(path: "/login", handle: "", signedIn: false).go == nil)
    let signedIn = interactive.tick(path: "/", handle: "a", signedIn: true)
    #expect(signedIn.visible == false && signedIn.go == "https://x.com/i/bookmarks")
}

@Test func phases() {
    let now = Date()
    var machine = SyncMachine(login: false, now: now)
    func tick(_ seconds: Double, _ handle: String = "") -> SyncMachine.Effects {
        machine.tick(path: "/i/history", handle: handle, signedIn: true, now: now.addingTimeInterval(seconds))
    }
    #expect(tick(46).error == "X did not load your bookmarks. It showed /i/history.")
    #expect((machine.captured(.like, saves: 0, added: 0, complete: false, now: now)) == false)
    #expect((machine.captured(.bookmark, saves: 0, added: 0, complete: false, now: now)) == true)
    #expect(!tick(1).finished)
    #expect(tick(2).go == nil)
    #expect(tick(3,"a").go == "https://x.com/a/likes")
    #expect((machine.captured(.like, saves: 1, added: 0, complete: true, now: now)) == false)
    #expect(tick(4).finished)
    var stalled = SyncMachine(login: false, now: now)
    #expect((stalled.captured(.bookmark, saves: 1, added: 1, complete: false, now: now)) == false)
    #expect(stalled.tick(path: "/", handle: "a", signedIn: true, now: now).scroll)
    #expect(stalled.tick(path: "/", handle: "a", signedIn: true, now: now.addingTimeInterval(31)).log?.contains("stopped loading") == true)
}
