import SwiftUI
import SwiftData
import UserNotifications
import SupplCore

@MainActor
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("name") private var name = ""
    @Query(sort: \Supplement.createdAt) private var supplements: [Supplement]

    @State private var adding = false
    @State private var showingProfile = false
    /// Unknown until the first check, so the status card never guesses.
    @State private var notificationStatus: UNAuthorizationStatus?

    private var router: AppRouter { .shared }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(greeting)
                        .font(.largeTitle.bold())

                    if let notificationStatus, !supplements.isEmpty {
                        StatusCard(notifications: notificationStatus, turnOn: turnOnReminders)
                    }

                    if let tip {
                        TipCard(tip: tip)
                    }

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
                    Button { showingProfile = true } label: { Image(systemName: "person.crop.circle") }
                        .accessibilityLabel("Profile")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { adding = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add supplement")
                }
            }
            .sheet(isPresented: $adding) { SupplementSearchView() }
            .sheet(isPresented: $showingProfile) { SettingsView() }
            .sheet(item: whyNowItem(router.whyNowGroupID)) { item in
                WhyNowView(groupID: item.id)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Reminders.reschedule()
                Task { await refreshNotificationStatus() }
            }
        }
        .task {
            Store.shared.start()
            await refreshNotificationStatus()
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let part = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        return name.isEmpty ? part : "\(part), \(name)"
    }

    /// Prefers tips about what the user actually takes.
    private var tip: Tip? {
        Content.tip(for: Day(.now, calendar: .current), preferring: Set(supplements.compactMap(\.catalogID)))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nothing here yet")
                .font(.title2.bold())
            Text("Add the supplements you already take and we'll remind you at the right moments.")
                .foregroundStyle(Color.forest.opacity(0.8))
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
                toggleTaken(item)
            } label: {
                Image(systemName: item.isTakenToday ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(item.isTakenToday ? Color.sage : Color.forest.opacity(0.4))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isTakenToday ? "Mark \(item.name) not taken" : "Mark \(item.name) taken")

            NavigationLink {
                SupplementDetailView(supplement: item)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.body.weight(.semibold))
                            .strikethrough(item.isTakenToday, color: Color.forest.opacity(0.4))
                        Text(subtitle(item))
                            .font(.subheadline)
                            .foregroundStyle(Color.forest.opacity(0.8))
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.forest.opacity(0.4))
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }

    private func subtitle(_ item: Supplement) -> String {
        let base = "\(item.doseText) · \(item.timingNote)"
        return item.takesEveryDay ? base : "\(base) · \(item.frequencyText)"
    }

    /// Taken in the app is logged like a notification Taken, so the scheduler stops reminding for today.
    private func toggleTaken(_ item: Supplement) {
        let dayKey = Day(.now, calendar: .current).key
        if item.isTakenToday {
            item.lastTakenAt = nil
            // Clears a Taken from the notification too, so history matches what Home shows.
            let id = item.planID
            let taken = DoseLog.Action.taken.rawValue
            let descriptor = FetchDescriptor<DoseLog>(predicate: #Predicate<DoseLog> { log in
                log.supplementID == id && log.dayKey == dayKey && log.actionRaw == taken
            })
            for log in (try? context.fetch(descriptor)) ?? [] {
                context.delete(log)
            }
        } else {
            item.lastTakenAt = .now
            context.insert(DoseLog(supplementID: item.planID, dayKey: dayKey, action: .taken, source: .app))
        }
        try? context.save()
        Reminders.reschedule()
    }

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = settings.authorizationStatus
    }

    private func turnOnReminders() {
        Task {
            _ = await Reminders.requestAuthorization()
            await refreshNotificationStatus()
            Reminders.reschedule()
        }
    }

    private func whyNowItem(_ groupID: String?) -> Binding<WhyNowItem?> {
        Binding(
            get: { groupID.map { WhyNowItem(id: $0) } },
            set: { item in
                if item == nil { Task { @MainActor in AppRouter.shared.whyNowGroupID = nil } }
            }
        )
    }
}

/// Wraps a group id so the sheet keeps it through the dismiss animation.
struct WhyNowItem: Identifiable, Equatable {
    let id: String
}

#if DEBUG
#Preview {
    HomeView()
        .modelContainer(PreviewData.container())
}

#Preview("Empty") {
    HomeView()
        .modelContainer(PreviewData.container(empty: true))
}
#endif
