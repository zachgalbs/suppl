import Foundation

/// The signals the engine is allowed to act on, already filtered for freshness and deduplicated.
struct SignalContext {
    struct Workout: Equatable {
        var start: Date
        var end: Date
        var source: SignalSource
    }

    struct Wake: Equatable {
        var at: Date
        var source: SignalSource
        var observedAt: Date
    }

    /// One entry per real workout, after merging reports of the same one from several sources.
    let workouts: [Workout]
    let wakes: [Wake]
    /// Fresh busy intervals, merged and sorted.
    let busy: [DateInterval]
    let freshness: FreshnessPolicy
    let now: Date
    let calendar: Calendar

    /// Two reports ending this close together are the same workout seen by two apps.
    static let sameWorkoutTolerance: TimeInterval = 10 * 60

    init(signals: [ContextSignal], freshness: FreshnessPolicy, now: Date, calendar: Calendar) {
        self.freshness = freshness
        self.now = now
        self.calendar = calendar

        var rawWorkouts: [Workout] = []
        var wakes: [Wake] = []
        var intervals: [DateInterval] = []
        for signal in signals {
            switch signal.kind {
            case let .workoutEnded(start, end):
                // A workout that hasn't ended yet (or bad data) can't have "just finished".
                guard start <= end, end <= now else { continue }
                rawWorkouts.append(Workout(start: start, end: end, source: signal.source))
            case let .wokeUp(at):
                guard at <= now, signal.observedAt <= now,
                      now.timeIntervalSince(signal.observedAt) <= TimeInterval(freshness.wakeMinutes * 60)
                else { continue }
                wakes.append(Wake(at: at, source: signal.source, observedAt: signal.observedAt))
            case let .busy(list):
                guard signal.observedAt <= now,
                      now.timeIntervalSince(signal.observedAt) <= TimeInterval(freshness.busyMinutes * 60)
                else { continue }
                intervals += list.filter { $0.duration > 0 }
            }
        }
        self.workouts = Self.dedupe(rawWorkouts)
        self.wakes = wakes
        self.busy = Self.merge(intervals)
    }

    /// Groups overlapping reports (or ones ending within 10 minutes of each other) and keeps the
    /// earliest-ending report of each group, so a second app syncing later doesn't push the reminder back.
    static func dedupe(_ workouts: [Workout]) -> [Workout] {
        let order = SignalSource.allCases
        let sorted = workouts.sorted {
            ($0.end, $0.start, order.firstIndex(of: $0.source) ?? 0)
                < ($1.end, $1.start, order.firstIndex(of: $1.source) ?? 0)
        }
        var result: [Workout] = []
        var latestEnd: Date?
        for w in sorted {
            if let last = latestEnd, w.start <= last || w.end.timeIntervalSince(last) <= sameWorkoutTolerance {
                latestEnd = max(last, w.end)
                continue
            }
            result.append(w)
            latestEnd = w.end
        }
        return result
    }

    static func merge(_ intervals: [DateInterval]) -> [DateInterval] {
        var result: [DateInterval] = []
        for i in intervals.sorted(by: { ($0.start, $0.end) < ($1.start, $1.end) }) {
            if let last = result.last, i.start <= last.end {
                result[result.count - 1] = DateInterval(start: last.start, end: max(last.end, i.end))
            } else {
                result.append(i)
            }
        }
        return result
    }

    /// The latest workout on `day` that ended recently enough to call it "just finished".
    func freshWorkout(on day: Day) -> Workout? {
        workouts.last {
            Day($0.end, calendar: calendar) == day
                && now.timeIntervalSince($0.end) <= TimeInterval(freshness.workoutMinutes * 60)
        }
    }

    /// Any workout on `day`, fresh or not. Used only to avoid claiming "no workout recorded" when one was.
    func anyWorkout(on day: Day) -> Bool {
        workouts.contains { Day($0.end, calendar: calendar) == day }
    }

    /// The newest wake report for `day`. Ties go to the earlier wake time, which moves reminders less.
    func wake(on day: Day) -> Wake? {
        wakes.filter { Day($0.at, calendar: calendar) == day }
            .min { ($1.observedAt, $0.at) < ($0.observedAt, $1.at) }
    }

    /// Start of the earliest free stretch of at least `minimumGap` inside `window`, if `date` is busy.
    /// Starts no sooner than a minute from now so the moved reminder isn't already in the past.
    func freeGap(moving date: Date, within window: DateInterval, minimumGap: TimeInterval) -> Date? {
        guard busy.contains(where: { $0.start <= date && date < $0.end }) else { return nil }
        var cursor = max(window.start, now.addingTimeInterval(ReminderEngine.minimumLead))
        for interval in busy where interval.end > cursor {
            guard cursor < window.end else { return nil }
            if interval.start > cursor, min(interval.start, window.end).timeIntervalSince(cursor) >= minimumGap {
                return cursor
            }
            cursor = max(cursor, interval.end)
        }
        return window.end.timeIntervalSince(cursor) >= minimumGap ? cursor : nil
    }
}
