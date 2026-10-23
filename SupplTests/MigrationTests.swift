import XCTest
import SwiftData
import SupplCore
@testable import suppl

/// Guards the persisted shapes that TestFlight installs already have on disk.
final class MigrationTests: XCTestCase {
    func testSlotRawValuesAndStorageKeysAreStable() {
        XCTAssertEqual(Slot.allCases.map(\.rawValue), ["wake", "breakfast", "lunch", "dinner", "bedtime", "postWorkout"])
        XCTAssertEqual(Slot.breakfast.storageKey, "time.breakfast")
    }

    func testEverySlotMapsToAMoment() {
        for slot in Slot.allCases {
            XCTAssertNotNil(Moment(rawValue: slot.rawValue), slot.rawValue)
        }
    }

    func testReminderIdentifiersAreStable() {
        XCTAssertEqual(Reminders.category, "SUPPL_REMINDER")
        XCTAssertEqual(Reminders.followUpCategory, "SUPPL_FOLLOWUP")
        XCTAssertEqual([Reminders.takenAction, Reminders.snoozeAction, Reminders.skipAction], ["TAKEN", "SNOOZE", "SKIP"])
    }

    @MainActor
    func testNewSupplementPropertiesHaveDefaultsAndIDsBackfill() throws {
        let container = try ModelContainer(for: Supplement.self, DoseLog.self, DecisionLog.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let s = Supplement(name: "Vitamin D")
        s.uid = nil // what a pre-v1 row looks like
        context.insert(s)
        XCTAssertEqual(s.frequencyRaw, "daily")
        XCTAssertTrue(s.takesEveryDay)
        XCTAssertFalse(s.clinicianDirected)

        Supplement.backfillIDs(in: context)
        let id = try XCTUnwrap(s.uid)
        Supplement.backfillIDs(in: context)
        XCTAssertEqual(s.uid, id, "backfill must not change an existing id")
    }
}
