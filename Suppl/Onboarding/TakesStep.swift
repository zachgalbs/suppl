import SwiftUI

/// Stored under `PrefKey.takesSupplements`.
enum SupplementHabit: String, CaseIterable {
    case daily, occasionally, notYet

    var title: String {
        switch self {
        case .daily: "Every day"
        case .occasionally: "Occasionally"
        case .notYet: "Not yet"
        }
    }
}

struct TakesStep: View {
    let next: (SupplementHabit) -> Void
    @AppStorage(PrefKey.takesSupplements) private var habitRaw = ""

    private var habit: SupplementHabit? { SupplementHabit(rawValue: habitRaw) }

    var body: some View {
        OnboardingPage("Do you take supplements?", subtitle: "Any answer is fine.",
                       primaryDisabled: habit == nil, onPrimary: { if let habit { next(habit) } }) {
            ForEach(SupplementHabit.allCases, id: \.self) { option in
                ChoiceRow(title: option.title, isSelected: habit == option) {
                    habitRaw = option.rawValue
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    TakesStep { _ in }
        .padding(24)
        .background(Color.cream)
        .foregroundStyle(Color.forest)
}
#endif
