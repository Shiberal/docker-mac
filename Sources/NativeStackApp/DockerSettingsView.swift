import SwiftUI
import NativeStackClient
import NativeStackCore

struct DockerSettingsView: View {
    @Environment(ContainerService.self) private var service
    @State private var dockerStatus = DockerCompatibilityStatus()

    var body: some View {
        Form {
            Section("Docker compatibility") {
                Text("Uses Socktainer to expose a Docker-compatible API on top of Apple's container runtime.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Socktainer", value: dockerStatus.socktainerRunning ? "Running" : "Stopped")
                LabeledContent("Docker CLI", value: dockerStatus.dockerCLIInstalled ? "Installed" : "Missing")
                LabeledContent("Compose", value: dockerStatus.composeInstalled ? "Installed" : "Missing")
                LabeledContent("Buildx", value: dockerStatus.buildxInstalled ? "Installed" : "Missing")
                LabeledContent("Ready", value: dockerStatus.isReady ? "Yes" : "No")

                if service.isEnablingDocker {
                    LabeledContent("Setup") {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text(service.dockerPhase.label)
                        }
                    }
                } else {
                    Button("Enable Docker & Compose") {
                        Task {
                            try? await service.enableDockerCompatibility()
                            dockerStatus = await service.dockerStatus
                        }
                    }
                }
            }

            Section("Shell setup") {
                Text(dockerStatus.dockerHost)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                Text("Run in your shell:")
                    .font(.caption)
                Text("eval \"$(nativestack docker env)\"")
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }

            Section("Examples") {
                Text("""
                nativestack compose up -d
                nativestack docker ps
                docker compose down
                """)
                .font(.caption.monospaced())
                .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .task {
            dockerStatus = await service.dockerStatus
        }
    }
}
