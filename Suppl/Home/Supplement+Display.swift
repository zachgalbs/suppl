import Foundation

extension Supplement {
    /// "Every day" or "Mon, Wed, Fri", in the order of the user's week.
    var frequencyText: String {
        if takesEveryDay { return "Every day" }
        let calendar = Calendar.current
        let symbols = calendar.shortWeekdaySymbols
        return Weekdays.ordered(calendar)
            .filter { weekdays.contains($0) }
            .map { symbols[$0 - 1] }
            .joined(separator: ", ")
    }
}

enum Weekdays {
    /// `Calendar` weekdays (1 = Sunday) starting from the user's first weekday.
    static func ordered(_ calendar: Calendar) -> [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }
}

/// "7:30 AM" for a minutes-after-midnight value.
func timeText(_ minutes: Int) -> String {
    let date = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
    return date.formatted(date: .omitted, time: .shortened)
}
