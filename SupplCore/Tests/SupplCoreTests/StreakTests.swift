import XCTest
@testable import SupplCore

final class StreakTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }
    // Friday.
    private let today = Day(year: 2026, month: 10, day: 23)

    private func day(_ offset: Int) -> Day { today.adding(days: offset, calendar: calendar) }
    private func plan(_ id: String, _ frequency: Frequency = .daily, since: Int = -30) -> Streak.Plan {
        Streak.Plan(plan: DosePlan(id: id, name: id, doseText: "1 capsule", moment: .breakfast, withFood: true,
                                   frequency: frequency), since: day(since))
    }
    private func streak(_ plans: [Streak.Plan], _ confirmed: [String: Set<Day>]) -> Int {
        Streak.confirmedDays(plans: plans, confirmed: confirmed, today: today, calendar: calendar)
    }

    func testNoPlansNoStreak() {
        XCTAssertEqual(streak([], [:]), 0)
    }

    func testCountsConsecutiveConfirmedDaysIncludingToday() {
        XCTAssertEqual(streak([plan("d")], ["d": [day(0), day(-1), day(-2)]]), 3)
    }

    func testUnfinishedTodayDoesNotBreakTheStreak() {
        XCTAssertEqual(streak([plan("d")], ["d": [day(-1), day(-2)]]), 2)
    }

    func testAGapEndsTheStreak() {
        XCTAssertEqual(streak([plan("d")], ["d": [day(0), day(-1), day(-3), day(-4)]]), 2)
    }

    func testEveryDueDoseMustBeConfirmed() {
        let plans = [plan("a"), plan("b")]
        XCTAssertEqual(streak(plans, ["a": [day(0), day(-1)], "b": [day(0)]]), 1)
    }

    func testDaysWithNothingDueAreSkipped() {
        // Weekdays only: Mon 19 to Fri 23. The weekend before doesn't break it.
        let weekdays = plan("w", .weekdays([2, 3, 4, 5, 6]))
        let confirmed: Set<Day> = [day(0), day(-1), day(-2), day(-3), day(-4), day(-7)]
        XCTAssertEqual(streak([weekdays], ["w": confirmed]), 6)
    }

    func testDaysBeforeAPlanWasAddedDontExpectIt() {
        let old = plan("old")
        let new = plan("new", since: -1)
        XCTAssertEqual(streak([old, new], ["old": [day(0), day(-1), day(-2)], "new": [day(0), day(-1)]]), 3)
    }

    func testSkippedOrUnconfirmedDaysAreNotCounted() {
        // Only confirmed days are passed in; a skipped day is simply absent.
        XCTAssertEqual(streak([plan("d")], ["d": [day(-2)]]), 0)
    }
}
