import Foundation

enum VideoFormat: String, CaseIterable, Identifiable {
    case mp4, mov, webm, mkv, gif

    var id: Self { self }
}

struct VideoOptions {
    var format: VideoFormat = .mp4
    var height: Int? = nil // nil = original resolution
    var bitrateKbps: Int? = nil // nil = encoder's default quality
    var trim: ClosedRange<Double>? = nil // seconds
    var audioOnly = false // outputs .m4a, ignores format
}

/// Thin ffmpeg/ffprobe wrapper.
enum VideoEngine {
    static func duration(of url: URL) async throws -> Double {
        let out = try await Tool.run("ffprobe", ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", url.path])
        guard let seconds = Double(out.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw ToolError.failed("ffprobe", "no duration for \(url.lastPathComponent)")
        }
        return seconds
    }

    /// Also handles GIF → video (input format doesn't matter to ffmpeg).
    static func convert(_ input: URL, to dir: URL, options: VideoOptions,
                        progress: @escaping (Double) -> Void = { _ in }) async throws -> URL {
        let output = uniqueOutputURL(for: input, in: dir, ext: options.audioOnly ? "m4a" : options.format.rawValue)
        var total = 0.0
        if let trim = options.trim { total = trim.upperBound - trim.lowerBound } else { total = try await duration(of: input) }
        do {
            try await Tool.run("ffmpeg", arguments(input: input, output: output, options: options)) { line in
                // `-progress pipe:1` emits key=value lines; out_time_us is the encoded position.
                if line.hasPrefix("out_time_us="), let us = Double(line.dropFirst(12)), total > 0 {
                    progress(min(us / 1_000_000 / total, 1))
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
        progress(1)
        return output
    }

    static func extractFrame(_ input: URL, at seconds: Double, to dir: URL) async throws -> URL {
        let output = uniqueOutputURL(for: input, in: dir, ext: "png")
        try await Tool.run("ffmpeg", ["-y", "-v", "error", "-ss", "\(seconds)", "-i", input.path, "-frames:v", "1", output.path])
        return output
    }

    static func arguments(input: URL, output: URL, options o: VideoOptions) -> [String] {
        var args = ["-y", "-v", "error", "-nostats", "-progress", "pipe:1"]
        if let trim = o.trim { args += ["-ss", "\(trim.lowerBound)"] }
        args += ["-i", input.path]
        if let trim = o.trim { args += ["-t", "\(trim.upperBound - trim.lowerBound)"] }
        if o.audioOnly { return args + ["-vn", "-c:a", "aac", output.path] }

        let scale = o.height.map { "scale=-2:\($0 / 2 * 2):flags=lanczos" }
        switch o.format {
        case .gif:
            let filters = ["fps=15", scale].compactMap { $0 }.joined(separator: ",")
            return args + ["-vf", "\(filters),split[a][b];[a]palettegen[p];[b][p]paletteuse", "-loop", "0", output.path]
        case .webm:
            args += ["-c:v", "libvpx-vp9", "-row-mt", "1", "-c:a", "libopus"]
            if o.bitrateKbps == nil { args += ["-crf", "32", "-b:v", "0"] } // vp9's default bitrate is tiny
        case .mp4, .mov, .mkv:
            args += ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac"]
            if o.format != .mkv { args += ["-movflags", "+faststart"] }
        }
        // yuv420p needs even dimensions; GIF sources often aren't.
        args += ["-vf", scale ?? "scale=trunc(iw/2)*2:trunc(ih/2)*2"]
        if let kbps = o.bitrateKbps { args += ["-b:v", "\(kbps)k"] }
        return args + [output.path]
    }
}
