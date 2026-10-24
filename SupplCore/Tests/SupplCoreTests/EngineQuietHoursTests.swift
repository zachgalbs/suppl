import XCTest
@testable import SupplCore

/// Quiet hours, the bedtime exception, DST days, and time-zone changes.
final class EngineQuietHoursTests: XCTestCase {
    typealias F = EngineFixtures

    // MARK: Quiet hours

    func testDefaultQuietHoursRunFromBedtimeWindowEndToWakeWindowStart() {
        XCTAssertEqual(Preferences().effectiveQuietHours, QuietHours(start: 22 * 60 + 30, end: 6 * 60 + 45))
        XCTAssertEqual(F.prefs(quiet: QuietHours(start: 60, end: 120)).effectiveQuietHours, QuietHours(start: 60, end: 120))
        // Wraps around midnight in both directions.
        let late = F.prefs { $0.usualTimes[.bedtime] = 23 * 60 + 30; $0.usualTimes[.wake] = 10 }
        XCTAssertEqual(late.effectiveQuietHours, QuietHours(start: 0, end: 24 * 60 - 5))
    }

    func testReminderInQuietHoursMovesToTheirEndWhenStillInsideTheWindow() {
        let prefs = F.prefs(intensity: .gentle, quiet: QuietHours(start: 23 * 60, end: 7 * 60)) {
            $0.usualTimes[.wake] = 6 * 60 + 30
        }
        let d = F.run([F.plan("b12", .wake)], prefs: prefs, now: F.at(5, 0)).decision(F.id(F.today, .wake))
        XCTAssertEqual(d?.fireDate, F.at(7, 0))
        XCTAssertEqual(d?.reason.trigger, .quietHours)
        XCTAssertEqual(d?.reason.usualDate, F.at(6, 30))
        XCTAssertEqual(d?.reason.ruleID, "timing.quietHours.v1")
    }

    func testQuietHoursSpanningMidnightMoveIntoTheNextDay() {
        // Late lunch at 23:40 (window 23:10 to 1:10), quiet 23:00 to 0:30.
        let prefs = F.prefs(intensity: .gentle, quiet: QuietHours(start: 23 * 60, end: 30)) {
            $0.usualTimes[.lunch] = 23 * 60 + 40
        }
        let d = F.run([F.plan("l", .lunch)], prefs: prefs, now: F.at(20, 0)).decision(F.id(F.today, .lunch))
        XCTAssertEqual(d?.fireDate, F.at(0, 30, day: 24))
        XCTAssertEqual(d?.day, F.today, "the group keeps its own day key")
    }

    func testReminderInQuietHoursPastItsWindowIsDropped() {
        let prefs = F.prefs(quiet: QuietHours(start: 18 * 60, end: 21 * 60))
        let out = F.run([F.plan("fish", .dinner)], prefs: prefs, now: F.at(12, 0))
        // Dinner 18:30 is quiet until 21:00, after the 20:00 window end: no reminder, no follow-ups.
        XCTAssertFalse(out.contains { $0.day == F.today })
    }

    func testFollowUpInQuietHoursIsDropped() {
        let out = F.run([F.plan("mel", .bedtime)], prefs: F.prefs(), now: F.at(20, 0)).filter { $0.day == F.today }
        // Bedtime 22:00 fires; its follow-up at 22:30 is the first minute of quiet hours.
        XCTAssertEqual(out.reminderIDs, ["suppl.2026-10-23.bedtime"])
    }

    func testBedtimeIsNotSuppressedByQuietHoursStartingInsideTheBedtimeWindow() {
        let prefs = F.prefs(quiet: QuietHours(start: 21 * 60 + 30, end: 7 * 60))
        let d = F.run([F.plan("mel", .bedtime)], prefs: prefs, now: F.at(20, 0)).decision(F.id(F.today, .bedtime))
        XCTAssertEqual(d?.fireDate, F.at(22, 0))
        XCTAssertEqual(d?.reason.trigger, .usualTime)
    }

    func testBedtimeIsSuppressedByQuietHoursTheUserStartedEarlier() {
        let prefs = F.prefs(quiet: QuietHours(start: 20 * 60, end: 7 * 60))
        let out = F.run([F.plan("mel", .bedtime), F.plan("fish", .dinner)], prefs: prefs, now: F.at(17, 0))
        XCTAssertNil(out.decision(F.id(F.today, .bedtime)))
        XCTAssertEqual(out.decision(F.id(F.today, .dinner))?.fireDate, F.at(18, 30))
    }

