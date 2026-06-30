import AppKit
import Observation
import SwiftUI

enum BatterySurfaceLayout {
    static let minimumWidth: CGFloat = 248
    static let menuBarPanelMinimumHeight: CGFloat = 260
    static let menuBarPanelCornerRadius: CGFloat = 18
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
            .background(CurrentWindowSpaceConfigurator())
    }
}

private struct CurrentWindowSpaceConfigurator: NSViewRepresentable {
    private static let windowConfigurationRetryDelays: [TimeInterval] = [0, 0.02, 0.12, 0.32]

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.scheduleConfiguration(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.scheduleConfiguration(for: nsView)
    }

    @MainActor
    final class Coordinator {
        private var configurationTask: Task<Void, Never>?

        deinit {
            configurationTask?.cancel()
        }

        func scheduleConfiguration(for view: NSView) {
            if Self.configureWindowIfAvailable(for: view) {
                configurationTask?.cancel()
                configurationTask = nil
                return
            }

            guard configurationTask == nil else {
                return
            }

            configurationTask = Task { @MainActor [weak self, weak view] in
                guard let self else {
                    return
                }

                for delay in CurrentWindowSpaceConfigurator.windowConfigurationRetryDelays {
                    if delay == 0 {
                        await Task.yield()
                    } else {
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }

                    guard Task.isCancelled == false else {
                        return
                    }

                    guard let view else {
                        configurationTask = nil
                        return
                    }

                    if Self.configureWindowIfAvailable(for: view) {
                        configurationTask = nil
                        return
                    }
                }

                self.configurationTask = nil
            }
        }

        private static func configureWindowIfAvailable(for view: NSView) -> Bool {
            guard let window = view.window else {
                return false
            }

            var behavior = window.collectionBehavior
            behavior.remove(.canJoinAllSpaces)
            behavior.formUnion([
                .canJoinAllApplications,
                .fullScreenAuxiliary,
                .moveToActiveSpace
            ])
            window.collectionBehavior = behavior
            return true
        }
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
                    VStack(alignment: .leading, spacing: 8) {
                        BatteryFreshnessView(
                            lastUpdated: monitor.lastUpdated,
                            isRefreshing: monitor.isRefreshing
                        )

                        BatterySummaryGridView(
                            snapshot: snapshot,
                            temperatureUnitPreference: preferences.temperatureUnitPreference,
                            temperatureUnitResolutionToken: preferences.temperatureUnitResolutionToken,
                            showsAdvancedValues: preferences.showAdvancedValues
                        )
                    }
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
