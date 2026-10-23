import XCTest
@testable import SupplCore

/// Validates the actual bundled `Suppl/Resources/catalog.json` and `tips.json`.
/// These files are read by a clinician and a lawyer; the checks here keep the mechanical rules from drifting.
final class CatalogContentTests: XCTestCase {
    /// The repo root is three directories above this test folder (SupplCore/Tests/SupplCoreTests).
    static func resource(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SupplCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // SupplCore
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("Suppl/Resources/\(name)")
    }

    /// Mirrors `Supplement.units` in Suppl/Models.swift.
    static let appUnits: Set<String> = ["capsule", "tablet", "softgel", "gummy", "scoop", "mg", "mcg", "g", "IU", "mL", "drops"]

    /// Ids another agent's rules reference by name.
    static let requiredIDs = ["vitamin-d", "vitamin-b12", "iron", "calcium", "magnesium", "zinc",
                              "omega-3", "creatine", "melatonin", "probiotic"]

    private static let catalog = try! Catalog.decode(Data(contentsOf: resource("catalog.json")))
    private static let tipBook = try! TipBook.decode(Data(contentsOf: resource("tips.json")))

    private var entries: [CatalogEntry] { Self.catalog.entries }
    private var tips: [Tip] { Self.tipBook.tips }

    // MARK: - Shared copy rules

    /// Returns the reason a piece of user-facing copy breaks the content rules, or nil.
    static func copyProblem(_ text: String) -> String? {
        if text.contains("\u{2014}") { return "em dash" }
        if text.contains("\u{2013}") { return "en dash" }
        if text.contains("!") { return "exclamation mark" }
        let lower = text.lowercased()
        if lower.replacingOccurrences(of: "don't double up", with: "").contains("double") { return "\"double\"" }
        if lower.contains("twice the dose") { return "\"twice the dose\"" }
        for word in ["cure", "cures", "treat", "treats", "treatment", "prevent", "prevents", "boost", "boosts",
                     "detox", "guaranteed", "miracle", "diagnose", "deficient", "deficiency", "you need to take", "you should take"] {
            let words = Set(lower.split { !$0.isLetter && $0 != "'" }.map(String.init))
            if word.contains(" ") ? lower.contains(word) : words.contains(word) { return "\"\(word)\"" }
        }
        return nil
    }

