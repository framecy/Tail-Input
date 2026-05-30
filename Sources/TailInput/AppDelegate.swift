import Cocoa
import ServiceManagement
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var isEnabled = true
    var hudController: HUDWindowController?
    var welcomeController: WelcomeWindowController?

    // Keep running when all windows are closed (menu bar app remains active)
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // Clicking the Dock icon while running re-opens the settings window
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MainWindowController.shared.showWindow() }
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 装配主菜单 — Cmd+W / Cmd+A / Cmd+C / Cmd+V / Cmd+Q 等系统快捷键的来源
        setupMainMenu()

        // 固定 26pt：纯文字徽章"中"/"En"，切换时宽度不跳变
        statusItem = NSStatusBar.system.statusItem(withLength: 26)

        updateStatusBarButton()

        hudController = HUDWindowController()

        // onInputStateRefreshed：TIS 通知无条件触发，仅更新状态栏图标（无 HUD 去重干扰）
        InputMethodManager.shared.onInputStateRefreshed = { [weak self] _ in
            self?.updateStatusBarButton()
        }
        // onInputMethodChanged：带去重，App 自身发起的切换走此路径，同时刷新状态栏和 HUD
        InputMethodManager.shared.onInputMethodChanged = { [weak self] isChinese in
            self?.updateStatusBarButton()
            self?.hudController?.showHUD(isChinese: isChinese)
        }

        // ── 性能优化：菜单懒构建，仅在用户点击时才构建 ──
        InputMethodManager.shared.onAppChanged = { [weak self] in
            self?.updateStatusBarButton()
        }

        // 离开 App 前保存当前输入源（用于 restorePrevious 策略）
        AppObserver.shared.onAppWillChange = { bundleID in
            InputMethodManager.shared.saveCurrentInputSource(for: bundleID)
        }

        // 绑定系统激活事件
        AppObserver.shared.onAppActivated = { [weak self] bundleId, appName in
            guard let self = self else { return }

            if self.isEnabled {
                InputMethodManager.shared.applyStrategy(for: bundleId, appName: appName)
            } else {
                InputMethodManager.shared.currentAppBundleIdentifier = bundleId
                InputMethodManager.shared.currentAppName = appName
            }
        }

        AppObserver.shared.start()

        // 启动 Helper 后台进程（CGEvent tap + TIS 切换容灾）
        HelperDaemon.shared.launch()

        // 恢复强制英文标点开关（UserDefaults 持久化）
        if UserDefaults.standard.bool(forKey: "PunctuationServiceEnabled") {
            _ = InputMethodManager.shared.punctuationService.start()
        }

        // 启动时如果用户之前已开启 CapsLock 拦截，恢复模式后尝试 start —— tap 创建成功即代表权限有效
        let savedMode = InputMethodManager.shared.capsLockMode
        if savedMode != .off {
            CapsLockInterceptor.shared.mode = savedMode
            CapsLockInterceptor.shared.start()
        }

        // 重启后自动开启：用户点击"立即重启"后由新进程在此处接管，使用保存的模式
        if UserDefaults.standard.bool(forKey: "PendingCapsLockEnableOnLaunch") {
            UserDefaults.standard.removeObject(forKey: "PendingCapsLockEnableOnLaunch")
            let targetMode: CapsLockMode = savedMode == .off ? .compat : savedMode
            if InputMethodManager.shared.tryEnableCapsLockMode(targetMode) {
                // 重启后权限生效，刷新 UI（主窗口可能尚未创建，延迟执行）
                DispatchQueue.main.async {
                    MainWindowController.shared.refreshSidebar()
                }
            } else {
                // 重启后仍然失败：提示用户重新授权
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "辅助功能权限未能激活"
                    alert.informativeText = "请在「系统设置 → 隐私与安全 → 辅助功能」中确认 Tail Input 已开启，然后再次尝试开启 CapsLock 直接切换。"
                    alert.addButton(withTitle: "好")
                    alert.window.level = .floating
                    alert.runModal()
                }
            }
        }

        // App 从后台回到前台时重试 start（用户从系统设置授权后切回时关键路径）
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )

        // 左键点击唤起主窗口；右键仍弹出菜单
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.target = self
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        // ── 启动窗口：首次运行显示 Onboarding，否则直接打开设置窗口 ──
        if !UserDefaults.standard.bool(forKey: "HasSeenWelcomePagev2") {
            welcomeController = WelcomeWindowController()
            welcomeController?.showWindow(nil)
        } else {
            MainWindowController.shared.showWindow()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - 主菜单

    /// 构建标准 macOS 主菜单。
    /// 为什么需要：.regular 应用如果不设置 NSApp.mainMenu，
    /// 系统快捷键（Cmd+W/A/C/V/X/Z/Q 等）不会派发到 first responder。
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App 菜单（标题不显示，但内容会成为应用名所在的首个菜单）
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 Tail Input",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 Tail Input",
                        action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "隐藏其他",
                                    action: #selector(NSApplication.hideOtherApplications(_:)),
                                    keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: "显示全部",
                        action: #selector(NSApplication.unhideAllApplications(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 Tail Input",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // 编辑菜单 — 系统通过 first responder 派发到 NSTextField / NSTableView
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // 窗口菜单 — Cmd+W 关闭、Cmd+M 最小化
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "最小化",
                           action: #selector(NSWindow.performMiniaturize(_:)),
                           keyEquivalent: "m")
        windowMenu.addItem(withTitle: "关闭",
                           action: #selector(NSWindow.performClose(_:)),
                           keyEquivalent: "w")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    // MARK: - 状态栏按钮更新

    func updateStatusBarButton() {
        guard let button = statusItem.button else { return }
        let isChinese = InputMethodManager.shared.cachedIsChinese
        button.image = makeStatusBadge(isChinese: isChinese)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.title = ""
        button.attributedTitle = NSAttributedString()
    }

    /// 纯文字 template 徽章：中文 = medium "中"，英文 = light "En"。
    /// isTemplate=true 让系统处理深/浅色菜单栏及高亮反色，低调无侵入感。
    private func makeStatusBadge(isChinese: Bool) -> NSImage {
        let imgW: CGFloat = 24
        let imgH: CGFloat = 20
        let image = NSImage(size: NSSize(width: imgW, height: imgH), flipped: false) { _ in
            let label    = isChinese ? "中" : "En"
            let fontSize = isChinese ? CGFloat(14) : CGFloat(12)
            let weight   = isChinese ? NSFont.Weight.medium : NSFont.Weight.light
            let font     = NSFont.systemFont(ofSize: fontSize, weight: weight)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.labelColor,
            ]
            let str  = NSAttributedString(string: label, attributes: attrs)
            let sz   = str.size()
            str.draw(at: NSPoint(x: (imgW - sz.width) / 2, y: (imgH - sz.height) / 2))
            return true
        }
        image.isTemplate = true
        return image
    }

    /// 构建菜单内容（仅在菜单即将显示时调用）
    private func buildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        // ── 当前应用 + 策略选择 ──
        if let appName = InputMethodManager.shared.currentAppName,
           let bundleId = InputMethodManager.shared.currentAppBundleIdentifier {

            // Section header: app name (non-interactive)
            let appItem = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
            appItem.isEnabled = false
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = NSSize(width: 16, height: 16)
                appItem.image = icon
            }
            menu.addItem(appItem)

            let strategy = InputMethodManager.shared.getStrategy(for: bundleId)

            // Strategy options — indented, with SF Symbol icons
            let strategies: [(AppInputStrategy, String, String)] = [
                (.globalDefault, "跟随全局设置", "circle"),
                (.forceEnglish,  "切换为英文",   "e.circle"),
                (.forceChinese,  "切换为中文",   "globe.asia.australia"),
                (.keepCurrent,   "保持不变",     "arrow.uturn.backward"),
                (.restorePrevious, "恢复上次输入源", "arrow.triangle.2.circlepath"),
            ]
            let iconCfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
            for (s, title, symbol) in strategies {
                let item = NSMenuItem(title: title,
                                      action: #selector(setStrategy(_:)),
                                      keyEquivalent: "")
                item.tag = s.rawValue
                item.state = strategy == s ? .on : .off
                item.indentationLevel = 1
                item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                    .flatMap { $0.withSymbolConfiguration(iconCfg) }
                menu.addItem(item)
            }

            menu.addItem(NSMenuItem.separator())
        }

        // ── 功能开关 ──
        let enableItem = NSMenuItem(title: "自动切换输入法",
                                    action: #selector(toggleAutoSwitch(_:)),
                                    keyEquivalent: "")
        enableItem.state = isEnabled ? .on : .off
        menu.addItem(enableItem)

        let loginItem = NSMenuItem(title: "开机自启动",
                                   action: #selector(toggleLaunchAtLogin(_:)),
                                   keyEquivalent: "")
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)

        // CapsLock 三态子菜单：关闭 / 兼容 / 纯切换
        let capsLockItem = NSMenuItem(title: "CapsLock 切换", action: nil, keyEquivalent: "")
        let capsSub = NSMenu()
        let currentMode = InputMethodManager.shared.capsLockMode
        let entries: [(String, CapsLockMode, String)] = [
            ("关闭",   .off,    "不拦截 CapsLock，走系统原生行为"),
            ("兼容模式", .compat, "短按 < 300ms 切换输入法，保留 macOS 原生 CapsLock 体验"),
            ("纯切换模式", .pure,   "按下即切换，零延迟，完全禁用大写锁定（需辅助功能权限）"),
        ]
        for (title, mode, tip) in entries {
            let item = NSMenuItem(title: title, action: #selector(setCapsLockMode(_:)), keyEquivalent: "")
            item.tag = mode.rawValue
            item.state = (mode == currentMode) ? .on : .off
            item.toolTip = tip
            capsSub.addItem(item)
        }
        capsLockItem.submenu = capsSub
        menu.addItem(capsLockItem)

        // ── 强制英文标点 ──
        let punctItem = NSMenuItem(title: "强制英文标点",
                                    action: #selector(togglePunctuationService(_:)),
                                    keyEquivalent: "")
        punctItem.state = punctuationServiceEnabled ? .on : .off
        menu.addItem(punctItem)

        menu.addItem(NSMenuItem.separator())

        // ── 应用规则管理窗口 ──
        let listItem = NSMenuItem(title: "应用输入法规则\u{2026}",
                                  action: #selector(openAppList),
                                  keyEquivalent: ",")
        menu.addItem(listItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出 Tail Input",
                                action: #selector(quit),
                                keyEquivalent: "q"))
    }

    // MARK: - Actions

    @objc func setStrategy(_ sender: NSMenuItem) {
        guard let bundleId = InputMethodManager.shared.currentAppBundleIdentifier else { return }
        if let newStrategy = AppInputStrategy(rawValue: sender.tag) {
            InputMethodManager.shared.setStrategy(newStrategy, for: bundleId)
        }
    }

    @objc func toggleAutoSwitch(_ sender: NSMenuItem) {
        isEnabled.toggle()
        AppObserver.shared.isEnabled = isEnabled
    }

    @objc func setCapsLockMode(_ sender: NSMenuItem) {
        guard let mode = CapsLockMode(rawValue: sender.tag) else { return }
        let manager = InputMethodManager.shared
        if mode == .off {
            manager.capsLockMode = .off
            MainWindowController.shared.refreshSidebar()
            return
        }
        // .pure 模式与 macOS 原生 "用 CapsLock 切换 ABC" 互斥，首次启用前确认
        if mode == .pure && !confirmPureModeMacOSConflict() {
            MainWindowController.shared.refreshSidebar()
            return
        }
        if !manager.tryEnableCapsLockMode(mode) {
            requestAccessibilityForCapsLock(mode: mode)
        } else {
            MainWindowController.shared.refreshSidebar()
        }
    }

    /// 首次启用 pure 模式时弹窗确认 macOS 原生 CapsLock 切换已关闭。
    /// 已确认过的（UserDefaults flag 写入）会直接返回 true 不再骚扰。
    ///
    /// 返回 true 表示可以继续启用 .pure；false 表示用户取消，调用方应回滚 UI。
    @discardableResult
    func confirmPureModeMacOSConflict() -> Bool {
        let ackKey = "PureModeMacOSCheckAcknowledged"
        if UserDefaults.standard.bool(forKey: ackKey) { return true }

        let alert = NSAlert()
        alert.messageText = "纯切换模式需要关闭 macOS 原生 CapsLock 切换"
        alert.informativeText = """
        系统设置 → 键盘 → 输入法 → 编辑… 中的「使用 ⇪ 大写锁定键切换 ABC 输入源」必须保持关闭，\
        否则 macOS 和 Tail Input 会同时切换输入法，互相抵消。

        • 已经关闭了 → 点击「已关闭，启用」继续
        • 还没关 → 点击「打开系统设置」前往，关闭后再回到本 App 选择纯切换
        """
        alert.addButton(withTitle: "已关闭，启用")
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "取消")
        alert.window.level = .floating

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            UserDefaults.standard.set(true, forKey: ackKey)
            return true
        case .alertSecondButtonReturn:
            if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
            return false
        default:
            return false
        }
    }

    /// 引导用户去系统设置授权辅助功能（使用 osascript）。
    /// 授权成功但进程仍需重启时，会在 didBecomeActive 时自动弹出重启提示。
    func requestAccessibilityForCapsLock(mode: CapsLockMode = .compat) {
        let alert = NSAlert()
        alert.messageText = "请授权辅助功能"
        alert.informativeText = "CapsLock 直接切换需要 Tail Input 在「系统设置 → 隐私与安全 → 辅助功能」中被授权。\n\n点击「打开系统设置」，在列表中找到 Tail Input 并开启开关，然后切回本 App 即可自动激活。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "取消")
        alert.window.level = .floating

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        // 标记期望的模式；didBecomeActive 负责重试
        pendingCapsLockMode = mode

        // 使用 osascript 打开隐私面板 + 轮询等待
        AccessibilityManager.shared.requestAndAwaitGrant(onGranted: { [weak self] in
            guard let self, let mode = self.pendingCapsLockMode else { return }
            // 权限已获取，尝试立即启动 tap
            if InputMethodManager.shared.tryEnableCapsLockMode(mode) {
                self.pendingCapsLockMode = nil
                MainWindowController.shared.refreshSidebar()
            }
            // 如果 tap 创建仍然失败（进程需重启），不清理 pendingCapsLockMode，
            // 留给 handleAppDidBecomeActive 展示重启提示
        })
    }

    /// 用户期望开启拦截器但当前没权限，等待用户回到 App 时重试。
    /// nil 表示无待处理；非 nil 即重试目标模式。
    private var pendingCapsLockMode: CapsLockMode?
    /// 防止重复弹出重启 Alert
    private var didShowRestartAlert = false

    @objc func handleAppDidBecomeActive() {
        guard let mode = pendingCapsLockMode else { return }
        if InputMethodManager.shared.tryEnableCapsLockMode(mode) {
            pendingCapsLockMode = nil
            didShowRestartAlert = false
            MainWindowController.shared.refreshSidebar()
        } else if !didShowRestartAlert {
            // 权限已授予但当前进程仍无法创建 tap（macOS 部分版本需重启进程）
            pendingCapsLockMode = nil
            didShowRestartAlert = true
            showRestartForCapsLockAlert()
        }
    }

    /// 提示用户需要重启 App 才能激活 CapsLock tap（权限已授但当前进程无法感知）
    private func showRestartForCapsLockAlert() {
        let alert = NSAlert()
        alert.messageText = "需要重启 App"
        alert.informativeText = "辅助功能权限已授予，但当前进程需要重启才能激活 CapsLock 功能。点击「立即重启」，App 重启后会自动启用。"
        alert.addButton(withTitle: "立即重启")
        alert.addButton(withTitle: "稍后")
        alert.window.level = .floating

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        UserDefaults.standard.set(true, forKey: "PendingCapsLockEnableOnLaunch")

        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.open(Bundle.main.bundleURL, configuration: config, completionHandler: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            NSApp.terminate(nil)
        }
    }

    @objc func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            print("Failed to toggle Launch at Login: \(error)")
        }
    }

    @objc func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            // 右键弹出菜单
            let menu = NSMenu()
            menu.delegate = self
            buildMenu(menu)
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            MainWindowController.shared.showWindow()
        }
    }

    @objc func openAppList() {
        MainWindowController.shared.showWindow()
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - 强制英文标点

    var punctuationServiceEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "PunctuationServiceEnabled") }
        set {
            UserDefaults.standard.set(newValue, forKey: "PunctuationServiceEnabled")
            if newValue {
                _ = InputMethodManager.shared.punctuationService.start()
            } else {
                InputMethodManager.shared.punctuationService.stop()
            }
        }
    }

    @objc func togglePunctuationService(_ sender: NSMenuItem) {
        let willEnable = !punctuationServiceEnabled
        if willEnable {
            // 尝试启动；失败则引导输入监控权限
            if !InputMethodManager.shared.punctuationService.start() {
                let alert = NSAlert()
                alert.messageText = "需要输入监控权限"
                alert.informativeText = "强制英文标点需要在「系统设置 → 隐私与安全 → 输入监控」中授权 Tail Input。\n\n点击「打开系统设置」前往授权。"
                alert.addButton(withTitle: "打开系统设置")
                alert.addButton(withTitle: "取消")
                alert.window.level = .floating
                if alert.runModal() == .alertFirstButtonReturn {
                    TCCManager.guidedAuthorizationFlow(for: .inputMonitoring, onGranted: { [weak self] in
                        _ = InputMethodManager.shared.punctuationService.start()
                        self?.punctuationServiceEnabled = true
                    })
                }
                return
            }
        } else {
            InputMethodManager.shared.punctuationService.stop()
        }
        punctuationServiceEnabled = willEnable
    }
}

// ── 性能优化：菜单仅在用户打开时才构建，而非每次 App 切换时 ──
extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        buildMenu(menu)
    }
}
