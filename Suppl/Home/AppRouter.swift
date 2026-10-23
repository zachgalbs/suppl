import Foundation
import Observation

/// App-wide navigation requests that come from outside the view tree, like tapping a notification.
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()
    /// Set to a notification group id to show its "Why now?" sheet on Home.
    var whyNowGroupID: String?
}
