import Foundation
import UIKit

extension BuildReport {
    /// The report of the running app on this device.
    @MainActor
    static var current: BuildReport {
        var info = utsname()
        uname(&info)
        let machine = withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: info.machine)) { String(cString: $0) }
        }
        let device = UIDevice.current
        return BuildReport(
            version: .current,
            system: "\(device.systemName) \(device.systemVersion)",
            model: deviceModel(machine: machine, environment: ProcessInfo.processInfo.environment)
        )
    }
}
