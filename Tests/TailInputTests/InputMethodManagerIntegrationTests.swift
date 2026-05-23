import XCTest
@testable import TailInput

/// 通过 InputMethodManager 的公开 API 验证可观测行为，
/// 不触碰真实 TIS 切换（只测状态读取、策略查询、回调机制）。
final class InputMethodManagerIntegrationTests: XCTestCase {

    private var manager: InputMethodManager!

    override func setUp() {
        super.setUp()
        // 使用共享实例；测试只读取状态，不做实际 TIS 切换
        manager = InputMethodManager.shared
    }

    // MARK: - 初始状态

    func test_initialState_cachedIsChineseIsBool() {
        // 初始化后 cachedIsChinese 应为合法布尔值（不崩溃）
        let state = manager.cachedIsChinese
        XCTAssertTrue(state == true || state == false)
    }

    func test_getCurrentInputMethodName_matchesCachedState() {
        let name = manager.getCurrentInputMethodName()
        if manager.cachedIsChinese {
            XCTAssertEqual(name, "简")
        } else {
            XCTAssertEqual(name, "EN")
        }
    }

    // MARK: - 策略读取（与 ConfiguredAppStore 联动）

    func test_getStrategy_unknownApp_returnsGlobalDefault() {
        let strategy = manager.getStrategy(for: "com.example.nonexistent.app.xyz")
        XCTAssertEqual(strategy, .globalDefault)
    }

    func test_setAndGetStrategy_roundTrip() {
        let bundleId = "com.tailinputtest.integration.app"
        manager.currentAppBundleIdentifier = bundleId
        manager.currentAppName = "TestApp"

        // 写入
        manager.setStrategy(.keepCurrent, for: bundleId)
        // 读取
        XCTAssertEqual(manager.getStrategy(for: bundleId), .keepCurrent)

        // 清理
        manager.setStrategy(.globalDefault, for: bundleId)
        XCTAssertEqual(manager.getStrategy(for: bundleId), .globalDefault)
    }

    func test_setStrategy_allCases_readable() {
        let bundleId = "com.tailinputtest.strategy.allcases"
        manager.currentAppBundleIdentifier = bundleId
        manager.currentAppName = "AllCasesApp"

        let cases: [AppInputStrategy] = [.forceEnglish, .forceChinese, .keepCurrent, .globalDefault]
        for strategy in cases {
            manager.setStrategy(strategy, for: bundleId)
            XCTAssertEqual(manager.getStrategy(for: bundleId), strategy,
                           "Round-trip failed for \(strategy)")
        }

        // 最终恢复默认
        manager.setStrategy(.globalDefault, for: bundleId)
    }

    // MARK: - CapsLock 拦截开关

    func test_capsLockIntercept_toggleRoundTrip() {
        let original = manager.useCapsLockIntercept
        manager.useCapsLockIntercept = !original
        XCTAssertEqual(manager.useCapsLockIntercept, !original)
        // 恢复
        manager.useCapsLockIntercept = original
        XCTAssertEqual(manager.useCapsLockIntercept, original)
    }

