import AppKit

@MainActor
public final class SettingsSection: NSView {
    public let headerLabel = NSTextField(labelWithString: "")
    public let contentStack = NSStackView()
    public private(set) var isCollapsible: Bool
    public private(set) var isExpanded: Bool

    private var disclosureButton: NSButton?

    public init(title: String, collapsible: Bool = false, initiallyExpanded: Bool = true) {
        self.isCollapsible = collapsible
        self.isExpanded = initiallyExpanded
        super.init(frame: .zero)

        // B-6.6.2 / E14: Section headers are uppercased with Turkish locale.
        let upper = title.uppercased(with: Locale(identifier: "tr"))
        headerLabel.stringValue = upper
        headerLabel.font = .systemFont(ofSize: 10.5, weight: .semibold)
        headerLabel.textColor = .secondaryLabelColor
        headerLabel.translatesAutoresizingMaskIntoConstraints = false

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 8
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.isHidden = !initiallyExpanded

        let headerView: NSView
        if collapsible {
            let btn = NSButton(frame: .zero)
            btn.bezelStyle = .disclosure
            btn.setButtonType(.onOff)
            btn.state = initiallyExpanded ? .on : .off
            btn.title = upper
            btn.font = .systemFont(ofSize: 10.5, weight: .semibold)
            btn.contentTintColor = .secondaryLabelColor
            btn.target = self
            btn.action = #selector(toggleDisclosure)
            btn.translatesAutoresizingMaskIntoConstraints = false
            disclosureButton = btn
            headerView = btn
        } else {
            headerView = headerLabel
        }

        let outer = NSStackView(views: [headerView, contentStack])
        outer.orientation = .vertical
        outer.alignment = .leading
        outer.spacing = 6
        outer.translatesAutoresizingMaskIntoConstraints = false

        addSubview(outer)

        NSLayoutConstraint.activate([
            outer.topAnchor.constraint(equalTo: topAnchor),
            outer.leadingAnchor.constraint(equalTo: leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: trailingAnchor),
            outer.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: outer.widthAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func addRow(_ row: NSView) {
        row.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    @objc private func toggleDisclosure() {
        isExpanded.toggle()
        disclosureButton?.state = isExpanded ? .on : .off
        contentStack.isHidden = !isExpanded
    }

    // MARK: - Row Builders

    public static func makeSwitchRow(
        title: String,
        subtitle: String,
        target: AnyObject,
        action: Selector
    ) -> (row: NSView, toggle: NSSwitch, subtitleLabel: NSTextField) {
        let titleLabel = NSTextField(wrappingLabelWithString: title)
        titleLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        titleLabel.textColor = .labelColor

        let subtitleLabel = NSTextField(wrappingLabelWithString: subtitle)
        subtitleLabel.font = .systemFont(ofSize: 10)
        subtitleLabel.textColor = .secondaryLabelColor

        let textStack = NSStackView(views: [titleLabel, subtitleLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let toggle = NSSwitch(frame: .zero)
        toggle.controlSize = .small
        toggle.target = target
        toggle.action = action
        toggle.setAccessibilityLabel(title)
        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.setContentHuggingPriority(.required, for: .horizontal)

        let row = NSView(frame: .zero)
        row.addSubview(textStack)
        row.addSubview(toggle)

        NSLayoutConstraint.activate([
            textStack.topAnchor.constraint(equalTo: row.topAnchor, constant: 2),
            textStack.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            textStack.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -2),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -8),

            toggle.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            toggle.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])

        return (row, toggle, subtitleLabel)
    }

    public static func makePopupRow(
        title: String,
        subtitle: String,
        items: [String],
        target: AnyObject,
        action: Selector
    ) -> (row: NSView, popup: NSPopUpButton, subtitleLabel: NSTextField) {
        let titleLabel = NSTextField(wrappingLabelWithString: title)
        titleLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        titleLabel.textColor = .labelColor

        let subtitleLabel = NSTextField(wrappingLabelWithString: subtitle)
        subtitleLabel.font = .systemFont(ofSize: 10)
        subtitleLabel.textColor = .secondaryLabelColor

        let textStack = NSStackView(views: [titleLabel, subtitleLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.controlSize = .small
        popup.font = .systemFont(ofSize: 11)
        popup.addItems(withTitles: items)
        popup.target = target
        popup.action = action
        popup.setAccessibilityLabel(title)
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.setContentHuggingPriority(.required, for: .horizontal)

        let row = NSView(frame: .zero)
        row.addSubview(textStack)
        row.addSubview(popup)

        NSLayoutConstraint.activate([
            textStack.topAnchor.constraint(equalTo: row.topAnchor, constant: 2),
            textStack.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            textStack.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -2),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: popup.leadingAnchor, constant: -8),

            popup.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            popup.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])

        return (row, popup, subtitleLabel)
    }
}
