import SwiftUI
import StoreKit

/// Membership status straight from StoreKit, plus restore and Apple's manage-subscription sheet.
@MainActor
struct MembershipSection: View {
    @Binding var showingPaywall: Bool
    @State private var managing = false
    @State private var restoring = false

    private var store: Store { .shared }

    /// Anyone with a subscription on record can manage it, including to fix a payment problem.
    private var canManage: Bool {
        switch store.status {
        case .active, .gracePeriod, .billingRetry: true
        case .notSubscribed, .expired, .revoked: false
        }
    }

    var body: some View {
        Section {
            Text(store.status.summary)
            if canManage {
                Button("Manage subscription") { managing = true }
                    .manageSubscriptionsSheet(isPresented: $managing)
            } else {
                Button("See Pro") { showingPaywall = true }
            }
            Button(restoring ? "Restoring..." : "Restore Purchases", action: restore)
                .disabled(restoring)
        } header: {
            Text("Membership")
        } footer: {
            if store.restoreFailed {
                Text("We couldn't reach the App Store to restore. Try again in a moment.")
            }
        }
        .onChange(of: managing) { _, isManaging in
            if !isManaging { Task { await store.refresh() } }
        }
    }

    private func restore() {
        restoring = true
        Task {
            await store.restore()
            restoring = false
        }
    }
}

#if DEBUG
#Preview {
    Form {
        MembershipSection(showingPaywall: .constant(false))
    }
}
#endif
