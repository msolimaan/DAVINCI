import CleanerCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            SafetySettings()
                .tabItem { Label("Safety", systemImage: "checkmark.shield") }
        }
        .frame(width: 520, height: 400)
    }
}

private struct GeneralSettings: View {
    @EnvironmentObject private var state: AppState
    @AppStorage(Preferences.removalModeKey) private var removalMode: RemovalMode = .moveToTrash
    @AppStorage(Preferences.showMenuBarKey) private var showMenuBar = true

    var body: some View {
        Form {
            Section("When cleaning") {
                Picker("Removed items", selection: $removalMode) {
                    ForEach(RemovalMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                Text(removalMode.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Menu bar") {
                Toggle("Show CPU, memory and disk in the menu bar", isOn: $showMenuBar)
            }
            Section("Permissions") {
                LabeledContent("Full Disk Access") {
                    HStack {
                        Text(state.hasFullDiskAccess ? "Granted" : "Not granted")
                            .foregroundStyle(state.hasFullDiskAccess ? Color.green : Color.orange)
                        Button("Open Settings", action: FullDiskAccess.openSettings)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct SafetySettings: View {
    var body: some View {
        Form {
            Section("How DaVinci Cleaner keeps you safe") {
                Label("Nothing is removed until you review it and press the button.", systemImage: "hand.raised")
                Label("Every item is re-checked right before removal and must sit inside the folder it was found in.", systemImage: "checkmark.shield")
                Label("Items go to the Trash by default, so you can put them back.", systemImage: "trash")
                Label("Apple's built-in apps are never offered for uninstalling.", systemImage: "apple.logo")
            }
            Section("Never touched") {
                Text(
                    (SafetyGuard.protectedSystemPaths + SafetyGuard.sealedHomeFolders.map { "~/" + $0 })
                        .joined(separator: "  ·  ")
                )
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
    }
}
