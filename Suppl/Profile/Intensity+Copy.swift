import Foundation
import SupplCore

extension Intensity {
    var title: String {
        switch self {
        case .gentle: "Gentle"
        case .balanced: "Balanced"
        case .extraHelp: "Extra Help"
        }
    }

    var detail: String {
        switch self {
        case .gentle: "One reminder. No follow-ups."
        case .balanced: "One follow-up if you don't respond."
        case .extraHelp: "Up to two follow-ups if you don't respond."
        }
    }

    var needsPro: Bool { self == .extraHelp }
}
