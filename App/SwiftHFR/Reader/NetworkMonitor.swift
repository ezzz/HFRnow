import Foundation
import Network
import os

/// Whether the device is on Wi-Fi (or Ethernet) right now, for the "Wi-Fi only" image mode. One monitor for the app,
/// started at launch (`AppEnvironment.make`) so the first topic opened already knows the network.
final class NetworkMonitor: Sendable {
    /// The app's monitor.
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let state = OSAllocatedUnfairLock(initialState: PathState())

    private init() {
        monitor.pathUpdateHandler = { [state] path in
            state.withLock { $0 = PathState(isKnown: true, isUnmetered: Self.isUnmetered(path)) }
        }
        monitor.start(queue: DispatchQueue(label: "SwiftHFR.NetworkMonitor"))
        // Seeded from the path known now unless an update already arrived (updates are asynchronous).
        let current = Self.isUnmetered(monitor.currentPath)
        state.withLock { if !$0.isKnown { $0 = PathState(isKnown: true, isUnmetered: current) } }
    }

    /// Starts the monitor if it is not running yet.
    static func start() { _ = shared }

    /// True on an unmetered Wi-Fi or Ethernet path; false on cellular, a hotspot marked expensive, Low Data Mode or offline.
    var isOnWiFi: Bool { state.withLock { $0.isUnmetered } }

    /// What the monitor knows: nothing yet, or whether the path is unmetered.
    private struct PathState {
        var isKnown = false
        var isUnmetered = false
    }

    private static func isUnmetered(_ path: NWPath) -> Bool {
        path.status == .satisfied && !path.isExpensive && !path.isConstrained
            && (path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet))
    }
}