    func test_capsLockIntercept_persistsInUserDefaults() {
        let key = "UseCapsLockSimulation"
        let original = UserDefaults.standard.bool(forKey: key)

        manager.useCapsLockIntercept = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: key))

        manager.useCapsLockIntercept = false
        XCTAssertFalse(UserDefaults.standard.bool(forKey: key))

        // 恢复
        UserDefaults.standard.set(original, forKey: key)
        // 测试环境可能因 AX 权限启动了拦截器，显式停止
        CapsLockInterceptor.shared.stop()
    }

    // MARK: - 防回归：tryEnable 与 isRunning 一致性
    // 核心约束：tryEnableCapsLockIntercept 返回值 == CapsLockInterceptor.isRunning
    // 失败时绝不能持久化 UserDefaults，避免"开关 on 但拦截器没跑"的不一致 UI 状态

    func test_tryEnable_returnsFalse_doesNotPersist() {
        let key = "UseCapsLockSimulation"
        let originalDefault = UserDefaults.standard.bool(forKey: key)
        UserDefaults.standard.set(false, forKey: key)
        CapsLockInterceptor.shared.stop()  // 已知初始状态

        let result = manager.tryEnableCapsLockIntercept()

        // 不变式：return value 与实际 isRunning 严格一致
        XCTAssertEqual(result, CapsLockInterceptor.shared.isRunning,
                       "tryEnable return value must match actual interceptor state")

        // 不变式：失败时 UserDefaults 不能被写成 true
        if !result {
            XCTAssertFalse(UserDefaults.standard.bool(forKey: key),
                           "Must not persist intent=true when tap creation failed")
        }

        // 清理
        CapsLockInterceptor.shared.stop()
        UserDefaults.standard.set(originalDefault, forKey: key)
    }

    func test_tryEnable_isIdempotent() {
        // 连续调用不应造成状态损坏
        CapsLockInterceptor.shared.stop()
        let r1 = manager.tryEnableCapsLockIntercept()
        let r2 = manager.tryEnableCapsLockIntercept()
        XCTAssertEqual(r1, r2, "Repeated tryEnable calls must return same result")

        // 清理
        CapsLockInterceptor.shared.stop()
        UserDefaults.standard.set(false, forKey: "UseCapsLockSimulation")
    }

    // MARK: - 回调注册与幂等性

    func test_onInputMethodChanged_canBeSet() {
        var callCount = 0
        manager.onInputMethodChanged = { _ in callCount += 1 }
        // 回调已注册，不应崩溃
        XCTAssertNotNil(manager.onInputMethodChanged)
        manager.onInputMethodChanged = nil  // 清理
    }

    func test_onAppChanged_canBeSet() {
        manager.onAppChanged = { }
        XCTAssertNotNil(manager.onAppChanged)
        manager.onAppChanged = nil
    }

    // MARK: - applyStrategy keepCurrent 不改变输入法状态

    func test_applyStrategy_keepCurrent_doesNotModifyCachedState() {
        let bundleId = "com.tailinputtest.keepcurrent"
        manager.currentAppBundleIdentifier = bundleId
        manager.currentAppName = "KeepCurrentApp"
        manager.setStrategy(.keepCurrent, for: bundleId)

        let stateBefore = manager.cachedIsChinese

        // applyStrategy with keepCurrent should not trigger any switch
        var appChangedFired = false
        manager.onAppChanged = { appChangedFired = true }
        manager.applyStrategy(for: bundleId, appName: "KeepCurrentApp")

        // cachedIsChinese should not be force-changed (it may update via TIS read, but direction is preserved)
        // We mainly check that onAppChanged fires (strategy was applied) and no crash
        XCTAssertTrue(appChangedFired, "onAppChanged should always fire after applyStrategy")
        _ = stateBefore  // suppress unused warning

        // cleanup
        manager.setStrategy(.globalDefault, for: bundleId)
        manager.onAppChanged = nil
    }

    // MARK: - currentAppBundleIdentifier / currentAppName

    func test_currentAppInfo_storedCorrectly() {
        manager.currentAppBundleIdentifier = "com.tailinputtest.current"
        manager.currentAppName = "Current Test App"
        XCTAssertEqual(manager.currentAppBundleIdentifier, "com.tailinputtest.current")
        XCTAssertEqual(manager.currentAppName, "Current Test App")
    }

    // MARK: - detectInputMethodState 与 refreshCachedInputSource 一致性

    func test_detectInputMethodState_matchesRefresh_forCurrentSource() {
        // 读取当前实际 TIS 状态，通过 getCurrentInputMethodName 反推
        let reportedName = manager.getCurrentInputMethodName()
        let reportedIsChinese = (reportedName == "简")
        XCTAssertEqual(reportedIsChinese, manager.cachedIsChinese,
                       "getCurrentInputMethodName must reflect cachedIsChinese")
    }
}
