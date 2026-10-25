import ImageIO
import XCTest
@testable import NoxPrism

final class EngineTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: Color

    func testColorFormats() {
        let red = RGBA(r: 1, g: 0, b: 0, a: 1)
        XCTAssertEqual(red.hex, "#FF0000")
        XCTAssertEqual(red.rgb, "rgb(255, 0, 0)")
        XCTAssertEqual(red.rgba, "rgba(255, 0, 0, 1)")
        XCTAssertEqual(red.hsl, "hsl(0, 100%, 50%)")
        XCTAssertEqual(red.hsb, "hsb(0, 100%, 100%)")
        XCTAssertEqual(red.cmyk, "cmyk(0%, 100%, 100%, 0%)")
        XCTAssertEqual(red.oklch, "oklch(62.80% 0.2577 29.23)") // reference: oklch(62.8% 0.2577 29.23)
        XCTAssertEqual(red.swiftUI, "Color(red: 1.000, green: 0.000, blue: 0.000)")

        let white = RGBA(r: 1, g: 1, b: 1, a: 1).oklabComponents
        XCTAssertEqual(white.L, 1, accuracy: 1e-4)
        XCTAssertEqual(white.a, 0, accuracy: 1e-4)

        let violet = RGBA(r: 64 / 255, g: 91 / 255, b: 1, a: 0.5)
        XCTAssertEqual(violet.hex, "#405BFF80")
        XCTAssertEqual(violet.rgba, "rgba(64, 91, 255, 0.5)")
        XCTAssertEqual(violet.hsl, "hsl(232, 100%, 63%)")
        XCTAssertEqual(RGBA(r: 0, g: 0, b: 0, a: 1).cmyk, "cmyk(0%, 0%, 0%, 100%)")
    }

    func testColorHistoryRoundTrip() throws {
        let url = dir.appendingPathComponent("sub/colors.json")
        let colors = [RGBA(r: 0.1, g: 0.2, b: 0.3, a: 1)]
        XCTAssertEqual(ColorHistory.load(from: url), [])
        try ColorHistory.save(colors, to: url)
        XCTAssertEqual(ColorHistory.load(from: url), colors)
    }

    // MARK: Image

    func testImageConvertEveryFormat() async throws {
        let input = try makeJPEG(width: 64, height: 48)
        for format in ImageFormat.allCases {
            let out = try await ImageEngine.convert(input, to: dir, options: .init(format: format, resize: .exact(width: 32, height: 24)))
            XCTAssertEqual(out.pathExtension, format.fileExtension)
            XCTAssertEqual(try pixelSize(out), [32, 24], "\(format)")
        }
    }

    func testImageMetadataAndNoOverwrite() async throws {
        let input = try makeJPEG(width: 20, height: 10)
        let kept = try await ImageEngine.convert(input, to: dir, options: .init(format: .jpeg))
        let stripped = try await ImageEngine.convert(input, to: dir, options: .init(format: .jpeg, stripMetadata: true))
        XCTAssertEqual(Set([input, kept, stripped].map(\.lastPathComponent)).count, 3) // source never overwritten
        XCTAssertEqual(try exif(kept)?[kCGImagePropertyExifUserComment] as? String, "nox")
        XCTAssertNil(try exif(stripped)?[kCGImagePropertyExifUserComment])
    }

    func testUpscale() async throws {
        let input = try makeJPEG(width: 10, height: 10)
        let out = try await ImageEngine.convert(input, to: dir, options: .init(resize: .scale(4)))
        XCTAssertEqual(try pixelSize(out), [40, 40])
        let wide = try await ImageEngine.convert(try makeJPEG(width: 20, height: 10), to: dir, options: .init(resize: .width(50)))
        XCTAssertEqual(try pixelSize(wide), [50, 25])
    }

    // MARK: Video

    func testVideo() async throws {
        let input = dir.appendingPathComponent("clip.mp4")
        try await Tool.run("ffmpeg", ["-v", "error", "-f", "lavfi", "-i", "testsrc=size=320x240:rate=10:duration=2",
                                      "-f", "lavfi", "-i", "sine=duration=2", "-shortest", "-pix_fmt", "yuv420p", input.path])

        var last = 0.0
        let webm = try await VideoEngine.convert(input, to: dir, options: .init(format: .webm, height: 120, trim: 0.5...1.5)) { last = $0 }
        XCTAssertEqual(last, 1)
        let webmDuration = try await VideoEngine.duration(of: webm)
        XCTAssertEqual(webmDuration, 1, accuracy: 0.15)
        let frame = try await VideoEngine.extractFrame(webm, at: 0.2, to: dir)
        XCTAssertEqual(try pixelSize(frame), [160, 120])

        let gif = try await VideoEngine.convert(input, to: dir, options: .init(format: .gif, height: 60))
        let back = try await VideoEngine.convert(gif, to: dir, options: .init(format: .mov))
        let backFrame = try await VideoEngine.extractFrame(back, at: 0, to: dir)
        XCTAssertEqual(try pixelSize(backFrame), [80, 60])

        let audio = try await VideoEngine.convert(input, to: dir, options: .init(audioOnly: true))
        XCTAssertEqual(audio.pathExtension, "m4a")
        let audioDuration = try await VideoEngine.duration(of: audio)
        XCTAssertEqual(audioDuration, 2, accuracy: 0.15)
    }

    // MARK: Helpers

    private func makeJPEG(width: Int, height: Int) throws -> URL {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(red: 0.25, green: 0.36, blue: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        let url = dir.appendingPathComponent("src.jpg")
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil)!
        let props = [kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "nox"]] as CFDictionary
        CGImageDestinationAddImage(dest, ctx.makeImage()!, props)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }

    private func properties(_ url: URL) throws -> [CFString: Any] {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    private func pixelSize(_ url: URL) throws -> [Int] {
        let p = try properties(url)
        return [p[kCGImagePropertyPixelWidth] as? Int ?? -1, p[kCGImagePropertyPixelHeight] as? Int ?? -1]
    }

    private func exif(_ url: URL) throws -> [CFString: Any]? {
        try properties(url)[kCGImagePropertyExifDictionary] as? [CFString: Any]
    }
}
