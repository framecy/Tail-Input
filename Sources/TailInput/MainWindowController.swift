import Cocoa
import ServiceManagement
import ApplicationServices

// MARK: - MainWindowController

final class MainWindowController: NSWindowController {
    static let shared = MainWindowController()

    private let sidebar = SidebarView()
    private let rulesPane = RulesPane()
    private let browserPane = BrowserPane()
    private var rightContainer: NSView!

    private init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.center()
        win.setFrameAutosaveName("MainWindow")
        win.isReleasedWhenClosed = false
        win.minSize = NSSize(width: 620, height: 400)

        super.init(window: win)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    func showWindow() {
        rulesPane.reload()
        sidebar.refresh()
        showRulesPane(animated: false)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 供外部（如授权完成回调）刷新侧栏开关状态
    func refreshSidebar() { sidebar.refresh() }

    // MARK: - Layout

    private func buildUI() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true

        // Full-window sidebar effect
        let fx = NSVisualEffectView()
        fx.material = .sidebar
        fx.blendingMode = .behindWindow
        fx.state = .active
        fx.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(fx)
        NSLayoutConstraint.activate([
            fx.topAnchor.constraint(equalTo: content.topAnchor),
            fx.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            fx.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            fx.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ])

        // Sidebar (left, fixed 220pt)
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(sidebar)

        // Vertical divider
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(divider)

        // Right container (clips subviews for view swap)
        rightContainer = NSView()
        rightContainer.wantsLayer = true
        rightContainer.layer?.masksToBounds = true
        rightContainer.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(rightContainer)

        NSLayoutConstraint.activate([
            sidebar.topAnchor.constraint(equalTo: content.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 220),

            divider.topAnchor.constraint(equalTo: content.topAnchor),
            divider.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),

            rightContainer.topAnchor.constraint(equalTo: content.topAnchor),
            rightContainer.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            rightContainer.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            rightContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ])

        // Wire callbacks
        rulesPane.onAddTapped = { [weak self] in self?.showBrowserPane() }
        browserPane.onBack = { [weak self] in self?.showRulesPane(animated: true) }
        browserPane.onAppAdded = { [weak self] in
            self?.rulesPane.reload()
            self?.showRulesPane(animated: true)
        }
    }

    // MARK: - Pane swap

    private func showRulesPane(animated: Bool) {
        swapRight(to: rulesPane, animated: animated)
    }

    private func showBrowserPane() {
        browserPane.reset()
        swapRight(to: browserPane, animated: true)
    }

    private func swapRight(to new: NSView, animated: Bool) {
        let old = rightContainer.subviews.first
        guard old !== new else { return }

        new.translatesAutoresizingMaskIntoConstraints = false
        new.alphaValue = animated ? 0 : 1
        rightContainer.addSubview(new)
        NSLayoutConstraint.activate([
            new.topAnchor.constraint(equalTo: rightContainer.topAnchor),
            new.bottomAnchor.constraint(equalTo: rightContainer.bottomAnchor),
            new.leadingAnchor.constraint(equalTo: rightContainer.leadingAnchor),
            new.trailingAnchor.constraint(equalTo: rightContainer.trailingAnchor),
        ])

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                new.animator().alphaValue = 1
                old?.animator().alphaValue = 0
            } completionHandler: {
                old?.removeFromSuperview()
            }
        } else {
            old?.removeFromSuperview()
        }
    }
}

// MARK: - SidebarView

private final class SidebarView: NSView {
    private let autoSwitch   = LabeledToggle(label: "自动切换输入法")
    private let loginItem    = LabeledToggle(label: "开机自启动")
    private let capsLockSeg  = NSSegmentedControl(labels: ["关闭", "兼容", "纯切换"], trackingMode: .selectOne, target: nil, action: nil)
    private let globalSeg    = NSSegmentedControl(labels: ["英文", "中文", "保持", "恢复"], trackingMode: .selectOne, target: nil, action: nil)
    private let hudPicker    = HUDPositionPicker()
    private let hudScreenRow = NSView()
    private let hudScreenPopup = NSPopUpButton()
    private let hudSizeSeg   = NSSegmentedControl(labels: ["小", "中", "大"], trackingMode: .selectOne, target: nil, action: nil)
    private let hudIconToggle = LabeledToggle(label: "显示图标")
    private let hudTextSeg   = NSSegmentedControl(labels: ["简短", "完整"], trackingMode: .selectOne, target: nil, action: nil)

