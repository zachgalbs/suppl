import Foundation
import Observation
import OSLog
import SupplCore
import UIKit

/// Reads workouts and sleep from WHOOP.
///
/// Sign-in runs in a web sheet. The code goes to our token broker (server/whoop-broker), which holds the
/// client secret and swaps it for tokens. Tokens live in the Keychain; data requests go straight to WHOOP.
/// Refresh tokens rotate, so every new pair is saved before it's used.
@MainActor @Observable
final class WhoopConnector: Connector {
    let id = ConnectorID.whoop
    let displayName = "WHOOP"
    let summary = "Reads your WHOOP workouts and sleep, so a post-workout reminder can follow a workout and a morning reminder can wait until you're up."
    let disconnectNote: String? = "Disconnecting signs suppl. out of WHOOP and deletes the sign-in from this phone."

    let config: WhoopConfig?
    private(set) var authorization: ConnectorAuthorization
    private(set) var lastSync: Date?
    /// Set after WHOOP says "too many requests". Fetches return nothing until then.
    private(set) var nextAllowedFetch: Date?

    @ObservationIgnored var now: () -> Date = Date.init
    @ObservationIgnored private let urlSession: URLSession
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let webAuth: WebAuthSession
    /// One refresh at a time: WHOOP accepts only the first of two concurrent refreshes.
    @ObservationIgnored private var refreshTask: Task<WhoopTokens, Error>?
    @ObservationIgnored private var backoffCount = 0
    @ObservationIgnored private let log = Logger(subsystem: "com.zgalbs.suppl", category: "whoop")

    static let keychainService = "com.zgalbs.suppl.whoop"
    static let keychainAccount = "tokens"
    static let lastSyncKey = "connector.whoop.lastSync"
    static let nextAllowedKey = "connector.whoop.nextAllowedFetch"
    /// Keychain items survive deleting the app. This flag doesn't, so a fresh install can clear old tokens.
    static let installedKey = "connector.whoop.installed"
    /// Upper bound on pages per collection per fetch, to stay well inside WHOOP's 100 requests a minute.
    static let maxPages = 4

    init(info: [String: Any]? = Bundle.main.infoDictionary,
         urlSession: URLSession = .shared,
         defaults: UserDefaults = .standard) {
        config = WhoopConfig(info: info)
        self.urlSession = urlSession
        self.defaults = defaults
        webAuth = WebAuthSession()
        // Before first unlock both stores read as empty, so only clean up when data is readable.
        if !defaults.bool(forKey: Self.installedKey), UIApplication.shared.isProtectedDataAvailable {
            Keychain.delete(service: Self.keychainService, account: Self.keychainAccount)
            defaults.set(true, forKey: Self.installedKey)
        }
        authorization = Self.loadTokens() == nil ? .notConnected : .connected
        lastSync = defaults.object(forKey: Self.lastSyncKey) as? Date
        nextAllowedFetch = defaults.object(forKey: Self.nextAllowedKey) as? Date
    }

    /// The UI hides Connect unless this is `.available`.
    var availability: ConnectorAvailability { config == nil ? .notConfigured : .available }

    // MARK: - Connect

    func connect() async throws {
        guard let config else { throw ConnectorError.notConfigured }
        let state = Self.makeState()
        var components = URLComponents(url: WhoopAPI.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: WhoopAPI.redirectURI),
            URLQueryItem(name: "scope", value: WhoopAPI.scopes),
            URLQueryItem(name: "state", value: state),
        ]
        guard let url = components.url else { throw ConnectorError.failed("Couldn't start WHOOP sign-in.") }

        let callback = try await webAuth.start(url: url, callbackScheme: WhoopAPI.callbackScheme)
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func item(_ name: String) -> String? { items.first { $0.name == name }?.value }

