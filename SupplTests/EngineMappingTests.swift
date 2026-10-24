import XCTest
import SwiftData
import UserNotifications
import SupplCore
@testable import suppl

/// The app-side mapping from SwiftData and UserDefaults to the engine's inputs.
@MainActor
final class EngineMappingTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 9))! }

    private func defaults() -> UserDefaults {
        let name = "EngineMappingTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testDosePlanCarriesSavedFieldsUnchanged() {
        let s = Supplement(name: "Creatine", dose: 5, unit: "g", slot: .postWorkout, withFood: false)
        s.frequencyRaw = "weekdays"
        s.weekdays = [2, 4, 6]
        s.clinicianDirected = true
        s.catalogID = "creatine"
        let plan = s.dosePlan
        XCTAssertEqual(plan.id, s.planID)
        XCTAssertEqual(plan.doseText, "5 g")
        XCTAssertEqual(plan.moment, .postWorkout)
        XCTAssertEqual(plan.frequency, .weekdays([2, 4, 6]))
        XCTAssertTrue(plan.clinicianDirected)
        XCTAssertEqual(plan.catalogID, "creatine")
        XCTAssertEqual(plan.startDate, s.createdAt)
    }

    func testPreferencesUseSavedTimesAndDefaultToTodaysBehaviour() {
        let d = defaults()
        d.set(7 * 60 + 15, forKey: Slot.breakfast.storageKey)
        let prefs = Preferences.current(isPro: false, connectedSources: [.appleHealth], defaults: d)
        XCTAssertEqual(prefs.usualMinutes(for: .breakfast), 7 * 60 + 15)
        XCTAssertEqual(prefs.usualMinutes(for: .lunch), Slot.lunch.defaultMinutes)
        XCTAssertEqual(prefs.intensity, .balanced)
        XCTAssertNil(prefs.quietHours)
        XCTAssertFalse(prefs.contextAware)
        XCTAssertTrue(prefs.connectedSources.isEmpty, "free users get usual times only")
    }

    func testExtraHelpAndContextNeedPro() {
        let d = defaults()
        d.set(Intensity.extraHelp.rawValue, forKey: PrefKey.intensity)
        XCTAssertEqual(Preferences.current(isPro: false, connectedSources: [], defaults: d).intensity, .balanced)
        let pro = Preferences.current(isPro: true, connectedSources: [.whoop], defaults: d)
        XCTAssertEqual(pro.intensity, .extraHelp)
        XCTAssertTrue(pro.contextAware)
        XCTAssertEqual(pro.connectedSources, [.whoop])
    }

    func testCustomQuietHoursAndPrivacy() {
        let d = defaults()
        d.set(23 * 60, forKey: PrefKey.quietStart)
        d.set(6 * 60, forKey: PrefKey.quietEnd)
        d.set(true, forKey: PrefKey.privacyMode)
        let prefs = Preferences.current(isPro: false, connectedSources: [], defaults: d)
        XCTAssertEqual(prefs.quietHours, QuietHours(start: 23 * 60, end: 6 * 60))
        XCTAssertTrue(prefs.privacyMode)
    }

    func testStatusesFollowTakenSkipAndSnooze() {
        let today = Day(now, calendar: calendar)
        let taken = Supplement(name: "Vitamin D")
        taken.lastTakenAt = now
        let skipped = Supplement(name: "Iron")
        let snoozed = Supplement(name: "Zinc")
        let silent = Supplement(name: "Magnesium")
        let until = now.addingTimeInterval(1800)
        let logs = [
            DoseLog(supplementID: skipped.planID, dayKey: today.key, action: .skipped, at: now, source: .notification),
            DoseLog(supplementID: snoozed.planID, dayKey: today.key, action: .snoozed, at: now, snoozedUntil: until, source: .notification),
        ]
        let statuses = EngineInputs.statuses(for: [taken, skipped, snoozed, silent], logs: logs, now: now, calendar: calendar)
        func state(_ s: Supplement) -> DoseState? {
            statuses.first { $0.planID == s.planID && $0.day == today }?.state
        }
        XCTAssertEqual(state(taken), .confirmed(at: now))
        XCTAssertEqual(state(skipped), .skipped(at: now))
        XCTAssertEqual(state(snoozed), .snoozed(until: until))
        XCTAssertNil(state(silent), "no response stays open, never missed")
    }

    func testUnmarkedTakenLogDoesNotCountAsConfirmed() {
        let s = Supplement(name: "Vitamin D")
        s.lastTakenAt = nil // un-marked on Home after tapping Taken in the notification
        let today = Day(now, calendar: calendar)
        let logs = [DoseLog(supplementID: s.planID, dayKey: today.key, action: .taken, at: now, source: .notification)]
        let statuses = EngineInputs.statuses(for: [s], logs: logs, now: now, calendar: calendar)
        XCTAssertTrue(statuses.isEmpty)
    }

    func testHistoryOnlyIncludesFiredDecisions() throws {
        let day = Day(now, calendar: calendar)
        func log(_ moment: Moment, _ offset: TimeInterval) -> DecisionLog {
            let d = ReminderDecision(id: ReminderID.make(day: day, moment: moment, stage: .initial),
                                     groupID: ReminderID.group(day: day, moment: moment), day: day, moment: moment,
                                     planIDs: ["a"], fireDate: now.addingTimeInterval(offset), stage: .initial,
                                     reason: Reason(trigger: .usualTime, ruleID: "timing.usual.v1"))
            return DecisionLog(decision: d, title: "t", reasonText: "r", supplementNames: ["A"])
        }
        let history = EngineInputs.history(from: [log(.breakfast, -600), log(.lunch, 3600)], now: now)
        XCTAssertEqual(history.map(\.moment), [.breakfast])
    }
    func testPreviousDayActionsDoNotConfirmToday() {
        let s = Supplement(name: "Magnesium")
        let today = Day(now, calendar: calendar)
        let yesterday = today.adding(days: -1, calendar: calendar)
        let taken = DoseLog(supplementID: s.planID, dayKey: yesterday.key,
                            action: .taken, at: now, source: .notification)
        let statuses = EngineInputs.statuses(for: [s], logs: [taken], now: now, calendar: calendar)
        XCTAssertEqual(statuses.first { $0.day == yesterday }?.state, .confirmed(at: now))
        XCTAssertNil(statuses.first { $0.day == today })
    }

    func testPreviousDaySkipAndSnoozeAreAvailableToReplanning() {
        let s = Supplement(name: "Magnesium")
        let yesterday = Day(now, calendar: calendar).adding(days: -1, calendar: calendar)
        let until = now.addingTimeInterval(1800)
        let snooze = DoseLog(supplementID: s.planID, dayKey: yesterday.key, action: .snoozed,
                             at: now, snoozedUntil: until, source: .notification)
        let skipped = DoseLog(supplementID: s.planID, dayKey: yesterday.key, action: .skipped,
                              at: now.addingTimeInterval(1), source: .notification)
        let snoozed = EngineInputs.statuses(for: [s], logs: [snooze], now: now, calendar: calendar)
        XCTAssertEqual(snoozed.first { $0.day == yesterday }?.state, .snoozed(until: until))
        let done = EngineInputs.statuses(for: [s], logs: [snooze, skipped], now: now, calendar: calendar)
        XCTAssertEqual(done.first { $0.day == yesterday }?.state, .skipped(at: skipped.at))
    }

    private func privateRequest(planIDs: [String] = ["a"], dayOffset: Int = 0,
                                minuteOffset: Int = 0) -> UNNotificationRequest {
        let day = Day(now, calendar: calendar).adding(days: dayOffset, calendar: calendar)
        let decision = ReminderDecision(id: ReminderID.make(day: day, moment: .breakfast, stage: .initial),
            groupID: ReminderID.group(day: day, moment: .breakfast), day: day, moment: .breakfast,
            planIDs: planIDs, fireDate: now.addingTimeInterval(Double(minuteOffset * 60)), stage: .initial,
            reason: Reason(trigger: .usualTime, ruleID: "timing.usual.v1"))
        let text = ReminderCopy.notification(for: decision, plans: [], privacyMode: true,
                                             calendar: calendar, locale: Locale(identifier: "en_US"))
        return NotificationScheduler.makeRequest(for: decision, text: text, calendar: calendar)
    }

    func testPrivateReminderReplacesChangedDoseTargets() {
        let original = privateRequest()
        XCTAssertTrue(NotificationScheduler.isSame(original, as: privateRequest()))
        for ids in [["a", "b"], ["b"], []] {
            let changed = privateRequest(planIDs: ids)
            XCTAssertEqual(original.content.body, changed.content.body)
            XCTAssertFalse(NotificationScheduler.isSame(original, as: changed), "actions must use the current plan set")
        }
    }

    func testReminderIdentityChecksDayTimeCategoryAndGroup() {
        let original = privateRequest()
        XCTAssertFalse(NotificationScheduler.isSame(original, as: privateRequest(dayOffset: 1)))
        XCTAssertFalse(NotificationScheduler.isSame(original, as: privateRequest(minuteOffset: 1)))
        let content = original.content.mutableCopy() as! UNMutableNotificationContent
        content.categoryIdentifier = Reminders.followUpCategory
        let followUp = UNNotificationRequest(identifier: original.identifier, content: content, trigger: original.trigger)
        XCTAssertFalse(NotificationScheduler.isSame(original, as: followUp))
        content.categoryIdentifier = original.content.categoryIdentifier
        content.threadIdentifier = "another-group"
        let regrouped = UNNotificationRequest(identifier: original.identifier, content: content, trigger: original.trigger)
        XCTAssertFalse(NotificationScheduler.isSame(original, as: regrouped))
    }

    func testReusedPrivateRequestKeepsAnUpdatedExplanation() {
        let day = Day(now, calendar: calendar)
        var decision = ReminderDecision(id: ReminderID.make(day: day, moment: .breakfast, stage: .initial),
            groupID: ReminderID.group(day: day, moment: .breakfast), day: day, moment: .breakfast,
            planIDs: ["a"], fireDate: now, stage: .initial,
            reason: Reason(trigger: .usualTime, ruleID: "timing.usual.v1"))
        let log = DecisionLog(decision: decision, title: "Private", reasonText: "Before", supplementNames: ["Old name"])
        decision.planIDs = ["b"]
        log.update(decision: decision, title: "Private", reasonText: "After", supplementNames: ["New name"])
        XCTAssertEqual(log.decision?.planIDs, ["b"])
        XCTAssertEqual(log.reasonText, "After")
        XCTAssertEqual(log.supplementNames, "New name")
    }

}
