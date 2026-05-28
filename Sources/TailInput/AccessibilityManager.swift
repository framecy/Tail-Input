import Cocoa
import ApplicationServices

class AccessibilityManager {
    static let shared = AccessibilityManager()
    
    /// 权限状态变更回调（主线程）
    var onPermissionChanged: ((Bool) -> Void)?
    
    /// 当前权限状态（线程安全读取）
    private(set) var isAccessibilityGranted: Bool = false
    
    private var pollTimer: DispatchSourceTimer?
    private let pollQueue = DispatchQueue(label: "com.smartinputswitcher.accessibility-poll", qos: .utility)
    private var pollIntervalSeconds: TimeInterval = 5

    init() {
        // 初始读取一次
        isAccessibilityGranted = AXIsProcessTrusted()
    }

    /// 启动后台轮询。等待授权期间用 1s 间隔快速捕获，常态用 5s 间隔节能。
    func startMonitoring(intervalSeconds: TimeInterval = 5) {
        if pollTimer != nil && intervalSeconds == pollIntervalSeconds { return }
        pollTimer?.cancel()
        pollIntervalSeconds = intervalSeconds

        let timer = DispatchSource.makeTimerSource(queue: pollQueue)
        timer.schedule(deadline: .now() + intervalSeconds, repeating: intervalSeconds)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            let current = AXIsProcessTrusted()
            if current != self.isAccessibilityGranted {
                self.isAccessibilityGranted = current
                DispatchQueue.main.async {
                    self.onPermissionChanged?(current)
                }
            }
        }
        timer.resume()
        pollTimer = timer
    }
    
    /// 停止轮询
    func stopMonitoring() {
        pollTimer?.cancel()
        pollTimer = nil
    }
    
    /// 一键打开系统设置 - 辅助功能权限页面
    func openAccessibilitySettings() {
        // macOS 13+ 使用新的 URL scheme
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// 主动触发系统授权弹窗（仅首次有效）
    func promptForPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// 立即刷新状态（同步）
    func refreshStatus() -> Bool {
        isAccessibilityGranted = AXIsProcessTrusted()
        return isAccessibilityGranted
    }

    /// 清除当前 bundle 的辅助功能 TCC 条目，移除上个版本/旧路径残留的 stale 授权。
    /// 失败时静默，不阻塞后续打开系统设置。
    func resetTCCEntry() {
        guard let bundleId = Bundle.main.bundleIdentifier else { return }
        let task = Process()
        task.launchPath = "/usr/bin/tccutil"
        task.arguments = ["reset", "Accessibility", bundleId]
        do {
            try task.run()
            task.waitUntilExit()
            isAccessibilityGranted = false
            NSLog("[TailInput] tccutil reset Accessibility %@ → exit %d", bundleId, task.terminationStatus)
        } catch {
            NSLog("[TailInput] tccutil reset failed: %@", error.localizedDescription)
        }
    }

    /// 引导授权一次性流程：打开系统设置 → 启动 1s 快速轮询，授权完成后回调一次。
    /// **不**做 tccutil reset —— 多次调用会清掉用户刚授的权造成循环。
    /// 如需清理旧版本残留授权，调用方显式调 resetTCCEntry() 一次即可。
    func requestAndAwaitGrant(onGranted: @escaping () -> Void) {
        // 触发系统注册（让 Tail Input 出现在系统设置列表里）
        promptForPermission()
        openAccessibilitySettings()

        onPermissionChanged = { [weak self] granted in
            guard granted else { return }
            DispatchQueue.main.async { onGranted() }
            self?.onPermissionChanged = nil
            // 授权完成后切回慢轮询节能
            self?.startMonitoring(intervalSeconds: 5)
        }
        startMonitoring(intervalSeconds: 1)
    }
}
