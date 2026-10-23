import SwiftUI
import SupplCore

/// Every connector, each independently connectable and revocable.
@MainActor
struct ConnectedAppsView: View {
    private var hub: ConnectorHub { .shared }

    var body: some View {
        Form {
            Section {
                ForEach(hub.connectors.map { $0.id }, id: \.self) { id in
                    if let connector = hub.connector(id) {
                        ConnectorRow(connector: connector, detailed: true)
                    }
                }
            } footer: {
                Text("All optional. suppl. reads only what each row says and keeps it on your phone. Timing around workouts, sleep, and your calendar is part of Pro; without it, reminders use your usual times.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.cream)
        .foregroundStyle(Color.forest)
        .navigationTitle("Connected apps")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        ConnectedAppsView()
    }
}
#endif
