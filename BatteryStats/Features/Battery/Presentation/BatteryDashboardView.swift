import AppKit
import Observation
import SwiftUI

struct BatteryDashboardView: View {
    private static let windowWidth: CGFloat = 250
    private static let windowHeight: CGFloat = 235
    private static let titleBarHeight: CGFloat = 26
    private static let titleBarLeadingInset: CGFloat = 76
    private static let titleBarTrailingInset: CGFloat = 10

    @Bindable var monitor: BatteryMonitor
    @Bindable var preferences: PreferencesStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let content = ZStack(alignment: .topLeading) {
            Group {
                switch monitor.availabilityState {
                case .loading:
                    ProgressView("Reading battery information…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                case .unsupported:
                    UnsupportedBatteryView()
                case .available:
                    if let snapshot = monitor.snapshot {
                        BatterySummaryGridView(
                            snapshot: snapshot,
                            compact: false,
                            temperatureUnitPreference: preferences.temperatureUnitPreference
                        )
                    } else {
                        UnsupportedBatteryView()
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, Self.titleBarHeight + 6)
            .padding(.bottom, 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            BatteryDashboardHeaderView {
                openSettings()
            }
            .padding(.leading, Self.titleBarLeadingInset)
            .padding(.trailing, Self.titleBarTrailingInset)
            .padding(.top, 6)
        }
        .frame(width: Self.windowWidth, height: Self.windowHeight, alignment: .top)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            monitor.start()
        }
        .background(WindowChromeConfigurator())

        if #available(macOS 15.0, *) {
            content
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                .containerBackground(.ultraThinMaterial, for: .window)
        } else {
            content
        }
    }
}

private struct BatteryDashboardHeaderView: View {
    let openSettings: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("BatteryStats")
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button(action: openSettings) {
                Image(systemName: "gearshape")
                    .imageScale(.medium)
            }
            .modifier(NativeSettingsButtonStyle())
            .help("Settings")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NativeSettingsButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .controlSize(.mini)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
        } else {
            content
                .controlSize(.small)
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
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

private struct WindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else {
            return
        }

        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = ""
        window.toolbarStyle = .unifiedCompact
        window.toolbar?.showsBaselineSeparator = false
        window.isMovableByWindowBackground = true
        window.styleMask.insert(.fullSizeContentView)
    }
}
