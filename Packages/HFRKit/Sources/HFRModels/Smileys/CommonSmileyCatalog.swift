import Foundation

/// Access to the smiley catalogue shipped inside the HFRModels bundle.
public enum CommonSmileyCatalog {
    /// Decodes a catalogue from JSON data (the bundled file's format).
    public static func decode(_ data: Data) throws -> [CommonSmiley] {
        try JSONDecoder().decode([CommonSmiley].self, from: data)
    }

    /// The catalogue shipped with the module, in the legacy order.
    public static func bundled() throws -> [CommonSmiley] {
        guard let location = Bundle.module.url(forResource: "CommonSmileys", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try decode(Data(contentsOf: location))
    }
}
