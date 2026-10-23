import XCTest
@testable import SupplCore

/// Late wake, calendar gaps, and clinician-directed plans staying put.
final class EngineContextTests: XCTestCase {
    typealias F = EngineFixtures
    let wakePlan = EngineFixtures.plan("b12", .wake)
    let breakfastPlan = EngineFixtures.plan("d", .breakfast, withFood: true)

    // MARK: Late wake

    func testLateWakeShiftsWakeAndBreakfastByTheDifference() {
        let woke = F.at(8, 10)
        let out = F.run([wakePlan, breakfastPlan], signals: [F.wake(woke, observed: F.at(8, 12))],
                        prefs: F.pro(), now: F.at(8, 12))
        let wake = out.decision(F.id(F.today, .wake))
        // The wake-time shift lands on the wake time itself, already past, so it gets a one-minute lead.
        XCTAssertEqual(wake?.fireDate, F.at(8, 13))
        let breakfast = out.decision(F.id(F.today, .breakfast))
        XCTAssertEqual(breakfast?.fireDate, F.at(9, 10))
        for d in [wake, breakfast] {
            XCTAssertEqual(d?.reason.trigger, .lateWake)
            XCTAssertEqual(d?.reason.source, .appleHealth)
            XCTAssertEqual(d?.reason.dataTimestamp, woke)
            XCTAssertEqual(d?.reason.ruleID, "timing.lateWake.v1")
        }
        XCTAssertEqual(wake?.reason.usualDate, F.at(7, 0))
        XCTAssertEqual(breakfast?.reason.usualDate, F.at(8, 0))
    }

    func testLateWakeIsClampedToTheWindowEnd() {
        // Usual wake 6:00, woke 8:45: breakfast would move 2h45m to 10:45, past its 9:30 window end.
        let prefs = F.pro { $0.usualTimes[.wake] = 6 * 60 }
        let out = F.run([wakePlan, breakfastPlan], signals: [F.wake(F.at(8, 45), .whoop)],
                        prefs: prefs, now: F.at(8, 46))
        // The wake window ended at 8:00, so there's nothing left to send for it.
        XCTAssertNil(out.decision(F.id(F.today, .wake)))
        XCTAssertEqual(out.decision(F.id(F.today, .breakfast))?.fireDate, F.at(9, 30))
        XCTAssertEqual(out.decision(F.id(F.today, .breakfast))?.reason.source, .whoop)
    }

    func testEarlyWakeChangesNothing() {
        let out = F.run([wakePlan, breakfastPlan], signals: [F.wake(F.at(6, 0))], prefs: F.pro(), now: F.at(6, 5))
        XCTAssertEqual(out.decision(F.id(F.today, .wake))?.fireDate, F.at(7, 0))
        XCTAssertEqual(out.decision(F.id(F.today, .breakfast))?.reason.trigger, .usualTime)
    }

    func testStaleWakeSignalIsIgnored() {
        let prefs = F.pro { $0.freshness.wakeMinutes = 60 }
        let out = F.run([breakfastPlan], signals: [F.wake(F.at(7, 40), observed: F.at(7, 41))], prefs: prefs, now: F.at(8, 50, 0, day: 23))
        // Observed 69 minutes ago with a 60-minute freshness limit: back to usual times (8:00 is past).
        XCTAssertNil(out.decision(F.id(F.today, .breakfast)))
        XCTAssertEqual(out.first?.day, F.tomorrow)
    }

    func testLateWakeDoesNotMoveOtherMoments() {
        let lunch = F.plan("l", .lunch)
        let out = F.run([lunch], signals: [F.wake(F.at(9, 0))], prefs: F.pro(), now: F.at(9, 1))
        XCTAssertEqual(out.first?.fireDate, F.at(12, 30))
        XCTAssertEqual(out.first?.reason.trigger, .usualTime)
    }

    // MARK: Clinician-directed

    func testClinicianDirectedGroupIgnoresLateWake() {
        let rx = F.plan("rx", .breakfast, clinician: true)
        let out = F.run([breakfastPlan, rx], signals: [F.wake(F.at(7, 40))], prefs: F.pro(), now: F.at(7, 41))
        let today = out.filter { $0.day == F.today && $0.moment == .breakfast }
        XCTAssertEqual(today.count, 1, "still one notification for the moment")
        XCTAssertEqual(today.first?.fireDate, F.at(8, 0))
        XCTAssertEqual(today.first?.planIDs, ["d", "rx"])
        XCTAssertEqual(today.first?.reason.trigger, .usualTime)
    }

    func testClinicianDirectedGroupIgnoresCalendar() {
        let rx = F.plan("rx", .lunch, clinician: true)
        let busy = F.busy([(F.at(12, 0), F.at(13, 0))], observed: F.at(9, 0))
        let d = F.run([rx], signals: [busy], prefs: F.pro(), now: F.at(9, 0)).decision(F.id(F.today, .lunch))
        XCTAssertEqual(d?.fireDate, F.at(12, 30))
        XCTAssertEqual(d?.reason.trigger, .usualTime)
    }

    // MARK: Calendar

