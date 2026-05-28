import Cocoa

class AppObserver: NSObject {
    static let shared = AppObserver()
    
    var onAppActivated: ((String, String?) -> Void)?
    var isEnabled: Bool = true {
        didSet {
            // 如果刚刚开启，顺便对当前最前台的应用执行一次策略
            if isEnabled {
                if let activeApp = NSWorkspace.shared.frontmostApplication,
                   let bundleId = activeApp.bundleIdentifier {
                    onAppActivated?(bundleId, activeApp.localizedName)
                }
            }
        }
    }
    
    // ── 性能优化：跳过同 App 重复激活 & coalesce 快速切换 ──
    private var lastActivatedBundleId: String?
    private var activateWorkItem: DispatchWorkItem?

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
        // 这些进程短暂获取焦点时不应被视为真实的前台应用切换，
        // 否则在焦点交还给原应用时，会错误地重新触发原应用的策略，覆盖用户在此期间的手动切换。
        let lowerID = identifier.lowercased()
        let isIgnored = Self.ignoredBundleIDs.contains(identifier) ||
                        lowerID.contains(".inputmethod.") ||
                        lowerID.contains("sogou") ||
                        lowerID.contains("baiduim") ||
                        lowerID.contains("rime") ||
                        lowerID.contains("squirrel") ||
                        lowerID.contains("wetype") ||
                        identifier == "com.framed.TailInput"
        guard !isIgnored else { return }

        // ── 跳过同 App 重复激活事件 ──
        guard identifier != lastActivatedBundleId else { return }
        lastActivatedBundleId = identifier

        // ── Coalesce 快速 Cmd+Tab 切换：取消之前未执行的回调，只保留最后一次 ──
        // 8ms 只跨过同一轮 run loop 的连发激活事件，降低前台应用切换感知延迟
        activateWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.onAppActivated?(identifier, app.localizedName)
        }
        activateWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.008, execute: work)
    }
}
