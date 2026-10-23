import Foundation

/// The bundled ingredient catalog (`Resources/catalog.json`) and its search.
/// General ingredients only: the catalog never knows the user's exact product.
public struct Catalog: Sendable {
    public let entries: [CatalogEntry]
    private let byID: [String: Int]
    private let index: [[Term]]

    /// One searchable name or synonym, pre-normalized.
    struct Term: Sendable {
        let text: String
        let compact: String
        let chars: [Character]
        let words: [String]
        let isName: Bool

        init(_ raw: String, isName: Bool) {
            text = SearchText.normalize(raw)
            compact = SearchText.compact(text)
            chars = Array(compact)
            words = text.split(separator: " ").map(String.init)
            self.isName = isName
        }
    }

    public init(entries: [CatalogEntry]) {
        self.entries = entries
        var byID: [String: Int] = [:]
        for (i, e) in entries.enumerated() where byID[e.id] == nil { byID[e.id] = i }
        self.byID = byID
        index = entries.map { e in
            ([Term(e.name, isName: true)] + e.synonyms.map { Term($0, isName: false) }).filter { !$0.text.isEmpty }
        }
    }

    private struct File: Decodable {
        let version: Int
        let entries: [CatalogEntry]
    }

    /// Decodes catalog.json: {"version": 1, "entries": [CatalogEntry...]}
    public static func decode(_ data: Data) throws -> Catalog {
        Catalog(entries: try JSONDecoder().decode(File.self, from: data).entries)
    }

    public func entry(id: String) -> CatalogEntry? {
        byID[id].map { entries[$0] }
    }

    // MARK: - Search

    /// How a term matched, best first. Raw values order the results.
    enum Tier: Int, Comparable {
        case exact, prefix, wordPrefix, substring, fuzzy
        static func < (a: Tier, b: Tier) -> Bool { a.rawValue < b.rawValue }
    }

    struct Match: Comparable {
        let tier: Tier
        let typos: Int
        let isName: Bool

        static func < (a: Match, b: Match) -> Bool {
            if a.tier != b.tier { return a.tier < b.tier }
            if a.typos != b.typos { return a.typos < b.typos }
            return a.isName && !b.isName
        }
    }

    /// Name + synonym search. Case- and diacritic-insensitive, ignores punctuation/extra spaces, typo-tolerant (simple edit distance scaled to query length). Best matches first: exact > prefix > substring > fuzzy. Empty query → [].
    public func search(_ query: String, limit: Int = 20) -> [CatalogEntry] {
        guard limit > 0 else { return [] }
        let q = Term(query, isName: false)
        guard !q.text.isEmpty else { return [] }
        let ranked: [(index: Int, match: Match)] = index.indices.compactMap { i in
            index[i].compactMap { match(q, $0) }.min().map { (index: i, match: $0) }
        }
        return ranked
            .sorted { a, b in
                if a.match != b.match { return a.match < b.match }
                let (ea, eb) = (entries[a.index], entries[b.index])
                if ea.name.count != eb.name.count { return ea.name.count < eb.name.count }
                return ea.name < eb.name
            }
            .prefix(limit)
            .map { entries[$0.index] }
    }

    func match(_ q: Term, _ t: Term) -> Match? {
        let m = { (tier: Tier, typos: Int) in Match(tier: tier, typos: typos, isName: t.isName) }
        if q.text == t.text || q.compact == t.compact { return m(.exact, 0) }
        if t.text.hasPrefix(q.text) || t.compact.hasPrefix(q.compact) { return m(.prefix, 0) }
        if t.words.contains(where: { $0.hasPrefix(q.text) }) { return m(.wordPrefix, 0) }
        if q.compact.count >= 3, t.compact.contains(q.compact) { return m(.substring, 0) }

        let limit = SearchText.maxTypos(forLength: q.chars.count)
        guard limit > 0 else { return nil }
        // Whole term ("magnesuim" → "magnesium"), each word ("tumeric" → "turmeric"),
        // and the start of the term while the user is still typing ("vitamn" → "vitamin d").
        var best = SearchText.distance(q.chars, t.chars, limit: limit)
        if q.words.count == 1 {
            for w in t.words where w.count >= 4 {
                best = min(best, SearchText.distance(q.chars, Array(w), limit: limit))
            }
        }
        let prefixLimit = min(limit, 1)
        for len in max(1, q.chars.count - 1)...(q.chars.count + 1) where len < t.chars.count {
            let d = SearchText.distance(q.chars, Array(t.chars.prefix(len)), limit: prefixLimit)
            if d <= prefixLimit { best = min(best, d) }
        }
        return best <= limit ? m(.fuzzy, best) : nil
    }

    // MARK: - Best match

    /// For mapping a name the user already typed (e.g. "Vitamin D3", "fish oil") to an entry, or nil if not confident.
    ///
    /// Confident means one of, in order:
    /// 1. the whole name equals a catalog name or synonym;
    /// 2. the name contains catalog terms as whole words ("Kirkland Fish Oil 1200mg") and they all point to one entry,
    ///    ignoring terms that sit inside a longer matched term ("D3" inside "Vitamin D3 K2");
    /// 3. the name is a small typo away from exactly one entry.
    public func bestMatch(forName name: String) -> CatalogEntry? {
        let q = Term(name, isName: false)
        guard !q.text.isEmpty else { return nil }

        let exact = Set(index.indices.filter { i in index[i].contains { $0.text == q.text || $0.compact == q.compact } })
        if exact.count == 1, let i = exact.first { return entries[i] }
        if exact.count > 1 { return nil }

        if let i = containedMatch(q) { return entries[i] }

        let limit = min(SearchText.maxTypos(forLength: q.chars.count), q.chars.count >= 9 ? 2 : 1)
        guard q.chars.count >= 5 else { return nil }
        var bestDistance = limit + 1
        var bestEntries = Set<Int>()
        for i in index.indices {
            for t in index[i] {
                let d = SearchText.distance(q.chars, t.chars, limit: limit)
                if d < bestDistance { bestDistance = d; bestEntries = [i] }
                else if d == bestDistance { bestEntries.insert(i) }
            }
        }
        guard bestDistance <= limit, bestEntries.count == 1, let i = bestEntries.first else { return nil }
        return entries[i]
    }

    private func containedMatch(_ q: Term) -> Int? {
        struct Span { let entry: Int; let start: Int; let end: Int }
        var spans: [Span] = []
        for i in index.indices {
            for t in index[i] where !t.words.isEmpty && t.words.count <= q.words.count {
                for start in 0...(q.words.count - t.words.count)
                where Array(q.words[start..<(start + t.words.count)]) == t.words {
                    spans.append(Span(entry: i, start: start, end: start + t.words.count))
                }
            }
        }
        let outer = spans.filter { s in
            !spans.contains { o in
                o.start <= s.start && o.end >= s.end && (o.end - o.start) > (s.end - s.start)
            }
        }
        let found = Set(outer.map(\.entry))
        return found.count == 1 ? found.first : nil
    }
}
