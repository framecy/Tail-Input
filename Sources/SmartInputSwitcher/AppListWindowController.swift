import Cocoa

class AppListWindowController: NSWindowController, NSWindowDelegate {
    static let shared = AppListWindowController()

    private var tableView: NSTableView!
    private var emptyLabel: NSTextField!
    private var apps: [ConfiguredApp] = []
    private var iconCache: [String: NSImage] = [:]

    // MARK: - 策略选项标题（与 AppInputStrategy 保持一致）
    private let strategyTitles: [(AppInputStrategy, String)] = [
        (.globalDefault,  "默认 (切回英文)"),
        (.forceEnglish,   "强制英文"),
        (.forceChinese,   "强制中文"),
        (.keepCurrent,    "保持原状态"),
    ]

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "应用输入法策略"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.minSize = NSSize(width: 400, height: 300)

        super.init(window: window)
        window.delegate = self
        window.center()
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - 外部调用

    func showWindow() {
        reload()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - UI

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        // 毛玻璃背景
        let visualEffect = NSVisualEffectView(frame: contentView.bounds)
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.material = .sidebar
        contentView.addSubview(visualEffect)

        // ── 底部"添加当前应用"按钮 ──
        let addButton = NSButton(title: "+ 添加当前应用", target: self, action: #selector(addCurrentApp))
        addButton.bezelStyle = .rounded
        addButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(addButton)

        // ── ScrollView + TableView ──
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
        tableView.rowHeight = 44
        tableView.headerView = nil
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.selectionHighlightStyle = .none
        tableView.backgroundColor = .clear
        tableView.usesAutomaticRowHeights = false

        // 列：应用图标 + 名称
        let appCol = NSTableColumn(identifier: .init("app"))
        appCol.minWidth = 120
        appCol.resizingMask = .autoresizingMask
        tableView.addTableColumn(appCol)

        // 列：策略选择
        let stratCol = NSTableColumn(identifier: .init("strategy"))
        stratCol.width = 150
        stratCol.minWidth = 120
        stratCol.resizingMask = .autoresizingMask
        tableView.addTableColumn(stratCol)

        // 列：删除按钮（固定宽度）
        let delCol = NSTableColumn(identifier: .init("delete"))
        delCol.width = 56
        delCol.minWidth = 56
        delCol.maxWidth = 64
        delCol.resizingMask = []
        tableView.addTableColumn(delCol)

        scrollView.documentView = tableView

        // ── 空状态提示 ──
        emptyLabel = NSTextField(labelWithString: "尚未配置任何应用策略")
        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(emptyLabel)

        // ── 布局约束 ──
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 32),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: addButton.topAnchor, constant: -8),

            addButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            addButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            addButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            addButton.heightAnchor.constraint(equalToConstant: 32),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
        ])
    }

    // MARK: - 数据

    private func reload() {
        apps = ConfiguredAppStore.shared.all()
        tableView?.reloadData()
        emptyLabel?.isHidden = !apps.isEmpty
    }

    // MARK: - Actions

    @objc private func addCurrentApp() {
        guard let bundleId = InputMethodManager.shared.currentAppBundleIdentifier else { return }
        let appName = InputMethodManager.shared.currentAppName ?? bundleId
        ConfiguredAppStore.shared.setStrategy(.forceEnglish, for: bundleId, appName: appName)
        reload()
    }

    @objc private func deleteApp(_ sender: NSButton) {
        let row = sender.tag
        guard row >= 0, row < apps.count else { return }
        ConfiguredAppStore.shared.remove(bundleId: apps[row].bundleId)
        reload()
    }

    @objc private func strategyChanged(_ sender: NSPopUpButton) {
        let row = sender.tag
        guard row >= 0, row < apps.count else { return }
        let app = apps[row]
        let strategy = AppInputStrategy(rawValue: sender.selectedTag()) ?? .globalDefault
        ConfiguredAppStore.shared.setStrategy(strategy, for: app.bundleId, appName: app.appName)
        reload()
    }

    // MARK: - 辅助

    private func appIcon(for bundleId: String) -> NSImage {
        if let cached = iconCache[bundleId] {
            return cached
        }

        let icon: NSImage
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            icon = NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
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
        switch tableColumn?.identifier.rawValue {

        // ── 应用列 ──
        case "app":
            let id = NSUserInterfaceItemIdentifier("AppCell")
            let cell: NSTableCellView
            if let reused = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView {
                cell = reused
            } else {
                cell = makeAppCell(identifier: id)
            }
            cell.textField?.stringValue = app.appName
            cell.imageView?.image = appIcon(for: app.bundleId)
            return cell

        // ── 策略列 ──
        case "strategy":
            let id = NSUserInterfaceItemIdentifier("StrategyCell")
            let cell = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView ?? NSTableCellView()
            cell.identifier = id
            cell.subviews.forEach { $0.removeFromSuperview() }

            let popup = NSPopUpButton()
            popup.translatesAutoresizingMaskIntoConstraints = false
            for (strategy, title) in strategyTitles {
                popup.addItem(withTitle: title)
                popup.lastItem?.tag = strategy.rawValue
            }
            popup.selectItem(withTag: app.strategy.rawValue)
            popup.tag = row
            popup.target = self
            popup.action = #selector(strategyChanged(_:))
            popup.controlSize = .small
            popup.font = .systemFont(ofSize: 12)

            cell.addSubview(popup)
            NSLayoutConstraint.activate([
                popup.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                popup.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                popup.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell

        // ── 删除列 ──
        case "delete":
            let id = NSUserInterfaceItemIdentifier("DeleteCell")
            let cell = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView ?? NSTableCellView()
            cell.identifier = id
            cell.subviews.forEach { $0.removeFromSuperview() }

            let btn = NSButton(title: "删除", target: self, action: #selector(deleteApp(_:)))
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.bezelStyle = .inline
            btn.contentTintColor = .systemRed
            btn.controlSize = .small
            btn.font = .systemFont(ofSize: 12)
            btn.tag = row

            cell.addSubview(btn)
            NSLayoutConstraint.activate([
                btn.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
                btn.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell

        default:
            return nil
        }
    }

    // MARK: - 单元格工厂

    private func makeAppCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier

        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        cell.imageView = imageView
        cell.addSubview(imageView)

        let textField = NSTextField(labelWithString: "")
        textField.font = .systemFont(ofSize: 13)
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.lineBreakMode = .byTruncatingTail
        cell.textField = textField
        cell.addSubview(textField)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
            imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 28),
            imageView.heightAnchor.constraint(equalToConstant: 28),

            textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
            textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}
