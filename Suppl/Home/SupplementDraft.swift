import Foundation
import SupplCore

/// Prefill for a new supplement. Everything stays editable in the form.
struct SupplementDraft: Identifiable {
    let id = UUID()
    var name: String
    var unit: String?
    var withFood: Bool?
    var slot: Slot?
    var catalogID: String?

    init(name: String = "") {
        self.name = name
    }

    init(_ entry: CatalogEntry) {
        name = entry.name
        unit = entry.typicalUnits.first { Supplement.units.contains($0) }
        switch entry.withFoodHint {
        case .food: withFood = true
        case .emptyStomach: withFood = false
        case .either, .unknown: withFood = nil
        }
        slot = entry.suggestedMoment.flatMap { Slot(rawValue: $0.rawValue) }
        catalogID = entry.id
    }
}
