import SwiftUI

struct SettingsView: View {
    @Bindable var preferences: PreferencesStore
    let monitor: BatteryMonitor

    @State private var launchAtLoginManager = LaunchAtLoginManager()
    @State private var launchAtLoginError: String?
    @State private var isUpdatingLaunchAtLogin = false

    var body: some View {
        Form {
            generalSection
            displaySection
            advancedSection
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 520)
    }

    private var generalSection: some View {
        Section("General") {
            Toggle(
                "Launch at Login",
                isOn: Binding(
                    get: { launchAtLoginManager.isEnabled },
                    set: { updateLaunchAtLogin($0) }
                )
            )
            .disabled(isUpdatingLaunchAtLogin)

            if isUpdatingLaunchAtLogin {
                ProgressView()
                    .controlSize(.small)
            }

            Text(launchAtLoginError ?? launchAtLoginManager.statusDescription)
                .font(.footnote)
                .foregroundStyle(launchAtLoginError == nil ? Color.secondary : Color.red)

            Toggle("Sync Preferences with iCloud", isOn: $preferences.isICloudSyncEnabled)

            Text(preferences.syncStatusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var displaySection: some View {
        Section("Display") {
            Picker("Menu Bar Display", selection: $preferences.menuBarDisplayMode) {
                ForEach(MenuBarDisplayMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            Picker("Temperature Unit", selection: $preferences.temperatureUnitPreference) {
                ForEach(TemperatureUnitPreference.allCases) { preference in
                    Text(preference.title).tag(preference)
                }
            }
        }
    }

    private var advancedSection: some View {
        Section("Advanced") {
            Toggle("Show Advanced Values", isOn: $preferences.showAdvancedValues)

            Button("Copy Raw Battery Snapshot") {
                monitor.copyRawSnapshot()
            }

            Button("Copy Parsed Battery Snapshot") {
                monitor.copyParsedSnapshot()
            }

            Button("Reset Settings") {
                preferences.reset()
            }
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        isUpdatingLaunchAtLogin = true
        defer {
            isUpdatingLaunchAtLogin = false
        }

        do {
            try launchAtLoginManager.setEnabled(enabled)
            preferences.launchAtLoginEnabled = launchAtLoginManager.isEnabled
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
            preferences.launchAtLoginEnabled = launchAtLoginManager.isEnabled
        }
    }
}

#Preview {
    SettingsView(preferences: PreferencesStore(), monitor: BatteryMonitor())
}
