import Foundation
import SwiftData
import SupplCore
import UserNotifications

/// Runs the reminder engine and makes iOS's pending notifications match its output.
/// Only changed requests are added or removed, so re-running is cheap and never double-schedules.
@MainActor
enum NotificationScheduler {
    private static var running = false
    private static var rerunRequested = false
    private static var cachedSignals: [ContextSignal] = []
    private static var signalsFetchedAt: Date?

    /// Coalesces bursts of calls (several edits, foreground + observer) into at most one extra run.
    /// `refreshSignals` forces a connector fetch, e.g. when HealthKit or the calendar says something changed.
    static func run(refreshSignals: Bool = false) async {
        if refreshSignals { signalsFetchedAt = nil }
        guard !running else {
            rerunRequested = true
            return
        }
        running = true
        defer { running = false }
        repeat {
            rerunRequested = false
            await runOnce(now: .now, calendar: .current)
        } while rerunRequested
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
        if let fetched = signalsFetchedAt, now.timeIntervalSince(fetched) < 5 * 60 {
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

            if let existing = pendingByID[decision.id], isSame(existing, text: text, fireDate: decision.fireDate) {
                continue
            }
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
            let interval = max(1, decision.fireDate.timeIntervalSince(now))
            let request = UNNotificationRequest(
                identifier: decision.id, content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))
            try? await center.add(request)

            if let log = logsByID[decision.id] {
                log.update(decision: decision, title: text.title, reasonText: reasonText, supplementNames: names)
            } else {
                context.insert(DecisionLog(decision: decision, title: text.title, reasonText: reasonText, supplementNames: names))
            }
        }
    }

    /// Same text and a fire date within a minute: leave it alone instead of churning the request.
    private static func isSame(_ request: UNNotificationRequest, text: NotificationText, fireDate: Date) -> Bool {
        guard request.content.title == text.title, request.content.body == text.body,
              let next = (request.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
        else { return false }
        return abs(next.timeIntervalSince(fireDate)) < 60
    }

    /// The Why-now sheet and Recent reminders only look back 14 days. Dose history is kept.
    private static func prune(_ decisionLogs: [DecisionLog], context: ModelContext, now: Date) {
        let cutoff = now.addingTimeInterval(-14 * 24 * 3600)
        for log in decisionLogs where log.fireDate < cutoff && !log.isDeleted {
            context.delete(log)
        }
    }
}
