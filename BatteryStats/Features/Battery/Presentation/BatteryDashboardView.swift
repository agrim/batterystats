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
    @State private var isLightningRefreshEnabled = false

    var body: some View {
        BatterySurfaceView(
            monitor: monitor,
            preferences: preferences,
            showsLightningRefreshButton: true,
            isLightningRefreshEnabled: $isLightningRefreshEnabled
        )
            .frame(minWidth: BatterySurfaceLayout.minimumWidth, alignment: .topLeading)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .containerBackground(.thinMaterial, for: .window)
            .background(CurrentWindowSpaceConfigurator())
            .background(LightningRefreshWindowLifecycleObserver(isEnabled: $isLightningRefreshEnabled))
            .onChange(of: isLightningRefreshEnabled) { _, isEnabled in
                monitor.setLightningRefreshActive(isEnabled)
            }
            .onDisappear {
                disableLightningRefresh()
            }
    }

    private func disableLightningRefresh() {
        guard isLightningRefreshEnabled else {
            return
        }

        isLightningRefreshEnabled = false
        monitor.setLightningRefreshActive(false)
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
    var showsLightningRefreshButton = false
    @Binding var isLightningRefreshEnabled: Bool

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
                        HStack(alignment: .center, spacing: 8) {
                            BatteryFreshnessView(
                                lastUpdated: monitor.lastUpdated,
                                isRefreshing: monitor.isRefreshing
                            )
                            .layoutPriority(1)

                            if showsLightningRefreshButton {
                                LightningRefreshButton(isEnabled: $isLightningRefreshEnabled)
                            }
                        }

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

private struct LightningRefreshButton: View {
    @Binding var isEnabled: Bool

    var body: some View {
        Button {
            isEnabled.toggle()
        } label: {
            Image(systemName: isEnabled ? "bolt.fill" : "bolt")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(isEnabled ? Color.yellow : Color.secondary)
        .background {
            if isEnabled {
                Capsule()
                    .fill(Color.yellow.opacity(0.18))
            }
        }
        .clipShape(Capsule())
        .help(isEnabled ? "Turn Off Lightning Refresh" : "Lightning Refresh")
        .accessibilityLabel("Lightning Refresh")
        .accessibilityValue(isEnabled ? "On" : "Off")
    }
}

private struct LightningRefreshWindowLifecycleObserver: NSViewRepresentable {
    @Binding var isEnabled: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isEnabled: $isEnabled)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.observeWindow(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(isEnabled: $isEnabled)
        context.coordinator.observeWindow(for: nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopObserving()
    }

    @MainActor
    final class Coordinator {
        private var isEnabled: Binding<Bool>
        private weak var observedWindow: NSWindow?
        private var observationTokens: [NSObjectProtocol] = []
        private var windowLookupTask: Task<Void, Never>?

        init(isEnabled: Binding<Bool>) {
            self.isEnabled = isEnabled
        }

        deinit {
            windowLookupTask?.cancel()
        }

        func update(isEnabled: Binding<Bool>) {
            self.isEnabled = isEnabled
        }

        func observeWindow(for view: NSView) {
            guard let window = view.window else {
                scheduleWindowLookup(for: view)
                return
            }

            windowLookupTask?.cancel()
            windowLookupTask = nil

            guard observedWindow !== window else {
                return
            }

            stopObserving()
            observedWindow = window
            observationTokens = [
                NotificationCenter.default.addObserver(
                    forName: NSWindow.didResignKeyNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.disableLightningRefresh()
                    }
                },
                NotificationCenter.default.addObserver(
                    forName: NSWindow.didMiniaturizeNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.disableLightningRefresh()
                    }
                },
                NotificationCenter.default.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.disableLightningRefresh()
                    }
                },
                NotificationCenter.default.addObserver(
                    forName: NSApplication.didResignActiveNotification,
                    object: NSApp,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.disableLightningRefresh()
                    }
                }
            ]
        }

        func stopObserving() {
            observationTokens.forEach(NotificationCenter.default.removeObserver)
            observationTokens.removeAll()
            observedWindow = nil
            windowLookupTask?.cancel()
            windowLookupTask = nil
        }

        private func scheduleWindowLookup(for view: NSView) {
            guard windowLookupTask == nil else {
                return
            }

            windowLookupTask = Task { @MainActor [weak self, weak view] in
                await Task.yield()

                guard Task.isCancelled == false,
                      let self,
                      let view else {
                    return
                }

                windowLookupTask = nil
                observeWindow(for: view)
            }
        }

        private func disableLightningRefresh() {
            isEnabled.wrappedValue = false
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