    /// Sentences end in "." or "?". "St." in "St. John's wort" is an abbreviation, not an ending.
    static func sentenceCount(_ text: String) -> Int {
        text.replacingOccurrences(of: "St. ", with: "St ")
            .split { ".?".contains($0) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
    }

    func testCopyRuleCatchesBadText() {
        XCTAssertNotNil(Self.copyProblem("Take it now — really"))
        XCTAssertNotNil(Self.copyProblem("Missed one? Take a double dose."))
        XCTAssertNotNil(Self.copyProblem("It boosts immunity."))
        XCTAssertNotNil(Self.copyProblem("Great for you!"))
        XCTAssertNil(Self.copyProblem("Missed one? Follow your label or ask a pharmacist. Don't double up."))
    }

    // MARK: - Catalog

    func testCatalogDecodesWithVersion() throws {
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: Self.resource("catalog.json"))) as! [String: Any]
        XCTAssertEqual(raw["version"] as? Int, 1)
        XCTAssertEqual(Set(raw.keys), ["version", "entries"])
    }

    func testCatalogSize() {
        XCTAssertGreaterThanOrEqual(entries.count, 50)
        XCTAssertLessThanOrEqual(entries.count, 80)
    }

    func testIDsAreUniqueAndWellFormed() {
        let ids = entries.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "duplicate ids")
        for id in ids {
            XCTAssertNotNil(id.range(of: "^[a-z0-9]+(-[a-z0-9]+)*$", options: .regularExpression), "id \(id)")
        }
    }

    func testRequiredIDsExist() {
        for id in Self.requiredIDs {
            XCTAssertNotNil(Self.catalog.entry(id: id), "missing \(id)")
        }
    }

    func testEveryEntryIsSourcedAndUnreviewed() {
        for e in entries {
            XCTAssertFalse(e.sources.isEmpty, "\(e.id) has no sources")
            for s in e.sources {
                XCTAssertTrue(s.hasPrefix("https://"), "\(e.id) source \(s)")
                XCTAssertNotNil(URL(string: s), "\(e.id) source \(s)")
            }
            XCTAssertEqual(Set(e.sources).count, e.sources.count, "\(e.id) duplicate source")
            XCTAssertEqual(e.reviewStatus, "unreviewed", e.id)
            XCTAssertNil(e.lastReviewed, e.id)
        }
    }

    func testSourcesAreAuthoritative() {
        let hosts = ["ods.od.nih.gov", "www.nccih.nih.gov", "medlineplus.gov", "www.fda.gov", "www.nei.nih.gov", "www.nia.nih.gov"]
        for e in entries {
            for s in e.sources + [e.odsURL].compactMap({ $0 }) {
                XCTAssertTrue(hosts.contains(URL(string: s)?.host ?? ""), "\(e.id): \(s)")
            }
        }
    }

    func testODSAndExamineLinksHaveTheRightShape() {
        for e in entries {
            if let ods = e.odsURL {
                XCTAssertNotNil(ods.range(of: "^https://ods\\.od\\.nih\\.gov/factsheets/[A-Za-z0-9]+-(Consumer|HealthProfessional)/$",
                                          options: .regularExpression), "\(e.id): \(ods)")
                XCTAssertTrue(e.sources.contains(ods), "\(e.id): odsURL should also be listed in sources")
            }
            if let ex = e.examineURL {
                XCTAssertTrue(ex.hasPrefix("https://examine.com/supplements/"), "\(e.id): \(ex)")
            }
        }
    }

    func testUnitsComeFromTheAppList() {
        for e in entries {
            XCTAssertFalse(e.typicalUnits.isEmpty, e.id)
            XCTAssertEqual(Set(e.typicalUnits).count, e.typicalUnits.count, "\(e.id) duplicate unit")
            for u in e.typicalUnits {
                XCTAssertTrue(Self.appUnits.contains(u), "\(e.id) unit \(u)")
            }
        }
    }

    func testNamesSynonymsAndCategories() {
        var seenNames = Set<String>()
        for e in entries {
            XCTAssertFalse(e.name.isEmpty, e.id)
            XCTAssertFalse(e.category.isEmpty, e.id)
            XCTAssertTrue(seenNames.insert(SearchText.normalize(e.name)).inserted, "duplicate name \(e.name)")
            for s in e.synonyms {
                XCTAssertGreaterThanOrEqual(SearchText.normalize(s).count, 2, "\(e.id) synonym \"\(s)\" too short to search")
            }
        }
    }

    /// A synonym that belongs to two entries makes search and best-match ambiguous.
    func testSynonymsDoNotCollideAcrossEntries() {
        var owner: [String: String] = [:]
        for e in entries {
            for term in Set(([e.name] + e.synonyms).map(SearchText.normalize)) {
                if let other = owner[term] { XCTFail("\"\(term)\" is in both \(other) and \(e.id)") }
                owner[term] = e.id
            }
        }
    }

    func testNotesFollowTheCopyRules() {
        for e in entries {
            XCTAssertFalse(e.note.isEmpty, e.id)
            if let problem = Self.copyProblem(e.note) { XCTFail("\(e.id) note: \(problem)") }
            XCTAssertLessThanOrEqual(Self.sentenceCount(e.note), 2, "\(e.id) note is longer than two sentences")
            XCTAssertTrue(e.note.hasSuffix("."), "\(e.id) note should end with a period")
            XCTAssertNil(e.note.range(of: "[0-9]+ ?(mg|mcg|IU|g)\\b", options: .regularExpression), "\(e.id) note mentions an amount")
        }
    }

    func testSuggestedMomentsStayConservative() {
        // Only a few conventions are allowed to prefill a moment; everything else is left to the user.
        let allowed: Set<Moment> = [.breakfast, .bedtime, .postWorkout]
        for e in entries {
            if let m = e.suggestedMoment { XCTAssertTrue(allowed.contains(m), "\(e.id) suggests \(m)") }
        }
        XCTAssertEqual(Self.catalog.entry(id: "melatonin")?.suggestedMoment, .bedtime)
        XCTAssertEqual(Self.catalog.entry(id: "creatine")?.suggestedMoment, .postWorkout)
    }

    func testJSONKeysMatchContract() throws {
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: Self.resource("catalog.json"))) as! [String: Any]
        let expected: Set<String> = ["id", "name", "synonyms", "category", "typicalUnits", "withFoodHint", "suggestedMoment",
                                     "note", "odsURL", "examineURL", "sources", "reviewStatus", "lastReviewed"]
        for e in raw["entries"] as! [[String: Any]] {
            XCTAssertEqual(Set(e.keys), expected, "\(e["id"] ?? "?")")
        }
    }

    // MARK: - Tips

    func testTipsDecodeWithVersion() throws {
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: Self.resource("tips.json"))) as! [String: Any]
        XCTAssertEqual(raw["version"] as? Int, 1)
        XCTAssertEqual(Set(raw.keys), ["version", "tips"])
        for t in raw["tips"] as! [[String: Any]] {
            XCTAssertEqual(Set(t.keys), ["id", "text", "ingredients", "sourceURL", "reviewStatus"], "\(t["id"] ?? "?")")
        }
    }

    func testAtLeastThirtyTips() {
        XCTAssertGreaterThanOrEqual(tips.count, 30)
    }

    func testTipIDsUnique() {
        XCTAssertEqual(tips.count, Set(tips.map(\.id)).count)
    }

    func testEveryTipIsSourcedAndUnreviewed() {
        for t in tips {
            XCTAssertTrue(t.sourceURL.hasPrefix("https://"), "\(t.id): \(t.sourceURL)")
            XCTAssertNotNil(URL(string: t.sourceURL), t.id)
            XCTAssertEqual(t.reviewStatus, "unreviewed", t.id)
        }
    }

    func testTipIngredientsExistInCatalog() {
        for t in tips {
            for id in t.ingredients {
                XCTAssertNotNil(Self.catalog.entry(id: id), "\(t.id) references unknown ingredient \(id)")
            }
        }
    }

    func testTipsFollowTheCopyRules() {
        for t in tips {
            if let problem = Self.copyProblem(t.text) { XCTFail("\(t.id): \(problem)") }
            XCTAssertLessThanOrEqual(Self.sentenceCount(t.text), 3, "\(t.id) is too long")
        }
    }

    /// Missed-dose copy must point to the label or a pharmacist.
    func testMissedDoseTipsPointToLabelOrPharmacist() {
        let missed = tips.filter { $0.text.lowercased().contains("missed") || $0.text.lowercased().contains("forgot") }
        XCTAssertFalse(missed.isEmpty)
        for t in missed {
            let lower = t.text.lowercased()
            XCTAssertTrue(lower.contains("label") || lower.contains("pharmacist"), t.id)
        }
    }

    /// Zach's original tips are kept (one rephrased for configurable reminder styles).
    func testZachsOriginalTipsAreKept() {
        let texts = Set(tips.map(\.text))
        for original in [
            "Keeping your bottles where you eat makes them easier to remember.",
            "Missed one? Follow your label or ask a pharmacist. Don't double up.",
            "Some supplements are better absorbed with food. Your label usually says.",
            "A consistent time each day tends to stick better than a perfect time.",
            "Bringing a new supplement into the mix? It's worth a quick check with your pharmacist.",
            "Check expiration dates now and then, especially for probiotics and oils.",
        ] {
            XCTAssertTrue(texts.contains(original), original)
        }
        XCTAssertFalse(texts.contains("Snooze is there for busy moments. One follow-up, then we'll leave you be."),
                       "intensity is configurable now, so the fixed one-follow-up promise is out of date")
    }

    func testBundledTipsMixGeneralAndSpecific() {
        XCTAssertGreaterThanOrEqual(tips.filter(\.ingredients.isEmpty).count, 15)
        XCTAssertGreaterThanOrEqual(tips.filter { !$0.ingredients.isEmpty }.count, 10)
    }
}
