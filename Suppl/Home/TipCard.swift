import SwiftUI
import SupplCore

/// The daily tip, with its source one tap away.
struct TipCard: View {
    let tip: Tip

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "leaf")
                .foregroundStyle(Color.lavender)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(tip.text)
                    .font(.callout)
                Text("General information. Check it against your label.")
                    .font(.footnote)
                    .foregroundStyle(Color.forest.opacity(0.8))
                if let url = URL(string: tip.sourceURL) {
                    Link("Learn more", destination: url)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.forest)
                        .frame(minHeight: 44)
                        .accessibilityHint("Opens the source in Safari")
                }
            }
        }
        .card()
    }
}

#if DEBUG
#Preview {
    TipCard(tip: Tip(id: "preview", text: "Keeping your bottles where you eat makes them easier to remember.",
                     sourceURL: "https://ods.od.nih.gov/factsheets/WYNTK-Consumer/"))
        .padding()
        .background(Color.cream)
}
#endif
