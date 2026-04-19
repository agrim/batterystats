import Observation
import SwiftUI

struct MenuBarBatteryView: View {
    @Bindable var monitor: BatteryMonitor
    @Bindable var preferences: PreferencesStore

    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let snapshot = monitor.snapshot {
                VStack(alignment: .leading, spacing: 8) {
                    Label(snapshot.powerState.displayTitle, systemImage: snapshot.powerState.symbolName)
                        .font(.headline)

                    Text(BatteryFormatting.summaryText(for: snapshot))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Divider()

                    MetricRowView(title: "Battery", value: BatteryFormatting.percent(snapshot.stateOfChargePercent))
                    MetricRowView(title: "Current charge", value: BatteryFormatting.milliampHours(snapshot.currentChargeMilliampHours))
                    MetricRowView(title: "Time", value: BatteryFormatting.duration(minutes: snapshot.displayedTimeMinutes))
                    MetricRowView(title: "Temperature", value: BatteryFormatting.temperature(snapshot.temperatureCelsius, unitPreference: preferences.temperatureUnitPreference))
                    MetricRowView(title: "Cycle count", value: snapshot.cycleCount.map(String.init) ?? "Unavailable")
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Battery Unavailable", systemImage: "battery.0")
                        .font(.headline)

                    Text("BatteryStats is designed for Mac laptops with an internal battery.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack {
                Button("Open BatteryStats") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }

                Spacer()

                Button("Refresh") {
                    monitor.refresh()
                }
            }

            HStack {
                Button("Settings") {
                    openSettings()
                }

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(16)
        .frame(width: 320)
        .onAppear {
            monitor.start()
        }
    }
}

struct MenuBarBatteryLabelView: View {
    let snapshot: BatterySnapshot?
    let displayMode: MenuBarDisplayMode

    var body: some View {
        let symbolName = snapshot?.powerState.symbolName ?? "battery.0"

        switch displayMode {
        case .iconOnly:
            Image(systemName: symbolName)
        case .iconAndPercentage:
            Label(BatteryFormatting.percent(snapshot?.stateOfChargePercent), systemImage: symbolName)
                .monospacedDigit()
        case .iconAndHealth:
            Label(BatteryFormatting.percent(snapshot?.healthPercent, decimals: 0), systemImage: symbolName)
                .monospacedDigit()
        case .iconAndFullCharge:
            Label(abbreviatedCapacity(snapshot?.fullChargeCapacityMilliampHours), systemImage: symbolName)
                .monospacedDigit()
        }
    }

    private func abbreviatedCapacity(_ milliampHours: Int?) -> String {
        guard let milliampHours else {
            return "—"
        }

        let ampHours = Double(milliampHours) / 1_000
        return "\(ampHours.formatted(.number.precision(.fractionLength(1))))Ah"
    }
}

#Preview {
    MenuBarBatteryView(monitor: {
        let monitor = BatteryMonitor()
        monitor.availabilityState = .available
        monitor.snapshot = .previewDischarging
        return monitor
    }(), preferences: PreferencesStore())
}
