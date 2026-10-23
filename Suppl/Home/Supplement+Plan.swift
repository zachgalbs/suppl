import Foundation
import SupplCore

extension Supplement {
    /// The engine's view of this supplement. Only the user's saved dose goes in; nothing here changes it.
    var dosePlan: DosePlan {
        DosePlan(id: planID,
                 name: name,
                 doseText: doseText,
                 moment: Moment(rawValue: slot.rawValue) ?? .breakfast,
                 withFood: withFood,
                 frequency: takesEveryDay ? .daily : .weekdays(weekdays),
                 clinicianDirected: clinicianDirected,
                 catalogID: catalogID)
    }
}
