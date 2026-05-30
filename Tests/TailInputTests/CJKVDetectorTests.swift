import XCTest
@testable import TailInput

final class CJKVDetectorTests: XCTestCase {

    func testDetectsChineseSCIM() {
        XCTAssertTrue(CJKVDetector.isCJKV(sourceID: "com.apple.inputmethod.scim.itabc"))
        XCTAssertTrue(CJKVDetector.isCJKV(sourceID: "com.apple.inputmethod.scim.wbx"))
        XCTAssertTrue(CJKVDetector.isCJKV(sourceID: "com.apple.inputmethod.scim.pinyin"))
    }

    func testDetectsTraditionalChineseTCIM() {
        XCTAssertTrue(CJKVDetector.isCJKV(sourceID: "com.apple.inputmethod.tcim.pinyin"))
        XCTAssertTrue(CJKVDetector.isCJKV(sourceID: "com.apple.inputmethod.tcim.cangjie"))
        XCTAssertTrue(CJKVDetector.isCJKV(sourceID: "com.apple.inputmethod.tcim.zhuyin"))
    }

    func testDetectsKorean() {
        XCTAssertTrue(CJKVDetector.isCJKV(sourceID: "com.apple.inputmethod.korean.2setkorean"))
        XCTAssertTrue(CJKVDetector.isCJKV(sourceID: "com.apple.inputmethod.korean.3setkorean"))
    }

    func testDetectsJapanese() {
        XCTAssertTrue(CJKVDetector.isCJKV(sourceID: "com.apple.inputmethod.kotoeri.romajityping.japanese"))
        XCTAssertTrue(CJKVDetector.isCJKV(sourceID: "com.apple.inputmethod.kotoeri.kanatyping.japanese"))
    }

    func testDetectsRussian() {
        XCTAssertTrue(CJKVDetector.isCJKV(sourceID: "com.apple.keylayout.russian.phonetic"))
    }

    func testDetectsVietnamese() {
        XCTAssertTrue(CJKVDetector.isCJKV(sourceID: "com.apple.inputmethod.vi.viqr"))
    }

    func testDetectsThirdPartyChinese() {
        XCTAssertTrue(CJKVDetector.isCJKV(sourceID: "com.sogou.inputmethod.sogou.pinyin"))
        XCTAssertTrue(CJKVDetector.isCJKV(sourceID: "im.rime.inputmethod.squirrel"))
    }

    func testRejectsEnglishLayouts() {
        XCTAssertFalse(CJKVDetector.isCJKV(sourceID: "com.apple.keylayout.abc"))
        XCTAssertFalse(CJKVDetector.isCJKV(sourceID: "com.apple.keylayout.us"))
        XCTAssertFalse(CJKVDetector.isCJKV(sourceID: "com.apple.keylayout.british"))
    }

    func testEnglishLayoutDetection() {
        XCTAssertTrue(CJKVDetector.isEnglishLayout(sourceID: "com.apple.keylayout.abc"))
        XCTAssertTrue(CJKVDetector.isEnglishLayout(sourceID: "com.apple.keylayout.us"))
        XCTAssertFalse(CJKVDetector.isEnglishLayout(sourceID: "com.apple.inputmethod.scim.itabc"))
    }

    func testCaseInsensitive() {
        XCTAssertTrue(CJKVDetector.isCJKV(sourceID: "COM.APPLE.INPUTMETHOD.SCIM.ITABC"))
        XCTAssertTrue(CJKVDetector.isCJKV(sourceID: "Com.Apple.Inputmethod.Korean.2SetKorean"))
    }

    func testEmptyAndUnknown() {
        XCTAssertFalse(CJKVDetector.isCJKV(sourceID: ""))
        XCTAssertFalse(CJKVDetector.isCJKV(sourceID: "com.example.unknown"))
    }
}
