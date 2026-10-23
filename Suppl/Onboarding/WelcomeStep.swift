import SwiftUI

struct WelcomeStep: View {
    let next: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Text("suppl.")
                .font(.system(size: 56, weight: .semibold, design: .rounded))
            Text("Your supplements. Finally simplified.")
                .font(.title2.bold())
            Text("Gentle reminders for the supplements you already take, at moments that fit your day.")
                .font(.title3)
            Spacer()
            Button("Get started", action: next)
                .buttonStyle(PrimaryButtonStyle())
        }
    }
}

#if DEBUG
#Preview {
    WelcomeStep {}
        .padding(24)
        .background(Color.cream)
        .foregroundStyle(Color.forest)
}
#endif
