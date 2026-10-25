import SwiftUI

struct ColorPickerSection: View {
    @State private var history = ColorHistory.load()
    @State private var selected: RGBA?

    private var current: RGBA? { selected ?? history.first }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Button { Task { await pick() } } label: {
                    Label("Pick Color", systemImage: "eyedropper").font(.title3.weight(.semibold)).padding(.horizontal, 8)
                }
                .buttonStyle(PillButtonStyle())

                RoundedRectangle(cornerRadius: 28)
                    .fill(current?.color ?? .carbon)
                    .frame(width: 150, height: 150)
                    .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.graphite))
                    .overlay { if current == nil { Text("No color yet").foregroundStyle(.fog) } }

                if let current {
                    VStack(spacing: 6) {
                        ForEach(current.formats, id: \.label) { ColorFormatRow(label: $0.label, value: $0.value) }
                    }
                }

                if !history.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("HISTORY").font(.caption.weight(.semibold)).foregroundStyle(.fog)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 36, maximum: 36), spacing: 8)], alignment: .leading, spacing: 8) {
                            ForEach(history, id: \.self) { color in
                                HistorySwatch(color: color, isSelected: color == current) {
                                    selected = color
                                } delete: {
                                    history.removeAll { $0 == color }
                                    if selected == color { selected = nil }
                                    save()
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 520)
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .background(.midnightInk)
        .navigationTitle("Color Picker")
    }

    private func pick() async {
        guard let color = await ColorSampler.pick() else { return }
        history.removeAll { $0 == color }
        history.insert(color, at: 0)
        selected = color
        save()
    }

    private func save() { try? ColorHistory.save(history) }
}

private struct HistorySwatch: View {
    let color: RGBA
    let isSelected: Bool
    let select: () -> Void
    let delete: () -> Void
    @State private var hovering = false

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(color.color)
            .frame(width: 36, height: 36)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isSelected ? .signalViolet : .graphite, lineWidth: isSelected ? 2 : 1))
            .overlay(alignment: .topTrailing) {
                if hovering {
                    Button(action: delete) {
                        Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.paper, .midnightInk)
                    }
                    .buttonStyle(.plain)
                    .offset(x: 5, y: -5)
                    .help("Remove from history")
                }
            }
            .onHover { hovering = $0 }
            .onTapGesture(perform: select)
            .help(color.hex)
    }
}
