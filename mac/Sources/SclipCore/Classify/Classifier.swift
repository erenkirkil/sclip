import Foundation

/// Sınır kaynaklı düşme nedeni (B-8.3.3, B-8.3.10).
public enum DropReason: Sendable, Equatable {
    case textTooLarge
    case overCap(EntryKind)
}

/// Sınıflandırma sonucu: öğe, sınır kaynaklı düşme ya da tanınmayan içerik.
public enum Classification: Sendable, Equatable {
    case payload(Payload)
    case drop(DropReason)
    case none
}

/// Pano görüntüsünü tek bir `Payload`'a indirger (`behavior.md` §8.3, §8.6).
public struct Classifier: Sendable {
    public let caps: SizeCaps
    private let files: any FileReading

    public init(caps: SizeCaps = .default, files: any FileReading = DiskFileReading()) {
        self.caps = caps
        self.files = files
    }

    public func classify(_ clip: RawClip) -> Classification {
        // Dosya URL'si görsel/metin temsillerinin önüne geçer (B-8.3.8).
        if !clip.files.isEmpty {
            return .payload(FileListClassifier(caps: caps, files: files).classify(clip.files))
        }
        switch clip.items.count {
        case 0: return .none
        case 1: return classifyItem(clip.items[0])
        default: return classifyMany(clip.items)
        }
    }

    /// Tek öğenin öncelik zinciri (B-8.3.1–B-8.3.6).
    func classifyItem(_ item: RawItem) -> Classification {
        var chain = ItemChain(caps: caps, item: item)
        return chain.run()
    }

    // MARK: - Çoklu öğe (B-8.3.7, B-8.3.10)

    private func classifyMany(_ items: [RawItem]) -> Classification {
        // Hepsi görsel yükte hiçbir görsel sığmazsa karışık yük kuralı uygulanır (B-8.3.7).
        if let images = allImages(items), let group = imageGroup(images) { return .payload(group) }
        var best: Payload?
        var firstDrop: DropReason?
        for item in items {
            switch classifyItem(item) {
            case .payload(let p):
                // Eşitlikte ilk gelen kalır: yalnız kesin büyük sıra yer değiştirir.
                if best.map({ Self.rank(p) > Self.rank($0) }) ?? true { best = p }
            case .drop(let reason):
                if firstDrop == nil { firstDrop = reason }
            case .none:
                break
            }
        }
        if let best { return .payload(best) }
        return firstDrop.map(Classification.drop) ?? .none
    }

    /// Her öğe (RTF kapısı kapalıyken) sihirli baytı tutan bir görsel taşıyorsa öğe başına bir görsel:
    /// sınıra sığan ilki, yoksa sınırı aşan ilki. Aksi hâlde `nil` (karışık yük).
    private func allImages(_ items: [RawItem]) -> [ImageItem]? {
        var out: [ImageItem] = []
        for item in items {
            guard !RtfGate.isOpen(item) else { return nil }
            let candidates = BinaryProbe.images(in: item)
            guard let pick = candidates.first(where: { $0.data.count <= caps.imageBytes }) ?? candidates.first
            else { return nil }
            out.append(pick)
        }
        return out
    }

    /// Sınırı aşanlar çıkarılır; kalan ≥ 2 görselin toplamı sınır içindeyse `imageSet`, değilse kalanların ilki;
    /// hiçbiri kalmazsa `nil`.
    private func imageGroup(_ images: [ImageItem]) -> Payload? {
        let fitting = images.filter { $0.data.count <= caps.imageBytes }
        let total = fitting.reduce(0) { $0 + $1.data.count }
        if fitting.count >= 2, total <= caps.imageBytes { return .imageSet(fitting) }
        return fitting.first.map(Payload.image)
    }

    /// Karışık çoklu öğede zenginlik sırası: image > svg > pdf > richText > url > color > text.
    static func rank(_ payload: Payload) -> Int {
        switch payload {
        case .image, .imageSet: return 6
        case .svg: return 5
        case .pdf: return 4
        case .richText: return 3
        case .url: return 2
        case .color: return 1
        case .text, .files: return 0
        }
    }
}

/// Tek öğenin zinciri. İlk karşılaşılan sınır düşmesi, zincir başka öğe üretmezse sonuç olur.
struct ItemChain {
    let caps: SizeCaps
    let item: RawItem
    private(set) var pendingDrop: DropReason?

    init(caps: SizeCaps, item: RawItem) {
        self.caps = caps
        self.item = item
    }

    mutating func run() -> Classification {
        let plain = item.formats[.plainText].map(TextDecoding.utf8)
        let gateOpen = RtfGate.isOpen(item)
        // E34: PDF probu yalnız düz metin yoksa ya da boş/boşluksa koşar.
        let plainBlank = plain.map { TextWhitespace.trim($0).isEmpty } ?? true
        if !gateOpen, let payload = binary(allowPdf: plainBlank) { return .payload(payload) }
        let text = textLegs(plain)
        switch text {
        case .payload:
            return text
        case .drop where !(plain?.isEmpty ?? true):
            return text   // sınırı aşan düz metin öğeyi hemen düşürür (B-8.3.3, Flutter ile aynı)
        case .drop, .none:
            break
        }
        // Zengin doküman geri dönüşü (B-8.3.6): kapı açıktı, metin yolları (sınırı aşan yalnız-HTML dahil)
        // öğe üretmedi. Geri dönüş de boşsa metin yolunun düşmesi, o da yoksa bekleyen düşme geçerlidir.
        if gateOpen, let payload = binary(allowPdf: true) { return .payload(payload) }
        if case .drop = text { return text }
        return pendingDrop.map(Classification.drop) ?? .none
    }

    mutating func note(_ reason: DropReason) {
        if pendingDrop == nil { pendingDrop = reason }
    }

    /// İkili problar (B-8.3.2): png → jpeg → gif → webp → SVG baytları → PDF.
    private mutating func binary(allowPdf: Bool) -> Payload? {
        for image in BinaryProbe.images(in: item) {
            if image.data.count <= caps.imageBytes { return .image(image) }
            note(.overCap(.image))
        }
        if let svg = svgBytes() { return .svg(svg) }
        if allowPdf, let data = item.formats[.pdf], !data.isEmpty {
            if data.count <= caps.pdfBytes { return .pdf(data) }
            note(.overCap(.pdf))
        }
        return nil
    }

    /// SVG bayt yolu: sınır, sanitizer (katı UTF-8 dahil) ve boş olmayan işaretleme.
    private mutating func svgBytes() -> String? {
        guard let data = item.formats[.svg], !data.isEmpty else { return nil }
        guard data.count <= caps.svgBytes else {
            note(.overCap(.svg))
            return nil
        }
        guard SvgSanitizer.isSafe(data, caps: caps) else { return nil }
        let xml = String(decoding: data, as: UTF8.self)
        return TextWhitespace.trim(xml).isEmpty ? nil : xml
    }
}