    override init(frame: NSRect) {
        super.init(frame: frame)
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        let mgr = InputMethodManager.shared
        autoSwitch.isOn = (NSApp.delegate as? AppDelegate)?.isEnabled ?? true
        loginItem.isOn  = SMAppService.mainApp.status == .enabled

        switch mgr.capsLockMode {
        case .off:    capsLockSeg.selectedSegment = 0
        case .compat: capsLockSeg.selectedSegment = 1
        case .pure:   capsLockSeg.selectedSegment = 2
        }

        switch mgr.globalDefaultStrategy {
        case .forceChinese: globalSeg.selectedSegment = 1
        case .keepCurrent:  globalSeg.selectedSegment = 2
        case .restorePrevious: globalSeg.selectedSegment = 3
        default:            globalSeg.selectedSegment = 0
        }

        // HUD 位置 / 大小 / 内容
        if let hud = (NSApp.delegate as? AppDelegate)?.hudController {
            hudPicker.setSelected(hud.hudPosition)
            refreshScreenPopup(hud: hud)
            hudSizeSeg.selectedSegment = hud.hudSizePreset
            hudIconToggle.isOn = hud.hudShowIcon
            hudTextSeg.selectedSegment = hud.hudTextStyle
        }
    }

    private func build() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 52),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])

        // Toggles
        stack.addArrangedSubview(autoSwitch)
        stack.addArrangedSubview(Spacer(4))
        stack.addArrangedSubview(loginItem)

        // CapsLock section（三态：关闭 / 兼容 / 纯切换）
        stack.addArrangedSubview(Spacer(20))
        stack.addArrangedSubview(sectionLabel("CapsLock 切换"))
        stack.addArrangedSubview(Spacer(6))
        capsLockSeg.translatesAutoresizingMaskIntoConstraints = false
        capsLockSeg.widthAnchor.constraint(equalToConstant: 188).isActive = true
        stack.addArrangedSubview(capsLockSeg)

        // Global default section
        stack.addArrangedSubview(Spacer(20))
        stack.addArrangedSubview(sectionLabel("其他应用默认"))
        stack.addArrangedSubview(Spacer(6))
        globalSeg.translatesAutoresizingMaskIntoConstraints = false
        globalSeg.widthAnchor.constraint(equalToConstant: 188).isActive = true
        stack.addArrangedSubview(globalSeg)

        // HUD 位置 section
        stack.addArrangedSubview(Spacer(20))
        stack.addArrangedSubview(sectionLabel("HUD 位置"))
        stack.addArrangedSubview(Spacer(6))
        stack.addArrangedSubview(hudPicker)
        stack.addArrangedSubview(Spacer(4))
        buildHUDScreenRow(into: stack)

        // HUD 大小
        stack.addArrangedSubview(Spacer(16))
        stack.addArrangedSubview(sectionLabel("HUD 大小"))
        stack.addArrangedSubview(Spacer(6))
        hudSizeSeg.translatesAutoresizingMaskIntoConstraints = false
        hudSizeSeg.widthAnchor.constraint(equalToConstant: 188).isActive = true
        stack.addArrangedSubview(hudSizeSeg)

        // HUD 提示内容
        stack.addArrangedSubview(Spacer(16))
        stack.addArrangedSubview(sectionLabel("HUD 内容"))
        stack.addArrangedSubview(Spacer(6))
        stack.addArrangedSubview(hudIconToggle)
        stack.addArrangedSubview(Spacer(4))
        hudTextSeg.translatesAutoresizingMaskIntoConstraints = false
        hudTextSeg.widthAnchor.constraint(equalToConstant: 188).isActive = true
        stack.addArrangedSubview(hudTextSeg)

        // Spacer pushes footer down
        let flex = NSView()
        flex.setContentHuggingPriority(.fittingSizeCompression, for: .vertical)
        stack.addArrangedSubview(flex)

        // Footer
        stack.addArrangedSubview(footerView())

        // Wire actions
        autoSwitch.onChange = { isOn in
            guard let delegate = NSApp.delegate as? AppDelegate else { return }
            delegate.isEnabled = isOn
            AppObserver.shared.isEnabled = isOn
        }
        loginItem.onChange = { isOn in
            let svc = SMAppService.mainApp
            try? isOn ? svc.register() : svc.unregister()
        }
        capsLockSeg.target = self
        capsLockSeg.action = #selector(capsLockSegChanged)
        globalSeg.target = self
        globalSeg.action = #selector(globalSegChanged)

        hudPicker.onChange = { [weak self] position in
            (NSApp.delegate as? AppDelegate)?.hudController?.hudPosition = position
            if let hud = (NSApp.delegate as? AppDelegate)?.hudController {
                self?.refreshScreenPopup(hud: hud)
            }
        }

        hudSizeSeg.target = self
        hudSizeSeg.action = #selector(hudSizeSegChanged)

        hudIconToggle.onChange = { isOn in
            (NSApp.delegate as? AppDelegate)?.hudController?.hudShowIcon = isOn
        }

        hudTextSeg.target = self
        hudTextSeg.action = #selector(hudTextSegChanged)
    }

    @objc private func globalSegChanged() {
        let strategies: [AppInputStrategy] = [.forceEnglish, .forceChinese, .keepCurrent, .restorePrevious]
        let sel = globalSeg.selectedSegment
        if sel >= 0 && sel < strategies.count {
            InputMethodManager.shared.globalDefaultStrategy = strategies[sel]
        }
    }

    @objc private func capsLockSegChanged() {
        let modes: [CapsLockMode] = [.off, .compat, .pure]
        let sel = capsLockSeg.selectedSegment
        guard sel >= 0 && sel < modes.count else { return }
        handleCapsLockModeChange(modes[sel])
    }

    private func handleCapsLockModeChange(_ mode: CapsLockMode) {
        let mgr = InputMethodManager.shared
        if mode == .off {
            mgr.capsLockMode = .off
            return
        }
        // .pure 模式与 macOS 原生 "用 CapsLock 切换 ABC" 互斥，首次启用前确认
        if mode == .pure,
           let delegate = NSApp.delegate as? AppDelegate,
           !delegate.confirmPureModeMacOSConflict() {
            refresh()   // 回滚到当前实际模式
            return
        }
        // 切到 .compat / .pure — 实际尝试 tap 创建，失败说明缺权限
        if !mgr.tryEnableCapsLockMode(mode) {
            // 视觉先回弹到 .off，didBecomeActive 时若成功会刷新
            capsLockSeg.selectedSegment = 0
            (NSApp.delegate as? AppDelegate)?.requestAccessibilityForCapsLock(mode: mode)
        }
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let tf = NSTextField(labelWithString: text)
        tf.font = .systemFont(ofSize: 11, weight: .semibold)
        tf.textColor = .secondaryLabelColor
        return tf
    }

    private func footerView() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.translatesAutoresizingMaskIntoConstraints = false

        // App icon
        let iconView = NSImageView()
        if let icon = NSImage(named: "AppIcon") ?? NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath) as NSImage? {
            iconView.image = icon
        }
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 8
        iconView.layer?.cornerCurve = .continuous
        iconView.layer?.masksToBounds = true
        iconView.translatesAutoresizingMaskIntoConstraints = false

        // App name + version
        let nameLabel = NSTextField(labelWithString: "Tail Input")
        nameLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        nameLabel.textColor = .labelColor
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        let versionLabel = NSTextField(labelWithString: "v\(Bundle.main.shortVersion) · MIT License")
        versionLabel.font = .systemFont(ofSize: 10)
        versionLabel.textColor = .tertiaryLabelColor
        versionLabel.translatesAutoresizingMaskIntoConstraints = false

        // GitHub button — subtle link style
        let githubBtn = NSButton(title: "GitHub ↗", target: self, action: #selector(openGitHub))
        githubBtn.bezelStyle = .inline
        githubBtn.isBordered = false
        githubBtn.font = .systemFont(ofSize: 10)
        githubBtn.contentTintColor = .tertiaryLabelColor
        githubBtn.translatesAutoresizingMaskIntoConstraints = false

        let textCol = NSStackView(views: [nameLabel, versionLabel, githubBtn])
        textCol.orientation = .vertical
        textCol.alignment = .leading
        textCol.spacing = 1
        textCol.translatesAutoresizingMaskIntoConstraints = false

        v.addSubview(iconView)
        v.addSubview(textCol)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 36),
            iconView.heightAnchor.constraint(equalToConstant: 36),

            textCol.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            textCol.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            textCol.trailingAnchor.constraint(lessThanOrEqualTo: v.trailingAnchor),

            v.heightAnchor.constraint(equalToConstant: 44),
        ])
        return v
    }

    // MARK: - HUD 屏幕选择行

    private func buildHUDScreenRow(into stack: NSStackView) {
        hudScreenRow.translatesAutoresizingMaskIntoConstraints = false
        hudScreenRow.widthAnchor.constraint(equalToConstant: 188).isActive = true
        hudScreenRow.heightAnchor.constraint(equalToConstant: 24).isActive = true

        let lbl = NSTextField(labelWithString: "显示在")
        lbl.font = .systemFont(ofSize: 11)
        lbl.textColor = .secondaryLabelColor
        lbl.translatesAutoresizingMaskIntoConstraints = false

        hudScreenPopup.controlSize = .small
        hudScreenPopup.font = .systemFont(ofSize: 11)
        hudScreenPopup.target = self
        hudScreenPopup.action = #selector(screenPopupChanged)
        hudScreenPopup.translatesAutoresizingMaskIntoConstraints = false

        hudScreenRow.addSubview(lbl)
        hudScreenRow.addSubview(hudScreenPopup)
        NSLayoutConstraint.activate([
            lbl.leadingAnchor.constraint(equalTo: hudScreenRow.leadingAnchor),
            lbl.centerYAnchor.constraint(equalTo: hudScreenRow.centerYAnchor),
            hudScreenPopup.leadingAnchor.constraint(equalTo: lbl.trailingAnchor, constant: 6),
            hudScreenPopup.trailingAnchor.constraint(equalTo: hudScreenRow.trailingAnchor),
            hudScreenPopup.centerYAnchor.constraint(equalTo: hudScreenRow.centerYAnchor),
        ])
        stack.addArrangedSubview(hudScreenRow)
        hudScreenRow.isHidden = NSScreen.screens.count <= 1
    }

    fileprivate func refreshScreenPopup(hud: HUDWindowController) {
        hudScreenPopup.removeAllItems()
        hudScreenPopup.addItem(withTitle: "跟随焦点屏幕")
        for (i, screen) in NSScreen.screens.enumerated() {
            let name = screen.localizedName.isEmpty ? "屏幕 \(i + 1)" : screen.localizedName
            hudScreenPopup.addItem(withTitle: name)
        }
        let sel = max(0, hud.hudScreenIndex + 1)   // -1→0, 0→1 …
        hudScreenPopup.selectItem(at: min(sel, hudScreenPopup.numberOfItems - 1))
        hudScreenRow.isHidden = NSScreen.screens.count <= 1
    }

    @objc private func screenPopupChanged() {
        guard let hud = (NSApp.delegate as? AppDelegate)?.hudController else { return }
        hud.hudScreenIndex = hudScreenPopup.indexOfSelectedItem - 1  // 0→-1, 1→0 …
    }

    @objc private func hudSizeSegChanged() {
        (NSApp.delegate as? AppDelegate)?.hudController?.hudSizePreset = hudSizeSeg.selectedSegment
    }

    @objc private func hudTextSegChanged() {
        (NSApp.delegate as? AppDelegate)?.hudController?.hudTextStyle = hudTextSeg.selectedSegment
    }

    @objc private func openGitHub() {
        NSWorkspace.shared.open(URL(string: "https://github.com/framecy/Tail-Input")!)
    }
}

