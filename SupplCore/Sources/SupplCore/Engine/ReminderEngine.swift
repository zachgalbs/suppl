import Foundation

/// Decides which reminders should be pending. Pure: the same inputs always give the same output,
/// so the scheduler can re-run it whenever anything changes and diff pending requests by id.
public enum ReminderEngine {
    /// iOS keeps 64 pending requests per app. Staying at 48 leaves room for the test reminder and old builds' ids.
    public static let maxDecisions = 48
    /// Reminders computed "for right now" fire at least this far out, so they're never already in the past.
    static let minimumLead: TimeInterval = 60
    /// Health data often lands a moment after the workout ends; wait a little before nudging.
    static let workoutSettle: TimeInterval = 2 * 60

    /// Stable ids of the timing rules, stored with each delivered reminder.
    public enum RuleID {
        public static let usual = "timing.usual.v1"
        public static let workout = "timing.workout.v1"
        public static let workoutFallback = "timing.workoutFallback.v1"
        public static let lateWake = "timing.lateWake.v1"
        public static let calendarGap = "timing.calendarGap.v1"
        public static let snooze = "timing.snooze.v1"
        public static let followUp = "timing.followUp.v1"
        public static let quietHours = "timing.quietHours.v1"
    }

    /// Reminders that should be pending right now, for today and tomorrow (relative to `now` in `calendar`),
    /// soonest first, at most 48. `history` holds decisions already delivered, so nothing fires twice.
    public static func plan(plans: [DosePlan], statuses: [DoseStatus], signals: [ContextSignal],
                            history: [ReminderDecision], prefs: Preferences,
                            now: Date, calendar: Calendar) -> [ReminderDecision] {
        // Context-aware timing is Pro. Without it, signals are ignored entirely and every reminder is a usual-time one.
        let context = SignalContext(signals: prefs.contextAware ? signals : [], freshness: prefs.freshness,
                                    now: now, calendar: calendar)
        let planner = Planner(prefs: prefs, now: now, calendar: calendar, context: context,
                              delivered: Dictionary(history.map { ($0.id, $0) }) { $0.fireDate <= $1.fireDate ? $0 : $1 })

        var states: [String: [Day: DoseState]] = [:]
        for status in statuses { states[status.planID, default: [:]][status.day] = status.state }

        // Input order is kept within a group (the app passes its list order), duplicates dropped.
        var seen = Set<String>()
        let unique = plans.filter { seen.insert($0.id).inserted }

        let today = Day(now, calendar: calendar)
        var decisions: [ReminderDecision] = []
        for day in [today, today.adding(days: 1, calendar: calendar)] {
            for moment in Moment.allCases {
                let open = unique.filter { plan in
                    guard plan.moment == moment, isDue(plan, on: day, calendar: calendar) else { return false }
                    switch states[plan.id]?[day] {
                    case .confirmed, .skipped: return false
                    default: return true
                    }
                }
                guard !open.isEmpty else { continue }
                let snoozes = open.compactMap { plan -> Date? in
                    if case let .snoozed(until) = states[plan.id]?[day] { return until }
                    return nil
                }
                decisions += planner.decisions(day: day, moment: moment, plans: open, snoozedUntil: snoozes.max())
            }
        }
        return capped(decisions)
    }

    /// Soonest first, ties by id, then the cap. Six moments over two days can't reach 48 today,
    /// but the cap guards against future moments or more follow-ups blowing the iOS limit.
    static func capped(_ decisions: [ReminderDecision]) -> [ReminderDecision] {
        Array(decisions.sorted { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }.prefix(maxDecisions))
    }

    static func isDue(_ plan: DosePlan, on day: Day, calendar: Calendar) -> Bool {
        switch plan.frequency {
        case .daily: true
        case let .weekdays(days): days.contains(day.weekday(in: calendar))
        }
    }
}