        if item("error") != nil {
            throw ConnectorError.denied("WHOOP access wasn't granted. You can try again any time.")
        }
        guard item("state") == state, let code = item("code"), !code.isEmpty else {
            throw ConnectorError.failed("WHOOP sign-in didn't match. Try again.")
        }
        let tokens = try await brokerTokens("whoop/token", body: ["code": code], previous: nil, config: config)
        guard save(tokens) else { throw ConnectorError.failed("Couldn't save the WHOOP sign-in on this phone. Try again.") }
        authorization = .connected
    }

    /// Revokes the grant at WHOOP (best effort) and deletes the tokens from this phone.
    func disconnect() async {
        if let tokens = Self.loadTokens() {
            var request = URLRequest(url: WhoopAPI.baseURL.appendingPathComponent(WhoopAPI.revokePath))
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 10
            _ = try? await urlSession.data(for: request)
        }
        deleteAllData()
    }

    /// For "Delete all data": removes tokens and sync state without calling WHOOP.
    func deleteAllData() {
        refreshTask?.cancel()
        refreshTask = nil
        Keychain.delete(service: Self.keychainService, account: Self.keychainAccount)
        defaults.removeObject(forKey: Self.lastSyncKey)
        defaults.removeObject(forKey: Self.nextAllowedKey)
        authorization = .notConnected
        lastSync = nil
        nextAllowedFetch = nil
        backoffCount = 0
    }

    // MARK: - Fetch

    func fetchSignals(since: Date) async throws -> [ContextSignal] {
        guard config != nil, authorization == .connected else { return [] }
        let at = now()
        if let nextAllowedFetch, at < nextAllowedFetch { return [] }

        let dayStart = Calendar.current.startOfDay(for: at)
        let workouts: [WhoopWorkout]
        let sleeps: [WhoopSleep]
        do {
            // A workout that started before `since` can still have ended after it.
            workouts = try await collection(WhoopAPI.workoutPath, start: since.addingTimeInterval(-6 * 3600))
            // Last night's sleep usually starts yesterday evening.
            sleeps = try await collection(WhoopAPI.sleepPath, start: min(since, dayStart.addingTimeInterval(-24 * 3600)))
        } catch is RateLimited {
            // Not the user's problem: we wait until `nextAllowedFetch` and use usual times meanwhile.
            return []
        }

        var signals: [ContextSignal] = []
        for w in workouts {
            guard let end = w.end, end >= since, end <= at, end > w.start else { continue }
            signals.append(ContextSignal(kind: .workoutEnded(start: w.start, end: end), source: .whoop, observedAt: at))
        }
        // Same rule as Apple Health: the latest main sleep (not a nap) that ended today, scored or not.
        let woke = sleeps
            .filter { $0.nap != true }
            .compactMap(\.end)
            .filter { $0 >= dayStart && $0 <= at }
            .max()
        if let woke {
            signals.append(ContextSignal(kind: .wokeUp(at: woke), source: .whoop, observedAt: at))
        }

        backoffCount = 0
        lastSync = at
        defaults.set(at, forKey: Self.lastSyncKey)
        return signals
    }

    /// Every record from `start` until now, following `next_token`, up to `maxPages` pages.
    private func collection<Record: Decodable>(_ path: String, start: Date) async throws -> [Record] {
        var records: [Record] = []
        var nextToken: String?
        for _ in 0..<Self.maxPages {
            var components = URLComponents(url: WhoopAPI.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "start", value: ISO8601DateFormatter().string(from: start)),
                URLQueryItem(name: "limit", value: String(WhoopAPI.pageLimit)),
            ]
            if let nextToken { components.queryItems?.append(URLQueryItem(name: "nextToken", value: nextToken)) }
            guard let url = components.url else { break }

            let data = try await authorizedGet(url)
            guard let page = try? JSONDecoder.whoop.decode(WhoopPage<Record>.self, from: data) else {
                throw ConnectorError.failed("WHOOP sent something unexpected. We'll try again later.")
            }
            records += page.records
            guard let token = page.nextToken, !token.isEmpty else { break }
            nextToken = token
        }
        return records
    }

    /// GET with the access token. Refreshes first if it's expired, and once more on a 401.
    private func authorizedGet(_ url: URL) async throws -> Data {
        var tokens = try await validTokens()
        for attempt in 0..<2 {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 20
            let (data, response) = try await urlSession.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch status {
            case 200..<300:
                return data
            case 401 where attempt == 0:
                tokens = try await refresh(tokens)
            case 429:
                backOff(response as? HTTPURLResponse)
                throw RateLimited()
            default:
                log.error("WHOOP request failed with status \(status, privacy: .public)")
                throw ConnectorError.failed("Couldn't reach WHOOP. We'll try again later.")
            }
        }
        throw ConnectorError.failed("Couldn't reach WHOOP. We'll try again later.")
    }

    /// Honours Retry-After or X-RateLimit-Reset (seconds), else backs off 1, 2, 4… minutes up to an hour.
    private func backOff(_ response: HTTPURLResponse?) {
        let header = response?.value(forHTTPHeaderField: "Retry-After") ?? response?.value(forHTTPHeaderField: "X-RateLimit-Reset")
        let fallback = min(3600, 60 * pow(2, Double(backoffCount)))
        let seconds = header.flatMap { TimeInterval($0.trimmingCharacters(in: .whitespaces)) }.map { min(max($0, 1), 24 * 3600) } ?? fallback
        backoffCount += 1
        let until = now().addingTimeInterval(seconds)
        nextAllowedFetch = until
        defaults.set(until, forKey: Self.nextAllowedKey)
    }

    // MARK: - Tokens

    private func validTokens() async throws -> WhoopTokens {
        // Only `deleteAllData()` removes tokens, and it also clears `authorization`. A miss here means the
        // Keychain isn't readable yet (phone not unlocked since boot), which is temporary.
        guard let tokens = Self.loadTokens() else {
            throw ConnectorError.failed("Couldn't read the WHOOP sign-in. We'll try again later.")
        }
        return tokens.isExpired(at: now()) ? try await refresh(tokens) : tokens
    }

    private func refresh(_ tokens: WhoopTokens) async throws -> WhoopTokens {
        if let refreshTask { return try await refreshTask.value }
        guard let config else { throw ConnectorError.notConfigured }
        let task = Task { @MainActor in
            let fresh = try await self.brokerTokens("whoop/refresh", body: ["refresh_token": tokens.refreshToken],
                                                    previous: tokens, config: config)
            // The old pair is dead now, so save the new one before anything uses it.
            self.save(fresh)
            return fresh
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    /// POSTs to the broker and turns WHOOP's token response into a pair. A 400 on refresh means the
    /// refresh token is dead (revoked, or already rotated), so the stored sign-in is removed.
    private func brokerTokens(_ path: String, body: [String: String], previous: WhoopTokens?,
                              config: WhoopConfig) async throws -> WhoopTokens {
        var request = URLRequest(url: config.brokerURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = config.appKey { request.setValue(key, forHTTPHeaderField: "x-suppl-key") }
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = 20

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw ConnectorError.failed("Couldn't reach the WHOOP sign-in service. Check your connection and try again.")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status),
              let decoded = try? JSONDecoder().decode(WhoopTokenResponse.self, from: data) else {
            log.error("WHOOP broker \(path, privacy: .public) failed with status \(status, privacy: .public)")
            if previous != nil, status == 400 {
                deleteAllData()
                throw ConnectorError.signedOut("WHOOP signed suppl. out. Connect again to keep using it.")
            }
            throw ConnectorError.failed("Couldn't connect to WHOOP. Try again in a bit.")
        }
        guard let refreshToken = decoded.refreshToken ?? previous?.refreshToken else {
            throw ConnectorError.failed("WHOOP didn't allow offline access. Try connecting again.")
        }
        // Refresh a minute early so a request never goes out with a token about to expire.
        let expiresAt = now().addingTimeInterval(max(0, decoded.expiresIn - 60))
        return WhoopTokens(accessToken: decoded.accessToken, refreshToken: refreshToken, expiresAt: expiresAt)
    }

    @discardableResult
    private func save(_ tokens: WhoopTokens) -> Bool {
        guard let data = try? JSONEncoder().encode(tokens),
              Keychain.set(data, service: Self.keychainService, account: Self.keychainAccount) else {
            log.error("Couldn't save WHOOP tokens to the Keychain")
            return false
        }
        return true
    }

    private static func loadTokens() -> WhoopTokens? {
        Keychain.data(service: keychainService, account: keychainAccount)
            .flatMap { try? JSONDecoder().decode(WhoopTokens.self, from: $0) }
    }

    /// WHOOP requires an 8-character `state`. `randomElement()` uses the system's secure generator.
    static func makeState() -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return String((0..<8).map { _ in alphabet.randomElement()! })
    }
}

/// Thrown internally on a 429 so `fetchSignals` can return nothing instead of an error.
private struct RateLimited: Error {}
