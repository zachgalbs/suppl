import SwiftUI

/// Shared layout for an onboarding question: title, optional subtitle, fields, and the buttons at the bottom.
/// Scrolls so large Dynamic Type sizes never push the buttons off screen.
struct OnboardingPage<Fields: View>: View {
    let title: String
    let subtitle: String?
    let primary: String
    let primaryDisabled: Bool
    let secondary: String?
    let onPrimary: () -> Void
    let onSecondary: (() -> Void)?
    let fields: Fields

    init(_ title: String, subtitle: String? = nil, primary: String = "Continue", primaryDisabled: Bool = false,
         secondary: String? = nil, onPrimary: @escaping () -> Void, onSecondary: (() -> Void)? = nil,
         @ViewBuilder fields: () -> Fields) {
        self.title = title
        self.subtitle = subtitle
        self.primary = primary
        self.primaryDisabled = primaryDisabled
        self.secondary = secondary
        self.onPrimary = onPrimary
        self.onSecondary = onSecondary
        self.fields = fields()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(title)
                        .font(.largeTitle.bold())
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle {
                        Text(subtitle)
                            .foregroundStyle(Color.forest.opacity(0.8))
                    }
                    fields
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)

            Button(primary, action: onPrimary)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(primaryDisabled)
                .opacity(primaryDisabled ? 0.5 : 1)
            if let secondary, let onSecondary {
                Button(secondary, action: onSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(Color.forest.opacity(0.8))
            }
        }
    }
}

/// A tappable answer card, used for single-choice questions.
struct ChoiceRow: View {
    let title: String
    var detail: String? = nil
    var badge: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.sage : Color.forest.opacity(0.4))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(title).font(.headline)
                        if let badge {
                            Text(badge)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.softLavender)
                                .clipShape(Capsule())
                        }
                    }
                    if let detail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(Color.forest.opacity(0.8))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(isSelected ? Color.softSage : Color.white.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? Color.sage : Color.clear, lineWidth: 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#if DEBUG
#Preview {
    OnboardingPage("A question", subtitle: "A short explanation.", secondary: "Skip", onPrimary: {}, onSecondary: {}) {
        ChoiceRow(title: "Every day", isSelected: true) {}
        ChoiceRow(title: "Occasionally", detail: "A few times a week", badge: "Pro", isSelected: false) {}
    }
    .padding(24)
    .background(Color.cream)
    .foregroundStyle(Color.forest)
}
#endif
