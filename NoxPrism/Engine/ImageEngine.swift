import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

enum ImageFormat: String, CaseIterable, Identifiable {
    case png, jpeg, webp, avif, heic, tiff, bmp, gif

    var id: Self { self }
    var fileExtension: String { self == .jpeg ? "jpg" : rawValue }
    var isLossy: Bool { [.jpeg, .webp, .avif, .heic].contains(self) }
    var utType: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .webp: .webP
        case .avif: UTType("public.avif")!
        case .heic: .heic
        case .tiff: .tiff
        case .bmp: .bmp
        case .gif: .gif
        }
    }
}

enum Resize: Hashable {
    case original
    case scale(Double)
    case width(Int) // height follows each image's aspect ratio
    case exact(width: Int, height: Int)

    func size(for s: CGSize) -> CGSize? {
        switch self {
        case .original: nil
        case .scale(let f): CGSize(width: max((s.width * f).rounded(), 1), height: max((s.height * f).rounded(), 1))
        case .width(let w): CGSize(width: CGFloat(w), height: max((s.height * CGFloat(w) / s.width).rounded(), 1))
        case .exact(let w, let h): CGSize(width: w, height: h)
        }
    }
}

struct ImageOptions {
    var format: ImageFormat = .png
    var quality = 0.8 // 0...1, lossy formats only
    var resize = Resize.original
    var removeBackground = false // keep format PNG/WebP/etc. to retain transparency; JPEG flattens it
    var stripMetadata = false
}

enum ImageError: LocalizedError {
    case unreadable(URL), unwritable(URL), noSubject

    var errorDescription: String? {
        switch self {
        case .unreadable(let url): "Can't read \(url.lastPathComponent)"
        case .unwritable(let url): "Can't write \(url.lastPathComponent)"
        case .noSubject: "No foreground subject found"
        }
    }
}

enum ImageEngine {
    static let context = CIContext()

    static func convert(_ input: URL, to dir: URL, options: ImageOptions) async throws -> URL {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
              var image = CIImage(contentsOf: input, options: [.applyOrientationProperty: true])
        else { throw ImageError.unreadable(input) }

        image = image.transformed(by: .init(translationX: -image.extent.minX, y: -image.extent.minY))
        if options.removeBackground { image = try removeBackground(image) }
        if let size = options.resize.size(for: image.extent.size) { image = resize(image, to: size) }
        guard let cgImage = context.createCGImage(image, from: image.extent) else { throw ImageError.unreadable(input) }

        var properties: [CFString: Any] = [:]
        if !options.stripMetadata {
            properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
            properties[kCGImagePropertyOrientation] = 1 // pixels are already upright
        }
        let output = uniqueOutputURL(for: input, in: dir, ext: options.format.fileExtension)

        if options.format == .webp {
            // No native WebP encoder: hand cwebp a lossless PNG.
            let png = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
            defer { try? FileManager.default.removeItem(at: png) }
            try write(cgImage, properties: properties, type: .png, to: png)
            try await Tool.run("cwebp", ["-quiet", "-q", "\(Int(options.quality * 100))",
                                         "-metadata", options.stripMetadata ? "none" : "all",
                                         png.path, "-o", output.path])
        } else {
            if options.format.isLossy { properties[kCGImageDestinationLossyCompressionQuality] = options.quality }
            try write(cgImage, properties: properties, type: options.format.utType, to: output)
        }
        return output
    }

    /// Lanczos, works for both down- and upscaling.
    static func resize(_ image: CIImage, to size: CGSize) -> CIImage {
        let scaleY = size.height / image.extent.height
        let filter = CIFilter.lanczosScaleTransform()
        filter.inputImage = image.clampedToExtent() // avoid dark fringes at the edges
        filter.scale = Float(scaleY)
        filter.aspectRatio = Float(size.width / image.extent.width / scaleY)
        return filter.outputImage!.cropped(to: CGRect(origin: .zero, size: size).integral)
    }

    /// Same engine as "Lift Subject" in Photos/Preview. Background becomes transparent.
    static func removeBackground(_ image: CIImage) throws -> CIImage {
        let handler = VNImageRequestHandler(ciImage: image)
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])
        guard let result = request.results?.first else { throw ImageError.noSubject }
        let mask = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
        return image.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(),
            kCIInputMaskImageKey: CIImage(cvPixelBuffer: mask),
        ])
    }

    private static func write(_ image: CGImage, properties: [CFString: Any], type: UTType, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
        else { throw ImageError.unwritable(url) }
        CGImageDestinationAddImage(dest, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ImageError.unwritable(url) }
    }
}