// MARK: - RulesPane

final class RulesPane: NSView, NSTableViewDataSource, NSTableViewDelegate {
    var onAddTapped: (() -> Void)?

    private var rules: [ConfiguredApp] = []
    private let searchField = NSSearchField()
    private var filtered: [ConfiguredApp] = []
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "暂无规则 — 点击 + 添加应用")

    override init(frame: NSRect) {
        super.init(frame: frame)
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    func reload() {
        rules = ConfiguredAppStore.shared.all()
        applyFilter()
    }

    private func applyFilter() {
        let q = searchField.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        filtered = q.isEmpty ? rules : rules.filter {
            $0.appName.lowercased().contains(q) || $0.bundleId.lowercased().contains(q)
        }
        tableView.reloadData()
        emptyLabel.isHidden = !filtered.isEmpty
    }

    private func build() {
        // Title bar area
        let titleLabel = NSTextField(labelWithString: "应用输入法规则")
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let addBtn = NSButton(image: NSImage(systemSymbolName: "plus", accessibilityDescription: "添加")!, target: self, action: #selector(addTapped))
        addBtn.bezelStyle = .texturedRounded
        addBtn.isBordered = true
        addBtn.translatesAutoresizingMaskIntoConstraints = false

        let topBar = NSView()
        topBar.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(titleLabel)
        topBar.addSubview(addBtn)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: topBar.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            addBtn.trailingAnchor.constraint(equalTo: topBar.trailingAnchor),
            addBtn.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 36),
        ])

        // Search
        searchField.placeholderString = "搜索应用名称或 Bundle ID"
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.target = self
        searchField.action = #selector(searchChanged)
        (searchField.delegate as? NSObject)?.setValue(self, forKey: "delegate")
        searchField.delegate = self as? NSSearchFieldDelegate

        // Table
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)
        tableView.headerView = nil
        tableView.rowHeight = 52
        tableView.selectionHighlightStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        tableView.intercellSpacing = NSSize(width: 0, height: 4)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = true

        addSubview(topBar)
        addSubview(searchField)
        addSubview(scrollView)
        addSubview(emptyLabel)
        topBar.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            topBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            topBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

            searchField.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 10),
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            searchField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 0),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 0),

            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 40),
        ])
    }

    @objc private func addTapped() { onAddTapped?() }

    @objc private func searchChanged() { applyFilter() }

    // MARK: NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let app = filtered[row]
        let cell = RuleRowView()
        cell.configure(app: app) { [weak self] newStrategy in
            guard let self = self else { return }
            ConfiguredAppStore.shared.setStrategy(newStrategy, for: app.bundleId, appName: app.appName)
            self.reload()
        } onDelete: { [weak self] in
            guard let self = self else { return }
            ConfiguredAppStore.shared.remove(bundleId: app.bundleId)
            self.reload()
        }
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { 52 }
}

