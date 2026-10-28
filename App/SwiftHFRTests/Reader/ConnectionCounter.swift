import Foundation
import Network

/// A TCP listener on 127.0.0.1 that counts incoming connections and answers each with a 404: proof that a page made
/// (or did not make) a request, without any external network.
final class ConnectionCounter: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "SwiftHFRTests.ConnectionCounter")
    private let lock = NSLock()
    private var count = 0
    private var isReady = false

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { [weak self] state in
            if case .ready = state { self?.lock.withLock { self?.isReady = true } }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.lock.withLock { self.count += 1 }
            connection.start(queue: self.queue)
            let reply = Data("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
            connection.send(content: reply, completion: .contentProcessed { _ in connection.cancel() })
        }
        listener.start(queue: queue)
    }

    /// Connections received so far.
    var connections: Int { lock.withLock { count } }

    /// The port the listener got.
    var port: UInt16 { listener.port?.rawValue ?? 0 }

    /// Returns once the listener accepts connections.
    func ready() async throws {
        for _ in 0..<500 {
            if lock.withLock({ isReady }) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw URLError(.cannotConnectToHost)
    }

    func stop() { listener.cancel() }
}
