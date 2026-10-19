/// Boyut sınırları (`behavior.md` Sabitler tablosu, B-8.6.x). Bayt sınırları bayt, `textChars`
/// UTF-16 kod birimi sayar (Flutter `maxTextChars` eşdeğeri).
public struct SizeCaps: Sendable, Equatable {
    public var textChars = 2_097_152
    public var rtfBytes = 2_097_152
    public var svgBytes = 20 << 20
    public var pdfBytes = 25 << 20
    public var imageBytes = 25 << 20
    public var fileImageBytes = 25 << 20
    public var totalBudgetBytes = 150 << 20
    public var weightFloorChars = 65_536
    public var searchIndexChars = 8_192
    public var previewScalars = 120

    public init() {}

    public static let `default` = SizeCaps()
}
