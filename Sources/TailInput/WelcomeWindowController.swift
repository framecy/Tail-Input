import Cocoa
import ServiceManagement

class WelcomeWindowController: NSWindowController {
    
    private var stackView: NSStackView!
    private var currentPage = 0
    private var permissionRefreshTimer: Timer?
    
    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
                              styleMask: [.titled, .fullSizeContentView],
                              backing: .buffered,
                              defer: false)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor.windowBackgroundColor
        
        super.init(window: window)
        window.center()
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        guard let window = window, let contentView = window.contentView else { return }
        
        // 视觉效果背景
        let visualEffect = NSVisualEffectView(frame: contentView.bounds)
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.material = .underWindowBackground
        contentView.addSubview(visualEffect)
        
        stackView = NSStackView(frame: contentView.bounds.insetBy(dx: 40, dy: 40))
        stackView.autoresizingMask = [.width, .height]
        stackView.orientation = .vertical
        stackView.spacing = 20
        stackView.alignment = .centerX
        stackView.distribution = .gravityAreas
        
        contentView.addSubview(stackView)
        
        showPage(0)
    }
    
    private func showPage(_ index: Int) {
        // 停止之前的定时器
        permissionRefreshTimer?.invalidate()
        permissionRefreshTimer = nil
        
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        switch index {
        case 0:
            let title = createLabel("欢迎使用 Tail Input", size: 24, weight: .bold)
            let desc = createLabel("极致顺滑的 macOS 智能输入法切换工具。\n自动感知应用状态，让输入不再断档。", size: 14)
            desc.alignment = .center
            
            let btn = createButton("开始设置", action: #selector(nextPage))
            
            stackView.addArrangedSubview(title)
            stackView.addArrangedSubview(desc)
            stackView.setCustomSpacing(40, after: desc)
            stackView.addArrangedSubview(btn)
            
        case 1:
            let title = createLabel("开机自启动", size: 20, weight: .semibold)
            let desc = createLabel("建议开启此项，确保应用时刻为您守护切换状态。", size: 13)
            
            let statusLabel = createLabel(SMAppService.mainApp.status == .enabled ? "当前状态：已开启" : "当前状态：未开启", size: 12)
            statusLabel.textColor = .secondaryLabelColor
            
            let btn = createButton("一键开启自启", action: #selector(toggleLaunchAtLogin))
            let nextBtn = createButton("下一步", action: #selector(nextPage))
            nextBtn.bezelStyle = .recessed
            
            stackView.addArrangedSubview(title)
            stackView.addArrangedSubview(desc)
            stackView.addArrangedSubview(statusLabel)
            stackView.addArrangedSubview(btn)
            stackView.addArrangedSubview(nextBtn)
            
        case 2:
            let title = createLabel("辅助功能权限", size: 20, weight: .semibold)
            let desc = createLabel("授予辅助功能权限可以让应用在复杂窗口\n环境中更精准地感应应用切换。", size: 13)
            desc.alignment = .center
            
            let isTrusted = AccessibilityManager.shared.refreshStatus()
            let statusLabel = createLabel(isTrusted ? "✅ 已获得辅助功能权限" : "⚠️ 尚未获取权限（点击下方按钮授权）", size: 12)
            statusLabel.tag = 1001 // 标记以便定时器刷新
            
            let btn = createButton("打开系统设置授权", action: #selector(openPermissions))
            if isTrusted {
                btn.isEnabled = false
                btn.title = "已授权 ✓"
            }
            btn.tag = 1002
            
            let finishBtn = createButton("完成并进入菜单栏", action: #selector(finish))
            finishBtn.keyEquivalent = "\r"
            
            stackView.addArrangedSubview(title)
            stackView.addArrangedSubview(desc)
            stackView.addArrangedSubview(statusLabel)
            stackView.addArrangedSubview(btn)
            stackView.setCustomSpacing(30, after: btn)
            stackView.addArrangedSubview(finishBtn)
            
            // ── 每 2 秒自动刷新权限状态 ──
            permissionRefreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                guard let self = self, self.currentPage == 2 else { return }
                let granted = AccessibilityManager.shared.refreshStatus()
                // 找到标记的控件并更新
                for view in self.stackView.arrangedSubviews {
                    if let label = view as? NSTextField, label.tag == 1001 {
                        label.stringValue = granted ? "✅ 已获得辅助功能权限" : "⚠️ 尚未获取权限（点击下方按钮授权）"
                    }
                    if let button = view as? NSButton, button.tag == 1002 {
                        if granted {
                            button.isEnabled = false
                            button.title = "已授权 ✓"
                        } else {
                            button.isEnabled = true
                            button.title = "打开系统设置授权"
                        }
                    }
                }
            }
            
        default:
            break
        }
    }
    
    private func createLabel(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.isEditable = false
        label.isSelectable = false
        label.alignment = .center
        return label
    }
    
    private func createButton(_ title: String, action: Selector) -> NSButton {
        let btn = NSButton(title: title, target: self, action: action)
        btn.bezelStyle = .rounded
        btn.controlSize = .large
        return btn
    }
    
    @objc private func nextPage() {
        currentPage += 1
        showPage(currentPage)
    }
    
    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
            showPage(1) // 刷新状态
        } catch {
            let alert = NSAlert()
            alert.messageText = "设置失败"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
    
    @objc private func openPermissions() {
        AccessibilityManager.shared.openAccessibilitySettings()
    }
    
    @objc private func finish() {
        permissionRefreshTimer?.invalidate()
        permissionRefreshTimer = nil
        UserDefaults.standard.set(true, forKey: "HasSeenWelcomePagev2")
        window?.close()
    }
}
