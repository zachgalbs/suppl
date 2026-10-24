import Foundation

/// Text normalization and edit distance for catalog search. Kept separate so the rules are easy to test and tweak.
enum SearchText {
    /// Lowercased, diacritics folded, apostrophes dropped ("St. John's" → "st johns"),
    /// every other non-alphanumeric character treated as a space, runs of spaces collapsed.
    static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                               locale: Locale(identifier: "en_US_POSIX"))
        var out = ""
        var pendingSpace = false
        for ch in folded.lowercased() {
            if ch == "'" || ch == "\u{2019}" { continue }
            if ch.isLetter || ch.isNumber {
                if pendingSpace && !out.isEmpty { out.append(" ") }
                pendingSpace = false
                out.append(ch)
            } else {
                pendingSpace = true
            }
        }
        return out
    }

    /// `normalize` without spaces, so "omega 3" matches "omega3" and "b 12" matches "b12".
    static func compact(_ normalized: String) -> String {
        normalized.replacingOccurrences(of: " ", with: "")
    }

    /// Typos we tolerate for a query of this many characters. Short queries get none,
    /// so "zz" or "fe" never fuzzy-match something unrelated.
    static func maxTypos(forLength n: Int) -> Int {
        switch n {
        case ..<4: 0
        case 4...5: 1
        case 6...8: 2
        default: 3
        }
    }

    /// Optimal string alignment distance (Levenshtein plus adjacent transpositions, so "magnesuim" is one typo).
    /// Returns `limit + 1` as soon as the distance is known to exceed `limit`.
    static func distance(_ a: [Character], _ b: [Character], limit: Int) -> Int {
        if abs(a.count - b.count) > limit { return limit + 1 }
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prevPrev = [Int](repeating: 0, count: b.count + 1)
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            var rowMin = cur[0]
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                var v = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    v = min(v, prevPrev[j - 2] + 1)
                }
                cur[j] = v
                rowMin = min(rowMin, v)
            }
            if rowMin > limit { return limit + 1 }
            (prevPrev, prev, cur) = (prev, cur, prevPrev)
        }
        return prev[b.count]
    }
}
