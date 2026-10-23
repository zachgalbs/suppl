import XCTest
@testable import SupplCore

final class CopyTests: XCTestCase {
    typealias F = EngineFixtures
    let vitaminD = EngineFixtures.plan("d", .breakfast, name: "Vitamin D", dose: "1 softgel", withFood: true)
    let magnesium = EngineFixtures.plan("mg", .breakfast, name: "Magnesium", dose: "200 mg")
    let creatine = EngineFixtures.plan("c", .postWorkout, name: "Creatine", dose: "5 g")

    private func decision(_ moment: Moment, _ planIDs: [String], fire: Date, stage: ReminderStage = .initial,
                          _ reason: Reason) -> ReminderDecision {
        ReminderDecision(id: F.id(F.today, moment, stage), groupID: ReminderID.group(day: F.today, moment: moment),
                         day: F.today, moment: moment, planIDs: planIDs, fireDate: fire, stage: stage, reason: reason)
    }

    private func text(_ d: ReminderDecision, plans: [DosePlan]? = nil, privacy: Bool = false,
                      calendar: Calendar = EngineFixtures.ny) -> NotificationText {
        let t = ReminderCopy.notification(for: d, plans: plans ?? [vitaminD, magnesium, creatine], privacyMode: privacy,
                                          calendar: calendar, locale: F.locale)
        return NotificationText(title: t.title, body: F.normalized(t.body))
    }

    private func why(_ r: Reason, _ moment: Moment = .breakfast) -> String {
        F.normalized(ReminderCopy.whyNow(r, moment: moment, calendar: F.ny, locale: F.locale))
    }

    func testMomentTitles() {
        XCTAssertEqual(Moment.allCases.map(ReminderCopy.momentTitle),
                       ["On waking", "Breakfast time", "Lunch time", "Dinner time", "Before bed", "After your workout"])
    }

    func testUsualTimeBodyListsNamesDosesAndFoodNote() {
        let d = decision(.breakfast, ["d", "mg"], fire: F.at(8, 0), Reason(trigger: .usualTime, usualDate: F.at(8, 0), ruleID: "timing.usual.v1"))
        XCTAssertEqual(text(d), NotificationText(
            title: "Breakfast time",
            body: "Your usual time for Vitamin D (1 softgel) and Magnesium (200 mg). Take with food."))
    }

    func testThreePlansUseCommasAndNoFoodNoteWhenNoneNeedFood() {
        let plans = [F.plan("a", .lunch, name: "Zinc", dose: "15 mg"), F.plan("b", .lunch, name: "Iron", dose: ""),
                     F.plan("c", .lunch, name: "Omega-3", dose: "2 capsules")]
        let d = decision(.lunch, ["a", "b", "c"], fire: F.at(12, 30), Reason(trigger: .usualTime, ruleID: "timing.usual.v1"))
        XCTAssertEqual(text(d, plans: plans).body, "Your usual time for Zinc (15 mg), Iron, and Omega-3 (2 capsules).")
    }

    func testWorkoutBodyNamesTheSourceAndEndTime() {
        let r = Reason(trigger: .workoutEnded, source: .appleHealth, dataTimestamp: F.at(17, 42), ruleID: "timing.workout.v1")
        let t = text(decision(.postWorkout, ["c"], fire: F.at(17, 44), r))
        XCTAssertEqual(t.title, "After your workout")
        XCTAssertEqual(t.body, "Apple Health recorded a workout ending at 5:42 PM. Time for Creatine (5 g).")
    }

    func testTimesUseTheCalendarsTimeZone() {
        let r = Reason(trigger: .workoutEnded, source: .whoop, dataTimestamp: F.at(17, 42), ruleID: "timing.workout.v1")
        XCTAssertEqual(text(decision(.postWorkout, ["c"], fire: F.at(17, 44), r), calendar: F.la).body,
                       "WHOOP recorded a workout ending at 2:42 PM. Time for Creatine (5 g).")
    }

    func testWorkoutFallbackIsHonest() {
        let r = Reason(trigger: .workoutFallback, usualDate: F.at(19, 30), ruleID: "timing.workoutFallback.v1")
        XCTAssertEqual(text(decision(.postWorkout, ["c"], fire: F.at(19, 30), r)).body,
                       "Here's your usual after-workout reminder for Creatine (5 g).")
    }

