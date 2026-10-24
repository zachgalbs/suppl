import Foundation
import SwiftData
import SupplCore
import UserNotifications

/// Runs the reminder engine and makes iOS's pending notifications match its output.
/// Only changed requests are added or removed, so re-running is cheap and never double-schedules.
@MainActor
enum NotificationScheduler {
    /// Bumped by every request; a run covers every request made before it started.
    private static var requested = 0
    private static var completed = 0
    private static var worker: Task<Void, Never>?
    /// Set when HealthKit, the calendar, or background refresh says connector data changed.
    /// Consumed at the start of a run, so a change that lands mid-run is picked up by the next one.
    private static var signalsInvalidated = false
    private static var cachedSignals: [ContextSignal] = []
    private static var signalsFetchedAt: Date?

    /// Re-plans and returns only once a run that started after this call has finished, so callers that
    /// must hand control back to iOS (notification actions, HealthKit, background tasks) know the
    /// pending requests are up to date. Bursts of calls share one run.
    static func run(refreshSignals: Bool = false) async {
        if refreshSignals { signalsInvalidated = true }
        requested += 1
        let target = requested
        if worker == nil {
            worker = Task { @MainActor in
                while completed < requested {
                    let generation = requested
                    await runOnce(now: .now, calendar: .current)
                    completed = generation
                }
                worker = nil
            }
        }
        while completed < target, let current = worker {
            await current.value
        }
    }

    private static func runOnce(now: Date, calendar: Calendar) async {
        let context = sharedContainer.mainContext
        Supplement.backfillIDs(in: context)
        let supplements = (try? context.fetch(FetchDescriptor<Supplement>())) ?? []
        let doseLogs = (try? context.fetch(FetchDescriptor<DoseLog>())) ?? []
        let decisionLogs = (try? context.fetch(FetchDescriptor<DecisionLog>())) ?? []

        // Entitlements come from StoreKit on every run; a lapsed subscription falls back to usual times here.
        await Store.shared.refresh()
        let isPro = Store.shared.isPro
        let hub = ConnectorHub.shared
        let signals = isPro ? await signals(from: hub, now: now, calendar: calendar) : []
        let prefs = Preferences.current(isPro: isPro, connectedSources: hub.connectedSources)

        let plans = supplements.map(\.dosePlan)
        let decisions = ReminderEngine.plan(
            plans: plans,
            statuses: EngineInputs.statuses(for: supplements, logs: doseLogs, now: now, calendar: calendar),
            signals: signals,
            history: EngineInputs.history(from: decisionLogs, now: now),
            prefs: prefs, now: now, calendar: calendar)

        await apply(decisions, plans: plans, prefs: prefs, logs: decisionLogs, context: context, now: now, calendar: calendar)
        prune(decisionLogs, context: context, now: now)
        try? context.save()
    }

    /// Connector data is cached for a few minutes so routine edits don't hit WHOOP's rate limits.
    private static func signals(from hub: ConnectorHub, now: Date, calendar: Calendar) async -> [ContextSignal] {
        let invalidated = signalsInvalidated
        signalsInvalidated = false
        if !invalidated, let fetched = signalsFetchedAt, now.timeIntervalSince(fetched) < 5 * 60 {
            return cachedSignals
        }
        cachedSignals = await hub.signals(since: calendar.startOfDay(for: now))
        signalsFetchedAt = now
        return cachedSignals
    }

    private static func apply(_ decisions: [ReminderDecision], plans: [DosePlan], prefs: Preferences,
                              logs: [DecisionLog], context: ModelContext, now: Date, calendar: Calendar) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let pendingByID = Dictionary(pending.map { ($0.identifier, $0) }, uniquingKeysWith: { a, _ in a })
        let wanted = Set(decisions.map(\.id))

        // Old builds scheduled repeating `suppl.<slot>` and one-off `suppl.followup.<slot>` requests.
        let legacy = Slot.allCases.flatMap { ["suppl.\($0.rawValue)", "suppl.followup.\($0.rawValue)"] }
        let stale = pending.map(\.identifier).filter { ReminderID.isEngineID($0) && !wanted.contains($0) }
        center.removePendingNotificationRequests(withIdentifiers: legacy + stale)

