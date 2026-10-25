import SwiftUI

// Tokens from design.md §4. One accent hue (violet-blue), everything else monochrome.
extension ShapeStyle where Self == Color {
    static var midnightInk: Color { Color(hex: 0x0E0E0E) } // canvas
    static var carbon: Color { Color(hex: 0x191919) } // surface/card
    static var graphite: Color { Color(hex: 0x414042) } // border/divider
    static var paper: Color { .white } // primary text
    static var fog: Color { Color(hex: 0xA7A9AC) } // secondary text
    static var ash: Color { Color(hex: 0xD1D3D4) } // tertiary text
    static var signalViolet: Color { Color(hex: 0x7084FF) } // glow, active state
    static var voltageBlue: Color { Color(hex: 0x405BFF) } // primary button fill
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

extension RGBA {
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
}

enum Radius {
    static let pill: CGFloat = 30
    static let input: CGFloat = 10
    static let card: CGFloat = 18
}

extension Font {
    static let mono = Font.system(.callout, design: .monospaced) // hex codes, paths, OKLCH
}

extension View {
    /// Elevation is glow, not drop shadow.
    func glow(_ active: Bool = true) -> some View {
        shadow(color: .signalViolet.opacity(active ? 0.25 : 0), radius: 20)
    }
}

struct PillButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .background(Capsule().fill(.voltageBlue))
            .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.8 : 1)
            .glow(isEnabled)
    }
}

/// Selectable pill, used as a wrapping segmented control.
struct ChipStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .foregroundStyle(selected ? .paper : .fog)
            .background(Capsule().fill(selected ? .voltageBlue : .midnightInk))
            .overlay(Capsule().strokeBorder(selected ? .signalViolet : .graphite))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
