import SwiftUI

struct OnboardingView: View {
    @AppStorage("onboarded") private var onboarded = false
    @AppStorage("name") private var name = ""
    @AppStorage(Slot.wake.storageKey) private var wake = Slot.wake.defaultMinutes
    @AppStorage(Slot.breakfast.storageKey) private var breakfast = Slot.breakfast.defaultMinutes
    @AppStorage(Slot.lunch.storageKey) private var lunch = Slot.lunch.defaultMinutes
    @AppStorage(Slot.dinner.storageKey) private var dinner = Slot.dinner.defaultMinutes
    @AppStorage(Slot.bedtime.storageKey) private var bedtime = Slot.bedtime.defaultMinutes

    @State private var step = 0
    @State private var isAdult = false

    var body: some View {
        ZStack {
            Color.cream.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 24) {
                switch step {
                case 0: welcome
                case 1: about
                case 2: times
                default: notifications
                }
            }
            .padding(24)
            .foregroundStyle(Color.forest)
            .animation(.easeInOut, value: step)
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Text("suppl.")
                .font(.system(size: 56, weight: .semibold, design: .rounded))
            Text("Gentle reminders for the supplements you already take, at moments that fit your day.")
                .font(.title3)
            Spacer()
            Button("Get started") { step = 1 }
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What should we call you?")
                .font(.largeTitle.bold())
            TextField("Your name", text: $name)
                .font(.title3)
                .textContentType(.givenName)
                .padding()
                .background(Color.white.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Toggle("I'm 18 or older", isOn: $isAdult)
                .font(.body)
            Spacer()
            Button("Continue") { step = 2 }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || !isAdult)
                .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty || !isAdult ? 0.5 : 1)
        }
    }

    private var times: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your usual day")
                .font(.largeTitle.bold())
            Text("Roughly is fine. You can change these anytime.")
                .foregroundStyle(Color.forest.opacity(0.7))
            VStack(spacing: 4) {
                timeRow(.wake, $wake)
                timeRow(.breakfast, $breakfast)
                timeRow(.lunch, $lunch)
                timeRow(.dinner, $dinner)
                timeRow(.bedtime, $bedtime)
            }
            .card()
            Spacer()
            Button("Continue") { step = 3 }
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var notifications: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Image(systemName: "bell.badge")
                .font(.system(size: 48))
                .foregroundStyle(Color.sage)
            Text("One nudge, at the right time")
                .font(.largeTitle.bold())
            Text("We'll remind you around meals, with Taken, Snooze, and Skip right in the notification. Never more than one follow-up.")
                .font(.title3)
            Spacer()
            Button("Turn on reminders") {
                Task {
                    _ = await Reminders.requestAuthorization()
                    onboarded = true
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            Button("Not now") { onboarded = true }
                .frame(maxWidth: .infinity)
                .foregroundStyle(Color.forest.opacity(0.7))
        }
    }

    private func timeRow(_ slot: Slot, _ value: Binding<Int>) -> some View {
        DatePicker(selection: value.asTime, displayedComponents: .hourAndMinute) {
            Label(slot.title, systemImage: slot.symbol)
        }
    }
}

#Preview {
    OnboardingView()
}
