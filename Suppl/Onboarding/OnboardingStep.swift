import Foundation

/// One question per screen. Order here is the order of the flow.
enum OnboardingStep: Int, CaseIterable {
    case welcome, name, age, takes, add, times, connect, style, notifications, summary, paywall

    /// Welcome and the paywall stand alone; everything between gets Back and a progress bar.
    var showsProgress: Bool { self != .welcome && self != .paywall }

    /// 1-based position among the steps that show progress.
    var position: Int { rawValue }

    static let progressCount = OnboardingStep.summary.rawValue
}
