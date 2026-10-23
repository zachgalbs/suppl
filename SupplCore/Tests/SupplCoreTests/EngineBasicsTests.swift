import XCTest
@testable import SupplCore

/// Due plans, grouping, the usual-time fallback, ordering, the cap, and idempotence.
final class EngineBasicsTests: XCTestCase {
    typealias F = EngineFixtures

    func testDailyPlanGetsUsualTimeReminderTodayAndTomorrow() {
        let out = F.run([F.plan("d", .breakfast)], prefs: F.prefs(intensity: .gentle), now: F.at(6, 0))
        XCTAssertEqual(out.reminderIDs, ["suppl.2026-10-23.breakfast", "suppl.2026-10-24.breakfast"])
        XCTAssertEqual(out[0].fireDate, F.at(8, 0))
        XCTAssertEqual(out[1].fireDate, F.at(8, 0, day: 24))
        XCTAssertEqual(out[0].groupID, ReminderID.group(day: F.today, moment: .breakfast))
        XCTAssertEqual(out[0].stage, .initial)
        XCTAssertEqual(out[0].reason.trigger, .usualTime)
        XCTAssertEqual(out[0].reason.ruleID, "timing.usual.v1")
        XCTAssertEqual(out[0].reason.usualDate, F.at(8, 0))
    }

    func testWeekdayPlanIsDueOnlyOnItsDays() {
        // Today is Friday (6), tomorrow Saturday (7).
        let saturdays = F.plan("s", .lunch, frequency: .weekdays([7]))
        let fridays = F.plan("f", .dinner, frequency: .weekdays([6]))
        let out = F.run([saturdays, fridays], prefs: F.prefs(intensity: .gentle), now: F.at(6, 0))
        XCTAssertEqual(out.reminderIDs, ["suppl.2026-10-23.dinner", "suppl.2026-10-24.lunch"])
    }

    func testOneDecisionPerMomentKeepingInputOrder() {
        let plans = [F.plan("zeta", .breakfast), F.plan("alpha", .breakfast), F.plan("dinner1", .dinner)]
        let out = F.run(plans, prefs: F.prefs(intensity: .gentle), now: F.at(6, 0))
        let todays = out.filter { $0.day == F.today }
        XCTAssertEqual(todays.count, 2)
        // Plan ids keep the order the app passed them in, not alphabetical.
        XCTAssertEqual(todays.decision(F.id(F.today, .breakfast))?.planIDs, ["zeta", "alpha"])
        XCTAssertEqual(todays.decision(F.id(F.today, .dinner))?.planIDs, ["dinner1"])
    }

    func testDuplicatePlanIDsAreCountedOnce() {
        let out = F.run([F.plan("a", .lunch), F.plan("a", .lunch)], prefs: F.prefs(intensity: .gentle), now: F.at(6, 0))
        XCTAssertEqual(out.first?.planIDs, ["a"])
    }

