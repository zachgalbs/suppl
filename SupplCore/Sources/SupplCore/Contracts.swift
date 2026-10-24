import Foundation

// Shared types for the app, the engine, the catalog, and the connectors.
// Everything here is plain data. Logic lives in Engine/, Catalog/, Rules/, and Copy/.
// Changing a type here touches every layer, so keep edits additive.

// MARK: - Moments and days

/// When a supplement is tied to. Raw values match the app's `Slot`, so stored data maps 1:1.
public enum Moment: String, CaseIterable, Codable, Sendable, Hashable {
    case wake, breakfast, lunch, dinner, bedtime, postWorkout
}

/// How far a reminder may move from the usual time, in minutes. A reminder never fires outside its window.
public struct MomentWindow: Codable, Sendable, Hashable {
    public var before: Int
    public var after: Int

    public init(before: Int, after: Int) {
        self.before = before
        self.after = after
    }

    public static func defaultWindow(for moment: Moment) -> MomentWindow {
        switch moment {
        case .wake: MomentWindow(before: 15, after: 120)
        case .breakfast, .lunch, .dinner: MomentWindow(before: 30, after: 90)
        case .bedtime: MomentWindow(before: 60, after: 30)
        // Post-workout is driven by the workout itself; this window applies to the fallback time.
        case .postWorkout: MomentWindow(before: 0, after: 120)
        }
    }
}

/// A calendar day in the user's current calendar and time zone.
public struct Day: Hashable, Codable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, calendar: Calendar) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 0, month: c.month ?? 0, day: c.day ?? 0)
    }

    /// Parses `key` back. `nil` for anything that isn't a real `yyyy-MM-dd` date.
    public init?(key: String) {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, key.count == 10, (1...12).contains(parts[1]), (1...31).contains(parts[2])
        else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    /// `yyyy-MM-dd`, used in notification identifiers.
    public var key: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var description: String { key }

    public func start(in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    public func adding(days: Int, calendar: Calendar) -> Day {
        let date = calendar.date(byAdding: .day, value: days, to: start(in: calendar)) ?? start(in: calendar)
        return Day(date, calendar: calendar)
    }

    /// `Calendar` weekday: 1 = Sunday … 7 = Saturday.
    public func weekday(in calendar: Calendar) -> Int {
        calendar.component(.weekday, from: start(in: calendar))
    }

    public static func < (lhs: Day, rhs: Day) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

// MARK: - Plans and statuses

public enum Frequency: Codable, Sendable, Hashable {
    case daily
    /// `Calendar` weekdays, 1 = Sunday … 7 = Saturday.
    case weekdays(Set<Int>)
}

/// One supplement the user takes, as the engine sees it.
public struct DosePlan: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    /// Already formatted, e.g. "2 capsules". Only the user's saved dose; the engine never changes it.
    public var doseText: String
    public var moment: Moment
    public var withFood: Bool
    public var frequency: Frequency
    /// Clinician-directed plans are never moved by context signals.
    public var clinicianDirected: Bool
    public var catalogID: String?
    /// Existing app creation timestamp; a routine never owes doses from before it was added.
    public var startDate: Date?

    public init(id: String, name: String, doseText: String, moment: Moment, withFood: Bool,
                frequency: Frequency = .daily, clinicianDirected: Bool = false, catalogID: String? = nil,
                startDate: Date? = nil) {
        self.id = id
        self.name = name
        self.doseText = doseText
        self.moment = moment
        self.withFood = withFood
        self.frequency = frequency
        self.clinicianDirected = clinicianDirected
        self.catalogID = catalogID
        self.startDate = startDate
    }
}

public enum DoseState: Codable, Sendable, Hashable {
    case pending
    case confirmed(at: Date)
    case skipped(at: Date)
    case snoozed(until: Date)
    /// No response. Never treated as taken or missed.
    case unconfirmed
}

public struct DoseStatus: Codable, Sendable, Hashable {
    public var planID: String
    public var day: Day
    public var state: DoseState

    public init(planID: String, day: Day, state: DoseState) {
        self.planID = planID
        self.day = day
        self.state = state
    }
}

// MARK: - Context signals

public enum SignalSource: String, Codable, Sendable, Hashable, CaseIterable {
    case appleHealth, calendar, whoop, oura

    public var displayName: String {
        switch self {
        case .appleHealth: "Apple Health"
        case .calendar: "your calendar"
        case .whoop: "WHOOP"
        case .oura: "Oura"
        }
    }
}

/// Something a connector observed. `observedAt` is when the app learned it, which can be much later
/// than the event itself (background delivery and wearable syncs are delayed).
public struct ContextSignal: Codable, Sendable, Hashable {
    public enum Kind: Codable, Sendable, Hashable {
        case workoutEnded(start: Date, end: Date)
        case wokeUp(at: Date)
        /// Busy intervals only. No titles, notes, or attendees ever reach the engine.
        case busy([DateInterval])
    }

    public var kind: Kind
    public var source: SignalSource
    public var observedAt: Date

    public init(kind: Kind, source: SignalSource, observedAt: Date) {
        self.kind = kind
        self.source = source
        self.observedAt = observedAt
    }
}

/// How old a signal may be before the engine stops relying on it. Stale data falls back to usual times.
public struct FreshnessPolicy: Codable, Sendable, Hashable {
    /// A workout counts as "just finished" only if it ended this recently.
    public var workoutMinutes: Int
    /// A wake signal is usable only if the app learned it this recently.
    public var wakeMinutes: Int
    /// Busy intervals are usable only if read this recently.
    public var busyMinutes: Int

    public init(workoutMinutes: Int = 90, wakeMinutes: Int = 18 * 60, busyMinutes: Int = 6 * 60) {
        self.workoutMinutes = workoutMinutes
        self.wakeMinutes = wakeMinutes
        self.busyMinutes = busyMinutes
    }
}

// MARK: - Preferences

public enum Intensity: String, Codable, Sendable, CaseIterable {
    case gentle, balanced, extraHelp

    public var maxFollowUps: Int {
        switch self {
        case .gentle: 0
        case .balanced: 1
        case .extraHelp: 2
        }
    }
}

/// Minutes after midnight. Spans midnight when `start > end`. `end` is exclusive.
public struct QuietHours: Codable, Sendable, Hashable {
    public var start: Int
    public var end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }
}

