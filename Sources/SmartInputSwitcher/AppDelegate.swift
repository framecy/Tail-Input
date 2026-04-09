import Cocoa
import ServiceManagement
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var isEnabled = true
    var hudController: HUDWindowController?
    var welcomeController: WelcomeWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // ── 固定宽度：避免"简"与"EN"宽度不同导致菜单栏跳动 ──
        statusItem = NSStatusBar.system.statusItem(withLength: 56)

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

    // MARK: - 状态栏按钮更新

    func updateStatusBarButton() {
        guard let button = statusItem.button else { return }
        let isChinese = InputMethodManager.shared.cachedIsChinese

        // SF Symbol：中文用 character.textbox，英文用 keyboard
        let symbolName = isChinese ? "character.textbox" : "keyboard"
        let symConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        guard let icon = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(symConfig) else {
            // 兜底：纯文字
            button.image = nil
            button.title = isChinese ? "简" : "EN"
            return
        }

        // 将 SF Symbol 嵌入 NSTextAttachment，与文字对齐后合并成 attributedTitle
        let attachment = NSTextAttachment()
        attachment.image = icon
        let iconSize = icon.size
        let font = NSFont.menuBarFont(ofSize: 12)
        let capH = font.capHeight
        attachment.bounds = CGRect(
            x: 0,
            y: (capH - iconSize.height) / 2,
            width: iconSize.width,
            height: iconSize.height
        )

        let result = NSMutableAttributedString(attachment: attachment)
        result.append(NSAttributedString(
            string: isChinese ? " 简" : " EN",
            attributes: [
                .font: font,
                .foregroundColor: NSColor.labelColor
            ]
        ))
        button.attributedTitle = result
    }

    /// 构建菜单内容（仅在菜单即将显示时调用）
    private func buildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        // 动态生成部分
        if let appName = InputMethodManager.shared.currentAppName,
           let bundleId = InputMethodManager.shared.currentAppBundleIdentifier {

            let titleItem = NSMenuItem(title: "[+] 当前前台应用: \(appName)", action: nil, keyEquivalent: "")
            titleItem.isEnabled = false
            menu.addItem(titleItem)

            let strategy = InputMethodManager.shared.getStrategy(for: bundleId)

            let s0 = NSMenuItem(title: "    默认 (切回英文)", action: #selector(setStrategy(_:)), keyEquivalent: "")
            s0.tag = AppInputStrategy.globalDefault.rawValue
            s0.state = strategy == .globalDefault ? .on : .off
            menu.addItem(s0)

            let s1 = NSMenuItem(title: "    强制为英文", action: #selector(setStrategy(_:)), keyEquivalent: "")
            s1.tag = AppInputStrategy.forceEnglish.rawValue
            s1.state = strategy == .forceEnglish ? .on : .off
            menu.addItem(s1)

            let s2 = NSMenuItem(title: "    强制为中文", action: #selector(setStrategy(_:)), keyEquivalent: "")
            s2.tag = AppInputStrategy.forceChinese.rawValue
            s2.state = strategy == .forceChinese ? .on : .off
            menu.addItem(s2)

            let s3 = NSMenuItem(title: "    保持原状态", action: #selector(setStrategy(_:)), keyEquivalent: "")
            s3.tag = AppInputStrategy.keepCurrent.rawValue
            s3.state = strategy == .keepCurrent ? .on : .off
            menu.addItem(s3)

            menu.addItem(NSMenuItem.separator())
        }

        let enableItem = NSMenuItem(
            title: isEnabled ? "✓ 开启 App 自动切换" : "  开启 App 自动切换",
            action: #selector(toggleAutoSwitch(_:)),
            keyEquivalent: ""
        )
        menu.addItem(enableItem)

        let loginStatus = SMAppService.mainApp.status == .enabled
        let loginItem = NSMenuItem(
            title: loginStatus ? "✓ 开机自启动" : "  开机自启动",
            action: #selector(toggleLaunchAtLogin(_:)),
            keyEquivalent: ""
        )
        menu.addItem(loginItem)

        // ── CapsLock 兼容模式 ──
        let capsLockOn = InputMethodManager.shared.useCapsLockSimulation
        let capsLockItem = NSMenuItem(
            title: (capsLockOn ? "✓ " : "  ") + "CapsLock 兼容模式",
            action: #selector(toggleCapsLockSimulation(_:)),
            keyEquivalent: ""
        )
        capsLockItem.toolTip = "开启后切换将通过模拟 CapsLock 完成，让 macOS 原生的 CapsLock 切换中英输入源功能保持正常工作（需要辅助功能权限）"
        menu.addItem(capsLockItem)

        menu.addItem(NSMenuItem.separator())

        // ── 应用策略管理窗口 ──
        let listItem = NSMenuItem(
            title: "管理应用策略...",
            action: #selector(openAppList),
            keyEquivalent: ","
        )
        menu.addItem(listItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
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
                alert.informativeText = "CapsLock 兼容模式需要 SimpleSwitch 在「系统设置 - 隐私与安全 - 辅助功能」中被授权。\n\n开启后，自动切换将通过模拟 CapsLock 完成，让你之后仍然可以用 CapsLock 切回中文。\n\n请前往系统设置开启 SimpleSwitch 的辅助功能权限，然后再次点击此菜单项。"
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
