import Foundation
import SwiftData
import SupplCore

/// One user-confirmed action on a supplement for a day. No response is never logged, so it stays "unconfirmed".
@Model
final class DoseLog {
    var supplementID: String
    /// `Day.key` (yyyy-MM-dd) in the time zone the action happened in.
    var dayKey: String
    /// "taken", "skipped", or "snoozed".
    var actionRaw: String
    var at: Date
    var snoozedUntil: Date?
    /// "notification" or "app".
    var sourceRaw: String

    init(supplementID: String, dayKey: String, action: Action, at: Date = .now,
         snoozedUntil: Date? = nil, source: Source) {
        self.supplementID = supplementID
        self.dayKey = dayKey
        self.actionRaw = action.rawValue
        self.at = at
        self.snoozedUntil = snoozedUntil
        self.sourceRaw = source.rawValue
    }

    enum Action: String { case taken, skipped, snoozed }
    enum Source: String { case notification, app }

    var action: Action? { Action(rawValue: actionRaw) }
}

/// A reminder the scheduler handed to iOS, with the "Why now?" text it was sent with.
/// Kept for 14 days for the Why-now sheet and Recent reminders.
@Model
final class DecisionLog {
    @Attribute(.unique) var requestID: String
    var groupID: String
    var momentRaw: String
    var fireDate: Date
    var title: String
    var reasonText: String
    var dataTimestamp: Date?
    var supplementNames: String
    /// The encoded `ReminderDecision`, fed back to the engine as history so nothing fires twice.
    var payload: Data

    init(decision: ReminderDecision, title: String, reasonText: String, supplementNames: [String]) {
        self.requestID = decision.id
        self.groupID = decision.groupID
        self.momentRaw = decision.moment.rawValue
        self.fireDate = decision.fireDate
        self.title = title
        self.reasonText = reasonText
        self.dataTimestamp = decision.reason.dataTimestamp
        self.supplementNames = supplementNames.joined(separator: ", ")
        self.payload = (try? JSONEncoder().encode(decision)) ?? Data()
    }

    var decision: ReminderDecision? { try? JSONDecoder().decode(ReminderDecision.self, from: payload) }
}
