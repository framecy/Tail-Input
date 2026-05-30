import Cocoa

enum TCCPermission: String {
    case accessibility    = "Privacy_Accessibility"
    case inputMonitoring  = "Privacy_ListenEvent"
    case automation       = "Privacy_Automation"
    case screenRecording  = "Privacy_ScreenCapture"
    case fullDiskAccess   = "Privacy_AllFiles"
}

final class TCCManager {
    private let logger = TILogger(category: "TCCManager")

    // MARK: - osascript 打开隐私面板

    /// 使用 AppleScript 打开系统设置对应隐私面板，失败时回退到 URL scheme
    @discardableResult
    static func openPrivacyPane(_ permission: TCCPermission) -> Bool {
        // 优先使用 AppleScript — 可以激活 System Settings 再导航
        if #available(macOS 15, *) {
            let script = """
            tell application "System Settings"
                activate
            end tell
            """
            let process = Process()
            process.launchPath = "/usr/bin/osascript"
            process.arguments = ["-e", script]
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                // fall through to URL scheme
            }
            // Sequoia+ URL scheme
            let url = "x-apple.systempreferences:com.apple.settings.Privacy.\(permission.rawValue)"
            if let nsurl = URL(string: url) {
                NSWorkspace.shared.open(nsurl)
                return true
            }
            return false
        }

        if #available(macOS 14, *) {
            // Sonoma
            let script = """
            tell application "System Settings"
                activate
                reveal pane id "com.apple.settings.Privacy.\(permission.rawValue)"
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

        // macOS 13 Ventura
        let url = "x-apple.systempreferences:com.apple.preference.security?\(permission.rawValue)"
        if let nsurl = URL(string: url) {
            NSWorkspace.shared.open(nsurl)
            return true
        }
        return false
    }

    // MARK: - 触发授权弹窗

    /// 通过 osascript 触发 AX 弹窗（让 App 出现在系统设置列表中）
    @discardableResult
    static func triggerAccessibilityPrompt() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        return true
    }

    /// 尝试触发 Input Monitoring 弹窗
    @discardableResult
    static func triggerInputMonitoringPrompt() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        )
        if let tap = tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        return tap != nil
    }

    // MARK: - 全自动授权流程

    /// 触发弹窗 → 打开隐私面板 → 高速轮询等待授权
    static func guidedAuthorizationFlow(
        for permission: TCCPermission,
        onGranted: @escaping () -> Void
    ) {
        let manager = AccessibilityManager.shared

        // Step 1: 触发 TCC 弹窗（让 App 出现在系统设置列表）
        switch permission {
        case .accessibility:
            triggerAccessibilityPrompt()
        case .inputMonitoring:
            triggerInputMonitoringPrompt()
        default:
            break
        }

        // Step 2: 短暂延迟后打开系统设置面板
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

    // MARK: - Input Monitoring 检测

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

    // MARK: - TCC 诊断

    static func diagnoseAll() -> [TCCPermission: Bool] {
        [
            .accessibility: AXIsProcessTrusted(),
            .inputMonitoring: checkInputMonitoring(),
        ]
    }

    // MARK: - TCC Reset

    @discardableResult
    static func resetPermission(_ permission: TCCPermission) -> Bool {
        guard let bundleId = Bundle.main.bundleIdentifier else { return false }
        let tccKey: String
        switch permission {
        case .inputMonitoring: tccKey = "ListenEvent"
        case .accessibility:   tccKey = "Accessibility"
        default: return false
        }
        let task = Process()
        task.launchPath = "/usr/bin/tccutil"
        task.arguments = ["reset", tccKey, bundleId]
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
}
