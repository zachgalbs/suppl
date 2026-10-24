import Foundation
import SwiftData
import SupplCore

// Maps what the app stores (SwiftData, UserDefaults) to the engine's plain value types.

extension Preferences {
    /// The user's saved preferences. Context-aware timing and Extra Help are Pro; without Pro the
    /// engine gets usual times only, which is exactly how reminders worked before v1.
    static func current(isPro: Bool, connectedSources: Set<SignalSource>,
                        defaults: UserDefaults = .standard) -> Preferences {
        var usual: [Moment: Int] = [:]
        for slot in Slot.allCases {
            if let moment = Moment(rawValue: slot.rawValue) {
                usual[moment] = (defaults.object(forKey: slot.storageKey) as? Int) ?? slot.defaultMinutes
            }
        }

        var intensity = Intensity(rawValue: defaults.string(forKey: PrefKey.intensity) ?? "") ?? .balanced
        if intensity == .extraHelp && !isPro { intensity = .balanced }

        let start = (defaults.object(forKey: PrefKey.quietStart) as? Int) ?? -1
        let end = (defaults.object(forKey: PrefKey.quietEnd) as? Int) ?? -1
        let quiet = (0..<1440).contains(start) && (0..<1440).contains(end) ? QuietHours(start: start, end: end) : nil

        return Preferences(
            usualTimes: usual,
            intensity: intensity,
            quietHours: quiet,
            privacyMode: defaults.bool(forKey: PrefKey.privacyMode),
            followUpDelayMinutes: Reminders.snoozeMinutes,
            contextAware: isPro,
            connectedSources: isPro ? connectedSources : []
        )
    }
}

enum EngineInputs {
    /// Per-plan state including yesterday’s reminders that can cross midnight. "Taken" follows `lastTakenAt` (which Home and the
    /// notification both set), so un-marking in the app always wins. Skip and snooze come from `DoseLog`.
    /// No log means no response: pending, never "missed".
    static func statuses(for supplements: [Supplement], logs: [DoseLog], now: Date, calendar: Calendar) -> [DoseStatus] {
        let today = Day(now, calendar: calendar)
        var result: [DoseStatus] = []
        for s in supplements {
            for offset in -1...1 {
                let day = today.adding(days: offset, calendar: calendar)
                if let taken = s.lastTakenAt, Day(taken, calendar: calendar) == day {
                    result.append(DoseStatus(planID: s.planID, day: day, state: .confirmed(at: taken)))
                    continue
                }
                // A notification acted on after midnight still confirms its original dose day.
                // Today's lastTakenAt remains authoritative so Home's undo keeps working.
                if day < today, let taken = logs.filter({
                    $0.supplementID == s.planID && $0.dayKey == day.key && $0.action == .taken
                }).max(by: { $0.at < $1.at }) {
                    result.append(DoseStatus(planID: s.planID, day: day, state: .confirmed(at: taken.at)))
                    continue
                }
                let latest = logs
                    .filter { $0.supplementID == s.planID && $0.dayKey == day.key && $0.action != .taken }
                    .max { $0.at < $1.at }
                switch latest?.action {
                case .skipped: result.append(DoseStatus(planID: s.planID, day: day, state: .skipped(at: latest!.at)))
                case .snoozed:
                    if let until = latest?.snoozedUntil {
                        result.append(DoseStatus(planID: s.planID, day: day, state: .snoozed(until: until)))
                    }
                default: break
                }
            }
        }
        return result
    }

    /// Accepted schedules whose fire date has passed. Used conservatively to prevent duplicate nudges,
    /// not as proof that iOS displayed them or that the user took a dose.
    static func history(from logs: [DecisionLog], now: Date) -> [ReminderDecision] {
        logs.filter { $0.fireDate <= now }.compactMap(\.decision)
    }
}
