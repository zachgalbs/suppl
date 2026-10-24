import SwiftUI
import SupplCore

/// Every connector, each independently connectable and revocable.
@MainActor
struct ConnectedAppsView: View {
    private var hub: ConnectorHub { .shared }

    private var footer: String {
        let start = "All optional. suppl. reads only what each row says and keeps it on your phone. "
        guard Features.current.smartTimingFree else {
            return start + "Timing around workouts, sleep, and your calendar is part of Pro; without it, reminders use your usual times."
        }
        let whoop = hub.connector(.whoop)?.availability == .available ? " Using WHOOP for timing is part of Pro." : ""
        return start + "Timing around workouts, sleep, and your calendar is free while suppl. is in testing." + whoop
    }

    var body: some View {
        Form {
            Section {
                ForEach(hub.connectors.map { $0.id }, id: \.self) { id in
                    if let connector = hub.connector(id) {
                        ConnectorRow(connector: connector, detailed: true)
                    }
                }
            } footer: {
                Text(footer)
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
