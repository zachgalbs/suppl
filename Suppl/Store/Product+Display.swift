import Foundation
import StoreKit

extension Product {
    /// "year", "month", "3 months". Read from StoreKit so it always matches what Apple charges.
    var periodText: String {
        guard let period = subscription?.subscriptionPeriod else { return "" }
        let unit: String
        switch period.unit {
        case .day: unit = "day"
        case .week: unit = "week"
        case .month: unit = "month"
        case .year: unit = "year"
        @unknown default: unit = "period"
        }
        return period.value == 1 ? unit : "\(period.value) \(unit)s"
    }

    /// "$39.99 / year"
    var priceLine: String {
        periodText.isEmpty ? displayPrice : "\(displayPrice) / \(periodText)"
    }

    /// For a one-year plan, the per-month equivalent, e.g. "$3.33 a month". Nil for anything else.
    var monthlyEquivalent: String? {
        guard let period = subscription?.subscriptionPeriod, period.unit == .year, period.value == 1 else { return nil }
        let perMonth = price / 12
        return "\(perMonth.formatted(priceFormatStyle)) a month"
    }
}