        // A request that was removed before it fired was never delivered, so it leaves no history.
        let staleSet = Set(stale)
        for log in logs where staleSet.contains(log.requestID) || (log.fireDate > now && !wanted.contains(log.requestID)) {
            context.delete(log)
        }

        let logsByID = Dictionary(logs.map { ($0.requestID, $0) }, uniquingKeysWith: { a, _ in a })
        let plansByID = Dictionary(plans.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let locale = Locale.current

        for decision in decisions {
            let text = ReminderCopy.notification(for: decision, plans: plans, privacyMode: prefs.privacyMode,
                                                 calendar: calendar, locale: locale)
            let reasonText = ReminderCopy.whyNow(decision.reason, moment: decision.moment, calendar: calendar, locale: locale)
            let names = decision.planIDs.compactMap { plansByID[$0]?.name }

            let request = makeRequest(for: decision, text: text, calendar: calendar)
            if let existing = pendingByID[decision.id], isSame(existing, as: request) {
                // Generic privacy text can stay unchanged while the explanation or saved plan changes.
                if let log = logsByID[decision.id] {
                    log.update(decision: decision, title: text.title, reasonText: reasonText, supplementNames: names)
                } else {
                    context.insert(DecisionLog(decision: decision, title: text.title, reasonText: reasonText, supplementNames: names))
                }
                continue
            }
            do {
                try await center.add(request)
            } catch {
                // Not scheduled (e.g. notifications not allowed yet), so it must not count as delivered later.
                if let log = logsByID[decision.id] { context.delete(log) }
                continue
            }

            if let log = logsByID[decision.id] {
                log.update(decision: decision, title: text.title, reasonText: reasonText, supplementNames: names)
            } else {
                context.insert(DecisionLog(decision: decision, title: text.title, reasonText: reasonText, supplementNames: names))
            }
        }
    }

    static func makeRequest(for decision: ReminderDecision, text: NotificationText,
                            calendar: Calendar) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = text.title
        content.body = text.body
        content.sound = .default
        content.threadIdentifier = decision.groupID
        content.categoryIdentifier = decision.stage == .initial ? Reminders.category : Reminders.followUpCategory
        content.userInfo = [
            "slot": decision.moment.rawValue,
            "group": decision.groupID,
            "day": decision.day.key,
            "plans": decision.planIDs,
        ]
        // Local wall-clock components preserve usual times when travelling without opening the app.
        let when = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: decision.fireDate)
        return UNNotificationRequest(identifier: decision.id, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false))
    }

    /// Matching text alone is insufficient: private reminders still carry distinct action targets.
    static func isSame(_ existing: UNNotificationRequest, as wanted: UNNotificationRequest) -> Bool {
        guard existing.identifier == wanted.identifier,
              existing.content.title == wanted.content.title,
              existing.content.body == wanted.content.body,
              existing.content.categoryIdentifier == wanted.content.categoryIdentifier,
              existing.content.threadIdentifier == wanted.content.threadIdentifier,
              NSDictionary(dictionary: existing.content.userInfo).isEqual(to: wanted.content.userInfo),
              let oldTrigger = existing.trigger as? UNCalendarNotificationTrigger,
              let newTrigger = wanted.trigger as? UNCalendarNotificationTrigger
        else { return false }
        return oldTrigger.repeats == newTrigger.repeats && oldTrigger.dateComponents == newTrigger.dateComponents
    }

    /// The Why-now sheet and Recent reminders only look back 14 days. Dose history is kept.
    private static func prune(_ decisionLogs: [DecisionLog], context: ModelContext, now: Date) {
        let cutoff = now.addingTimeInterval(-14 * 24 * 3600)
        for log in decisionLogs where log.fireDate < cutoff && !log.isDeleted {
            context.delete(log)
        }
    }
}
