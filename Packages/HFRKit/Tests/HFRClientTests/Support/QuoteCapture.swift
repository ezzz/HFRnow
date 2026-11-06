import Foundation

/// The quote prefills legacy read on the captured composers (LOT-004 form oracles).
enum QuoteCapture {
    /// `result.legacy.contentForm` (line breaks `\n`) and `contentFormRaw` (line breaks as served) of oracle `id`.
    static func prefill(_ id: String) throws -> (decoded: String, served: String) {
        let url = Capture.directory.deletingLastPathComponent().appendingPathComponent("LOT-004/\(id).oracle.json")
        let root = try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        let legacy = (root?["result"] as? [String: Any])?["legacy"] as? [String: Any]
        guard let decoded = legacy?["contentForm"] as? String, let served = legacy?["contentFormRaw"] as? String else {
            throw Capture.Missing(name: id + ".oracle contentForm")
        }
        return (decoded, served)
    }
}
