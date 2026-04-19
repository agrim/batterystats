import SwiftUI

struct UnsupportedBatteryView: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ContentUnavailableView {
            Label("Internal Battery Unavailable", systemImage: "battery.0")
        } description: {
            Text("BatteryStats is designed for Mac laptops with an internal battery. You can still open Settings if you want to adjust the app's display preferences.")
        } actions: {
            Button("Open Settings") {
                openSettings()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
