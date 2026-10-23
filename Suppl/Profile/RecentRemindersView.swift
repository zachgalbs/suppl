import SwiftUI
import SwiftData

/// Reminders that went out in the last 14 days, newest first, with why each was sent. Pro.
@MainActor
struct RecentRemindersView: View {
    @Query private var logs: [DecisionLog]
    @State private var showingPaywall = false

    init() {
        let now = Date.now
        let cutoff = now.addingTimeInterval(-14 * 24 * 60 * 60)
        // Only reminders already delivered; pending ones live in DecisionLog too.
        _logs = Query(filter: #Predicate<DecisionLog> { $0.fireDate <= now && $0.fireDate >= cutoff },
                      sort: [SortDescriptor(\DecisionLog.fireDate, order: .reverse)])
    }

    var body: some View {
        Form {
            if !Store.shared.isPro {
                Section {
                    Text("Recent reminders is part of Pro.")
                    Button("See Pro") { showingPaywall = true }
                }
            } else if logs.isEmpty {
                Section {
                    Text("No reminders in the last 14 days.")
                }
            } else {
                Section {
                    ForEach(logs) { log in
                        row(log)
                    }
                } footer: {
                    Text("Kept for 14 days, only on this phone.")
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
