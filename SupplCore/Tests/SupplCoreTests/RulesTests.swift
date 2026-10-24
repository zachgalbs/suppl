import XCTest
@testable import SupplCore

final class RulesTests: XCTestCase {
    typealias F = EngineFixtures

    private func plan(_ catalogID: String?, _ moment: Moment = .breakfast) -> DosePlan {
        F.plan(catalogID ?? "manual", moment, catalogID: catalogID)
    }

    func testEveryRuleIsSourcedFromODSAndUnreviewed() {
        XCTAssertFalse(RuleBook.all.isEmpty)
        XCTAssertEqual(Set(RuleBook.all.map(\.id)).count, RuleBook.all.count, "rule ids are unique")
        for rule in RuleBook.all {
            XCTAssertFalse(rule.sources.isEmpty, rule.id)
            for source in rule.sources {
                XCTAssertTrue(source.hasPrefix("https://ods.od.nih.gov/factsheets/"), "\(rule.id): \(source)")
            }
            XCTAssertEqual(rule.reviewStatus, "unreviewed", rule.id)
            XCTAssertNil(rule.reviewer, rule.id)
            XCTAssertGreaterThanOrEqual(rule.version, 1)
            for id in rule.ingredients {
                XCTAssertNotNil(id.range(of: "^[a-z0-9]+(-[a-z0-9]+)*$", options: .regularExpression), id)
            }
        }
    }

    func testSpacingRulesShipDisabled() {
        let spacing = RuleBook.all.filter { $0.kind == .spacing }
        XCTAssertFalse(spacing.isEmpty)
        XCTAssertTrue(spacing.allSatisfy { !$0.enabled })
        // Only purely informational notes are on.
        XCTAssertTrue(RuleBook.all.filter(\.enabled).allSatisfy { $0.kind == .informational })
    }

    func testRuleTextPointsToTheLabelOrAPharmacistAndAvoidsDashes() {
        for rule in RuleBook.all {
            let text = rule.explanation
            XCTAssertFalse(text.contains("\u{2014}") || text.contains("\u{2013}"), rule.id)
            XCTAssertTrue(text.contains("label") || text.contains("pharmacist"), rule.id)
            XCTAssertFalse(text.lowercased().contains("you should take"), rule.id)
        }
    }

    func testDisabledRulesAreExcludedByDefault() {
        let plans = [plan("calcium"), plan("iron")]
        let ids = Set(RuleEvaluator.applicableRules(for: plans, rules: RuleBook.all).map(\.id))
        XCTAssertFalse(ids.contains("spacing.calcium-iron"))
        XCTAssertEqual(ids, ["info.iron-calcium-foods", "info.calcium-forms"])
        let all = Set(RuleEvaluator.applicableRules(for: plans, rules: RuleBook.all, includeDisabled: true).map(\.id))
        XCTAssertTrue(all.contains("spacing.calcium-iron"))
    }

    func testRuleNeedsEveryIngredient() {
        let ironOnly = RuleEvaluator.applicableRules(for: [plan("iron")], rules: RuleBook.all, includeDisabled: true)
        XCTAssertFalse(ironOnly.contains { $0.kind == .spacing })
        let zincIron = RuleEvaluator.applicableRules(for: [plan("zinc"), plan("iron", .dinner)], rules: RuleBook.all,
                                                     includeDisabled: true)
        XCTAssertTrue(zincIron.contains { $0.id == "spacing.zinc-iron" })
    }

    func testEnabledRuleIsMatched() {
        let custom = InteractionRule(id: "spacing.test", version: 1, kind: .spacing, severity: .caution,
                                     ingredients: ["calcium", "iron"], separationMinutes: 120, explanation: "x",
                                     sources: ["https://ods.od.nih.gov/factsheets/Iron-HealthProfessional/"], enabled: true)
        XCTAssertEqual(RuleEvaluator.applicableRules(for: [plan("iron"), plan("calcium")], rules: [custom]).map(\.id),
                       ["spacing.test"])
    }

    func testManualPlansMatchNothing() {
        XCTAssertTrue(RuleEvaluator.applicableRules(for: [plan(nil)], rules: RuleBook.all, includeDisabled: true).isEmpty)
        XCTAssertTrue(RuleEvaluator.notes(for: plan(nil), allPlans: [plan(nil), plan("iron")], rules: RuleBook.all).isEmpty)
    }

    func testNotesForAPlanAreEnabledAndInformational() {
        let iron = plan("iron")
        let all = [iron, plan("calcium"), plan("zinc")]
        XCTAssertEqual(RuleEvaluator.notes(for: iron, allPlans: all, rules: RuleBook.all).map(\.id), ["info.iron-calcium-foods"])
        XCTAssertTrue(RuleEvaluator.notes(for: plan("magnesium"), allPlans: all, rules: RuleBook.all).isEmpty)
    }

    func testMultiIngredientNoteShowsOnlyWhenBothArePresent() {
        let note = InteractionRule(id: "info.pair", version: 1, kind: .informational, severity: .info,
                                   ingredients: ["calcium", "iron"], explanation: "x", sources: [], enabled: true)
        XCTAssertTrue(RuleEvaluator.notes(for: plan("iron"), allPlans: [plan("iron")], rules: [note]).isEmpty)
        XCTAssertEqual(RuleEvaluator.notes(for: plan("iron"), allPlans: [plan("iron"), plan("calcium")], rules: [note]).count, 1)
    }

    func testEngineNeverSpacesDosesInV1() {
        // Calcium and iron at the same moment stay together at the usual time; no rule is improvised.
        let plans = [plan("calcium"), plan("iron")]
        let out = F.run(plans, prefs: F.pro(), now: F.at(6, 0))
        let breakfast = try! XCTUnwrap(out.decision(F.id(F.today, .breakfast)))
        XCTAssertEqual(breakfast.planIDs, ["calcium", "iron"])
        XCTAssertEqual(breakfast.fireDate, F.at(8, 0))
        XCTAssertEqual(out.filter { $0.day == F.today }.count, 1)
    }
}
