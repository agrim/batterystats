import SwiftUI

struct UnsupportedBatteryView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Internal Battery Unavailable", systemImage: "battery.0")
        } description: {
            Text("BatteryStats is designed for Mac laptops with an internal battery. You can still open Settings if you want to adjust the app's display preferences.")
        } actions: {
            SettingsLink {
                Text("Open Settings")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
