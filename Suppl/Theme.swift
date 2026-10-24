import SwiftUI

extension Color {
    static let cream = Color(hex: 0xF8F6F0)
    static let sage = Color(hex: 0x789575)
    static let forest = Color(hex: 0x344536)
    static let lavender = Color(hex: 0x987E9F)
    // Secondary tokens from the design blueprint, for selected states and badges.
    static let softSage = Color(hex: 0xE8EDE2)
    static let softLavender = Color(hex: 0xF0EAF1)

    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.forest.opacity(configuration.isPressed ? 0.8 : 1))
            .foregroundStyle(Color.cream)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

extension View {
    func card() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Bridges a minutes-after-midnight Int to a Date for DatePicker.
extension Binding where Value == Int {
    var asTime: Binding<Date> {
        Binding<Date>(
            get: {
                Calendar.current.date(bySettingHour: wrappedValue / 60, minute: wrappedValue % 60, second: 0, of: .now) ?? .now
            },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }
}
