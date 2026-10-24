import SwiftUI
import SupplCore

/// All optional. Each app asks for permission only when its row is tapped.
@MainActor
struct ConnectStep: View {
    let next: () -> Void

    private var hub: ConnectorHub { .shared }

    private var whoopNote: String {
        hub.connector(.whoop)?.availability == .available ? " Using WHOOP for timing is part of suppl. Pro." : ""
    }

    private var anyConnected: Bool {
        hub.connectors.contains { $0.authorization == .connected }
    }

    var body: some View {
        OnboardingPage("Connect your apps", subtitle: "Optional. This lets suppl. time reminders around your workouts, sleep, and calendar.",
                       primary: anyConnected ? "Continue" : "Skip for now", onPrimary: next) {
            ForEach(hub.connectors.map { $0.id }, id: \.self) { id in
                if let connector = hub.connector(id) {
                    ConnectorRow(connector: connector)
                        .card()
                }
            }
            Text(Features.current.smartTimingFree
                 ? "Timing around your workouts, sleep, and calendar is free while suppl. is in testing.\(whoopNote) You can connect or disconnect anytime in Profile."
                 : "Smart timing with these apps is part of suppl. Pro. Without it, reminders come at your usual times. You can connect or disconnect anytime in Profile.")
                .font(.footnote)
                .foregroundStyle(Color.forest.opacity(0.8))
        }
    }
}

#if DEBUG
#Preview {
    ConnectStep {}
        .padding(24)
        .background(Color.cream)
        .foregroundStyle(Color.forest)
}
#endif
