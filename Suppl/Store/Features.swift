import Foundation
import SupplCore

/// What the current user can use. One place, so the engine and the screens can't disagree.
struct Features: Equatable {
    var isPro: Bool
    /// While testing, workout, late-wake, and calendar timing are free. WHOOP, Extra Help, and history stay Pro.
    var smartTimingFree: Bool

    /// Set in project.yml. Missing means today's Pro gating.
    static let infoKey = "SupplSmartTimingFree"

    static var smartTimingFreeInBuild: Bool {
        Bundle.main.object(forInfoDictionaryKey: infoKey) as? Bool ?? false
    }

    @MainActor static var current: Features {
        Features(isPro: Store.shared.isPro, smartTimingFree: smartTimingFreeInBuild)
    }

    var smartTiming: Bool { isPro || smartTimingFree }
    var extraHelp: Bool { isPro }
    var reminderHistory: Bool { isPro }

    /// Connected sources whose data may time reminders.
    func timingSources(_ connected: Set<SignalSource>) -> Set<SignalSource> {
        if isPro { return connected }
        return smartTimingFree ? connected.subtracting([.whoop]) : []
    }

    func timingSignals(_ signals: [ContextSignal], connected: Set<SignalSource>) -> [ContextSignal] {
        let allowed = timingSources(connected)
        return signals.filter { allowed.contains($0.source) }
    }
}
