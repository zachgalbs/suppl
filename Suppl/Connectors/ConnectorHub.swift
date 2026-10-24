import Foundation
import Observation
import OSLog
import SupplCore

/// The app's single entry point to every connector. Connectors are optional and never block the app:
/// errors are kept per connector in `lastError` for the UI, never thrown.
@MainActor @Observable
final class ConnectorHub {
    static let shared = ConnectorHub()

    let health: AppleHealthConnector
    let calendar: CalendarConnector
    let whoop: WhoopConnector
    private(set) var revision = 0
    @ObservationIgnored private var changing: Set<ConnectorID> = []
    @ObservationIgnored private let suppliedConnectors: [any Connector]?
    @ObservationIgnored private let onChange: @MainActor () -> Void
    private(set) var lastError: [ConnectorID: String] = [:]

    /// Without a sync in this long, a connected source "hasn't updated recently".
    static let staleAfter: TimeInterval = 24 * 3600

    @ObservationIgnored private let log = Logger(subsystem: "com.zgalbs.suppl", category: "connectors")

    /// Optionals rather than default arguments, because default arguments can't call main-actor inits in Swift 5 mode.
    init(health: AppleHealthConnector? = nil, calendar: CalendarConnector? = nil, whoop: WhoopConnector? = nil,
         connectors: [any Connector]? = nil,
         onChange: @escaping @MainActor () -> Void = { NotificationScheduler.connectionsChanged() }) {
        suppliedConnectors = connectors
        self.onChange = onChange
        self.health = health ?? AppleHealthConnector()
        self.calendar = calendar ?? CalendarConnector()
        self.whoop = whoop ?? WhoopConnector()
    }

    /// Display order: Apple Health, Calendar, WHOOP.
    var connectors: [any Connector] { suppliedConnectors ?? [health, calendar, whoop] }

    func connector(_ id: ConnectorID) -> (any Connector)? {
        connectors.first { $0.id == id }
    }

    /// The connector's note on revoking access at the OS or service level, for the disconnect sheet.
    func disconnectNote(_ id: ConnectorID) -> String? {
        switch id {
        case .appleHealth: health.disconnectNote
        case .calendar: calendar.disconnectNote
        case .whoop: whoop.disconnectNote
        case .oura: nil
        }
    }

    /// Calls connect(), records a user-readable error in lastError[id] instead of throwing.
    /// On success a fresh replan fetches permitted context for Pro timing.
    func connect(_ id: ConnectorID) async {
        guard let connector = connector(id), !changing.contains(id) else { return }
        let version = revision
        lastError[id] = nil
        do {
            try await connector.connect()
        } catch {
            guard version == revision else { return }
            lastError[id] = message(for: error, connector: connector)
            return
        }
        guard isUsable(connector), !Task.isCancelled else { return }
        changed()
    }

    func disconnect(_ id: ConnectorID) async {
        guard let connector = connector(id) else { return }
        changing.insert(id)
        changed()
        await connector.disconnect()
        changing.remove(id)
        lastError[id] = nil
        changed()
    }

    /// Sources of connected connectors (for engine copy).
    var connectedSources: Set<SignalSource> {
        Set(connectors.filter(isUsable).compactMap { SignalSource(rawValue: $0.id.rawValue) })
    }

    /// Connected but no successful sync in 24 h (Home shows "hasn't updated recently").
    func isStale(_ id: ConnectorID, now: Date) -> Bool {
        guard let connector = connector(id), isUsable(connector) else { return false }
        guard let lastSync = connector.lastSync else { return true }
        return now.timeIntervalSince(lastSync) > Self.staleAfter
    }

    /// Fetches from every connected, available connector since `since`, swallowing per-connector errors (logged to lastError). Never throws.
    /// `sources` limits which connectors are read at all; nil reads every connected one.
    func signals(since: Date, sources: Set<SignalSource>? = nil) async -> [ContextSignal] {
        let version = revision
        var all: [ContextSignal] = []
        for connector in connectors where isUsable(connector) {
            if let sources {
                guard let source = SignalSource(rawValue: connector.id.rawValue), sources.contains(source) else { continue }
            }
            all += await fetch(from: connector, since: since)
        }
        guard version == revision, !Task.isCancelled else { return [] }
        return all.filter { connectedSources.contains($0.source) }
    }

    /// For "Delete all data": disconnects everything and deletes WHOOP tokens.
    func disconnectAll() async {
        changing = Set(connectors.map(\.id))
        changed()
        // WHOOP clears local credentials first, then attempts grant revocation with its saved token.
        await whoop.disconnect()
        for connector in connectors where connector.id != .whoop { await connector.disconnect() }
        changing = []
        lastError = [:]
        changed()
    }

    private func changed() {
        revision += 1
        onChange()
    }

    // MARK: - Private

    private func isUsable(_ connector: any Connector) -> Bool {
        !changing.contains(connector.id) && connector.availability == .available && connector.authorization == .connected
    }

    @discardableResult
    private func fetch(from connector: any Connector, since: Date) async -> [ContextSignal] {
        let version = revision
        do {
            let signals = try await connector.fetchSignals(since: since)
            guard version == revision, isUsable(connector), !Task.isCancelled else { return [] }
            lastError[connector.id] = nil
            return signals
        } catch {
            guard version == revision, isUsable(connector), !Task.isCancelled else { return [] }
            log.error("\(connector.id.rawValue, privacy: .public) fetch failed")
            lastError[connector.id] = message(for: error, connector: connector)
            return []
        }
    }

    /// Our own errors carry copy written for the user. Anything else (HealthKit, network) gets a plain fallback,
    /// so system error text never reaches the screen.
    private func message(for error: Error, connector: any Connector) -> String? {
        if let error = error as? ConnectorError { return error.errorDescription }
        return "Couldn't update \(connector.displayName). We'll try again later."
    }
}
