import XCTest
@testable import SupplCore

/// Search and best-match behaviour, run against the real bundled catalog so content and logic are tested together.
final class CatalogSearchTests: XCTestCase {
    private static let catalog: Catalog = {
        let url = CatalogContentTests.resource("catalog.json")
        return try! Catalog.decode(Data(contentsOf: url))
    }()

    private var catalog: Catalog { Self.catalog }

    private func top(_ q: String) -> String? { catalog.search(q).first?.id }
    private func ids(_ q: String, limit: Int = 20) -> [String] { catalog.search(q, limit: limit).map(\.id) }

    // MARK: - Normalization

    func testNormalizeFoldsCaseDiacriticsAndPunctuation() {
        XCTAssertEqual(SearchText.normalize("  Vitamín   D3!! "), "vitamin d3")
        XCTAssertEqual(SearchText.normalize("St. John’s Wort"), "st johns wort")
        XCTAssertEqual(SearchText.normalize("Omega-3 (Fish Oil)"), "omega 3 fish oil")
        XCTAssertEqual(SearchText.normalize("D3+K2"), "d3 k2")
        XCTAssertEqual(SearchText.normalize("---"), "")
    }

    func testEditDistanceCountsTranspositionAsOne() {
        func d(_ a: String, _ b: String, _ limit: Int = 5) -> Int { SearchText.distance(Array(a), Array(b), limit: limit) }
        XCTAssertEqual(d("magnesuim", "magnesium"), 1)
        XCTAssertEqual(d("tumeric", "turmeric"), 1)
        XCTAssertEqual(d("creatin", "creatine"), 1)
        XCTAssertEqual(d("", "abc"), 3)
        XCTAssertEqual(d("kitten", "sitting"), 3)
        XCTAssertEqual(d("abcdef", "uvwxyz", 2), 3, "stops at limit + 1")
    }

    // MARK: - Search

    func testCaseInsensitive() {
        XCTAssertEqual(top("MAGNESIUM"), "magnesium")
        XCTAssertEqual(top("vitamin c"), "vitamin-c")
        XCTAssertEqual(top("ViTaMiN b12"), "vitamin-b12")
    }

    func testDiacriticInsensitive() {
        XCTAssertEqual(top("vitamine D"), "vitamin-d")
        XCTAssertEqual(top("Vitamín D"), "vitamin-d")
        XCTAssertEqual(top("échinacea"), "echinacea")
        XCTAssertTrue(ids("Vitamín").contains("vitamin-d"))
        XCTAssertTrue(ids("Vitamín").allSatisfy { catalog.entry(id: $0)!.name.lowercased().contains("vitamin") || catalog.entry(id: $0)!.synonyms.contains { $0.contains("vitamin") } })
    }

    func testPunctuationAndSpacingIgnored() {
        XCTAssertEqual(top("omega3"), "omega-3")
        XCTAssertEqual(top("Omega - 3"), "omega-3")
        XCTAssertEqual(top("b-12"), "vitamin-b12")
        XCTAssertEqual(top("  co   q10 "), "coq10")
        XCTAssertEqual(top("st johns wort"), "st-johns-wort")
        XCTAssertEqual(top("St. John's Wort"), "st-johns-wort")
    }

    func testSynonyms() {
        XCTAssertEqual(top("cholecalciferol"), "vitamin-d")
        XCTAssertEqual(top("fish oil"), "omega-3")
        XCTAssertEqual(top("EPA/DHA"), "omega-3")
        XCTAssertEqual(top("ascorbic acid"), "vitamin-c")
        XCTAssertEqual(top("magnesium glycinate"), "magnesium")
        XCTAssertEqual(top("whey"), "protein-powder")
        XCTAssertEqual(top("psyllium husk"), "fiber")
        XCTAssertEqual(top("curcumin"), "turmeric")
        XCTAssertEqual(top("folic acid"), "folate")
        XCTAssertEqual(top("D3"), "vitamin-d")
    }

    func testMisspellingsListedAsSynonyms() {
        XCTAssertEqual(top("magnesuim"), "magnesium")
        XCTAssertEqual(top("ashwaganda"), "ashwagandha")
        XCTAssertEqual(top("creatin"), "creatine")
        XCTAssertEqual(top("tumeric"), "turmeric")
        XCTAssertEqual(top("probiotec"), "probiotic")
    }

    /// Typos nobody listed still land, through edit distance.
    func testUnlistedTyposFoundByFuzzyMatch() {
        XCTAssertEqual(top("melatonen"), "melatonin")
        XCTAssertEqual(top("glucosamne"), "glucosamine")
        XCTAssertEqual(top("ashwagnadha"), "ashwagandha")
        XCTAssertEqual(top("seleneum"), "selenium")
        XCTAssertEqual(top("vitamn d"), "vitamin-d")
        XCTAssertEqual(top("magneseum"), "magnesium")
    }

    func testRankingExactBeforePrefixBeforeFuzzy() {
        // "vitamin e" is exact for vitamin E and one typo from vitamin D, C, A, K.
        let r = ids("vitamin e")
        XCTAssertEqual(r.first, "vitamin-e")
        XCTAssertTrue(r.contains("vitamin-d"), "fuzzy neighbours still listed, just later")
        // "d3": exact synonym of vitamin D beats the prefix match on "d3 k2".
        let d3 = ids("d3")
        XCTAssertEqual(d3.first, "vitamin-d")
        XCTAssertLessThan(d3.firstIndex(of: "vitamin-d")!, d3.firstIndex(of: "vitamin-d3-k2")!)
        // Prefix of a name ranks above a substring hit inside another entry.
        let mag = ids("magn")
        XCTAssertEqual(mag.first, "magnesium")
    }

