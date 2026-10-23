import Foundation
import SwiftData

/// A moment in the day a supplement is tied to. Reminders fire at the user's usual time for each slot.
enum Slot: String, CaseIterable, Codable, Identifiable {
    case wake, breakfast, lunch, dinner, bedtime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wake: "On waking"
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        case .bedtime: "Before bed"
        }
    }

    var symbol: String {
        switch self {
        case .wake: "sunrise"
        case .breakfast: "cup.and.saucer"
        case .lunch: "fork.knife"
        case .dinner: "moon.stars"
        case .bedtime: "bed.double"
        }
    }

    var isMeal: Bool { [.breakfast, .lunch, .dinner].contains(self) }

    /// Default time as minutes after midnight.
    var defaultMinutes: Int {
        switch self {
        case .wake: 7 * 60
        case .breakfast: 8 * 60
        case .lunch: 12 * 60 + 30
        case .dinner: 18 * 60 + 30
        case .bedtime: 22 * 60
        }
    }

    var storageKey: String { "time.\(rawValue)" }

    var minutes: Int {
        let stored = UserDefaults.standard.object(forKey: storageKey) as? Int
        return stored ?? defaultMinutes
    }
}

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

    init(name: String, brand: String = "", dose: Double = 1, unit: String = "capsule",
         slot: Slot = .breakfast, withFood: Bool = true) {
        self.name = name
        self.brand = brand
        self.dose = dose
        self.unit = unit
        self.slotRaw = slot.rawValue
        self.withFood = withFood
        self.createdAt = .now
    }

    var slot: Slot {
        get { Slot(rawValue: slotRaw) ?? .breakfast }
        set { slotRaw = newValue.rawValue }
    }

    var isTakenToday: Bool {
        lastTakenAt.map(Calendar.current.isDateInToday) ?? false
    }

    var doseText: String {
        let n = dose.formatted(.number.precision(.fractionLength(0...2)))
        let pluralizable = ["capsule", "tablet", "gummy", "scoop", "softgel"]
        if pluralizable.contains(unit) && dose != 1 {
            return "\(n) \(unit == "gummy" ? "gummies" : unit + "s")"
        }
        return "\(n) \(unit)"
    }

    var timingNote: String {
        if slot.isMeal {
            return withFood ? "With \(slot.title.lowercased())" : "Around \(slot.title.lowercased())"
        }
        return slot.title
    }

    static let units = ["capsule", "tablet", "softgel", "gummy", "scoop", "mg", "mcg", "g", "IU", "mL", "drops"]
}

/// One container shared by the UI and the notification delegate.
@MainActor
let sharedContainer: ModelContainer = {
    do {
        return try ModelContainer(for: Supplement.self)
    } catch {
        fatalError("Could not create ModelContainer: \(error)")
    }
}()
