import Cocoa
import Carbon
import ApplicationServices

enum AppInputStrategy: Int, Codable {
    case globalDefault = 0 // 遵循全局默认（强切英文）
    case forceEnglish = 1
    case forceChinese = 2
    case keepCurrent = 3
}

class InputMethodManager {
    static let shared = InputMethodManager()

    // ── 输入源缓存（按优先级排序：strict ABC / Apple Pinyin 排第一位）──
    private var englishInputSources: [TISInputSource] = []
    private var chineseInputSources: [TISInputSource] = []

    // ── 当前输入法状态缓存（避免反复 TIS 调用与字符串解析）──
    private var cachedInputSourceID: String?
    var cachedIsChinese: Bool = false   // internal：AppDelegate / HUD 直接读取

    // ── 防抖 ──
    private var inputChangeWorkItem: DispatchWorkItem?
    private var enabledSourcesWorkItem: DispatchWorkItem?

    // ── 当前应用信息 ──
    var currentAppBundleIdentifier: String?
    var currentAppName: String?

    // ── 回调 ──
    var onInputMethodChanged: ((Bool) -> Void)?   // 传 isChinese Bool，下游自行推导文字/图标
    var onAppChanged: (() -> Void)?

    // ── 设置：是否使用 CapsLock 模拟来切换输入法 ──
    // 开启后，自动切换将通过模拟系统级 CapsLock 事件完成，
    // 这样 macOS 内置的 "CapsLock 切换中英输入源" 状态机能保持一致，
    // 用户在 App 切换之后仍可以用 CapsLock 切回中文。
    private static let kUseCapsLockSimulationKey = "UseCapsLockSimulation"
    var useCapsLockSimulation: Bool {
        get { UserDefaults.standard.bool(forKey: Self.kUseCapsLockSimulationKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.kUseCapsLockSimulationKey) }
    }

    init() {
        loadInputSources()
        refreshCachedInputSource()
        setupObserver()
    }

    // MARK: - 中英文识别（共享）

    private static let chineseKeywords: [String] = [
        "chinese", "pinyin", "sogou", "wubi", "baidu", "shuangpin", "rime", "squirrel"
    ]

    private static func isChineseID(_ lowerId: String) -> Bool {
        for kw in chineseKeywords where lowerId.contains(kw) { return true }
        return false
    }

    private static func isEnglishLayoutID(_ lowerId: String) -> Bool {
        if lowerId == "com.apple.keylayout.abc" { return true }
        if lowerId.hasPrefix("com.apple.keylayout.") {
            return !isChineseID(lowerId)
        }
        return false
    }

    // MARK: - 输入源加载

    func loadInputSources() {
        englishInputSources.removeAll(keepingCapacity: true)
        chineseInputSources.removeAll(keepingCapacity: true)

        let filter = [kTISPropertyInputSourceIsSelectCapable as String: true]
        guard let sourceList = TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue() as? [TISInputSource] else {
            return
        }

        var primaryEnglish: TISInputSource?
        var fallbackEnglish: [TISInputSource] = []
        var primaryChinese: TISInputSource?
        var fallbackChinese: [TISInputSource] = []

        for source in sourceList {
            guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
                  let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String? else {
                continue
            }
            let lowerId = id.lowercased()

            // English 优先级：严格 ABC > 其他 keylayout
            if lowerId == "com.apple.keylayout.abc" {
                primaryEnglish = source
            } else if Self.isEnglishLayoutID(lowerId) {
                fallbackEnglish.append(source)
            }

            // Chinese 优先级：Apple Pinyin > 其他中文 IME
            if lowerId == "com.apple.inputmethod.scim.itabc" || lowerId == "com.apple.inputmethod.scim.pinyin" {
                primaryChinese = source
            } else if Self.isChineseID(lowerId) {
                fallbackChinese.append(source)
            }
        }

        if let p = primaryEnglish { englishInputSources.append(p) }
        englishInputSources.append(contentsOf: fallbackEnglish)
        if let p = primaryChinese { chineseInputSources.append(p) }
        chineseInputSources.append(contentsOf: fallbackChinese)
    }

    // MARK: - 当前输入法状态

    private func refreshCachedInputSource() {
        guard let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            cachedInputSourceID = nil
            cachedIsChinese = false
            return
        }

