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

    private var lastDeliveredInputState: Bool?

    // 拦截 TIS 通知里的过渡"幽灵"读数：
    // TISSelectInputSource 异步生效，通知在状态稳定前就到达，首次 re-read 会拿到旧值。
    // 记录"我们期望的目标"，在 150ms 窗口内若 TIS 报告值与目标不符，直接用目标值覆盖。
    private var pendingSwitchTarget: Bool? = nil
    private var pendingSwitchDeadline: Date = .distantPast

    // 防止旧 re-read 在新切换后仍然清除 pendingSwitchTarget：
    // 每次 selectInputSource 调用递增计数，re-read 闭包只在代数匹配时才清除 pending。
    private var switchGeneration: Int = 0
    private var reReadItem: DispatchWorkItem?

    // ── 当前应用信息 ──
    var currentAppBundleIdentifier: String?
    var currentAppName: String?

    // ── 回调 ──
    var onInputMethodChanged: ((Bool) -> Void)?  // HUD 触发（带去重）
    var onInputStateRefreshed: ((Bool) -> Void)? // 状态栏刷新（无去重，TIS 通知即触发）
    var onAppChanged: (() -> Void)?

    // ── CapsLock 拦截模式 ──
    // UserDefaults 持久化的是"用户的意图"。实际 tap 是否运行由 CapsLockInterceptor.isRunning 决定。
    // 两者可能短暂不一致：用户开启意图后等待 AX 授权期间 → 意图 .compat/.pure，isRunning false。
    // AppDelegate 监听 NSApplication.didBecomeActive，在用户从系统设置回到 App 时重试 start()。
    private static let kCapsLockModeKey         = "CapsLockMode"
    private static let kUseCapsLockInterceptKey = "UseCapsLockSimulation" // legacy v1.4.0 之前

    /// 用户期望的 CapsLock 拦截模式。读取时若新键缺失，自动从旧 Bool 键迁移。
    var capsLockMode: CapsLockMode {
        get {
            if UserDefaults.standard.object(forKey: Self.kCapsLockModeKey) == nil {
                // 迁移：旧版 Bool 为 true 视为 .compat（保留原 300ms 短按行为）
                return UserDefaults.standard.bool(forKey: Self.kUseCapsLockInterceptKey) ? .compat : .off
            }
            let raw = UserDefaults.standard.integer(forKey: Self.kCapsLockModeKey)
            return CapsLockMode(rawValue: raw) ?? .off
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.kCapsLockModeKey)
            // 同步 legacy key，便于回滚到旧版本时设置不丢失
            UserDefaults.standard.set(newValue != .off, forKey: Self.kUseCapsLockInterceptKey)
            CapsLockInterceptor.shared.mode = newValue
            if newValue == .off {
                CapsLockInterceptor.shared.stop()
            } else {
                CapsLockInterceptor.shared.start()
            }
        }
    }

    /// 向后兼容：true ↔ 拦截器以某种模式运行；false ↔ .off。
    /// 默认开启路径走 .compat，保持与 v1.4.0 之前一致的体验。
    var useCapsLockIntercept: Bool {
        get { capsLockMode != .off }
        set { capsLockMode = newValue ? .compat : .off }
    }

    /// UI 调用：尝试以指定模式开启拦截器。返回 false 表示需要权限，调用方应触发授权流程。
    /// 仅在 tap 实际创建成功时才持久化意图，避免"开关 on 但拦截器没跑"的不一致状态。
    @discardableResult
    func tryEnableCapsLockMode(_ mode: CapsLockMode) -> Bool {
        if mode == .off {
            capsLockMode = .off
            return true
        }
        CapsLockInterceptor.shared.mode = mode
        if CapsLockInterceptor.shared.start() {
            UserDefaults.standard.set(mode.rawValue, forKey: Self.kCapsLockModeKey)
            UserDefaults.standard.set(true, forKey: Self.kUseCapsLockInterceptKey)
            return true
        }
        return false
    }

    /// 向后兼容入口，等价于 tryEnableCapsLockMode(.compat)。
    @discardableResult
    func tryEnableCapsLockIntercept() -> Bool {
        return tryEnableCapsLockMode(.compat)
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
        "chinese", "pinyin", "scim", "tcim", "sogou", "wubi", "baidu",
        "shuangpin", "rime", "squirrel", "cangjie", "zhuyin", "stroke", "itabc",
    ]

    private static let chineseNameKeywords = [
        "拼音", "中文", "简体", "繁体", "五笔", "搜狗", "百度", "双拼",
        "pinyin", "chinese", "wubi", "shuangpin", "cangjie", "zhuyin",
    ]

    // kTISTypeKeyboardInputMode 子节点：直接 select 可保证进入正确子模式，
    // 而非仅激活父级 source（父级会恢复上次离开时的子模式，可能是英文 submode）。
    // 大写字母保留原始 Apple ID 大小写（TIS 区分）。
    private static let chineseInputModeIDs: Set<String> = [
        "com.apple.inputmethod.SCIM.ITABC",
        "com.apple.inputmethod.SCIM.Shuangpin",
        "com.apple.inputmethod.SCIM.Wubi",
        "com.apple.inputmethod.TCIM.Pinyin",
        "com.apple.inputmethod.TCIM.Cangjie",
        "com.apple.inputmethod.TCIM.Zhuyin",
    ]

    // Pinyin 等输入法的英文 in-source 子模式 ID（不含 "roman"，需独立识别）
    private static let englishSubmodeIDs: Set<String> = [
        "com.apple.inputmethod.SCIM.ABC",
        "com.apple.inputmethod.TCIM.Roman",
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
    /// Apple Pinyin 英文子模式 modeID 为 "com.apple.inputmethod.SCIM.ABC"，不含 "roman"，
    /// 需通过 englishSubmodeIDs 集合和 ".abc" 后缀额外识别，否则会误报为中文。
    static func detectInputMethodState(sourceID: String, modeID: String?) -> Bool {
        let lower = sourceID.lowercased()
        var isChinese = isChineseID(lower)
        if isChinese, let mode = modeID {
            let mLower = mode.lowercased()
            if mLower.contains("roman") || englishSubmodeIDs.contains(mode) || mLower.hasSuffix(".abc") {
                isChinese = false
            }
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
        // 注意：这里不调用 adoptPendingTargetIfActive()。
        // switchTo 由 applyStrategy（应用规则）调用，应始终以真实 TIS 状态为基准，
        // 而不以"我们期望的目标"为基准；否则 pendingSwitchTarget 可能让 guard
        // 错误地 bail-out，导致规则下的应用中 CapsLock 切换失效。
        guard cachedIsChinese != chinese else { return }
        switchViaTIS(chinese: chinese)
    }

    func toggleInputMethod() {
        refreshCachedInputSource()
        adoptPendingTargetIfActive()
        switchViaTIS(chinese: !cachedIsChinese)
    }

    /// 紧接的上次切换尚未在 TIS 中落地时，TISCopyCurrentKeyboardInputSource 仍返回旧值。
    /// 连按 CapsLock 时若以旧值做"取反"，第二次会反向回到第一次的目标，使两次按键合并为
    /// 单次切换，并造成 HUD 显示与实际输入状态长期不一致。改以目标值为基准即可正确交替。
    private func adoptPendingTargetIfActive() {
        if let target = pendingSwitchTarget, Date() < pendingSwitchDeadline {
            cachedIsChinese = target
        }
    }

    // MARK: - TIS 切换（每次获取新鲜列表，避免缓存 TISInputSource 指针悬空）

    private func switchViaTIS(chinese: Bool) {
        // ── 中文路径：必须先走 mode-node ──
        // 缓存按 kTISPropertyInputSourceID 过滤会优先命中父级 source —— Pinyin 父 source 与
        // Chinese mode node 的 kTISPropertyInputSourceID 是同一字符串（如 "com.apple.inputmethod.SCIM.ITABC"），
        // 而父级 selectCapable=true、mode node selectCapable 不稳定，过滤器永远返回父级。
        // 选父级会触发 TIS 的"恢复上次子模式"逻辑——若上次 Pinyin 离开时在 ABC 子模式
        // （例如用户用 Pinyin 内置 Shift 切到 ABC，或被其他规则带去英文），名义 select 成功但实际
        // 进入英文输入状态。直接 select mode 节点是规避 rebound 的唯一可靠路径。
        if chinese && selectChineseInputMode() { return }

        // ── 缓存兜底 ──
        // 英文：cachedEnglishInputSourceID = "com.apple.keylayout.ABC"，无 submode 问题。
        // 中文：仅在 selectChineseInputMode 失败时（如 Sogou/Rime 等无 mode 节点的输入法）才命中。
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
                // Apple Pinyin 是最优中文源（子模式选择失败时的兜底）
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

    /// 通过 kTISTypeKeyboardInputMode 子节点直接切换到中文子模式。
    /// 这是解决"Apple Pinyin 父级恢复英文 submode"问题的核心：直接 select mode 节点，
    /// 系统不会走"恢复上次状态"逻辑，而是强制进入该子模式。
    @discardableResult
    private func selectChineseInputMode() -> Bool {
        // 包含不可选的 source（第二参数 true）—— mode 节点的 kTISPropertyInputSourceIsSelectCapable
        // 经常报 false（尤其当 Pinyin 当前正处于 ABC 子模式时），但 TISSelectInputSource 实际可以接受
        // 选中并切换到该 mode。所以不做 pre-check，由 TISSelectInputSource 的返回值决定。
        guard let list = TISCreateInputSourceList(nil, true)?.takeRetainedValue() else { return false }
        let count = CFArrayGetCount(list)
        for i in 0..<count {
            guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
            let src = Unmanaged<TISInputSource>.fromOpaque(raw).takeUnretainedValue()

            // 只考虑 InputMode 类型的节点
            guard let typePtr = TISGetInputSourceProperty(src, kTISPropertyInputSourceType) else { continue }
            let type_ = Unmanaged<CFString>.fromOpaque(typePtr).takeUnretainedValue() as String
            guard type_ == (kTISTypeKeyboardInputMode as String) else { continue }

            guard let modePtr = TISGetInputSourceProperty(src, kTISPropertyInputModeID) else { continue }
            let modeID = Unmanaged<CFString>.fromOpaque(modePtr).takeUnretainedValue() as String

            guard Self.chineseInputModeIDs.contains(modeID) else { continue }

            // 直接尝试选中，不预过滤 selectCapable（mode 节点 capable 报 false 但实际可选中是常态）
            let status = selectInputSource(src, id: modeID, chinese: true)
            if status == noErr {
                NSLog("[TailInput] switched to Chinese mode node: %@", modeID)
                return true
            }
        }
        return false
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
            // 乐观更新：TISSelectInputSource 异步生效，立即 re-read 会拿到旧值。
            cachedIsChinese = chinese
            cachedInputSourceID = id
            if chinese {
                cachedChineseInputSourceID = id
            } else {
                cachedEnglishInputSourceID = id
            }
            // 150ms 窗口：告知通知处理器"TIS 在此期间报告旧值属正常，应忽略"
            pendingSwitchTarget = chinese
            pendingSwitchDeadline = Date(timeIntervalSinceNow: 0.15)
            // 递增代数并调度 re-read；旧 re-read 被取消，防止它清除本次的 pending
            switchGeneration += 1
            scheduleReRead(forGeneration: switchGeneration)
            deliverInputMethodChanged(chinese)
            NSLog("[TailInput] switched to %@", chinese ? "Chinese" : "English")
        }
        return result
    }

    /// 80ms 后确认 TIS 已落地，并清除 pendingSwitchTarget。
    /// generation 守卫确保只有最新一次 selectInputSource 的 re-read 能清除 pending，
    /// 旧通知触发的 re-read（代数已过期）直接退出，不干扰新切换的状态。
    /// 额外检测：切中文目标后若 TIS 仍报英文 submode（Apple Pinyin ABC 模式回弹），
    /// 主动重试 selectChineseInputMode() 一次并纠正状态。
    private func scheduleReRead(forGeneration gen: Int) {
        reReadItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard self.switchGeneration == gen else { return }
            let prev = self.cachedIsChinese
            self.refreshCachedInputSource()
            let settled = self.cachedIsChinese

            // 诊断：目标是中文，但 TIS 落地后仍报英文（submode 回弹）
            if let target = self.pendingSwitchTarget, target == true, settled == false {
                NSLog("[TailInput] re-read: Chinese target but TIS settled to English (submode rebound), retrying mode select")
                if self.selectChineseInputMode() {
                    // 重试成功：selectInputSource 已更新状态并重新调度 re-read，本次 re-read 停止
                    return
                }
                // 重试失败：暂时维持乐观目标值，让 HUD 不撒谎；等下一次通知修正
                NSLog("[TailInput] selectChineseInputMode retry failed, keeping optimistic state")
                self.pendingSwitchTarget = nil
                return
            }

            // TIS 已落地：清除 pending，不再用乐观值覆盖后续通知
            self.pendingSwitchTarget = nil
            if settled != prev {
                self.onInputStateRefreshed?(settled)
                self.deliverInputMethodChanged(settled)
            }
        }
        reReadItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: item)
    }

    private func clearCachedTargetID(chinese: Bool) {
        if chinese {
            cachedChineseInputSourceID = nil
        } else {
            cachedEnglishInputSourceID = nil
        }
    }

    // MARK: - 全局默认策略（UserDefaults 持久化，默认切英文）

    var globalDefaultStrategy: AppInputStrategy {
        get {
            let raw = UserDefaults.standard.integer(forKey: "GlobalDefaultStrategy")
            let s = AppInputStrategy(rawValue: raw) ?? .forceEnglish
            // globalDefault 不能作为全局值本身，回退到英文
            return (s == .globalDefault) ? .forceEnglish : s
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "GlobalDefaultStrategy")
        }
    }

    // MARK: - 策略（委托 ConfiguredAppStore）

    func applyStrategy(for bundleIdentifier: String, appName: String?) {
        currentAppBundleIdentifier = bundleIdentifier
        currentAppName = appName

        let strategy = ConfiguredAppStore.shared.strategy(for: bundleIdentifier)
        NSLog("[TailInput] applyStrategy: %@ → strategy=%d cachedIsChinese=%d",
              appName ?? bundleIdentifier, strategy.rawValue, cachedIsChinese ? 1 : 0)

        switch strategy {
        case .globalDefault:
            switch globalDefaultStrategy {
            case .forceEnglish: switchToEnglish()
            case .forceChinese: switchToChinese()
            case .keepCurrent:  break
            default:            switchToEnglish()
            }
        case .forceEnglish: switchToEnglish()
        case .forceChinese: switchToChinese()
        case .keepCurrent:  break
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
        refreshCachedInputSource()

        // 若在 pendingSwitchTarget 窗口内 TIS 报告的是旧值，用目标值替代以避免闪烁。
        // 这发生在 TISSelectInputSource 异步生效期间：通知先到，但状态尚未稳定。
        let now = Date()
        let effectiveState: Bool
        if let target = pendingSwitchTarget, now < pendingSwitchDeadline {
            if cachedIsChinese != target {
                // TIS 尚未稳定：继续使用乐观目标值
                effectiveState = target
                cachedIsChinese = target
            } else {
                // TIS 已与目标对齐，但不在此清除 pending —— 等 scheduleReRead 的 re-read 来清除。
                // 这里清除会产生 Bug B：双重通知里第二条通知使 TIS 正好匹配 target，
                // 从而提前清除 pending，导致后续通知里的旧值无法被正确覆盖。
                effectiveState = cachedIsChinese
            }
        } else {
            // 窗口已过期或没有 pending：清除过期的 pending（正常情况 re-read 早已清除）
            pendingSwitchTarget = nil
            effectiveState = cachedIsChinese
        }

        onInputStateRefreshed?(effectiveState)
        deliverInputMethodChanged(effectiveState)
        // 注意：不在此调度 asyncAfter re-read。
        // re-read 由 selectInputSource → scheduleReRead 统一管理，
        // 代数守卫保证只有最新切换的 re-read 才能清除 pending。
    }

    private func deliverInputMethodChanged(_ isChinese: Bool) {
        guard lastDeliveredInputState != isChinese else { return }
        lastDeliveredInputState = isChinese
        onInputMethodChanged?(isChinese)
    }
}
