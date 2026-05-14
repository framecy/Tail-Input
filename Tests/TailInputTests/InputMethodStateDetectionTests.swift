import XCTest
@testable import TailInput

/// 覆盖 detectInputMethodState(sourceID:modeID:) 和 detectChineseByLocalizedName(_:) 的全量场景。
final class InputMethodStateDetectionTests: XCTestCase {

    // MARK: - detectInputMethodState: modeID 为 nil（不触发覆盖逻辑）

    func test_chineseSource_nilModeID_returnsChinese() {
        XCTAssertTrue(
            InputMethodManager.detectInputMethodState(
                sourceID: "com.apple.inputmethod.scim.itabc",
                modeID: nil
            )
        )
    }

    func test_englishLayout_nilModeID_returnsEnglish() {
        XCTAssertFalse(
            InputMethodManager.detectInputMethodState(
                sourceID: "com.apple.keylayout.ABC",
                modeID: nil
            )
        )
    }

    func test_unknownSource_nilModeID_returnsEnglish() {
        XCTAssertFalse(
            InputMethodManager.detectInputMethodState(
                sourceID: "com.example.unknown.layout",
                modeID: nil
            )
        )
    }

    // MARK: - detectInputMethodState: modeID 含 "roman" → 覆盖为英文

    func test_chineseSource_romanModeID_returnsEnglish() {
        XCTAssertFalse(
            InputMethodManager.detectInputMethodState(
                sourceID: "com.apple.inputmethod.scim.itabc",
                modeID: "com.apple.inputmethod.Roman"
            )
        )
    }

    func test_chineseSource_romanModeID_caseInsensitive() {
        // modeID 大小写不敏感匹配
        XCTAssertFalse(
            InputMethodManager.detectInputMethodState(
                sourceID: "com.apple.inputmethod.scim.itabc",
                modeID: "com.apple.inputmethod.ROMAN"
            )
        )
    }

    func test_thirdPartyChineseSource_romanModeID_returnsEnglish() {
        // 第三方输入法（如 Squirrel/Rime）in-source 英文模式
        XCTAssertFalse(
            InputMethodManager.detectInputMethodState(
                sourceID: "im.rime.inputmethod.squirrel",
                modeID: "im.rime.inputmethod.Roman"
            )
        )
    }

    func test_sogouPinyin_romanModeID_returnsEnglish() {
        XCTAssertFalse(
            InputMethodManager.detectInputMethodState(
                sourceID: "com.sogou.inputmethod.sogou.pinyin",
                modeID: "com.sogou.inputmethod.Roman"
            )
        )
    }

    // MARK: - detectInputMethodState: modeID 为中文 mode ID → 保持中文

    func test_chineseSource_chineseModeID_remainsChinese() {
        XCTAssertTrue(
            InputMethodManager.detectInputMethodState(
                sourceID: "com.apple.inputmethod.scim.itabc",
                modeID: "com.apple.inputmethod.SCIM.ITABC"
            )
        )
    }

    func test_chineseSource_shuangpinModeID_remainsChinese() {
        XCTAssertTrue(
            InputMethodManager.detectInputMethodState(
                sourceID: "com.apple.inputmethod.scim.shuangpin",
                modeID: "com.apple.inputmethod.SCIM.Shuangpin"
            )
        )
    }

    // MARK: - detectInputMethodState: 英文布局 + modeID（modeID check 不运行，因为 isChineseID 为 false）

    func test_englishLayout_withRomanModeID_remainsEnglish() {
        // 英文布局本身 isChineseID=false，modeID 检测不运行，结果仍为英文
        XCTAssertFalse(
            InputMethodManager.detectInputMethodState(
                sourceID: "com.apple.keylayout.ABC",
                modeID: "com.apple.inputmethod.Roman"
            )
        )
    }

    func test_englishLayout_withChineseModeID_remainsEnglish() {
        // 英文布局即使有奇怪的 modeID 也不应被判中文
        XCTAssertFalse(
            InputMethodManager.detectInputMethodState(
                sourceID: "com.apple.keylayout.ABC",
                modeID: "com.apple.inputmethod.SCIM.ITABC"
            )
        )
    }

    // MARK: - detectInputMethodState: 日语输入法（不含中文关键字，modeID roman 无影响）

    func test_kotoeriRoman_alreadyEnglish_modeIDIgnored() {
        // Kotoeri.Roman sourceID 本身不含中文关键字 → isChinese=false → modeID check 不运行
        XCTAssertFalse(
            InputMethodManager.detectInputMethodState(
                sourceID: "com.apple.inputmethod.Kotoeri.KanaTyping.Roman",
                modeID: "com.apple.inputmethod.Roman"
            )
        )
    }

    func test_kotoeriJapanese_notChinese() {
        XCTAssertFalse(
            InputMethodManager.detectInputMethodState(
                sourceID: "com.apple.inputmethod.Kotoeri.KanaTyping.Japanese",
                modeID: "com.apple.inputmethod.Japanese"
            )
        )
    }

    // MARK: - detectInputMethodState: 空字符串边界

    func test_emptySourceID_nilModeID_returnsEnglish() {
        XCTAssertFalse(
            InputMethodManager.detectInputMethodState(sourceID: "", modeID: nil)
        )
    }

    func test_emptySourceID_romanModeID_returnsEnglish() {
        XCTAssertFalse(
            InputMethodManager.detectInputMethodState(sourceID: "", modeID: "com.apple.inputmethod.Roman")
        )
    }

    // MARK: - detectChineseByLocalizedName

    func test_localizedName_pinyin_chinese() {
        XCTAssertTrue(InputMethodManager.detectChineseByLocalizedName("拼音"))
    }

    func test_localizedName_zhongwen_chinese() {
        XCTAssertTrue(InputMethodManager.detectChineseByLocalizedName("中文"))
    }

    func test_localizedName_simplified_chinese() {
        XCTAssertTrue(InputMethodManager.detectChineseByLocalizedName("简体拼音"))
    }

    func test_localizedName_traditional_chinese() {
        XCTAssertTrue(InputMethodManager.detectChineseByLocalizedName("繁体注音"))
    }

    func test_localizedName_sogou_chinese() {
        XCTAssertTrue(InputMethodManager.detectChineseByLocalizedName("搜狗输入法"))
    }

    func test_localizedName_english_abc_notChinese() {
        XCTAssertFalse(InputMethodManager.detectChineseByLocalizedName("ABC"))
    }

    func test_localizedName_english_us_notChinese() {
        XCTAssertFalse(InputMethodManager.detectChineseByLocalizedName("U.S."))
    }

    func test_localizedName_japanese_notChinese() {
        XCTAssertFalse(InputMethodManager.detectChineseByLocalizedName("Hiragana"))
    }

    func test_localizedName_empty_notChinese() {
        XCTAssertFalse(InputMethodManager.detectChineseByLocalizedName(""))
    }

    func test_localizedName_pinyin_english_keyword() {
        // "pinyin" 英文拼写也应被识别
        XCTAssertTrue(InputMethodManager.detectChineseByLocalizedName("Pinyin Input"))
    }

    func test_localizedName_chinese_english_keyword() {
        XCTAssertTrue(InputMethodManager.detectChineseByLocalizedName("Chinese (Simplified)"))
    }
}
