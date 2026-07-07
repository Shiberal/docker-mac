import SwiftUI
import NativeStackClient
import NativeStackCore

struct MenuBarRootView: View {
    @Environment(ContainerService.self) private var service
    @Environment(\.openWindow) private var openWindow
    @AppStorage("autoRefresh") private var autoRefresh = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusHeader
            Divider()
            containerSection
            Divider()
            actionsFooter
        }
        .frame(width: 320)
        .task { await service.refresh(all: true) }
        .onReceive(Timer.publish(every: 10, on: .main, in: .common).autoconnect()) { _ in
            guard autoRefresh else { return }
            Task { await service.refresh(all: false) }
        }
    }

    private var statusHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("NativeStack")
                    .font(.headline)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            EngineStatusDot(state: service.systemStatus.engineState)
        }
        .padding()
    }

    private var statusText: String {
        if !service.isInstalled {
            return "container CLI not installed"
        }
        switch service.systemStatus.engineState {
        case .running:
            return "\(service.systemStatus.runningContainers) running"
        case .stopped:
            return "Engine stopped"
        case .notInstalled:
            return "Checking installation…"
        case .starting:
            return "Starting…"
        case .error:
            return service.lastError ?? "Error"
        }
    }

    @ViewBuilder
    private var containerSection: some View {
        if service.containers.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "shippingbox")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("No containers")
                    .font(.headline)
                Text("Pull an image and run a container to get started.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .padding(.horizontal)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(service.containers) { container in
                        MenuBarContainerRow(container: container)
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 280)
        }
    }

    private var actionsFooter: some View {
        VStack(spacing: 8) {
            if service.systemStatus.engineState == .stopped {
                Button("Start Engine") {
                    Task { try? await service.startEngine() }
                }
                .buttonStyle(.borderedProminent)
            }

            if !service.isInstalled {
                if service.isInstallingToolkit {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(service.installPhase.label)
                            .font(.caption)
                    }
                } else {
                    Button("Install Container Toolkit") {
                        Task { try? await service.installToolkit() }
                    }
                }
            }

            Button("Open Dashboard") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }

            Button("Quit NativeStack") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
    }
}

struct MenuBarContainerRow: View {
    @Environment(ContainerService.self) private var service
    let container: ContainerRecord

    var body: some View {
        HStack {
            StatusDot(isRunning: container.state.isActive)
            VStack(alignment: .leading, spacing: 2) {
                Text(container.displayName)
                    .font(.body.weight(.medium))
                Text(container.image)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Menu {
                if container.state.isActive {
                    Button("Stop") {
                        Task { try? await service.stopContainer(id: container.id) }
                    }
                } else {
                    Button("Start") {
                        Task { try? await service.startContainer(id: container.id) }
                    }
                }
                Button("Copy ID") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(container.id, forType: .string)
                }
                Divider()
                Button("Remove", role: .destructive) {
                    Task { try? await service.removeContainer(id: container.id, force: true) }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct EngineStatusDot: View {
    let state: EngineState

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
    }

    private var color: Color {
        switch state {
        case .running: .green
        case .starting: .yellow
        case .stopped: .secondary
        case .error, .notInstalled: .red
        }
    }
}

struct StatusDot: View {
    let isRunning: Bool

    var body: some View {
        Circle()
            .fill(isRunning ? Color.green : Color.secondary)
            .frame(width: 8, height: 8)
    }
}
