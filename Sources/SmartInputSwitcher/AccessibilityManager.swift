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
    
    init() {
        // 初始读取一次
        isAccessibilityGranted = AXIsProcessTrusted()
    }
    
    /// 启动后台轮询（每 5 秒检查一次权限状态）
    func startMonitoring() {
        guard pollTimer == nil else { return }
        
        let timer = DispatchSource.makeTimerSource(queue: pollQueue)
        timer.schedule(deadline: .now() + 5, repeating: 5)
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
}
