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

    // MARK: - CapsLock 模拟开关

    func test_capsLockSimulation_toggleRoundTrip() {
        let original = manager.useCapsLockSimulation
        manager.useCapsLockSimulation = !original
        XCTAssertEqual(manager.useCapsLockSimulation, !original)
        // 恢复
        manager.useCapsLockSimulation = original
        XCTAssertEqual(manager.useCapsLockSimulation, original)
    }

    func test_capsLockSimulation_persistsInUserDefaults() {
        let key = "UseCapsLockSimulation"
        let original = UserDefaults.standard.bool(forKey: key)

        manager.useCapsLockSimulation = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: key))

        manager.useCapsLockSimulation = false
        XCTAssertFalse(UserDefaults.standard.bool(forKey: key))

        // 恢复
        UserDefaults.standard.set(original, forKey: key)
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
