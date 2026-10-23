import Foundation
import HealthKit
import Observation
import SupplCore

/// Reads workouts and sleep from Apple Health. Read-only: nothing is ever written back.
///
/// iOS never tells an app whether read access was granted, so `.connected` only means the user went
/// through the Health prompt. A denied user just looks like someone with no workouts.
@MainActor @Observable
final class AppleHealthConnector: Connector {
    let id = ConnectorID.appleHealth
    let displayName = "Apple Health"
    let summary = "Reads your workouts and sleep, so a post-workout reminder can follow a workout and a morning reminder can wait until you're up."
    let disconnectNote: String? = "To fully revoke access, open the Health app, then Sharing > Apps > suppl."

    private(set) var authorization: ConnectorAuthorization
    private(set) var lastSync: Date?

    @ObservationIgnored var now: () -> Date = Date.init
    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var observer: HKObserverQuery?
    @ObservationIgnored private var onWorkoutUpdate: (@MainActor () async -> Void)?

    static let connectedKey = "connector.appleHealth.connected"
    static let lastSyncKey = "connector.appleHealth.lastSync"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        authorization = defaults.bool(forKey: Self.connectedKey) ? .connected : .notConnected
        lastSync = defaults.object(forKey: Self.lastSyncKey) as? Date
    }

    var availability: ConnectorAvailability {
        HKHealthStore.isHealthDataAvailable() ? .available : .unsupported
    }

    private var workoutType: HKWorkoutType { HKObjectType.workoutType() }
    private var sleepType: HKCategoryType { HKCategoryType(.sleepAnalysis) }

    func connect() async throws {
        guard availability == .available else { throw ConnectorError.unsupported }
        do {
            try await store.requestAuthorization(toShare: [], read: [workoutType, sleepType])
        } catch {
            throw ConnectorError.failed("Couldn't open the Apple Health prompt. Try again.")
        }
        defaults.set(true, forKey: Self.connectedKey)
        authorization = .connected
        startQueryIfReady()
    }

    /// Stops reading. Only the user can revoke the OS permission, in the Health app (see `disconnectNote`).
    func disconnect() async {
        if let observer { store.stop(observer) }
        observer = nil
        if availability == .available {
            store.disableBackgroundDelivery(for: workoutType) { _, _ in }
        }
        defaults.removeObject(forKey: Self.connectedKey)
        defaults.removeObject(forKey: Self.lastSyncKey)
        authorization = .notConnected
        lastSync = nil
    }

    func fetchSignals(since: Date) async throws -> [ContextSignal] {
        guard availability == .available, authorization == .connected else { return [] }
        let at = now()
        var signals: [ContextSignal] = []

        let workouts = try await HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForSamples(withStart: since, end: at, options: []))],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 20
        ).result(for: store)
        for w in workouts where w.endDate >= since && w.endDate <= at {
            signals.append(ContextSignal(kind: .workoutEnded(start: w.startDate, end: w.endDate),
                                         source: .appleHealth, observedAt: at))
        }

        // Last night's sleep usually starts yesterday evening, so look back a full day.
        let dayStart = Calendar.current.startOfDay(for: at)
        let lookBack = dayStart.addingTimeInterval(-24 * 3600)
        let sleep = try await HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleepType,
                                         predicate: HKQuery.predicateForSamples(withStart: lookBack, end: at, options: []))],
            sortDescriptors: [SortDescriptor(\.startDate)],
            limit: nil
        ).result(for: store)
        let asleep = sleep
            .filter { SleepSessions.asleepValues.contains($0.value) && $0.endDate > $0.startDate }
            .map { DateInterval(start: $0.startDate, end: $0.endDate) }
        if let woke = SleepSessions.mainSleepEnd(asleep: asleep, dayStart: dayStart, now: at) {
            signals.append(ContextSignal(kind: .wokeUp(at: woke), source: .appleHealth, observedAt: at))
        }

        lastSync = at
        defaults.set(at, forKey: Self.lastSyncKey)
        return signals
    }

    /// Wakes the app when a workout is saved, so a post-workout reminder can be re-planned.
    /// Call once at launch; it does nothing until the user connects, then starts on its own.
    /// Background delivery is best effort: iOS may batch or delay it.
    func startObservingWorkouts(onUpdate: @escaping @MainActor () async -> Void) {
        onWorkoutUpdate = onUpdate
        startQueryIfReady()
    }

    private func startQueryIfReady() {
        guard observer == nil, let onUpdate = onWorkoutUpdate,
              availability == .available, authorization == .connected else { return }
        let type = workoutType
        let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
            // HealthKit stops background delivery if the completion handler is skipped, so always call it.
            guard error == nil else { completion(); return }
            Task { @MainActor in
                await onUpdate()
                completion()
            }
        }
        store.execute(query)
        observer = query
        store.enableBackgroundDelivery(for: type, frequency: .immediate) { _, _ in }
    }
}

/// Turns sleep-stage samples into a wake time. Plain functions so they can be unit tested without HealthKit data.
enum SleepSessions {
    /// Shorter asleep stretches are naps and don't count as waking up for the day.
    static let minimumMainSleep: TimeInterval = 3 * 3600
    /// Asleep samples closer together than this belong to the same night (brief wake-ups, overlapping sources).
    static let joinGap: TimeInterval = 60 * 60

    /// Stage values that count as asleep. `inBed` and `awake` don't.
    static let asleepValues: Set<Int> = [
        HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
        HKCategoryValueSleepAnalysis.asleepCore.rawValue,
        HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
        HKCategoryValueSleepAnalysis.asleepREM.rawValue,
    ]

    /// End of the latest main sleep that ended today. Asleep samples are joined into sessions
    /// (stages arrive as many short samples, sometimes from several sources); sessions with less than
    /// `minimumMainSleep` asleep are naps and ignored.
    static func mainSleepEnd(asleep: [DateInterval], dayStart: Date, now: Date) -> Date? {
        var sessions: [(start: Date, end: Date, asleep: TimeInterval)] = []
        for interval in asleep.sorted(by: { $0.start < $1.start }) {
            if let last = sessions.last, interval.start.timeIntervalSince(last.end) <= joinGap {
                // Overlapping sources: only count time past the session's current end.
                let added = max(0, interval.end.timeIntervalSince(max(interval.start, last.end)))
                sessions[sessions.count - 1] = (last.start, max(last.end, interval.end), last.asleep + added)
            } else {
                sessions.append((interval.start, interval.end, interval.duration))
            }
        }
        return sessions
            .filter { $0.asleep >= minimumMainSleep && $0.end >= dayStart && $0.end <= now }
            .map { $0.end }
            .max()
    }
}
