import Foundation

/// WHOOP endpoints, checked against developer.whoop.com on 2026-10-23 (see server/whoop-broker/README.md).
enum WhoopAPI {
    static let authorizeURL = URL(string: "https://api.prod.whoop.com/oauth/oauth2/auth")!
    static let baseURL = URL(string: "https://api.prod.whoop.com/developer")!
    static let workoutPath = "v2/activity/workout"
    static let sleepPath = "v2/activity/sleep"
    /// `DELETE` revokes the user's grant for this app.
    static let revokePath = "v2/user/access"
    /// `offline` is what gets us a refresh token.
    static let scopes = "read:workout read:sleep offline"
    static let redirectURI = "suppl://whoop/callback"
    static let callbackScheme = "suppl"
    /// Collection pages hold at most 25 records.
    static let pageLimit = 25
}

/// Client id and broker URL from Info.plist, which get them from Config/*.xcconfig.
/// Both ship empty, and then WHOOP shows as "Not available yet".
struct WhoopConfig: Equatable {
    var clientID: String
    var brokerURL: URL
    /// Optional `x-suppl-key` for the broker. It ships inside the app, so it's a speed bump, not a secret.
    var appKey: String?

    init?(info: [String: Any]?) {
        guard let clientID = Self.value("WHOOPClientID", in: info),
              let raw = Self.value("WHOOPBrokerURL", in: info),
              let url = URL(string: raw), url.scheme == "https", url.host != nil else { return nil }
        self.clientID = clientID
        self.brokerURL = url
        self.appKey = Self.value("WHOOPAppKey", in: info)
    }

    /// Empty, or an unexpanded `$(VAR)` when the build setting doesn't exist, both mean "not set".
    private static func value(_ key: String, in info: [String: Any]?) -> String? {
        let value = (info?[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty || value.contains("$(") ? nil : value
    }
}

/// Access and refresh token, stored together in the Keychain because WHOOP rotates them as a pair.
struct WhoopTokens: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date

    func isExpired(at date: Date) -> Bool { date >= expiresAt }
}

/// What the broker passes back from WHOOP's token endpoint.
struct WhoopTokenResponse: Decodable {
    var accessToken: String
    var refreshToken: String?
    var expiresIn: Double

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

/// One page of `/v2/activity/workout` or `/v2/activity/sleep`. Only the fields we use are decoded.
struct WhoopPage<Record: Decodable>: Decodable {
    var records: [Record]
    var nextToken: String?

    enum CodingKeys: String, CodingKey {
        case records
        case nextToken = "next_token"
    }
}

struct WhoopWorkout: Decodable {
    var start: Date
    var end: Date?
}

struct WhoopSleep: Decodable {
    var start: Date
    var end: Date?
    var nap: Bool?
}

extension JSONDecoder {
    /// WHOOP sends ISO 8601 with milliseconds ("2022-04-24T02:25:44.774Z"); accept either form.
    static var whoop: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let precise = ISO8601DateFormatter()
            precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = precise.date(from: string) ?? ISO8601DateFormatter().date(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO 8601 date")
        }
        return decoder
    }
}
