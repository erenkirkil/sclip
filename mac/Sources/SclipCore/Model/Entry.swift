import Foundation

/// Geçmişteki bir kayıt. `contentHash` oluşturulurken hesaplanır ve `touched` ile korunur (B-8.1.4).
public struct Entry: Sendable, Equatable, Identifiable {
    public let id: EntryID
    public var createdAt: Date
    public let payload: Payload
    public let isSensitive: Bool
    public let contentHash: String

    public init(id: EntryID, createdAt: Date, payload: Payload, isSensitive: Bool) {
        self.id = id
        self.createdAt = createdAt
        self.payload = payload
        self.isSensitive = isSensitive
        self.contentHash = ContentHash.of(payload)
    }

    /// Aynı id ve hash ile zamanı yenilenmiş kopya.
    public func touched(at date: Date) -> Entry {
        var copy = self
        copy.createdAt = date
        return copy
    }
}
