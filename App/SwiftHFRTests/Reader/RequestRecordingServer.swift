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

    init(status: Int = 200, body: String = "<html><body>player</body></html>") throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { [weak self] state in
            if case .ready = state { self?.lock.withLock { self?.isReady = true } }
        }
        let reply = Data(
            ("HTTP/1.1 \(status) X\r\nContent-Type: text/html\r\nContent-Length: \(body.utf8.count)\r\n"
                + "Connection: close\r\n\r\n\(body)").utf8
        )
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.start(queue: self.queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, _ in
                let head = String(bytes: data ?? Data(), encoding: .utf8) ?? ""
                self.lock.withLock { self.heads.append(head) }
                connection.send(content: reply, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        listener.start(queue: queue)
    }

    var port: UInt16 { listener.port?.rawValue ?? 0 }

    /// The request heads received so far (request line and headers).
    var requests: [String] { lock.withLock { heads } }

    /// The value of `name` in the first request, nil when the header was not sent.
    func header(_ name: String) -> String? {
        guard let head = requests.first else { return nil }
        let prefix = name.lowercased() + ":"
        for line in head.split(separator: "\r\n") where line.lowercased().hasPrefix(prefix) {
            return line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    func ready() async throws {
        for _ in 0..<500 {
            if lock.withLock({ isReady }) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw URLError(.cannotConnectToHost)
    }

    func stop() { listener.cancel() }
}
