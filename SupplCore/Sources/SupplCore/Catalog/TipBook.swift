import Foundation

/// The daily tips (`Resources/tips.json`).
public struct TipBook: Sendable {
    public let tips: [Tip]

    public init(tips: [Tip]) {
        self.tips = tips
    }

    private struct File: Decodable {
        let version: Int
        let tips: [Tip]
    }

    /// Decodes tips.json: {"version": 1, "tips": [Tip...]}
    public static func decode(_ data: Data) throws -> TipBook {
        TipBook(tips: try JSONDecoder().decode(File.self, from: data).tips)
    }

    /// Deterministic for a given day. Prefers tips whose `ingredients` intersect `ingredientIDs` (most days), falls back to general tips, and rotates so the same tip doesn't repeat on consecutive days.
    ///
    /// Tips are laid out in a fixed cycle (two relevant, one general, repeat) and each day takes the next slot,
    /// so consecutive days always land on neighbouring slots, and neighbouring slots never hold the same tip.
    public func tip(for day: Day, preferring ingredientIDs: Set<String>) -> Tip? {
        let cycle = Self.cycle(tips, preferring: ingredientIDs)
        guard !cycle.isEmpty else { return nil }
        let n = Self.dayNumber(day) % cycle.count
        return cycle[n < 0 ? n + cycle.count : n]
    }

    static func cycle(_ tips: [Tip], preferring ids: Set<String>) -> [Tip] {
        let sorted = tips.sorted { $0.id < $1.id }
        let relevant = sorted.filter { !$0.ingredients.isEmpty && !ids.isDisjoint(with: $0.ingredients) }
        let general = sorted.filter { $0.ingredients.isEmpty }
        if relevant.isEmpty { return general.isEmpty ? sorted : general }
        if general.isEmpty { return relevant }
        if relevant.count == 1 {
            // r g r g … so the single relevant tip never lands on two days in a row.
            return general.flatMap { [relevant[0], $0] }
        }
        let blocks = max((relevant.count + 1) / 2, general.count)
        var out: [Tip] = []
        out.reserveCapacity(blocks * 3)
        for b in 0..<blocks {
            out.append(relevant[(2 * b) % relevant.count])
            out.append(relevant[(2 * b + 1) % relevant.count])
            out.append(general[b % general.count])
        }
        return out
    }

    /// Days since 1970-01-01 in the proleptic Gregorian calendar. Pure arithmetic, so it needs no `Calendar`
    /// and gives the same answer in every time zone.
    static func dayNumber(_ d: Day) -> Int {
        // Howard Hinnant's days_from_civil.
        let y = d.month <= 2 ? d.year - 1 : d.year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (d.month + 9) % 12
        let doy = (153 * mp + 2) / 5 + d.day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }
}
