import XCTest
@testable import SupplCore

/// Every trigger is one-shot, so the planning horizon bounds how long reminders keep coming if the app
/// never runs again. EngineDurabilityTests covers the budget and the heads-up that warns before they stop.
final class EngineHorizonTests: XCTestCase {
    private typealias F = EngineFixtures

    private func week(_ intensity: Intensity = .balanced) -> Preferences {
        F.prefs(intensity: intensity) { $0.planningDays = 7 }
    }

    func testInitialsCoverAWeek() {
        let out = F.run([F.plan("d", .breakfast)], prefs: week(), now: F.at(6, 0))
        let initials = out.filter { $0.stage == .initial }.map(\.day.key)
        XCTAssertEqual(initials, ["2026-10-23", "2026-10-24", "2026-10-25", "2026-10-26",
                                  "2026-10-27", "2026-10-28", "2026-10-29"])
    }

    func testFollowUpsOnlyCoverTodayAndTomorrow() {
        let out = F.run([F.plan("d", .breakfast)], prefs: week(.extraHelp), now: F.at(6, 0))
        let followUpDays = Set(out.filter { $0.stage != .initial }.map(\.day.key))
        XCTAssertEqual(followUpDays, ["2026-10-23", "2026-10-24"])
    }

    func testWeekdayPlansAreDueOnlyOnTheirDays() {
        // 2026-10-23 is a Friday; Mondays (2) fall on the 26th only within the week.
        let out = F.run([F.plan("m", .lunch, frequency: .weekdays([2]))], prefs: week(.gentle), now: F.at(6, 0))
        XCTAssertEqual(out.map(\.day.key), ["2026-10-26"])
    }

    func testCapKeepsTheWeeksInitialsBeforeLaterFollowUps() {
        let plans = Moment.allCases.map { F.plan($0.rawValue, $0) }
        let out = F.run(plans, prefs: week(.extraHelp), now: F.at(0, 1))
        XCTAssertLessThanOrEqual(out.count, ReminderEngine.maxDecisions)
        XCTAssertEqual(out.map(\.fireDate), out.map(\.fireDate).sorted())
        // Every initial of the week survives the cap.
        let allInitials = F.run(plans, prefs: week(.gentle), now: F.at(0, 1))
        XCTAssertEqual(Set(out.filter { $0.stage == .initial }.reminderIDs), Set(allInitials.reminderIDs))
        // So do the follow-ups due within a day.
        let soon = F.at(0, 1).addingTimeInterval(24 * 3600)
        let nearFollowUps = F.run(plans, prefs: F.prefs(intensity: .extraHelp), now: F.at(0, 1))
            .filter { $0.stage != .initial && $0.fireDate <= soon }
        XCTAssertFalse(nearFollowUps.isEmpty)
        XCTAssertTrue(Set(nearFollowUps.reminderIDs).isSubset(of: Set(out.reminderIDs)))
    }

    func testDefaultHorizonIsTwoWeeksFilledToFour() {
        XCTAssertEqual(Preferences().planningDays, 14)
        XCTAssertEqual(Preferences().maxPlanningDays, 28)
    }
    func testClinicianDirectedWorkoutKeepsUsualTime() throws {
        let plans = [F.plan("fixed", .postWorkout, clinician: true), F.plan("flexible", .postWorkout)]
        let output = F.run(plans, signals: [F.workout(F.at(16, 0), F.at(17, 0))],
                           prefs: F.pro(), now: F.at(17, 1))
        let initial = try XCTUnwrap(output.decision(F.id(F.today, .postWorkout)))
        XCTAssertEqual(initial.fireDate, F.at(19, 30))
        XCTAssertEqual(initial.reason.trigger, .usualTime)
        XCTAssertEqual(initial.planIDs, ["fixed", "flexible"])
    }

    func testPendingQuietHoursReminderSurvivesMidnightReplan() throws {
        let plans = [F.plan("late", .lunch)]
        let prefs = F.prefs(intensity: .gentle, quiet: QuietHours(start: 23 * 60, end: 30)) {
            $0.usualTimes[.lunch] = 23 * 60 + 40
        }
        let before = F.run(plans, prefs: prefs, now: F.at(23, 30))
        let after = F.run(plans, prefs: prefs, now: F.at(0, 5, day: 24))
        let id = F.id(F.today, .lunch)
        let original = try XCTUnwrap(before.decision(id))
        XCTAssertEqual(original.fireDate, F.at(0, 30, day: 24))
        XCTAssertEqual(after.decision(id), original)
    }

    func testPreviousDaySnoozeAndConfirmationKeepTheirDoseDay() {
        let plans = [F.plan("late", .bedtime)]
        let prefs = F.prefs(intensity: .gentle, quiet: QuietHours(start: 0, end: 0))
        let until = F.at(0, 30, day: 24)
        let snooze = DoseStatus(planID: "late", day: F.today, state: .snoozed(until: until))
        let out = F.run(plans, statuses: [snooze], prefs: prefs, now: F.at(0, 5, day: 24))
        XCTAssertEqual(out.decision(F.id(F.today, .bedtime, .snoozed))?.fireDate, until)
        let taken = DoseStatus(planID: "late", day: F.today, state: .confirmed(at: F.at(0, 1, day: 24)))
        let done = F.run(plans, statuses: [taken], prefs: prefs, now: F.at(0, 5, day: 24))
        XCTAssertFalse(done.contains { $0.day == F.today })
        XCTAssertTrue(done.contains { $0.day == F.tomorrow })
    }

    func testNewRoutineDoesNotInheritYesterdaysOvernightReminder() {
        var plan = F.plan("new", .lunch)
        plan.startDate = F.at(0, 2, day: 24)
        let prefs = F.prefs(intensity: .gentle, quiet: QuietHours(start: 23 * 60, end: 30)) {
            $0.usualTimes[.lunch] = 23 * 60 + 40
        }
        let out = F.run([plan], prefs: prefs, now: F.at(0, 5, day: 24))
        XCTAssertNil(out.decision(F.id(F.today, .lunch)))
        XCTAssertEqual(out.decision(F.id(F.tomorrow, .lunch))?.fireDate, F.at(0, 30, day: 25))
    }

    func testExistingRoutineStillKeepsYesterdaysOvernightReminder() {
        var plan = F.plan("existing", .lunch)
        plan.startDate = F.at(12, 0)
        let prefs = F.prefs(intensity: .gentle, quiet: QuietHours(start: 23 * 60, end: 30)) {
            $0.usualTimes[.lunch] = 23 * 60 + 40
        }
        let out = F.run([plan], prefs: prefs, now: F.at(0, 5, day: 24))
        XCTAssertEqual(out.decision(F.id(F.today, .lunch))?.fireDate, F.at(0, 30, day: 24))
    }

}
