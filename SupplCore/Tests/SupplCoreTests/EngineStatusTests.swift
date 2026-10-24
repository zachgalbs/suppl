import XCTest
@testable import SupplCore

/// Statuses, snoozes, follow-ups, and delivered history.
final class EngineStatusTests: XCTestCase {
    typealias F = EngineFixtures
    let d = EngineFixtures.plan("d", .breakfast)
    let mg = EngineFixtures.plan("mg", .breakfast)

    private func status(_ id: String, _ state: DoseState, day: Day = EngineFixtures.today) -> DoseStatus {
        DoseStatus(planID: id, day: day, state: state)
    }

    // MARK: Statuses

    func testConfirmedPlanLeavesItsGroup() {
        let out = F.run([d, mg], statuses: [status("d", .confirmed(at: F.at(6, 30)))], now: F.at(7, 0))
        XCTAssertEqual(out.decision(F.id(F.today, .breakfast))?.planIDs, ["mg"])
        XCTAssertEqual(out.decision(F.id(F.today, .breakfast, .followUp(1)))?.planIDs, ["mg"])
        // Statuses are per day: tomorrow has both again.
        XCTAssertEqual(out.decision(F.id(F.tomorrow, .breakfast))?.planIDs, ["d", "mg"])
    }

    func testEmptyGroupHasNoReminderOrFollowUps() {
        let statuses = [status("d", .confirmed(at: F.at(6, 30))), status("mg", .skipped(at: F.at(6, 31)))]
        let out = F.run([d, mg], statuses: statuses, now: F.at(7, 0))
        XCTAssertFalse(out.contains { $0.day == F.today })
        XCTAssertEqual(out.first?.day, F.tomorrow)
    }

    func testPendingAndUnconfirmedStayOpen() {
        let statuses = [status("d", .pending), status("mg", .unconfirmed)]
        let out = F.run([d, mg], statuses: statuses, now: F.at(7, 0))
        XCTAssertEqual(out.decision(F.id(F.today, .breakfast))?.planIDs, ["d", "mg"])
    }

    func testLatestStatusForAPlanAndDayWins() {
        let statuses = [status("d", .confirmed(at: F.at(6, 0))), status("d", .pending)]
        let out = F.run([d], statuses: statuses, now: F.at(7, 0))
        XCTAssertNotNil(out.decision(F.id(F.today, .breakfast)))
    }

    // MARK: Snooze

    func testSnoozeReplacesTheInitialAndFollowUps() {
        let until = F.at(8, 35)
        let out = F.run([d, mg], statuses: [status("d", .snoozed(until: until)), status("mg", .snoozed(until: until))],
                        prefs: F.prefs(intensity: .extraHelp), now: F.at(8, 5))
        let today = out.filter { $0.day == F.today }
        XCTAssertEqual(today.reminderIDs, ["suppl.2026-10-23.breakfast.s"])
        XCTAssertEqual(today.first?.stage, .snoozed)
        XCTAssertEqual(today.first?.fireDate, until)
        XCTAssertEqual(today.first?.reason.trigger, .snoozed)
        XCTAssertEqual(today.first?.reason.dataTimestamp, until)
        XCTAssertEqual(today.first?.planIDs, ["d", "mg"])
    }

    func testSnoozeMayRunPastTheWindow() {
        let until = F.at(10, 0)  // Breakfast window ends 9:30.
        let out = F.run([d], statuses: [status("d", .snoozed(until: until))], now: F.at(9, 30))
        XCTAssertEqual(out.decision(F.id(F.today, .breakfast, .snoozed))?.fireDate, until)
    }

    func testSnoozeThatAlreadyFiredProducesNothing() {
        let out = F.run([d], statuses: [status("d", .snoozed(until: F.at(8, 30)))], now: F.at(8, 45))
        XCTAssertFalse(out.contains { $0.day == F.today })
    }

    func testSnoozeIntoQuietHoursIsDropped() {
        let bed = F.plan("mel", .bedtime)
        let out = F.run([bed], statuses: [status("mel", .snoozed(until: F.at(23, 0)))], now: F.at(22, 30))
        // Quiet hours run 22:30 to 6:45; moving a bedtime dose to the morning would be wrong, so it's dropped.
        XCTAssertFalse(out.contains { $0.day == F.today })
    }

