import SwiftUI
import SupplCore

/// Asks for notification permission after the user knows what they'll get, as Zach's flow did.
struct NotificationsStep: View {
    let next: () -> Void
    @AppStorage(PrefKey.intensity) private var intensityRaw = Intensity.balanced.rawValue

    private var followUps: String {
        switch Intensity(rawValue: intensityRaw) ?? .balanced {
        case .gentle: "No follow-ups."
        case .balanced: "Never more than one follow-up."
        case .extraHelp: "Never more than two follow-ups."
        }
    }

    var body: some View {
        OnboardingPage("One nudge, at the right time", primary: "Turn on reminders",
                       secondary: "Not now", onPrimary: turnOn, onSecondary: next) {
            Image(systemName: "bell.badge")
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(Color.sage)
                .accessibilityHidden(true)
            Text("We'll remind you with Taken, Snooze, and Skip right in the notification. \(followUps)")
                .font(.title3)
        }
    }

    private func turnOn() {
        Task {
            _ = await Reminders.requestAuthorization()
            // Anything added earlier in onboarding couldn't be scheduled before permission existed.
            Reminders.reschedule()
            next()
        }
    }
}

#if DEBUG
#Preview {
    NotificationsStep {}
        .padding(24)
        .background(Color.cream)
        .foregroundStyle(Color.forest)
}
#endif
