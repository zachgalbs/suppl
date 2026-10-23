import SwiftUI

/// The onboarding flow. Each step lives in Onboarding/; this file only handles order, Back, and progress.
@MainActor
struct OnboardingView: View {
    @AppStorage("onboarded") private var onboarded = false
    @AppStorage(PrefKey.takesSupplements) private var habitRaw = ""

    /// Visited steps, so Back retraces the path the user actually took (e.g. "Not yet" skips ahead).
    @State private var path: [OnboardingStep] = [.welcome]

    private var step: OnboardingStep { path.last ?? .welcome }

    var body: some View {
        ZStack {
            Color.cream.ignoresSafeArea()
            if step == .paywall {
                PaywallView(onClose: { onboarded = true })
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    if step.showsProgress {
                        header
                    }
                    page
                }
                .padding(24)
                .foregroundStyle(Color.forest)
            }
        }
        .animation(.easeInOut, value: step)
        .task { Store.shared.start() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: back) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            ProgressView(value: Double(step.position), total: Double(OnboardingStep.progressCount))
                .tint(Color.sage)
                .accessibilityLabel("Progress")
                .accessibilityValue("Step \(step.position) of \(OnboardingStep.progressCount)")
        }
        .padding(.leading, -12)
    }

    @ViewBuilder private var page: some View {
        switch step {
        case .welcome: WelcomeStep { go(.name) }
        case .name: NameStep { go(.age) }
        case .age: AgeStep { go(.takes) }
        // "Not yet" goes straight to the summary. We never suggest anyone needs supplements.
        case .takes: TakesStep { habit in go(habit == .notYet ? .summary : .add) }
        case .add: AddSupplementsStep { go(.times) }
        case .times: TimesStep { go(.connect) }
        case .connect: ConnectStep { go(.style) }
        case .style: StyleStep { go(.notifications) }
        case .notifications: NotificationsStep { go(.summary) }
        case .summary: SummaryStep(finish: finishSummary)
        case .paywall: EmptyView()
        }
    }

    private func go(_ next: OnboardingStep) {
        path.append(next)
    }

    private func back() {
        if path.count > 1 { path.removeLast() }
    }

    /// The paywall is offered once, dismissibly. Skipped for people who don't take anything yet or already have Pro.
    private func finishSummary() {
        if habitRaw == SupplementHabit.notYet.rawValue || Store.shared.isPro {
            onboarded = true
        } else {
            go(.paywall)
        }
    }
}

#if DEBUG
#Preview {
    OnboardingView()
        .modelContainer(PreviewData.container(empty: true))
}
#endif
