import SwiftUI
import UserNotifications
import SupplCore

/// One calm line about what suppl. is doing, built only from real state.
@MainActor
struct StatusCard: View {
    let notifications: UNAuthorizationStatus
    var turnOn: () -> Void
    @Environment(\.openURL) private var openURL

    /// A connected app whose data is too old to use. The engine falls back to usual times on its own.
    private var staleConnector: String? {
        let hub = ConnectorHub.shared
        let now = Date.now
        return hub.connectors.first { connector in
            connector.availability == .available
                && connector.authorization == .connected
                && hub.isStale(connector.id, now: now)
        }?.displayName
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(Color.sage)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                Text(message)
                    .font(.callout)
                action
            }
        }
        .card()
    }

    private var symbol: String {
        switch notifications {
        case .denied, .notDetermined: "bell.slash"
        default: staleConnector == nil ? "checkmark.circle" : "clock"
        }
    }

    private var message: String {
        switch notifications {
        case .denied:
            return "Notifications are off. Turn them on to get reminders."
        case .notDetermined:
            return "Reminders aren't on yet. Turn them on and we'll nudge you at the right moments."
        default:
            if let name = staleConnector {
                return "\(name) hasn't updated recently, so we're using your usual times."
            }
            return "Your routine is ready. We'll let you know when it's a good time."
        }
    }

    @ViewBuilder private var action: some View {
        switch notifications {
        case .denied:
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: 44)
        case .notDetermined:
            Button("Turn on reminders", action: turnOn)
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
        default:
            EmptyView()
        }
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 16) {
        StatusCard(notifications: .authorized, turnOn: {})
        StatusCard(notifications: .denied, turnOn: {})
        StatusCard(notifications: .notDetermined, turnOn: {})
    }
    .padding()
    .background(Color.cream)
    .foregroundStyle(Color.forest)
}
#endif
