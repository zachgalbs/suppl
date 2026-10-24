import XCTest
import SupplCore
@testable import suppl

/// The testing switch: smart timing free for everyone, while Pro keeps WHOOP, Extra Help, and history.
@MainActor
final class FeaturesTests: XCTestCase {
    private let off = Features(isPro: false, smartTimingFree: false)
    private let on = Features(isPro: false, smartTimingFree: true)
    private let pro = Features(isPro: true, smartTimingFree: false)

    private func defaults() -> UserDefaults {
        let name = "FeaturesTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        d.set(Intensity.extraHelp.rawValue, forKey: PrefKey.intensity)
        return d
    }

    func testSwitchIsABooleanInfoKeyAndIsWhatTheAppReads() {
        let value = Bundle.main.object(forInfoDictionaryKey: Features.infoKey) as? Bool
        XCTAssertNotNil(value, "set SupplSmartTimingFree to true or false in project.yml")
        XCTAssertEqual(Features.smartTimingFreeInBuild, value)
    }

    func testSwitchOffKeepsTodaysProGatingExactly() {
        XCTAssertFalse(off.smartTiming)
        XCTAssertFalse(off.extraHelp)
        XCTAssertFalse(off.reminderHistory)
        XCTAssertTrue(off.timingSources([.appleHealth, .calendar, .whoop]).isEmpty)
        let prefs = Preferences.current(off, connectedSources: [.appleHealth, .calendar], defaults: defaults())
        XCTAssertFalse(prefs.contextAware)
        XCTAssertTrue(prefs.connectedSources.isEmpty)
        XCTAssertEqual(prefs.intensity, .balanced)
        let signal = ContextSignal(kind: .wokeUp(at: .now), source: .appleHealth, observedAt: .now)
        XCTAssertTrue(off.timingSignals([signal], connected: [.appleHealth]).isEmpty)
    }

    func testSwitchOnFreesSmartTimingButNotProFeatures() {
        XCTAssertTrue(on.smartTiming)
        XCTAssertFalse(on.extraHelp, "Extra Help stays Pro")
        XCTAssertFalse(on.reminderHistory, "Recent reminders stays Pro")
        XCTAssertEqual(on.timingSources([.appleHealth, .calendar, .whoop]), [.appleHealth, .calendar], "WHOOP stays Pro")
        let prefs = Preferences.current(on, connectedSources: [.appleHealth, .calendar, .whoop], defaults: defaults())
        XCTAssertTrue(prefs.contextAware)
        XCTAssertEqual(prefs.connectedSources, [.appleHealth, .calendar])
        XCTAssertEqual(prefs.intensity, .balanced)
        let health = ContextSignal(kind: .wokeUp(at: .now), source: .appleHealth, observedAt: .now)
        let whoop = ContextSignal(kind: .wokeUp(at: .now), source: .whoop, observedAt: .now)
        XCTAssertEqual(on.timingSignals([health, whoop], connected: [.appleHealth, .whoop]), [health])
    }

    func testProUnlocksEverythingEitherWay() {
        for features in [pro, Features(isPro: true, smartTimingFree: true)] {
            XCTAssertTrue(features.smartTiming)
            XCTAssertTrue(features.extraHelp)
            XCTAssertTrue(features.reminderHistory)
            XCTAssertEqual(features.timingSources([.appleHealth, .whoop]), [.appleHealth, .whoop])
            let prefs = Preferences.current(features, connectedSources: [.whoop], defaults: defaults())
            XCTAssertEqual(prefs.intensity, .extraHelp)
            XCTAssertEqual(prefs.connectedSources, [.whoop])
        }
    }

    func testDisconnectedSourcesNeverTimeReminders() {
        let calendar = ContextSignal(kind: .busy([]), source: .calendar, observedAt: .now)
        XCTAssertTrue(pro.timingSignals([calendar], connected: [.appleHealth]).isEmpty)
    }
}
