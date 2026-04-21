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
    var cachedIsChinese: Bool = false   // internal：AppDelegate / HUD 直接读取

    // ── 防抖：UI 通知合并 ──
    private var inputChangeWorkItem: DispatchWorkItem?

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

    private static let chineseKeywords = ["chinese", "pinyin", "sogou", "wubi",
                                           "baidu", "shuangpin", "rime", "squirrel"]

    static func isChineseID(_ lowerId: String) -> Bool {
        chineseKeywords.contains { lowerId.contains($0) }
    }

    static func isEnglishLayoutID(_ lowerId: String) -> Bool {
        guard lowerId.hasPrefix("com.apple.keylayout.") else { return false }
        return !isChineseID(lowerId)
    }

    // MARK: - 当前输入法状态

    private func refreshCachedInputSource() {
        guard let src = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            cachedInputSourceID = nil; cachedIsChinese = false; return
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
            let cnWords = ["拼音","中文","简体","繁体","五笔","搜狗","百度","双拼"]
            isChinese = cnWords.contains { name.contains($0) }
        }
        cachedIsChinese = isChinese
    }

    // MARK: - 公开切换入口

    func switchToEnglish() { switchTo(chinese: false) }
    func switchToChinese() { switchTo(chinese: true) }

    private func switchTo(chinese: Bool) {
        guard cachedIsChinese != chinese else { return }

        if useCapsLockSimulation && AXIsProcessTrusted() {
            // 乐观更新：CapsLock 事件异步生效，提前写入目标状态让 UI 立即响应
            cachedIsChinese = chinese
            simulateCapsLock()
            return
        }
        switchViaTIS(chinese: chinese)
    }

    // MARK: - TIS 切换（每次获取新鲜列表，避免缓存 TISInputSource 指针悬空）

    private func switchViaTIS(chinese: Bool) {
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
        var fallbackPtr: UnsafeRawPointer? = nil

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
                    primaryPtr = rawPtr; break
                }
                if Self.isChineseID(lower), fallbackPtr == nil { fallbackPtr = rawPtr }
            } else {
                // 严格 ABC 是最优英文源
                if lower == "com.apple.keylayout.abc" {
                    primaryPtr = rawPtr; break
                }
                if Self.isEnglishLayoutID(lower), fallbackPtr == nil { fallbackPtr = rawPtr }
            }
        }

        guard let ptr = primaryPtr ?? fallbackPtr else {
            NSLog("[TailInput] No \(chinese ? "Chinese" : "English") source found in \(count) sources")
            return
        }

        // TISSelectInputSource 调用必须在 cfList 存活期间（此时 rawPtr 仍有效）
        let target = Unmanaged<TISInputSource>.fromOpaque(ptr).takeUnretainedValue()
        let result = TISSelectInputSource(target)
        if result == noErr {
            // 乐观更新：TISSelectInputSource 是异步生效的，立即 re-read 会拿到旧值。
            // 这里直接写入目标值；TIS 通知到来后 handleInputMethodChange 会用真实值覆盖。
            cachedIsChinese = chinese
            NSLog("[TailInput] switched to %@", chinese ? "Chinese" : "English")
        } else {
            NSLog("[TailInput] TISSelectInputSource failed: %d", result)
        }
        // cfList 在此处释放（函数结束）
    }

    // MARK: - CapsLock 模拟

    private func simulateCapsLock() {
        let src = CGEventSource(stateID: .hidSystemState)
        let kVK_CapsLock: CGKeyCode = 0x39
        CGEvent(keyboardEventSource: src, virtualKey: kVK_CapsLock, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: src, virtualKey: kVK_CapsLock, keyDown: false)?.post(tap: .cghidEventTap)
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
        nc.addObserver(self,
                       selector: #selector(handleInputMethodChange),
                       name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
                       object: nil)
    }

    @objc private func handleInputMethodChange() {
        // DistributedNotificationCenter 在注册线程（主线程）回调，直接操作缓存
        refreshCachedInputSource()
        let isChinese = cachedIsChinese

        // TIS 通知本身是单发事件（每次切换只触发一次），无需防抖。
        // 直接同步通知 UI 让图标和 HUD 即时响应，消除额外的 50ms 感知延迟。
        inputChangeWorkItem?.cancel()
        onInputMethodChanged?(isChinese)
    }
}
