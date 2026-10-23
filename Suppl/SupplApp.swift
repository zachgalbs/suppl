import SwiftUI
import SwiftData
import UserNotifications

@main
struct SupplApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("onboarded") private var onboarded = false
    @Environment(\.scenePhase) private var scenePhase

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
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { BackgroundRefresh.schedule() }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Reminders.registerCategories()
        Supplement.backfillIDs(in: sharedContainer.mainContext)
        Store.shared.start()
        BackgroundRefresh.register()

        // Context changes re-plan with fresh connector data. Both are no-ops until the user connects.
        let hub = ConnectorHub.shared
        hub.health.startObservingWorkouts { await NotificationScheduler.run(refreshSignals: true) }
        hub.calendar.observeChanges { await NotificationScheduler.run(refreshSignals: true) }

        // Reminders are planned in local wall-clock time, so travel and clock changes re-plan.
        for name in [Notification.Name.NSSystemTimeZoneDidChange, UIApplication.significantTimeChangeNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in Reminders.reschedule() }
            }
        }
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        // Taken / Snooze / Skip are recorded; tapping the notification opens "Why now?"; dismissing records nothing.
        let reply = ReminderResponse(action: response.actionIdentifier,
                                     userInfo: response.notification.request.content.userInfo)
        await ReminderActions.handle(reply)
    }
}
