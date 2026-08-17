import AppKit
import SwiftUI

enum BatterySurfaceLayout {
    static let minimumWidth: CGFloat = 248
    static let contentMinimumWidth: CGFloat = minimumWidth - (contentPadding * 2)
    static let menuBarPanelMinimumHeight: CGFloat = 260
    static let menuBarPanelCornerRadius: CGFloat = 18
    static let contentPadding: CGFloat = 14
    static let unavailableMinHeight: CGFloat = 180
}

struct BatteryDashboardView: View {
    let monitor: BatteryMonitor
    let preferences: PreferencesStore
    @State private var isLightningRefreshEnabled = false

    var body: some View {
        BatterySurfaceView(
            monitor: monitor,
            preferences: preferences,
            lightningRefreshBinding: $isLightningRefreshEnabled
        )
            .frame(minWidth: BatterySurfaceLayout.minimumWidth, alignment: .topLeading)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .containerBackground(.thinMaterial, for: .window)
            .background(BatteryDashboardWindowObserver(isLightningRefreshEnabled: $isLightningRefreshEnabled))
            .onChange(of: isLightningRefreshEnabled) { _, isEnabled in
                monitor.setLightningRefreshActive(isEnabled)
            }
            .onDisappear {
                isLightningRefreshEnabled = false
                monitor.setLightningRefreshActive(false)
            }
    }
}

private struct BatteryDashboardWindowObserver: NSViewRepresentable {
    @Binding var isLightningRefreshEnabled: Bool
    private static let windowLookupRetryDelays: [TimeInterval] = [0, 0.02, 0.12, 0.32]

    func makeCoordinator() -> Coordinator {
        Coordinator(isLightningRefreshEnabled: $isLightningRefreshEnabled)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(isLightningRefreshEnabled: $isLightningRefreshEnabled)
        context.coordinator.attach(to: nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator {
        private var isLightningRefreshEnabled: Binding<Bool>
        private weak var observedWindow: NSWindow?
        private var observationTokens: [NSObjectProtocol] = []
        private var windowLookupTask: Task<Void, Never>?

        init(isLightningRefreshEnabled: Binding<Bool>) {
            self.isLightningRefreshEnabled = isLightningRefreshEnabled
        }

        isolated deinit {
            stop()
        }

        func update(isLightningRefreshEnabled: Binding<Bool>) {
            self.isLightningRefreshEnabled = isLightningRefreshEnabled
        }

        func attach(to view: NSView) {
            guard let window = view.window else {
                scheduleWindowLookup(for: view)
                return
            }

            windowLookupTask?.cancel()
            windowLookupTask = nil
            BatteryWindowSpaceBehavior.applyActiveSpacePresentation(to: window)

            guard observedWindow !== window else {
                return
            }

            removeObservers()
            observedWindow = window
            observationTokens = [
                observe(NSWindow.didResignKeyNotification, object: window),
                observe(NSWindow.didMiniaturizeNotification, object: window),
                observe(NSWindow.willCloseNotification, object: window),
                observe(NSApplication.didResignActiveNotification, object: NSApp)
            ]
        }

        func stop() {
            windowLookupTask?.cancel()
            windowLookupTask = nil
            removeObservers()
            observedWindow = nil
        }

        private func scheduleWindowLookup(for view: NSView) {
            guard windowLookupTask == nil else {
                return
            }

            windowLookupTask = Task { @MainActor [weak self, weak view] in
                guard let self else {
                    return
                }

                for delay in BatteryDashboardWindowObserver.windowLookupRetryDelays {
                    if delay == 0 {
                        await Task.yield()
                    } else {
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }

                    guard Task.isCancelled == false,
                          let view else {
                        break
                    }

                    if view.window != nil {
                        attach(to: view)
                        break
                    }
                }

                windowLookupTask = nil
            }
        }

        private func observe(_ name: Notification.Name, object: Any?) -> NSObjectProtocol {
            NotificationCenter.default.addObserver(
                forName: name,
                object: object,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.isLightningRefreshEnabled.wrappedValue = false
                }
            }
        }

        private func removeObservers() {
            observationTokens.forEach(NotificationCenter.default.removeObserver)
            observationTokens.removeAll()
        }
    }
}

struct BatterySurfaceView: View {
    let monitor: BatteryMonitor
    let preferences: PreferencesStore
    var lightningRefreshBinding: Binding<Bool>? = nil

    var body: some View {
        Group {
            switch monitor.availabilityState {
            case .loading:
                ProgressView("Reading battery information…")
                    .frame(
                        minWidth: BatterySurfaceLayout.contentMinimumWidth,
                        minHeight: BatterySurfaceLayout.unavailableMinHeight,
                        alignment: .center
                    )
            case .unsupported:
                UnsupportedBatteryView()
                    .frame(
                        minWidth: BatterySurfaceLayout.contentMinimumWidth,
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

                            if let lightningRefreshBinding {
                                LightningRefreshButton(isEnabled: lightningRefreshBinding)
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
                            minWidth: BatterySurfaceLayout.contentMinimumWidth,
                            minHeight: BatterySurfaceLayout.unavailableMinHeight
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(BatterySurfaceLayout.contentPadding)
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

#Preview {
    BatteryDashboardView(monitor: {
        let monitor = BatteryMonitor()
        monitor.availabilityState = .available
        monitor.snapshot = .previewDischarging
        monitor.lastUpdated = .now
        return monitor
    }(), preferences: PreferencesStore())
}