public struct Preferences: Codable, Sendable, Hashable {
    /// Minutes after midnight per moment. For `.postWorkout` this is the evening fallback time
    /// used when no fresh workout was recorded.
    public var usualTimes: [Moment: Int]
    public var windows: [Moment: MomentWindow]
    public var intensity: Intensity
    /// `nil` means "from the end of the bedtime window to the start of the wake window".
    public var quietHours: QuietHours?
    public var privacyMode: Bool
    public var followUpDelayMinutes: Int
    /// Pro only. When false the engine ignores every signal and uses usual times.
    public var contextAware: Bool
    /// Sources the user has connected. Lets copy say "No workout recorded today" only when something could have recorded one.
    public var connectedSources: Set<SignalSource>
    public var freshness: FreshnessPolicy
    /// Shortest calendar gap worth moving a reminder into.
    public var minimumGapMinutes: Int
    /// Days of initial reminders kept pending. Every trigger is one-shot, so this is how long reminders
    /// keep coming if the app is never opened and background refresh never runs. Follow-ups cover two days.
    public var planningDays: Int

    public init(usualTimes: [Moment: Int] = Preferences.defaultUsualTimes,
                windows: [Moment: MomentWindow] = [:],
                intensity: Intensity = .balanced,
                quietHours: QuietHours? = nil,
                privacyMode: Bool = false,
                followUpDelayMinutes: Int = 30,
                contextAware: Bool = false,
                connectedSources: Set<SignalSource> = [],
                freshness: FreshnessPolicy = FreshnessPolicy(),
                minimumGapMinutes: Int = 10,
                planningDays: Int = 7) {
        self.usualTimes = usualTimes
        self.windows = windows
        self.intensity = intensity
        self.quietHours = quietHours
        self.privacyMode = privacyMode
        self.followUpDelayMinutes = followUpDelayMinutes
        self.contextAware = contextAware
        self.connectedSources = connectedSources
        self.freshness = freshness
        self.minimumGapMinutes = minimumGapMinutes
        self.planningDays = planningDays
    }

    /// Same defaults as the app's `Slot.defaultMinutes`.
    public static let defaultUsualTimes: [Moment: Int] = [
        .wake: 7 * 60, .breakfast: 8 * 60, .lunch: 12 * 60 + 30,
        .dinner: 18 * 60 + 30, .bedtime: 22 * 60, .postWorkout: 19 * 60 + 30,
    ]

    public func usualMinutes(for moment: Moment) -> Int {
        usualTimes[moment] ?? Preferences.defaultUsualTimes[moment] ?? 0
    }

    public func window(for moment: Moment) -> MomentWindow {
        windows[moment] ?? .defaultWindow(for: moment)
    }
}

