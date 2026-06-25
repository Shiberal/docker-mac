import SwiftUI
import NativeStackClient
import NativeStackCore

struct MainWindowView: View {
    @Environment(ContainerService.self) private var service
    @State private var selection: SidebarSection? = .containers
    @State private var selectedContainerID: ContainerRecord.ID?
    @State private var selectedImageID: ImageRecord.ID?
    @State private var inspectorTab: InspectorTab = .info
    @State private var searchText = ""
    @State private var showAllContainers = true
    @State private var pullImageReference = ""
    @State private var showPullSheet = false

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } content: {
            contentColumn
        } detail: {
            inspectorColumn
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar { mainToolbar }
        .searchable(text: $searchText, prompt: "Search")
        .sheet(isPresented: $showPullSheet) { pullImageSheet }
        .task { await service.refresh(all: true) }
        .onReceive(Timer.publish(every: 4, on: .main, in: .common).autoconnect()) { _ in
            Task { await service.refresh(all: showAllContainers) }
        }
    }

    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                Task { await service.refresh(all: showAllContainers) }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }

            if selection == .images {
                Button("Pull Image") { showPullSheet = true }
            }
        }
    }

    @ViewBuilder
    private var contentColumn: some View {
        switch selection {
        case .containers, .none:
            ContainerListView(
                containers: filteredContainers,
                selectedID: $selectedContainerID,
                showAll: $showAllContainers
            )
        case .images:
            ImageListView(images: filteredImages, selectedID: $selectedImageID)
        case .activity:
            ActivityMonitorView(containers: service.containers)
        }
    }

    @ViewBuilder
    private var inspectorColumn: some View {
        switch selection {
        case .containers, .none:
            if let container = selectedContainer {
                ContainerInspectorView(container: container, tab: $inspectorTab)
            } else {
                ContentUnavailableView("Select a container", systemImage: "shippingbox")
            }
        case .images:
            if let image = selectedImage {
                ImageDetailView(image: image)
            } else {
                ContentUnavailableView("Select an image", systemImage: "cube")
            }
        case .activity:
            ContentUnavailableView(
                "Activity Monitor",
                systemImage: "chart.xyaxis.line",
                description: Text("Select a container to view per-container stats.")
            )
        }
    }

    private var pullImageSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pull Image")
                .font(.title2.bold())
            TextField("e.g. alpine:latest", text: $pullImageReference)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { showPullSheet = false }
                Button("Pull") {
                    let ref = pullImageReference
                    showPullSheet = false
                    pullImageReference = ""
                    Task {
                        try? await service.pullImage(ref)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(pullImageReference.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    private var filteredContainers: [ContainerRecord] {
        service.containers.filter { c in
            guard searchText.isEmpty else {
                let q = searchText.lowercased()
                return c.displayName.lowercased().contains(q)
                    || c.image.lowercased().contains(q)
                    || c.id.lowercased().contains(q)
            }
            return true
        }
    }

    private var filteredImages: [ImageRecord] {
        service.images.filter { i in
            guard searchText.isEmpty else {
                let q = searchText.lowercased()
                return i.reference.lowercased().contains(q) || i.id.lowercased().contains(q)
            }
            return true
        }
    }

    private var selectedContainer: ContainerRecord? {
        guard let selectedContainerID else { return nil }
        return service.containers.first { $0.id == selectedContainerID }
    }

    private var selectedImage: ImageRecord? {
        guard let selectedImageID else { return nil }
        return service.images.first { $0.id == selectedImageID }
    }
}

enum SidebarSection: String, CaseIterable, Identifiable {
    case containers = "Containers"
    case images = "Images"
    case activity = "Activity"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .containers: "shippingbox"
        case .images: "cube"
        case .activity: "chart.xyaxis.line"
        }
    }
}

enum InspectorTab: String, CaseIterable, Identifiable {
    case info = "Info"
    case logs = "Logs"
    case stats = "Stats"

    var id: String { rawValue }
}

struct SidebarView: View {
    @Binding var selection: SidebarSection?

    var body: some View {
        List(SidebarSection.allCases, selection: $selection) { section in
            Label(section.rawValue, systemImage: section.icon)
        }
        .navigationTitle("NativeStack")
        .listStyle(.sidebar)
    }
}
