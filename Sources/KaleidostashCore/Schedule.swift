import Foundation

package struct Schedule: Sendable {
    typealias Runner = @Sendable ([String]) throws -> Void
    private let plist: URL, executable: URL, dataDir: URL
    private let run: Runner
    package init() {
        self.init(folder: URL.libraryDirectory.appending(path: "LaunchAgents"),
                  executable: Bundle.main.executableURL!, dataDir: Paths.dataDir, run: Self.launchctl)
    }
    init(folder: URL, executable: URL, dataDir: URL, run: @escaping Runner) {
        let current = folder.appending(path: "com.kaleidostash.sync.plist")
        let previous = ["com.stash.sync.plist", "com.xsaves.sync.plist", "com.mosaic.sync.plist"].map { folder.appending(path: $0) }
        plist = ([current] + previous).first { FileManager.default.fileExists(atPath: $0.path) } ?? current
        self.executable = executable
        self.dataDir = dataDir
        self.run = run
    }
    package var isOn: Bool { FileManager.default.fileExists(atPath: plist.path) }
    package var programPath: String? {
        guard let data = try? Data(contentsOf: plist),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return (dict["ProgramArguments"] as? [String])?.first
    }
    package func set(on: Bool) throws {
        let label = plist.deletingPathExtension().lastPathComponent
        let domain = "gui/\(getuid())"
        try? run(["bootout", "\(domain)/\(label)"])
        guard on else {
            if isOn { try FileManager.default.removeItem(at: plist) }
            return
        }
        let log = dataDir.appending(path: "sync.log").path
        let spec: [String: Any] = ["Label": label, "ProgramArguments": [executable.path, "sync"], "StartInterval": 21600,
                                   "StandardOutPath": log, "StandardErrorPath": log]
        let bytes = try PropertyListSerialization.data(fromPropertyList: spec, format: .xml, options: 0)
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: plist, options: .atomic)
        do { try run(["bootstrap", domain, plist.path]) }
        catch { try? FileManager.default.removeItem(at: plist); throw error }
    }
    private static func launchctl(_ args: [String]) throws {
        let task = Process(), pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = args
        task.standardOutput = pipe
        task.standardError = pipe
        try task.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            throw ArchiveError("launchctl: " + String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
