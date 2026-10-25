import SwiftUI
import UniformTypeIdentifiers

struct ImageSection: View {
    @Bindable var queue: JobQueue<ImageOptions>
    @State private var showSettings = true

    static func accepts(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                DropZoneView(title: "Drop images or folders", onDrop: queue.add)
                QueueList(queue: queue)
            }
            .padding(20)
            BottomBar(outputDir: $queue.outputDir, isRunning: queue.isRunning, canRun: !queue.items.isEmpty,
                      run: convert, cancel: queue.cancel) {
                Button("WebP 80%") { apply { $0.format = .webp; $0.quality = 0.8 } }
                Button("Compress JPEG 70%, strip metadata") { apply { $0.format = .jpeg; $0.quality = 0.7; $0.stripMetadata = true } }
                Button("Transparent PNG (remove background)") { apply { $0.format = .png; $0.removeBackground = true } }
            }
        }
        .background(.midnightInk)
        .navigationTitle("Image")
        .inspector(isPresented: $showSettings) {
            settings.inspectorColumnWidth(min: 260, ideal: 300, max: 380)
        }
        .toolbar {
            Button { showSettings.toggle() } label: { Label("Settings", systemImage: "sidebar.right") }
        }
    }

    private var settings: some View {
        SettingsPanel {
            SettingsSection("Format") {
                ChipPicker(options: ImageFormat.allCases, selection: $queue.options.format) { $0.rawValue.uppercased() }
            }
            if queue.options.format.isLossy {
                SettingsSection("Quality") {
                    HStack {
                        Slider(value: $queue.options.quality, in: 0.1 ... 1)
                        Text("\(Int(queue.options.quality * 100))").font(.mono).frame(width: 32, alignment: .trailing)
                    }
                }
            }
            SettingsSection("Resize") {
                Picker("Resize", selection: resizeMode) {
                    ForEach(ResizeMode.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if resizeMode.wrappedValue == .custom { customSizeFields }
            }
            SettingsSection("Options") {
                Toggle("Remove Background", isOn: $queue.options.removeBackground).toggleStyle(.switch)
                if queue.options.removeBackground && [.jpeg, .bmp].contains(queue.options.format) {
                    Text("\(queue.options.format.rawValue.uppercased()) has no transparency — background turns black.")
                        .font(.caption).foregroundStyle(.fog)
                }
                Toggle("Strip metadata", isOn: $queue.options.stripMetadata).toggleStyle(.checkbox)
            }
        }
    }

    private var customSizeFields: some View {
        HStack(spacing: 8) {
            TextField("Width", value: Binding(get: { custom.w }, set: { setCustom(w: $0, h: custom.h) }),
                      format: .number.grouping(.never))
            Button { setCustom(w: custom.w, h: custom.h == nil ? custom.w : nil) } label: {
                Image(systemName: custom.h == nil ? "lock.fill" : "lock.open")
            }
            .buttonStyle(.borderless)
            .help(custom.h == nil ? "Aspect ratio locked — height follows each image" : "Unlock: exact width × height")
            if custom.h == nil {
                Text("auto").font(.mono).foregroundStyle(.fog).frame(maxWidth: .infinity)
            } else {
                TextField("Height", value: Binding(get: { custom.h ?? custom.w }, set: { setCustom(w: custom.w, h: $0) }),
                          format: .number.grouping(.never))
            }
        }
        .textFieldStyle(.roundedBorder)
        .font(.mono)
    }

    // MARK: Resize <-> UI

    private enum ResizeMode: String, CaseIterable {
        case original = "Original", half = "50%", double = "200%", quadruple = "400%", custom = "Custom"
    }

    private var resizeMode: Binding<ResizeMode> {
        Binding {
            switch queue.options.resize {
            case .original: .original
            case .scale(0.5): .half
            case .scale(2): .double
            case .scale(4): .quadruple
            default: .custom
            }
        } set: {
            queue.options.resize = switch $0 {
            case .original: .original
            case .half: .scale(0.5)
            case .double: .scale(2)
            case .quadruple: .scale(4)
            case .custom: .width(1920)
            }
        }
    }

    /// h == nil means aspect-locked.
    private var custom: (w: Int, h: Int?) {
        switch queue.options.resize {
        case .width(let w): (w, nil)
        case .exact(let w, let h): (w, h)
        default: (1920, nil)
        }
    }

    private func setCustom(w: Int, h: Int?) {
        queue.options.resize = h.map { .exact(width: max(w, 1), height: max($0, 1)) } ?? .width(max(w, 1))
    }

    // MARK: Actions

    private func apply(_ preset: (inout ImageOptions) -> Void) { preset(&queue.options) }

    private func convert() {
        let options = queue.options
        queue.run { input, dir, _ in try await ImageEngine.convert(input, to: dir, options: options) }
    }
}
