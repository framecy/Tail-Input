import Cocoa

enum TCCPermission: String {
    case accessibility = "Privacy_Accessibility"
    case inputMonitoring = "Privacy_ListenEvent"
    case automation = "Privacy_Automation"
    case screenRecording = "Privacy_ScreenCapture"
    case fullDiskAccess = "Privacy_AllFiles"
}

final class TCCManager {
    private let logger = TILogger(category: "TCCManager")

    // MARK: - osascript 系统设置导航

    /// 使用 AppleScript 直接打开指定隐私面板
    @discardableResult
    static func openPrivacyPane(_ permission: TCCPermission) -> Bool {
        let script: String
        if #available(macOS 15, *) {
            script = """
            tell application "System Settings"
                activate
                delay 0.3
            end tell
            do shell script "open x-apple.systempreferences:com.apple.settings.Privacy.\(permission.rawValue)"
            """
        } else if #available(macOS 14, *) {
            script = """
            tell application "System Settings"
                activate
                reveal pane id "com.apple.settings.Privacy.\(permission.rawValue)"
            end tell
            """
        } else {
            // macOS 13 Ventura
            let url = "x-apple.systempreferences:com.apple.preference.security?\(permission.rawValue)"
            if let nsurl = URL(string: url) {
                NSWorkspace.shared.open(nsurl)
                return true
            }
            return false
        }

        let process = Process()
        process.launchPath = "/usr/bin/osascript"
        process.arguments = ["-e", script]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// 使用 osascript 触发系统授权弹窗
    @discardableResult
    static func triggerAccessibilityPrompt() -> Bool {
        let script = """
        tell application "System Events"
            try
                set _ to UI elements of process "Finder"
            end try
        end tell
        """
        let process = Process()
        process.launchPath = "/usr/bin/osascript"
        process.arguments = ["-e", script]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// 全自动授权流程：触发弹窗 + 打开隐私面板 + 持续检测授权
    static func guidedAuthorizationFlow(for permission: TCCPermission, onGranted: @escaping () -> Void) {
        let manager = AccessibilityManager.shared

        // Step 1: 触发系统弹窗（让 App 出现在 TCC 列表中）
        triggerAccessibilityPrompt()

        // Step 2: 打开系统设置对应面板
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            openPrivacyPane(permission)
        }

        // Step 3: 高速轮询等待授权
        manager.onPermissionChanged = { [weak manager] granted in
            guard granted else { return }
            DispatchQueue.main.async { onGranted() }
            manager?.onPermissionChanged = nil
            manager?.startMonitoring(intervalSeconds: 5)
        }
        manager.startMonitoring(intervalSeconds: 1)
    }

    // MARK: - TCC 诊断

    /// 诊断当前进程所有 TCC 权限状态
    static func diagnoseAll() -> [TCCPermission: Bool] {
        var result: [TCCPermission: Bool] = [:]
        result[.accessibility] = AXIsProcessTrusted()
        result[.inputMonitoring] = checkInputMonitoring()
        return result
    }

    /// 检测 Input Monitoring 权限
    static func checkInputMonitoring() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        ) else {
            return false
        }
        CGEvent.tapEnable(tap: tap, enable: false)
        return true
    }

    /// reset 指定权限的 TCC 条目（用于测试和修复）
    @discardableResult
    static func resetPermission(_ permission: TCCPermission) -> Bool {
        guard let bundleId = Bundle.main.bundleIdentifier else { return false }
        let task = Process()
        task.launchPath = "/usr/bin/tccutil"
        task.arguments = ["reset", permission == .inputMonitoring ? "ListenEvent" : "Accessibility", bundleId]
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
}
