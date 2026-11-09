import AppKit
import Combine
import SclipCore
import SclipViewModels

@MainActor
public final class SettingsView: NSView {
    public let closeButton = FirstMouseButton(frame: .zero)
    public let changeHotkeyButton = FirstMouseButton(frame: .zero)
    public let hotkeySubtitleLabel = NSTextField(labelWithString: "")
    public let themeControl = NSSegmentedControl(frame: .zero)

    private var maxItemsPopup = NSPopUpButton(frame: .zero)
    private var maxItemsSubtitleLabel = NSTextField(labelWithString: "")
    private var sensitiveSwitch = NSSwitch(frame: .zero)
    private var sensitiveSubtitleLabel = NSTextField(labelWithString: "")
    private var lockClearSwitch = NSSwitch(frame: .zero)
    private var plainTextSwitch = NSSwitch(frame: .zero)
    private var autoHideSwitch = NSSwitch(frame: .zero)
    private var alwaysOnTopSwitch = NSSwitch(frame: .zero)
    private var pollingPopup = NSPopUpButton(frame: .zero)
    private var pollingSubtitleLabel = NSTextField(labelWithString: "")
    private var clearStartupSwitch = NSSwitch(frame: .zero)
    private let resetButton = FirstMouseButton(frame: .zero)

    private let settingsViewModel: SettingsViewModel
    private let panelViewModel: PanelViewModel
    private let strings: Strings
    private var cancellables: Set<AnyCancellable> = []
    private var isRecordingHotkey = false

    public init(
        settingsViewModel: SettingsViewModel,
        panelViewModel: PanelViewModel,
        strings: Strings
    ) {
        self.settingsViewModel = settingsViewModel
        self.panelViewModel = panelViewModel
        self.strings = strings
        super.init(frame: .zero)

        setupViews()
        bind()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func focusInitialControl() {
        window?.makeFirstResponder(closeButton)
    }

    public func dismissActiveModalIfNeeded() {
        (window?.contentView as? PanelContentView)?.dismissModal()
        stopRecordingIfNeeded()
    }

    private func stopRecordingIfNeeded() {
        guard isRecordingHotkey else { return }
        isRecordingHotkey = false
        settingsViewModel.endRecording()
        changeHotkeyButton.title = strings[.settingsToggleHotkeyChange]
        changeHotkeyButton.isEnabled = true
    }

    // MARK: - Setup

    private func setupViews() {
        let headerBar = makeHeaderBar()

        let scrollView = NSScrollView(frame: .zero)
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 12, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let sections = [
            makeShortcutsSection(),
            makeAppearanceSection(),
            makeHistorySection(),
            makeWindowSection(),
            makeAdvancedSection(),
        ]

        resetButton.bezelStyle = .rounded
        resetButton.controlSize = .small
        resetButton.title = strings[.settingsResetButton]
        resetButton.target = self
        resetButton.action = #selector(handleReset)

        for section in sections {
            stack.addArrangedSubview(section)
            section.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -20).isActive = true
        }
        stack.addArrangedSubview(resetButton)

        let clipView = FlippedClipView()
        clipView.drawsBackground = false
        clipView.documentView = stack
        scrollView.contentView = clipView

        addSubview(headerBar)
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            headerBar.topAnchor.constraint(equalTo: topAnchor),
            headerBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerBar.heightAnchor.constraint(equalToConstant: 28),

            scrollView.topAnchor.constraint(equalTo: headerBar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.topAnchor.constraint(equalTo: clipView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
        ])
    }

