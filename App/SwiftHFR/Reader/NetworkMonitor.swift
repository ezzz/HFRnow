import Foundation
import Network
import os

/// Whether the device is on Wi-Fi (or Ethernet) right now, for the "Wi-Fi only" image mode. One monitor for the app.
final class NetworkMonitor: Sendable {
    /// The app's monitor, started on first use.
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let state = OSAllocatedUnfairLock(initialState: false)

    private init() {
        monitor.pathUpdateHandler = { [state] path in
            let unmetered = path.status == .satisfied && !path.isExpensive && !path.isConstrained
                && (path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet))
            state.withLock { $0 = unmetered }
        }
        monitor.start(queue: DispatchQueue(label: "SwiftHFR.NetworkMonitor"))
    }

    /// True on an unmetered Wi-Fi or Ethernet path; false on cellular, a hotspot marked expensive, Low Data Mode or offline.
    var isOnWiFi: Bool { state.withLock { $0 } }
}
