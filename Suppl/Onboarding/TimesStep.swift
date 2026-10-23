import SwiftUI
import SwiftData

/// Zach's usual-day screen. The post-workout row only appears for people who take something after workouts.
struct TimesStep: View {
    let next: () -> Void
    @Query private var supplements: [Supplement]
    @AppStorage(Slot.wake.storageKey) private var wake = Slot.wake.defaultMinutes
    @AppStorage(Slot.breakfast.storageKey) private var breakfast = Slot.breakfast.defaultMinutes
    @AppStorage(Slot.lunch.storageKey) private var lunch = Slot.lunch.defaultMinutes
    @AppStorage(Slot.dinner.storageKey) private var dinner = Slot.dinner.defaultMinutes
    @AppStorage(Slot.bedtime.storageKey) private var bedtime = Slot.bedtime.defaultMinutes
    @AppStorage(Slot.postWorkout.storageKey) private var postWorkout = Slot.postWorkout.defaultMinutes

    private var takesPostWorkout: Bool { supplements.contains { $0.slot == .postWorkout } }

    var body: some View {
        OnboardingPage("Your usual day", subtitle: "Roughly is fine. You can change these anytime.", onPrimary: next) {
            VStack(spacing: 4) {
                timeRow(.wake, $wake)
                timeRow(.breakfast, $breakfast)
                timeRow(.lunch, $lunch)
                timeRow(.dinner, $dinner)
                timeRow(.bedtime, $bedtime)
                if takesPostWorkout {
                    timeRow(.postWorkout, $postWorkout)
                }
            }
            .card()
            if takesPostWorkout {
                Text("\"After a workout\" reminders come at this time when no workout is recorded.")
                    .font(.footnote)
                    .foregroundStyle(Color.forest.opacity(0.8))
            }
        }
    }

    private func timeRow(_ slot: Slot, _ value: Binding<Int>) -> some View {
        DatePicker(selection: value.asTime, displayedComponents: .hourAndMinute) {
            Label(slot.title, systemImage: slot.symbol)
        }
        .frame(minHeight: 44)
    }
}

#if DEBUG
#Preview {
    TimesStep {}
        .padding(24)
        .background(Color.cream)
        .foregroundStyle(Color.forest)
        .modelContainer(PreviewData.container())
}
#endif
