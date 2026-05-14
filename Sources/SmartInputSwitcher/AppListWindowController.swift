import Cocoa

// MARK: - App Row View

private class AppRowView: NSView {
    private let iconView      = NSImageView()
    private let nameLabel     = NSTextField(labelWithString: "")
    private let bundleLabel   = NSTextField(labelWithString: "")
    private let strategyPopup = NSPopUpButton()
    private let deleteButton  = NSButton()
    private let separatorLayer = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupViews()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        wantsLayer = true

        // App icon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        // App name
        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)

        // Bundle ID
        bundleLabel.font = .systemFont(ofSize: 10.5)
        bundleLabel.textColor = .tertiaryLabelColor
        bundleLabel.lineBreakMode = .byTruncatingMiddle
        bundleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bundleLabel)

        // Strategy picker
        strategyPopup.bezelStyle = .roundRect
        strategyPopup.controlSize = .small
        strategyPopup.font = .systemFont(ofSize: 11.5)
        strategyPopup.translatesAutoresizingMaskIntoConstraints = false
        addSubview(strategyPopup)

        // Delete button — xmark circle
        deleteButton.bezelStyle = .regularSquare
        deleteButton.isBordered = false
        let delCfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .light)
        deleteButton.image = NSImage(systemSymbolName: "xmark.circle.fill",
                                     accessibilityDescription: "移除规则")
            .flatMap { $0.withSymbolConfiguration(delCfg) }
        deleteButton.contentTintColor = .tertiaryLabelColor
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(deleteButton)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            nameLabel.bottomAnchor.constraint(equalTo: centerYAnchor, constant: -1),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: strategyPopup.leadingAnchor, constant: -8),

            bundleLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            bundleLabel.topAnchor.constraint(equalTo: centerYAnchor, constant: 1),
            bundleLabel.trailingAnchor.constraint(lessThanOrEqualTo: strategyPopup.leadingAnchor, constant: -8),

            strategyPopup.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -6),
            strategyPopup.centerYAnchor.constraint(equalTo: centerYAnchor),
            strategyPopup.widthAnchor.constraint(equalToConstant: 80),

            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            deleteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 20),
            deleteButton.heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    func configure(
        app: ConfiguredApp,
        icon: NSImage,
        strategies: [(AppInputStrategy, String)],
        row: Int,
        strategyTarget: AnyObject,
        strategyAction: Selector,
        deleteTarget: AnyObject,
        deleteAction: Selector
    ) {
        iconView.image = icon
        nameLabel.stringValue = app.appName
        bundleLabel.stringValue = app.bundleId

        strategyPopup.removeAllItems()
        for (strategy, title) in strategies {
            strategyPopup.addItem(withTitle: title)
            strategyPopup.lastItem?.tag = strategy.rawValue
        }
        strategyPopup.selectItem(withTag: app.strategy.rawValue)
        strategyPopup.tag = row
        strategyPopup.target = strategyTarget
        strategyPopup.action = strategyAction

        deleteButton.tag = row
        deleteButton.target = deleteTarget
        deleteButton.action = deleteAction
    }

    // Separator line that respects dark/light mode
    override func updateLayer() {
        super.updateLayer()
        if separatorLayer.superlayer == nil {
            layer?.addSublayer(separatorLayer)
        }
        separatorLayer.backgroundColor = NSColor.separatorColor
            .withAlphaComponent(0.45).cgColor
        separatorLayer.frame = CGRect(x: 58, y: 0,
                                      width: bounds.width - 58, height: 0.5)
    }
}

// MARK: - Controller

class AppListWindowController: NSWindowController, NSWindowDelegate {
    static let shared = AppListWindowController()

    private var tableView: NSTableView!
    private var emptyStateView: NSView!
    private var globalStrategyControl: NSSegmentedControl!
    private var activePicker: AppPickerSheetController?   // retain until sheet dismissed
    private var apps: [ConfiguredApp] = []
    private var iconCache: [String: NSImage] = [:]

    // Three explicit rules — "remove rule" (→ global default) is the delete button
    private let strategyOptions: [(AppInputStrategy, String)] = [
        (.forceEnglish, "英文"),
        (.forceChinese, "中文"),
        (.keepCurrent,  "保持"),
    ]

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Tail Input"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 420, height: 360)
        window.backgroundColor = .clear
        window.isOpaque = false

        super.init(window: window)
        window.delegate = self
        window.center()
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - External API

