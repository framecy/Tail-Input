import Cocoa
import ServiceManagement
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var isEnabled = true
    var hudController: HUDWindowController?
    var welcomeController: WelcomeWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 固定 28pt：比 squareLength(22pt) 多给 6pt breathing room，
        // 让 character.textbox 与 keyboard 两个图标视觉重量对等，切换时宽度不跳变
        statusItem = NSStatusBar.system.statusItem(withLength: 28)

        updateStatusBarButton()

        hudController = HUDWindowController()

        // 监听输入法状态变更（更新状态栏图标与弹窗）
        InputMethodManager.shared.onInputMethodChanged = { [weak self] isChinese in
            self?.updateStatusBarButton()
            self?.hudController?.showHUD(isChinese: isChinese)
        }

        // ── 性能优化：菜单懒构建，仅在用户点击时才构建 ──
        InputMethodManager.shared.onAppChanged = { [weak self] in
            self?.updateStatusBarButton()
        }

        // 绑定系统激活事件
        AppObserver.shared.onAppActivated = { [weak self] bundleId, appName in
            guard let self = self else { return }

            if self.isEnabled {
                InputMethodManager.shared.applyStrategy(for: bundleId, appName: appName)
            } else {
                // 就算未开启总开关，也要更新状态存储
                InputMethodManager.shared.currentAppBundleIdentifier = bundleId
                InputMethodManager.shared.currentAppName = appName
            }
        }

        AppObserver.shared.start()

        // 使用 NSMenuDelegate 实现懒构建
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // ── Onboarding：首次运行显示欢迎页面 ──
        if !UserDefaults.standard.bool(forKey: "HasSeenWelcomePagev2") {
            welcomeController = WelcomeWindowController()
            welcomeController?.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - 状态栏按钮更新（仅图标，随系统深色/浅色自动适配）

    func updateStatusBarButton() {
        guard let button = statusItem.button else { return }
        let isChinese = InputMethodManager.shared.cachedIsChinese

        // 中文：character.textbox（笔画感）  英文：keyboard（直观）
        let symbolName = isChinese ? "character.textbox" : "keyboard"

        // 13pt medium weight 在 28pt 宽度内与系统原生图标视觉对齐
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            .applying(NSImage.SymbolConfiguration(hierarchicalColor: .labelColor))

        if let icon = NSImage(systemSymbolName: symbolName, accessibilityDescription: isChinese ? "中文" : "英文")?
                .withSymbolConfiguration(config) {
            icon.isTemplate = true   // 模板图像：系统自动处理深/浅色及高亮状态
            button.image = icon
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
        } else {
            // 兜底：等宽字符
            button.image = nil
            button.title = isChinese ? "中" : "En"
            button.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        }

        button.title = ""
        button.attributedTitle = NSAttributedString()
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
                (.forceEnglish,  "切换为英文",   "keyboard"),
                (.forceChinese,  "切换为中文",   "character.textbox"),
                (.keepCurrent,   "保持不变",     "arrow.uturn.backward"),
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

        let capsLockItem = NSMenuItem(title: "CapsLock 兼容模式",
                                      action: #selector(toggleCapsLockSimulation(_:)),
                                      keyEquivalent: "")
        capsLockItem.state = InputMethodManager.shared.useCapsLockSimulation ? .on : .off
        capsLockItem.toolTip = "通过模拟 CapsLock 按键完成切换，需要辅助功能权限"
        menu.addItem(capsLockItem)

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

    @objc func toggleCapsLockSimulation(_ sender: NSMenuItem) {
        let manager = InputMethodManager.shared
        if !manager.useCapsLockSimulation {
            // 开启前先要求辅助功能权限（带系统弹窗）
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            if !AXIsProcessTrustedWithOptions(options) {
                let alert = NSAlert()
                alert.messageText = "请授权辅助功能"
                alert.informativeText = "CapsLock 兼容模式需要 Tail Input 在「系统设置 - 隐私与安全 - 辅助功能」中被授权。\n\n开启后，自动切换将通过模拟 CapsLock 完成，让你之后仍然可以用 CapsLock 切回中文。\n\n请前往系统设置开启 Tail Input 的辅助功能权限，然后再次点击此菜单项。"
                alert.addButton(withTitle: "好")
                alert.runModal()
                return
            }
        }
        manager.useCapsLockSimulation.toggle()
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

    @objc func openAppList() {
        AppListWindowController.shared.showWindow()
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }
}

// ── 性能优化：菜单仅在用户打开时才构建，而非每次 App 切换时 ──
extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        buildMenu(menu)
    }
}
