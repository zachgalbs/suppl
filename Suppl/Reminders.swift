import Foundation
import SwiftData
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

    /// Fires a sample reminder a few seconds from now so testers can try the actions.
    /// It respects lock-screen privacy, and its actions record nothing.
    @MainActor
    static func sendTest() {
        let supplements = (try? sharedContainer.mainContext.fetch(FetchDescriptor<Supplement>())) ?? []
        let slot = supplements.first?.slot ?? .breakfast
        let names = supplements.filter { $0.slot == slot }.map(\.name)
        let request = UNNotificationRequest(
            identifier: "suppl.test",
            content: content(for: slot, names: names.isEmpty ? ["Vitamin D"] : names, category: category),
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    private static func content(for slot: Slot, names: [String], category: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        if UserDefaults.standard.bool(forKey: PrefKey.privacyMode) {
            content.title = ReminderCopy.privateTitle
            content.body = ReminderCopy.privateBody
        } else {
            content.title = slot.isMeal ? "\(slot.title) time" : slot.title
            content.body = ListFormatter.localizedString(byJoining: names)
        }
        content.sound = .default
        content.categoryIdentifier = category
        content.userInfo = ["slot": slot.rawValue, "test": true]
        return content
    }
}
