import XCTest
@testable import SupplCore

/// Post-workout re-timing, cross-source dedupe, the evening fallback, and no double-fire.
final class EngineWorkoutTests: XCTestCase {
    typealias F = EngineFixtures
    let creatine = EngineFixtures.plan("creatine", .postWorkout, name: "Creatine", dose: "5 g")

    private func todaysPostWorkout(_ out: [ReminderDecision]) -> ReminderDecision? {
        out.decision(F.id(F.today, .postWorkout))
    }

    func testFreshWorkoutFiresTwoMinutesAfterItEnds() {
        let end = F.at(17, 40)
        let out = F.run([creatine], signals: [F.workout(F.at(17, 0), end)], prefs: F.pro(), now: F.at(17, 40, 30))
        let d = todaysPostWorkout(out)
        XCTAssertEqual(d?.fireDate, F.at(17, 42))
        XCTAssertEqual(d?.reason.trigger, .workoutEnded)
        XCTAssertEqual(d?.reason.source, .appleHealth)
        XCTAssertEqual(d?.reason.dataTimestamp, end)
        XCTAssertEqual(d?.reason.ruleID, "timing.workout.v1")
    }

    func testLateArrivingWorkoutFiresAMinuteFromNow() {
        // Background delivery reported it 30 minutes late: still fresh, fire now-ish rather than in the past.
        let out = F.run([creatine], signals: [F.workout(F.at(16, 15), F.at(17, 0), observed: F.at(17, 30))],
                        prefs: F.pro(), now: F.at(17, 30))
        XCTAssertEqual(todaysPostWorkout(out)?.fireDate, F.at(17, 31))
    }

    func testAppleHealthAndWhoopReportingTheSameWorkoutGiveOneReminder() {
        let signals = [F.workout(F.at(17, 0), F.at(17, 40), .appleHealth),
                       F.workout(F.at(17, 2), F.at(17, 45), .whoop)]
        let out = F.run([creatine], signals: signals, prefs: F.pro(), now: F.at(17, 46))
        let today = out.filter { $0.day == F.today }
        XCTAssertEqual(today.count, 1)
        // The earliest report wins, so a later sync doesn't push the reminder back.
        XCTAssertEqual(today.first?.reason.source, .appleHealth)
        XCTAssertEqual(today.first?.reason.dataTimestamp, F.at(17, 40))
        XCTAssertEqual(today.first?.fireDate, F.at(17, 47))
    }

    func testReportsEndingWithinTenMinutesAreOneWorkoutEvenWithoutOverlap() {
        let signals = [F.workout(F.at(17, 0), F.at(17, 30), .whoop), F.workout(F.at(17, 32), F.at(17, 38), .appleHealth)]
        let d = todaysPostWorkout(F.run([creatine], signals: signals, prefs: F.pro(), now: F.at(17, 39)))
        XCTAssertEqual(d?.reason.source, .whoop)
        XCTAssertEqual(d?.reason.dataTimestamp, F.at(17, 30))
    }

    func testSeparateWorkoutsUseTheLatestFreshOne() {
        let signals = [F.workout(F.at(7, 0), F.at(7, 45)), F.workout(F.at(16, 0), F.at(16, 50))]
        let d = todaysPostWorkout(F.run([creatine], signals: signals, prefs: F.pro(), now: F.at(17, 0)))
        XCTAssertEqual(d?.reason.dataTimestamp, F.at(16, 50))
        XCTAssertEqual(d?.fireDate, F.at(17, 1))
    }

    func testStaleWorkoutFallsBackSilentlyToUsualTime() {
        // Ended three hours ago: not "just finished", and it would be untrue to say none was recorded.
        let out = F.run([creatine], signals: [F.workout(F.at(13, 0), F.at(14, 0))], prefs: F.pro(), now: F.at(17, 0))
        let d = todaysPostWorkout(out)
        XCTAssertEqual(d?.fireDate, F.at(19, 30))
        XCTAssertEqual(d?.reason.trigger, .usualTime)
        XCTAssertNil(d?.reason.dataTimestamp)
    }

    func testNoWorkoutWithHealthConnectedUsesTheEveningFallback() {
        for source in [SignalSource.appleHealth, .whoop] {
            let prefs = F.prefs(intensity: .gentle, contextAware: true, sources: [source])
            let d = todaysPostWorkout(F.run([creatine], prefs: prefs, now: F.at(12, 0)))
            XCTAssertEqual(d?.fireDate, F.at(19, 30))
            XCTAssertEqual(d?.reason.trigger, .workoutFallback, "\(source)")
            XCTAssertEqual(d?.reason.ruleID, "timing.workoutFallback.v1")
        }
    }

    func testNoWorkoutSourceConnectedMeansPlainUsualTime() {
        let prefs = F.prefs(intensity: .gentle, contextAware: true, sources: [.calendar])
        XCTAssertEqual(todaysPostWorkout(F.run([creatine], prefs: prefs, now: F.at(12, 0)))?.reason.trigger, .usualTime)
    }

