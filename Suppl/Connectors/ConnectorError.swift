import Foundation

/// Errors a connector throws from `connect()` or `fetchSignals(since:)`.
/// `errorDescription` is shown to the user as is, so it stays short and never includes server bodies or tokens.
enum ConnectorError: LocalizedError, Equatable {
    /// Missing credentials or setup, e.g. WHOOP before a developer app exists.
    case notConfigured
    /// Not possible on this device.
    case unsupported
    /// The user said no. The string says where to turn it back on.
    case denied(String)
    /// The user closed the sign-in sheet. Not worth an error message.
    case cancelled
    /// The stored sign-in no longer works and was removed. The user has to connect again.
    case signedOut(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Not available yet."
        case .unsupported: "Not available on this device."
        case .denied(let message), .signedOut(let message), .failed(let message): message
        case .cancelled: nil
        }
    }
}
