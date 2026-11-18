import Foundation
import Testing
@testable import XSavesCore

@Test func schedule() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let executable = folder.appending(path: "x & y")
    let schedule = Schedule(folder: folder, executable: executable, dataDir: folder) { args in
        if args.first == "bootout" { throw ArchiveError("No existing agent.") }
        #expect(args == ["bootstrap", "gui/\(getuid())", folder.appending(path: "com.xsaves.sync.plist").path])
    }
    try schedule.set(on: true)
    #expect(schedule.isOn && schedule.programPath == executable.path)
    let data = try Data(contentsOf: folder.appending(path: "com.xsaves.sync.plist"))
    let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    #expect(plist["StartInterval"] as? Int == 21600)
    #expect(plist["ProgramArguments"] as? [String] == [executable.path, "sync"])
    try schedule.set(on: false)
    #expect(!schedule.isOn)
    let broken = Schedule(folder: folder, executable: executable, dataDir: folder) { _ in throw ArchiveError("failed") }
    #expect(throws: ArchiveError.self) { try broken.set(on: true) }
    #expect(!broken.isOn)
}
