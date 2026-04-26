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

private struct HistoryStatsView: View {
    let stats: BatteryHistoryStats?
    let unitPreference: TemperatureUnitPreference
    let emptyText: String

    var body: some View {
        Group {
            if let stats {
                VStack(alignment: .leading, spacing: 5) {
                    HistoryStatRow(title: "History", value: "\(stats.sampleCount) samples")
                    HistoryStatRow(title: "Latest", value: dateText(stats.latestTimestamp))
                    HistoryStatRow(title: "Captured", value: capturedText(for: stats))
                    HistoryStatRow(title: "Power", value: powerText(for: stats))
                    HistoryStatRow(
                        title: "Charge",
                        value: percentRangeText(
                            minimum: stats.minimumChargePercent,
                            maximum: stats.maximumChargePercent
                        )
                    )
                    HistoryStatRow(
                        title: "Temperature",
                        value: temperatureRangeText(
                            minimum: stats.minimumTemperatureCelsius,
                            maximum: stats.maximumTemperatureCelsius
                        )
                    )
                }
                .font(.footnote)
            } else {
                Text(emptyText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func capturedText(for stats: BatteryHistoryStats) -> String {
        if Calendar.current.isDate(stats.firstTimestamp, inSameDayAs: stats.latestTimestamp) {
            return "\(dateText(stats.firstTimestamp)) - \(timeText(stats.latestTimestamp))"
        }

        return "\(dateText(stats.firstTimestamp)) - \(dateText(stats.latestTimestamp))"
    }

    private func powerText(for stats: BatteryHistoryStats) -> String {
        switch (stats.averagePowerWatts, stats.peakPowerWatts) {
        case let (.some(average), .some(peak)):
            return "Avg \(BatteryFormatting.watts(average)), Peak \(BatteryFormatting.watts(peak))"
        case let (.some(average), .none):
            return "Avg \(BatteryFormatting.watts(average))"
        case let (.none, .some(peak)):
            return "Peak \(BatteryFormatting.watts(peak))"
        case (.none, .none):
            return "Unavailable"
        }
    }

    private func percentRangeText(minimum: Double?, maximum: Double?) -> String {
        guard let minimum, let maximum else {
            return "Unavailable"
        }

        let minimumText = BatteryFormatting.percent(minimum)
        let maximumText = BatteryFormatting.percent(maximum)
        guard minimumText != maximumText else {
            return minimumText
        }

        return "\(minimumText) - \(maximumText)"
    }

    private func temperatureRangeText(minimum: Double?, maximum: Double?) -> String {
        guard let minimum, let maximum else {
            return "Unavailable"
        }

        let minimumText = BatteryFormatting.temperature(minimum, unitPreference: unitPreference)
        let maximumText = BatteryFormatting.temperature(maximum, unitPreference: unitPreference)
        guard minimumText != maximumText else {
            return minimumText
        }

        return "\(minimumText) - \(maximumText)"
    }

    private func dateText(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    private func timeText(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }
}

private struct HistoryStatRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            Text(value)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .lineLimit(2)
                .layoutPriority(1)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    SettingsView(preferences: PreferencesStore(), monitor: BatteryMonitor(), historyStore: BatteryHistoryStore())
}
