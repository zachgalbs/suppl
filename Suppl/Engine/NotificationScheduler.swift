import Foundation
import SwiftData
import SupplCore
import UserNotifications

/// Runs the reminder engine and makes iOS's pending notifications match its output.
/// Only changed requests are added or removed, so re-running is cheap and never double-schedules.
@MainActor
enum NotificationScheduler {
    private static let work = ReminderWorkQueue()
    private static var revision = 0
    private static var cachedSignals: [ContextSignal] = []
    private static var signalsFetchedAt: Date?
    private static var cachedHubRevision = -1

    static var isResetting: Bool { work.isPaused }

    /// Each caller waits for a fresh pass. Cancelling a background caller releases it promptly;
    /// unrelated foreground callers retain their work.
    static func run(refreshSignals: Bool = false) async {
        guard !isResetting, !Task.isCancelled else { return }
        if refreshSignals { invalidateSignals() }
        await work.run { await runOnce(now: .now, calendar: .current) }
    }

    static func connectionsChanged() {
        invalidateSignals()
        Reminders.reschedule()
    }

    private static func invalidateSignals() {
        revision += 1
        cachedSignals = []
        signalsFetchedAt = nil
    }

    /// Drain any in-flight notification add before the caller deletes data and clears requests.
    static func beginReset() async {
        invalidateSignals()
        await work.pauseAndDrain()
    }

    static func endReset() { work.resume() }

    private static func isCurrent(_ value: Int) -> Bool {
        value == revision && !work.isPaused && !Task.isCancelled
    }

    private static func runOnce(now: Date, calendar: Calendar) async {
        let pass = revision
        // Entitlements come from StoreKit on every run; a lapsed subscription falls back to usual times here.
        await Store.shared.refresh()
        guard isCurrent(pass) else { return }
        let isPro = Store.shared.isPro
        let hub = ConnectorHub.shared
        let signals = isPro ? await signals(from: hub, now: now, calendar: calendar) : []
        guard isCurrent(pass) else { return }
        let context = sharedContainer.mainContext
        Supplement.backfillIDs(in: context)
        let supplements = (try? context.fetch(FetchDescriptor<Supplement>())) ?? []
        let doseLogs = (try? context.fetch(FetchDescriptor<DoseLog>())) ?? []
        let decisionLogs = (try? context.fetch(FetchDescriptor<DecisionLog>())) ?? []
        let prefs = Preferences.current(isPro: isPro, connectedSources: hub.connectedSources)

        let plans = supplements.map(\.dosePlan)
        let decisions = ReminderEngine.plan(
            plans: plans,
            statuses: EngineInputs.statuses(for: supplements, logs: doseLogs, now: now, calendar: calendar),
            signals: signals,
            history: EngineInputs.history(from: decisionLogs, now: now),
            prefs: prefs, now: now, calendar: calendar)

        await apply(decisions, plans: plans, prefs: prefs, logs: decisionLogs, context: context, now: now, calendar: calendar, pass: pass)
        guard isCurrent(pass) else { return }
        prune(decisionLogs, context: context, now: now)
        try? context.save()
    }

    /// Connector data is cached for a few minutes so routine edits don't hit WHOOP's rate limits.
    private static func signals(from hub: ConnectorHub, now: Date, calendar: Calendar) async -> [ContextSignal] {
        let hubRevision = hub.revision
        if cachedHubRevision == hubRevision, let fetched = signalsFetchedAt,
           now.timeIntervalSince(fetched) < 5 * 60 {
            return cachedSignals.filter { hub.connectedSources.contains($0.source) }
        }
        let pass = revision
        let fresh = await hub.signals(since: calendar.startOfDay(for: now))
        guard isCurrent(pass), hub.revision == hubRevision else { return [] }
        cachedSignals = fresh.filter { hub.connectedSources.contains($0.source) }
        signalsFetchedAt = now
        cachedHubRevision = hubRevision
        return cachedSignals
    }

    private static func apply(_ decisions: [ReminderDecision], plans: [DosePlan], prefs: Preferences,
                              logs: [DecisionLog], context: ModelContext, now: Date, calendar: Calendar, pass: Int) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        guard isCurrent(pass) else { return }
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
                guard isCurrent(pass) else {
                    center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
                    return
                }
            } catch {
                guard isCurrent(pass) else { return }
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

/// One serial scheduler worker, with individually cancellable callers and a deletion barrier.
/// The operation checks cancellation after each suspension before touching persistent state.
@MainActor
final class ReminderWorkQueue {
    private(set) var isPaused = false
    private var requested = 0
    private var worker: Task<Void, Never>?
    private var waiters: [UUID: (generation: Int, continuation: CheckedContinuation<Void, Never>)] = [:]
    private var operation: (@MainActor () async -> Void)?

    func run(_ operation: @escaping @MainActor () async -> Void) async {
        guard !isPaused, !Task.isCancelled else { return }
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !isPaused, !Task.isCancelled else { continuation.resume(); return }
                requested += 1
                self.operation = operation
                waiters[id] = (requested, continuation)
                startIfNeeded()
            }
        } onCancel: {
            Task { @MainActor in self.cancel(id) }
        }
    }

    func pauseAndDrain() async {
        isPaused = true
        worker?.cancel()
        let pending = waiters.values.map(\.continuation)
        waiters.removeAll()
        for continuation in pending { continuation.resume() }
        await worker?.value
    }

    func resume() { isPaused = false }

    private func cancel(_ id: UUID) {
        waiters.removeValue(forKey: id)?.continuation.resume()
        if waiters.isEmpty { worker?.cancel() }
    }

    private func startIfNeeded() {
        guard worker == nil, !isPaused, !waiters.isEmpty else { return }
        worker = Task { @MainActor in
            while !isPaused, !waiters.isEmpty, !Task.isCancelled {
                let generation = requested
                await operation?()
                guard !Task.isCancelled else { break }
                let done = waiters.filter { $0.value.generation <= generation }.map(\.key)
                for id in done { waiters.removeValue(forKey: id)?.continuation.resume() }
            }
            worker = nil
            startIfNeeded()
        }
    }
}
