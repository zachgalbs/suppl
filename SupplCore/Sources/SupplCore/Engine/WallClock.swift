import Foundation

/// Wall-clock math. Usual times are "8:00 on the kitchen clock", not "480 minutes after midnight",
/// so on DST days they must be resolved through the calendar rather than by adding seconds.
enum WallClock {
    /// `minutes` after midnight on `day`. A time skipped by spring-forward resolves to the next valid
    /// time (2:30 becomes 3:00); a time repeated by fall-back resolves to its first occurrence.
    static func date(_ day: Day, minutes: Int, calendar: Calendar) -> Date {
        let m = ((minutes % 1440) + 1440) % 1440
        let start = day.start(in: calendar)
        return calendar.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: start,
                             matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
            ?? start.addingTimeInterval(TimeInterval(m * 60))
    }

    static func minuteOfDay(_ date: Date, calendar: Calendar) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

extension Preferences {
    /// `prefs.quietHours`, or the default: from the end of the bedtime window to the start of the wake window.
    /// Starting after the bedtime window is what keeps the bedtime reminder itself out of quiet hours.
    public var effectiveQuietHours: QuietHours {
        if let quietHours { return quietHours }
        let start = usualMinutes(for: .bedtime) + window(for: .bedtime).after
        let end = usualMinutes(for: .wake) - window(for: .wake).before
        return QuietHours(start: ((start % 1440) + 1440) % 1440, end: ((end % 1440) + 1440) % 1440)
    }
}

extension QuietHours {
    /// Equal start and end means no quiet hours at all, not 24 of them.
    func contains(minute m: Int) -> Bool {
        if start == end { return false }
        if start < end { return m >= start && m < end }
        return m >= start || m < end
    }

    func contains(_ date: Date, calendar: Calendar) -> Bool {
        contains(minute: WallClock.minuteOfDay(date, calendar: calendar))
    }

    /// When the quiet stretch containing `date` ends. Only meaningful if `contains(date)`.
    func end(after date: Date, calendar: Calendar) -> Date {
        let day = Day(date, calendar: calendar)
        let spansMidnight = start > end
        let endDay = spansMidnight && WallClock.minuteOfDay(date, calendar: calendar) >= start
            ? day.adding(days: 1, calendar: calendar) : day
        return WallClock.date(endDay, minutes: end, calendar: calendar)
    }
}
