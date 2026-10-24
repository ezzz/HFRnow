import HFRModels
import HFRNetwork
import HFRParsing

/// Namespace marker for the HFRClient module.
/// Multi-step forum flows (fetch → parse → submit → classify) composed from HFRNetwork and HFRParsing (ADR 0008).
public enum HFRClient {
    public static let moduleName = "HFRClient"
}