extension RulesPane: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) { applyFilter() }
}

// MARK: - RuleRowView

private final class RuleRowView: NSTableRowView {
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let bundleLabel = NSTextField(labelWithString: "")
    private let strategyPopup = NSPopUpButton()
    private let deleteBtn = NSButton()
    private var onChange: ((AppInputStrategy) -> Void)?
    private var onDelete: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        buildLayout()
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(app: ConfiguredApp, onChange: @escaping (AppInputStrategy) -> Void, onDelete: @escaping () -> Void) {
        self.onChange = onChange
        self.onDelete = onDelete

        nameLabel.stringValue = app.appName
        // path: 合成 ID 在 UI 上去掉前缀，只露真实路径
        bundleLabel.stringValue = app.bundleId.hasPrefix("path:")
            ? String(app.bundleId.dropFirst("path:".count))
            : app.bundleId

        if app.bundleId.hasPrefix("path:") {
            iconView.image = NSWorkspace.shared.icon(forFile: String(app.bundleId.dropFirst("path:".count)))
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleId) {
            iconView.image = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            iconView.image = NSWorkspace.shared.icon(forFileType: "app")
        }

        let titles = ["切换为英文", "切换为中文", "保持不变", "恢复上次"]
        let strategies: [AppInputStrategy] = [.forceEnglish, .forceChinese, .keepCurrent, .restorePrevious]
        strategyPopup.removeAllItems()
        strategyPopup.addItems(withTitles: titles)
        if let idx = strategies.firstIndex(of: app.strategy) {
            strategyPopup.selectItem(at: idx)
        }
    }

