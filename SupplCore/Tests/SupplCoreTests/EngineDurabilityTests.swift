import XCTest
@testable import SupplCore

/// R14: every trigger is one-shot, so without app execution the queue eventually runs out.
/// The budget keeps iOS's 64 with the heads-up always fitting; the heads-up warns before silence.
final class EngineDurabilityTests: XCTestCase {
    private typealias F = EngineFixtures
    private let now = EngineFixtures.at(0, 1)

    /// Six moments, Extra Help, quiet hours off, default horizon: the most requests anyone can need.
    private var sixMoments: [DosePlan] { Moment.allCases.map { F.plan($0.rawValue, $0) } }

    private func worstCase(quiet: QuietHours? = QuietHours(start: 0, end: 0)) -> Preferences {
        F.prefs(intensity: .extraHelp, quiet: quiet) { $0.planningDays = Preferences().planningDays }
    }

    func testBudgetKeepsReservedSlotsInsideTheIOSLimit() {
        XCTAssertEqual(NotificationBudget.pendingLimit, 64)
        XCTAssertEqual(ReminderEngine.maxDecisions + NotificationBudget.reserved, NotificationBudget.pendingLimit)
        XCTAssertEqual(NotificationBudget.engineSlots(foreign: 10), 52)
        XCTAssertEqual(NotificationBudget.engineSlots(foreign: 100), 0)
        let pending = ["suppl.breakfast", "suppl.followup.lunch", NotificationBudget.headsUpID,
                       NotificationBudget.testID, "suppl.2026-10-23.lunch", "suppl.breakfast"]
        XCTAssertEqual(NotificationBudget.foreignCount(pending), 2)
        XCTAssertFalse(ReminderID.isEngineID(NotificationBudget.headsUpID))
    }

    func testWorstCaseFitsWithTheHeadsUp() {
        // Ten foreign requests is an upgrade from the old build: five repeating slots plus five follow-ups.
        for foreign in [0, 10] {
            let budget = NotificationBudget.engineSlots(foreign: foreign)
            let out = F.run(sixMoments, prefs: worstCase(), now: now, budget: budget)
            XCTAssertEqual(out.count, budget, "the busiest routine uses every slot it is given")
            XCTAssertLessThanOrEqual(out.count + foreign + NotificationBudget.reserved, NotificationBudget.pendingLimit)
            XCTAssertEqual(Set(out.reminderIDs).count, out.count)
            XCTAssertNotNil(ReminderEngine.headsUpDate(for: out, prefs: worstCase(), calendar: F.ny))
        }
    }

    /// Zero launches after `now`: only what was planned then ever fires.
    func testWorstCaseNeverStopsWithoutWarning() throws {
        let prefs = worstCase()
        let out = F.run(sixMoments, prefs: prefs, now: now)
        let headsUp = try XCTUnwrap(ReminderEngine.headsUpDate(for: out, prefs: prefs, calendar: F.ny))
        let planned = Set(out.filter { $0.stage == .initial }.reminderIDs)
        // Silence begins at the first usual-time reminder that won't come.
        var firstMissing: Date?
        for offset in 0..<30 {
            let day = F.today.adding(days: offset, calendar: F.ny)
            for moment in Moment.allCases where !planned.contains(F.id(day, moment)) {
                let usual = WallClock.date(day, minutes: prefs.usualMinutes(for: moment), calendar: F.ny)
                if usual > now, firstMissing.map({ usual < $0 }) ?? true { firstMissing = usual }
            }
        }
        let silence = try XCTUnwrap(firstMissing)
        XCTAssertLessThanOrEqual(headsUp, silence.addingTimeInterval(-24 * 3600), "at least a day's warning")
        // Every moment keeps coming for eight full days (the old queue ran out after about four).
        for offset in 0..<8 {
            let day = F.today.adding(days: offset, calendar: F.ny)
            for moment in Moment.allCases {
                XCTAssertTrue(planned.contains(F.id(day, moment)), "\(day) \(moment)")
            }
        }
        XCTAssertGreaterThanOrEqual(silence, F.date(2026, 10, 31, 0, 0))
    }

    func testHeadsUpSharesAPlannedTimeOutsideQuietHours() throws {
        for quiet in [nil, QuietHours(start: 11 * 60, end: 13 * 60), QuietHours(start: 20 * 60, end: 9 * 60)] {
            let prefs = worstCase(quiet: quiet)
            let out = F.run(sixMoments, prefs: prefs, now: now)
            let headsUp = try XCTUnwrap(ReminderEngine.headsUpDate(for: out, prefs: prefs, calendar: F.ny))
            XCTAssertTrue(out.contains { $0.stage == .initial && $0.fireDate == headsUp })
            XCTAssertFalse(prefs.effectiveQuietHours.contains(headsUp, calendar: F.ny))
            XCTAssertTrue(out.allSatisfy { !prefs.effectiveQuietHours.contains($0.fireDate, calendar: F.ny) })
        }
    }

    func testHeadsUpComesADayBeforeTheLastReminder() {
        let prefs = F.prefs(intensity: .gentle) { $0.planningDays = 14 }
        let out = F.run([F.plan("d", .breakfast)], prefs: prefs, now: F.at(6, 0))
        XCTAssertEqual(out.count, 14)
        XCTAssertEqual(out.last?.fireDate, F.date(2026, 11, 5, 8, 0))
        XCTAssertEqual(ReminderEngine.headsUpDate(for: out, prefs: prefs, calendar: F.ny), F.date(2026, 11, 4, 8, 0))
    }

