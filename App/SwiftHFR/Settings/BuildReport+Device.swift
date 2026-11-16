import Foundation
import UIKit

extension BuildReport {
    /// The report of the running app on this device.
    @MainActor
    static var current: BuildReport {
        var info = utsname()
        uname(&info)
        // The capacity is read before the closure: reading `info.machine` inside it overlaps the `&info.machine` access.
        let capacity = MemoryLayout.size(ofValue: info.machine)
        let machine = withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) }
        }
        let device = UIDevice.current
        return BuildReport(
            version: .current,
            system: "\(device.systemName) \(device.systemVersion)",
            model: deviceModel(machine: machine, environment: ProcessInfo.processInfo.environment)
        )
    }
}