    private func buildLayout() {
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 32).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 32).isActive = true

        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        bundleLabel.font = .systemFont(ofSize: 10)
        bundleLabel.textColor = .tertiaryLabelColor
        bundleLabel.lineBreakMode = .byTruncatingTail
        bundleLabel.translatesAutoresizingMaskIntoConstraints = false

        let textStack = NSStackView(views: [nameLabel, bundleLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        strategyPopup.bezelStyle = .roundRect
        strategyPopup.translatesAutoresizingMaskIntoConstraints = false
        strategyPopup.target = self
        strategyPopup.action = #selector(strategyChanged)

        deleteBtn.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "删除")
        deleteBtn.isBordered = false
        deleteBtn.bezelStyle = .inline
        deleteBtn.contentTintColor = .tertiaryLabelColor
        deleteBtn.translatesAutoresizingMaskIntoConstraints = false
        deleteBtn.target = self
        deleteBtn.action = #selector(deleteTapped)

        let row = NSStackView(views: [iconView, textStack, NSView(), strategyPopup, deleteBtn])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        // Let textStack compress
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    override func drawBackground(in dirtyRect: NSRect) {
        if isSelected { return }
        NSColor.quaternaryLabelColor.withAlphaComponent(0.08).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
    }

    @objc private func strategyChanged() {
        let strategies: [AppInputStrategy] = [.forceEnglish, .forceChinese, .keepCurrent, .restorePrevious]
        let idx = strategyPopup.indexOfSelectedItem
        if idx >= 0 && idx < strategies.count {
            onChange?(strategies[idx])
        }
    }

    @objc private func deleteTapped() { onDelete?() }
}

// MARK: - BrowserPane

final class BrowserPane: NSView, NSTableViewDataSource, NSTableViewDelegate {
    var onBack: (() -> Void)?
    var onAppAdded: (() -> Void)?

    private struct AppEntry {
        let bundleId: String
        let name: String
        let url: URL
    }

