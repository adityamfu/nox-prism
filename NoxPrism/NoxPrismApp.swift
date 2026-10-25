import SwiftUI

@main
struct NoxPrismApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 900, minHeight: 600)
                .preferredColorScheme(.dark) // dark-only in v1
                .tint(.signalViolet)
        }
        .windowResizability(.contentMinSize)
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case image = "Image", video = "Video", color = "Color Picker"

    var id: Self { self }
    var symbol: String {
        switch self {
        case .image: "photo"
        case .video: "film"
        case .color: "eyedropper"
        }
    }
}

struct RootView: View {
    @State private var section: AppSection? = .image
    @State private var images = JobQueue(options: ImageOptions(), accepts: ImageSection.accepts)
    @State private var videos = JobQueue(options: VideoOptions(), accepts: VideoSection.accepts)

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $section) { section in
                Label(section.rawValue, systemImage: section.symbol).tag(section)
            }
            .navigationSplitViewColumnWidth(200)
        } detail: {
            switch section ?? .image {
            case .image: ImageSection(queue: images)
            case .video: VideoSection(queue: videos)
            case .color: ColorPickerSection()
            }
        }
    }
}
