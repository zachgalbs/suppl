import SwiftUI

struct NameStep: View {
    let next: () -> Void
    @AppStorage("name") private var name = ""
    @FocusState private var focused: Bool

    private var isEmpty: Bool { name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        OnboardingPage("What should we call you?", primaryDisabled: isEmpty,
                       secondary: "Skip", onPrimary: next, onSecondary: skip) {
            TextField("Your name", text: $name)
                .font(.title3)
                .textContentType(.givenName)
                .submitLabel(.continue)
                .focused($focused)
                .onSubmit { if !isEmpty { next() } }
                .padding()
                .background(Color.white.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .onAppear { focused = true }
    }

    private func skip() {
        name = ""
        next()
    }
}

#if DEBUG
#Preview {
    NameStep {}
        .padding(24)
        .background(Color.cream)
        .foregroundStyle(Color.forest)
}
#endif
