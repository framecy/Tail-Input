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
    
    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        
        // 初始应用
        if let activeApp = NSWorkspace.shared.frontmostApplication,
           let bundleId = activeApp.bundleIdentifier {
            lastActivatedBundleId = bundleId
            onAppActivated?(bundleId, activeApp.localizedName)
        }
    }
    
    @objc private func appDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleIdentifier = app.bundleIdentifier else {
            return
        }
        
        // ── 跳过同 App 重复激活事件 ──
        guard bundleIdentifier != lastActivatedBundleId else { return }
        lastActivatedBundleId = bundleIdentifier
        
        // ── Coalesce 快速 Cmd+Tab 切换：取消之前未执行的回调，只保留最后一次 ──
        // 8ms 只跨过同一轮 run loop 的连发激活事件，降低前台应用切换感知延迟
        activateWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.onAppActivated?(bundleIdentifier, app.localizedName)
        }
        activateWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.008, execute: work)
    }
}
