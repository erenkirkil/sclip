import Foundation

/// Desteklenen görsel biçimleri (B-8.1.1).
public enum ImageFormat: String, Sendable, CaseIterable {
    case png, jpeg, gif, webp
}

/// Biçimiyle birlikte tek görselin baytları.
public struct ImageItem: Sendable, Equatable {
    public let data: Data
    public let format: ImageFormat

    public init(data: Data, format: ImageFormat) {
        self.data = data
        self.format = format
    }
}
