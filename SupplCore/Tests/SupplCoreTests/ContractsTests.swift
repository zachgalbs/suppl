import XCTest
@testable import SupplCore

final class ContractsTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    /// Moment raw values are persisted through the app's `Slot`. Renaming one breaks existing installs.
    func testMomentRawValuesAreStable() {
        XCTAssertEqual(Moment.allCases.map(\.rawValue),
                       ["wake", "breakfast", "lunch", "dinner", "bedtime", "postWorkout"])
    }

    func testDayKeyAndArithmetic() {
        let day = Day(year: 2026, month: 12, day: 31)
        XCTAssertEqual(day.key, "2026-12-31")
        XCTAssertEqual(day.adding(days: 1, calendar: calendar).key, "2027-01-01")
        XCTAssertEqual(Day(day.start(in: calendar), calendar: calendar), day)
        XCTAssertLessThan(day, day.adding(days: 1, calendar: calendar))
    }

    func testReminderIdentifiers() {
        let day = Day(year: 2026, month: 3, day: 8)
        XCTAssertEqual(ReminderID.make(day: day, moment: .breakfast, stage: .initial), "suppl.2026-03-08.breakfast")
        XCTAssertEqual(ReminderID.make(day: day, moment: .breakfast, stage: .followUp(1)), "suppl.2026-03-08.breakfast.f1")
        XCTAssertEqual(ReminderID.make(day: day, moment: .postWorkout, stage: .snoozed), "suppl.2026-03-08.postWorkout.s")
        XCTAssertTrue(ReminderID.isEngineID("suppl.2026-03-08.breakfast.f1"))
        XCTAssertFalse(ReminderID.isEngineID("suppl.breakfast"))
        XCTAssertFalse(ReminderID.isEngineID("suppl.followup.breakfast"))
        XCTAssertFalse(ReminderID.isEngineID("suppl.test"))
    }

    func testPreferenceDefaultsMatchTheApp() {
        let prefs = Preferences()
        XCTAssertEqual(prefs.usualMinutes(for: .breakfast), 8 * 60)
        XCTAssertEqual(prefs.intensity, .balanced)
        XCTAssertEqual(prefs.intensity.maxFollowUps, 1)
        XCTAssertFalse(prefs.contextAware)
        XCTAssertEqual(prefs.window(for: .breakfast), MomentWindow(before: 30, after: 90))
    }

    func testDecisionRoundTripsThroughJSON() throws {
        let day = Day(year: 2026, month: 10, day: 23)
        let decision = ReminderDecision(
            id: ReminderID.make(day: day, moment: .lunch, stage: .followUp(1)),
            groupID: ReminderID.group(day: day, moment: .lunch), day: day, moment: .lunch,
            planIDs: ["a"], fireDate: Date(timeIntervalSince1970: 1_800_000_000), stage: .followUp(1),
            reason: Reason(trigger: .followUp, ruleID: "timing.followUp.v1"))
        let data = try JSONEncoder().encode(decision)
        XCTAssertEqual(try JSONDecoder().decode(ReminderDecision.self, from: data), decision)
    }
}
