import Cocoa
import Carbon
import ApplicationServices

enum AppInputStrategy: Int, Codable {
    case globalDefault = 0 // 遵循全局默认（强切英文）
    case forceEnglish = 1
    case forceChinese = 2
    case keepCurrent = 3
}

class InputMethodManager: NSObject {
    static let shared = InputMethodManager()

    // ── 当前输入法状态缓存（布尔值，O(1) 读取）──
    private var cachedInputSourceID: String?
    private var cachedChineseInputSourceID: String?
    private var cachedEnglishInputSourceID: String?
    var cachedIsChinese: Bool = false   // internal：AppDelegate / HUD 直接读取

    // ── CapsLock 切换校验：避免系统状态机与乐观缓存不同步 ──
    private var pendingCapsLockTarget: Bool?
    private var capsLockVerificationWorkItem: DispatchWorkItem?
    private var lastDeliveredInputState: Bool?

    // ── 当前应用信息 ──
    var currentAppBundleIdentifier: String?
    var currentAppName: String?

    // ── 回调 ──
    var onInputMethodChanged: ((Bool) -> Void)?
    var onAppChanged: (() -> Void)?

    // ── CapsLock 兼容模式 ──
    private static let kUseCapsLockSimulationKey = "UseCapsLockSimulation"
    var useCapsLockSimulation: Bool {
        get { UserDefaults.standard.bool(forKey: Self.kUseCapsLockSimulationKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.kUseCapsLockSimulationKey) }
    }

    override init() {
        super.init()
        refreshCachedInputSource()
        setupObserver()
    }

    // MARK: - 中英文 ID 识别

    private static let appleChineseInputSourceIDs: Set<String> = [
        "com.apple.inputmethod.scim.itabc",
        "com.apple.inputmethod.scim.pinyin",
        "com.apple.inputmethod.scim.wbx",
        "com.apple.inputmethod.tcim.pinyin",
        "com.apple.inputmethod.tcim.zhuyin",
        "com.apple.inputmethod.tcim.cangjie",
    ]

    private static let chineseIDPrefixes = [
        "com.apple.inputmethod.scim.",
        "com.apple.inputmethod.tcim.",
    ]

    private static let chineseKeywords = [
        "chinese", "pinyin", "sogou", "wubi", "baidu", "shuangpin",
        "rime", "squirrel", "cangjie", "zhuyin", "stroke", "itabc",
    ]

    private static let chineseNameKeywords = [
        "拼音", "中文", "简体", "繁体", "五笔", "搜狗", "百度", "双拼",
        "pinyin", "chinese", "wubi", "shuangpin", "cangjie", "zhuyin",
    ]

    static func isChineseID(_ lowerId: String) -> Bool {
        if appleChineseInputSourceIDs.contains(lowerId) {
            return true
        }
        if chineseIDPrefixes.contains(where: { lowerId.hasPrefix($0) }) {
            return true
        }
        return chineseKeywords.contains { lowerId.contains($0) }
    }

    static func isEnglishLayoutID(_ lowerId: String) -> Bool {
        guard lowerId.hasPrefix("com.apple.keylayout.") else { return false }
        return !isChineseID(lowerId)
    }

    // MARK: - 纯函数：输入法状态判断（internal 以支持单元测试）

    /// 根据 TIS source ID 和 mode ID 判断最终的中英文状态。
    /// modeID 含 "roman" 时，即使 sourceID 被识别为中文，也判定为英文（in-source 英文模式）。
    static func detectInputMethodState(sourceID: String, modeID: String?) -> Bool {
        let lower = sourceID.lowercased()
        var isChinese = isChineseID(lower)
        if isChinese, let mode = modeID, mode.lowercased().contains("roman") {
            isChinese = false
        }
        return isChinese
    }

    /// 从本地化名称判断是否为中文输入法（sourceID 识别失败时的兜底）。
    static func detectChineseByLocalizedName(_ name: String) -> Bool {
        let lowerName = name.lowercased()
        return chineseNameKeywords.contains { name.contains($0) || lowerName.contains($0) }
    }

    // MARK: - 当前输入法状态

    @discardableResult
    private func refreshCachedInputSource() -> Bool {
        guard let src = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            cachedInputSourceID = nil
            cachedIsChinese = false
            return false
        }

