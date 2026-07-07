import SwiftUI
import NativeStackClient

struct OnboardingView: View {
    @Environment(ContainerService.self) private var service
    let onComplete: () -> Void

    @State private var step = 0

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "shippingbox.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text("Welcome to NativeStack")
                    .font(.largeTitle.bold())
                Text("A native OrbStack-style manager for Apple's container tool")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            onboardingStepContent
                .frame(maxWidth: 480)

            HStack(spacing: 12) {
                if step > 0 {
                    Button("Back") { step -= 1 }
                }
                Spacer()
                if step < 2 {
                    Button("Skip") { onComplete() }
                        .foregroundStyle(.secondary)
                }
                Button(step < 2 ? "Continue" : "Get Started") {
                    if step < 2 {
                        step += 1
                    } else {
                        onComplete()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: 480)

            Spacer()
        }
        .padding(40)
        .task { await service.checkInstallation() }
    }

    private var installDetail: String {
        if service.isInstalled { return "Found on PATH" }
        if service.isInstallingToolkit { return service.installPhase.label }
        return "Will install automatically via Homebrew or Apple installer"
    }

    @ViewBuilder
    private var onboardingStepContent: some View {
        switch step {
        case 0:
            VStack(alignment: .leading, spacing: 12) {
                featureRow("shippingbox", "Native containers", "Built on Apple's Containerization framework — one lightweight VM per container.")
                featureRow("menubar.rectangle", "Menu bar control", "Start, stop, and monitor containers without leaving your workflow.")
                featureRow("network", "OrbStack-like UX", "Container list, images, logs, and activity monitor in a native SwiftUI app.")
            }
        case 1:
            VStack(alignment: .leading, spacing: 12) {
                Label("Prerequisites", systemImage: "checklist")
                    .font(.headline)

                prerequisiteRow(
                    title: "Apple Silicon Mac",
                    ok: true,
                    detail: "Required by Apple's container tool"
                )
                prerequisiteRow(
                    title: "macOS 26+",
                    ok: true,
                    detail: "Full networking support"
                )
                prerequisiteRow(
                    title: "container CLI",
                    ok: service.isInstalled,
                    detail: installDetail
                )

                if service.isInstallingToolkit {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(service.installPhase.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if !service.isInstalled {
                    Button("Install Automatically") {
                        Task { try? await service.installToolkit() }
                    }
                    .buttonStyle(.borderedProminent)

                    Link("Manual download", destination: URL(string: "https://github.com/apple/container/releases")!)
                        .font(.caption)
                }
            }
        default:
            VStack(alignment: .leading, spacing: 12) {
                Text("Quick start")
                    .font(.headline)
                Text("1. Install Apple's `container` tool")
                Text("2. Run `container system start`")
                Text("3. Pull an image: `nativestack image pull alpine:latest`")
                Text("4. Run a container: `nativestack run alpine:latest`")
                    .font(.body.monospaced())
            }
        }
    }

    private func featureRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
        }
    }

    private func prerequisiteRow(title: String, ok: Bool, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
