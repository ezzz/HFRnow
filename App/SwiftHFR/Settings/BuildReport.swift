import Foundation

/// What a tester pastes in a bug report: version, build, commit, OS and device model, and nothing personal (#970).
struct BuildReport: Equatable, Sendable {
    let version: AppVersion
    /// `iOS 27.0`.
    let system: String
    /// `iPhone18,2`; on the simulator the model it simulates.
    let model: String

    /// `SwiftHFR 1.0 (42) · cd04954 · iOS 27.0 · iPhone18,2`.
    var text: String {
        "SwiftHFR \(version.display) · \(version.commit) · \(system) · \(model)"
    }

    /// The device model: the simulator reports its host in `utsname`, so its own identifier wins; an empty value is `?`.
    static func deviceModel(machine: String, environment: [String: String]) -> String {
        if let simulated = environment["SIMULATOR_MODEL_IDENTIFIER"], !simulated.isEmpty { return simulated }
        return machine.isEmpty ? "?" : machine
    }
}
