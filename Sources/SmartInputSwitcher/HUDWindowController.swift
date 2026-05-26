import Cocoa

// MARK: - HUD 显示位置

enum HUDPosition: Int, CaseIterable {
    case topLeft      = 0
    case topCenter    = 1
    case topRight     = 2   // 默认
    case middleLeft   = 3
    case middleCenter = 4
    case middleRight  = 5
    case bottomLeft   = 6
    case bottomCenter = 7
    case bottomRight  = 8
    case nearMouse    = 9   // 鼠标附近
}

// MARK: - HUDWindowController

class HUDWindowController: NSWindowController {

    private let iconView = NSImageView()
    private let label    = NSTextField(labelWithString: "")
    private var hideWorkItem: DispatchWorkItem?

    // ── 持久化位置偏好 ──
    private static let kPositionKey    = "HUDPosition"
    private static let kScreenIndexKey = "HUDScreenIndex"

    /// 当前选中的 HUD 位置，持久化到 UserDefaults
    var hudPosition: HUDPosition {
        get {
            let raw = UserDefaults.standard.integer(forKey: Self.kPositionKey)
            return HUDPosition(rawValue: raw) ?? .topRight
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Self.kPositionKey) }
    }

    /// -1 = 跟随焦点屏幕（默认）；0+ = NSScreen.screens 固定索引
    var hudScreenIndex: Int {
        get {
            guard UserDefaults.standard.object(forKey: Self.kScreenIndexKey) != nil else { return -1 }
            return UserDefaults.standard.integer(forKey: Self.kScreenIndexKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.kScreenIndexKey) }
    }

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 178, height: 66),
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

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        // Plain CALayer instead of NSVisualEffectView — avoids WindowServer stutter
        let container = NSView(frame: contentView.bounds)
        container.autoresizingMask = [.width, .height]
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.76).cgColor
        container.layer?.cornerRadius = 18
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        contentView.addSubview(container)

        // Subtle top-edge shine
        let shine = CALayer()
        shine.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        shine.frame = CGRect(x: 1, y: container.bounds.height - 1,
                             width: container.bounds.width - 2, height: 1)
        shine.autoresizingMask = [.layerWidthSizable, .layerMinYMargin]
        container.layer?.addSublayer(shine)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.contentTintColor = .white

        label.font = NSFont.systemFont(ofSize: 18, weight: .regular)
        label.textColor = .white
        label.alignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false

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

    // MARK: - 屏幕选择

    private func targetScreen() -> NSScreen {
        if hudScreenIndex >= 0 {
            let screens = NSScreen.screens
            if hudScreenIndex < screens.count { return screens[hudScreenIndex] }
            return NSScreen.main ?? screens.first!
        }
        // 跟随焦点：鼠标所在屏幕
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first!
    }

    // MARK: - 位置计算

    private func frameForHUD(size: NSSize, position: HUDPosition, screen: NSScreen) -> NSRect {
        let sf     = screen.visibleFrame
        let margin: CGFloat = 24
        let w = size.width
        let h = size.height
        var x: CGFloat = 0
        var y: CGFloat = 0

        switch position {
        case .topLeft:
            x = sf.minX + margin;      y = sf.maxY - h - margin
        case .topCenter:
            x = sf.midX - w / 2;      y = sf.maxY - h - margin
        case .topRight:
            x = sf.maxX - w - margin;  y = sf.maxY - h - margin
        case .middleLeft:
            x = sf.minX + margin;      y = sf.midY - h / 2
        case .middleCenter:
            x = sf.midX - w / 2;      y = sf.midY - h / 2
        case .middleRight:
            x = sf.maxX - w - margin;  y = sf.midY - h / 2
        case .bottomLeft:
            x = sf.minX + margin;      y = sf.minY + margin
        case .bottomCenter:
            x = sf.midX - w / 2;      y = sf.minY + margin
        case .bottomRight:
            x = sf.maxX - w - margin;  y = sf.minY + margin
        case .nearMouse:
            let mouse = NSEvent.mouseLocation
            x = min(max(mouse.x + 16, sf.minX + margin), sf.maxX - w - margin)
            y = min(max(mouse.y + 12, sf.minY + margin), sf.maxY - h - margin)
        }

        return NSRect(x: x, y: y, width: w, height: h)
    }

    // MARK: - 显示

    func showHUD(isChinese: Bool) {
        let symbolName = isChinese ? "character.textbox" : "keyboard"
        let config = NSImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        label.stringValue = isChinese ? "简体中文" : "English"

        hideWorkItem?.cancel()

        // nearMouse 每次都重新定位；固定位置在 HUD 已可见时跳过淡入动画
        if hudPosition != .nearMouse && window?.alphaValue == 1.0 {
            resetHideTimer()
            return
        }

        let hudSize = NSSize(width: 178, height: 66)
        let hudRect = frameForHUD(size: hudSize, position: hudPosition, screen: targetScreen())
        window?.setFrame(hudRect, display: true)
        window?.orderFront(nil)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            self.window?.animator().alphaValue = 1.0
        }, completionHandler: { [weak self] in
            self?.resetHideTimer()
        })
    }

    private func resetHideTimer() {
        hideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.hideHUD() }
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
