import SwiftUI
import SwiftData
import UserNotifications

@main
struct SupplApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("onboarded") private var onboarded = false

    var body: some Scene {
        WindowGroup {
            Group {
                if onboarded {
                    HomeView()
                } else {
                    OnboardingView()
                }
            }
            .tint(.sage)
            .preferredColorScheme(.light)
        }
        .modelContainer(sharedContainer)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Reminders.registerCategories()
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard let raw = response.notification.request.content.userInfo["slot"] as? String,
              let slot = Slot(rawValue: raw) else { return }

        switch response.actionIdentifier {
        case Reminders.takenAction:
            await MainActor.run { Reminders.markTaken(slot: slot) }
        case Reminders.snoozeAction:
            let names = await MainActor.run { Reminders.names(in: slot) }
            Reminders.scheduleFollowUp(for: slot, names: names)
        default:
            break // Skip, dismiss, or tapping the banner: nothing to record.
        }
    }
}
