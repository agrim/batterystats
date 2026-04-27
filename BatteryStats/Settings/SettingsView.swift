import SwiftUI

struct SettingsView: View {
    @Bindable var preferences: PreferencesStore
    let monitor: BatteryMonitor
    let historyStore: BatteryHistoryStore

    @State private var launchAtLoginManager = LaunchAtLoginManager()
    @State private var launchAtLoginError: String?
    @State private var isUpdatingLaunchAtLogin = false

    var body: some View {
        Form {
            generalSection
            displaySection
            updatesSection
            alertsSection
            advancedSection
            aboutSection
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

    private var updatesSection: some View {
        Section("Updates") {
            Picker("Refresh Cadence", selection: $preferences.refreshCadencePreference) {
                ForEach(RefreshCadencePreference.allCases) { cadence in
                    Text(cadence.title).tag(cadence)
                }
            }

            Picker("Energy Shift Trigger", selection: $preferences.energyChangeSensitivity) {
                ForEach(EnergyChangeSensitivity.allCases) { sensitivity in
                    Text(sensitivity.title).tag(sensitivity)
                }
            }

            Text("Large charging or discharge-rate changes can refresh BatteryStats between scheduled updates.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var alertsSection: some View {
        Section("Alerts") {
            Toggle("Low Battery", isOn: $preferences.isLowBatteryAlertEnabled)
            Toggle("Charge Complete", isOn: $preferences.isChargeCompleteAlertEnabled)
            Toggle("High Temperature", isOn: $preferences.isHighTemperatureAlertEnabled)
        }
    }

    private var advancedSection: some View {
        Section("Advanced") {
            Toggle("Show Advanced Values", isOn: $preferences.showAdvancedValues)

            Toggle("Keep Battery History", isOn: $preferences.isHistoryEnabled)

            Toggle("Sync History with iCloud", isOn: $preferences.isHistoryICloudSyncEnabled)
                .disabled(preferences.isHistoryEnabled == false)

            HistoryStatsView(
                stats: historyStore.stats,
                unitPreference: preferences.temperatureUnitPreference,
                emptyText: historyStore.summaryText
            )

            Button("Copy Raw Battery Snapshot") {
                monitor.copyRawSnapshot()
            }

            Button("Copy Parsed Battery Snapshot") {
                monitor.copyParsedSnapshot()
            }

            Button("Copy History CSV") {
                historyStore.copyCSV()
            }
            .disabled(historyStore.entries.isEmpty)

            Button("Reset Settings") {
                preferences.reset()
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            Text(ReleaseVersion.from(Bundle.main.infoDictionary)?.displayText ?? "Version unavailable")
                .font(.footnote)
                .foregroundStyle(.secondary)
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
    SettingsView(preferences: PreferencesStore(), monitor: BatteryMonitor(), historyStore: BatteryHistoryStore())
}