// MARK: - Decisions

/// Why a reminder fires when it does. Rendered to "Why now?" text by `ReminderCopy`.
public struct Reason: Codable, Sendable, Hashable {
    public enum Trigger: String, Codable, Sendable {
        case usualTime
        case workoutEnded
        /// No fresh workout by the fallback time.
        case workoutFallback
        case lateWake
        case calendarGap
        case snoozed
        case followUp
        /// Moved to the end of quiet hours.
        case quietHours
    }

    public var trigger: Trigger
    public var source: SignalSource?
    /// The time of the underlying event (workout end, wake time, snooze time), not when it was observed.
    public var dataTimestamp: Date?
    /// The usual time before any move, so copy can say "moved from 7:00 AM".
    public var usualDate: Date?
    /// Stable id of the timing rule applied, e.g. "timing.lateWake.v1".
    public var ruleID: String

    public init(trigger: Trigger, source: SignalSource? = nil, dataTimestamp: Date? = nil,
                usualDate: Date? = nil, ruleID: String) {
        self.trigger = trigger
        self.source = source
        self.dataTimestamp = dataTimestamp
        self.usualDate = usualDate
        self.ruleID = ruleID
    }
}

public enum ReminderStage: Codable, Sendable, Hashable {
    case initial
    /// 1-based.
    case followUp(Int)
    case snoozed
}

/// One local notification the app should have pending.
public struct ReminderDecision: Codable, Sendable, Hashable, Identifiable {
    /// Notification request identifier. See `ReminderID`.
    public var id: String
    /// Shared by the initial reminder, its follow-ups, and its snooze. Used as the notification thread.
    public var groupID: String
    public var day: Day
    public var moment: Moment
    public var planIDs: [String]
    public var fireDate: Date
    public var stage: ReminderStage
    public var reason: Reason

    public init(id: String, groupID: String, day: Day, moment: Moment, planIDs: [String],
                fireDate: Date, stage: ReminderStage, reason: Reason) {
        self.id = id
        self.groupID = groupID
        self.day = day
        self.moment = moment
        self.planIDs = planIDs
        self.fireDate = fireDate
        self.stage = stage
        self.reason = reason
    }
}

/// Notification identifiers. These must stay stable across releases: the scheduler diffs pending
/// requests by id, and old builds' ids (`suppl.<slot>`, `suppl.followup.<slot>`) are cleaned up by the app.
public enum ReminderID {
    public static func group(day: Day, moment: Moment) -> String {
        "suppl.\(day.key).\(moment.rawValue)"
    }

    public static func make(day: Day, moment: Moment, stage: ReminderStage) -> String {
        let base = group(day: day, moment: moment)
        switch stage {
        case .initial: return base
        case .followUp(let n): return "\(base).f\(n)"
        case .snoozed: return "\(base).s"
        }
    }

    /// True for identifiers this engine produces (as opposed to legacy or test ids).
    public static func isEngineID(_ id: String) -> Bool {
        let parts = id.split(separator: ".")
        return parts.count >= 3 && parts[0] == "suppl" && parts[1].count == 10
    }
}

/// Title and body for one notification.
public struct NotificationText: Codable, Sendable, Hashable {
    public var title: String
    public var body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

// MARK: - Engine and copy entry points
//
// Implemented in Engine/ReminderEngine.swift and Copy/ReminderCopy.swift:
//
//   public enum ReminderEngine {
//       /// Reminders that should be pending right now, for today and tomorrow, soonest first, at most 48.
//       /// `history` holds decisions already delivered (fire date in the past), so nothing fires twice.
//       public static func plan(plans: [DosePlan], statuses: [DoseStatus], signals: [ContextSignal],
//                               history: [ReminderDecision], prefs: Preferences,
//                               now: Date, calendar: Calendar) -> [ReminderDecision]
//   }
//
//   public enum ReminderCopy {
//       public static func notification(for decision: ReminderDecision, plans: [DosePlan],
//                                       privacyMode: Bool, calendar: Calendar, locale: Locale) -> NotificationText
//       public static func whyNow(_ reason: Reason, moment: Moment, calendar: Calendar, locale: Locale) -> String
//   }

// MARK: - Catalog and tips

public enum WithFoodHint: String, Codable, Sendable, CaseIterable {
    case food, either, emptyStomach, unknown
}

/// A general supplement ingredient. Not a brand-level product: the user's exact product may differ.
public struct CatalogEntry: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    /// Other names and common misspellings, used by search.
    public var synonyms: [String]
    public var category: String
    /// Unit strings from the app's unit list, most common first.
    public var typicalUnits: [String]
    public var withFoodHint: WithFoodHint
    public var suggestedMoment: Moment?
    /// Short, general, conservative. Never a dose recommendation.
    public var note: String
    public var odsURL: String?
    /// Link only. Examine's text is licensed and must not be copied.
    public var examineURL: String?
    public var sources: [String]
    public var reviewStatus: String
    public var lastReviewed: String?

