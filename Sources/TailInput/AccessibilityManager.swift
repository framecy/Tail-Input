import Cocoa
import ApplicationServices

class AccessibilityManager {
    static let shared = AccessibilityManager()

    var onPermissionChanged: ((Bool) -> Void)?

    private(set) var isAccessibilityGranted: Bool = false

    private var pollTimer: DispatchSourceTimer?
    private let pollQueue = DispatchQueue(label: "com.smartinputswitcher.accessibility-poll", qos: .utility)
    private var pollIntervalSeconds: TimeInterval = 5

    init() {
        isAccessibilityGranted = AXIsProcessTrusted()
    }

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

    func stopMonitoring() {
        pollTimer?.cancel()
        pollTimer = nil
    }

    /// 使用 osascript 打开辅助功能面板（委托 TCCManager）
    func openAccessibilitySettings() {
        TCCManager.openPrivacyPane(.accessibility)
    }

    func promptForPermission() {
        TCCManager.triggerAccessibilityPrompt()
    }

    func refreshStatus() -> Bool {
        isAccessibilityGranted = AXIsProcessTrusted()
        return isAccessibilityGranted
    }

    func resetTCCEntry() {
        _ = TCCManager.resetPermission(.accessibility)
        isAccessibilityGranted = false
    }

    /// 全自动授权流程：osascript 弹窗 → 打开面板 → 高速轮询 → 授权完成回调
    func requestAndAwaitGrant(onGranted: @escaping () -> Void) {
        TCCManager.guidedAuthorizationFlow(for: .accessibility, onGranted: onGranted)
    }
}
