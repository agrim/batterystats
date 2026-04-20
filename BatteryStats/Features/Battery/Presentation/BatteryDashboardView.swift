import Observation
import SwiftUI

enum BatterySurfaceLayout {
    static let minimumWidth: CGFloat = 248
    static let horizontalPadding: CGFloat = 14
    static let topPadding: CGFloat = 14
    static let bottomPadding: CGFloat = 14
    static let unavailableMinHeight: CGFloat = 180
}

struct BatteryDashboardView: View {
    @Bindable var monitor: BatteryMonitor
    @Bindable var preferences: PreferencesStore

    var body: some View {
        BatterySurfaceView(monitor: monitor, preferences: preferences)
            .frame(minWidth: BatterySurfaceLayout.minimumWidth, alignment: .topLeading)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .containerBackground(.thinMaterial, for: .window)
    }
}

struct BatterySurfaceView: View {
    @Bindable var monitor: BatteryMonitor
    @Bindable var preferences: PreferencesStore

    var body: some View {
        Group {
            switch monitor.availabilityState {
            case .loading:
                ProgressView("Reading battery information…")
                    .frame(
                        minWidth: BatterySurfaceLayout.minimumWidth - (BatterySurfaceLayout.horizontalPadding * 2),
                        minHeight: BatterySurfaceLayout.unavailableMinHeight,
                        alignment: .center
                    )
            case .unsupported:
                UnsupportedBatteryView()
                    .frame(
                        minWidth: BatterySurfaceLayout.minimumWidth - (BatterySurfaceLayout.horizontalPadding * 2),
                        minHeight: BatterySurfaceLayout.unavailableMinHeight
                    )
            case .available:
                if let snapshot = monitor.snapshot {
                    BatterySummaryGridView(
                        snapshot: snapshot,
                        temperatureUnitPreference: preferences.temperatureUnitPreference
                    )
                } else {
                    UnsupportedBatteryView()
                        .frame(
                            minWidth: BatterySurfaceLayout.minimumWidth - (BatterySurfaceLayout.horizontalPadding * 2),
                            minHeight: BatterySurfaceLayout.unavailableMinHeight
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, BatterySurfaceLayout.horizontalPadding)
        .padding(.top, BatterySurfaceLayout.topPadding)
        .padding(.bottom, BatterySurfaceLayout.bottomPadding)
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
