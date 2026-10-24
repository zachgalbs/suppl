import SwiftUI
import StoreKit
import SupplCore

/// suppl. Pro. Always dismissible: the free app keeps working without it.
@MainActor
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    /// Onboarding passes this to move on; sheets leave it nil and dismiss.
    var onClose: (() -> Void)? = nil

    @State private var selectedID = Store.yearlyID
    @State private var purchasing = false
    @State private var restoring = false
    @State private var errorText: String?

    private var store: Store { .shared }

    private var whoopAvailable: Bool {
        ConnectorHub.shared.connector(.whoop)?.availability == .available
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                proFeatures
                if store.isPro {
                    alreadyPro
                } else {
                    plans
                }
                legal
                freeFeatures
            }
            .padding(24)
        }
        .background(Color.cream.ignoresSafeArea())
        .foregroundStyle(Color.forest)
        .overlay(alignment: .topTrailing) { closeButton }
        .task {
            store.start()
            if store.loadState == .failed {
                await store.loadProducts()
            }
        }
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }

    private var closeButton: some View {
        Button(action: close) {
            Image(systemName: "xmark")
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.7))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, 16)
        .padding(.top, 8)
        .accessibilityLabel("Close")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("suppl. Pro")
                .font(.headline)
                .foregroundStyle(Color.forest)
            Text("Let suppl. take care of the remembering.")
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 32)
    }

    private var proFeatures: some View {
        VStack(alignment: .leading, spacing: 14) {
            feature("figure.run", "Reminders after your workouts",
                    "When Apple Health\(whoopAvailable ? " or WHOOP" : "") records one.")
            feature("sunrise", "Mornings that wait for you",
                    "Slept in? If Apple Health shows you're up late, morning reminders that haven't gone out yet can wait.")
            feature("calendar", "Around your calendar",
                    "A reminder can move to a free moment instead of mid-meeting.")
            if whoopAvailable {
                feature("waveform.path.ecg", "WHOOP", "Use your WHOOP workouts and sleep for timing.")
            }
            feature("bell.badge", "Extra Help", "Up to two gentle follow-ups if you don't respond.")
            feature("clock.arrow.circlepath", "Recent reminders", "See scheduled reminders and why.")
        }
        .card()
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(Color.sage)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Color.forest.opacity(0.8))
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var plans: some View {
        switch store.loadState {
        case .idle, .loading:
            ProgressView("Loading plans")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        case .failed:
            VStack(alignment: .leading, spacing: 12) {
                Text("We couldn't reach the App Store. Check your connection and try again.")
                Button("Try again") { Task { await store.loadProducts() } }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .card()
        case .loaded:
            planPicker
        }
    }

    private var selected: Product? {
        store.products.first { $0.id == selectedID } ?? store.products.first
    }

    private var savingsBadge: String? {
        guard let yearly = store.yearly, let monthly = store.monthly else { return nil }
        let year = NSDecimalNumber(decimal: yearly.price).doubleValue
        let twelveMonths = NSDecimalNumber(decimal: monthly.price).doubleValue * 12
        guard twelveMonths > 0, year < twelveMonths else { return nil }
        let percent = Int(((1 - year / twelveMonths) * 100).rounded(.down))
        return "Save \(percent)%"
    }

    private var planPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(store.products, id: \.id) { product in
                PlanOption(product: product,
                           isSelected: product.id == selected?.id,
                           badge: product.id == Store.yearlyID ? savingsBadge : nil) {
                    selectedID = product.id
                }
            }
            if let selected {
                Button {
                    buy(selected)
                } label: {
                    if purchasing {
                        ProgressView().tint(Color.cream)
                    } else {
                        Text("Continue with \(selected.priceLine)")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(purchasing)
                .padding(.top, 4)
            }
            Text("Payment is charged to your Apple ID when you confirm. It renews automatically unless you cancel at least 24 hours before the end of the current period. Manage or cancel anytime in Settings.")
                .font(.footnote)
                .foregroundStyle(Color.forest.opacity(0.8))
            if store.purchasePending {
                Text("Your purchase is waiting for approval. Pro turns on as soon as it's approved.")
                    .font(.footnote)
            }
            if let errorText {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(Color.forest)
            }
        }
    }

    private var alreadyPro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("You're on Pro. Thanks for supporting suppl.")
                .font(.headline)
            Button("Done", action: close)
                .buttonStyle(PrimaryButtonStyle())
        }
        .card()
    }

    private var legal: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                restore()
            } label: {
                Text(restoring ? "Restoring..." : "Restore Purchases")
                    .frame(minHeight: 44)
            }
            .disabled(restoring)
            if store.restoreFailed {
                Text("We couldn't reach the App Store to restore. Try again in a moment.")
                    .font(.footnote)
            }
            HStack(spacing: 24) {
                Link("Terms of Use", destination: LegalLinks.terms)
                    .frame(minHeight: 44)
                Link("Privacy Policy", destination: LegalLinks.privacy)
                    .frame(minHeight: 44)
            }
            .font(.footnote)
        }
        .foregroundStyle(Color.forest)
        .tint(Color.forest)
    }

    private var freeFeatures: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Always free")
                .font(.headline)
            Text("Your supplement list and search. Reminders at your usual times with Taken, Snooze, and Skip. All supplement and safety information.")
                .font(.subheadline)
                .foregroundStyle(Color.forest.opacity(0.8))
        }
        .card()
    }

    private func buy(_ product: Product) {
        errorText = nil
        purchasing = true
        Task {
            defer { purchasing = false }
            do {
                if try await store.purchase(product) { close() }
            } catch {
                errorText = (error as? LocalizedError)?.errorDescription
                    ?? "The purchase didn't go through. Please try again."
            }
        }
    }

    private func restore() {
        restoring = true
        Task {
            await store.restore()
            restoring = false
            if store.isPro { close() }
        }
    }
}

#if DEBUG
#Preview {
    PaywallView()
}
#endif
