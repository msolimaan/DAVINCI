import AppKit
import CleanerCore
import SwiftUI

@main
struct DaVinciCleanerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()
    @AppStorage(Preferences.showMenuBarKey) private var showMenuBarMonitor = true

    var body: some Scene {
        WindowGroup("DaVinci Cleaner", id: "main") {
            RootView()
                .environmentObject(state)
                .environmentObject(state.junk)
                .environmentObject(state.smartScan)
                .environmentObject(state.uninstaller)
                .environmentObject(state.spaceLens)
                .environmentObject(state.largeFiles)
                .environmentObject(state.duplicates)
                .environmentObject(state.maintenance)
                .environmentObject(state.loginItems)
                .environmentObject(state.monitor)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1040, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Scan") {
                ForEach(Module.allCases) { module in
                    Button(module.title) { state.show(module) }
                        .keyboardShortcut(shortcut(for: module), modifiers: .command)
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(state)
                .preferredColorScheme(.dark)
        }

        MenuBarExtra(isInserted: $showMenuBarMonitor) {
            MenuBarView()
                .environmentObject(state)
                .environmentObject(state.monitor)
                .preferredColorScheme(.dark)
        } label: {
            Image(systemName: "sparkles")
        }
        .menuBarExtraStyle(.window)
    }

    private func shortcut(for module: Module) -> KeyEquivalent {
        let index = Module.allCases.firstIndex(of: module) ?? 0
        return KeyEquivalent(Character(String(index + 1)))
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched with `swift run`, which starts the binary without an app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running so the menu bar monitor stays available.
        false
    }
}