    func testStaleWorkoutNeverProducesJustFinishedWording() {
        let out = F.run([creatine], signals: [F.workout(F.at(13, 0), F.at(14, 0))], prefs: F.pro(), now: F.at(17, 0))
        let d = try! XCTUnwrap(out.decision(F.id(F.today, .postWorkout)))
        let body = text(d).body.lowercased()
        let sheet = why(d.reason, .postWorkout).lowercased()
        for phrase in ["recorded a workout", "just finished", "no workout"] {
            XCTAssertFalse(body.contains(phrase), body)
            XCTAssertFalse(sheet.contains(phrase), sheet)
        }
    }

    func testLateWakeMentionsSourceAndShiftedTime() {
        let r = Reason(trigger: .lateWake, source: .appleHealth, dataTimestamp: F.at(8, 40), usualDate: F.at(8, 0), ruleID: "timing.lateWake.v1")
        XCTAssertEqual(text(decision(.breakfast, ["mg"], fire: F.at(9, 30), r)).body,
                       "Apple Health shows you woke at 8:40 AM, so this moved to 9:30 AM. Time for Magnesium (200 mg).")
    }

    func testCalendarMoveUsesConditionalWording() {
        let r = Reason(trigger: .calendarGap, source: .calendar, usualDate: F.at(8, 0), ruleID: "timing.calendarGap.v1")
        XCTAssertEqual(text(decision(.breakfast, ["d"], fire: F.at(7, 30), r)).body,
                       "You have a free moment. If you're eating, it's a good time for Vitamin D (1 softgel). Take with food.")
        // Outside meals there's no talk of eating at all.
        let bed = F.plan("mel", .bedtime, name: "Melatonin", dose: "1 tablet")
        XCTAssertEqual(text(decision(.bedtime, ["mel"], fire: F.at(21, 30), r), plans: [bed]).body,
                       "You have a free moment, so it's a good time for Melatonin (1 tablet).")
    }

    func testFollowUpIsGentle() {
        let r = Reason(trigger: .followUp, dataTimestamp: F.at(8, 0), ruleID: "timing.followUp.v1")
        let t = text(decision(.breakfast, ["mg"], fire: F.at(8, 30), stage: .followUp(1), r))
        XCTAssertEqual(t.title, "Breakfast time")
        XCTAssertEqual(t.body, "Still open: Magnesium (200 mg). No rush, take it when it suits you.")
    }

    func testSnoozedAndQuietHoursBodies() {
        let snooze = Reason(trigger: .snoozed, dataTimestamp: F.at(8, 30), ruleID: "timing.snooze.v1")
        XCTAssertEqual(text(decision(.breakfast, ["mg"], fire: F.at(8, 30), stage: .snoozed, snooze)).body,
                       "Here's the reminder you snoozed: Magnesium (200 mg).")
        let quiet = Reason(trigger: .quietHours, usualDate: F.at(6, 30), ruleID: "timing.quietHours.v1")
        XCTAssertEqual(text(decision(.breakfast, ["mg"], fire: F.at(7, 0), quiet)).body,
                       "Your quiet hours have ended. Time for Magnesium (200 mg).")
    }

    func testPrivacyModeHidesEverything() {
        let r = Reason(trigger: .workoutEnded, source: .appleHealth, dataTimestamp: F.at(17, 42), ruleID: "timing.workout.v1")
        XCTAssertEqual(text(decision(.postWorkout, ["c"], fire: F.at(17, 44), r), privacy: true),
                       NotificationText(title: "suppl.", body: "suppl. has a reminder for you."))
    }

    func testUnknownPlansStillReadNaturally() {
        let d = decision(.lunch, ["gone"], fire: F.at(12, 30), Reason(trigger: .usualTime, ruleID: "timing.usual.v1"))
        XCTAssertEqual(text(d).body, "Your usual time for your supplements.")
    }