    func testShortQueuesStillGetAHeadsUp() {
        XCTAssertNil(ReminderEngine.headsUpDate(for: [], prefs: F.prefs(), calendar: F.ny))
        let monday = F.plan("m", .lunch, frequency: .weekdays([2]))
        let one = F.run([monday], prefs: F.prefs(intensity: .gentle) { $0.planningDays = 4 }, now: F.at(6, 0))
        XCTAssertEqual(one.count, 1)
        XCTAssertEqual(ReminderEngine.headsUpDate(for: one, prefs: F.prefs(), calendar: F.ny), one.first?.fireDate)
        // Follow-ups never anchor it: they aren't the reminders that must keep coming.
        let followUps = F.run([F.plan("b", .breakfast)], prefs: F.prefs(), now: F.at(8, 10)).filter { $0.stage != .initial }
        XCTAssertFalse(followUps.isEmpty)
        XCTAssertNil(ReminderEngine.headsUpDate(for: followUps, prefs: F.prefs(), calendar: F.ny))
    }

    func testTakenAndSkippedDosesHaveNothingPendingAndNothingDoublesUp() {
        let statuses = [DoseStatus(planID: "breakfast", day: F.today, state: .confirmed(at: now)),
                        DoseStatus(planID: "lunch", day: F.today, state: .skipped(at: now))]
        let out = F.run(sixMoments, statuses: statuses, prefs: worstCase(), now: now)
        XCTAssertFalse(out.contains { $0.groupID == ReminderID.group(day: F.today, moment: .breakfast) })
        XCTAssertFalse(out.contains { $0.groupID == ReminderID.group(day: F.today, moment: .lunch) })
        XCTAssertTrue(out.contains { $0.groupID == ReminderID.group(day: F.tomorrow, moment: .breakfast) })
        XCTAssertEqual(Set(out.reminderIDs).count, out.count)
        let initials = out.filter { $0.stage == .initial }
        XCTAssertEqual(Set(initials.map(\.groupID)).count, initials.count, "one initial per dose day and moment")
    }

    func testWeekdayAndClinicianTimingHoldUnderTheBudget() throws {
        var prefs = worstCase()
        prefs.contextAware = true
        prefs.connectedSources = [.appleHealth]
        let plans = sixMoments + [F.plan("mon", .lunch, frequency: .weekdays([2])),
                                  F.plan("fixed", .postWorkout, clinician: true)]
        let out = F.run(plans, signals: [F.workout(F.at(16, 0), F.at(17, 0))], prefs: prefs, now: F.at(17, 1))
        // The clinician-directed plan keeps its whole group at the usual time, workout or not.
        let workout = try XCTUnwrap(out.decision(F.id(F.today, .postWorkout)))
        XCTAssertEqual(workout.fireDate, F.at(19, 30))
        XCTAssertEqual(workout.reason.trigger, .usualTime)
        let mondays = out.filter { $0.planIDs.contains("mon") }
        XCTAssertFalse(mondays.isEmpty)
        XCTAssertTrue(mondays.allSatisfy { $0.day.weekday(in: F.ny) == 2 })
    }

    func testFollowUpsNeverOutliveTheirInitialAndSnoozesStay() {
        let snooze = DoseStatus(planID: "dinner", day: F.today, state: .snoozed(until: F.at(19, 0)))
        let tight = F.run(sixMoments, statuses: [snooze], prefs: worstCase(), now: F.at(9, 5), budget: 3)
        XCTAssertLessThanOrEqual(tight.count, 3)
        XCTAssertTrue(tight.contains { $0.stage == .snoozed })
        let initials = Set(tight.filter { $0.stage == .initial }.reminderIDs)
        for d in tight {
            if case .followUp = d.stage { XCTAssertTrue(initials.contains(F.id(d.day, d.moment)), d.id) }
        }
    }

    /// Sparse routines reach past two weeks with leftover slots, so the heads-up isn't on their next reminder.
    private func sparse(_ edit: (inout Preferences) -> Void = { _ in }) -> Preferences {
        F.prefs { $0.planningDays = 14; $0.maxPlanningDays = 28; edit(&$0) }
    }

    func testWeeklyPlanHeadsUpIsWeeksAwayNotOnTheNextReminder() throws {
        let prefs = sparse { $0.intensity = .gentle }
        let out = F.run([F.plan("m", .lunch, frequency: .weekdays([2]))], prefs: prefs, now: F.at(6, 0))
        XCTAssertEqual(out.map(\.day.key), ["2026-10-26", "2026-11-02", "2026-11-09", "2026-11-16"])
        let headsUp = try XCTUnwrap(ReminderEngine.headsUpDate(for: out, prefs: prefs, calendar: F.ny))
        XCTAssertEqual(headsUp, F.date(2026, 11, 9, 12, 30))
    }

    func testFillDaysTakeOnlyWhatFollowUpsLeave() {
        let plans = [F.plan("b", .breakfast), F.plan("d", .dinner)]
        let all = F.run(plans, prefs: sparse(), now: F.at(6, 0))
        XCTAssertLessThanOrEqual(all.count, ReminderEngine.maxDecisions)
        XCTAssertNotNil(all.decision(F.id(F.tomorrow, .breakfast, .followUp(1))))
        XCTAssertNotNil(all.decision(F.id(Day(year: 2026, month: 11, day: 19), .dinner)), "four weeks ahead")
        // With room for everything but the fill days, tomorrow's follow-ups still win.
        let tight = F.run(plans, prefs: sparse(), now: F.at(6, 0), budget: 32)
        XCTAssertNotNil(tight.decision(F.id(F.tomorrow, .breakfast, .followUp(1))))
        XCTAssertNotNil(tight.decision(F.id(F.tomorrow, .dinner, .followUp(1))))
        XCTAssertFalse(tight.contains { $0.day >= Day(year: 2026, month: 11, day: 6) })
    }
}
