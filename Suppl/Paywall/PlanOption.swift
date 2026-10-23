import SwiftUI
import StoreKit

/// One selectable plan. Price and period come straight from StoreKit.
struct PlanOption: View {
    let product: Product
    let isSelected: Bool
    var badge: String? = nil
    let select: () -> Void

    private var title: String {
        switch product.periodText {
        case "year": "Yearly"
        case "month": "Monthly"
        default: product.displayName
        }
    }

    var body: some View {
        Button(action: select) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.sage : Color.forest.opacity(0.4))
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title)
                            .font(.headline)
                        if let badge {
                            Text(badge)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.softLavender)
                                .foregroundStyle(Color.forest)
                                .clipShape(Capsule())
                        }
                    }
                    Text(product.priceLine)
                        .font(.body)
                    if let perMonth = product.monthlyEquivalent {
                        Text(perMonth)
                            .font(.subheadline)
                            .foregroundStyle(Color.forest.opacity(0.8))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.softSage : Color.white.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? Color.sage : Color.clear, lineWidth: 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
