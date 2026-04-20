import Observation
import SwiftUI

struct MenuBarBatteryView: View {
    @Bindable var monitor: BatteryMonitor
    @Bindable var preferences: PreferencesStore

    var body: some View {
        BatterySurfaceView(monitor: monitor, preferences: preferences)
            .frame(minWidth: BatterySurfaceLayout.minimumWidth, alignment: .topLeading)
            .containerBackground(.thinMaterial, for: .window)
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
