import Foundation

/// The rules suppl. ships with. Spacing rules are clinical, so they stay `enabled: false` until a
/// qualified person reviews them; the engine never moves a dose for spacing on its own.
/// Medication interactions are out of scope: the app doesn't collect medications.
public enum RuleBook {
    static let ironHP = "https://ods.od.nih.gov/factsheets/Iron-HealthProfessional/"
    static let ironConsumer = "https://ods.od.nih.gov/factsheets/Iron-Consumer/"
    static let calciumHP = "https://ods.od.nih.gov/factsheets/Calcium-HealthProfessional/"
    static let calciumConsumer = "https://ods.od.nih.gov/factsheets/Calcium-Consumer/"
    static let zincHP = "https://ods.od.nih.gov/factsheets/Zinc-HealthProfessional/"
    static let magnesiumHP = "https://ods.od.nih.gov/factsheets/Magnesium-HealthProfessional/"

    /// All shipped rules. Clinical (spacing) rules have enabled: false pending human review.
    public static let all: [InteractionRule] = [
        InteractionRule(
            id: "spacing.calcium-iron", version: 1, kind: .spacing, severity: .caution,
            ingredients: ["calcium", "iron"], separationMinutes: 120,
            explanation: "Calcium can lower how much iron the body absorbs when they're taken together. "
                + "Some people take them at different times. Check your labels or ask a pharmacist.",
            sources: [ironHP, calciumHP], enabled: false),
        InteractionRule(
            id: "spacing.zinc-iron", version: 1, kind: .spacing, severity: .caution,
            ingredients: ["iron", "zinc"], separationMinutes: 120,
            explanation: "Iron supplements can lower zinc absorption when taken at the same time. "
                + "Check your labels or ask a pharmacist.",
            sources: [zincHP, ironHP], enabled: false),
        InteractionRule(
            id: "spacing.zinc-magnesium", version: 1, kind: .spacing, severity: .info,
            ingredients: ["magnesium", "zinc"], separationMinutes: 120,
            explanation: "Very high doses of zinc can interfere with magnesium absorption. "
                + "Check your labels or ask a pharmacist.",
            sources: [magnesiumHP, zincHP], enabled: false),
        // Informational notes: shown on the detail screen only, never change timing.
        InteractionRule(
            id: "info.iron-calcium-foods", version: 1, kind: .informational, severity: .info,
            ingredients: ["iron"],
            explanation: "Some people take iron away from calcium-rich foods and drinks. "
                + "Check your label or ask a pharmacist.",
            sources: [ironConsumer, ironHP], enabled: true),
        InteractionRule(
            id: "info.calcium-forms", version: 1, kind: .informational, severity: .info,
            ingredients: ["calcium"],
            explanation: "Calcium carbonate is usually absorbed best with food, while calcium citrate works "
                + "with or without food. Your label says which form you have.",
            sources: [calciumConsumer, calciumHP], enabled: true),
    ]
}
