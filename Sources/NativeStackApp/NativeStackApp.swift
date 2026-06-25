import SwiftUI
import NativeStackClient
import NativeStackCore

@main
struct NativeStackApp: App {
    @State private var service = ContainerService()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        MenuBarExtra("NativeStack", systemImage: menuBarIcon) {
            MenuBarRootView()
                .environment(service)
        }
        .menuBarExtraStyle(.window)

        WindowGroup("NativeStack", id: "main") {
            Group {
                if hasCompletedOnboarding {
                    MainWindowView()
                } else {
                    OnboardingView {
                        hasCompletedOnboarding = true
                    }
                }
            }
            .environment(service)
            .frame(minWidth: 900, minHeight: 560)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Containers") {
                Button("Refresh") {
                    Task { await service.refresh(all: true) }
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Start Engine") {
                    Task { try? await service.startEngine() }
                }

                Button("Stop Engine") {
                    Task { try? await service.stopEngine() }
                }
            }
        }

        Settings {
            SettingsView()
                .environment(service)
        }
    }

    private var menuBarIcon: String {
        switch service.systemStatus.engineState {
        case .running: "shippingbox.fill"
        case .starting: "shippingbox"
        case .stopped, .error: "shippingbox"
        case .notInstalled: "exclamationmark.triangle"
        }
    }
}
