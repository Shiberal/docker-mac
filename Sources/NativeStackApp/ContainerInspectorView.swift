import SwiftUI
import NativeStackClient
import NativeStackCore

struct ContainerInspectorView: View {
    @Environment(ContainerService.self) private var service
    let container: ContainerRecord
    @Binding var tab: InspectorTab

    @State private var logsText = ""
    @State private var isLoadingLogs = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("Inspector", selection: $tab) {
                ForEach(InspectorTab.allCases) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            switch tab {
            case .info:
                infoTab
            case .logs:
                logsTab
            case .stats:
                statsTab
            }
        }
        .navigationTitle(container.displayName)
        .toolbar { containerToolbar }
    }

    @ToolbarContentBuilder
    private var containerToolbar: some ToolbarContent {
        ToolbarItemGroup {
            if container.state.isActive {
                Button("Stop") {
                    Task { try? await service.stopContainer(id: container.id) }
                }
            } else {
                Button("Start") {
                    Task { try? await service.startContainer(id: container.id) }
                }
            }

            Button("Remove", role: .destructive) {
                Task { try? await service.removeContainer(id: container.id, force: true) }
            }
        }
    }

    private var infoTab: some View {
        Form {
            Section("Container") {
                CopyableRow(label: "ID", value: container.id)
                CopyableRow(label: "Name", value: container.displayName)
                CopyableRow(label: "Image", value: container.image)
                LabeledContent("State", value: container.state.rawValue.capitalized)
                if let ip = container.ipAddress {
                    CopyableRow(label: "IP", value: ip)
                }
            }

            if !container.ports.isEmpty {
                Section("Ports") {
                    ForEach(container.ports, id: \.self) { port in
                        Text(port).font(.body.monospaced())
                    }
                }
            }

            Section("DNS") {
                CopyableRow(
                    label: "Local domain",
                    value: "\(container.displayName).nativestack.local"
                )
            }
        }
        .formStyle(.grouped)
    }

    private var logsTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Refresh Logs") { loadLogs() }
                if isLoadingLogs {
                    ProgressView().controlSize(.small)
                }
                Spacer()
            }
            .padding(.horizontal)

            ScrollView {
                Text(logsText.isEmpty ? "No logs yet." : logsText)
                    .font(.body.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding()
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .onAppear { loadLogs() }
        .onChange(of: container.id) { _, _ in loadLogs() }
    }

    private var statsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            MetricCard(title: "CPU", value: "—", subtitle: "Requires container inspect API")
            MetricCard(title: "Memory", value: "—", subtitle: "Polling via container stats")
            Text("Full resource monitoring will use `container inspect` stats when available.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private func loadLogs() {
        isLoadingLogs = true
        Task {
            defer { isLoadingLogs = false }
            if let text = try? await service.logs(for: container.id) {
                logsText = text
            } else {
                logsText = "Unable to load logs."
            }
        }
    }
}

struct CopyableRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            LabeledContent(label, value: value)
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold())
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}