    private func makeHeaderBar() -> NSView {
        let bar = NSView(frame: .zero)
        bar.translatesAutoresizingMaskIntoConstraints = false
        let title = NSTextField(labelWithString: strings[.settingsTitle])
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false

        let closeTooltip = strings[.settingsClose]
        let cfg = NSImage.SymbolConfiguration(pointSize: Metrics.rowButtonIcon, weight: .regular)
        closeButton.isBordered = false
        closeButton.imagePosition = .imageOnly
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: closeTooltip)?.withSymbolConfiguration(cfg)
        closeButton.toolTip = closeTooltip
        closeButton.setAccessibilityLabel(closeTooltip)
        closeButton.target = self
        closeButton.action = #selector(handleClose)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        bar.addSubview(title)
        bar.addSubview(closeButton)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 10),
            title.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -8),
            closeButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: Metrics.toolbarButton),
            closeButton.heightAnchor.constraint(equalToConstant: Metrics.toolbarButton),
        ])
        return bar
    }

    private func makeShortcutsSection() -> SettingsSection {
        let section = SettingsSection(title: strings[.settingsSectionShortcuts])
        let titleLabel = NSTextField(labelWithString: strings[.settingsToggleHotkeyTitle])
        titleLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        hotkeySubtitleLabel.font = .systemFont(ofSize: 10)
        hotkeySubtitleLabel.textColor = .secondaryLabelColor

        let leftStack = NSStackView(views: [titleLabel, hotkeySubtitleLabel])
        leftStack.orientation = .vertical
        leftStack.alignment = .leading
        leftStack.spacing = 2
        leftStack.translatesAutoresizingMaskIntoConstraints = false

        changeHotkeyButton.bezelStyle = .rounded
        changeHotkeyButton.controlSize = .small
        changeHotkeyButton.title = strings[.settingsToggleHotkeyChange]
        changeHotkeyButton.target = self
        changeHotkeyButton.action = #selector(handleOpenHotkeyRecorder)
        changeHotkeyButton.translatesAutoresizingMaskIntoConstraints = false

        let row = NSView(frame: .zero)
        row.addSubview(leftStack)
        row.addSubview(changeHotkeyButton)
        NSLayoutConstraint.activate([
            leftStack.topAnchor.constraint(equalTo: row.topAnchor, constant: 2),
            leftStack.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            leftStack.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -2),
            changeHotkeyButton.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            changeHotkeyButton.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        section.addRow(row)
        return section
    }

    private func makeAppearanceSection() -> SettingsSection {
        let section = SettingsSection(title: strings[.settingsSectionAppearance])
        themeControl.segmentCount = 3
        themeControl.setLabel(strings[.settingsThemeSystem], forSegment: 0)
        themeControl.setLabel(strings[.settingsThemeLight], forSegment: 1)
        themeControl.setLabel(strings[.settingsThemeDark], forSegment: 2)
        themeControl.segmentStyle = .rounded
        themeControl.controlSize = .small
        themeControl.target = self
        themeControl.action = #selector(handleThemeChanged)
        section.addRow(themeControl)
        return section
    }

    private func makeHistorySection() -> SettingsSection {
        let section = SettingsSection(title: strings[.settingsSectionHistory])
        let maxSubtitle = strings.format(.settingsMaxItemsSubtitle, ["n": String(settingsViewModel.maxItems)])
        let maxRow = SettingsSection.makePopupRow(title: strings[.settingsMaxItemsTitle], subtitle: maxSubtitle, items: SettingsViewModel.allowedMaxItems.map(String.init), target: self, action: #selector(handleMaxItemsChanged))
        maxItemsPopup = maxRow.popup
        maxItemsSubtitleLabel = maxRow.subtitleLabel
        section.addRow(maxRow.row)

        let sensRow = SettingsSection.makeSwitchRow(title: strings[.settingsSensitiveFilterTitle], subtitle: strings[.settingsSensitiveFilterSubtitleOn], target: self, action: #selector(handleSensitiveChanged))
        sensitiveSwitch = sensRow.toggle
        sensitiveSubtitleLabel = sensRow.subtitleLabel
        section.addRow(sensRow.row)

        let lockRow = SettingsSection.makeSwitchRow(title: strings[.settingsClearOnScreenLockTitle], subtitle: strings[.settingsClearOnScreenLockSubtitle], target: self, action: #selector(handleLockClearChanged))
        lockClearSwitch = lockRow.toggle
        section.addRow(lockRow.row)

        let plainRow = SettingsSection.makeSwitchRow(title: strings[.settingsAlwaysPastePlainTextTitle], subtitle: strings[.settingsAlwaysPastePlainTextSubtitle], target: self, action: #selector(handlePlainTextChanged))
        plainTextSwitch = plainRow.toggle
        section.addRow(plainRow.row)
        return section
    }

    private func makeWindowSection() -> SettingsSection {
        let section = SettingsSection(title: strings[.settingsSectionWindow])
        let blurRow = SettingsSection.makeSwitchRow(title: strings[.settingsAutoHideOnBlurTitle], subtitle: strings[.settingsAutoHideOnBlurSubtitle], target: self, action: #selector(handleAutoHideChanged))
        autoHideSwitch = blurRow.toggle
        section.addRow(blurRow.row)

        let pinRow = SettingsSection.makeSwitchRow(title: strings[.settingsAlwaysOnTopTitle], subtitle: strings[.settingsAlwaysOnTopSubtitle], target: self, action: #selector(handleAlwaysOnTopChanged))
        alwaysOnTopSwitch = pinRow.toggle
        section.addRow(pinRow.row)
        return section
    }

    private func makeAdvancedSection() -> SettingsSection {
        let section = SettingsSection(title: strings[.settingsSectionAdvanced], collapsible: true, initiallyExpanded: false)
        let pollItems = SettingsViewModel.allowedPollingIntervals.map { strings.format(.settingsPollingIntervalValue, ["n": String($0)]) }
        let pollRow = SettingsSection.makePopupRow(title: strings[.settingsPollingIntervalTitle], subtitle: strings.format(.settingsPollingIntervalValue, ["n": String(settingsViewModel.pollingIntervalMs)]), items: pollItems, target: self, action: #selector(handlePollingChanged))
        pollingPopup = pollRow.popup
        pollingSubtitleLabel = pollRow.subtitleLabel
        section.addRow(pollRow.row)

        let startupRow = SettingsSection.makeSwitchRow(title: strings[.settingsClearOnStartupTitle], subtitle: strings[.settingsClearOnStartupSubtitle], target: self, action: #selector(handleClearStartupChanged))
        clearStartupSwitch = startupRow.toggle
        section.addRow(startupRow.row)
        return section
    }

    // MARK: - Bindings & Actions

    private func bind() {
        settingsViewModel.$registeredHotkey.sink { [weak self] combo in
            self?.hotkeySubtitleLabel.stringValue = HotkeyFormatter.formatReadable(combo)
        }.store(in: &cancellables)

        settingsViewModel.$themeMode.sink { [weak self] mode in
            self?.themeControl.selectedSegment = ThemeMode.allCases.firstIndex(of: mode) ?? 0
        }.store(in: &cancellables)

        settingsViewModel.$maxItems.sink { [weak self] val in
            guard let self else { return }
            if let idx = SettingsViewModel.allowedMaxItems.firstIndex(of: val) {
                self.maxItemsPopup.selectItem(at: idx)
            }
            self.maxItemsSubtitleLabel.stringValue = self.strings.format(.settingsMaxItemsSubtitle, ["n": String(val)])
        }.store(in: &cancellables)

        settingsViewModel.$sensitiveFilter.sink { [weak self] on in
            guard let self else { return }
            self.sensitiveSwitch.state = on ? .on : .off
            self.sensitiveSubtitleLabel.stringValue =
                on ? self.strings[.settingsSensitiveFilterSubtitleOn] : self.strings[.settingsSensitiveFilterSubtitleOff]
            self.sensitiveSubtitleLabel.textColor = on ? .secondaryLabelColor : .systemRed
        }.store(in: &cancellables)

        settingsViewModel.$clearOnScreenLock.sink { [weak self] on in self?.lockClearSwitch.state = on ? .on : .off }.store(in: &cancellables)
        settingsViewModel.$alwaysPastePlainText.sink { [weak self] on in self?.plainTextSwitch.state = on ? .on : .off }.store(in: &cancellables)
        settingsViewModel.$autoHideOnBlur.sink { [weak self] on in self?.autoHideSwitch.state = on ? .on : .off }.store(in: &cancellables)
        settingsViewModel.$alwaysOnTopDefault.sink { [weak self] on in self?.alwaysOnTopSwitch.state = on ? .on : .off }.store(in: &cancellables)
        settingsViewModel.$clearOnStartup.sink { [weak self] on in self?.clearStartupSwitch.state = on ? .on : .off }.store(in: &cancellables)

        settingsViewModel.$pollingIntervalMs.sink { [weak self] ms in
            guard let self else { return }
            if let idx = SettingsViewModel.allowedPollingIntervals.firstIndex(of: ms) {
                self.pollingPopup.selectItem(at: idx)
            }
            self.pollingSubtitleLabel.stringValue = self.strings.format(.settingsPollingIntervalValue, ["n": String(ms)])
        }.store(in: &cancellables)
    }

    @objc private func handleClose() { panelViewModel.closeSettings() }

    @objc private func handleThemeChanged() {
        let idx = themeControl.selectedSegment
        guard (0..<ThemeMode.allCases.count).contains(idx) else { return }
        settingsViewModel.themeMode = ThemeMode.allCases[idx]
    }

    @objc private func handleMaxItemsChanged() {
        let idx = maxItemsPopup.indexOfSelectedItem
        guard (0..<SettingsViewModel.allowedMaxItems.count).contains(idx) else { return }
        settingsViewModel.maxItems = SettingsViewModel.allowedMaxItems[idx]
    }

    @objc private func handleSensitiveChanged() { settingsViewModel.sensitiveFilter = (sensitiveSwitch.state == .on) }
    @objc private func handleLockClearChanged() { settingsViewModel.clearOnScreenLock = (lockClearSwitch.state == .on) }
    @objc private func handlePlainTextChanged() { settingsViewModel.alwaysPastePlainText = (plainTextSwitch.state == .on) }
    @objc private func handleAutoHideChanged() { settingsViewModel.autoHideOnBlur = (autoHideSwitch.state == .on) }
    @objc private func handleAlwaysOnTopChanged() { settingsViewModel.alwaysOnTopDefault = (alwaysOnTopSwitch.state == .on) }

    @objc private func handlePollingChanged() {
        let idx = pollingPopup.indexOfSelectedItem
        guard (0..<SettingsViewModel.allowedPollingIntervals.count).contains(idx) else { return }
        settingsViewModel.pollingIntervalMs = SettingsViewModel.allowedPollingIntervals[idx]
    }

    @objc private func handleClearStartupChanged() { settingsViewModel.clearOnStartup = (clearStartupSwitch.state == .on) }

    @objc private func handleOpenHotkeyRecorder() {
        guard let host = window?.contentView as? PanelContentView else { return }
        isRecordingHotkey = true
        settingsViewModel.beginRecording()
        panelViewModel.setDialogOpen(true)
        changeHotkeyButton.title = strings[.settingsToggleHotkeyRecording]
        changeHotkeyButton.isEnabled = false

        let recorder = HotkeyRecorderView(strings: strings, initialCombo: settingsViewModel.registeredHotkey)
        let finish: () -> Void = { [weak self, weak host] in
            guard let self else { return }
            host?.dismissModal(runCancel: false)
            self.stopRecordingIfNeeded()
            self.panelViewModel.setDialogOpen(false)
            self.window?.makeFirstResponder(self.changeHotkeyButton)
        }
        recorder.onCancel = finish
        recorder.onSave = { [weak self] combo in
            guard let self else { return }
            self.stopRecordingIfNeeded()
            _ = self.settingsViewModel.changeHotkey(combo)
            finish()
        }
        host.presentModal(recorder, initialFirstResponder: recorder) { [weak self] in
            guard let self else { return }
            self.stopRecordingIfNeeded()
            self.panelViewModel.setDialogOpen(false)
        }
    }

    @objc private func handleReset() {
        guard let host = window?.contentView as? PanelContentView else {
            _ = settingsViewModel.resetToDefaults()
            return
        }
        panelViewModel.setDialogOpen(true)
        let card = ModalDialogView(
            title: strings[.settingsResetTitle],
            body: strings[.settingsResetBody],
            confirmTitle: strings[.settingsResetConfirm],
            cancelTitle: strings[.commonCancel],
            onConfirm: { [weak self, weak host] in
                guard let self else { return }
                host?.dismissModal(runCancel: false)
                self.panelViewModel.setDialogOpen(false)
                _ = self.settingsViewModel.resetToDefaults()
            },
            onCancel: { [weak self, weak host] in
                guard let self else { return }
                host?.dismissModal(runCancel: false)
                self.panelViewModel.setDialogOpen(false)
            }
        )
        host.presentModal(card, initialFirstResponder: card) { [weak self] in
            self?.panelViewModel.setDialogOpen(false)
        }
    }
}

@MainActor
private final class FlippedClipView: NSClipView {
    override var isFlipped: Bool { true }
}
