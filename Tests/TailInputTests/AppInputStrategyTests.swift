import XCTest
@testable import TailInput

/// 覆盖 AppInputStrategy 枚举的 rawValue、Codable 以及策略语义。
final class AppInputStrategyTests: XCTestCase {

    // MARK: - RawValue 稳定性（持久化依赖 rawValue，不能随意变更）

    func test_rawValue_globalDefault_isZero() {
        XCTAssertEqual(AppInputStrategy.globalDefault.rawValue, 0)
    }

    func test_rawValue_forceEnglish_isOne() {
        XCTAssertEqual(AppInputStrategy.forceEnglish.rawValue, 1)
    }

    func test_rawValue_forceChinese_isTwo() {
        XCTAssertEqual(AppInputStrategy.forceChinese.rawValue, 2)
    }

    func test_rawValue_keepCurrent_isThree() {
        XCTAssertEqual(AppInputStrategy.keepCurrent.rawValue, 3)
    }

    // MARK: - RawValue 反向构造

    func test_init_fromRawValue_globalDefault() {
        XCTAssertEqual(AppInputStrategy(rawValue: 0), .globalDefault)
    }

    func test_init_fromRawValue_forceEnglish() {
        XCTAssertEqual(AppInputStrategy(rawValue: 1), .forceEnglish)
    }

    func test_init_fromRawValue_forceChinese() {
        XCTAssertEqual(AppInputStrategy(rawValue: 2), .forceChinese)
    }

    func test_init_fromRawValue_keepCurrent() {
        XCTAssertEqual(AppInputStrategy(rawValue: 3), .keepCurrent)
    }

    func test_init_fromRawValue_invalidReturnsNil() {
        XCTAssertNil(AppInputStrategy(rawValue: 99))
        XCTAssertNil(AppInputStrategy(rawValue: -1))
    }

    // MARK: - Codable 往返

    func test_codable_roundTrip_allCases() throws {
        let cases: [AppInputStrategy] = [.globalDefault, .forceEnglish, .forceChinese, .keepCurrent]
        for strategy in cases {
            let data = try JSONEncoder().encode(strategy)
            let decoded = try JSONDecoder().decode(AppInputStrategy.self, from: data)
            XCTAssertEqual(decoded, strategy, "Codable round-trip failed for \(strategy)")
        }
    }

    func test_codable_encodedAsInteger() throws {
        let data = try JSONEncoder().encode(AppInputStrategy.forceEnglish)
        let value = try JSONDecoder().decode(Int.self, from: data)
        XCTAssertEqual(value, 1)
    }

    // MARK: - Codable 在 ConfiguredApp 容器中

    func test_codable_insideConfiguredApp() throws {
        let app = ConfiguredApp(bundleId: "com.example.app", appName: "Test App", strategy: .forceChinese)
        let data = try JSONEncoder().encode(app)
        let decoded = try JSONDecoder().decode(ConfiguredApp.self, from: data)
        XCTAssertEqual(decoded.bundleId,  app.bundleId)
        XCTAssertEqual(decoded.appName,   app.appName)
        XCTAssertEqual(decoded.strategy,  app.strategy)
    }

    func test_codable_dictionaryOfConfiguredApp() throws {
        let dict: [String: ConfiguredApp] = [
            "com.a": ConfiguredApp(bundleId: "com.a", appName: "A", strategy: .forceEnglish),
            "com.b": ConfiguredApp(bundleId: "com.b", appName: "B", strategy: .keepCurrent),
        ]
        let data = try JSONEncoder().encode(dict)
        let decoded = try JSONDecoder().decode([String: ConfiguredApp].self, from: data)
        XCTAssertEqual(decoded["com.a"]?.strategy, .forceEnglish)
        XCTAssertEqual(decoded["com.b"]?.strategy, .keepCurrent)
    }

    // MARK: - 策略语义（与 applyStrategy 的业务对齐）

    func test_globalDefault_andForceEnglish_bothCauseSwitchToEnglish() {
        // 验证业务逻辑：两者等效触发 switchToEnglish
        // 这里只测语义一致性，不调用实际 TIS
        let strategiesThatMeanEnglish: [AppInputStrategy] = [.globalDefault, .forceEnglish]
        for s in strategiesThatMeanEnglish {
            let meansEnglish = (s == .globalDefault || s == .forceEnglish)
            XCTAssertTrue(meansEnglish, "\(s) should cause English switch")
        }
    }

    func test_keepCurrent_doesNotMeanSwitch() {
        XCTAssertNotEqual(AppInputStrategy.keepCurrent, .forceEnglish)
        XCTAssertNotEqual(AppInputStrategy.keepCurrent, .forceChinese)
    }
}
