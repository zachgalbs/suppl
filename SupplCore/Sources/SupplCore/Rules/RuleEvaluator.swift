import Foundation

/// Matches rules to the user's plans by catalog id. Plans entered manually have no catalog id,
/// so no rule ever matches them: better silent than guessing from a typed name.
public enum RuleEvaluator {
    /// Rules whose ingredients are all present among the plans' catalogIDs. Disabled rules excluded unless includeDisabled.
    public static func applicableRules(for plans: [DosePlan], rules: [InteractionRule],
                                       includeDisabled: Bool = false) -> [InteractionRule] {
        let present = Set(plans.compactMap(\.catalogID))
        return rules.filter { rule in
            (includeDisabled || rule.enabled) && !rule.ingredients.isEmpty
                && Set(rule.ingredients).isSubset(of: present)
        }
    }

    /// Informational, enabled notes relevant to one plan (any rule that mentions its catalogID), for the detail screen.
    /// A note naming several ingredients shows only when the user takes all of them.
    public static func notes(for plan: DosePlan, allPlans: [DosePlan], rules: [InteractionRule]) -> [InteractionRule] {
        guard let id = plan.catalogID else { return [] }
        let present = Set(allPlans.compactMap(\.catalogID)).union([id])
        return rules.filter { rule in
            rule.enabled && rule.kind == .informational && rule.ingredients.contains(id)
                && Set(rule.ingredients).isSubset(of: present)
        }
    }
}
