import Observation
import SwiftUI

struct BatteryDashboardView: View {
    @Bindable var monitor: BatteryMonitor
    @Bindable var preferences: PreferencesStore

    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Group {
            switch monitor.availabilityState {
            case .loading:
                ProgressView("Reading battery information…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .unsupported:
                UnsupportedBatteryView()
            case .available:
                if let snapshot = monitor.snapshot {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            overviewHeader(snapshot)
                            heroMetric(snapshot)
                            chargeSection(snapshot)
                            capacitySection(snapshot)
                            electricalSection(snapshot)

                            if let statusMessage = monitor.statusMessage {
                                Text(statusMessage)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 4)
                            }
                        }
                        .padding(20)
                    }
                } else {
                    UnsupportedBatteryView()
                }
            }
        }
        .navigationTitle("BatteryStats")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    monitor.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }

                Button {
                    openSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .onAppear {
            monitor.start()
        }
    }

    @ViewBuilder
    private func overviewHeader(_ snapshot: BatterySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Battery")
                .font(.title2.weight(.semibold))

            HStack(spacing: 8) {
                Text(snapshot.powerState.displayTitle)
                Text("•")
                    .foregroundStyle(.tertiary)
                Text(BatteryFormatting.percent(snapshot.stateOfChargePercent))
                Text("•")
                    .foregroundStyle(.tertiary)
                Text(BatteryFormatting.lastUpdated(monitor.lastUpdated))
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .monospacedDigit()
        }
    }

    @ViewBuilder
    private func heroMetric(_ snapshot: BatterySnapshot) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Current charge-holding capacity")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text(BatteryFormatting.milliampHours(snapshot.fullChargeCapacityMilliampHours))
                    .font(.system(size: 34, weight: .semibold, design: .default))
                    .monospacedDigit()

                Text("\(BatteryFormatting.wattHours(snapshot.fullChargeCapacityWattHours)) • \(BatteryFormatting.percent(snapshot.healthPercent, decimals: 1)) of design")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func chargeSection(_ snapshot: BatterySnapshot) -> some View {
        BatterySectionView("Charge") {
            MetricRowView(title: "Current charge", value: BatteryFormatting.milliampHours(snapshot.currentChargeMilliampHours))
            MetricRowView(title: "Current energy", value: BatteryFormatting.wattHours(snapshot.currentChargeWattHours))
            MetricRowView(
                title: "Estimated time remaining",
                value: snapshot.powerState == .onBattery
                    ? BatteryFormatting.duration(minutes: snapshot.rateBasedTimeRemainingMinutes)
                    : "Unavailable"
            )

            if snapshot.powerState == .charging {
                MetricRowView(title: "Time to full", value: BatteryFormatting.duration(minutes: snapshot.timeToFullMinutes))
            }
        }
    }

    @ViewBuilder
    private func capacitySection(_ snapshot: BatterySnapshot) -> some View {
        BatterySectionView("Capacity") {
            MetricRowView(title: "Full charge capacity", value: BatteryFormatting.milliampHours(snapshot.fullChargeCapacityMilliampHours))
            MetricRowView(title: "Full charge energy", value: BatteryFormatting.wattHours(snapshot.fullChargeCapacityWattHours))
            MetricRowView(title: "Design capacity", value: BatteryFormatting.milliampHours(snapshot.designCapacityMilliampHours))
            MetricRowView(title: "Design energy", value: BatteryFormatting.wattHours(snapshot.designCapacityWattHours))
            MetricRowView(title: "Battery health", value: BatteryFormatting.percent(snapshot.healthPercent, decimals: 1))
        }
    }

    @ViewBuilder
    private func electricalSection(_ snapshot: BatterySnapshot) -> some View {
        BatterySectionView("Electrical & Lifecycle") {
            MetricRowView(
                title: "Discharge rate",
                value: snapshot.powerState == .onBattery
                    ? BatteryFormatting.milliamps(snapshot.dischargeRateMilliamps)
                    : "Unavailable"
            )

            MetricRowView(
                title: "Charge rate",
                value: snapshot.powerState == .charging
                    ? BatteryFormatting.watts(snapshot.chargeRateWatts)
                    : "Unavailable"
            )

            MetricRowView(title: "Cycle count", value: snapshot.cycleCount.map(String.init) ?? "Unavailable")
            MetricRowView(title: "Temperature", value: BatteryFormatting.temperature(snapshot.temperatureCelsius, unitPreference: preferences.temperatureUnitPreference))
            MetricRowView(title: "Manufacture date", value: BatteryFormatting.date(snapshot.manufactureDate))
            MetricRowView(title: "Battery age", value: BatteryFormatting.age(snapshot.batteryAgeComponents))

            if preferences.showAdvancedValues {
                MetricRowView(title: "Voltage", value: BatteryFormatting.millivolts(snapshot.voltageMillivolts))
                MetricRowView(title: "Signed current", value: BatteryFormatting.signedMilliamps(snapshot.currentMilliampsSigned))
                MetricRowView(title: "System time remaining", value: BatteryFormatting.duration(minutes: snapshot.systemTimeRemainingMinutes))
                MetricRowView(title: "Adapter max", value: snapshot.adapterMaxWatts.map { "\($0) W" } ?? "Unavailable")
            }
        }
    }
}

#Preview {
    BatteryDashboardView(monitor: {
        let monitor = BatteryMonitor()
        monitor.availabilityState = .available
        monitor.snapshot = .previewDischarging
        monitor.lastUpdated = .now
        return monitor
    }(), preferences: PreferencesStore())
}
