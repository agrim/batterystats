import SwiftUI

struct UnsupportedBatteryView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Internal Battery Unavailable", systemImage: "battery.0")
        } description: {
            Text("BatteryStats is designed for Mac laptops with an internal battery.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
