import Cocoa

class AppObserver: NSObject {
    static let shared = AppObserver()

    var onAppActivated: ((String, String?) -> Void)?
    var onAppWillChange: ((String) -> Void)?  // 离开 App 前回调

    var isEnabled: Bool = true {
        didSet {
            if isEnabled {
                activateWorkItem?.cancel()
                activateWorkItem = nil
                if let activeApp = NSWorkspace.shared.frontmostApplication,
                   let bundleId = Self.identifier(for: activeApp) {
                    onAppActivated?(bundleId, activeApp.localizedName)
                }
            }
        }
    }

    /// 当前前台 App 的 bundleID（nil 表示未知/系统进程）
    private(set) var currentBundleID: String?

    // ── 性能优化：去重 + coalesce + bounce-back guard ──
    private var lastActivatedBundleId: String?
    private var previousBundleID: String?            // 上一个不同 App 的 ID
    private var lastActivationTime: TimeInterval = 0 // 上次激活时间
    private var activateWorkItem: DispatchWorkItem?

    /// 回弹窗口：同一 App 在离开后 < bounceBackWindow 秒内重新激活，视为系统覆盖层干扰，不重新执行策略。
    /// 这防止系统对话框/Menu Bar 短暂抢焦点后交还时覆盖用户的手动切换。
    private let bounceBackWindow: TimeInterval = 0.2

    /// Coalesce 窗口：快速 Cmd+Tab 切换时合并多次激活事件，仅保留最后一次。
    private let coalesceWindow: TimeInterval = 0.015

    /// 取 NSRunningApplication 的稳定标识：优先 CFBundleIdentifier，
    /// 缺失时回退到 `path:<bundle 绝对路径>`（与 AppPicker 扫描格式一致）。
    private static func identifier(for app: NSRunningApplication) -> String? {
        if let bid = app.bundleIdentifier, !bid.isEmpty { return bid }
        if let path = app.bundleURL?.path { return "path:\(path)" }
        return nil
    }

    // 忽略的系统覆盖层级应用（菜单栏、控制中心、输入法切换 HUD 等）。
    // 这些应用短暂获取焦点时不应被视为前台应用切换，否则在它们关闭、焦点交还给原应用时，
    // 会错误地触发原应用的策略，覆盖用户在此期间的手动切换（如点击菜单栏切换中英文）。
    private static let ignoredBundleIDs: Set<String> = [
        "com.apple.systemuiserver",
        "com.apple.TextInputUI.Menu",
        "com.apple.HIToolbox",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.WindowManager",
        "com.apple.loginwindow",
        "com.apple.dock",
        "com.apple.AppSSOAgent",
        "com.apple.SecurityAgent"
    ]

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        // 初始应用
        if let activeApp = NSWorkspace.shared.frontmostApplication,
           let identifier = Self.identifier(for: activeApp) {
            lastActivatedBundleId = identifier
            onAppActivated?(identifier, activeApp.localizedName)
        }
    }
    
    @objc private func appDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let identifier = Self.identifier(for: app) else {
            return
        }

        // ── 忽略系统覆盖层与输入法后台进程 ──
        guard app.activationPolicy == .regular else { return }
        let lowerID = identifier.lowercased()
        let isIgnored = Self.ignoredBundleIDs.contains(identifier) ||
                        lowerID.contains(".inputmethod.") ||
                        lowerID.contains("sogou") ||
                        lowerID.contains("baiduim") ||
                        lowerID.contains("rime") ||
                        lowerID.contains("squirrel") ||
                        lowerID.contains("wetype") ||
                        identifier == "com.framed.TailInput"

        // CJKVFixWindow 自激活用于强制提交输入源切换，应忽略
        let isSelfActivation = CJKVFixWindow.isTemporaryWindowActivation(app)
        guard !isIgnored, !isSelfActivation else { return }

        // ── 跳过同 App 重复激活事件 ──
        guard identifier != lastActivatedBundleId else { return }

        let now = ProcessInfo.processInfo.systemUptime

        // ── Bounce-back guard：离开后 < 200ms 内回到同一个 App，视为系统覆盖层干扰 ──
        // 例如：Menu Bar 下拉 → 关闭 → 焦点回到原 App。
        // 此时跳过 strategy re-apply，保留用户的输入法状态。
        if let prev = previousBundleID,
           identifier == prev,
           now - lastActivationTime < bounceBackWindow {
            lastActivatedBundleId = identifier
            currentBundleID = identifier
            return
        }

        // ── 记录上一个不同 App，用于离开时保存输入源 ──
        if let current = currentBundleID, current != identifier {
            onAppWillChange?(current)
            previousBundleID = current
        }

        lastActivatedBundleId = identifier
        currentBundleID = identifier
        lastActivationTime = now

        // ── flatMapLatest 等效：取消之前未执行的回调，只保留最后一次 ──
        activateWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.onAppActivated?(identifier, app.localizedName)
        }
        activateWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + coalesceWindow, execute: work)
    }
}
