import SwiftUI

/// Adults only. Under 18 stops here: no personalized setup, and the only way on is changing the answer.
struct AgeStep: View {
    let next: () -> Void
    @AppStorage(PrefKey.birthYear) private var birthYear = 0
    @AppStorage(PrefKey.isAdult) private var isAdult = true
    @State private var ageText = ""
    @State private var tooYoung = false
    @FocusState private var focused: Bool

    private var age: Int? {
        guard let value = Int(ageText.trimmingCharacters(in: .whitespaces)), (1...120).contains(value) else { return nil }
        return value
    }

    var body: some View {
        Group {
            if tooYoung {
                youngMessage
            } else {
                question
            }
        }
        .onAppear {
            // Someone who answered under 18 earlier sees the same message until they change it.
            if birthYear > 0 && !isAdult { tooYoung = true }
        }
    }

    private var question: some View {
        OnboardingPage("How old are you?", subtitle: "suppl. is for adults 18 and over.",
                       primaryDisabled: age == nil, onPrimary: submit) {
            TextField("Your age", text: $ageText)
                .font(.title3)
                .keyboardType(.numberPad)
                .focused($focused)
                .padding()
                .background(Color.white.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onAppear { focused = true }
        }
    }

    private var youngMessage: some View {
        OnboardingPage("Thanks for checking out suppl.", primary: "Change my answer", onPrimary: changeAnswer) {
            Text("suppl. is made for adults, so we can't set it up for you. If you take supplements, a parent, pharmacist, or doctor can help you keep track.")
                .font(.title3)
        }
    }

    private func submit() {
        guard let age else { return }
        let year = Calendar.current.component(.year, from: .now)
        // We only ask for age, so the birth year is approximate. Only `isAdult` gates anything.
        birthYear = year - age
        isAdult = age >= 18
        if isAdult {
            next()
        } else {
            focused = false
            tooYoung = true
        }
    }

    private func changeAnswer() {
        ageText = ""
        tooYoung = false
    }
}

#if DEBUG
#Preview {
    AgeStep {}
        .padding(24)
        .background(Color.cream)
        .foregroundStyle(Color.forest)
}
#endif
