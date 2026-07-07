import SwiftUI
import NativeStackClient
import NativeStackCore
import AppKit

@main
struct NativeStackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var service = ContainerService()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        MenuBarExtra("NativeStack", systemImage: menuBarIcon) {
            MenuBarRootView()
                .environment(service)
                .activatesWindowOnAppear()
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
            .activatesWindowOnAppear()
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
                .activatesWindowOnAppear()
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

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows where window.canBecomeKey {
                window.makeKeyAndOrderFront(nil)
                return true
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }
}
