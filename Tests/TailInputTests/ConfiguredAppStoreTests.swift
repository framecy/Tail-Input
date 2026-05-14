import XCTest
@testable import TailInput

/// 覆盖 ConfiguredAppStore 的 CRUD、持久化和 Legacy 迁移逻辑。
final class ConfiguredAppStoreTests: XCTestCase {

    // 每个测试前后清理 UserDefaults，防止状态污染
    private let storeKey    = "ConfiguredAppsV2"
    private let migratedKey = "ConfiguredAppsV2_migrated"
    private let legacyPrefix = "AppStrategy_"

    override func setUp() {
        super.setUp()
        cleanDefaults()
    }

    override func tearDown() {
        cleanDefaults()
        super.tearDown()
    }

    private func cleanDefaults() {
        let ud = UserDefaults.standard
        ud.removeObject(forKey: storeKey)
        ud.removeObject(forKey: migratedKey)
        // 清除所有可能遗留的 legacy key
        for key in ud.dictionaryRepresentation().keys where key.hasPrefix(legacyPrefix) {
            ud.removeObject(forKey: key)
        }
        ud.synchronize()
    }

    private func makeStore() -> ConfiguredAppStore {
        ConfiguredAppStore()
    }

    // MARK: - 默认策略

    func test_defaultStrategy_isGlobalDefault() {
        let store = makeStore()
        XCTAssertEqual(store.strategy(for: "com.example.unknown"), .globalDefault)
    }

    func test_all_emptyOnFreshStore() {
        let store = makeStore()
        XCTAssertTrue(store.all().isEmpty)
    }

    // MARK: - Set / Get 基本 CRUD

    func test_setStrategy_forceEnglish_thenGet() {
        let store = makeStore()
        store.setStrategy(.forceEnglish, for: "com.example.app", appName: "App")
        XCTAssertEqual(store.strategy(for: "com.example.app"), .forceEnglish)
    }

    func test_setStrategy_forceChinese_thenGet() {
        let store = makeStore()
        store.setStrategy(.forceChinese, for: "com.example.app", appName: "App")
        XCTAssertEqual(store.strategy(for: "com.example.app"), .forceChinese)
    }

    func test_setStrategy_keepCurrent_thenGet() {
        let store = makeStore()
        store.setStrategy(.keepCurrent, for: "com.example.app", appName: "App")
        XCTAssertEqual(store.strategy(for: "com.example.app"), .keepCurrent)
    }

    func test_setStrategy_globalDefault_removesEntry() {
        let store = makeStore()
        store.setStrategy(.forceEnglish, for: "com.example.app", appName: "App")
        store.setStrategy(.globalDefault, for: "com.example.app", appName: "App")
        XCTAssertEqual(store.strategy(for: "com.example.app"), .globalDefault)
        XCTAssertTrue(store.all().isEmpty, "globalDefault should not persist in store")
    }

    func test_setStrategy_overwrite() {
        let store = makeStore()
        store.setStrategy(.forceEnglish, for: "com.example.app", appName: "App")
        store.setStrategy(.forceChinese, for: "com.example.app", appName: "App")
        XCTAssertEqual(store.strategy(for: "com.example.app"), .forceChinese)
    }

    // MARK: - Remove

    func test_remove_clearsStrategy() {
        let store = makeStore()
        store.setStrategy(.forceEnglish, for: "com.example.app", appName: "App")
        store.remove(bundleId: "com.example.app")
        XCTAssertEqual(store.strategy(for: "com.example.app"), .globalDefault)
    }

    func test_remove_nonExistentApp_noError() {
        let store = makeStore()
        // Should not crash
        store.remove(bundleId: "com.example.doesnotexist")
        XCTAssertEqual(store.strategy(for: "com.example.doesnotexist"), .globalDefault)
    }

    // MARK: - all() 过滤和排序

