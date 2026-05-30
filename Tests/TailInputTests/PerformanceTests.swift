import XCTest
@testable import TailInput

final class PerformanceTests: XCTestCase {

    // MARK: - CJKVDetector 吞吐测试

    func testCJKVDetector_throughput_BatchOf10K() {
        let ids = generateTestIDs(count: 10000)
        measure {
            for id in ids {
                _ = CJKVDetector.isCJKV(sourceID: id)
            }
        }
    }

    func testCJKVDetector_singleLookup_SubMicrosecond() {
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<1000 {
            _ = CJKVDetector.isCJKV(sourceID: "com.apple.inputmethod.scim.itabc")
            _ = CJKVDetector.isCJKV(sourceID: "com.apple.keylayout.abc")
        }
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        let avgNanos = Double(elapsed) / 2000.0
        XCTAssertLessThan(avgNanos, 50_000, "average lookup should be < 50us, got \(avgNanos)ns")
    }

    // MARK: - AppKeyboardCache 压力测试

    func testAppKeyboardCache_10KWrites() {
        let cache = AppKeyboardCache()
        measure {
            for i in 0..<10000 {
                cache.save(bundleID: "com.test.app\(i)", sourceID: "source\(i % 50)")
            }
        }
    }

    func testAppKeyboardCache_10KReads() {
        let cache = AppKeyboardCache()
        for i in 0..<10000 {
            cache.save(bundleID: "com.test.app\(i)", sourceID: "source\(i)")
        }
        measure {
            for i in 0..<10000 {
                _ = cache.retrieve(bundleID: "com.test.app\(i)")
            }
        }
    }

    func testAppKeyboardCache_overwriteSameKey() {
        let cache = AppKeyboardCache()
        measure {
            for _ in 0..<50000 {
                cache.save(bundleID: "com.apple.Safari", sourceID: UUID().uuidString)
            }
        }
    }

    func testAppKeyboardCache_concurrentReads() {
        let cache = AppKeyboardCache()
        for i in 0..<1000 {
            cache.save(bundleID: "app\(i)", sourceID: "src\(i)")
        }

        let expectation = XCTestExpectation(description: "concurrent reads")
        expectation.expectedFulfillmentCount = 4

        for _ in 0..<4 {
            DispatchQueue.global().async {
                for i in 0..<1000 {
                    _ = cache.retrieve(bundleID: "app\(i)")
                }
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 5.0)
    }

    // MARK: - InputSourceLabel 高频查询

    func testInputSourceLabel_10KLookups() {
        let testIDs = [
            "com.apple.inputmethod.SCIM.ITABC",
            "com.apple.keylayout.ABC",
            "com.apple.inputmethod.Korean.2SetKorean",
            "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese",
            "com.apple.inputmethod.TCIM.Cangjie",
            "com.sogou.inputmethod.pinyin",
            "im.rime.inputmethod.squirrel",
        ]
        measure {
            for _ in 0..<1500 {
                for id in testIDs {
                    _ = InputSourceLabel.shortLabel(for: id)
                }
            }
        }
    }

    // MARK: - CJKVFixWindow 快速启停

    func testCJKVFixWindow_activationFlag_Speed() {
        measure {
            for _ in 0..<100000 {
                _ = CJKVFixWindow.isHandlingActivation
                _ = CJKVFixWindow.isShowingTemporaryWindow
            }
        }
    }

    // MARK: - 模拟快速 App 切换

    func testRapidAppSwitchSimulation() {
        let apps = generateTestIDs(count: 500)
        let manager = InputMethodManager.shared
        measure {
            for id in apps {
                manager.currentAppBundleIdentifier = id
                manager.currentAppName = "TestApp"
            }
        }
    }

    // MARK: - CJKVDetector 正确性验证

    func testCJKVDetector_correctness_ChineseID() {
        XCTAssertTrue(CJKVDetector.isCJKV(sourceID: "com.apple.inputmethod.scim.itabc"))
        XCTAssertTrue(CJKVDetector.isCJKV(sourceID: "com.apple.inputmethod.tcim.pinyin"))
    }

    func testCJKVDetector_correctness_EnglishID() {
        XCTAssertFalse(CJKVDetector.isCJKV(sourceID: "com.apple.keylayout.abc"))
        XCTAssertFalse(CJKVDetector.isCJKV(sourceID: "com.apple.keylayout.us"))
    }

    // MARK: - Helpers

    private func generateTestIDs(count: Int) -> [String] {
        let base = [
            "com.apple.Safari",
            "com.apple.inputmethod.scim.itabc",
            "com.apple.keylayout.ABC",
            "com.apple.inputmethod.korean.2setkorean",
            "com.google.Chrome",
            "com.microsoft.Word",
            "com.jetbrains.intellij",
            "com.apple.inputmethod.tcim.pinyin",
            "im.rime.inputmethod.squirrel",
            "com.sogou.inputmethod.pinyin",
        ]
        var result: [String] = []
        for i in 0..<count {
            result.append(base[i % base.count])
        }
        return result
    }
}
