import SwiftUI
import NativeStackCore

struct ContainerListView: View {
    let containers: [ContainerRecord]
    @Binding var selectedID: ContainerRecord.ID?
    @Binding var showAll: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Filter", selection: $showAll) {
                    Text("Running").tag(false)
                    Text("All").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
                Spacer()
                Text("\(containers.count) containers")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .padding()

            if containers.isEmpty {
                ContentUnavailableView(
                    "No containers",
                    systemImage: "shippingbox",
                    description: Text("Run `nativestack run alpine:latest` or pull an image.")
                )
            } else {
                Table(containers, selection: $selectedID) {
                    TableColumn("") { container in
                        StatusDot(isRunning: container.state.isActive)
                    }
                    .width(24)

                    TableColumn("Name") { container in
                        Text(container.displayName)
                    }

                    TableColumn("Image") { container in
                        Text(container.image)
                            .foregroundStyle(.secondary)
                    }

                    TableColumn("State") { container in
                        Text(container.state.rawValue.capitalized)
                            .foregroundStyle(container.state.isActive ? .green : .secondary)
                    }

                    TableColumn("Ports") { container in
                        Text(container.ports.joined(separator: ", "))
                            .font(.caption.monospaced())
                    }
                }
            }
        }
        .navigationTitle("Containers")
    }
}
