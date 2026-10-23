import Foundation
import SupplCore

/// The bundled catalog and tips. If a file is missing or malformed the app still works, just without that content.
enum Content {
    static let catalog: Catalog? = load("catalog", Catalog.decode)
    static let tips: TipBook? = load("tips", TipBook.decode)

    /// Alphabetical, for the search screen before anything is typed.
    static var allEntries: [CatalogEntry] {
        (catalog?.entries ?? []).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func search(_ query: String) -> [CatalogEntry] {
        catalog?.search(query) ?? []
    }

    static func entry(id: String?) -> CatalogEntry? {
        guard let id else { return nil }
        return catalog?.entry(id: id)
    }

    static func bestMatch(forName name: String) -> CatalogEntry? {
        catalog?.bestMatch(forName: name)
    }

    static func tip(for day: Day, preferring ids: Set<String>) -> Tip? {
        tips?.tip(for: day, preferring: ids)
    }

    private static func load<T>(_ name: String, _ decode: (Data) throws -> T) -> T? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? decode(data)
    }
}