    func testWorkoutFromYesterdayDoesNotCountForToday() {
        let late = F.workout(F.at(23, 0, day: 22), F.at(23, 50, day: 22))
        let d = todaysPostWorkout(F.run([creatine], signals: [late], prefs: F.pro(), now: F.at(0, 30)))
        XCTAssertEqual(d?.fireDate, F.at(19, 30))
        XCTAssertEqual(d?.reason.trigger, .workoutFallback)
    }

    func testWorkoutNeverAddsPlans() {
        let vitaminD = F.plan("d", .breakfast)
        let signals = [F.workout(F.at(16, 0), F.at(17, 0))]
        let out = F.run([vitaminD], signals: signals, prefs: F.pro(), now: F.at(17, 1))
        XCTAssertFalse(out.contains { $0.moment == .postWorkout })
        XCTAssertEqual(out.reminderIDs, ["suppl.2026-10-24.breakfast"])
    }

    func testWorkoutOnlyRetimesPostWorkoutPlans() {
        let plans = [creatine, F.plan("fish", .dinner)]
        let out = F.run(plans, signals: [F.workout(F.at(16, 0), F.at(17, 0))], prefs: F.pro(), now: F.at(17, 1))
        XCTAssertEqual(out.decision(F.id(F.today, .dinner))?.fireDate, F.at(18, 30))
        XCTAssertEqual(out.decision(F.id(F.today, .dinner))?.planIDs, ["fish"])
        XCTAssertEqual(todaysPostWorkout(out)?.planIDs, ["creatine"])
    }

    func testDeliveredWorkoutReminderIsNeverResent() {
        let signals = [F.workout(F.at(17, 0), F.at(17, 40))]
        let prefs = F.pro(intensity: .balanced)
        let first = F.run([creatine], signals: signals, prefs: prefs, now: F.at(17, 41))
        let delivered = try! XCTUnwrap(todaysPostWorkout(first))
        // WHOOP syncs the same workout later; the initial is already delivered.
        let later = signals + [F.workout(F.at(17, 3), F.at(17, 48), .whoop)]
        let out = F.run([creatine], signals: later, history: [delivered], prefs: prefs, now: F.at(17, 50))
        XCTAssertNil(todaysPostWorkout(out))
        XCTAssertEqual(out.decision(F.id(F.today, .postWorkout, .followUp(1)))?.fireDate, F.at(18, 12))
    }

    func testWorkoutAfterTheFallbackWasDeliveredDoesNotFireAgain() {
        let fallback = ReminderDecision(
            id: F.id(F.today, .postWorkout), groupID: ReminderID.group(day: F.today, moment: .postWorkout),
            day: F.today, moment: .postWorkout, planIDs: ["creatine"], fireDate: F.at(19, 30), stage: .initial,
            reason: Reason(trigger: .workoutFallback, usualDate: F.at(19, 30), ruleID: "timing.workoutFallback.v1"))
        let out = F.run([creatine], signals: [F.workout(F.at(19, 0), F.at(19, 35))], history: [fallback],
                        prefs: F.pro(intensity: .balanced), now: F.at(19, 40))
        XCTAssertNil(todaysPostWorkout(out))
        // The follow-up still hangs off the delivered fallback.
        XCTAssertEqual(out.decision(F.id(F.today, .postWorkout, .followUp(1)))?.fireDate, F.at(20, 0))
    }

    func testWorkoutFollowUpsStayInsideTheWorkoutWindow() {
        let prefs = F.pro(intensity: .extraHelp) { $0.followUpDelayMinutes = 60 }
        let out = F.run([creatine], signals: [F.workout(F.at(17, 0), F.at(17, 40))], prefs: prefs, now: F.at(17, 41))
        // Window is 17:40 to 19:40: 17:42, then 18:42; 19:42 is past the end.
        XCTAssertEqual(out.filter { $0.day == F.today }.map(\.fireDate), [F.at(17, 42), F.at(18, 42)])
    }

    func testEarlyWorkoutWaitsForQuietHoursAndKeepsItsWindow() {
        // Workout ends 5:30, inside quiet hours (until 6:45). Its window runs to 7:30.
        let prefs = F.pro(intensity: .extraHelp)
        let signals = [F.workout(F.at(4, 45), F.at(5, 30))]
        let first = F.run([creatine], signals: signals, prefs: prefs, now: F.at(5, 31)).filter { $0.day == F.today }
        XCTAssertEqual(first.map(\.fireDate), [F.at(6, 45), F.at(7, 15)], "7:45 is past the workout window")
        XCTAssertEqual(first.first?.reason.trigger, .quietHours)
        XCTAssertEqual(first.first?.reason.dataTimestamp, F.at(5, 30))
        // Once delivered, follow-ups still respect the workout window, not the evening fallback window.
        let later = F.run([creatine], signals: signals, history: [first[0]], prefs: prefs, now: F.at(6, 50))
        XCTAssertEqual(later.filter { $0.day == F.today }.reminderIDs, ["suppl.2026-10-23.postWorkout.f1"])
    }

    func testUnfinishedWorkoutIsIgnored() {
        // An end time in the future is bad data, not a finished workout.
        let out = F.run([creatine], signals: [F.workout(F.at(17, 0), F.at(18, 0))], prefs: F.pro(), now: F.at(17, 30))
        XCTAssertEqual(todaysPostWorkout(out)?.reason.trigger, .workoutFallback)
    }
}