/// One planning pass. Holds the inputs shared by every (day, moment) group.
private struct Planner {
    let prefs: Preferences
    let now: Date
    let calendar: Calendar
    let context: SignalContext
    let delivered: [String: ReminderDecision]
    typealias RuleID = ReminderEngine.RuleID

    var quiet: QuietHours { prefs.effectiveQuietHours }

    func decisions(day: Day, moment: Moment, plans: [DosePlan], snoozedUntil: Date?) -> [ReminderDecision] {
        let planIDs = plans.map(\.id)
        let usual = WallClock.date(day, minutes: prefs.usualMinutes(for: moment), calendar: calendar)
        let w = prefs.window(for: moment)
        let window = DateInterval(start: usual.addingTimeInterval(TimeInterval(-w.before * 60)),
                                  end: usual.addingTimeInterval(TimeInterval(w.after * 60)))

        func decision(_ stage: ReminderStage, _ fire: Date, _ reason: Reason) -> ReminderDecision {
            ReminderDecision(id: ReminderID.make(day: day, moment: moment, stage: stage),
                             groupID: ReminderID.group(day: day, moment: moment), day: day, moment: moment,
                             planIDs: planIDs, fireDate: fire, stage: stage, reason: reason)
        }

        // A snooze replaces the rest of the group. It may run past the window (the user asked for it),
        // but it still honours quiet hours.
        if let until = snoozedUntil {
            guard until > now else { return [] }
            let reason = Reason(trigger: .snoozed, dataTimestamp: until, ruleID: RuleID.snooze)
            guard let moved = quietAdjusted(until, reason, window: window, exempt: false) else { return [] }
            return [decision(.snoozed, moved.fire, moved.reason)]
        }

        var result: [ReminderDecision] = []
        let anchor: ReminderDecision
        let followUpEnd: Date
        let initialID = ReminderID.make(day: day, moment: moment, stage: .initial)
        if let past = delivered[initialID] {
            // Already delivered: never re-send it, even if a late signal would now pick a different time.
            anchor = past
            if moment == .postWorkout, past.reason.trigger == .workoutEnded || past.reason.trigger == .quietHours,
               let end = past.reason.dataTimestamp {
                followUpEnd = end.addingTimeInterval(TimeInterval(w.after * 60))
            } else {
                followUpEnd = window.end
            }
        } else {
            guard let first = initial(day: day, moment: moment, plans: plans, usual: usual, window: window)
            else { return [] }
            anchor = decision(.initial, first.fire, first.reason)
            followUpEnd = first.windowEnd
            if first.fire > now { result.append(anchor) }
        }

        // Follow-ups hang off the initial's actual fire time. If the initial is in the past but wasn't
        // reported delivered, it was still scheduled, so its follow-ups stay.
        let delay = TimeInterval(prefs.followUpDelayMinutes * 60)
        let count = delay > 0 ? prefs.intensity.maxFollowUps : 0
        for n in stride(from: 1, through: count, by: 1) {
            let fire = anchor.fireDate.addingTimeInterval(delay * Double(n))
            guard fire <= followUpEnd else { break }
            let id = ReminderID.make(day: day, moment: moment, stage: .followUp(n))
            guard fire > now, delivered[id] == nil, !quiet.contains(fire, calendar: calendar) else { continue }
            result.append(decision(.followUp(n), fire, Reason(trigger: .followUp, dataTimestamp: anchor.fireDate,
                                                              ruleID: RuleID.followUp)))
        }
        return result
    }