    func showWindow() {
        reload()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - UI Construction

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        // Glass background — LiquidGlass sidebar material
        let glass = NSVisualEffectView(frame: contentView.bounds)
        glass.autoresizingMask = [.width, .height]
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.material = .sidebar
        contentView.addSubview(glass)

        // Header
        let header = buildHeader()
        header.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(header)

        // Separator below header
        let sep1 = makeSeparator()
        contentView.addSubview(sep1)

        // Global default bar
        let globalBar = buildGlobalBar()
        globalBar.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(globalBar)

        // Separator below global bar
        let sep1b = makeSeparator()
        contentView.addSubview(sep1b)

        // Scroll view + table
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        contentView.addSubview(scrollView)

        tableView = NSTableView()
        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = 56
        tableView.headerView = nil
        tableView.intercellSpacing = .zero
        tableView.selectionHighlightStyle = .none
        tableView.backgroundColor = .clear

        let col = NSTableColumn(identifier: .init("row"))
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)
        scrollView.documentView = tableView

        // Empty state
        emptyStateView = buildEmptyState()
        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(emptyStateView)

        // Separator above footer
        let sep2 = makeSeparator()
        contentView.addSubview(sep2)

        // Footer — version / author / link
        let footer = buildFooter()
        footer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(footer)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 28),
            header.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 52),

            sep1.topAnchor.constraint(equalTo: header.bottomAnchor),
            sep1.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            sep1.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            globalBar.topAnchor.constraint(equalTo: sep1.bottomAnchor),
            globalBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            globalBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            globalBar.heightAnchor.constraint(equalToConstant: 44),

            sep1b.topAnchor.constraint(equalTo: globalBar.bottomAnchor),
            sep1b.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            sep1b.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: sep1b.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: sep2.topAnchor),

            emptyStateView.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyStateView.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),

            sep2.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            sep2.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            sep2.bottomAnchor.constraint(equalTo: footer.topAnchor),

            footer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    private func buildHeader() -> NSView {
        let view = NSView()

        let titleLabel = NSTextField(labelWithString: "应用输入法规则")
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        let subtitleLabel = NSTextField(labelWithString: "切换到指定应用时自动切换输入法")
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(subtitleLabel)

        // Add current-app button — plus.circle.fill with accent color
        let addBtn = NSButton()
        addBtn.bezelStyle = .regularSquare
        addBtn.isBordered = false
        let addCfg = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        addBtn.image = NSImage(systemSymbolName: "plus.circle.fill",
                               accessibilityDescription: "添加当前应用")
            .flatMap { $0.withSymbolConfiguration(addCfg) }
        addBtn.contentTintColor = .controlAccentColor
        addBtn.toolTip = "为当前前台应用添加输入法规则"
        addBtn.target = self
        addBtn.action = #selector(addCurrentApp)
        addBtn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(addBtn)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),

            subtitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),

            addBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            addBtn.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            addBtn.widthAnchor.constraint(equalToConstant: 28),
            addBtn.heightAnchor.constraint(equalToConstant: 28),
        ])
        return view
    }

    private func buildEmptyState() -> NSView {
        let view = NSView()

        let symCfg = NSImage.SymbolConfiguration(pointSize: 36, weight: .thin)
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "tray", accessibilityDescription: nil)
            .flatMap { $0.withSymbolConfiguration(symCfg) }
        icon.contentTintColor = .quaternaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(icon)

        let label = NSTextField(labelWithString: "暂无应用规则")
        label.font = .systemFont(ofSize: 13)
        label.textColor = .tertiaryLabelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        let hint = NSTextField(labelWithString: "点击右上角 + 为当前前台应用添加规则")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .quaternaryLabelColor
        hint.alignment = .center
        hint.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hint)

        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            icon.topAnchor.constraint(equalTo: view.topAnchor),
            icon.widthAnchor.constraint(equalToConstant: 44),
            icon.heightAnchor.constraint(equalToConstant: 44),

            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 12),

            hint.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hint.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 4),

            view.bottomAnchor.constraint(equalTo: hint.bottomAnchor),
            view.widthAnchor.constraint(equalToConstant: 300),
        ])
        return view
    }

    private func buildFooter() -> NSView {
        let view = NSView()

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"

        let verLabel = NSTextField(labelWithString: "Tail Input \(version)")
        verLabel.font = .systemFont(ofSize: 11)
        verLabel.textColor = .tertiaryLabelColor
        verLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(verLabel)

        let dotLabel = NSTextField(labelWithString: "·")
        dotLabel.font = .systemFont(ofSize: 11)
        dotLabel.textColor = .quaternaryLabelColor
        dotLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dotLabel)

        let authorLabel = NSTextField(labelWithString: "framed")
        authorLabel.font = .systemFont(ofSize: 11)
        authorLabel.textColor = .tertiaryLabelColor
        authorLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(authorLabel)

        // Clickable GitHub link
        let githubBtn = NSButton(title: "GitHub ↗", target: self, action: #selector(openGitHub))
        githubBtn.bezelStyle = .inline
        githubBtn.isBordered = false
        githubBtn.font = .systemFont(ofSize: 11)
        githubBtn.contentTintColor = .linkColor
        githubBtn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(githubBtn)

        NSLayoutConstraint.activate([
            verLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            verLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            dotLabel.leadingAnchor.constraint(equalTo: verLabel.trailingAnchor, constant: 5),
            dotLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            authorLabel.leadingAnchor.constraint(equalTo: dotLabel.trailingAnchor, constant: 5),
            authorLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            githubBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            githubBtn.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        return view
    }

    private func buildGlobalBar() -> NSView {
        let view = NSView()

        let label = NSTextField(labelWithString: "其他应用默认")
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        globalStrategyControl = NSSegmentedControl(
            labels: ["切换为英文", "切换为中文", "保持不变"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(globalStrategyChanged(_:))
        )
        globalStrategyControl.controlSize = .small
        globalStrategyControl.font = .systemFont(ofSize: 11.5)
        globalStrategyControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(globalStrategyControl)

        // Reflect current saved value
        switch InputMethodManager.shared.globalDefaultStrategy {
        case .forceChinese: globalStrategyControl.selectedSegment = 1
        case .keepCurrent:  globalStrategyControl.selectedSegment = 2
        default:            globalStrategyControl.selectedSegment = 0
        }

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            globalStrategyControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            globalStrategyControl.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        return view
    }

    @objc private func globalStrategyChanged(_ sender: NSSegmentedControl) {
        let strategy: AppInputStrategy
        switch sender.selectedSegment {
        case 1:  strategy = .forceChinese
        case 2:  strategy = .keepCurrent
        default: strategy = .forceEnglish
        }
        InputMethodManager.shared.globalDefaultStrategy = strategy
    }

    private func makeSeparator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        return box
    }

    // MARK: - Data

    private func reload() {
        apps = ConfiguredAppStore.shared.all()
        tableView?.reloadData()
        emptyStateView?.isHidden = !apps.isEmpty

        // Keep global bar in sync with stored value
        switch InputMethodManager.shared.globalDefaultStrategy {
        case .forceChinese: globalStrategyControl?.selectedSegment = 1
        case .keepCurrent:  globalStrategyControl?.selectedSegment = 2
        default:            globalStrategyControl?.selectedSegment = 0
        }
    }

    // MARK: - Actions

    @objc private func addCurrentApp() {
        guard let window = window else { return }

        let picker = AppPickerSheetController(
            preselectedBundleId: InputMethodManager.shared.currentAppBundleIdentifier
        )
        activePicker = picker   // must retain — sheet doesn't hold a strong ref to the controller

        picker.completion = { [weak self] bundleId, appName, strategy in
            ConfiguredAppStore.shared.setStrategy(strategy, for: bundleId, appName: appName)
            self?.reload()
            if let idx = self?.apps.firstIndex(where: { $0.bundleId == bundleId }) {
                self?.tableView.scrollRowToVisible(idx)
            }
        }

        window.beginSheet(picker.window!) { [weak self] _ in
            self?.activePicker = nil    // release after sheet ends (OK or cancel)
        }
    }

    @objc private func strategyChanged(_ sender: NSPopUpButton) {
        let row = sender.tag
        guard row >= 0, row < apps.count else { return }
        let app = apps[row]
        guard let strategy = AppInputStrategy(rawValue: sender.selectedTag()) else { return }
        ConfiguredAppStore.shared.setStrategy(strategy, for: app.bundleId, appName: app.appName)
        reload()
    }

    @objc private func deleteApp(_ sender: NSButton) {
        let row = sender.tag
        guard row >= 0, row < apps.count else { return }
        ConfiguredAppStore.shared.remove(bundleId: apps[row].bundleId)
        reload()
    }

    @objc private func openGitHub() {
        if let url = URL(string: "https://github.com/framecy/Tail-Input") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Helpers

    private func appIcon(for bundleId: String) -> NSImage {
        if let cached = iconCache[bundleId] { return cached }
        let icon: NSImage
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            let cfg = NSImage.SymbolConfiguration(pointSize: 22, weight: .light)
            icon = NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil)
                .flatMap { $0.withSymbolConfiguration(cfg) } ?? NSImage()
        }
        iconCache[bundleId] = icon
        return icon
    }
}

// MARK: - NSTableViewDataSource / Delegate

extension AppListWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { apps.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let app = apps[row]
        let id = NSUserInterfaceItemIdentifier("AppRow")
        let rowView: AppRowView
        if let reused = tableView.makeView(withIdentifier: id, owner: nil) as? AppRowView {
            rowView = reused
        } else {
            rowView = AppRowView(frame: .zero)
            rowView.identifier = id
        }
        rowView.configure(
            app: app,
            icon: appIcon(for: app.bundleId),
            strategies: strategyOptions,
            row: row,
            strategyTarget: self, strategyAction: #selector(strategyChanged(_:)),
            deleteTarget: self, deleteAction: #selector(deleteApp(_:))
        )
        return rowView
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { 56 }
}
