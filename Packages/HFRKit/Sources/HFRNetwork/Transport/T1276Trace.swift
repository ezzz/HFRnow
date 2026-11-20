import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// DO NOT MERGE (#1276): throwaway launch trace, deleted once #1276 is diagnosed.
// Logs method, host, a redacted path, timings, status, error code and byte counts only. Never cookies, headers, query
// strings, fragments, bodies, pseudos or hash_check.

/// Launch trace for #1276; every line starts with `[T1276]` and the time in ms since the trace origin (first use, forced at app
/// init by `SwiftHFRApp`).
public enum T1276 {
    /// Shared monotonic origin.
    public static let origin: TimeInterval = ProcessInfo.processInfo.systemUptime

    /// Milliseconds since `origin`.
    public static func ms() -> Int { Int((ProcessInfo.processInfo.systemUptime - origin) * 1000) }

    /// Writes one line.
    public static func log(_ message: String) {
        let line = "[T1276] t=\(ms())ms \(message)"
        #if canImport(Darwin)
        NSLog("%@", line)
        #else
        print(line)
        #endif
    }

    private static let counters = Counters()

    static func nextRequestID() -> Int { counters.nextRequest() }
    static func nextSessionID() -> Int { counters.nextSession() }
    static func began() -> Int { counters.adjustInFlight(by: 1) }
    static func ended() -> Int { counters.adjustInFlight(by: -1) }

    /// Host and path of `url`, never its query or fragment. Forum `.php` pages and `/` are kept whole; any other path keeps its
    /// first segment and its extension only (topic slugs, MP subjects and personal smiley names can carry member names).
    public static func place(_ url: URL?) -> String {
        guard let url else { return "-" }
        let host = url.host ?? "-"
        let path = url.path
        if host == "forum.hardware.fr", path == "/" || (path.hasSuffix(".php") && !path.dropFirst().contains("/")) {
            return "\(host) \(path)"
        }
        let segments = path.split(separator: "/")
        guard let first = segments.first else { return "\(host) /" }
        let ext = (path as NSString).pathExtension
        let tail = segments.count > 1 ? "/…" + (ext.isEmpty ? "" : ".\(ext)") : ""
        return "\(host) /\(first)\(tail)"
    }

    /// A short name for a thrown error: the `URLError` code name, the `NetworkError` case, or the type and code.
    public static func describe(_ error: any Error) -> String {
        if let urlError = error as? URLError { return "URLError.\(name(urlError.code)) (\(urlError.errorCode))" }
        if let network = error as? NetworkError { return name(network) }
        if error is CancellationError { return "CancellationError" }
        let nsError = error as NSError
        return "\(type(of: error)) \(nsError.domain) \(nsError.code)"
    }

    /// A `NetworkError` case without any URL (`httpStatus` carries one with its query).
    public static func name(_ error: NetworkError) -> String {
        switch error {
        case .invalidRequest: "NetworkError.invalidRequest"
        case .httpStatus(let code, let url): "NetworkError.httpStatus(\(code), \(place(url)))"
        case .timedOut: "NetworkError.timedOut"
        case .offline: "NetworkError.offline"
        case .cancelled: "NetworkError.cancelled"
        case .invalidResponse: "NetworkError.invalidResponse"
        case .transport(let code): "NetworkError.transport(\(code))"
        case .unscripted: "NetworkError.unscripted"
        }
    }

    static func name(_ code: URLError.Code) -> String {
        switch code {
        case .timedOut: "timedOut"
        case .cancelled: "cancelled"
        case .notConnectedToInternet: "notConnectedToInternet"
        case .networkConnectionLost: "networkConnectionLost"
        case .cannotFindHost: "cannotFindHost"
        case .cannotConnectToHost: "cannotConnectToHost"
        case .dnsLookupFailed: "dnsLookupFailed"
        case .secureConnectionFailed: "secureConnectionFailed"
        case .dataNotAllowed: "dataNotAllowed"
        case .internationalRoamingOff: "internationalRoamingOff"
        case .badServerResponse: "badServerResponse"
        case .httpTooManyRedirects: "httpTooManyRedirects"
        case .resourceUnavailable: "resourceUnavailable"
        case .cannotParseResponse: "cannotParseResponse"
        case .backgroundSessionWasDisconnected: "backgroundSessionWasDisconnected"
        default: "code\(code.rawValue)"
        }
    }

    /// The configuration values of one new `URLSession` that bear on a timeout.
    static func logSession(_ id: Int, kind: String, _ configuration: URLSessionConfiguration) {
        log(
            "session s\(id) created kind=\(kind) maxConnPerHost=\(configuration.httpMaximumConnectionsPerHost) "
                + "timeoutRequest=\(configuration.timeoutIntervalForRequest) "
                + "timeoutResource=\(configuration.timeoutIntervalForResource) "
                + "waitsForConnectivity=\(configuration.waitsForConnectivity)"
        )
    }

    private final class Counters: @unchecked Sendable {
        private let lock = NSLock()
        private var request = 0
        private var session = 0
        private var inFlight = 0

        func nextRequest() -> Int { lock.withLock { request += 1; return request } }
        func nextSession() -> Int { lock.withLock { session += 1; return session } }
        func adjustInFlight(by delta: Int) -> Int { lock.withLock { inFlight += delta; return inFlight } }
    }
}

#if !canImport(FoundationNetworking)
/// Per-task delegate that logs the phases of each transaction (`URLSessionTaskMetrics`); it implements nothing else, so
/// redirects still go to the session's delegate.
final class T1276MetricsDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    let requestID: Int

    init(requestID: Int) { self.requestID = requestID }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        let start = metrics.taskInterval.start
        func at(_ date: Date?) -> String {
            guard let date else { return "-" }
            return "\(Int(date.timeIntervalSince(start) * 1000))"
        }
        T1276.log(
            "metrics r\(requestID) task=\(Int(metrics.taskInterval.duration * 1000))ms redirects=\(metrics.redirectCount) "
                + "transactions=\(metrics.transactionMetrics.count)"
        )
        for (index, transaction) in metrics.transactionMetrics.enumerated() {
            T1276.log(
                "metrics r\(requestID).\(index) \(T1276.place(transaction.request.url)) "
                    + "fetchType=\(transaction.resourceFetchType.rawValue) reused=\(transaction.isReusedConnection) "
                    + "proto=\(transaction.networkProtocolName ?? "-") "
                    + "ms from task start: fetch=\(at(transaction.fetchStartDate)) "
                    + "dns=\(at(transaction.domainLookupStartDate))-\(at(transaction.domainLookupEndDate)) "
                    + "connect=\(at(transaction.connectStartDate))-\(at(transaction.connectEndDate)) "
                    + "tls=\(at(transaction.secureConnectionStartDate))-\(at(transaction.secureConnectionEndDate)) "
                    + "reqStart=\(at(transaction.requestStartDate)) reqEnd=\(at(transaction.requestEndDate)) "
                    + "respStart=\(at(transaction.responseStartDate)) respEnd=\(at(transaction.responseEndDate)) "
                    + "status=\((transaction.response as? HTTPURLResponse)?.statusCode ?? -1) "
                    + "rxBody=\(transaction.countOfResponseBodyBytesReceived)"
            )
        }
    }
}
#endif
