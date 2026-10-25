import QuickLookThumbnailing
import SwiftUI

struct DropZoneView: View {
    let title: String
    let onDrop: ([URL]) -> Void
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(targeted ? .signalViolet : .fog)
            Text(title).font(.headline)
            Text("or click to browse").font(.callout).foregroundStyle(.fog)
        }
        .frame(maxWidth: .infinity, minHeight: 130)
        .background(RoundedRectangle(cornerRadius: Radius.card).fill(.carbon))
        .overlay(RoundedRectangle(cornerRadius: Radius.card)
            .strokeBorder(targeted ? .signalViolet : .graphite, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
        .glow(targeted)
        .animation(.easeOut(duration: 0.15), value: targeted)
        .contentShape(Rectangle())
        .onTapGesture(perform: browse)
        .dropDestination(for: URL.self) { urls, _ in
            onDrop(urls)
            return true
        } isTargeted: { targeted = $0 }
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        if panel.runModal() == .OK { onDrop(panel.urls) }
    }
}

struct QueueList<Options>: View {
    let queue: JobQueue<Options>

    var body: some View {
        if queue.items.isEmpty {
            Text("Queue is empty").foregroundStyle(.fog).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(queue.items.count) file\(queue.items.count == 1 ? "" : "s")").foregroundStyle(.fog)
                    Spacer()
                    Button("Clear", action: queue.clear).buttonStyle(.borderless).disabled(queue.isRunning)
                }
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(queue.items) { item in
                            QueueRow(item: item).contextMenu {
                                Button("Remove") { queue.remove(item.id) }.disabled(queue.isRunning)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct QueueRow: View {
    let item: QueueItem

    var body: some View {
        HStack(spacing: 12) {
            Thumbnail(url: item.url)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                switch item.status {
                case .processing: ProgressView(value: item.progress).controlSize(.small)
                case .failed(let message): Text(message).font(.caption).foregroundStyle(.fog).lineLimit(2)
                case .done(let output): Text(output.lastPathComponent).font(.caption).foregroundStyle(.fog).lineLimit(1)
                case .pending: EmptyView()
                }
            }
            Spacer()
            StatusBadge(status: item.status)
            if case .done(let output) = item.status {
                Button { NSWorkspace.shared.activateFileViewerSelecting([output]) } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("Show in Finder")
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(.carbon))
    }
}

struct StatusBadge: View {
    let status: QueueItem.Status

    var body: some View {
        let (label, icon, active): (String, String?, Bool) = switch status {
        case .pending: ("Pending", nil, false)
        case .processing: ("Processing", nil, true)
        case .done: ("Done", "checkmark", true)
        case .failed: ("Error", "exclamationmark.triangle.fill", false)
        }
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon) }
            Text(label)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .foregroundStyle(active ? .signalViolet : .ash)
        .overlay(Capsule().strokeBorder(active ? .signalViolet : .graphite))
    }
}

struct Thumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "doc").foregroundStyle(.fog)
            }
        }
        .frame(width: 40, height: 40)
        .background(.midnightInk)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: url) {
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 40, height: 40), scale: 2, representationTypes: .all)
            image = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
        }
    }
}

struct SettingsPanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) { content }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.carbon)
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.fog)
            content
        }
    }
}

struct ChipPicker<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
            ForEach(options, id: \.self) { option in
                Button(label(option)) { selection = option }.buttonStyle(ChipStyle(selected: option == selection))
            }
        }
    }
}

/// Destination folder, preset menu, and the main action.
struct BottomBar<Presets: View>: View {
    @Binding var outputDir: URL?
    let isRunning: Bool
    let canRun: Bool
    let run: () -> Void
    let cancel: () -> Void
    @ViewBuilder let presets: Presets

    var body: some View {
        HStack(spacing: 12) {
            Button(action: chooseFolder) {
                Label(outputDir?.lastPathComponent ?? "Same folder as source", systemImage: "folder").font(.mono)
            }
            .help(outputDir?.path ?? "Outputs go next to each source file")
            if outputDir != nil {
                Button { outputDir = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .help("Reset to source folder")
            }
            Menu("Preset") { presets }.fixedSize()
            Spacer()
            if isRunning { Button("Cancel", action: cancel) }
            Button(isRunning ? "Converting…" : "Convert All", action: run)
                .buttonStyle(PillButtonStyle())
                .disabled(!canRun || isRunning)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.carbon)
        .overlay(alignment: .top) { Rectangle().fill(.graphite).frame(height: 1) }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        if panel.runModal() == .OK { outputDir = panel.url }
    }
}

struct ColorFormatRow: View {
    let label: String
    let value: String
    @State private var copied = false

    var body: some View {
        Button(action: copy) {
            HStack {
                Text(label).foregroundStyle(.fog).frame(width: 70, alignment: .leading)
                Text(value).font(.mono).lineLimit(1)
                Spacer()
                Image(systemName: copied ? "checkmark" : "doc.on.doc").foregroundStyle(copied ? .signalViolet : .fog)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: Radius.input).fill(.carbon))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Copy \(label)")
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            copied = false
        }
    }
}
