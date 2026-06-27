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
                    if monitor.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.62)
                            .frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(monitor.isRefreshing)
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
        let symbolName = snapshot?.batterySymbolName ?? "questionmark"
        let symbolTint = BatteryPresentationStyle.chargeTint(for: snapshot)
        let value = displayValue

        HStack(spacing: value == nil ? 0 : 3) {
            Image(systemName: symbolName)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(symbolTint)

            if let value {
                Text(value)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .monospacedDigit()
        .accessibilityLabel(accessibilityLabel)
    }

    private var displayValue: String? {
        switch displayMode {
        case .iconOnly:
            return nil
        case .iconAndPercentage:
            return abbreviatedPercent(snapshot?.stateOfChargePercent)
        case .iconAndTimeRemaining:
            return BatteryFormatting.compactWidgetDuration(minutes: snapshot?.displayedTimeMinutes)
        case .iconAndHealth:
            return abbreviatedPercent(snapshot?.healthPercent)
        case .iconAndFullCharge:
            return abbreviatedCapacity(snapshot?.fullChargeCapacityMilliampHours)
        case .iconAndTemperature:
            return abbreviatedTemperature(snapshot?.temperatureCelsius)
        case .iconAndPower:
            return abbreviatedPower(snapshot?.activePowerWatts)
        }
    }

    private var accessibilityLabel: String {
        switch displayMode {
        case .iconOnly:
            return snapshot?.statusDisplayTitle ?? "Battery status unavailable"
        case .iconAndPercentage:
            return "Battery \(BatteryFormatting.percent(snapshot?.stateOfChargePercent))"
        case .iconAndTimeRemaining:
            return "Battery time \(BatteryFormatting.duration(minutes: snapshot?.displayedTimeMinutes))"
        case .iconAndHealth:
            return "Battery health \(BatteryFormatting.percent(snapshot?.healthPercent, decimals: 0))"
        case .iconAndFullCharge:
            return "Battery full charge capacity \(BatteryFormatting.milliampHours(snapshot?.fullChargeCapacityMilliampHours))"
        case .iconAndTemperature:
            return "Battery temperature \(BatteryFormatting.temperature(snapshot?.temperatureCelsius, unitPreference: .celsius))"
        case .iconAndPower:
            return "Battery power \(BatteryFormatting.watts(snapshot?.activePowerWatts))"
        }
    }

    private func abbreviatedPercent(_ value: Double?) -> String {
        guard let value else {
            return "—"
        }

        let clamped = max(0, min(100, value))
        return "\(clamped.formatted(.number.precision(.fractionLength(0))))%"
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
