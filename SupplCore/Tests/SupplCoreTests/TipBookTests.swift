import XCTest
@testable import SupplCore

final class TipBookTests: XCTestCase {
    private func t(_ id: String, _ ingredients: [String] = []) -> Tip {
        Tip(id: id, text: "Tip \(id).", ingredients: ingredients, sourceURL: "https://ods.od.nih.gov/")
    }

    private var book: TipBook {
        TipBook(tips: [
            t("g1"), t("g2"), t("g3"), t("g4"), t("g5"),
            t("d1", ["vitamin-d"]), t("d2", ["vitamin-d", "calcium"]),
            t("i1", ["iron"]), t("i2", ["iron", "vitamin-c"]),
            t("m1", ["magnesium"]),
        ])
    }

    /// 2026-01-01 plus `n` days, built without a Calendar so the test is time-zone free.
    private func days(_ count: Int, from start: Day = Day(year: 2026, month: 1, day: 1)) -> [Day] {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return (0..<count).map { start.adding(days: $0, calendar: c) }
    }

    func testDayNumberMatchesUnixEpoch() {
        XCTAssertEqual(TipBook.dayNumber(Day(year: 1970, month: 1, day: 1)), 0)
        XCTAssertEqual(TipBook.dayNumber(Day(year: 1970, month: 1, day: 2)), 1)
        XCTAssertEqual(TipBook.dayNumber(Day(year: 1969, month: 12, day: 31)), -1)
        XCTAssertEqual(TipBook.dayNumber(Day(year: 2000, month: 3, day: 1)), 11_017)
        // Leap day and the day after.
        XCTAssertEqual(TipBook.dayNumber(Day(year: 2028, month: 3, day: 1)) - TipBook.dayNumber(Day(year: 2028, month: 2, day: 28)), 2)
        // Consecutive across a year boundary.
        XCTAssertEqual(TipBook.dayNumber(Day(year: 2027, month: 1, day: 1)) - TipBook.dayNumber(Day(year: 2026, month: 12, day: 31)), 1)
    }

    func testDeterministicForADay() {
        let day = Day(year: 2026, month: 10, day: 23)
        let a = book.tip(for: day, preferring: ["iron"])
        for _ in 0..<5 { XCTAssertEqual(book.tip(for: day, preferring: ["iron"]), a) }
        // Same answer from a separately built book with the tips in a different order.
        XCTAssertEqual(TipBook(tips: book.tips.reversed()).tip(for: day, preferring: ["iron"]), a)
    }

    func testPrefersRelevantTipsOnMostDays() {
        let picks = days(90).compactMap { book.tip(for: $0, preferring: ["iron", "vitamin-d"]) }
        let relevant = picks.filter { !$0.ingredients.isEmpty }
        XCTAssertGreaterThan(relevant.count, picks.count / 2)
        XCTAssertTrue(relevant.allSatisfy { !Set($0.ingredients).isDisjoint(with: ["iron", "vitamin-d"]) },
                      "never shows a tip for an ingredient the user doesn't take")
        XCTAssertTrue(picks.contains { $0.ingredients.isEmpty }, "general tips still appear")
        XCTAssertEqual(Set(relevant.map(\.id)), ["d1", "d2", "i1", "i2"], "every relevant tip gets a turn")
    }

    func testNeverRepeatsOnConsecutiveDays() {
        let prefs: [Set<String>] = [[], ["iron"], ["magnesium"], ["iron", "vitamin-d", "magnesium"], ["unknown-id"]]
        for p in prefs {
            let picks = days(400, from: Day(year: 2025, month: 12, day: 1)).map { book.tip(for: $0, preferring: p)!.id }
            for (a, b) in zip(picks, picks.dropFirst()) {
                XCTAssertNotEqual(a, b, "repeat for preferences \(p)")
            }
        }
    }

    func testSingleRelevantTipAlternatesWithGeneral() {
        let picks = days(30).map { book.tip(for: $0, preferring: ["magnesium"])!.id }
        XCTAssertEqual(picks.filter { $0 == "m1" }.count, 15)
        for (a, b) in zip(picks, picks.dropFirst()) { XCTAssertNotEqual(a, b) }
    }

    func testEmptyPreferenceSetShowsGeneralTipsOnly() {
        let picks = days(60).map { book.tip(for: $0, preferring: [])! }
        XCTAssertTrue(picks.allSatisfy(\.ingredients.isEmpty))
        XCTAssertEqual(Set(picks.map(\.id)), ["g1", "g2", "g3", "g4", "g5"])
    }

    func testUnknownIngredientsFallBackToGeneral() {
        let picks = days(20).map { book.tip(for: $0, preferring: ["not-in-catalog"])! }
        XCTAssertTrue(picks.allSatisfy(\.ingredients.isEmpty))
    }

    func testEmptyBookReturnsNil() {
        XCTAssertNil(TipBook(tips: []).tip(for: Day(year: 2026, month: 1, day: 1), preferring: ["iron"]))
    }

    func testOnlySpecificTipsStillReturnsSomething() {
        let only = TipBook(tips: [t("a", ["iron"]), t("b", ["zinc"])])
        XCTAssertNotNil(only.tip(for: Day(year: 2026, month: 1, day: 1), preferring: []))
        let picks = days(10).map { only.tip(for: $0, preferring: ["iron"])!.id }
        XCTAssertEqual(Set(picks), ["a"], "single relevant tip and no general ones: it's all we have")
    }

    func testOnlyGeneralTips() {
        let only = TipBook(tips: [t("a"), t("b")])
        let picks = days(10).map { only.tip(for: $0, preferring: ["iron"])!.id }
        XCTAssertEqual(picks.count, 10)
        for (a, b) in zip(picks, picks.dropFirst()) { XCTAssertNotEqual(a, b) }
    }

    func testBundledTipsRotateWithoutRepeats() throws {
        let book = try TipBook.decode(Data(contentsOf: CatalogContentTests.resource("tips.json")))
        for p: Set<String> in [[], ["vitamin-d"], ["iron", "calcium", "magnesium", "omega-3", "creatine"]] {
            let picks = days(366).map { book.tip(for: $0, preferring: p)!.id }
            for (a, b) in zip(picks, picks.dropFirst()) { XCTAssertNotEqual(a, b, "\(p)") }
        }
    }
}
