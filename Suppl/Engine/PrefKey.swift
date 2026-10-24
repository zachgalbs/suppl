import Foundation

/// `@AppStorage` keys added for v1. The original keys (`name`, `onboarded`, `time.<slot>`) stay where they are.
enum PrefKey {
    /// `Intensity` raw value. Defaults to balanced.
    static let intensity = "reminders.intensity"
    /// Minutes after midnight, or -1 for automatic (end of bedtime window to wake).
    static let quietStart = "reminders.quietStart"
    static let quietEnd = "reminders.quietEnd"
    /// Generic lock-screen text.
    static let privacyMode = "reminders.privacy"
    static let birthYear = "profile.birthYear"
    /// Defaults to true: anyone who onboarded before v1 confirmed they were 18 or older.
    static let isAdult = "profile.isAdult"
    /// "daily", "occasionally", or "notYet".
    static let takesSupplements = "profile.takesSupplements"
}
