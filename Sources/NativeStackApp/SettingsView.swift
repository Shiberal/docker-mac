import SwiftUI
import NativeStackClient

struct SettingsView: View {
    @Environment(ContainerService.self) private var service
    @AppStorage("autoRefresh") private var autoRefresh = true
    @AppStorage("showStoppedInMenuBar") private var showStoppedInMenuBar = false
    @AppStorage("dnsDomain") private var dnsDomain = "nativestack.local"

    var body: some View {
        TabView {
            Form {
                Section("Engine") {
                    LabeledContent("Status", value: service.systemStatus.engineState.rawValue.capitalized)
                    if let version = service.systemStatus.version {
                        LabeledContent("Version", value: version)
                    }
                    HStack {
                        Button("Start Engine") {
                            Task { try? await service.startEngine() }
                        }
                        Button("Stop Engine") {
                            Task { try? await service.stopEngine() }
                        }
                    }
                }

                Section("About") {
                    LabeledContent("Backend", value: "Apple container CLI")
                    LabeledContent("Container tool", value: service.isInstalled ? "Installed" : "Not found")
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gearshape") }

            Form {
                Section("Display") {
                    Toggle("Auto-refresh lists", isOn: $autoRefresh)
                    Toggle("Show stopped containers in menu bar", isOn: $showStoppedInMenuBar)
                }

                Section("Networking") {
                    TextField("Local DNS suffix", text: $dnsDomain)
                    Text("Containers are reachable at `<name>.\(dnsDomain)` when DNS is configured.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Network", systemImage: "network") }

            Form {
                Section("CLI") {
                    Text("Use `nativestack` for Docker-familiar commands:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("""
                    nativestack system start
                    nativestack image pull alpine:latest
                    nativestack run -p 8080:80 nginx:latest
                    nativestack ps
                    """)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                }
            }
            .tabItem { Label("Advanced", systemImage: "terminal") }
        }
        .frame(width: 480, height: 320)
        .task { await service.refresh(all: true) }
    }
}