    private var allApps: [AppEntry] = []
    private var filtered: [AppEntry] = []
    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let spinner = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: "")
    private let strategySegment = NSSegmentedControl(
        labels: ["英文", "中文", "保持", "恢复"],
        trackingMode: .selectOne, target: nil, action: nil)
    private let addBtn = NSButton(title: "添加规则", target: nil, action: nil)

    private var selectedBundleId: String?
    private var selectedAppName: String?

    override init(frame: NSRect) {
        super.init(frame: frame)
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    func reset() {
        searchField.stringValue = ""
        tableView.deselectAll(nil)
        selectedBundleId = nil
        selectedAppName = nil
        updateAddButton()
        if allApps.isEmpty { loadApps() }
        else { applyFilter() }
    }

    private func loadApps() {
        spinner.isHidden = false
        spinner.startAnimation(nil)
        statusLabel.stringValue = "正在扫描已安装应用…"
        statusLabel.isHidden = false
        scrollView.isHidden = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let entries = self.scanInstalledApps()
            DispatchQueue.main.async {
                self.allApps = entries
                self.spinner.stopAnimation(nil)
                self.spinner.isHidden = true
                self.statusLabel.isHidden = true
                self.scrollView.isHidden = false
                self.applyFilter()
            }
        }
    }

    private func scanInstalledApps() -> [AppEntry] {
        let fm = FileManager.default
        let dirs = [
            "/Applications",
            "\(NSHomeDirectory())/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
        ]
        var seenPaths = Set<String>()
        var result: [AppEntry] = []

        func addEntry(at rawPath: String, fallbackName: String) {
            let path = (rawPath as NSString).standardizingPath
            guard !seenPaths.contains(path) else { return }
            // .app 包必须真实存在（mdfind 索引可能滞后）
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return }

            let info = NSDictionary(contentsOfFile: "\(path)/Contents/Info.plist")
            // 优先 CFBundleIdentifier；缺失时用 `path:<绝对路径>` 当合成 ID。
            // AppObserver 在 NSRunningApplication.bundleIdentifier == nil 时会同样回退到此格式。
            let bid: String
            if let realBid = info?["CFBundleIdentifier"] as? String, !realBid.isEmpty {
                bid = realBid
            } else {
                bid = "path:\(path)"
            }
            let name = (info?["CFBundleDisplayName"] as? String)
                ?? (info?["CFBundleName"] as? String)
                ?? URL(fileURLWithPath: path).lastPathComponent.replacingOccurrences(of: ".app", with: "")
            seenPaths.insert(path)
            result.append(AppEntry(bundleId: bid, name: name, url: URL(fileURLWithPath: path)))
        }

        // ① 文件系统递归扫描，覆盖常见安装位置（深度 2）
        func scan(_ dir: String, depth: Int) {
            guard depth >= 0, let items = try? fm.contentsOfDirectory(atPath: dir) else { return }
            for item in items {
                let path = "\(dir)/\(item)"
                if item.hasSuffix(".app") {
                    addEntry(at: path, fallbackName: item)
                } else if depth > 0 {
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue,
                       !path.hasSuffix(".framework"), !path.hasSuffix(".bundle") {
                        scan(path, depth: depth - 1)
                    }
                }
            }
        }
        for dir in dirs { scan(dir, depth: 2) }

        // ② Spotlight 兜底（mdfind 同步子进程），捕获文件系统扫描遗漏的非标准 bundle
        for path in scanViaSpotlight() {
            addEntry(at: path, fallbackName: URL(fileURLWithPath: path).lastPathComponent)
        }

        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// 同步调用 mdfind 列出系统 Spotlight 索引到的所有 .app bundle 路径。
    /// 失败 / 超时返回空数组，由上层文件系统扫描兜底。
    private func scanViaSpotlight() -> [String] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        proc.arguments = ["kMDItemContentTypeTree == 'com.apple.application-bundle'"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()

        do {
            try proc.run()
        } catch {
            return []
        }
        // 2 秒安全超时（mdfind 通常 <100ms 返回）
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) { [weak proc] in
            if proc?.isRunning == true { proc?.terminate() }
        }
        proc.waitUntilExit()

        guard let output = try? pipe.fileHandleForReading.readToEnd(),
              let str = String(data: output, encoding: .utf8) else { return [] }
        return str.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    /// 手动选择 .app 文件，绕过自动扫描。
    /// 返回 nil 表示用户取消。
    private func pickAppManually() -> AppEntry? {
        let panel = NSOpenPanel()
        panel.title = "选择应用"
        panel.message = "选择需要配置规则的 .app 文件"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false  // .app 当作单一文件而非目录
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [.application]
        } else {
            panel.allowedFileTypes = ["app"]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        let path = url.path
        let info = NSDictionary(contentsOfFile: "\(path)/Contents/Info.plist")
        let bid: String
        if let realBid = info?["CFBundleIdentifier"] as? String, !realBid.isEmpty {
            bid = realBid
        } else {
            bid = "path:\(path)"
        }
        let name = (info?["CFBundleDisplayName"] as? String)
            ?? (info?["CFBundleName"] as? String)
            ?? url.lastPathComponent.replacingOccurrences(of: ".app", with: "")
        return AppEntry(bundleId: bid, name: name, url: url)
    }

    private func applyFilter() {
        let q = searchField.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        filtered = q.isEmpty ? allApps : allApps.filter {
            $0.name.lowercased().contains(q) || $0.bundleId.lowercased().contains(q)
        }
        tableView.reloadData()
    }

    private func updateAddButton() {
        addBtn.isEnabled = selectedBundleId != nil
    }

    private func build() {
        // Back button
        let backBtn = NSButton(title: "← 返回", target: self, action: #selector(backTapped))
        backBtn.bezelStyle = .inline
        backBtn.isBordered = false
        backBtn.font = .systemFont(ofSize: 13)
        backBtn.contentTintColor = .secondaryLabelColor
        backBtn.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "选择应用")
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // 手动选择按钮：兜底入口，搜不到的 .app 可以直接 NSOpenPanel 选
        let manualBtn = NSButton(title: "手动选择…", target: self, action: #selector(manualPickTapped))
        manualBtn.bezelStyle = .inline
        manualBtn.isBordered = false
        manualBtn.font = .systemFont(ofSize: 12)
        manualBtn.contentTintColor = .controlAccentColor
        manualBtn.translatesAutoresizingMaskIntoConstraints = false

        let topBar = NSView()
        topBar.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(backBtn)
        topBar.addSubview(titleLabel)
        topBar.addSubview(manualBtn)
        NSLayoutConstraint.activate([
            backBtn.leadingAnchor.constraint(equalTo: topBar.leadingAnchor),
            backBtn.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: topBar.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            manualBtn.trailingAnchor.constraint(equalTo: topBar.trailingAnchor),
            manualBtn.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 36),
        ])

        // Search
        searchField.placeholderString = "搜索应用名称或 Bundle ID"
        searchField.delegate = self as? NSSearchFieldDelegate
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.target = self
        searchField.action = #selector(searchChanged)

        // Spinner + status
        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.isIndeterminate = true
        spinner.isHidden = true
        spinner.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center
        statusLabel.isHidden = true
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        // Table
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)
        tableView.headerView = nil
        tableView.rowHeight = 44
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.allowsEmptySelection = true

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        // Bottom bar: strategy + add
        strategySegment.selectedSegment = 0
        strategySegment.translatesAutoresizingMaskIntoConstraints = false

        addBtn.bezelStyle = .rounded
        addBtn.isEnabled = false
        addBtn.translatesAutoresizingMaskIntoConstraints = false
        addBtn.target = self
        addBtn.action = #selector(addTapped)

        let bottomBar = NSView()
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(strategySegment)
        bottomBar.addSubview(addBtn)
        NSLayoutConstraint.activate([
            strategySegment.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor),
            strategySegment.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            addBtn.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor),
            addBtn.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 40),
        ])

        addSubview(topBar)
        addSubview(searchField)
        addSubview(scrollView)
        addSubview(spinner)
        addSubview(statusLabel)
        addSubview(bottomBar)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            topBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            topBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

            searchField.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 10),
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            searchField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -8),

            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 20),

            statusLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 8),
            statusLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            bottomBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            bottomBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            bottomBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])
    }

    @objc private func backTapped() { onBack?() }

    @objc private func searchChanged() { applyFilter() }

    @objc private func addTapped() {
        guard let bundleId = selectedBundleId,
              let appName = selectedAppName else { return }
        let strategies: [AppInputStrategy] = [.forceEnglish, .forceChinese, .keepCurrent, .restorePrevious]
        let idx = strategySegment.selectedSegment
        let strategy = (idx >= 0 && idx < strategies.count) ? strategies[idx] : .forceEnglish
        ConfiguredAppStore.shared.setStrategy(strategy, for: bundleId, appName: appName)
        onAppAdded?()
    }

    @objc private func manualPickTapped() {
        guard let entry = pickAppManually() else { return }
        // 把手动挑选的 entry 塞进当前列表（如果已存在则只选中），并清空搜索高亮它
        if !allApps.contains(where: { $0.bundleId == entry.bundleId }) {
            allApps.insert(entry, at: 0)
        }
        searchField.stringValue = ""
        applyFilter()
        if let idx = filtered.firstIndex(where: { $0.bundleId == entry.bundleId }) {
            tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
            tableView.scrollRowToVisible(idx)
        }
    }

    // MARK: NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = filtered[row]
        let cell = AppBrowserRowView()
        cell.configure(name: entry.name, bundleId: entry.bundleId, url: entry.url)
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { 44 }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        if row >= 0 && row < filtered.count {
            selectedBundleId = filtered[row].bundleId
            selectedAppName = filtered[row].name
        } else {
            selectedBundleId = nil
            selectedAppName = nil
        }
        updateAddButton()
    }
}

