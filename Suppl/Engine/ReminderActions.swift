import Foundation
import SwiftData
import SupplCore
import UserNotifications

/// What the user did with a notification, pulled out of `userInfo` so it can cross to the main actor.
struct ReminderResponse: Sendable {
    var action: String
    var slot: String?
    var groupID: String?
    var dayKey: String?
    var planIDs: [String]?
    /// The Profile test reminder. Its actions record nothing, so testing never marks a real dose.
    var isTest: Bool

    init(action: String, userInfo: [AnyHashable: Any]) {
        self.action = action
        slot = userInfo["slot"] as? String
        groupID = userInfo["group"] as? String
        dayKey = userInfo["day"] as? String
        planIDs = userInfo["plans"] as? [String]
        isTest = userInfo["test"] as? Bool ?? false
    }
}

/// Taken / Snooze / Skip from a notification. Each records a `DoseLog` and re-plans, which clears
/// or replaces that group's follow-ups. Tapping the notification itself opens "Why now?".
@MainActor
enum ReminderActions {
    static func handle(_ response: ReminderResponse, now: Date = .now) async {
        guard !response.isTest else { return }
        let calendar = Calendar.current
        let todayKey = Day(now, calendar: calendar).key
        let dayKey = response.dayKey ?? todayKey
        let context = sharedContainer.mainContext
        let all = (try? context.fetch(FetchDescriptor<Supplement>())) ?? []

        // Notifications from builds before v1 only carry the slot.
        let targets: [Supplement]
        if let ids = response.planIDs {
            targets = all.filter { ids.contains($0.planID) }
        } else if let raw = response.slot, let slot = Slot(rawValue: raw) {
            targets = all.filter { $0.slot == slot }
        } else {
            targets = []
        }

        switch response.action {
        case Reminders.takenAction:
            for s in targets {
                // A bedtime reminder tapped after midnight belongs to yesterday; it mustn't mark today taken.
                if dayKey == todayKey { s.lastTakenAt = now }
                context.insert(DoseLog(supplementID: s.planID, dayKey: dayKey, action: .taken, at: now, source: .notification))
            }
        case Reminders.snoozeAction:
            let until = now.addingTimeInterval(TimeInterval(Reminders.snoozeMinutes * 60))
            for s in targets {
                context.insert(DoseLog(supplementID: s.planID, dayKey: dayKey, action: .snoozed, at: now,
                                       snoozedUntil: until, source: .notification))
            }
        case Reminders.skipAction:
            for s in targets {
                context.insert(DoseLog(supplementID: s.planID, dayKey: dayKey, action: .skipped, at: now, source: .notification))
            }
        case UNNotificationDefaultActionIdentifier:
            if let group = response.groupID ?? response.slot.flatMap({ Moment(rawValue: $0) })
                .map({ ReminderID.group(day: Day(now, calendar: calendar), moment: $0) }) {
                AppRouter.shared.whyNowGroupID = group
            }
            return
        default:
            return // Dismissed: no response stays unconfirmed.
        }
        try? context.save()
        // Pull this group's follow-ups now, before re-planning: if iOS suspends the app mid-run,
        // a stale "Still open" must not fire after Taken or Skip. A snooze is re-added by the engine.
        if let group = response.groupID {
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: ["\(group).f1", "\(group).f2", "\(group).s"])
        }
        await NotificationScheduler.run()
    }
}
