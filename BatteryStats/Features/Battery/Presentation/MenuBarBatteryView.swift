import AppKit
import Observation
import SwiftUI

struct MenuBarBatteryView: View {
    @Environment(\.openSettings) private var openSettings

    @Bindable var monitor: BatteryMonitor
    @Bindable var preferences: PreferencesStore
    let historyStore: BatteryHistoryStore

    var body: some View {
        VStack(spacing: 0) {
            BatterySurfaceView(monitor: monitor, preferences: preferences)
                .frame(minWidth: BatterySurfaceLayout.minimumWidth, alignment: .topLeading)

            Divider()

            HStack(spacing: 10) {
                Button {
                    monitor.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")

                Button {
                    monitor.copyParsedSnapshot()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy Snapshot")

                Button {
                    historyStore.copyCSV()
                } label: {
                    Image(systemName: "tablecells")
                }
                .disabled(historyStore.entries.isEmpty)
                .help("Copy History CSV")

                Spacer(minLength: 16)

                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .help("Quit")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .containerBackground(.thinMaterial, for: .window)
    }
}

struct MenuBarBatteryLabelView: View {
    let snapshot: BatterySnapshot?
    let displayMode: MenuBarDisplayMode

    var body: some View {
        let symbolName = snapshot?.batterySymbolName ?? "battery.0"
        let symbolTint = BatteryPresentationStyle.chargeTint(for: snapshot)

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
        case .iconAndTimeRemaining:
            Label {
                Text(BatteryFormatting.compactWidgetDuration(minutes: snapshot?.displayedTimeMinutes))
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
        case .iconAndTemperature:
            Label {
                Text(abbreviatedTemperature(snapshot?.temperatureCelsius))
            } icon: {
                Image(systemName: symbolName)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(symbolTint)
            }
                .monospacedDigit()
        case .iconAndPower:
            Label {
                Text(abbreviatedPower(snapshot?.activePowerWatts))
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

    private func abbreviatedTemperature(_ celsius: Double?) -> String {
        guard let celsius else {
            return "—"
        }

        return "\(celsius.formatted(.number.precision(.fractionLength(0))))°"
    }

    private func abbreviatedPower(_ watts: Double?) -> String {
        guard let watts else {
            return "—"
        }

        return "\(watts.formatted(.number.precision(.fractionLength(1))))W"
    }
}

#Preview {
    MenuBarBatteryView(monitor: {
        let monitor = BatteryMonitor()
        monitor.availabilityState = .available
        monitor.snapshot = .previewDischarging
        return monitor
    }(), preferences: PreferencesStore(), historyStore: BatteryHistoryStore())
}
