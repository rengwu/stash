import Foundation

package actor Downloader {
    private struct Job: Sendable {
        let source: String, path: String
        var mediaID: String?
    }
    private let store: Store, session: URLSession
    private var failed = Set<String>()
    package init(store: Store) {
        self.store = store
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 600
        session = URLSession(configuration: config)
    }
    package func runOnce(progress: @Sendable (Int) async -> Void) async throws {
        var jobs: [Job] = []
        let root = store.mediaDir
        for (id, media) in try await store.pendingMedia() {
            if !media.poster.isEmpty {
                jobs.append(Job(source: media.poster, path: Paths.posterFile(id, media)))
            }
            jobs.append(Job(source: media.url, path: Paths.mediaFile(id, media), mediaID: media.id))
        }
        for (id, url) in try await store.avatars() {
            jobs.append(Job(source: Paths.avatarURL(url), path: Paths.avatarFile(id)))
        }
        var seen = failed
        jobs = jobs.filter { job in
            seen.insert(job.path).inserted && (job.mediaID != nil || !FileManager.default.fileExists(atPath: root.appending(path: job.path).path))
        }
        var left = jobs.count, iterator = jobs.makeIterator()
        await progress(left)
        try await withThrowingTaskGroup(of: (Job, Bool).self) { group in
            func enqueue() {
                guard let job = iterator.next() else { return }
                group.addTask { [session] in
                    let dest = root.appending(path: job.path).standardizedFileURL
                    guard !job.path.split(separator: "/").contains(".."),
                          let url = URL(string: job.source), url.scheme == "https",
                          ["pbs.twimg.com", "video.twimg.com"].contains(url.host?.lowercased()) else { return (job, false) }
                    do {
                        let (tmp, response) = try await session.download(from: url)
                        defer { try? FileManager.default.removeItem(at: tmp) }
                        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return (job, false) }
                        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                        if FileManager.default.fileExists(atPath: dest.path) {
                            _ = try FileManager.default.replaceItemAt(dest, withItemAt: tmp)
                        } else { try FileManager.default.moveItem(at: tmp, to: dest) }
                        return (job, true)
                    } catch { return (job, false) }
                }
            }
            for _ in 0..<4 { enqueue() }
            while let (job, downloaded) = try await group.next() {
                if !downloaded { failed.insert(job.path) }
                else if let id = job.mediaID { try await store.markDone(id) }
                left -= 1
                await progress(left)
                enqueue()
            }
        }
    }
}
