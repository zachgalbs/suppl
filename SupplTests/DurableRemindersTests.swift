import XCTest
import UserNotifications
import SupplCore
@testable import suppl

/// R14 at the app layer: the requests the scheduler hands iOS for the busiest routine, and what is
/// left firing if the app never runs again.
@MainActor
final class DurableRemindersTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 0, minute: 1))! }
    /// What the old build left pending: repeating `suppl.<slot>` and `suppl.followup.<slot>` for its five slots.
    private let legacy = Slot.allCases.filter { $0 != .postWorkout }
        .flatMap { ["suppl.\($0.rawValue)", "suppl.followup.\($0.rawValue)"] }

    /// One supplement per slot, Extra Help, quiet hours off: the most requests anyone can need.
    private func routine() -> (supplements: [Supplement], prefs: Preferences) {
        let name = "DurableRemindersTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        d.set(Intensity.extraHelp.rawValue, forKey: PrefKey.intensity)
        d.set(0, forKey: PrefKey.quietStart)
        d.set(0, forKey: PrefKey.quietEnd)
        let supplements = Slot.allCases.map { Supplement(name: $0.title, slot: $0) }
        for s in supplements { s.createdAt = now.addingTimeInterval(-86_400) }
        return (supplements, Preferences.current(Features(isPro: true, smartTimingFree: true), connectedSources: [], defaults: d))
    }

    /// The engine reminders plus the heads-up, built exactly as `NotificationScheduler` builds them.
    private func requests(_ supplements: [Supplement], logs: [DoseLog] = [], prefs: Preferences,
                          pending: [String]) -> [UNNotificationRequest] {
        let plans = supplements.map(\.dosePlan)
        let decisions = ReminderEngine.plan(
            plans: plans,
            statuses: EngineInputs.statuses(for: supplements, logs: logs, now: now, calendar: calendar),
            signals: [], history: [], prefs: prefs, now: now, calendar: calendar,
            budget: NotificationBudget.engineSlots(foreign: NotificationBudget.foreignCount(pending)))
        var result = decisions.map { d in
            NotificationScheduler.makeRequest(
                for: d, text: ReminderCopy.notification(for: d, plans: plans, privacyMode: prefs.privacyMode,
                                                        calendar: calendar, locale: Locale(identifier: "en_US")),
                calendar: calendar)
        }
        if let date = ReminderEngine.headsUpDate(for: decisions, prefs: prefs, calendar: calendar) {
            result.append(NotificationScheduler.makeHeadsUpRequest(at: date, calendar: calendar))
        }
        return result
    }

    private func fireDate(_ request: UNNotificationRequest) -> Date? {
        (request.trigger as? UNCalendarNotificationTrigger).flatMap { calendar.date(from: $0.dateComponents) }
    }

    func testBusiestRoutineNeverExceedsTheLimitEvenWhileUpgrading() {
        let r = routine()
        for pending in [[], legacy, legacy + [NotificationBudget.testID]] {
            let out = requests(r.supplements, prefs: r.prefs, pending: pending)
            XCTAssertEqual(Set(out.map(\.identifier)).count, out.count, "no duplicate requests")
            XCTAssertTrue(out.contains { $0.identifier == NotificationBudget.headsUpID }, "the heads-up always fits")
            // Counts the old build's requests as still pending and the Debug test reminder as present.
            let total = Set(out.map(\.identifier) + pending + [NotificationBudget.testID]).count
            XCTAssertLessThanOrEqual(total, NotificationBudget.pendingLimit)
            XCTAssertTrue(out.allSatisfy { ($0.trigger as? UNCalendarNotificationTrigger)?.repeats == false })
        }
    }

    func testZeroLaunchesKeepRemindersComingThenWarnAheadOfTheLast() throws {
        let r = routine()
        // The first run after upgrading has the fewest slots.
        let out = requests(r.supplements, prefs: r.prefs, pending: legacy)
        let headsUp = try XCTUnwrap(out.first { $0.identifier == NotificationBudget.headsUpID }.flatMap(fireDate))
        let initials = out.filter { $0.content.categoryIdentifier == Reminders.category }.compactMap(fireDate)
        let last = try XCTUnwrap(initials.max())
        XCTAssertLessThanOrEqual(headsUp, last.addingTimeInterval(-24 * 3600))
        XCTAssertTrue(initials.contains(headsUp), "shares a reminder's time, so it adds no new interruption")
        let ids = Set(out.map(\.identifier))
        for offset in 0..<6 {
            let day = Day(now, calendar: calendar).adding(days: offset, calendar: calendar)
            for slot in Slot.allCases {
                let moment = try XCTUnwrap(Moment(rawValue: slot.rawValue))
                XCTAssertTrue(ids.contains(ReminderID.make(day: day, moment: moment, stage: .initial)), "\(day) \(slot)")
            }
        }
    }

    func testTakenAndSkippedDosesLeaveNothingPending() throws {
        let r = routine()
        let today = Day(now, calendar: calendar)
        let breakfast = try XCTUnwrap(r.supplements.first { $0.slot == .breakfast })
        breakfast.lastTakenAt = now
        let lunch = try XCTUnwrap(r.supplements.first { $0.slot == .lunch })
        let skip = DoseLog(supplementID: lunch.planID, dayKey: today.key, action: .skipped, at: now, source: .notification)
        let out = requests(r.supplements, logs: [skip], prefs: r.prefs, pending: [])
        for moment in [Moment.breakfast, .lunch] {
            XCTAssertFalse(out.contains { $0.content.threadIdentifier == ReminderID.group(day: today, moment: moment) })
        }
        XCTAssertTrue(out.contains { $0.identifier == NotificationBudget.headsUpID })
    }

    func testQuietHoursHoldForRemindersAndTheHeadsUp() throws {
        let r = routine()
        var prefs = r.prefs
        prefs.quietHours = QuietHours(start: 23 * 60, end: 7 * 60 + 30)
        for request in requests(r.supplements, prefs: prefs, pending: []) {
            let date = try XCTUnwrap(fireDate(request))
            let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
            XCTAssertFalse(minute >= 23 * 60 || minute < 7 * 60 + 30, request.identifier)
        }
    }

    func testHeadsUpNamesNoDoseAndIsMovedNotDuplicated() {
        let at = now.addingTimeInterval(3600)
        let request = NotificationScheduler.makeHeadsUpRequest(at: at, calendar: calendar)
        XCTAssertEqual(request.identifier, NotificationBudget.headsUpID)
        XCTAssertEqual(request.content.categoryIdentifier, "", "no Taken, Snooze, or Skip to act on")
        XCTAssertNil(request.content.userInfo["plans"])
        XCTAssertEqual(request.content.body, "Open suppl. to keep your reminders coming.")
        XCTAssertFalse(ReminderID.isEngineID(request.identifier), "never swept up as a stale reminder")
        XCTAssertEqual((request.trigger as? UNCalendarNotificationTrigger)?.repeats, false)
        let tap = ReminderResponse(action: UNNotificationDefaultActionIdentifier, userInfo: request.content.userInfo)
        XCTAssertTrue(tap.isHeadsUp)
        XCTAssertNil(tap.planIDs)
        // One identifier: a re-plan replaces it in place.
        XCTAssertTrue(NotificationScheduler.isSame(request, as: NotificationScheduler.makeHeadsUpRequest(at: at, calendar: calendar)))
        XCTAssertFalse(NotificationScheduler.isSame(
            request, as: NotificationScheduler.makeHeadsUpRequest(at: at.addingTimeInterval(3600), calendar: calendar)))
    }
}
