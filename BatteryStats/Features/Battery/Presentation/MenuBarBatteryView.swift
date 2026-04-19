import Observation
import SwiftUI

struct MenuBarBatteryView: View {
    @Bindable var monitor: BatteryMonitor
    @Bindable var preferences: PreferencesStore

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 12) {
            if let snapshot = monitor.snapshot {
                BatterySummaryGridView(
                    snapshot: snapshot,
                    compact: true,
                    temperatureUnitPreference: preferences.temperatureUnitPreference
                )
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

                SettingsLink {
                    Text("Settings")
                }

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
            .font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(width: 264)
        .onAppear {
            monitor.start()
        }

        if #available(macOS 15.0, *) {
            content.containerBackground(.ultraThinMaterial, for: .window)
        } else {
            content
        }
    }
}

struct MenuBarBatteryLabelView: View {
    let snapshot: BatterySnapshot?
    let displayMode: MenuBarDisplayMode

    var body: some View {
        let symbolName = snapshot?.batterySymbolName ?? "battery.0"
        let symbolTint = snapshot.map { BatterySummaryGridView.tint(for: $0.chargeTone) } ?? .secondary

        switch displayMode {
        case .iconOnly:
            Image(systemName: symbolName)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(symbolTint)
        case .iconAndPercentage:
            Label {
                Text(BatteryFormatting.percent(snapshot?.stateOfChargePercent))
            } icon: {
                Image(systemName: symbolName)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(symbolTint)
            }
                .monospacedDigit()
        case .iconAndHealth:
            Label {
                Text(BatteryFormatting.percent(snapshot?.healthPercent, decimals: 0))
            } icon: {
                Image(systemName: symbolName)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(symbolTint)
            }
                .monospacedDigit()
        case .iconAndFullCharge:
            Label {
                Text(abbreviatedCapacity(snapshot?.fullChargeCapacityMilliampHours))
            } icon: {
                Image(systemName: symbolName)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(symbolTint)
            }
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
