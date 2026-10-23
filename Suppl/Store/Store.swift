import Foundation
import Observation
import StoreKit

/// StoreKit 2 subscriptions. `isPro` is always recomputed from the App Store's signed transactions,
/// never read from a saved flag, so a refund or lapse takes effect on the next refresh.
@MainActor
@Observable
final class Store {
    static let shared = Store()
    // nonisolated so plain value types like `Membership` can read them.
    nonisolated static let yearlyID = "com.zgalbs.suppl.pro.yearly"
    nonisolated static let monthlyID = "com.zgalbs.suppl.pro.monthly"
    nonisolated static let productIDs = [yearlyID, monthlyID]

    enum LoadState: Equatable { case idle, loading, loaded, failed }

    /// Yearly first.
    private(set) var products: [Product] = []
    private(set) var loadState = LoadState.idle
    private(set) var isPro = false
    private(set) var status = Membership.notSubscribed
    /// Set when a purchase is waiting on Ask to Buy or a bank check.
    private(set) var purchasePending = false
    private(set) var restoreFailed = false

    @ObservationIgnored private var updates: Task<Void, Never>?

    var yearly: Product? { products.first { $0.id == Self.yearlyID } }
    var monthly: Product? { products.first { $0.id == Self.monthlyID } }

    /// Safe to call more than once. Starts the transaction listener, loads products, and refreshes.
    func start() {
        guard updates == nil else { return }
        // Renewals, refunds, and Ask to Buy approvals arrive here, including ones made on other devices.
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                await self?.refresh()
            }
        }
        Task {
            await self.loadProducts()
            await self.refresh()
        }
    }

    func loadProducts() async {
        loadState = .loading
        do {
            let found = try await Product.products(for: Self.productIDs)
            products = found.sorted { a, b in a.id == Self.yearlyID && b.id != Self.yearlyID }
            loadState = found.isEmpty ? .failed : .loaded
        } catch {
            loadState = .failed
        }
    }

    /// The only source of truth for Pro.
    func refresh() async {
        var entitled: [Transaction] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  Self.productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil else { continue }
            entitled.append(transaction)
        }
        let statuses = await subscriptionStatuses(entitled: entitled)
        status = Self.membership(from: statuses, entitled: entitled)
        let wasPro = isPro
        isPro = status.includesPro
        // Buying or losing Pro changes how reminders are timed, so re-plan right away.
        if isPro != wasPro { Reminders.reschedule() }
    }

    /// True when a verified purchase went through. False when the user cancelled or it's pending approval.
    func purchase(_ product: Product) async throws -> Bool {
        purchasePending = false
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else { throw StoreError.unverified }
            await transaction.finish()
            await self.refresh()
            return true
        case .pending:
            purchasePending = true
            return false
        case .userCancelled:
            return false
        @unknown default:
            return false
        }
    }

    func restore() async {
        restoreFailed = false
        do {
            try await AppStore.sync()
        } catch {
            restoreFailed = true
        }
        await refresh()
    }

    private func subscriptionStatuses(entitled: [Transaction]) async -> [Product.SubscriptionInfo.Status] {
        // Any product in the group reports the whole group, including expired and revoked subscriptions.
        if let info = products.first?.subscription, let all = try? await info.status {
            return all
        }
        var found: [Product.SubscriptionInfo.Status] = []
        for transaction in entitled {
            if let status = await transaction.subscriptionStatus { found.append(status) }
        }
        return found
    }

    private static func membership(from statuses: [Product.SubscriptionInfo.Status],
                                   entitled: [Transaction]) -> Membership {
        var best: (rank: Int, membership: Membership)?
        for status in statuses {
            guard case .verified(let transaction) = status.transaction,
                  productIDs.contains(transaction.productID) else { continue }
            let candidate: (rank: Int, membership: Membership)
            switch status.state {
            case .subscribed:
                var willRenew = false
                if case .verified(let info) = status.renewalInfo { willRenew = info.willAutoRenew }
                candidate = (5, .active(productID: transaction.productID,
                                        renewalDate: transaction.expirationDate, willRenew: willRenew))
            case .inGracePeriod:
                candidate = (4, .gracePeriod)
            case .inBillingRetryPeriod:
                candidate = (3, .billingRetry)
            case .expired:
                candidate = (2, .expired)
            case .revoked:
                candidate = (1, .revoked)
            default:
                continue
            }
            if best == nil || candidate.rank > best!.rank { best = candidate }
        }
        if let best { return best.membership }
        // No renewal status (offline, or products didn't load). A verified entitlement still proves access;
        // without renewal info we don't claim a renew or end date.
        if let transaction = entitled.first {
            return .active(productID: transaction.productID, renewalDate: nil, willRenew: false)
        }
        return .notSubscribed
    }
}

enum StoreError: LocalizedError {
    case unverified

    var errorDescription: String? {
        "We couldn't confirm that purchase with the App Store. Try Restore Purchases."
    }
}
