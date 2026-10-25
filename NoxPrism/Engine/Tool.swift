import Foundation

enum ToolError: LocalizedError {
    case notInstalled(String)
    case failed(String, String)

    var errorDescription: String? {
        switch self {
        case .notInstalled(let name): "\(name) not found — brew install it"
        case .failed(let name, let stderr): "\(name) failed: \(stderr)"
        }
    }
}

/// Runs the Homebrew CLIs (ffmpeg, ffprobe, cwebp). GUI apps don't inherit the shell PATH,
/// so look in the brew prefixes directly.
enum Tool {
    static let searchPaths = ["/opt/homebrew/bin", "/usr/local/bin"]

    static func url(_ name: String) throws -> URL {
        guard let dir = searchPaths.first(where: { FileManager.default.isExecutableFile(atPath: "\($0)/\(name)") })
        else { throw ToolError.notInstalled(name) }
        return URL(fileURLWithPath: "\(dir)/\(name)")
    }

    /// Streams stdout lines to `onLine`, returns full stdout. Cancelling the task kills the process.
    @discardableResult
    static func run(_ name: String, _ args: [String], onLine: @escaping (String) -> Void = { _ in }) async throws -> String {
        let process = Process()
        process.executableURL = try url(name)
        process.arguments = args
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let stderr = Task.detached { err.fileHandleForReading.readDataToEndOfFile() }

        var stdout = ""
        try await withTaskCancellationHandler {
            for try await line in out.fileHandleForReading.bytes.lines {
                stdout += line + "\n"
                onLine(line)
            }
        } onCancel: {
            process.terminate()
        }
        process.waitUntilExit()
        try Task.checkCancellation()
        guard process.terminationStatus == 0 else {
            throw ToolError.failed(name, String(decoding: await stderr.value, as: UTF8.self))
        }
        return stdout
    }
}

/// `dir/<input name>.<ext>`, numbered (" 2", " 3", …) so it never overwrites the source or an earlier output.
// ponytail: check-then-write race if two parallel jobs map to the same name; reserve names in the queue if that bites.
func uniqueOutputURL(for input: URL, in dir: URL, ext: String) -> URL {
    let base = input.deletingPathExtension().lastPathComponent
    var url = dir.appendingPathComponent(base).appendingPathExtension(ext)
    var n = 2
    while FileManager.default.fileExists(atPath: url.path) {
        url = dir.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
        n += 1
    }
    return url
}
