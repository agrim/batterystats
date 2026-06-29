import AppKit
import SwiftUI

enum SettingsLayout {
    static let contentWidth: CGFloat = 520
    static let contentPadding: CGFloat = 20
    static let minimumWindowWidth: CGFloat = contentWidth + (contentPadding * 2)
}

struct SettingsView: View {
    @Bindable var preferences: PreferencesStore
    let monitor: BatteryMonitor
    let historyStore: BatteryHistoryStore

    @State private var launchAtLoginState = LaunchAtLoginSettingsModel()
    @State private var alertSettings = BatteryAlertSettingsModel()

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
        .frame(width: SettingsLayout.contentWidth)
        .padding(SettingsLayout.contentPadding)
        .onAppear {
            refreshExternalSettingsState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshExternalSettingsState()
        }
    }

    private var generalSection: some View {
        Section("General") {
            Toggle(
                "Launch at Login",
                isOn: Binding(
                    get: { launchAtLoginState.isEnabled },
                    set: { updateLaunchAtLogin($0) }
                )
            )
            .disabled(launchAtLoginState.isUpdating)

            if launchAtLoginState.isUpdating {
                ProgressView()
                    .controlSize(.small)
            }

            Text(launchAtLoginState.errorMessage ?? launchAtLoginState.statusDescription)
                .font(.footnote)
                .foregroundStyle(launchAtLoginState.errorMessage == nil ? Color.secondary : Color.red)

            Toggle("Sync Preferences with iCloud", isOn: $preferences.isICloudSyncEnabled)
                .disabled(preferences.isICloudSyncAvailable == false)

            Text(preferences.syncStatusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var displaySection: some View {
        Section("Display") {
            Picker("Menu Bar Display", selection: menuBarDisplayPreferenceBinding(\.menuBarDisplayMode)) {
                ForEach(MenuBarDisplayMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            Picker("Temperature Unit", selection: menuBarDisplayPreferenceBinding(\.temperatureUnitPreference)) {
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
            Toggle("Low Battery", isOn: alertBinding(\.isLowBatteryAlertEnabled))
            Toggle("Charge Complete", isOn: alertBinding(\.isChargeCompleteAlertEnabled))
            Toggle("High Temperature", isOn: alertBinding(\.isHighTemperatureAlertEnabled))

            if alertSettings.isResolvingAuthorization {
                ProgressView()
                    .controlSize(.small)
            }

            Text(alertSettings.statusDescription)
                .font(.footnote)
                .foregroundStyle(alertSettings.authorizationStatus == .denied ? Color.red : Color.secondary)
        }
    }

    private var advancedSection: some View {
        Section("Advanced") {
            Toggle("Show Advanced Values", isOn: $preferences.showAdvancedValues)

            Toggle("Keep Battery History", isOn: $preferences.isHistoryEnabled)

            Toggle("Sync History with iCloud", isOn: $preferences.isHistoryICloudSyncEnabled)
                .disabled(preferences.canEnableHistoryICloudSync == false)

            HistoryStatsView(
                stats: historyStore.stats,
                unitPreference: preferences.temperatureUnitPreference,
                unitResolutionToken: preferences.temperatureUnitResolutionToken,
                emptyText: historyStore.summaryText
            )

            Button {
                monitor.copyRawSnapshot()
            } label: {
                HStack(spacing: 6) {
                    if monitor.isCopyingRawSnapshot {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Text("Copy Raw Battery Snapshot")
                }
            }
            .disabled(monitor.isCopyingRawSnapshot)

            Button("Copy Parsed Battery Snapshot") {
                monitor.copyParsedSnapshot()
            }
            .disabled(monitor.canCopyParsedSnapshot == false)

            Button("Copy History CSV") {
                historyStore.copyCSV()
            }
            .disabled(historyStore.entries.isEmpty)

            Button("Reset Settings") {
                resetSettings()
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
        launchAtLoginState.setEnabled(enabled)
        preferences.launchAtLoginEnabled = launchAtLoginState.isEnabled
    }

    private func resetSettings() {
        launchAtLoginState.disableForReset()
        alertSettings.cancelPendingAlertEnables()
        preferences.reset()
        preferences.launchAtLoginEnabled = launchAtLoginState.isEnabled
    }

    private func refreshLaunchAtLoginState() {
        launchAtLoginState.refresh()
        preferences.launchAtLoginEnabled = launchAtLoginState.isEnabled
    }

    private func refreshExternalSettingsState() {
        preferences.refreshICloudSyncAvailability()
        refreshLaunchAtLoginState()
        alertSettings.refreshAuthorizationStatus(preferences: preferences)
    }

    private func menuBarDisplayPreferenceBinding<Value>(
        _ keyPath: ReferenceWritableKeyPath<PreferencesStore, Value>
    ) -> Binding<Value> where Value: Equatable {
        Binding(
            get: {
                preferences[keyPath: keyPath]
            },
            set: { value in
                guard preferences[keyPath: keyPath] != value else {
                    preferences.invalidateMenuBarDisplayPreferences()
                    return
                }

                preferences[keyPath: keyPath] = value
            }
        )
    }

    private func alertBinding(_ keyPath: ReferenceWritableKeyPath<PreferencesStore, Bool>) -> Binding<Bool> {
        Binding(
            get: {
                preferences[keyPath: keyPath]
            },
            set: { enabled in
                Task { @MainActor in
                    await alertSettings.setAlertEnabled(
                        enabled,
                        preferences: preferences,
                        keyPath: keyPath
                    )
                }
            }
        )
    }
}

#Preview {
    SettingsView(preferences: PreferencesStore(), monitor: BatteryMonitor(), historyStore: BatteryHistoryStore())
}