        let id: String? = {
            guard let ptr = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) else { return nil }
            return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
        }()
        cachedInputSourceID = id

        let lower = id?.lowercased() ?? ""
        var isChinese = Self.isChineseID(lower)

        if !isChinese, !Self.isEnglishLayoutID(lower),
           let ptr = TISGetInputSourceProperty(src, kTISPropertyLocalizedName) {
            let name = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
            let lowerName = name.lowercased()
            isChinese = Self.chineseNameKeywords.contains {
                name.contains($0) || lowerName.contains($0)
            }
        }

        // macOS 26：委托 detectInputMethodState 处理 in-source 英文模式（含 modeID 检测）
        let modeID: String? = {
            guard let ptr = TISGetInputSourceProperty(src, kTISPropertyInputModeID) else { return nil }
            return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
        }()
        isChinese = Self.detectInputMethodState(sourceID: id ?? "", modeID: modeID)

        cachedIsChinese = isChinese
        if isChinese {
            cachedChineseInputSourceID = id
        } else if Self.isEnglishLayoutID(lower) {
            cachedEnglishInputSourceID = id
        }
        return isChinese
    }

    // MARK: - 公开切换入口

    func switchToEnglish() { switchTo(chinese: false) }
    func switchToChinese() { switchTo(chinese: true) }

    private func switchTo(chinese: Bool) {
        refreshCachedInputSource()
        guard cachedIsChinese != chinese else { return }

        if useCapsLockSimulation && AXIsProcessTrusted() {
            // 乐观更新：CapsLock 事件异步生效，提前写入目标状态让 UI 立即响应
            switchViaCapsLock(chinese: chinese)
            return
        }
        switchViaTIS(chinese: chinese)
    }

    // MARK: - TIS 切换（每次获取新鲜列表，避免缓存 TISInputSource 指针悬空）

    private func switchViaTIS(chinese: Bool) {
        if let cachedID = chinese ? cachedChineseInputSourceID : cachedEnglishInputSourceID,
           selectCachedInputSource(id: cachedID, chinese: chinese) {
            return
        }

        // 注意：所有对 rawPtr 的使用必须在 cfList 存活期间完成，
        // 不可将 rawPtr 存出函数范围，否则 CFArray 释放后指针悬空。
        let filter = [kTISPropertyInputSourceIsSelectCapable as String: true] as CFDictionary
        guard let cfList = TISCreateInputSourceList(filter, false)?.takeRetainedValue() else {
            NSLog("[TailInput] TISCreateInputSourceList returned nil")
            return
        }

        let count = CFArrayGetCount(cfList)

        // 两级优先级：精确匹配 > 同类兜底
        var primaryPtr: UnsafeRawPointer? = nil
        var primaryID: String?
        var fallbackPtr: UnsafeRawPointer? = nil
        var fallbackID: String?

        for i in 0..<count {
            guard let rawPtr = CFArrayGetValueAtIndex(cfList, i) else { continue }
            let source = Unmanaged<TISInputSource>.fromOpaque(rawPtr).takeUnretainedValue()

            guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { continue }
            let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
            let lower = id.lowercased()

            if chinese {
                // Apple Pinyin 是最优中文源
                if lower == "com.apple.inputmethod.scim.itabc" ||
                   lower == "com.apple.inputmethod.scim.pinyin" {
                    primaryPtr = rawPtr; primaryID = id; break
                }
                if Self.isChineseID(lower), fallbackPtr == nil {
                    fallbackPtr = rawPtr; fallbackID = id
                }
            } else {
                // 严格 ABC 是最优英文源
                if lower == "com.apple.keylayout.abc" {
                    primaryPtr = rawPtr; primaryID = id; break
                }
                if Self.isEnglishLayoutID(lower), fallbackPtr == nil {
                    fallbackPtr = rawPtr; fallbackID = id
                }
            }
        }

        guard let ptr = primaryPtr ?? fallbackPtr else {
            NSLog("[TailInput] No \(chinese ? "Chinese" : "English") source found in \(count) sources")
            return
        }
        let selectedID = primaryID ?? fallbackID

        // TISSelectInputSource 调用必须在 cfList 存活期间（此时 rawPtr 仍有效）
        let target = Unmanaged<TISInputSource>.fromOpaque(ptr).takeUnretainedValue()
        let result = selectInputSource(target, id: selectedID, chinese: chinese)
        if result != noErr {
            NSLog("[TailInput] TISSelectInputSource failed: %d", result)
        }
        // cfList 在此处释放（函数结束）
    }

    private func selectCachedInputSource(id: String, chinese: Bool) -> Bool {
        let filter = [
            kTISPropertyInputSourceID as String: id,
            kTISPropertyInputSourceIsSelectCapable as String: true,
        ] as CFDictionary

        guard let cfList = TISCreateInputSourceList(filter, false)?.takeRetainedValue(),
              CFArrayGetCount(cfList) > 0,
              let rawPtr = CFArrayGetValueAtIndex(cfList, 0) else {
            clearCachedTargetID(chinese: chinese)
            return false
        }

        let source = Unmanaged<TISInputSource>.fromOpaque(rawPtr).takeUnretainedValue()
        if selectInputSource(source, id: id, chinese: chinese) == noErr {
            return true
        }

        clearCachedTargetID(chinese: chinese)
        return false
    }

    @discardableResult
    private func selectInputSource(_ source: TISInputSource, id: String?, chinese: Bool) -> OSStatus {
        let result = TISSelectInputSource(source)
        if result == noErr {
            // 乐观更新：TISSelectInputSource 是异步生效的，立即 re-read 会拿到旧值。
            // 这里直接写入目标值；TIS 通知到来后 handleInputMethodChange 会用真实值覆盖。
            cachedIsChinese = chinese
            cachedInputSourceID = id
            if chinese {
                cachedChineseInputSourceID = id
            } else {
                cachedEnglishInputSourceID = id
            }
            deliverInputMethodChanged(chinese)
            NSLog("[TailInput] switched to %@", chinese ? "Chinese" : "English")
        }
        return result
    }

    private func clearCachedTargetID(chinese: Bool) {
        if chinese {
            cachedChineseInputSourceID = nil
        } else {
            cachedEnglishInputSourceID = nil
        }
    }

    // MARK: - CapsLock 模拟

    private func switchViaCapsLock(chinese: Bool) {
        pendingCapsLockTarget = chinese
        cachedIsChinese = chinese
        deliverInputMethodChanged(chinese)
        simulateCapsLock()
        scheduleCapsLockVerification(target: chinese, retriesRemaining: 1)
    }

    private func simulateCapsLock() {
        let src = CGEventSource(stateID: .hidSystemState)
        let kVK_CapsLock: CGKeyCode = 0x39
        CGEvent(keyboardEventSource: src, virtualKey: kVK_CapsLock, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: src, virtualKey: kVK_CapsLock, keyDown: false)?.post(tap: .cghidEventTap)
    }

    private func scheduleCapsLockVerification(target: Bool, retriesRemaining: Int) {
        capsLockVerificationWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            self.refreshCachedInputSource()
            if self.cachedIsChinese == target {
                self.pendingCapsLockTarget = nil
                self.deliverInputMethodChanged(target)
                return
            }

            if retriesRemaining > 0 {
                NSLog("[TailInput] CapsLock switch verification failed, retrying")
                self.cachedIsChinese = target
                self.deliverInputMethodChanged(target)
                self.simulateCapsLock()
                self.scheduleCapsLockVerification(target: target, retriesRemaining: retriesRemaining - 1)
            } else {
                NSLog("[TailInput] CapsLock switch verification failed, falling back to TIS")
                self.pendingCapsLockTarget = nil
                self.switchViaTIS(chinese: target)
            }
        }
        capsLockVerificationWorkItem = work
        // macOS 26 CapsLock 生效更快，从 120ms 降至 80ms
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    // MARK: - 策略（委托 ConfiguredAppStore）

    func applyStrategy(for bundleIdentifier: String, appName: String?) {
        currentAppBundleIdentifier = bundleIdentifier
        currentAppName = appName

        let strategy = ConfiguredAppStore.shared.strategy(for: bundleIdentifier)
        NSLog("[TailInput] applyStrategy: %@ → strategy=%d cachedIsChinese=%d",
              appName ?? bundleIdentifier, strategy.rawValue, cachedIsChinese ? 1 : 0)

        switch strategy {
        case .globalDefault, .forceEnglish: switchToEnglish()
        case .forceChinese:                 switchToChinese()
        case .keepCurrent:                  break
        }

        onAppChanged?()
    }

    func setStrategy(_ strategy: AppInputStrategy, for bundleIdentifier: String) {
        ConfiguredAppStore.shared.setStrategy(
            strategy,
            for: bundleIdentifier,
            appName: currentAppName ?? bundleIdentifier
        )
        applyStrategy(for: bundleIdentifier, appName: currentAppName)
    }

    func getStrategy(for bundleIdentifier: String) -> AppInputStrategy {
        ConfiguredAppStore.shared.strategy(for: bundleIdentifier)
    }

    func getCurrentInputMethodName() -> String {
        cachedIsChinese ? "简" : "EN"
    }

    // MARK: - 通知监听

    private func setupObserver() {
        let nc = DistributedNotificationCenter.default()
        // 监听 TIS 输入源切换（跨源切换，如拼音 ↔ ABC 键盘）
        nc.addObserver(self,
                       selector: #selector(handleInputMethodChange),
                       name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
                       object: nil)
        // macOS 26：Apple 拼音 CapsLock 切换中/英时只改变 in-source 模式，
        // 不触发上面的通知，需额外监听此通知保持状态同步
        nc.addObserver(self,
                       selector: #selector(handleInputMethodChange),
                       name: NSNotification.Name("com.apple.inputmethod.currentInputModeDidChange"),
                       object: nil)
    }

    @objc private func handleInputMethodChange() {
        // DistributedNotificationCenter 在注册线程（主线程）回调，直接操作缓存
        refreshCachedInputSource()
        let isChinese = cachedIsChinese

        if pendingCapsLockTarget == isChinese {
            pendingCapsLockTarget = nil
            capsLockVerificationWorkItem?.cancel()
            capsLockVerificationWorkItem = nil
        }

        deliverInputMethodChanged(isChinese)
    }

    private func deliverInputMethodChanged(_ isChinese: Bool) {
        guard lastDeliveredInputState != isChinese else { return }
        lastDeliveredInputState = isChinese
        onInputMethodChanged?(isChinese)
    }
}
