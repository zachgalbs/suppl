import SwiftUI
import SupplCore

/// Gentle, Balanced (default), or Extra Help. Extra Help is Pro, so choosing it without Pro opens the paywall.
@MainActor
struct StyleStep: View {
    let next: () -> Void
    @AppStorage(PrefKey.intensity) private var intensityRaw = Intensity.balanced.rawValue
    @State private var showingPaywall = false

    private var selected: Intensity { Intensity(rawValue: intensityRaw) ?? .balanced }
    private var isPro: Bool { Store.shared.isPro }

    var body: some View {
        OnboardingPage("How much help do you want?", subtitle: "You can change this anytime in Profile.", onPrimary: next) {
            ForEach(Intensity.allCases, id: \.self) { option in
                ChoiceRow(title: option.title, detail: option.detail,
                          badge: option.needsPro && !isPro ? "Pro" : nil,
                          isSelected: selected == option) {
                    choose(option)
                }
            }
        }
        .sheet(isPresented: $showingPaywall, onDismiss: {
            if Store.shared.isPro { intensityRaw = Intensity.extraHelp.rawValue }
        }) {
            PaywallView()
        }
    }

    private func choose(_ option: Intensity) {
        if option.needsPro && !isPro {
            showingPaywall = true
        } else {
            intensityRaw = option.rawValue
        }
    }
}

#if DEBUG
#Preview {
    StyleStep {}
        .padding(24)
        .background(Color.cream)
        .foregroundStyle(Color.forest)
}
#endif
