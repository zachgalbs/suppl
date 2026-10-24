import Foundation

/// How many requests the app may keep pending. iOS keeps only the soonest-firing 64 local notifications
/// and discards the rest, so going over would silently drop the farthest reminders, heads-up included.
public enum NotificationBudget {
    public static let pendingLimit = 64
    /// "Open suppl. to keep your reminders coming." Replaced on every re-plan; never a dose reminder.
    public static let headsUpID = "suppl.headsup"
    /// The Debug test reminder.
    public static let testID = "suppl.test"
    /// The heads-up and the test reminder always have a slot.
    public static let reserved = 2

    /// Slots left for engine reminders while `foreign` other requests are pending.
    public static func engineSlots(foreign: Int) -> Int {
        max(0, pendingLimit - reserved - max(0, foreign))
    }

    /// Pending requests the engine doesn't manage (old builds' ids, anything unknown). They are counted
    /// even while being removed, because removal finishes asynchronously.
    public static func foreignCount(_ pendingIDs: [String]) -> Int {
        Set(pendingIDs).filter { !ReminderID.isEngineID($0) && $0 != headsUpID && $0 != testID }.count
    }
}
