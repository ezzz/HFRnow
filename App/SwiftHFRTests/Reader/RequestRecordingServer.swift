import Foundation
import Network

/// A TCP listener on 127.0.0.1 that records the head of each HTTP request it gets and answers with a fixed status:
/// proof of what a web view sends (headers), without any external network.
final class RequestRecordingServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "SwiftHFRTests.RequestRecordingServer")
    private let lock = NSLock()
    private var heads: [String] = []
    private var isReady = false
    /// The listener left its setup: ready, failed or cancelled (issue #801: an event, not a polling loop).
    private let settled = TestEvent()
    /// The first request head arrived.
    private let requested = TestEvent()

    init(status: Int = 200, body: String = "<html><body>player</body></html>") throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.lock.withLock { self?.isReady = true }
                self?.settled.fire()
            case .failed, .cancelled:
                self?.settled.fire()
            default:
                break
            }
        }
        let reply = Data(
            ("HTTP/1.1 \(status) X\r\nContent-Type: text/html\r\nContent-Length: \(body.utf8.count)\r\n"
                + "Connection: close\r\n\r\n\(body)").utf8
        )
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.start(queue: self.queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, _ in
                // WebKit may open a connection it never writes to (preconnect): that is not a request.
                guard let data, !data.isEmpty, let head = String(bytes: data, encoding: .utf8) else {
                    connection.cancel()
                    return
                }
                self.lock.withLock { self.heads.append(head) }
                self.requested.fire()
                connection.send(content: reply, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        listener.start(queue: queue)
    }

    var port: UInt16 { listener.port?.rawValue ?? 0 }

    /// The request heads received so far (request line and headers).
    var requests: [String] { lock.withLock { heads } }

    /// The value of `name` in the first GET, nil when the header was not sent.
    func header(_ name: String) -> String? {
        guard let head = requests.first(where: { $0.hasPrefix("GET ") }) else { return nil }
        let prefix = name.lowercased() + ":"
        for line in head.split(separator: "\r\n") where line.lowercased().hasPrefix(prefix) {
            return line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// Returns once the listener accepts connections; throws when it failed, or did not start within `timeout`.
    func ready(timeout: Duration = .seconds(60)) async throws {
        guard await settled.wait(timeout: timeout), lock.withLock({ isReady }) else { throw URLError(.cannotConnectToHost) }
    }

    /// True once a request head arrived, false when `timeout` passed first.
    func firstRequest(timeout: Duration = .seconds(120)) async -> Bool {
        await requested.wait(timeout: timeout)
    }

    func stop() { listener.cancel() }
}