    func testBusyUsualTimeMovesToTheEarliestFreeGap() {
        // Breakfast window 7:30 to 9:30; busy 7:45 to 8:40. The 15-minute gap at 7:30 comes first.
        let busy = F.busy([(F.at(7, 45), F.at(8, 40))], observed: F.at(6, 0))
        let d = F.run([breakfastPlan], signals: [busy], prefs: F.pro(), now: F.at(6, 0)).decision(F.id(F.today, .breakfast))
        XCTAssertEqual(d?.fireDate, F.at(7, 30))
        XCTAssertEqual(d?.reason.trigger, .calendarGap)
        XCTAssertEqual(d?.reason.source, .calendar)
        XCTAssertEqual(d?.reason.usualDate, F.at(8, 0))
        XCTAssertEqual(d?.reason.ruleID, "timing.calendarGap.v1")
    }

    func testGapShorterThanTheMinimumIsSkipped() {
        let busy = F.busy([(F.at(7, 35), F.at(8, 40))], observed: F.at(6, 0))
        let d = F.run([breakfastPlan], signals: [busy], prefs: F.pro(), now: F.at(6, 0)).decision(F.id(F.today, .breakfast))
        XCTAssertEqual(d?.fireDate, F.at(8, 40))
    }

    func testOverlappingBusyIntervalsFromSeveralSignalsAreMerged() {
        let signals = [F.busy([(F.at(7, 25), F.at(8, 15))], observed: F.at(6, 0)),
                       F.busy([(F.at(8, 10), F.at(8, 50)), (F.at(8, 55), F.at(9, 0))], observed: F.at(6, 30))]
        let d = F.run([breakfastPlan], signals: signals, prefs: F.pro(), now: F.at(7, 0)).decision(F.id(F.today, .breakfast))
        // 8:50 to 8:55 is too short; the first real gap starts at 9:00.
        XCTAssertEqual(d?.fireDate, F.at(9, 0))
    }

    func testNoFreeGapKeepsTheUsualTime() {
        let busy = F.busy([(F.at(7, 0), F.at(10, 0))], observed: F.at(6, 0))
        let d = F.run([breakfastPlan], signals: [busy], prefs: F.pro(), now: F.at(6, 0)).decision(F.id(F.today, .breakfast))
        XCTAssertEqual(d?.fireDate, F.at(8, 0))
        XCTAssertEqual(d?.reason.trigger, .usualTime)
    }

    func testGapAtTheEndOfTheWindowMustBeLongEnough() {
        let busy = F.busy([(F.at(7, 0), F.at(9, 25))], observed: F.at(6, 0))
        let d = F.run([breakfastPlan], signals: [busy], prefs: F.pro(), now: F.at(6, 0)).decision(F.id(F.today, .breakfast))
        // Only 5 minutes free before 9:30.
        XCTAssertEqual(d?.fireDate, F.at(8, 0))
    }

    func testStaleBusySignalIsIgnored() {
        let busy = F.busy([(F.at(7, 45), F.at(8, 40))], observed: F.at(0, 30))
        let d = F.run([breakfastPlan], signals: [busy], prefs: F.pro(), now: F.at(7, 0)).decision(F.id(F.today, .breakfast))
        XCTAssertEqual(d?.fireDate, F.at(8, 0))
    }

    func testCalendarGapStartsAfterNow() {
        let busy = F.busy([(F.at(7, 55), F.at(8, 30))], observed: F.at(7, 50))
        let d = F.run([breakfastPlan], signals: [busy], prefs: F.pro(), now: F.at(7, 50)).decision(F.id(F.today, .breakfast))
        // 7:51 to 7:55 is too short, so the reminder waits for 8:30.
        XCTAssertEqual(d?.fireDate, F.at(8, 30))
    }

    func testCalendarAppliesToTomorrow() {
        let busy = F.busy([(F.at(12, 0, day: 24), F.at(13, 0, day: 24))], observed: F.at(21, 0))
        let lunch = F.plan("l", .lunch)
        let d = F.run([lunch], signals: [busy], prefs: F.pro(), now: F.at(21, 0)).decision(F.id(F.tomorrow, .lunch))
        XCTAssertEqual(d?.fireDate, F.at(13, 0, day: 24))
    }

    func testCalendarNeverMovesPostWorkout() {
        let busy = F.busy([(F.at(19, 0), F.at(21, 0))], observed: F.at(18, 0))
        let d = F.run([F.plan("c", .postWorkout)], signals: [busy], prefs: F.pro(), now: F.at(18, 0))
            .decision(F.id(F.today, .postWorkout))
        XCTAssertEqual(d?.fireDate, F.at(19, 30))
        XCTAssertNotEqual(d?.reason.trigger, .calendarGap)
    }

    func testCalendarMoveAfterLateWakeNeverLandsBeforeTheUserWasUp() {
        // Woke 30 minutes late, so breakfast moves to 8:30, which is busy until 9:00.
        let signals = [F.wake(F.at(7, 30)), F.busy([(F.at(8, 15), F.at(9, 0))], observed: F.at(7, 30))]
        let d = F.run([breakfastPlan], signals: signals, prefs: F.pro(), now: F.at(7, 31)).decision(F.id(F.today, .breakfast))
        // The shifted window starts at 8:00; 8:00 to 8:15 is free.
        XCTAssertEqual(d?.fireDate, F.at(8, 0))
        XCTAssertEqual(d?.reason.trigger, .calendarGap)
        XCTAssertEqual(d?.reason.usualDate, F.at(8, 0))
    }
}
