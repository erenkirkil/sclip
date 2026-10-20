import Combine
import Foundation
import SclipCore

public enum Visibility: Sendable { case hidden, shown, pasting }
public enum Page: Sendable { case history, settings }
public enum ToggleSource: Sendable { case hotkey, tray, secondInstance }

/// Panelin senkron durum makinesi (B-7.1.1 – B-7.1.9). Tüm geçişler ana thread'de, beklemesizdir (E1).
@MainActor
public final class PanelViewModel: ObservableObject {
    @Published public private(set) var visibility: Visibility = .hidden
    @Published public private(set) var page: Page = .history
    @Published public private(set) var pinned: Bool
    @Published public private(set) var dialogOpen = false

    /// Arama çubuğu açık mı (E17, B-6.2.1); SearchViewModel bağlar.
    public var searchOpen: () -> Bool = { false }
    /// Esc'nin arama katmanı: çubuğu kapatır ve sorguyu temizler; SearchViewModel bağlar.
    public var closeSearch: () -> Void = {}
    public var autoHideOnBlur: Bool
    /// `alwaysPastePlainText` ayarı (B-6.6.16); yalnız richText'i etkiler (B-8.9.1).
    public var alwaysPastePlainText = false
    /// Başarılı yazımın makbuzu; `CaptureEngine.noteOwnWrite`'a bağlanır.
    public var onOwnWrite: (WriteReceipt) -> Void = { _ in }
    /// Başarılı yazımdan sonra öğeyi öne alır (B-7.1.5); `HistoryStore.touch`'a bağlanır.
    public var onTouch: (EntryID) -> Void = { _ in }
    /// Pencere her gizlendiğinde çağrılır; sorguyu temizler (SearchViewModel bağlar).
    public var onHidden: () -> Void = {}

    private let window: PanelWindowPort
    private let paster: PastePort
    private let sink: ClipboardSink
    private let refresh: RefreshPort
    private let clock: Clock
    private let trayBlurWindow: TimeInterval
    /// Son blur-gizleme anı (E7); başka bir gösterim/gizleme bunu sıfırlar.
    private var lastBlurHide: Date?
    /// Her yapıştırmada artar; eski bir tamamlama yeni yapıştırmayı bitiremez.
    private var pasteGeneration: UInt = 0

    public init(
        window: PanelWindowPort, paster: PastePort, sink: ClipboardSink, refresh: RefreshPort,
        clock: Clock, pinned: Bool, autoHideOnBlur: Bool, trayBlurWindow: TimeInterval = 0.2
    ) {
        self.window = window
        self.paster = paster
        self.sink = sink
        self.refresh = refresh
        self.clock = clock
        self.pinned = pinned
        self.autoHideOnBlur = autoHideOnBlur
        self.trayBlurWindow = trayBlurWindow
    }

    // MARK: - Göster / gizle

    public func toggle(_ source: ToggleSource) {
        switch visibility {
        case .pasting:
            return
        case .hidden:
            // E7: blur'un az önce gizlediği paneli tepsi tıklaması yeniden açmaz.
            if source == .tray, let hiddenAt = lastBlurHide,
                clock.now().timeIntervalSince(hiddenAt) <= trayBlurWindow
            {
                return
            }
            present()
        case .shown:
            if window.isKey || pinned {
                hideWindow(byBlur: false)
            } else {
                present()  // B-7.1.3: görünür ama odakta değil → öne getir, yeniden yakala
            }
        }
    }

    /// Panel panelden çıkıp başka uygulamaya geçtiğinde (pencere key'ini kaybetti, B-7.1.8).
    public func blur() {
        guard visibility == .shown, !pinned, autoHideOnBlur else { return }
        hideWindow(byBlur: true)
    }

    /// Kapat düğmesi / Cmd+W.
    public func requestHide() {
        guard visibility == .shown else { return }
        hideWindow(byBlur: false)
    }

    /// Esc: tek çağrı tek katman — diyalog → ayarlar → arama → gizle (B-6.2.1, E16).
    public func escape() {
        guard visibility == .shown else { return }
        if dialogOpen {
            setDialogOpen(false)
        } else if page == .settings {
            closeSettings()
        } else if searchOpen() {
            closeSearch()
        } else {
            hideWindow(byBlur: false)
        }
    }

    // MARK: - Yapıştırma

    public func paste(_ entry: Entry, imageIndex: Int?) {
        guard visibility == .shown else { return }
        let kind = entry.payload.kind
        let plainOnly = alwaysPastePlainText && kind == .richText
        let index = kind == .imageSet ? imageIndex : nil
        let receipt: WriteReceipt
        do {
            receipt = try sink.write(entry, plainOnly: plainOnly, imageIndex: index)
        } catch {
            return  // B-7.1.5: panel shown kalır, touch/gizleme yok
        }
        onOwnWrite(receipt)
        onTouch(entry.id)
        // Durum port çağrısından önce döner: window.hide() eşzamanlı resign-key ile blur()'u
        // yeniden tetikleyebilir; o çağrı .pasting'i görüp yok sayılmalı (E9).
        visibility = .pasting
        lastBlurHide = nil
        pasteGeneration &+= 1
        let generation = pasteGeneration
        window.hide()
        onHidden()
        paster.pasteToTarget { [weak self] _ in
            // B-7.1.6: pasting'ten her çıkış hidden'a gider; shown'a dönüş yok.
            self?.finishPasting(generation)
        }
    }

    /// Bayat ya da yinelenen tamamlama (eski bir yapıştırmanın kapanışı) yok sayılır.
    private func finishPasting(_ generation: UInt) {
        guard visibility == .pasting, generation == pasteGeneration else { return }
        visibility = .hidden
    }

    // MARK: - Durum

    public func setPinned(_ value: Bool) { pinned = value }
    public func openSettings() { page = .settings }
    public func closeSettings() { page = .history }
    public func setDialogOpen(_ value: Bool) { dialogOpen = value }

    // MARK: - Özel

    /// Senkron yakala → hedefi kaydet → göster → odakla (B-7.1.2, B-8.8.3, B-7.2.1, E6, E17).
    private func present() {
        refresh.refreshNow()
        paster.captureTarget()  // pid, panel öne çıkmadan önce alınır
        lastBlurHide = nil
        visibility = .shown
        window.show()
        window.focus(focusTarget())
    }

    private func focusTarget() -> FocusTarget {
        if page == .settings { return .settings }
        return searchOpen() ? .searchField : .firstRow
    }

    private func hideWindow(byBlur: Bool) {
        // Durum port çağrısından önce döner (eşzamanlı resign-key → blur() yeniden girişi, E1).
        visibility = .hidden
        lastBlurHide = byBlur ? clock.now() : nil
        window.hide()
        onHidden()
    }
}
