import Foundation

/// Geri yazımın makbuzu: yazımdan hemen sonraki sayaç ve yazılan içeriğin imzası (B-8.8.8, E30).
public struct WriteReceipt: Sendable {
    public let change: Int
    public let signature: String

    public init(change: Int, signature: String) {
        self.change = change
        self.signature = signature
    }
}

/// Platform pano yazma portu. Ana thread'de çağrılır.
public protocol ClipboardSink: AnyObject {
    func write(_ entry: Entry, plainOnly: Bool, imageIndex: Int?) throws -> WriteReceipt
}
