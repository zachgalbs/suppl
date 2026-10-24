import SwiftUI
import SwiftData
import UserNotifications
import SupplCore

/// Profile: Zach's settings plus reminder preferences, connected apps, membership, and data.
@MainActor
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("onboarded") private var onboarded = true
    @AppStorage("name") private var name = ""
    @AppStorage(Slot.wake.storageKey) private var wake = Slot.wake.defaultMinutes
    @AppStorage(Slot.breakfast.storageKey) private var breakfast = Slot.breakfast.defaultMinutes
    @AppStorage(Slot.lunch.storageKey) private var lunch = Slot.lunch.defaultMinutes
    @AppStorage(Slot.dinner.storageKey) private var dinner = Slot.dinner.defaultMinutes
    @AppStorage(Slot.bedtime.storageKey) private var bedtime = Slot.bedtime.defaultMinutes
    @AppStorage(Slot.postWorkout.storageKey) private var postWorkout = Slot.postWorkout.defaultMinutes
    @AppStorage(PrefKey.intensity) private var intensityRaw = Intensity.balanced.rawValue
    @AppStorage(PrefKey.privacyMode) private var privacyMode = false
    @AppStorage(PrefKey.quietStart) private var quietStart = -1
    @AppStorage(PrefKey.quietEnd) private var quietEnd = -1

    @State private var confirmingReset = false
    #if DEBUG
    @State private var testSent = false
    @State private var testError: String?
    #endif
    @State private var showingPaywall = false

    private var isPro: Bool { Store.shared.isPro }

    var body: some View {
        NavigationStack {
            Form {
                Section("You") {
                    TextField("Name", text: $name)
                }

                usualTimes
                reminderStyle
                QuietHoursSection()
                privacy
                connections
                MembershipSection(showingPaywall: $showingPaywall)

                #if DEBUG
                Section {
                    Button(testSent ? "Test scheduled. Lock your phone." : "Send a test reminder in 5 seconds") {
                        Task {
                            do {
                                try await Reminders.sendTest()
                                testSent = true
                                testError = nil
                            } catch {
                                testError = "Couldn't schedule the test reminder. Try again."
                            }
                        }
                    }
                    if let testError { Text(testError) }
                } footer: {
                    Text("Long-press to try the actions. Test actions don't change your routine.")
                }
                #endif

                Section {
                    Button("Delete all data", role: .destructive) { confirmingReset = true }
                } header: {
                    Text("Data")
                } footer: {
                    Text("suppl. reminds you to take what you already use. It doesn't give medical advice. Talk to a pharmacist or doctor about doses and interactions.\n\nVersion \(Bundle.main.appVersion)")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.cream)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Delete all data and start over?", isPresented: $confirmingReset, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive, action: reset)
            } message: {
                Text("This removes your supplements, reminder history, and settings, and disconnects your apps. It doesn't cancel a subscription.")
            }
            .sheet(isPresented: $showingPaywall) { PaywallView() }
            .onChange(of: [wake, breakfast, lunch, dinner, bedtime, postWorkout, quietStart, quietEnd]) {
                Reminders.reschedule()
            }
            .onChange(of: intensityRaw) { Reminders.reschedule() }
            .onChange(of: privacyMode) { Reminders.reschedule() }
            .onDisappear { Reminders.reschedule() }
        }
    }

    private var usualTimes: some View {
        Section {
            time(.wake, $wake)
            time(.breakfast, $breakfast)
            time(.lunch, $lunch)
            time(.dinner, $dinner)
            time(.bedtime, $bedtime)
            time(.postWorkout, $postWorkout)
        } header: {
            Text("Usual times")
        } footer: {
            Text("\"After a workout\" reminders come at this time when no workout is recorded.")
        }
    }

    private var intensity: Binding<Intensity> {
        // Read here, on the main actor, so the binding's closures don't touch Store.
        let pro = isPro
        return Binding(
            get: { Intensity(rawValue: intensityRaw) ?? .balanced },
            set: { new in
                if new.needsPro && !pro {
                    showingPaywall = true
                } else {
                    intensityRaw = new.rawValue
                }
            }
        )
    }

    private var reminderStyle: some View {
        Section("Reminder style") {
            Picker("Reminder style", selection: intensity) {
                ForEach(Intensity.allCases, id: \.self) { option in
                    styleLabel(option).tag(option)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }

    private func styleLabel(_ option: Intensity) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(option.needsPro && !isPro ? "\(option.title) (Pro)" : option.title)
            Text(option.detail)
                .font(.subheadline)
                .foregroundStyle(Color.forest.opacity(0.8))
        }
    }

    private var privacy: some View {
        Section {
            Toggle("Private lock-screen text", isOn: $privacyMode)
        } footer: {
            Text("Reminders will say \"suppl. has a reminder for you\" instead of naming your supplements.")
        }
    }

    private var connections: some View {
        Section {
            NavigationLink("Connected apps") { ConnectedAppsView() }
            if isPro {
                NavigationLink("Recent reminders") { RecentRemindersView() }
            } else {
                Button {
                    showingPaywall = true
                } label: {
                    HStack {
                        Text("Recent reminders")
                            .foregroundStyle(Color.forest)
                        Spacer()
                        Text("Pro")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.forest)
                    }
                }
            }
        }
    }

    private func time(_ slot: Slot, _ value: Binding<Int>) -> some View {
        DatePicker(selection: value.asTime, displayedComponents: .hourAndMinute) {
            Label(slot.title, systemImage: slot.symbol)
        }
    }

    /// Everything the app stores on this phone. Subscriptions belong to the Apple ID and aren't touched.
    private func reset() {
        try? context.delete(model: Supplement.self)
        try? context.delete(model: DoseLog.self)
        try? context.delete(model: DecisionLog.self)
        try? context.save()
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        let keys = [PrefKey.intensity, PrefKey.quietStart, PrefKey.quietEnd, PrefKey.privacyMode,
                    PrefKey.birthYear, PrefKey.isAdult, PrefKey.takesSupplements] + Slot.allCases.map(\.storageKey)
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        AppRouter.shared.whyNowGroupID = nil
        Task {
            await ConnectorHub.shared.disconnectAll()
            name = ""
            onboarded = false
        }
    }
}

extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

#if DEBUG
#Preview {
    SettingsView()
        .modelContainer(PreviewData.container())
}
#endif
