#if DEBUG
import Foundation
import SwiftData
import SupplCore

/// Sample data for SwiftUI previews only. Never compiled into Release builds.
@MainActor
enum PreviewData {
    static func container(empty: Bool = false) -> ModelContainer {
        let container = try! ModelContainer(for: Supplement.self, DoseLog.self, DecisionLog.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        if !empty {
            for supplement in samples() { container.mainContext.insert(supplement) }
            container.mainContext.insert(decisionLog())
        }
        return container
    }

    static func samples() -> [Supplement] {
        let d = Supplement(name: "Vitamin D3", brand: "Nature Made", dose: 1, unit: "softgel", slot: .breakfast)
        d.catalogID = "vitamin-d"
        let magnesium = Supplement(name: "Magnesium", dose: 2, unit: "capsule", slot: .bedtime, withFood: false)
        magnesium.catalogID = "magnesium"
        let creatine = Supplement(name: "Creatine", dose: 5, unit: "g", slot: .postWorkout, withFood: false)
        creatine.frequencyRaw = "weekdays"
        creatine.weekdays = [2, 4, 6]
        let iron = Supplement(name: "Iron", dose: 1, unit: "tablet", slot: .wake, withFood: false)
        iron.clinicianDirected = true
        iron.notes = "Take with orange juice."
        return [d, magnesium, creatine, iron]
    }

    static let groupID = "suppl.preview.postWorkout"

    static func decisionLog() -> DecisionLog {
        let ended = Date.now.addingTimeInterval(-20 * 60)
        let reason = Reason(trigger: .workoutEnded, source: .appleHealth, dataTimestamp: ended,
                            ruleID: "timing.postWorkout.v1")
        let decision = ReminderDecision(id: groupID, groupID: groupID, day: Day(.now, calendar: .current),
                                        moment: .postWorkout, planIDs: [],
                                        fireDate: .now.addingTimeInterval(-15 * 60),
                                        stage: .initial, reason: reason)
        let endText = ended.formatted(date: .omitted, time: .shortened)
        return DecisionLog(decision: decision, title: "After your workout",
                           reasonText: "Apple Health recorded a workout ending at \(endText).",
                           supplementNames: ["Creatine"])
    }
}
#endif
