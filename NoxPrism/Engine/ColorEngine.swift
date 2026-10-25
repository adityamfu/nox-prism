import AppKit

/// sRGB, components 0...1.
struct RGBA: Codable, Hashable {
    var r, g, b, a: Double
}

extension RGBA {
    init?(_ color: NSColor) {
        guard let c = color.usingColorSpace(.sRGB) else { return nil }
        let clamp = { (v: CGFloat) in min(max(Double(v), 0), 1) }
        self.init(r: clamp(c.redComponent), g: clamp(c.greenComponent), b: clamp(c.blueComponent), a: clamp(c.alphaComponent))
    }

    /// Rows for the Color Picker list, in design.md order.
    var formats: [(label: String, value: String)] {
        [("HEX", hex), ("RGB", rgb), ("RGBA", rgba), ("HSL", hsl), ("HSB", hsb),
         ("CMYK", cmyk), ("OKLCH", oklch), ("OKLAB", oklab), ("SwiftUI", swiftUI)]
    }

    private var bytes: [Int] { [r, g, b].map { Int(($0 * 255).rounded()) } }
    private var alpha: String { String(format: "%.2g", a) }

    var hex: String {
        let rgb = bytes.map { String(format: "%02X", $0) }.joined()
        return a < 1 ? "#\(rgb)\(String(format: "%02X", Int((a * 255).rounded())))" : "#\(rgb)"
    }

    var rgb: String { "rgb(\(bytes.map(String.init).joined(separator: ", ")))" }
    var rgba: String { "rgba(\(bytes.map(String.init).joined(separator: ", ")), \(alpha))" }

    private var hue: Double {
        let mx = max(r, g, b), d = mx - min(r, g, b)
        guard d > 0 else { return 0 }
        let h = mx == r ? (g - b) / d : mx == g ? (b - r) / d + 2 : (r - g) / d + 4
        return (h * 60 + 360).truncatingRemainder(dividingBy: 360)
    }

    var hsl: String {
        let mx = max(r, g, b), mn = min(r, g, b), l = (mx + mn) / 2
        let s = mx == mn ? 0 : (mx - mn) / (1 - abs(2 * l - 1))
        return String(format: "hsl(%.0f, %.0f%%, %.0f%%)", hue, s * 100, l * 100)
    }

    var hsb: String {
        let mx = max(r, g, b)
        let s = mx == 0 ? 0 : (mx - min(r, g, b)) / mx
        return String(format: "hsb(%.0f, %.0f%%, %.0f%%)", hue, s * 100, mx * 100)
    }

    var cmyk: String {
        let k = 1 - max(r, g, b)
        let cmy = [r, g, b].map { k == 1 ? 0 : (1 - $0 - k) / (1 - k) }
        return String(format: "cmyk(%.0f%%, %.0f%%, %.0f%%, %.0f%%)", cmy[0] * 100, cmy[1] * 100, cmy[2] * 100, k * 100)
    }

    /// Björn Ottosson's OKLab, from linear sRGB.
    var oklabComponents: (L: Double, a: Double, b: Double) {
        let lin = [r, g, b].map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        let l = cbrt(0.4122214708 * lin[0] + 0.5363325363 * lin[1] + 0.0514459929 * lin[2])
        let m = cbrt(0.2119034982 * lin[0] + 0.6806995451 * lin[1] + 0.1073969566 * lin[2])
        let s = cbrt(0.0883024619 * lin[0] + 0.2817188376 * lin[1] + 0.6299787005 * lin[2])
        return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    var oklab: String {
        let c = oklabComponents
        return String(format: "oklab(%.2f%% %.4f %.4f)", c.L * 100, c.a, c.b)
    }

    var oklch: String {
        let c = oklabComponents
        let chroma = hypot(c.a, c.b)
        let h = chroma < 0.0001 ? 0 : (atan2(c.b, c.a) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        return String(format: "oklch(%.2f%% %.4f %.2f)", c.L * 100, chroma, h)
    }

    var swiftUI: String {
        let opacity = a < 1 ? String(format: ", opacity: %.2f", a) : ""
        return String(format: "Color(red: %.3f, green: %.3f, blue: %.3f", r, g, b) + opacity + ")"
    }
}

enum ColorSampler {
    /// System-wide eyedropper with magnifier loupe. nil if the user cancels (Esc).
    @MainActor
    static func pick() async -> RGBA? {
        await withCheckedContinuation { continuation in
            NSColorSampler().show { continuation.resume(returning: $0.flatMap(RGBA.init)) }
        }
    }
}

/// Picked colors, recent-first, as JSON in Application Support.
enum ColorHistory {
    static let defaultURL = URL.applicationSupportDirectory.appending(path: "Nox Prism/colors.json")

    static func load(from url: URL = defaultURL) -> [RGBA] {
        (try? JSONDecoder().decode([RGBA].self, from: Data(contentsOf: url))) ?? []
    }

    static func save(_ colors: [RGBA], to url: URL = defaultURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(colors).write(to: url, options: .atomic)
    }
}