    func testExactMatchBeatsFuzzyNeighbour() {
        // "zinc" is exact; "zink" is a listed misspelling of zinc too, so nothing else should outrank it.
        XCTAssertEqual(top("zinc"), "zinc")
        XCTAssertEqual(top("iron"), "iron")
        XCTAssertEqual(top("iodine"), "iodine")
    }

    func testPrefixWhileTyping() {
        XCTAssertEqual(top("mela"), "melatonin")
        XCTAssertEqual(top("creat"), "creatine")
        XCTAssertEqual(top("ashw"), "ashwagandha")
        XCTAssertTrue(ids("vit").count >= 10)
    }

    func testEmptyAndWhitespaceQueryReturnsNothing() {
        XCTAssertEqual(catalog.search(""), [])
        XCTAssertEqual(catalog.search("   "), [])
        XCTAssertEqual(catalog.search("\n\t"), [])
        XCTAssertEqual(catalog.search("?!-"), [])
    }

    func testLimit() {
        XCTAssertEqual(catalog.search("vitamin", limit: 3).count, 3)
        XCTAssertEqual(catalog.search("vitamin", limit: 0), [])
        XCTAssertLessThanOrEqual(catalog.search("a").count, 20, "default limit is 20")
    }

    func testNoAbsurdFuzzyMatchesForShortQueries() {
        XCTAssertEqual(ids("zz"), [])
        XCTAssertEqual(ids("qx"), [])
        XCTAssertEqual(ids("xyz"), [])
        XCTAssertEqual(ids("qqqq"), [])
        XCTAssertEqual(ids("Mystery Blend"), [])
        XCTAssertEqual(ids("pizza"), [])
    }

    func testResultsHaveNoDuplicates() {
        for q in ["vitamin", "oil", "b", "mag", "fish oil", "d3"] {
            let r = ids(q)
            XCTAssertEqual(r.count, Set(r).count, q)
        }
    }

    // MARK: - Best match

    func testBestMatchExactNamesAndSynonyms() {
        XCTAssertEqual(catalog.bestMatch(forName: "Vitamin D3")?.id, "vitamin-d")
        XCTAssertEqual(catalog.bestMatch(forName: "Fish Oil")?.id, "omega-3")
        XCTAssertEqual(catalog.bestMatch(forName: "magnesium")?.id, "magnesium")
        XCTAssertEqual(catalog.bestMatch(forName: "Creatine Monohydrate")?.id, "creatine")
        XCTAssertEqual(catalog.bestMatch(forName: "Vitamin D3 + K2")?.id, "vitamin-d3-k2")
    }

    func testBestMatchFindsIngredientInsideProductName() {
        XCTAssertEqual(catalog.bestMatch(forName: "Kirkland Fish Oil 1200mg")?.id, "omega-3")
        XCTAssertEqual(catalog.bestMatch(forName: "Nature's Vitamin D3 5000 IU softgels")?.id, "vitamin-d")
        XCTAssertEqual(catalog.bestMatch(forName: "Magnesium Glycinate 400")?.id, "magnesium")
        XCTAssertEqual(catalog.bestMatch(forName: "Sports Research D3 + K2 drops")?.id, "vitamin-d3-k2")
    }

    func testBestMatchToleratesSmallTypo() {
        XCTAssertEqual(catalog.bestMatch(forName: "Melatonen")?.id, "melatonin")
        XCTAssertEqual(catalog.bestMatch(forName: "glucosamne")?.id, "glucosamine")
    }

    func testBestMatchReturnsNilWhenNotConfident() {
        XCTAssertNil(catalog.bestMatch(forName: "Mystery Blend"))
        XCTAssertNil(catalog.bestMatch(forName: ""))
        XCTAssertNil(catalog.bestMatch(forName: "   "))
        XCTAssertNil(catalog.bestMatch(forName: "Vitamin"), "a prefix of many entries is ambiguous")
        XCTAssertNil(catalog.bestMatch(forName: "Calcium with Vitamin D"), "two different ingredients")
        XCTAssertNil(catalog.bestMatch(forName: "vitamin x"), "one typo from several vitamins")
        XCTAssertNil(catalog.bestMatch(forName: "zz"))
    }

    // MARK: - Lookup

    func testEntryByID() {
        XCTAssertEqual(catalog.entry(id: "omega-3")?.name, "Omega-3 (Fish Oil)")
        XCTAssertNil(catalog.entry(id: "nope"))
    }

    func testSmallInMemoryCatalog() {
        let c = Catalog(entries: [
            CatalogEntry(id: "a", name: "Alpha", synonyms: ["first"], category: "x", typicalUnits: ["mg"], note: "n", sources: ["https://x"]),
            CatalogEntry(id: "b", name: "Alphabet", category: "x", typicalUnits: ["mg"], note: "n", sources: ["https://x"]),
        ])
        XCTAssertEqual(c.search("alpha").map(\.id), ["a", "b"])
        XCTAssertEqual(c.search("first").map(\.id), ["a"])
        XCTAssertEqual(c.bestMatch(forName: "Alpha")?.id, "a")
        XCTAssertEqual(Catalog(entries: []).search("alpha"), [])
    }
}
