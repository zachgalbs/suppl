import Foundation

/// Notification and "Why now?" text. Calm and plain: no diagnosis, no dose advice, never "missed".
/// Times are formatted in the passed calendar's zone so copy matches the fire time the user sees.
public enum ReminderCopy {
    public static let privateTitle = "suppl."
    public static let privateBody = "suppl. has a reminder for you."
    /// Sent before the pending queue runs out. Names no supplement, so it's the same with lock-screen privacy on.
    public static let headsUp = NotificationText(title: "suppl.", body: "Open suppl. to keep your reminders coming.")

    public static func momentTitle(_ moment: Moment) -> String {
        switch moment {
        case .wake: "On waking"
        case .breakfast: "Breakfast time"
        case .lunch: "Lunch time"
        case .dinner: "Dinner time"
        case .bedtime: "Before bed"
        case .postWorkout: "After your workout"
        }
    }

    public static func notification(for decision: ReminderDecision, plans: [DosePlan],
                                    privacyMode: Bool, calendar: Calendar, locale: Locale) -> NotificationText {
        // Lock-screen privacy hides everything, reasons included: "after your workout" is health data too.
        if privacyMode { return NotificationText(title: privateTitle, body: privateBody) }

        let byID = Dictionary(plans.map { ($0.id, $0) }) { first, _ in first }
        let items = decision.planIDs.compactMap { byID[$0] }
        let list = items.isEmpty ? "your supplements" : joined(items.map(label))
        let reason = decision.reason
        let time = { (date: Date) in format(date, calendar: calendar, locale: locale) }

        var sentence: String
        switch decision.stage {
        case .followUp:
            sentence = "Still open: \(list). No rush, take it when it suits you."
        case .snoozed:
            sentence = "Here's the reminder you snoozed: \(list)."
        case .initial:
            switch reason.trigger {
            case .workoutEnded:
                let when = reason.dataTimestamp.map { " ending at \(time($0))" } ?? ""
                sentence = "\(sourceName(reason.source)) recorded a workout\(when). Time for \(list)."
            case .workoutFallback:
                // Planned hours earlier, so it makes no claim about today: a workout may have happened since.
                sentence = "Here's your usual after-workout reminder for \(list)."
            case .lateWake:
                let woke = reason.dataTimestamp.map { " at \(time($0))" } ?? " later than usual"
                sentence = "\(sourceName(reason.source)) shows you woke\(woke), so this moved to \(time(decision.fireDate)). Time for \(list)."
            case .calendarGap:
                // A free slot is not a meal, so the wording stays conditional.
                sentence = decision.moment.isMeal
                    ? "You have a free moment. If you're eating, it's a good time for \(list)."
                    : "You have a free moment, so it's a good time for \(list)."
            case .quietHours:
                sentence = "Your quiet hours have ended. Time for \(list)."
            case .usualTime, .snoozed, .followUp:
                sentence = "Your usual time for \(list)."
            }
        }
        if items.contains(where: \.withFood) { sentence += " Take with food." }
        return NotificationText(title: momentTitle(decision.moment), body: sentence)
    }

    /// Full "Why now?" sentence(s) for the sheet in the app.
    public static func whyNow(_ reason: Reason, moment: Moment, calendar: Calendar, locale: Locale) -> String {
        let time = { (date: Date) in format(date, calendar: calendar, locale: locale) }
        let noun = momentNoun(moment)
        switch reason.trigger {
        case .usualTime:
            if let usual = reason.usualDate {
                return "This came at \(time(usual)), the usual \(noun) time you set."
            }
            return "This came at the usual \(noun) time you set."
        case .workoutEnded:
            let when = reason.dataTimestamp.map { " ending at \(time($0))" } ?? ""
            return "\(sourceName(reason.source)) recorded a workout\(when). You take these after a workout, "
                + "so this reminder was timed from that."
        case .workoutFallback:
            let at = reason.usualDate.map { " (\(time($0)))" } ?? ""
            return "This came at your usual after-workout time\(at). When it was planned, your connected "
                + "apps hadn't recorded a workout today."
        case .lateWake:
            let woke = reason.dataTimestamp.map { " at \(time($0))" } ?? ""
            let from = reason.usualDate.map { " from \(time($0))" } ?? ""
            return "\(sourceName(reason.source)) shows you woke up\(woke), later than usual. "
                + "This reminder moved\(from) by the same amount and stays inside your \(noun) window."
        case .calendarGap:
            let at = reason.usualDate.map { " at \(time($0))" } ?? " at the usual time"
            return "Your calendar showed you as busy\(at), so this moved to a free moment in your \(noun) window. "
                + "suppl. reads only busy times, never event details."
        case .snoozed:
            if let until = reason.dataTimestamp {
                return "You snoozed this reminder until \(time(until))."
            }
            return "You snoozed this reminder."
        case .followUp:
            let from = reason.dataTimestamp.map { " from \(time($0))" } ?? ""
            return "The reminder\(from) hasn't been marked yet, so this is a gentle follow-up. "
                + "You can choose fewer follow-ups in Reminder style."
        case .quietHours:
            if let planned = reason.usualDate {
                return "\(time(planned)) falls in your quiet hours, so this waited until they ended."
            }
            return "This would have come during your quiet hours, so it waited until they ended."
        }
    }

    // MARK: - Pieces

    static func label(_ plan: DosePlan) -> String {
        let dose = plan.doseText.trimmingCharacters(in: .whitespaces)
        return dose.isEmpty ? plan.name : "\(plan.name) (\(dose))"
    }

    /// "A", "A and B", "A, B, and C". Hand-rolled because `ListFormatter` isn't on every Foundation.
    static func joined(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + ", and " + items[items.count - 1]
        }
    }

    static func sourceName(_ source: SignalSource?) -> String {
        guard let name = source?.displayName else { return "Your connected app" }
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    static func momentNoun(_ moment: Moment) -> String {
        switch moment {
        case .wake: "wake-up"
        case .breakfast: "breakfast"
        case .lunch: "lunch"
        case .dinner: "dinner"
        case .bedtime: "bedtime"
        case .postWorkout: "after-workout"
        }
    }

    static func format(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private extension Moment {
    var isMeal: Bool { self == .breakfast || self == .lunch || self == .dinner }
}
