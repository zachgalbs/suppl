import AuthenticationServices
import UIKit

/// Async wrapper around `ASWebAuthenticationSession`. Ephemeral, so no WHOOP cookies are left in Safari.
@MainActor
final class WebAuthSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    /// Kept alive until the sheet finishes; the system doesn't retain it for us.
    private var session: ASWebAuthenticationSession?

    func start(url: URL, callbackScheme: String) async throws -> URL {
        let once = ResumeOnce()
        return try await withCheckedThrowingContinuation { continuation in
            once.continuation = continuation
            let done: ASWebAuthenticationSession.CompletionHandler = { [weak self] callbackURL, error in
                if let callbackURL {
                    once.resume(.success(callbackURL))
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    once.resume(.failure(ConnectorError.cancelled))
                } else {
                    once.resume(.failure(ConnectorError.failed("Couldn't finish signing in. Try again.")))
                }
                Task { @MainActor in self?.session = nil }
            }

            let session: ASWebAuthenticationSession
            if #available(iOS 17.4, *) {
                session = ASWebAuthenticationSession(url: url, callback: .customScheme(callbackScheme), completionHandler: done)
            } else {
                session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme, completionHandler: done)
            }
            session.prefersEphemeralWebBrowserSession = true
            session.presentationContextProvider = self
            self.session = session
            if !session.start() {
                once.resume(.failure(ConnectorError.failed("Couldn't open the sign-in page. Try again.")))
                self.session = nil
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) { return window }
        if let scene = scenes.first { return UIWindow(windowScene: scene) }
        return ASPresentationAnchor()
    }
}

/// The completion handler can run on any queue and, if `start()` fails, may or may not be called.
/// This makes sure the continuation is resumed exactly once.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    var continuation: CheckedContinuation<URL, Error>?

    func resume(_ result: Result<URL, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}