    func test_all_excludesGlobalDefault() {
        let store = makeStore()
        store.setStrategy(.forceEnglish, for: "com.a.app", appName: "A App")
        store.setStrategy(.globalDefault, for: "com.b.app", appName: "B App")
        let all = store.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.bundleId, "com.a.app")
    }

    func test_all_sortedByAppName() {
        let store = makeStore()
        store.setStrategy(.forceEnglish, for: "com.z.app", appName: "Zebra")
        store.setStrategy(.forceChinese, for: "com.a.app", appName: "Apple")
        store.setStrategy(.keepCurrent, for: "com.m.app", appName: "Mango")
        let names = store.all().map { $0.appName }
        XCTAssertEqual(names, ["Apple", "Mango", "Zebra"])
    }

    func test_all_multipleApps_allPresent() {
        let store = makeStore()
        let apps = ["com.a": "Alpha", "com.b": "Beta", "com.c": "Gamma"]
        for (bundle, name) in apps {
            store.setStrategy(.keepCurrent, for: bundle, appName: name)
        }
        XCTAssertEqual(store.all().count, 3)
    }

    // MARK: - 持久化（跨实例）

    func test_persistence_surviveNewInstance() {
        let store1 = makeStore()
        store1.setStrategy(.forceChinese, for: "com.example.app", appName: "App")

        let store2 = makeStore()  // 新实例，从 UserDefaults 加载
        XCTAssertEqual(store2.strategy(for: "com.example.app"), .forceChinese)
    }

    func test_persistence_removesSurviveNewInstance() {
        let store1 = makeStore()
        store1.setStrategy(.forceEnglish, for: "com.example.app", appName: "App")
        store1.remove(bundleId: "com.example.app")

        let store2 = makeStore()
        XCTAssertEqual(store2.strategy(for: "com.example.app"), .globalDefault)
    }

    func test_persistence_multipleApps_allSurvive() {
        let store1 = makeStore()
        store1.setStrategy(.forceEnglish, for: "com.a", appName: "A")
        store1.setStrategy(.forceChinese, for: "com.b", appName: "B")
        store1.setStrategy(.keepCurrent, for: "com.c", appName: "C")

        let store2 = makeStore()
        XCTAssertEqual(store2.strategy(for: "com.a"), .forceEnglish)
        XCTAssertEqual(store2.strategy(for: "com.b"), .forceChinese)
        XCTAssertEqual(store2.strategy(for: "com.c"), .keepCurrent)
    }

    // MARK: - Legacy 迁移

    func test_migration_fromLegacyKeys_convertsToNewFormat() {
        let ud = UserDefaults.standard
        // 写入旧格式数据（AppStrategy_ 前缀 + rawValue）
        ud.set(AppInputStrategy.forceEnglish.rawValue,  forKey: "\(legacyPrefix)com.example.safari")
        ud.set(AppInputStrategy.forceChinese.rawValue,  forKey: "\(legacyPrefix)com.example.vscode")
        ud.set(AppInputStrategy.globalDefault.rawValue, forKey: "\(legacyPrefix)com.example.finder") // 应被过滤
        // 未设置 migratedKey → 触发迁移

        let store = makeStore()  // 构造时触发 migrateFromLegacyIfNeeded
        XCTAssertEqual(store.strategy(for: "com.example.safari"), .forceEnglish)
        XCTAssertEqual(store.strategy(for: "com.example.vscode"), .forceChinese)
        XCTAssertEqual(store.strategy(for: "com.example.finder"), .globalDefault, "globalDefault should not persist")
    }

    func test_migration_onlyRunsOnce() {
        let ud = UserDefaults.standard
        ud.set(AppInputStrategy.forceEnglish.rawValue, forKey: "\(legacyPrefix)com.example.app")

        let store1 = makeStore()  // 第一次：迁移执行，写入 migratedKey
        XCTAssertEqual(store1.strategy(for: "com.example.app"), .forceEnglish)

        // 模拟：删除迁移结果但保留 migratedKey（迁移不应重跑）
        ud.removeObject(forKey: storeKey)
        // 保持 migratedKey = true

        let store2 = makeStore()  // 第二次：migratedKey 存在，跳过迁移
        XCTAssertEqual(store2.strategy(for: "com.example.app"), .globalDefault,
                       "Migration should not re-run, store should be empty")
    }

    func test_migration_emptyLegacy_noDataLoss() {
        // 无 legacy 数据时迁移应无副作用
        let store = makeStore()
        XCTAssertTrue(store.all().isEmpty)
        XCTAssertEqual(store.strategy(for: "com.example.app"), .globalDefault)
    }

    // MARK: - appName 存储与更新

    func test_appName_storedCorrectly() {
        let store = makeStore()
        store.setStrategy(.forceEnglish, for: "com.example.app", appName: "My App")
        let entry = store.all().first(where: { $0.bundleId == "com.example.app" })
        XCTAssertEqual(entry?.appName, "My App")
    }

    func test_appName_updatedOnOverwrite() {
        let store = makeStore()
        store.setStrategy(.forceEnglish, for: "com.example.app", appName: "Old Name")
        store.setStrategy(.forceChinese, for: "com.example.app", appName: "New Name")
        let entry = store.all().first(where: { $0.bundleId == "com.example.app" })
        XCTAssertEqual(entry?.appName, "New Name")
    }

    // MARK: - bundleId 边界

    func test_differentBundleIDs_independent() {
        let store = makeStore()
        store.setStrategy(.forceEnglish, for: "com.a.app", appName: "A")
        store.setStrategy(.forceChinese, for: "com.b.app", appName: "B")
        XCTAssertEqual(store.strategy(for: "com.a.app"), .forceEnglish)
        XCTAssertEqual(store.strategy(for: "com.b.app"), .forceChinese)
        XCTAssertEqual(store.strategy(for: "com.c.app"), .globalDefault)
    }

    func test_caseSensitiveBundleID() {
        let store = makeStore()
        store.setStrategy(.forceEnglish, for: "com.Example.App", appName: "App")
        // Bundle ID 区分大小写
        XCTAssertEqual(store.strategy(for: "com.Example.App"), .forceEnglish)
        XCTAssertEqual(store.strategy(for: "com.example.app"), .globalDefault)
    }
}
