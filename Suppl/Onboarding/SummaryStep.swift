import SwiftUI
import SwiftData
import UserNotifications
import SupplCore

/// An honest recap built from what the user actually entered. No scores, no invented problems.
@MainActor
struct SummaryStep: View {
    let finish: () -> Void
    @Query(sort: \Supplement.createdAt) private var supplements: [Supplement]
    @AppStorage(PrefKey.takesSupplements) private var habitRaw = ""
    @AppStorage(PrefKey.intensity) private var intensityRaw = Intensity.balanced.rawValue
    @State private var notificationStatus: UNAuthorizationStatus?

    private var notYet: Bool { habitRaw == SupplementHabit.notYet.rawValue }
    private var hub: ConnectorHub { .shared }

    var body: some View {
        OnboardingPage(notYet ? "That's fine" : "You're all set", primary: notYet ? "Go to suppl." : "Continue",
                       onPrimary: finish) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.title3)
                }
            }
            .card()
        }
        .task {
            notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        }
    }

    private var lines: [String] {
        if notYet {
            return ["suppl. is here whenever you need it. If you start taking something, add it from Home and we'll handle the reminders."]
        }
        var result = [supplementLine]
        let style = Intensity(rawValue: intensityRaw) ?? .balanced
        result.append("Reminder style: \(style.title). \(style.detail)")
        let connected = hub.connectors.filter { $0.authorization == .connected }.map { $0.displayName }
        if !connected.isEmpty {
            result.append("Apps you set up: \(ListFormatter.localizedString(byJoining: connected)).")
        }
        if notificationStatus == .denied || notificationStatus == .notDetermined {
            result.append("Reminders are off for now. You can turn them on from Home.")
        }
        return result
    }

    private var supplementLine: String {
        guard !supplements.isEmpty else {
            return "You haven't added any supplements yet. Add them from Home whenever you're ready."
        }
        let count = supplements.count == 1 ? "1 supplement" : "\(supplements.count) supplements"
        let slots = Slot.allCases.filter { slot in supplements.contains { $0.slot == slot } }
        let moments = ListFormatter.localizedString(byJoining: slots.map(phrase))
        return "You're taking \(count). We'll remind you \(moments)."
    }

    /// "After workouts" only when something can actually see a workout and Pro is on; otherwise the real fallback time.
    private func phrase(_ slot: Slot) -> String {
        switch slot {
        case .wake: return "when you wake up"
        case .breakfast: return "around breakfast"
        case .lunch: return "around lunch"
        case .dinner: return "around dinner"
        case .bedtime: return "before bed"
        case .postWorkout:
            let canSeeWorkouts = !hub.connectedSources.isDisjoint(with: [.appleHealth, .whoop])
            let fixedGroup = supplements.contains { $0.slot == .postWorkout && $0.clinicianDirected }
            if canSeeWorkouts && Store.shared.isPro && !fixedGroup { return "after recorded workouts when data is available" }
            return "at \(timeText(Slot.postWorkout.minutes)) for after-workout supplements"
        }
    }
}

#if DEBUG
#Preview {
    SummaryStep {}
        .padding(24)
        .background(Color.cream)
        .foregroundStyle(Color.forest)
        .modelContainer(PreviewData.container())
}
#endif
