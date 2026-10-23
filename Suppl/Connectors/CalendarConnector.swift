import Foundation
import EventKit
import Observation
import SupplCore

/// Reads when you're busy today and tomorrow. Only start, end, all-day, and availability are touched:
/// titles, notes, attendees, URLs, and locations are never read.
@MainActor @Observable
final class CalendarConnector: Connector {
    let id = ConnectorID.calendar
    let displayName = "Calendar"
    let summary = "Reads only when you're busy today and tomorrow, so a flexible reminder can land in a free moment. Never titles, notes, or attendees."
    let disconnectNote: String? = "To fully revoke access, open Settings, then Privacy & Security > Calendars > suppl."

    private(set) var lastSync: Date?
    /// The user connected in the app. Disconnecting clears it; only Settings can revoke the OS permission.
    private var enabled: Bool

    @ObservationIgnored var now: () -> Date = Date.init
    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var changeObserver: NSObjectProtocol?

    static let connectedKey = "connector.calendar.connected"
    static let lastSyncKey = "connector.calendar.lastSync"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.bool(forKey: Self.connectedKey)
        lastSync = defaults.object(forKey: Self.lastSyncKey) as? Date
    }

    let availability = ConnectorAvailability.available

    /// Read live, because the user can change the permission in Settings while the app is running.
    var authorization: ConnectorAuthorization {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: enabled ? .connected : .notConnected
        case .denied, .restricted: .denied
        // notDetermined, writeOnly (busy times need full access), and the pre-iOS 17 `authorized`.
        default: .notConnected
        }
    }

    func connect() async throws {
        let granted: Bool
        do {
            granted = try await store.requestFullAccessToEvents()
        } catch {
            throw ConnectorError.failed("Couldn't ask for calendar access. Try again.")
        }
        guard granted else {
            enabled = false
            throw ConnectorError.denied("Calendar access is off. You can turn it on in Settings, then Privacy & Security > Calendars.")
        }
        enabled = true
        defaults.set(true, forKey: Self.connectedKey)
    }

    func disconnect() async {
        enabled = false
        lastSync = nil
        defaults.removeObject(forKey: Self.connectedKey)
        defaults.removeObject(forKey: Self.lastSyncKey)
    }

    /// One `.busy` signal with today's and tomorrow's timed, non-free events. An empty list is a real
    /// answer ("nothing booked"), so it's still returned. `since` doesn't apply: busy times look ahead.
    func fetchSignals(since: Date) async throws -> [ContextSignal] {
        guard authorization == .connected else { return [] }
        let at = now()
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: at)
        guard let end = calendar.date(byAdding: .day, value: 2, to: start) else { return [] }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        var busy: [DateInterval] = []
        for event in store.events(matching: predicate) {
            guard !event.isAllDay, event.availability != .free,
                  let eventStart = event.startDate, let eventEnd = event.endDate, eventEnd > eventStart else { continue }
            busy.append(DateInterval(start: eventStart, end: eventEnd))
        }
        busy.sort { $0.start < $1.start }

        lastSync = at
        defaults.set(at, forKey: Self.lastSyncKey)
        return [ContextSignal(kind: .busy(busy), source: .calendar, observedAt: at)]
    }

    /// Calls `onChange` when any calendar changes (including edits from other apps), while connected.
    /// Call once; later calls replace the handler.
    func observeChanges(onChange: @escaping @MainActor () async -> Void) {
        if let changeObserver { NotificationCenter.default.removeObserver(changeObserver) }
        changeObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard self?.authorization == .connected else { return }
                await onChange()
            }
        }
    }
}
