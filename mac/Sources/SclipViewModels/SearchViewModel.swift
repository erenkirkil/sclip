import Combine
import Foundation

/// Arama çubuğunun durumu (B-6.5.1, B-6.5.2, B-6.2.3). Filtreleme `HistoryViewModel`'dedir.
@MainActor
public final class SearchViewModel: ObservableObject {
    @Published public private(set) var isOpen = false
    @Published public var query = ""

    private let focusSubject = PassthroughSubject<Void, Never>()

    /// Arama kutusuna odak + tümünü seç isteği. `open()` her çağrıda yayar: kapalıyken açılışta
    /// odak gerekir (Flutter `_openSearch` da koşulsuz ister), açıkken Cmd+F tekrarı (B-6.2.3).
    /// Yayın `isOpen` güncellendikten sonra olur; UI çubuk henüz bağlanmadıysa görünür olunca da odaklamalı.
    public var focusRequest: AnyPublisher<Void, Never> { focusSubject.eraseToAnyPublisher() }

    public init() {}

    public func open() {
        isOpen = true
        focusSubject.send()
    }

    /// Esc / kapat düğmesi: çubuğu kapatır ve sorguyu siler (B-6.2.1).
    public func close() {
        if isOpen { isOpen = false }
        clearQuery()
    }

    /// Panel gizlenince ve temizlemede: yalnız sorgu gider, çubuk açık kalır (B-6.5.2, B-8.8.9).
    public func clearQuery() {
        if !query.isEmpty { query = "" }
    }
}
