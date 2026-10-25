import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// A request as seen by `LoopbackServer`.
struct ReceivedRequest: Sendable {
    let method: String
    let path: String
    let headers: [String: String]  // lowercased names
    let body: Data
}

/// What `LoopbackServer` answers.
struct ServerReply: Sendable {
    var status = 200
    var headers: [String: String] = [:]
    var body = Data()
    /// Never answers, to exercise timeouts and cancellation.
    var hangs = false
}

/// Minimal HTTP/1.1 server on 127.0.0.1 (no external network), because swift-corelibs-foundation
/// cannot simulate redirects through `URLProtocol` and the redirect policy must be tested for real.
final class LoopbackServer: @unchecked Sendable {
    typealias Route = @Sendable (ReceivedRequest) -> ServerReply

    private let descriptor: Int32
    private let route: Route
    private let lock = NSLock()
    private var received: [ReceivedRequest] = []
    private var stopped = false
    /// Base URL such as `http://127.0.0.1:PORT`.
    let baseURL: URL
    private let port: UInt16
    private let closed = DispatchSemaphore(value: 0)

    init(route: @escaping Route) throws {
        self.route = route
        #if canImport(Glibc)
        let streamType = Int32(SOCK_STREAM.rawValue)
        #else
        let streamType = SOCK_STREAM
        #endif
        let listener = socket(AF_INET, streamType, 0)
        guard listener >= 0 else { throw POSIXError(.EIO) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = UInt32(0x7F00_0001).bigEndian
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, listen(listener, 16) == 0 else { close(listener); throw POSIXError(.EADDRINUSE) }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(listener, $0, &length) }
        }
        descriptor = listener
        port = UInt16(bigEndian: address.sin_port)
        guard let url = URL(string: "http://127.0.0.1:\(port)") else { throw POSIXError(.EINVAL) }
        baseURL = url
        Thread.detachNewThread { [self] in acceptLoop() }
    }

    /// Requests received so far.
    var requests: [ReceivedRequest] { lock.lock(); defer { lock.unlock() }; return received }

    /// Stops accepting connections. The accept thread closes the descriptor itself: closing it from here would
    /// let the number be reused by another server while the old thread is still calling `accept` on it.
    func stop() {
        lock.lock()
        let wasStopped = stopped
        stopped = true
        lock.unlock()
        if !wasStopped { wakeAcceptThread() }
        // Every caller waits (and passes the signal on), so the listener is gone whenever stop() returns.
        // Bounded so a failed wake-up (socket or connect error) cannot hang teardown.
        guard closed.wait(timeout: .now() + 2) == .success else { return }
        closed.signal()
    }

    private var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }

    /// Connects once to ourselves so a blocked `accept` returns (shutdown does not wake it on macOS).
    private func wakeAcceptThread() {
        #if canImport(Glibc)
        let streamType = Int32(SOCK_STREAM.rawValue)
        #else
        let streamType = SOCK_STREAM
        #endif
        let probe = socket(AF_INET, streamType, 0)
        guard probe >= 0 else { return }
        defer { close(probe) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = UInt32(0x7F00_0001).bigEndian
        _ = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(probe, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
    }

    private func acceptLoop() {
        defer {
            close(descriptor)
            closed.signal()
        }
        while true {
            let client = accept(descriptor, nil, nil)
            if isStopped {
                if client >= 0 { close(client) }
                return
            }
            if client < 0 { return }
            Thread.detachNewThread { [self] in serve(client) }
        }
    }

    private func serve(_ client: Int32) {
        defer { close(client) }
        guard let request = readRequest(client) else { return }
        lock.lock()
        received.append(request)
        lock.unlock()
        let reply = route(request)
        if reply.hangs {
            Thread.sleep(forTimeInterval: 5)
            return
        }
        var head = "HTTP/1.1 \(reply.status) X\r\nContent-Length: \(reply.body.count)\r\nConnection: close\r\n"
        for (name, value) in reply.headers { head += "\(name): \(value)\r\n" }
        write(client, Data(head.utf8) + Data("\r\n".utf8) + reply.body)
    }

    private func readRequest(_ client: Int32) -> ReceivedRequest? {
        var buffer = Data()
        let separator = Data("\r\n\r\n".utf8)
        while buffer.range(of: separator) == nil {
            guard let chunk = read(client), !chunk.isEmpty else { return nil }
            buffer.append(chunk)
        }
        guard let split = buffer.range(of: separator) else { return nil }
        let headText = String(bytes: buffer[..<split.lowerBound], encoding: .utf8) ?? ""
        var body = Data(buffer[split.upperBound...])
        var lines = headText.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let expected = Int(headers["content-length"] ?? "0") ?? 0
        while body.count < expected {
            guard let chunk = read(client), !chunk.isEmpty else { break }
            body.append(chunk)
        }
        return ReceivedRequest(method: String(requestLine[0]), path: String(requestLine[1]), headers: headers, body: body)
    }

    private func read(_ client: Int32) -> Data? {
        var bytes = [UInt8](repeating: 0, count: 4096)
        let count = recv(client, &bytes, bytes.count, 0)
        return count < 0 ? nil : Data(bytes[..<count])
    }

    private func write(_ client: Int32, _ data: Data) {
        data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let sent = send(client, raw.baseAddress.map { $0 + offset }, raw.count - offset, 0)
                if sent <= 0 { return }
                offset += sent
            }
        }
    }
}
