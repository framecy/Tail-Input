import Cocoa

class HUDWindowController: NSWindowController {

    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var hideWorkItem: DispatchWorkItem?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 170, height: 64),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.alphaValue = 0.0

        super.init(window: window)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        // 使用普通 View+CALayer 替代 NSVisualEffectView，
        // 后者在系统输入法切换时同时开启动画会导致 WindowServer 渲染卡顿
        let container = NSView(frame: contentView.bounds)
        container.autoresizingMask = [.width, .height]
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        container.layer?.cornerRadius = 14
        container.layer?.masksToBounds = true
        contentView.addSubview(container)

        // ── 图标 ──
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.contentTintColor = .white

        // ── 文字 ──
        label.font = NSFont.systemFont(ofSize: 18, weight: .regular)
        label.textColor = .white
        label.alignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false

        // ── 水平 StackView：图标 + 文字居中排列 ──
        let stack = NSStackView(views: [iconView, label])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),

            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
    }

    // MARK: - 定位

    private func getActiveScreen() -> NSScreen {
        let mouseLoc = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first!
    }

    // MARK: - 显示

    func showHUD(isChinese: Bool) {
        // 更新图标
        let symbolName = isChinese ? "character.textbox" : "keyboard"
        // semibold 在黑色背景上比 regular 更清晰
        let config = NSImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)

        // 更新文字
        label.stringValue = isChinese ? "简体中文" : "English"

        hideWorkItem?.cancel()

        // ── 性能优化：如果 HUD 已可见，只更新内容和重置隐藏计时器，跳过淡入动画 ──
        if window?.alphaValue == 1.0 {
            resetHideTimer()
            return
        }

        // 重新计算并设置窗口位置到当前激活屏幕的右上角
        let screenRect = getActiveScreen().visibleFrame
        let hudWidth: CGFloat = 170
        let hudHeight: CGFloat = 64
        let margin: CGFloat = 20
        let hudRect = NSRect(
            x: screenRect.maxX - hudWidth - margin,
            y: screenRect.maxY - hudHeight - margin,
            width: hudWidth,
            height: hudHeight
        )
        window?.setFrame(hudRect, display: true)
        window?.orderFront(nil)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12   // 从 0.15 降至 0.12，出现更敏捷
            self.window?.animator().alphaValue = 1.0
        }, completionHandler: { [weak self] in
            self?.resetHideTimer()
        })
    }

    private func resetHideTimer() {
        hideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.hideHUD()
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    private func hideHUD() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.5
            self.window?.animator().alphaValue = 0.0
        }, completionHandler: nil)
    }
}
