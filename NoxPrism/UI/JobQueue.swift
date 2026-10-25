import Foundation
import Observation

struct QueueItem: Identifiable {
    enum Status {
        case pending, processing, done(URL), failed(String)
    }

    let id = UUID()
    let url: URL
    var status = Status.pending
    var progress = 0.0
}

/// Files + settings for one section. Owned by the root view so it survives switching sections.
@MainActor @Observable
final class JobQueue<Options> {
    var items: [QueueItem] = []
    var options: Options
    var outputDir: URL? // nil = next to each source
    private(set) var isRunning = false
    @ObservationIgnored private let accepts: (URL) -> Bool
    @ObservationIgnored private var task: Task<Void, Never>?

    init(options: Options, accepts: @escaping (URL) -> Bool) {
        self.options = options
        self.accepts = accepts
    }

    /// Folders are expanded recursively; unsupported files and duplicates are skipped.
    func add(_ urls: [URL]) {
        var seen = Set(items.map(\.url))
        // Resolve symlinks so a file dropped directly and via its folder dedupes (/var vs /private/var).
        for url in urls.flatMap({ Self.files(in: $0) }).map({ $0.resolvingSymlinksInPath() })
        where accepts(url) && seen.insert(url).inserted {
            items.append(QueueItem(url: url))
        }
    }

    func remove(_ id: UUID) { items.removeAll { $0.id == id } }
    func clear() { items.removeAll() }
    func cancel() { task?.cancel() }

    /// Runs `work(input, outputDir, progress)` on every item, one at a time.
    // ponytail: sequential; a TaskGroup with a width limit if batches feel slow.
    func run(_ work: @escaping (URL, URL, @escaping (Double) -> Void) async throws -> URL) {
        guard !isRunning else { return }
        for i in items.indices { items[i].status = .pending; items[i].progress = 0 }
        isRunning = true
        task = Task {
            for id in items.map(\.id) {
                if Task.isCancelled { break }
                guard let url = items.first(where: { $0.id == id })?.url else { continue }
                update(id) { $0.status = .processing }
                do {
                    let output = try await work(url, outputDir ?? url.deletingLastPathComponent()) { progress in
                        Task { @MainActor in self.update(id) { $0.progress = progress } }
                    }
                    update(id) { $0.status = .done(output) }
                } catch {
                    update(id) { $0.status = Task.isCancelled ? .pending : .failed(error.localizedDescription) }
                }
            }
            isRunning = false
        }
    }

    private func update(_ id: UUID, _ change: (inout QueueItem) -> Void) {
        if let i = items.firstIndex(where: { $0.id == id }) { change(&items[i]) }
    }

    private static func files(in url: URL) -> [URL] {
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return [url] }
        let all = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: .skipsHiddenFiles)?
            .allObjects as? [URL] ?? []
        return all.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
    }
}
