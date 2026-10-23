import SwiftUI
import SwiftData

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

    @State private var confirmingReset = false
    @State private var testSent = false

    var body: some View {
        NavigationStack {
            Form {
                Section("You") {
                    TextField("Name", text: $name)
                }

                Section("Usual times") {
                    time(.wake, $wake)
                    time(.breakfast, $breakfast)
                    time(.lunch, $lunch)
                    time(.dinner, $dinner)
                    time(.bedtime, $bedtime)
                }

                Section {
                    Button(testSent ? "Sent. Lock your phone." : "Send a test reminder in 5 seconds") {
                        Reminders.sendTest()
                        testSent = true
                    }
                } footer: {
                    Text("Long-press the notification to see Taken, Snooze, and Skip.")
                }

                Section {
                    Button("Reset app", role: .destructive) { confirmingReset = true }
                } footer: {
                    Text("suppl. reminds you to take what you already use. It doesn't give medical advice. Talk to a pharmacist or doctor about doses and interactions.\n\nVersion \(Bundle.main.appVersion)")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.cream)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Delete all supplements and start over?", isPresented: $confirmingReset, titleVisibility: .visible) {
                Button("Reset", role: .destructive, action: reset)
            }
            .onDisappear { Reminders.reschedule() }
        }
    }

    private func time(_ slot: Slot, _ value: Binding<Int>) -> some View {
        DatePicker(selection: value.asTime, displayedComponents: .hourAndMinute) {
            Label(slot.title, systemImage: slot.symbol)
        }
    }

    private func reset() {
        try? context.delete(model: Supplement.self)
        try? context.save()
        Reminders.reschedule()
        name = ""
        onboarded = false
    }
}

extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
