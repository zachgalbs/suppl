import Foundation
import SwiftData
import UserNotifications

/// Schedules one repeating local notification per slot that has supplements in it.
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

    @MainActor
    static func reschedule() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: Slot.allCases.map { "suppl.\($0.rawValue)" })

        let supplements = (try? sharedContainer.mainContext.fetch(FetchDescriptor<Supplement>())) ?? []
        for slot in Slot.allCases {
            let names = supplements.filter { $0.slot == slot }.map(\.name)
            guard !names.isEmpty else { continue }

            var when = DateComponents()
            when.hour = slot.minutes / 60
            when.minute = slot.minutes % 60
            let request = UNNotificationRequest(
                identifier: "suppl.\(slot.rawValue)",
                content: content(for: slot, names: names, category: category),
                trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
            )
            center.add(request)
        }
    }

    static func scheduleFollowUp(for slot: Slot, names: [String]) {
        let request = UNNotificationRequest(
            identifier: "suppl.followup.\(slot.rawValue)",
            content: content(for: slot, names: names, category: followUpCategory),
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(snoozeMinutes * 60), repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Fires a sample reminder a few seconds from now so testers can try the actions.
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
        content.title = slot.isMeal ? "\(slot.title) time" : slot.title
        content.body = ListFormatter.localizedString(byJoining: names)
        content.sound = .default
        content.categoryIdentifier = category
        content.userInfo = ["slot": slot.rawValue]
        return content
    }

    @MainActor
    static func markTaken(slot: Slot) {
        let context = sharedContainer.mainContext
        let supplements = (try? context.fetch(FetchDescriptor<Supplement>())) ?? []
        for s in supplements where s.slot == slot {
            s.lastTakenAt = .now
        }
        try? context.save()
    }

    @MainActor
    static func names(in slot: Slot) -> [String] {
        let supplements = (try? sharedContainer.mainContext.fetch(FetchDescriptor<Supplement>())) ?? []
        return supplements.filter { $0.slot == slot }.map(\.name)
    }
}
