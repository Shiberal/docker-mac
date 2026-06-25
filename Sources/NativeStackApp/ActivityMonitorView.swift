import SwiftUI
import NativeStackCore

struct ActivityMonitorView: View {
    let containers: [ContainerRecord]

    private var running: [ContainerRecord] {
        containers.filter(\.state.isActive)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 16) {
                    summaryCard(title: "Running", value: "\(running.count)", icon: "play.circle.fill", color: .green)
                    summaryCard(title: "Total", value: "\(containers.count)", icon: "shippingbox", color: .blue)
                    summaryCard(title: "Stopped", value: "\(containers.count - running.count)", icon: "stop.circle", color: .secondary)
                }

                Text("Per-container CPU and memory charts will integrate with Apple's container stats API in a future release.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if !running.isEmpty {
                    Text("Running Containers")
                        .font(.headline)
                    ForEach(running) { container in
                        HStack {
                            StatusDot(isRunning: true)
                            VStack(alignment: .leading) {
                                Text(container.displayName)
                                Text(container.image)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("Active")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                        .padding(12)
                        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Activity Monitor")
    }

    private func summaryCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.largeTitle.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
    }
}
