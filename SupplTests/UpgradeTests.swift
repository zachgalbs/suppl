import XCTest
import SwiftData
@testable import suppl

/// The shape `Supplement` had on main before v1, copied exactly. Only used to write an old store to disk.
enum V0 {
    @Model
    final class Supplement {
        var name: String
        var brand: String
        var dose: Double
        var unit: String
        var slotRaw: String
        var withFood: Bool
        var createdAt: Date
        var lastTakenAt: Date?

        init(name: String) {
            self.name = name
            self.brand = "Acme"
            self.dose = 2
            self.unit = "capsule"
            self.slotRaw = "dinner"
            self.withFood = true
            self.createdAt = .now
            self.lastTakenAt = nil
        }
    }
}

/// TestFlight installs have a pre-v1 store on disk. Opening it with the v1 schema must keep every row.
@MainActor
final class UpgradeTests: XCTestCase {
    func testPreV1StoreOpensWithTheV1Schema() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("default.store")

        do {
            let old = try ModelContainer(for: Schema([V0.Supplement.self]),
                                         configurations: ModelConfiguration(url: url))
            old.mainContext.insert(V0.Supplement(name: "Magnesium"))
            old.mainContext.insert(V0.Supplement(name: "Fish oil"))
            try old.mainContext.save()
        }

        let new = try ModelContainer(for: Schema([Supplement.self, DoseLog.self, DecisionLog.self]),
                                     configurations: ModelConfiguration(url: url))
        let context = new.mainContext
        let rows = try context.fetch(FetchDescriptor<Supplement>(sortBy: [SortDescriptor(\.name)]))
        XCTAssertEqual(rows.map(\.name), ["Fish oil", "Magnesium"])
        XCTAssertEqual(rows.first?.brand, "Acme")
        XCTAssertEqual(rows.first?.slot, .dinner)
        XCTAssertEqual(rows.first?.frequencyRaw, "daily")
        XCTAssertFalse(rows.first?.clinicianDirected ?? true)
        XCTAssertNil(rows.first?.uid)

        Supplement.backfillIDs(in: context)
        XCTAssertEqual(Set(rows.compactMap(\.uid)).count, 2, "each old row gets its own id")
    }
}
