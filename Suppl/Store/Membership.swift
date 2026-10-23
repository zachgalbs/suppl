import Foundation

/// Where the user's Pro subscription stands, as StoreKit last reported it.
enum Membership: Equatable {
    case notSubscribed
    case active(productID: String, renewalDate: Date?, willRenew: Bool)
    /// Renewal failed but Apple is still giving access while the user fixes their payment.
    case gracePeriod
    /// Renewal failed and Apple is retrying, outside any grace period. Apple's guidance is no access here.
    case billingRetry
    case expired
    /// Refunded or removed from Family Sharing.
    case revoked

    var includesPro: Bool {
        switch self {
        case .active, .gracePeriod: true
        case .notSubscribed, .billingRetry, .expired, .revoked: false
        }
    }

    /// One plain line for Profile.
    var summary: String {
        switch self {
        case .notSubscribed:
            return "You're on the free plan."
        case let .active(productID, renewalDate, willRenew):
            let plan = productID == Store.yearlyID ? "yearly" : "monthly"
            guard let date = renewalDate?.formatted(date: .abbreviated, time: .omitted) else {
                return "You're on Pro, \(plan)."
            }
            return willRenew ? "You're on Pro, \(plan). Renews \(date)." : "You're on Pro, \(plan). Ends \(date)."
        case .gracePeriod:
            return "Your last payment didn't go through. Pro stays on while you update it in Settings."
        case .billingRetry:
            return "Apple couldn't renew Pro. Update your payment method in Settings to turn it back on."
        case .expired:
            return "Your Pro subscription has ended."
        case .revoked:
            return "Your Pro subscription was refunded or removed."
        }
    }
}