    func testOutputSortedByFireDateThenID() {
        let prefs = F.prefs(intensity: .gentle) { $0.usualTimes[.breakfast] = 7 * 60 }
        let out = F.run([F.plan("w", .wake), F.plan("b", .breakfast), F.plan("l", .lunch)], prefs: prefs, now: F.at(6, 50))
        // Wake and breakfast share 7:00; the id breaks the tie.
        XCTAssertEqual(Array(out.reminderIDs.prefix(3)),
                       ["suppl.2026-10-23.breakfast", "suppl.2026-10-23.wake", "suppl.2026-10-23.lunch"])
        XCTAssertEqual(out, out.sorted { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) })
    }

    func testFallbackFiresEveryMomentAtItsUsualTime() {
        let plans = Moment.allCases.map { F.plan($0.rawValue, $0) }
        let prefs = F.prefs(intensity: .gentle)
        let out = F.run(plans, prefs: prefs, now: F.at(0, 30))
        XCTAssertEqual(out.count, 12)
        for d in out {
            XCTAssertEqual(d.reason.trigger, .usualTime, d.id)
            XCTAssertEqual(d.fireDate, WallClock.date(d.day, minutes: prefs.usualMinutes(for: d.moment), calendar: F.ny), d.id)
        }
    }

    func testContextAwareOffIgnoresEverySignal() {
        let plans = [F.plan("w", .wake), F.plan("b", .breakfast), F.plan("p", .postWorkout)]
        let now = F.at(7, 30)
        let signals = [
            F.wake(F.at(7, 25)),
            F.workout(F.at(6, 30), F.at(7, 20)),
            F.busy([(F.at(7, 30), F.at(12, 0))], observed: now),
        ]
        // Free tier, but with connected sources left over from a lapsed subscription.
        let free = F.prefs(contextAware: false, sources: [.appleHealth, .whoop, .calendar])
        let withSignals = F.run(plans, signals: signals, prefs: free, now: now)
        let without = F.run(plans, prefs: free, now: now)
        XCTAssertEqual(withSignals, without)
        XCTAssertTrue(withSignals.allSatisfy { $0.reason.trigger == .usualTime || $0.reason.trigger == .followUp })
        XCTAssertEqual(withSignals.decision(F.id(F.today, .postWorkout))?.reason.trigger, .usualTime)
    }

    func testProWithNoSignalsMatchesFreeTiming() {
        let plans = [F.plan("b", .breakfast), F.plan("d", .dinner)]
        let pro = F.run(plans, prefs: F.pro(intensity: .balanced), now: F.at(6, 0))
        let free = F.run(plans, prefs: F.prefs(), now: F.at(6, 0))
        XCTAssertEqual(pro, free)
    }

    func testPastRemindersAreDropped() {
        let out = F.run([F.plan("b", .breakfast)], prefs: F.prefs(), now: F.at(9, 0))
        // 8:00 and its 8:30 follow-up are past; tomorrow remains.
        XCTAssertEqual(out.reminderIDs, ["suppl.2026-10-24.breakfast", "suppl.2026-10-24.breakfast.f1"])
        XCTAssertTrue(out.allSatisfy { $0.fireDate > F.at(9, 0) })
    }

    func testCapKeepsTheSoonest48() {
        let base = F.at(0, 0)
        let many = (0..<60).reversed().map { i in
            ReminderDecision(id: String(format: "x%02d", i), groupID: "g", day: F.today, moment: .lunch, planIDs: ["a"],
                             fireDate: base.addingTimeInterval(TimeInterval(i * 60)), stage: .initial,
                             reason: Reason(trigger: .usualTime, ruleID: "timing.usual.v1"))
        }
        let capped = ReminderEngine.capped(many)
        XCTAssertEqual(capped.count, ReminderEngine.maxDecisions)
        XCTAssertEqual(capped.first?.id, "x00")
        XCTAssertEqual(capped.last?.id, "x47")
    }

    func testBusiestRealInputStaysUnderTheCap() {
        let plans = Moment.allCases.flatMap { m in (0..<5).map { F.plan("\(m.rawValue)\($0)", m) } }
        let out = F.run(plans, prefs: F.prefs(intensity: .extraHelp) { $0.followUpDelayMinutes = 10 }, now: F.at(0, 1))
        XCTAssertLessThanOrEqual(out.count, 48)
        XCTAssertEqual(Set(out.reminderIDs).count, out.count, "ids must be unique")
    }

    func testSameInputsGiveIdenticalOutput() {
        let plans = [F.plan("w", .wake), F.plan("b", .breakfast, withFood: true), F.plan("p", .postWorkout),
                     F.plan("bed", .bedtime)]
        let now = F.at(7, 40)
        let signals = [F.wake(F.at(7, 35)), F.workout(F.at(6, 40), F.at(7, 30)), F.workout(F.at(6, 41), F.at(7, 33), .whoop),
                       F.busy([(F.at(8, 30), F.at(9, 0))], observed: now)]
        let statuses = [DoseStatus(planID: "bed", day: F.today, state: .unconfirmed)]
        let prefs = F.pro(intensity: .extraHelp)
        let first = F.run(plans, statuses: statuses, signals: signals, prefs: prefs, now: now)
        let second = F.run(plans, statuses: statuses, signals: signals, prefs: prefs, now: now)
        XCTAssertEqual(first, second)
        // Signal order is irrelevant too.
        XCTAssertEqual(first, F.run(plans, statuses: statuses, signals: signals.reversed(), prefs: prefs, now: now))
        XCTAssertFalse(first.isEmpty)
    }

    func testNothingFiresOutsideItsWindow() {
        let plans = Moment.allCases.map { F.plan($0.rawValue, $0) }
        let prefs = F.pro(intensity: .extraHelp)
        for hour in [0, 6, 7, 9, 12, 17, 21] {
            let now = F.at(hour, 5)
            let signals = [
                F.wake(F.at(min(hour, 11), 0)),
                F.workout(F.at(max(hour - 1, 0), 0), now.addingTimeInterval(-60)),
                F.busy([(F.at(7, 0), F.at(13, 0)), (F.at(18, 0), F.at(23, 0))], observed: now),
            ]
            let out = F.run(plans, signals: signals, prefs: prefs, now: now)
            for d in out where d.stage != .snoozed {
                let usual = WallClock.date(d.day, minutes: prefs.usualMinutes(for: d.moment), calendar: F.ny)
                let w = prefs.window(for: d.moment)
                var window = DateInterval(start: usual.addingTimeInterval(TimeInterval(-w.before * 60)),
                                          end: usual.addingTimeInterval(TimeInterval(w.after * 60)))
                // Workout-triggered reminders use the workout's own window.
                let initial = d.stage == .initial ? d : out.first { $0.groupID == d.groupID && $0.stage == .initial }
                if d.moment == .postWorkout, d.stage != .initial, initial == nil { continue }
                if d.moment == .postWorkout, let initial, let end = initial.reason.dataTimestamp,
                   initial.reason.trigger == .workoutEnded || initial.reason.trigger == .quietHours {
                    window = DateInterval(start: end, duration: TimeInterval(w.after * 60))
                }
                XCTAssertTrue(window.contains(d.fireDate), "\(d.id) at hour \(hour) fired outside its window")
                XCTAssertGreaterThan(d.fireDate, now)
            }
        }
    }
}