    // MARK: Follow-ups

    func testFollowUpCountFollowsIntensity() {
        let expected: [Intensity: [Date]] = [
            .gentle: [F.at(8, 0)],
            .balanced: [F.at(8, 0), F.at(8, 30)],
            .extraHelp: [F.at(8, 0), F.at(8, 30), F.at(9, 0)],
        ]
        for (intensity, times) in expected {
            let out = F.run([d], prefs: F.prefs(intensity: intensity), now: F.at(6, 0)).filter { $0.day == F.today }
            XCTAssertEqual(out.map(\.fireDate), times, "\(intensity)")
        }
        let extra = F.run([d], prefs: F.prefs(intensity: .extraHelp), now: F.at(6, 0))
        XCTAssertEqual(extra.decision(F.id(F.today, .breakfast, .followUp(2)))?.stage, .followUp(2))
        XCTAssertEqual(extra.decision(F.id(F.today, .breakfast, .followUp(1)))?.reason.trigger, .followUp)
        XCTAssertEqual(extra.decision(F.id(F.today, .breakfast, .followUp(1)))?.reason.ruleID, "timing.followUp.v1")
        XCTAssertEqual(extra.decision(F.id(F.today, .breakfast, .followUp(1)))?.reason.dataTimestamp, F.at(8, 0))
    }

    func testFollowUpsStopAtTheWindowEnd() {
        let prefs = F.prefs(intensity: .extraHelp) { $0.followUpDelayMinutes = 60 }
        let out = F.run([d], prefs: prefs, now: F.at(6, 0)).filter { $0.day == F.today }
        // 8:00, 9:00; 10:00 is past the 9:30 window end.
        XCTAssertEqual(out.map(\.fireDate), [F.at(8, 0), F.at(9, 0)])
    }

    func testFollowUpsAreTimedFromAMovedInitial() {
        let busy = F.busy([(F.at(7, 45), F.at(8, 40))], observed: F.at(6, 0))
        let out = F.run([d], signals: [busy], prefs: F.pro(intensity: .balanced), now: F.at(6, 0))
        let f1 = out.decision(F.id(F.today, .breakfast, .followUp(1)))
        XCTAssertEqual(f1?.fireDate, F.at(8, 0))
        XCTAssertEqual(f1?.reason.dataTimestamp, F.at(7, 30))
    }

    func testDeliveredInitialAnchorsFollowUpsAndIsNotResent() {
        let delivered = ReminderDecision(
            id: F.id(F.today, .breakfast), groupID: ReminderID.group(day: F.today, moment: .breakfast), day: F.today,
            moment: .breakfast, planIDs: ["d"], fireDate: F.at(8, 5), stage: .initial,
            reason: Reason(trigger: .calendarGap, source: .calendar, usualDate: F.at(8, 0), ruleID: "timing.calendarGap.v1"))
        let out = F.run([d], history: [delivered], now: F.at(8, 10))
        XCTAssertNil(out.decision(F.id(F.today, .breakfast)))
        XCTAssertEqual(out.decision(F.id(F.today, .breakfast, .followUp(1)))?.fireDate, F.at(8, 35))
    }

    func testDeliveredFollowUpIsNotResent() {
        let initial = F.run([d], prefs: F.prefs(intensity: .extraHelp), now: F.at(6, 0)).filter { $0.day == F.today }
        let out = F.run([d], history: Array(initial.prefix(2)), prefs: F.prefs(intensity: .extraHelp), now: F.at(8, 20))
        XCTAssertEqual(out.filter { $0.day == F.today }.reminderIDs, ["suppl.2026-10-23.breakfast.f2"])
    }

    func testNoFollowUpForAnInitialThatWasNeverSent() {
        // Added at 8:10, after the 8:00 usual time: nothing went out, so "Still open" would be a lie.
        let out = F.run([d], now: F.at(8, 10))
        XCTAssertEqual(out.filter { $0.day == F.today }.reminderIDs, [])
    }

    func testZeroDelayMeansNoFollowUps() {
        let prefs = F.prefs(intensity: .extraHelp) { $0.followUpDelayMinutes = 0 }
        XCTAssertEqual(F.run([d], prefs: prefs, now: F.at(6, 0)).filter { $0.day == F.today }.count, 1)
    }
}
