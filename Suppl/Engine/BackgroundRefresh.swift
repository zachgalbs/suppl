import BackgroundTasks
import Foundation

/// Periodic wake-ups so WHOOP and calendar changes reach the engine while the app is closed.
/// iOS decides when these actually run; nothing in the app promises a schedule.
enum BackgroundRefresh {
    static let identifier = "com.zgalbs.suppl.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            schedule()
            let work = Task { @MainActor in
                await NotificationScheduler.run(refreshSignals: true)
                task.setTaskCompleted(success: !Task.isCancelled)
            }
            // Cancelling ends the run's wait early; the task above still reports completion exactly once.
            task.expirationHandler = { work.cancel() }
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
