import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("name") private var name = ""
    @Query(sort: \Supplement.createdAt) private var supplements: [Supplement]

    @State private var editing: Supplement?
    @State private var adding = false
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(greeting)
                        .font(.largeTitle.bold())

                    tipCard

                    if supplements.isEmpty {
                        emptyState
                    } else {
                        ForEach(Slot.allCases) { slot in
                            let items = supplements.filter { $0.slot == slot }
                            if !items.isEmpty {
                                section(slot, items)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Color.cream.ignoresSafeArea())
            .foregroundStyle(Color.forest)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { adding = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $adding) { SupplementForm(supplement: nil) }
            .sheet(item: $editing) { SupplementForm(supplement: $0) }
            .sheet(isPresented: $showingSettings) { SettingsView() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Reminders.reschedule() }
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let part = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        return name.isEmpty ? part : "\(part), \(name)"
    }

    private var tipCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "leaf")
                .foregroundStyle(Color.lavender)
            Text(Tips.today)
                .font(.callout)
        }
        .card()
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nothing here yet")
                .font(.title2.bold())
            Text("Add the supplements you already take and we'll remind you at the right moments.")
                .foregroundStyle(Color.forest.opacity(0.7))
            Button("Add a supplement") { adding = true }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 8)
        }
        .card()
    }

    private func section(_ slot: Slot, _ items: [Supplement]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(slot.title, systemImage: slot.symbol)
                .font(.headline)
                .foregroundStyle(Color.sage)
            VStack(spacing: 0) {
                ForEach(items) { item in
                    row(item)
                    if item.id != items.last?.id { Divider() }
                }
            }
            .card()
        }
    }

    private func row(_ item: Supplement) -> some View {
        HStack(spacing: 12) {
            Button {
                item.lastTakenAt = item.isTakenToday ? nil : .now
            } label: {
                Image(systemName: item.isTakenToday ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(item.isTakenToday ? Color.sage : Color.forest.opacity(0.3))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isTakenToday ? "Mark \(item.name) not taken" : "Mark \(item.name) taken")

            Button { editing = item } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.body.weight(.semibold))
                        .strikethrough(item.isTakenToday, color: Color.forest.opacity(0.4))
                    Text("\(item.doseText) · \(item.timingNote)")
                        .font(.subheadline)
                        .foregroundStyle(Color.forest.opacity(0.6))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
    }
}

enum Tips {
    static let all = [
        "Keeping your bottles where you eat makes them easier to remember.",
        "Missed one? Follow your label or ask a pharmacist. Don't double up.",
        "Some supplements are better absorbed with food. Your label usually says.",
        "A consistent time each day tends to stick better than a perfect time.",
        "Bringing a new supplement into the mix? It's worth a quick check with your pharmacist.",
        "Snooze is there for busy moments. One follow-up, then we'll leave you be.",
        "Check expiration dates now and then, especially for probiotics and oils.",
    ]

    static var today: String {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: .now) ?? 0
        return all[day % all.count]
    }
}

#Preview {
    HomeView()
        .modelContainer(for: Supplement.self, inMemory: true)
}
