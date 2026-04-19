import SwiftUI

struct MetricRowView: View {
    let title: String
    let value: String
    var secondaryValue: String?

    var body: some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .monospacedDigit()

                if let secondaryValue {
                    Text(secondaryValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        } label: {
            Text(title)
                .foregroundStyle(.secondary)
        }
    }
}