extension BrowserPane: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) { applyFilter() }
}

// MARK: - AppBrowserRowView

private final class AppBrowserRowView: NSTableRowView {
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let bundleLabel = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        buildLayout()
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(name: String, bundleId: String, url: URL) {
        nameLabel.stringValue = name
        // path: 合成 ID 在 UI 上去掉前缀
        bundleLabel.stringValue = bundleId.hasPrefix("path:")
            ? String(bundleId.dropFirst("path:".count))
            : bundleId
        iconView.image = NSWorkspace.shared.icon(forFile: url.path)
    }

    private func buildLayout() {
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 28).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 28).isActive = true

        nameLabel.font = .systemFont(ofSize: 13)
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        bundleLabel.font = .systemFont(ofSize: 10)
        bundleLabel.textColor = .tertiaryLabelColor
        bundleLabel.lineBreakMode = .byTruncatingTail
        bundleLabel.translatesAutoresizingMaskIntoConstraints = false

        let textStack = NSStackView(views: [nameLabel, bundleLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [iconView, textStack])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
}

// MARK: - HUDPositionPicker

private final class HUDPositionPicker: NSView {
    var onChange: ((HUDPosition) -> Void)?
    private var buttons: [NSButton] = []

    // 行从上到下排列
    private static let layout: [(HUDPosition, String)] = [
        (.topLeft,     "arrow.up.left"),
        (.topCenter,   "arrow.up"),
        (.topRight,    "arrow.up.right"),
        (.middleLeft,  "arrow.left"),
        (.middleCenter,"dot.square"),
        (.middleRight, "arrow.right"),
        (.bottomLeft,  "arrow.down.left"),
        (.bottomCenter,"arrow.down"),
        (.bottomRight, "arrow.down.right"),
    ]

