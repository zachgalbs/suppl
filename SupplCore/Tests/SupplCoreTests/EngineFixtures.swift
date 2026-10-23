import XCTest
@testable import SupplCore

/// Fixed clock and calendar for engine and copy tests. Nothing here reads the real clock.
/// Namespaced so helpers can't collide with other test files in the module.
enum EngineFixtures {
    static func calendar(_ zone: String = "America/New_York") -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: zone)!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }

    static let ny = calendar()
    static let la = calendar("America/Los_Angeles")
    static let locale = Locale(identifier: "en_US")

    /// 2026-10-23 is a Friday (weekday 6).
    static let today = Day(year: 2026, month: 10, day: 23)
    static let tomorrow = Day(year: 2026, month: 10, day: 24)

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int,
                     _ second: Int = 0, in cal: Calendar = ny) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    /// A time on 2026-10-23 (or another October day) in New York.
    static func at(_ hour: Int, _ minute: Int, _ second: Int = 0, day: Int = 23) -> Date {
        date(2026, 10, day, hour, minute, second)
    }

    static func plan(_ id: String, _ moment: Moment, name: String? = nil, dose: String = "1 capsule",
                     withFood: Bool = false, frequency: Frequency = .daily, clinician: Bool = false,
                     catalogID: String? = nil) -> DosePlan {
        DosePlan(id: id, name: name ?? id, doseText: dose, moment: moment, withFood: withFood,
                 frequency: frequency, clinicianDirected: clinician, catalogID: catalogID)
    }

    static func prefs(intensity: Intensity = .balanced, contextAware: Bool = false,
                      sources: Set<SignalSource> = [], quiet: QuietHours? = nil,
                      edit: (inout Preferences) -> Void = { _ in }) -> Preferences {
        var p = Preferences(intensity: intensity, quietHours: quiet, contextAware: contextAware,
                            connectedSources: sources)
        edit(&p)
        return p
    }

    /// Pro user with Apple Health and Calendar connected.
    static func pro(intensity: Intensity = .gentle, quiet: QuietHours? = nil,
                    edit: (inout Preferences) -> Void = { _ in }) -> Preferences {
        prefs(intensity: intensity, contextAware: true, sources: [.appleHealth, .calendar], quiet: quiet, edit: edit)
    }

    static func workout(_ start: Date, _ end: Date, _ source: SignalSource = .appleHealth,
                        observed: Date? = nil) -> ContextSignal {
        ContextSignal(kind: .workoutEnded(start: start, end: end), source: source, observedAt: observed ?? end)
    }

    static func wake(_ at: Date, _ source: SignalSource = .appleHealth, observed: Date? = nil) -> ContextSignal {
        ContextSignal(kind: .wokeUp(at: at), source: source, observedAt: observed ?? at)
    }

    static func busy(_ intervals: [(Date, Date)], observed: Date) -> ContextSignal {
        ContextSignal(kind: .busy(intervals.map { DateInterval(start: $0.0, end: $0.1) }),
                      source: .calendar, observedAt: observed)
    }

    static func run(_ plans: [DosePlan], statuses: [DoseStatus] = [], signals: [ContextSignal] = [],
                    history: [ReminderDecision] = [], prefs: Preferences = prefs(), now: Date,
                    calendar: Calendar = ny) -> [ReminderDecision] {
        ReminderEngine.plan(plans: plans, statuses: statuses, signals: signals, history: history,
                            prefs: prefs, now: now, calendar: calendar)
    }

    static func id(_ day: Day, _ moment: Moment, _ stage: ReminderStage = .initial) -> String {
        ReminderID.make(day: day, moment: moment, stage: stage)
    }

    /// Copy tests compare against plain spaces; ICU puts narrow no-break spaces before AM/PM.
    static func normalized(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
    }
}

extension Array where Element == ReminderDecision {
    func decision(_ id: String) -> ReminderDecision? { first { $0.id == id } }
    var reminderIDs: [String] { map(\.id) }
}
