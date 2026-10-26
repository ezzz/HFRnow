/// The `rehost_resize_before_upload` setting: longest side, in pixels, images are downscaled to before upload.
public enum RehostMaxDimension: Int, Sendable, Codable, CaseIterable {
    /// 400 px.
    case px400 = 400
    /// 600 px.
    case px600 = 600
    /// 800 px.
    case px800 = 800
    /// 1000 px.
    case px1000 = 1000
    /// 1200 px (default).
    case px1200 = 1200
}
