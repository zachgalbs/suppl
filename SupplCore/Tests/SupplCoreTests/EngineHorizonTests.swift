import XCTest
@testable import SupplCore

/// Every trigger is one-shot, so the planning horizon is how long reminders keep coming if the app
/// is never opened again. The old build used repeating triggers; a two-day horizon would be a regression.
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

    func testCapDropsTheFarthestInitialsFirst() {
        let plans = Moment.allCases.map { F.plan($0.rawValue, $0) }
        let out = F.run(plans, prefs: week(.extraHelp), now: F.at(0, 1))
        XCTAssertEqual(out.count, ReminderEngine.maxDecisions)
        XCTAssertEqual(out.map(\.fireDate), out.map(\.fireDate).sorted())
        // Today's and tomorrow's follow-ups all survive the cap.
        let keptFollowUps = out.filter { $0.stage != .initial }.count
        let allFollowUps = F.run(plans, prefs: F.prefs(intensity: .extraHelp), now: F.at(0, 1))
            .filter { $0.stage != .initial }.count
        XCTAssertEqual(keptFollowUps, allFollowUps)
    }

    func testDefaultHorizonIsAWeek() {
        XCTAssertEqual(Preferences().planningDays, 7)
    }
}
