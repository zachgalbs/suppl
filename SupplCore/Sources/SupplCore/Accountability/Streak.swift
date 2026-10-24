import Foundation

/// Consecutive days on which the user confirmed every dose that was due. Only user-confirmed
/// doses count: a delivered notification, or no response, never does.
public enum Streak {
    public struct Plan: Sendable {
        public var plan: DosePlan
        /// The day the user added it. Days before that don't expect it.
        public var since: Day

        public init(plan: DosePlan, since: Day) {
            self.plan = plan
            self.since = since
        }
    }

    /// Today counts once it's complete; until then the streak runs through yesterday, so an
    /// unfinished morning never reads as a broken streak. Days with nothing due are skipped,
    /// so a weekday-only routine isn't broken by the weekend.
    public static func confirmedDays(plans: [Plan], confirmed: [String: Set<Day>], today: Day,
                                     calendar: Calendar, lookBack: Int = 366) -> Int {
        guard !plans.isEmpty, let earliest = plans.map(\.since).min() else { return 0 }
        var count = 0
        for offset in 0..<lookBack {
            let day = today.adding(days: -offset, calendar: calendar)
            guard day >= earliest else { break }
            let due = plans.filter { $0.since <= day && ReminderEngine.isDue($0.plan, on: day, calendar: calendar) }
            if due.isEmpty { continue }
            let complete = due.allSatisfy { confirmed[$0.plan.id]?.contains(day) == true }
            if complete {
                count += 1
            } else if offset > 0 {
                break
            }
        }
        return count
    }
}
