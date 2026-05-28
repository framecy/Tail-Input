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
    private var iconWidthConstraint:  NSLayoutConstraint?
    private var iconHeightConstraint: NSLayoutConstraint?

    // ── 持久化 key ──
    private static let kPositionKey    = "HUDPosition"
    private static let kScreenIndexKey = "HUDScreenIndex"
    private static let kSizePresetKey  = "HUDSizePreset"   // 0=小, 1=中, 2=大
    private static let kShowIconKey    = "HUDShowIcon"
    private static let kTextStyleKey   = "HUDTextStyle"    // 0=简短, 1=完整

    // ── 尺寸配置 ──
    private struct SizeConfig {
        let hudW: CGFloat; let hudH: CGFloat
        let iconPt: CGFloat; let fontSize: CGFloat; let iconSide: CGFloat
    }
    private static let sizeConfigs: [SizeConfig] = [
        SizeConfig(hudW: 140, hudH: 52,  iconPt: 16, fontSize: 14, iconSide: 18),  // 小
        SizeConfig(hudW: 178, hudH: 66,  iconPt: 22, fontSize: 18, iconSide: 24),  // 中
        SizeConfig(hudW: 220, hudH: 82,  iconPt: 28, fontSize: 22, iconSide: 30),  // 大
    ]
    private var currentSizeConfig: SizeConfig { Self.sizeConfigs[hudSizePreset] }

    // MARK: Preferences

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

    var hudSizePreset: Int {
        get {
            guard UserDefaults.standard.object(forKey: Self.kSizePresetKey) != nil else { return 1 }
            return min(max(UserDefaults.standard.integer(forKey: Self.kSizePresetKey), 0), 2)
        }
        set { UserDefaults.standard.set(min(max(newValue, 0), 2), forKey: Self.kSizePresetKey) }
    }

    var hudShowIcon: Bool {
        get {
            guard UserDefaults.standard.object(forKey: Self.kShowIconKey) != nil else { return true }
            return UserDefaults.standard.bool(forKey: Self.kShowIconKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.kShowIconKey) }
    }

    /// 0 = 简短（中文/英文），1 = 完整（简体中文/English）
    var hudTextStyle: Int {
        get {
            guard UserDefaults.standard.object(forKey: Self.kTextStyleKey) != nil else { return 1 }
            return UserDefaults.standard.integer(forKey: Self.kTextStyleKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.kTextStyleKey) }
    }

    // MARK: Init

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

        let wc = iconView.widthAnchor.constraint(equalToConstant: 24)
        let hc = iconView.heightAnchor.constraint(equalToConstant: 24)
        iconWidthConstraint  = wc
        iconHeightConstraint = hc

        NSLayoutConstraint.activate([
            wc, hc,
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
        let cfg = currentSizeConfig

        // 更新图标可见性与大小
        iconView.isHidden = !hudShowIcon
        if hudShowIcon {
            let symbolName = isChinese ? "character.textbox" : "keyboard"
            let config = NSImage.SymbolConfiguration(pointSize: cfg.iconPt, weight: .semibold)
            iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
            iconWidthConstraint?.constant  = cfg.iconSide
            iconHeightConstraint?.constant = cfg.iconSide
        }

        // 更新文字内容与字号
        if hudTextStyle == 0 {
            label.stringValue = isChinese ? "中文" : "英文"
        } else {
            label.stringValue = isChinese ? "简体中文" : "English"
        }
        label.font = NSFont.systemFont(ofSize: cfg.fontSize, weight: .regular)

        hideWorkItem?.cancel()

        let hudSize = NSSize(width: cfg.hudW, height: cfg.hudH)
        let hudRect = frameForHUD(size: hudSize, position: hudPosition, screen: targetScreen())

        // nearMouse 每次都重新定位；固定位置在 HUD 已可见时只更新位置/尺寸，跳过淡入动画
        if hudPosition != .nearMouse && window?.alphaValue == 1.0 {
            window?.setFrame(hudRect, display: true)
            resetHideTimer()
            return
        }

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
