import SwiftUI
import SupplCore

/// One connected app. Permission is only requested when the user taps Connect.
@MainActor
struct ConnectorRow: View {
    let connector: any Connector
    /// Profile shows last sync, the disconnect note, and Disconnect. Onboarding keeps it short.
    var detailed = false

    @State private var working = false
    @Environment(\.openURL) private var openURL

    private var hub: ConnectorHub { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: symbol)
                    .foregroundStyle(Color.sage)
                    .accessibilityHidden(true)
                Text(connector.displayName)
                    .font(.headline)
                Spacer(minLength: 8)
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(Color.forest.opacity(0.8))
            }
            .accessibilityElement(children: .combine)
            Text(connector.summary)
                .font(.subheadline)
                .foregroundStyle(Color.forest.opacity(0.8))
            if detailed {
                details
            }
            if let error = hub.lastError[connector.id] {
                Text(error)
                    .font(.footnote)
            }
            action
        }
        .padding(.vertical, 4)
    }

    private var symbol: String {
        switch connector.id {
        case .appleHealth: "heart"
        case .calendar: "calendar"
        case .whoop: "waveform.path.ecg"
        case .oura: "circle.circle"
        }
    }

    private var statusText: String {
        switch connector.availability {
        case .notConfigured: return "Not available yet"
        case .unsupported: return "Not on this device"
        case .available: break
        }
        switch connector.authorization {
        // iOS never tells apps whether Health read access was granted, so don't claim more than the prompt.
        case .connected: return connector.id == .appleHealth ? "Set up" : "Connected"
        case .denied: return "Access off"
        case .notConnected: return "Not connected"
        }
    }

    @ViewBuilder private var details: some View {
        if connector.authorization == .connected {
            Text(syncText)
                .font(.footnote)
                .foregroundStyle(Color.forest.opacity(0.8))
            if let note = hub.disconnectNote(connector.id) {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Color.forest.opacity(0.8))
            }
        }
    }

    private var syncText: String {
        guard let lastSync = connector.lastSync else { return "No data received yet." }
        return "Last updated \(lastSync.formatted(date: .abbreviated, time: .shortened))."
    }

    @ViewBuilder private var action: some View {
        if working {
            ProgressView()
                .frame(minHeight: 44)
        } else if connector.availability == .available {
            switch connector.authorization {
            case .notConnected:
                Button("Connect", action: connect)
                    .buttonStyle(.bordered)
                    .tint(Color.sage)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Connect \(connector.displayName)")
            case .denied:
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.borderless)
                .frame(minHeight: 44)
            case .connected:
                if detailed {
                    Button("Disconnect", role: .destructive, action: disconnect)
                        .buttonStyle(.borderless)
                        .frame(minHeight: 44)
                        .accessibilityLabel("Disconnect \(connector.displayName)")
                }
            }
        }
    }

    private func connect() {
        working = true
        Task {
            await hub.connect(connector.id)
            working = false
        }
    }

    private func disconnect() {
        working = true
        Task {
            await hub.disconnect(connector.id)
            working = false
        }
    }
}