    func testWhyNowNamesSourceAndTimestampForEveryTrigger() {
        let cases: [(Reason, Moment, [String])] = [
            (Reason(trigger: .usualTime, usualDate: F.at(8, 0), ruleID: "u"), .breakfast, ["8:00 AM", "usual breakfast time"]),
            (Reason(trigger: .workoutEnded, source: .appleHealth, dataTimestamp: F.at(17, 42), ruleID: "w"), .postWorkout,
             ["Apple Health", "5:42 PM"]),
            (Reason(trigger: .workoutFallback, usualDate: F.at(19, 30), ruleID: "f"), .postWorkout, ["hadn't recorded a workout", "7:30 PM"]),
            (Reason(trigger: .lateWake, source: .whoop, dataTimestamp: F.at(8, 40), usualDate: F.at(7, 0), ruleID: "l"), .wake,
             ["WHOOP", "8:40 AM", "7:00 AM"]),
            (Reason(trigger: .calendarGap, source: .calendar, usualDate: F.at(8, 0), ruleID: "c"), .breakfast,
             ["calendar", "8:00 AM", "never event details"]),
            (Reason(trigger: .snoozed, dataTimestamp: F.at(8, 30), ruleID: "s"), .breakfast, ["snoozed", "8:30 AM"]),
            (Reason(trigger: .followUp, dataTimestamp: F.at(8, 0), ruleID: "f"), .breakfast, ["8:00 AM", "follow-up"]),
            (Reason(trigger: .quietHours, usualDate: F.at(6, 30), ruleID: "q"), .wake, ["6:30 AM", "quiet hours"]),
        ]
        XCTAssertEqual(Set(cases.map(\.0.trigger.rawValue)).count, 8, "every trigger is covered")
        for (reason, moment, needles) in cases {
            let s = why(reason, moment)
            XCTAssertTrue(s.hasSuffix("."), s)
            for needle in needles { XCTAssertTrue(s.contains(needle), "\(s) should mention \(needle)") }
        }
    }

    func testWhyNowWithoutTimestampsIsStillAFullSentence() {
        for trigger in [Reason.Trigger.usualTime, .workoutEnded, .workoutFallback, .lateWake, .calendarGap, .snoozed, .followUp, .quietHours] {
            let s = why(Reason(trigger: trigger, ruleID: "x"))
            XCTAssertTrue(s.hasSuffix("."), s)
            XCTAssertFalse(s.contains("  "), s)
            XCTAssertGreaterThan(s.count, 20, s)
        }
    }

    /// Safety and style rules over every string the engine can produce.
    func testNoUserFacingStringBreaksTheCopyRules() {
        let plans = [vitaminD, magnesium, creatine, F.plan("w", .wake, name: "B12", dose: "1 tablet")]
        let now = F.at(7, 40)
        let signals = [F.wake(F.at(7, 35)), F.workout(F.at(6, 40), F.at(7, 30)),
                       F.busy([(F.at(7, 30), F.at(8, 10))], observed: now)]
        var strings: [String] = []
        let out = F.run(plans, signals: signals, prefs: F.pro(intensity: .extraHelp), now: now)
            + F.run(plans, statuses: [DoseStatus(planID: "mg", day: F.today, state: .snoozed(until: F.at(9, 0)))],
                    prefs: F.prefs(contextAware: true, sources: [.whoop]), now: now)
        for d in out {
            let t = text(d, plans: plans)
            strings += [t.title, t.body, why(d.reason, d.moment)]
        }
        for trigger in [Reason.Trigger.usualTime, .workoutEnded, .workoutFallback, .lateWake, .calendarGap, .snoozed, .followUp, .quietHours] {
            strings.append(why(Reason(trigger: trigger, ruleID: "x")))
        }
        strings += [ReminderCopy.privateTitle, ReminderCopy.privateBody]
        XCTAssertGreaterThan(out.count, 5)
        for s in strings {
            let lower = s.lowercased()
            XCTAssertFalse(s.contains("\u{2014}") || s.contains("\u{2013}"), "dash in: \(s)")
            XCTAssertFalse(s.contains("!"), s)
            for banned in ["missed", "double", "diagnos", "deficien", "extra dose", "increase your dose"] {
                XCTAssertFalse(lower.contains(banned), "\(banned) in: \(s)")
            }
        }
    }
}
