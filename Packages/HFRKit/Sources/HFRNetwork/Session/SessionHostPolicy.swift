import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The hosts an `HFRSession` may contact, and the redirects it may follow.
///
/// An account session only talks to the forum: requests elsewhere are refused, so the jar only ever receives
/// `hardware.fr` cookies, and a redirect leaving the forum is not followed, because swift-corelibs-foundation copies
/// the account's `Cookie` header onto the redirected request whatever its host.
enum SessionHostPolicy: Sendable {
    /// `hardware.fr` and its subdomains (production).
    case forum
    /// One exact host (tests against the loopback server).
    case exactHost(String)

    /// True when `url` is `http`/`https` on an allowed host.
    func allows(_ url: URL?) -> Bool {
        guard let url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var host = url.host?.lowercased(), !host.isEmpty else { return false }
        if host.hasSuffix(".") { host.removeLast() }
        switch self {
        case .forum: return host == "hardware.fr" || host.hasSuffix(".hardware.fr")
        case .exactHost(let allowed): return host == allowed.lowercased()
        }
    }

    /// True when a redirect from `source` to `target` may be followed: the target is allowed and HTTPS is not
    /// downgraded to HTTP (corelibs would send `Secure` cookies over plain HTTP).
    func allowsRedirect(from source: URL?, to target: URL?) -> Bool {
        guard allows(target) else { return false }
        let downgrade = source?.scheme?.lowercased() == "https" && target?.scheme?.lowercased() == "http"
        return !downgrade
    }
}

/// Session delegate that stops a redirect the policy refuses; the 3xx answer is then returned to the caller.
final class HostPolicyRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    private let policy: SessionHostPolicy

    init(policy: SessionHostPolicy) {
        self.policy = policy
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(policy.allowsRedirect(from: response.url, to: request.url) ? request : nil)
    }
}