        var id: String?
        if let idPtr = TISGetInputSourceProperty(currentSource, kTISPropertyInputSourceID) {
            id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
        }
        cachedInputSourceID = id

        let lowerId = id?.lowercased() ?? ""
        var isChinese = Self.isChineseID(lowerId)

        // 字符串无法识别时，退化到本地化名称识别
        if !isChinese && !Self.isEnglishLayoutID(lowerId),
           let namePtr = TISGetInputSourceProperty(currentSource, kTISPropertyLocalizedName),
           let name = Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String? {
            if name.contains("拼音") || name.contains("中文") || name.contains("简体")
                || name.contains("繁体") || name.contains("五笔") || name.contains("搜狗")
                || name.contains("百度") || name.contains("双拼") {
                isChinese = true
            }
        }

        cachedIsChinese = isChinese
    }

    // MARK: - 切换

    func switchToEnglish() { switchTo(chinese: false) }
    func switchToChinese() { switchTo(chinese: true) }

    private func switchTo(chinese: Bool) {
        // 守卫：已在目标状态则跳过（CapsLock 和 TIS 两条路径均适用）
        if cachedIsChinese == chinese { return }

        // CapsLock 模拟路径：通过系统原生事件切换，确保 CapsLock 状态机正常。
        // 不做乐观更新——TIS 通知到达后 refreshCachedInputSource() 会自然修正缓存。
        // 这样可以避免"快速双击 CapsLock"时回退逻辑错误覆盖用户主动按键的问题。
        if useCapsLockSimulation && AXIsProcessTrusted() {
            simulateCapsLock()
            return
        }

        switchViaTIS(chinese: chinese)
    }

    private func switchViaTIS(chinese: Bool) {
        if chinese ? chineseInputSources.isEmpty : englishInputSources.isEmpty {
            loadInputSources()
        }
        let sources = chinese ? chineseInputSources : englishInputSources
        for source in sources {
            if TISSelectInputSource(source) == noErr {
                refreshCachedInputSource()
                return
            }
        }
    }

    // MARK: - CapsLock 模拟

    private func simulateCapsLock() {
        let src = CGEventSource(stateID: .hidSystemState)
        let kVK_CapsLock: CGKeyCode = 0x39
        if let down = CGEvent(keyboardEventSource: src, virtualKey: kVK_CapsLock, keyDown: true) {
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: src, virtualKey: kVK_CapsLock, keyDown: false) {
            up.post(tap: .cghidEventTap)
        }
    }

    // MARK: - 策略（委托 ConfiguredAppStore）

    func applyStrategy(for bundleIdentifier: String, appName: String?) {
        self.currentAppBundleIdentifier = bundleIdentifier
        self.currentAppName = appName

        let strategy = ConfiguredAppStore.shared.strategy(for: bundleIdentifier)

        switch strategy {
        case .globalDefault, .forceEnglish:
            switchToEnglish()
        case .forceChinese:
            switchToChinese()
        case .keepCurrent:
            break
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

    // MARK: - 显示名称（O(1) 直接读缓存）

    func getCurrentInputMethodName() -> String {
        return cachedIsChinese ? "简" : "EN"
    }

    // MARK: - 通知监听

    private func setupObserver() {
        let nc = DistributedNotificationCenter.default()
        nc.addObserver(
            self,
            selector: #selector(handleInputMethodChange),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil
        )
        // 监听输入源列表变化（用户启用/禁用输入法时）
        nc.addObserver(
            self,
            selector: #selector(handleEnabledSourcesChanged),
            name: NSNotification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
            object: nil
        )
    }

    @objc private func handleInputMethodChange() {
        // DistributedNotificationCenter 在主线程回调（注册在主线程），直接操作缓存，
        // 无需额外 DispatchQueue.main.async 包装。
        refreshCachedInputSource()
        let isChinese = cachedIsChinese

        // 仅 UI 通知（状态栏 / HUD）走 debounce 合并多次连续事件
        inputChangeWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.onInputMethodChanged?(isChinese)
        }
        inputChangeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    @objc private func handleEnabledSourcesChanged() {
        // Debounce：用户快速启用/禁用多个输入源时只执行一次重载
        enabledSourcesWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.loadInputSources()
        }
        enabledSourcesWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}
