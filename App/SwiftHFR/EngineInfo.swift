import HFRClient
import HFRModels
import HFRNetwork
import HFRParsing
import HFRStorage

/// The HFRKit modules the app links; referencing each one proves the local package is wired in.
enum EngineInfo {
    /// Module names in dependency order, read from the modules themselves rather than hard-coded.
    static let linkedModules: [String] = [
        HFRModels.moduleName,
        HFRParsing.moduleName,
        HFRNetwork.moduleName,
        HFRStorage.moduleName,
        HFRClient.moduleName
    ]
}