    public init(id: String, name: String, synonyms: [String] = [], category: String, typicalUnits: [String],
                withFoodHint: WithFoodHint = .unknown, suggestedMoment: Moment? = nil, note: String,
                odsURL: String? = nil, examineURL: String? = nil, sources: [String],
                reviewStatus: String = "unreviewed", lastReviewed: String? = nil) {
        self.id = id
        self.name = name
        self.synonyms = synonyms
        self.category = category
        self.typicalUnits = typicalUnits
        self.withFoodHint = withFoodHint
        self.suggestedMoment = suggestedMoment
        self.note = note
        self.odsURL = odsURL
        self.examineURL = examineURL
        self.sources = sources
        self.reviewStatus = reviewStatus
        self.lastReviewed = lastReviewed
    }
}

/// One daily tip. General information only, always with a source.
public struct Tip: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var text: String
    /// Catalog ids this tip is relevant to. Empty means general.
    public var ingredients: [String]
    public var sourceURL: String
    public var reviewStatus: String

    public init(id: String, text: String, ingredients: [String] = [], sourceURL: String,
                reviewStatus: String = "unreviewed") {
        self.id = id
        self.text = text
        self.ingredients = ingredients
        self.sourceURL = sourceURL
        self.reviewStatus = reviewStatus
    }
}

// MARK: - Rules

/// A reviewed, versioned rule about supplement timing or interactions.
/// Clinical rules ship disabled until a qualified person reviews them.
public struct InteractionRule: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        /// Shown on the detail screen only. Never changes timing.
        case informational
        /// Would keep two ingredients apart in time. Clinical; disabled pending review.
        case spacing
    }

    public enum Severity: String, Codable, Sendable {
        case info, caution, important
    }

    public var id: String
    public var version: Int
    public var kind: Kind
    public var severity: Severity
    /// Catalog ids. The rule applies when the user's plans include all of them (or the one, for single-ingredient notes).
    public var ingredients: [String]
    public var separationMinutes: Int?
    /// Plain-language explanation shown to the user.
    public var explanation: String
    public var sources: [String]
    public var enabled: Bool
    public var reviewStatus: String
    public var reviewer: String?
    public var lastReviewed: String?

    public init(id: String, version: Int, kind: Kind, severity: Severity, ingredients: [String],
                separationMinutes: Int? = nil, explanation: String, sources: [String], enabled: Bool,
                reviewStatus: String = "unreviewed", reviewer: String? = nil, lastReviewed: String? = nil) {
        self.id = id
        self.version = version
        self.kind = kind
        self.severity = severity
        self.ingredients = ingredients
        self.separationMinutes = separationMinutes
        self.explanation = explanation
        self.sources = sources
        self.enabled = enabled
        self.reviewStatus = reviewStatus
        self.reviewer = reviewer
        self.lastReviewed = lastReviewed
    }
}

// MARK: - Connectors

public enum ConnectorID: String, Codable, Sendable, CaseIterable {
    case appleHealth, calendar, whoop, oura
}

public enum ConnectorAvailability: Codable, Sendable, Hashable {
    case available
    /// Built but missing credentials or setup (e.g. WHOOP before a developer app exists). Shown as "Not available yet".
    case notConfigured
    /// Not possible on this device.
    case unsupported
}

public enum ConnectorAuthorization: Codable, Sendable, Hashable {
    case notConnected
    /// The user went through the connect flow. For HealthKit this can't prove read access
    /// (iOS hides read authorization), so copy must not promise data.
    case connected
    case denied
}

/// An optional source of context signals. Every connector is independently revocable and never blocks the app.
@MainActor
public protocol Connector: AnyObject {
    var id: ConnectorID { get }
    var displayName: String { get }
    /// One plain-English line: what we read and why.
    var summary: String { get }
    var availability: ConnectorAvailability { get }
    var authorization: ConnectorAuthorization { get }
    var lastSync: Date? { get }
    func connect() async throws
    func disconnect() async
    func fetchSignals(since: Date) async throws -> [ContextSignal]
}