    /// Fire time and reason for a group's first reminder, plus where its follow-ups must stop.
    /// `nil` when quiet hours leave no room inside the window.
    private func initial(day: Day, moment: Moment, plans: [DosePlan], usual: Date,
                         window: DateInterval) -> (fire: Date, reason: Reason, windowEnd: Date)? {
        var fire = usual
        var reason = Reason(trigger: .usualTime, usualDate: usual, ruleID: RuleID.usual)
        var window = window
        // Clinician-directed timing stays put, so the whole group stays put: one notification per moment.
        let movable = !plans.contains(where: \.clinicianDirected)

        if moment == .postWorkout {
            // A workout only re-times plans the user already marked post-workout. It never adds any.
            let after = TimeInterval(prefs.window(for: .postWorkout).after * 60)
            if let workout = context.freshWorkout(on: day),
               case let target = max(workout.end.addingTimeInterval(ReminderEngine.workoutSettle),
                                     now.addingTimeInterval(ReminderEngine.minimumLead)),
               target <= workout.end.addingTimeInterval(after) {
                fire = target
                window = DateInterval(start: workout.end, duration: after)
                reason = Reason(trigger: .workoutEnded, source: workout.source, dataTimestamp: workout.end,
                                usualDate: usual, ruleID: RuleID.workout)
            } else if prefs.contextAware, !prefs.connectedSources.isDisjoint(with: [.appleHealth, .whoop, .oura]),
                      !context.anyWorkout(on: day) {
                // Only say "no workout recorded" when something could have recorded one and nothing did.
                // A stale workout falls back with plain usual-time wording.
                reason = Reason(trigger: .workoutFallback, usualDate: usual, ruleID: RuleID.workoutFallback)
            }
        } else if movable {
            var searchWindow = window
            if moment == .wake || moment == .breakfast, let wake = context.wake(on: day) {
                let usualWake = WallClock.date(day, minutes: prefs.usualMinutes(for: .wake), calendar: calendar)
                if wake.at > usualWake {
                    let delta = wake.at.timeIntervalSince(usualWake)
                    // The shifted "on waking" time is the wake time itself, which is already past once we
                    // know about it, so it gets the same one-minute lead as a workout.
                    let shifted = max(usual.addingTimeInterval(delta), now.addingTimeInterval(ReminderEngine.minimumLead))
                    fire = min(shifted, window.end)
                    // A calendar move afterwards must not pull it back to before the user was up.
                    searchWindow = DateInterval(start: min(window.start.addingTimeInterval(delta), fire), end: window.end)
                    reason = Reason(trigger: .lateWake, source: wake.source, dataTimestamp: wake.at,
                                    usualDate: usual, ruleID: RuleID.lateWake)
                }
            }
            if let gap = context.freeGap(moving: fire, within: searchWindow,
                                         minimumGap: TimeInterval(prefs.minimumGapMinutes * 60)) {
                fire = gap
                reason = Reason(trigger: .calendarGap, source: .calendar, usualDate: usual, ruleID: RuleID.calendarGap)
            }
        }

        guard let moved = quietAdjusted(fire, reason, window: window,
                                        exempt: moment == .bedtime && quietStartsInBedtimeWindow)
        else { return nil }
        return (moved.fire, moved.reason, window.end)
    }

    /// Moves a reminder out of quiet hours to their end if that's still inside the window; otherwise drops it.
    private func quietAdjusted(_ fire: Date, _ reason: Reason, window: DateInterval,
                               exempt: Bool) -> (fire: Date, reason: Reason)? {
        guard !exempt, quiet.contains(fire, calendar: calendar) else { return (fire, reason) }
        let end = quiet.end(after: fire, calendar: calendar)
        guard end <= window.end else { return nil }
        // usualDate keeps the time it would have fired, so copy can say what it was moved from. Source and
        // timestamp carry over so a delivered post-workout reminder still knows its workout's window.
        return (end, Reason(trigger: .quietHours, source: reason.source, dataTimestamp: reason.dataTimestamp,
                            usualDate: fire, ruleID: RuleID.quietHours))
    }

    /// The bedtime reminder is the one quiet hours must never swallow when they begin during the bedtime window.
    private var quietStartsInBedtimeWindow: Bool {
        let w = prefs.window(for: .bedtime)
        var offset = (quiet.start - prefs.usualMinutes(for: .bedtime)) % 1440
        if offset > 720 { offset -= 1440 }
        if offset <= -720 { offset += 1440 }
        return offset >= -w.before && offset <= w.after
    }
}
