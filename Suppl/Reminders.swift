import Foundation
import SupplCore
import UserNotifications

/// Notification categories, permission, and the entry point for re-planning reminders.
/// Category and action identifiers must not change: notifications from older builds still route through them.
enum Reminders {
    static let category = "SUPPL_REMINDER"
    static let followUpCategory = "SUPPL_FOLLOWUP"
    static let takenAction = "TAKEN"
    static let snoozeAction = "SNOOZE"
    static let skipAction = "SKIP"
    static let snoozeMinutes = 30

    static func registerCategories() {
        let taken = UNNotificationAction(identifier: takenAction, title: "Taken")
        let snooze = UNNotificationAction(identifier: snoozeAction, title: "Snooze \(snoozeMinutes) min")
        let skip = UNNotificationAction(identifier: skipAction, title: "Skip today")
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: category, actions: [taken, snooze, skip], intentIdentifiers: []),
            // Balanced mode: the follow-up can't be snoozed again.
            UNNotificationCategory(identifier: followUpCategory, actions: [taken, skip], intentIdentifiers: []),
        ])
    }

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Re-plans every pending reminder. The engine decides what to send and when; see `NotificationScheduler`.
    /// Kept as the one entry point so every existing call site (save, delete, foreground, settings) still works.
    @MainActor
    static func reschedule() {
        Task { await NotificationScheduler.run() }
    }

    #if DEBUG
    /// A clearly labelled sample. Test actions never record a real dose.
    @MainActor
    static func sendTest() async throws {
        let content = UNMutableNotificationContent()
        if UserDefaults.standard.bool(forKey: PrefKey.privacyMode) {
            content.title = ReminderCopy.privateTitle
            content.body = ReminderCopy.privateBody
        } else {
            content.title = "suppl. test reminder"
            content.body = "This is a test. Its actions don't change your routine."
        }
        content.sound = .default
        content.categoryIdentifier = category
        content.userInfo = ["test": true]
        let request = UNNotificationRequest(identifier: NotificationBudget.testID, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false))
        try await UNUserNotificationCenter.current().add(request)
    }
    #endif
}
