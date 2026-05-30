import XCTest
@testable import TailInput

final class InputSourceLabelTests: XCTestCase {

    func testChineseSCIMLabels() {
        XCTAssertEqual(InputSourceLabel.shortLabel(for: "com.apple.inputmethod.SCIM.ITABC"), "拼")
        XCTAssertEqual(InputSourceLabel.shortLabel(for: "com.apple.inputmethod.SCIM.WBX"), "五")
        XCTAssertEqual(InputSourceLabel.shortLabel(for: "com.apple.inputmethod.SCIM.WBH"), "画")
        XCTAssertEqual(InputSourceLabel.shortLabel(for: "com.apple.inputmethod.SCIM.Shuangpin"), "双")
    }

    func testTraditionalChineseTCIMLabels() {
        XCTAssertEqual(InputSourceLabel.shortLabel(for: "com.apple.inputmethod.TCIM.Cangjie"), "倉")
        XCTAssertEqual(InputSourceLabel.shortLabel(for: "com.apple.inputmethod.TCIM.Pinyin"), "繁拼")
        XCTAssertEqual(InputSourceLabel.shortLabel(for: "com.apple.inputmethod.TCIM.Zhuyin"), "注")
    }

    func testKoreanLabels() {
        XCTAssertEqual(InputSourceLabel.shortLabel(for: "com.apple.inputmethod.Korean.2SetKorean"), "한")
    }

    func testJapaneseLabels() {
        XCTAssertEqual(InputSourceLabel.shortLabel(for: "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese"), "あ")
    }

    func testEnglishLayoutLabels() {
        XCTAssertEqual(InputSourceLabel.shortLabel(for: "com.apple.keylayout.ABC"), "A")
        XCTAssertEqual(InputSourceLabel.shortLabel(for: "com.apple.keylayout.US"), "US")
        XCTAssertEqual(InputSourceLabel.shortLabel(for: "com.apple.keylayout.British"), "GB")
    }

    func testFallbackByKeyword() {
        XCTAssertEqual(InputSourceLabel.shortLabel(for: "com.sogou.inputmethod.pinyin"), "搜")
        XCTAssertEqual(InputSourceLabel.shortLabel(for: "im.rime.inputmethod.squirrel"), "鼠")
        XCTAssertEqual(InputSourceLabel.shortLabel(for: "com.baidu.inputmethod"), "百")
    }

    func testFallbackByLocalizedName() {
        XCTAssertEqual(InputSourceLabel.shortLabel(for: "unknown.source", localizedName: "拼音输入法"), "拼")
        XCTAssertEqual(InputSourceLabel.shortLabel(for: "unknown.source", localizedName: "五笔"), "五")
        XCTAssertEqual(InputSourceLabel.shortLabel(for: "unknown.source", localizedName: "Korean Keyboard"), "한")
    }

    func testUnknownSourceReturnsQuestionMark() {
        XCTAssertEqual(InputSourceLabel.shortLabel(for: "com.unknown.keyboard"), "?")
    }
}
