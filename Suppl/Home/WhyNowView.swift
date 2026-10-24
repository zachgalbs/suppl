import SwiftUI
import SwiftData

/// The scheduled reminder and the data its timing was based on.
struct WhyNowView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var logs: [DecisionLog]

    init(groupID: String) {
        let id = groupID
        _logs = Query(filter: #Predicate<DecisionLog> { $0.groupID == id },
                      sort: [SortDescriptor(\DecisionLog.fireDate, order: .reverse)])
    }

    /// Prefer the latest elapsed schedule; a passed fire date alone does not prove delivery.
    private var latest: DecisionLog? {
        logs.first { $0.fireDate <= .now } ?? logs.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let latest {
                        details(latest)
                    } else {
                        empty
                    }
                    footer
                }
                .padding(20)
            }
            .background(Color.cream.ignoresSafeArea())
            .foregroundStyle(Color.forest)
            .navigationTitle("Why now?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func details(_ log: DecisionLog) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(log.title)
                    .font(.title2.bold())
                if !log.supplementNames.isEmpty {
                    Text(log.supplementNames)
                        .font(.body)
                        .foregroundStyle(Color.forest.opacity(0.8))
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(log.reasonText)
                Label("Scheduled for \(stamp(log.fireDate))", systemImage: "bell")
                    .font(.subheadline)
                if let data = log.dataTimestamp {
                    Label("Data from \(stamp(data))", systemImage: "clock")
                        .font(.subheadline)
                }
            }
            .card()
        }
    }

    /// Time only for today, otherwise with the date, so old data never reads as fresh.
    private func stamp(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(date: .abbreviated, time: .shortened)
    }

    private var empty: some View {
        Text("We couldn't find the details for this reminder. Reminder details are kept for 14 days.")
            .card()
    }

    private var footer: some View {
        Text("suppl. times reminders around your day. It doesn't give medical advice. For doses and interactions, follow your label or ask a pharmacist.")
            .font(.footnote)
            .foregroundStyle(Color.forest.opacity(0.8))
    }
}

#if DEBUG
#Preview {
    WhyNowView(groupID: PreviewData.groupID)
        .modelContainer(PreviewData.container())
}

#Preview("Missing") {
    WhyNowView(groupID: "none")
        .modelContainer(PreviewData.container(empty: true))
}
#endif