    override init(frame: NSRect) {
        super.init(frame: frame)
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    func setSelected(_ position: HUDPosition) {
        for btn in buttons {
            btn.state = HUDPosition(rawValue: btn.tag) == position ? .on : .off
        }
    }

    private func build() {
        let btnW: CGFloat = 36
        let btnH: CGFloat = 30
        let gap:  CGFloat = 3
        let gridW = btnW * 3 + gap * 2   // 114pt

        let vStack = NSStackView()
        vStack.orientation = .vertical
        vStack.spacing = gap
        vStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(vStack)
        NSLayoutConstraint.activate([
            vStack.topAnchor.constraint(equalTo: topAnchor),
            vStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            vStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        for row in 0..<3 {
            let hStack = NSStackView()
            hStack.orientation = .horizontal
            hStack.spacing = gap
            for col in 0..<3 {
                let (pos, symbol) = Self.layout[row * 3 + col]
                let btn = NSButton()
                btn.tag = pos.rawValue
                btn.bezelStyle = .regularSquare
                btn.setButtonType(.pushOnPushOff)
                btn.translatesAutoresizingMaskIntoConstraints = false
                btn.widthAnchor.constraint(equalToConstant: btnW).isActive = true
                btn.heightAnchor.constraint(equalToConstant: btnH).isActive = true
                if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
                    btn.image = img.withSymbolConfiguration(
                        NSImage.SymbolConfiguration(pointSize: 10, weight: .regular))
                }
                btn.target = self
                btn.action = #selector(tapped(_:))
                hStack.addArrangedSubview(btn)
                buttons.append(btn)
            }
            vStack.addArrangedSubview(hStack)
        }

        // "鼠标附近" — 跨行全宽按钮
        let nearBtn = NSButton(title: "鼠标附近", target: self, action: #selector(tapped(_:)))
        nearBtn.tag = HUDPosition.nearMouse.rawValue
        nearBtn.bezelStyle = .regularSquare
        nearBtn.setButtonType(.pushOnPushOff)
        nearBtn.font = .systemFont(ofSize: 11)
        nearBtn.translatesAutoresizingMaskIntoConstraints = false
        nearBtn.widthAnchor.constraint(equalToConstant: gridW).isActive = true
        nearBtn.heightAnchor.constraint(equalToConstant: 24).isActive = true
        vStack.addArrangedSubview(nearBtn)
        buttons.append(nearBtn)

        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: gridW).isActive = true
    }

    @objc private func tapped(_ sender: NSButton) {
        guard let pos = HUDPosition(rawValue: sender.tag) else { return }
        setSelected(pos)
        onChange?(pos)
    }
}

// MARK: - LabeledToggle

private final class LabeledToggle: NSView {
    var isOn: Bool {
        get { toggle.state == .on }
        set { toggle.state = newValue ? .on : .off }
    }
    var onChange: ((Bool) -> Void)?

    private let label = NSTextField(labelWithString: "")
    private let toggle = NSSwitch()

    init(label text: String) {
        super.init(frame: .zero)
        label.stringValue = text
        label.font = .systemFont(ofSize: 13)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        toggle.controlSize = .small
        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.target = self
        toggle.action = #selector(toggled)

        addSubview(label)
        addSubview(toggle)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            toggle.trailingAnchor.constraint(equalTo: trailingAnchor),
            toggle.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 28),
            widthAnchor.constraint(equalToConstant: 188),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func toggled() { onChange?(toggle.state == .on) }
}

// MARK: - Helpers

private final class Spacer: NSView {
    init(_ height: CGFloat) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: height).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }
}

private extension Bundle {
    var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
}

