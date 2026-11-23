import Foundation
import KaleidostashCore

enum SyncController {
    @MainActor static func run(executable: URL, progress: @escaping @MainActor @Sendable (SyncProgress) -> Void) async throws {
        let process = Process(), pipe = Pipe()
        let log = Paths.dataDir.appending(path: "sync.log")
        if !FileManager.default.fileExists(atPath: log.path) { FileManager.default.createFile(atPath: log.path, contents: nil) }
        let errors = try FileHandle(forWritingTo: log)
        defer { try? errors.close() }
        try errors.seekToEnd()
        process.executableURL = executable
        process.arguments = ["sync", "--login"]
        process.standardOutput = pipe
        process.standardError = errors
        try process.run()
        let message = try await Task.detached {
            var message: String?
            for try await line in pipe.fileHandleForReading.bytes.lines {
                if let update = try? JSONDecoder().decode(SyncProgress.self, from: Data(line.utf8)) {
                    await progress(update)
                    if let error = update.error { message = error }
                }
            }
            process.waitUntilExit()
            return message
        }.value
        guard process.terminationStatus == 0 else {
            throw ArchiveError(message ?? "Sync stopped (exit status \(process.terminationStatus)).")
        }
    }
}