    func testEqualStartAndEndMeansNoQuietHours() {
        let prefs = F.prefs(intensity: .gentle, quiet: QuietHours(start: 0, end: 0)) { $0.usualTimes[.wake] = 3 * 60 }
        XCTAssertEqual(F.run([F.plan("w", .wake)], prefs: prefs, now: F.at(1, 0)).first?.fireDate, F.at(3, 0))
    }

    func testLateNightWorkoutReminderIsDroppedByQuietHours() {
        let out = F.run([F.plan("c", .postWorkout)], signals: [F.workout(F.at(22, 0), F.at(23, 0))],
                        prefs: F.pro(), now: F.at(23, 1))
        XCTAssertNil(out.decision(F.id(F.today, .postWorkout)))
    }

    // MARK: DST and time zones

    func testSpringForwardSkippedTimeLandsAtTheNextValidTime() {
        let prefs = F.prefs(intensity: .gentle) { $0.usualTimes[.wake] = 2 * 60 + 30 }
        let out = F.run([F.plan("w", .wake), F.plan("b", .breakfast)], prefs: prefs, now: F.date(2026, 3, 8, 0, 30))
        let wake = out.decision("suppl.2026-03-08.wake")
        // 2:30 AM doesn't exist on 2026-03-08 in New York; 3:00 AM EDT is 07:00 UTC.
        XCTAssertEqual(wake?.fireDate, Date(timeIntervalSince1970: 1_772_953_200))
        XCTAssertEqual(F.ny.component(.hour, from: wake!.fireDate), 3)
        // Breakfast is still 8:00 on the wall clock, now in EDT (12:00 UTC).
        XCTAssertEqual(out.decision("suppl.2026-03-08.breakfast")?.fireDate, Date(timeIntervalSince1970: 1_772_971_200))
        // Tomorrow's wake is 2:30 as usual.
        XCTAssertEqual(out.decision("suppl.2026-03-09.wake")?.fireDate, F.date(2026, 3, 9, 2, 30))
    }

    func testFallBackKeepsWallClockTimesAndUsesTheFirstRepeatedHour() {
        let prefs = F.prefs(intensity: .gentle) { $0.usualTimes[.wake] = 90 }
        let out = F.run([F.plan("w", .wake), F.plan("b", .breakfast)], prefs: prefs, now: F.date(2026, 10, 31, 23, 0))
        let breakfast = try! XCTUnwrap(out.decision("suppl.2026-11-01.breakfast"))
        // 8:00 AM EST is 13:00 UTC, 25 hours after the previous day's 8:00 AM EDT.
        XCTAssertEqual(breakfast.fireDate, Date(timeIntervalSince1970: 1_793_538_000))
        XCTAssertEqual(breakfast.fireDate.timeIntervalSince(F.date(2026, 10, 31, 8, 0)), 25 * 3600)
        // 1:30 AM happens twice; the first one (EDT, 05:30 UTC) is used.
        XCTAssertEqual(out.decision("suppl.2026-11-01.wake")?.fireDate, Date(timeIntervalSince1970: 1_793_511_000))
    }

    func testTimeZoneChangeUsesTheNewZonesClockAndDayKeys() {
        // 1:30 AM Saturday in New York is still 10:30 PM Friday in Los Angeles.
        let now = F.date(2026, 10, 24, 1, 30)
        let plans = [F.plan("d", .breakfast)]
        let prefs = F.prefs(intensity: .gentle)
        let newYork = F.run(plans, prefs: prefs, now: now, calendar: F.ny)
        let losAngeles = F.run(plans, prefs: prefs, now: now, calendar: F.la)
        XCTAssertEqual(newYork.reminderIDs, ["suppl.2026-10-24.breakfast", "suppl.2026-10-25.breakfast"])
        XCTAssertEqual(losAngeles.reminderIDs, ["suppl.2026-10-24.breakfast"])
        let la = try! XCTUnwrap(losAngeles.first)
        XCTAssertEqual(la.fireDate, F.date(2026, 10, 24, 8, 0, in: F.la))
        XCTAssertEqual(F.la.component(.hour, from: la.fireDate), 8)
        XCTAssertEqual(la.fireDate.timeIntervalSince(newYork[0].fireDate), 3 * 3600)
    }
}
