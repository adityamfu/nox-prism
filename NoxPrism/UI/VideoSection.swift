import SwiftUI
import UniformTypeIdentifiers

struct VideoSection: View {
    @Bindable var queue: JobQueue<VideoOptions>
    @State private var showSettings = true
    @State private var duration = 0.0 // of the single queued file, for trim

    static func accepts(_ url: URL) -> Bool {
        ["webm", "mkv", "gif"].contains(url.pathExtension.lowercased())
            || UTType(filenameExtension: url.pathExtension)?.conforms(to: .audiovisualContent) == true
    }

    /// Trim and frame extraction only make sense for one file.
    private var single: URL? { queue.items.count == 1 ? queue.items[0].url : nil }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                DropZoneView(title: "Drop videos, GIFs or folders", onDrop: queue.add)
                QueueList(queue: queue)
            }
            .padding(20)
            BottomBar(outputDir: $queue.outputDir, isRunning: queue.isRunning, canRun: !queue.items.isEmpty,
                      run: convert, cancel: queue.cancel) {
                Button("Compress for WhatsApp (MP4 720p)") { apply { $0 = .init(format: .mp4, height: 720, bitrateKbps: 1500, trim: $0.trim) } }
                Button("WebM 720p") { apply { $0 = .init(format: .webm, height: 720, trim: $0.trim) } }
                Button("GIF 480p") { apply { $0 = .init(format: .gif, height: 480, trim: $0.trim) } }
                Button("Extract audio") { apply { $0.audioOnly = true } }
            }
        }
        .background(.midnightInk)
        .navigationTitle("Video")
        .inspector(isPresented: $showSettings) {
            settings.inspectorColumnWidth(min: 260, ideal: 300, max: 380)
        }
        .toolbar {
            Button { showSettings.toggle() } label: { Label("Settings", systemImage: "sidebar.right") }
        }
        .task(id: single) {
            queue.options.trim = nil
            duration = 0
            if let single { duration = (try? await VideoEngine.duration(of: single)) ?? 0 }
        }
    }

    private var settings: some View {
        SettingsPanel {
            SettingsSection("Format") {
                ChipPicker(options: VideoFormat.allCases, selection: $queue.options.format) { $0.rawValue.uppercased() }
                    .disabled(queue.options.audioOnly)
                    .opacity(queue.options.audioOnly ? 0.4 : 1)
            }
            SettingsSection("Resolution") {
                Picker("Resolution", selection: resolution) {
                    Text("Original").tag(Int?.none)
                    ForEach([1080, 720, 480], id: \.self) { Text(verbatim: "\($0)p").tag(Int?.some($0)) }
                    Text("Custom").tag(Int?.some(-1))
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if resolution.wrappedValue == -1 {
                    HStack {
                        TextField("Height", value: Binding(get: { queue.options.height ?? 0 }, set: { queue.options.height = max($0, 2) }),
                                  format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder)
                        Text("px tall").foregroundStyle(.fog)
                    }
                    .font(.mono)
                }
            }
            SettingsSection("Bitrate") {
                Toggle("Custom bitrate", isOn: Binding(get: { queue.options.bitrateKbps != nil },
                                                        set: { queue.options.bitrateKbps = $0 ? 4000 : nil }))
                    .toggleStyle(.switch)
                if let kbps = queue.options.bitrateKbps {
                    HStack {
                        Slider(value: Binding(get: { Double(kbps) }, set: { queue.options.bitrateKbps = Int($0) }), in: 300 ... 20000, step: 100)
                        Text(verbatim: "\(kbps) kbps").font(.mono).frame(width: 90, alignment: .trailing)
                    }
                }
            }
            SettingsSection("Trim") {
                if single != nil && duration > 0 {
                    trimSlider("Start", \.lowerBound)
                    trimSlider("End", \.upperBound)
                } else {
                    Text("Queue a single file to trim").font(.caption).foregroundStyle(.fog)
                }
            }
            SettingsSection("Extract") {
                Toggle("Extract audio only", isOn: $queue.options.audioOnly).toggleStyle(.switch)
                Button("Extract frame as image", systemImage: "photo", action: extractFrame)
                    .disabled(single == nil || queue.isRunning)
                    .help("Saves the frame at the trim start as PNG")
            }
        }
    }

    private var resolution: Binding<Int?> {
        Binding {
            switch queue.options.height {
            case nil, 1080, 720, 480: queue.options.height
            default: -1
            }
        } set: {
            queue.options.height = $0 == -1 ? 1440 : $0
        }
    }

    private var trim: ClosedRange<Double> { queue.options.trim ?? 0 ... duration }

    private func trimSlider(_ label: String, _ bound: KeyPath<ClosedRange<Double>, Double>) -> some View {
        let isStart = bound == \.lowerBound
        let value = Binding<Double> { trim[keyPath: bound] } set: { new in
            // keep at least 0.1s between handles
            let range = isStart ? min(new, trim.upperBound - 0.1) ... trim.upperBound : trim.lowerBound ... max(new, trim.lowerBound + 0.1)
            queue.options.trim = range == 0 ... duration ? nil : range
        }
        return HStack {
            Text(label).foregroundStyle(.fog).frame(width: 36, alignment: .leading)
            Slider(value: value, in: 0 ... duration)
            Text(Self.timestamp(value.wrappedValue)).font(.mono).frame(width: 64, alignment: .trailing)
        }
    }

    private static func timestamp(_ t: Double) -> String {
        String(format: "%d:%05.2f", Int(t) / 60, t.truncatingRemainder(dividingBy: 60))
    }

    // MARK: Actions

    private func apply(_ preset: (inout VideoOptions) -> Void) { preset(&queue.options) }

    private func convert() {
        var options = queue.options
        if single == nil { options.trim = nil }
        queue.run { input, dir, progress in try await VideoEngine.convert(input, to: dir, options: options, progress: progress) }
    }

    private func extractFrame() {
        let at = trim.lowerBound
        queue.run { input, dir, _ in try await VideoEngine.extractFrame(input, at: at, to: dir) }
    }
}
