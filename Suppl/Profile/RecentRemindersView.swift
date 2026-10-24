import SwiftUI
import SwiftData

/// Elapsed reminder schedules from the last 14 days, newest first. Delivery is not verified. Pro.
@MainActor
struct RecentRemindersView: View {
    @Query private var logs: [DecisionLog]
    @State private var showingPaywall = false

    init() {
        let now = Date.now
        let cutoff = now.addingTimeInterval(-14 * 24 * 60 * 60)
        // Show elapsed schedules; iOS may have silenced or delayed their delivery.
        _logs = Query(filter: #Predicate<DecisionLog> { $0.fireDate <= now && $0.fireDate >= cutoff },
                      sort: [SortDescriptor(\DecisionLog.fireDate, order: .reverse)])
    }

    var body: some View {
        Form {
            if !Features.current.reminderHistory {
                Section {
                    Text("Recent reminders is part of Pro.")
                    Button("See Pro") { showingPaywall = true }
                }
            } else if logs.isEmpty {
                Section {
                    Text("No scheduled reminders in the last 14 days.")
                }
            } else {
                Section {
                    ForEach(logs) { log in
                        row(log)
                    }
                } footer: {
                    Text("These are scheduled times, not delivery confirmations. iOS may silence or delay notifications. Kept for 14 days, only on this phone.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.cream)
        .foregroundStyle(Color.forest)
        .navigationTitle("Recent reminders")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPaywall) { PaywallView() }
    }

    private func row(_ log: DecisionLog) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(log.title)
                    .font(.headline)
                Spacer(minLength: 8)
                Text(log.fireDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(Color.forest.opacity(0.8))
            }
            if !log.supplementNames.isEmpty {
                Text(log.supplementNames)
                    .font(.subheadline)
            }
            Text(log.reasonText)
                .font(.subheadline)
                .foregroundStyle(Color.forest.opacity(0.8))
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        RecentRemindersView()
    }
    .modelContainer(PreviewData.container())
}
#endif
