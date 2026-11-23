import Foundation
import Testing
@testable import KaleidostashCore

@Test(arguments: ["com.kaleidostash.sync", "com.stash.sync", "com.mosaic.sync", "com.xsaves.sync"])
func schedule(label: String) throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let executable = folder.appending(path: "x & y")
    let plistURL = folder.appending(path: label + ".plist")
    if label != "com.kaleidostash.sync" {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let existing = ["Label": label, "ProgramArguments": ["/old/path", "sync"]] as [String: Any]
        try PropertyListSerialization.data(fromPropertyList: existing, format: .xml, options: 0).write(to: plistURL)
    }
    let schedule = Schedule(folder: folder, executable: executable, dataDir: folder) { args in
        if args.first == "bootout" { throw ArchiveError("No existing agent.") }
        #expect(args == ["bootstrap", "gui/\(getuid())", plistURL.path])
    }
    if label != "com.kaleidostash.sync" {
        #expect(schedule.isOn && schedule.programPath == "/old/path")
    }
    try schedule.set(on: true)
    #expect(schedule.isOn && schedule.programPath == executable.path)
    let data = try Data(contentsOf: plistURL)
    let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    #expect(plist["Label"] as? String == label)
    #expect(plist["StartInterval"] as? Int == 21600)
    #expect(plist["ProgramArguments"] as? [String] == [executable.path, "sync"])
    try schedule.set(on: false)
    #expect(!schedule.isOn)
    let broken = Schedule(folder: folder, executable: executable, dataDir: folder) { _ in throw ArchiveError("failed") }
    #expect(throws: ArchiveError.self) { try broken.set(on: true) }
    #expect(!broken.isOn)
}
