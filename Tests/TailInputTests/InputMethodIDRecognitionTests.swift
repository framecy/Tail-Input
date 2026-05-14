import XCTest
@testable import TailInput

/// 覆盖 InputMethodManager.isChineseID(_:) 和 isEnglishLayoutID(_:) 的全量场景。
final class InputMethodIDRecognitionTests: XCTestCase {

    // MARK: - isChineseID: Apple 已知集合（精确匹配）

    func test_isChineseID_itabc() {
        XCTAssertTrue(InputMethodManager.isChineseID("com.apple.inputmethod.scim.itabc"))
    }

    func test_isChineseID_pinyin() {
        XCTAssertTrue(InputMethodManager.isChineseID("com.apple.inputmethod.scim.pinyin"))
    }

    func test_isChineseID_wbx() {
        XCTAssertTrue(InputMethodManager.isChineseID("com.apple.inputmethod.scim.wbx"))
    }

    func test_isChineseID_tcim_pinyin() {
        XCTAssertTrue(InputMethodManager.isChineseID("com.apple.inputmethod.tcim.pinyin"))
    }

    func test_isChineseID_tcim_zhuyin() {
        XCTAssertTrue(InputMethodManager.isChineseID("com.apple.inputmethod.tcim.zhuyin"))
    }

    func test_isChineseID_tcim_cangjie() {
        XCTAssertTrue(InputMethodManager.isChineseID("com.apple.inputmethod.tcim.cangjie"))
    }

    // MARK: - isChineseID: SCIM 前缀匹配（不在精确集合中的子模式）

    func test_isChineseID_scim_shuangpin() {
        XCTAssertTrue(InputMethodManager.isChineseID("com.apple.inputmethod.scim.shuangpin"))
    }

    func test_isChineseID_scim_wbh() {
        XCTAssertTrue(InputMethodManager.isChineseID("com.apple.inputmethod.scim.wbh"))
    }

    func test_isChineseID_scim_arbitrary_suffix() {
        XCTAssertTrue(InputMethodManager.isChineseID("com.apple.inputmethod.scim.newmode2025"))
    }

    // MARK: - isChineseID: TCIM 前缀匹配

    func test_isChineseID_tcim_arbitrary() {
        XCTAssertTrue(InputMethodManager.isChineseID("com.apple.inputmethod.tcim.jianyi"))
    }

    // MARK: - isChineseID: 关键字匹配（第三方输入法）

    func test_isChineseID_sogou_with_pinyin_keyword() {
        XCTAssertTrue(InputMethodManager.isChineseID("com.sogou.inputmethod.sogou.pinyin"))
    }

    func test_isChineseID_baidu_pinyin() {
        XCTAssertTrue(InputMethodManager.isChineseID("com.baidu.inputmethod.baiduinputios"))
    }

    func test_isChineseID_squirrel_rime() {
        XCTAssertTrue(InputMethodManager.isChineseID("im.rime.inputmethod.squirrel"))
    }

    func test_isChineseID_rime_keyword() {
        XCTAssertTrue(InputMethodManager.isChineseID("org.rime.inputmethod.rime"))
    }

    func test_isChineseID_wubi_keyword() {
        XCTAssertTrue(InputMethodManager.isChineseID("com.example.inputmethod.wubi"))
    }

    func test_isChineseID_cangjie_keyword() {
        XCTAssertTrue(InputMethodManager.isChineseID("com.example.inputmethod.cangjie"))
    }

    func test_isChineseID_zhuyin_keyword() {
        XCTAssertTrue(InputMethodManager.isChineseID("com.example.inputmethod.zhuyin"))
    }

    func test_isChineseID_stroke_keyword() {
        XCTAssertTrue(InputMethodManager.isChineseID("com.example.inputmethod.stroke"))
    }

    func test_isChineseID_chinese_keyword() {
        XCTAssertTrue(InputMethodManager.isChineseID("com.example.chinese.input"))
    }

    func test_isChineseID_shuangpin_keyword() {
        XCTAssertTrue(InputMethodManager.isChineseID("com.example.shuangpin.input"))
    }

    // MARK: - isChineseID: 大小写不敏感（调用者需传入小写，这里验证匹配）

    func test_isChineseID_itabc_already_lowercase() {
        // 函数约定接收 lowercased 输入
        let lower = "com.apple.inputmethod.scim.itabc"
        XCTAssertTrue(InputMethodManager.isChineseID(lower))
    }

    // MARK: - isChineseID: 英文/非中文源 → false

    func test_isChineseID_abc_false() {
        XCTAssertFalse(InputMethodManager.isChineseID("com.apple.keylayout.abc"))
    }

    func test_isChineseID_us_false() {
        XCTAssertFalse(InputMethodManager.isChineseID("com.apple.keylayout.us"))
    }

    func test_isChineseID_british_false() {
        XCTAssertFalse(InputMethodManager.isChineseID("com.apple.keylayout.british"))
    }

    func test_isChineseID_japanese_kotoeri_false() {
        // Kotoeri 日语输入法不应被判断为中文
        XCTAssertFalse(InputMethodManager.isChineseID("com.apple.inputmethod.kotoeri.kanatying.roman"))
    }

    func test_isChineseID_korean_false() {
        XCTAssertFalse(InputMethodManager.isChineseID("com.apple.inputmethod.korean.2setkorean"))
    }

    func test_isChineseID_empty_false() {
        XCTAssertFalse(InputMethodManager.isChineseID(""))
    }

    func test_isChineseID_unknown_false() {
        XCTAssertFalse(InputMethodManager.isChineseID("com.example.unknown.layout"))
    }

    // MARK: - isEnglishLayoutID: 标准 Apple 英文布局

    func test_isEnglishLayoutID_abc() {
        XCTAssertTrue(InputMethodManager.isEnglishLayoutID("com.apple.keylayout.abc"))
    }

    func test_isEnglishLayoutID_us() {
        XCTAssertTrue(InputMethodManager.isEnglishLayoutID("com.apple.keylayout.us"))
    }

    func test_isEnglishLayoutID_british() {
        XCTAssertTrue(InputMethodManager.isEnglishLayoutID("com.apple.keylayout.british"))
    }

    func test_isEnglishLayoutID_australian() {
        XCTAssertTrue(InputMethodManager.isEnglishLayoutID("com.apple.keylayout.australian"))
    }

    func test_isEnglishLayoutID_dvorak() {
        XCTAssertTrue(InputMethodManager.isEnglishLayoutID("com.apple.keylayout.dvorak"))
    }

    func test_isEnglishLayoutID_colemak() {
        XCTAssertTrue(InputMethodManager.isEnglishLayoutID("com.apple.keylayout.colemak"))
    }

    // MARK: - isEnglishLayoutID: 非 keylayout 前缀 → false

    func test_isEnglishLayoutID_inputmethod_false() {
        XCTAssertFalse(InputMethodManager.isEnglishLayoutID("com.apple.inputmethod.scim.itabc"))
    }

    func test_isEnglishLayoutID_third_party_false() {
        XCTAssertFalse(InputMethodManager.isEnglishLayoutID("com.example.keylayout.custom"))
    }

    func test_isEnglishLayoutID_empty_false() {
        XCTAssertFalse(InputMethodManager.isEnglishLayoutID(""))
    }

    // MARK: - isEnglishLayoutID: keylayout 但含中文关键字 → false（理论边界，防御性）

    func test_isEnglishLayoutID_keylayout_with_stroke_keyword_false() {
        // keylayout.stroke 含中文关键词，不应被当作英文布局
        XCTAssertFalse(InputMethodManager.isEnglishLayoutID("com.apple.keylayout.stroke"))
    }

    // MARK: - 相互一致性约束

    func test_consistency_chinese_and_english_mutuallyExclusive() {
        let chineseIDs = [
            "com.apple.inputmethod.scim.itabc",
            "com.apple.inputmethod.scim.pinyin",
            "com.sogou.inputmethod.sogou.pinyin",
        ]
        for id in chineseIDs {
            XCTAssertTrue(InputMethodManager.isChineseID(id),  "Expected Chinese: \(id)")
            XCTAssertFalse(InputMethodManager.isEnglishLayoutID(id), "Should not be English: \(id)")
        }
    }

    func test_consistency_english_notChinese() {
        let englishIDs = [
            "com.apple.keylayout.abc",
            "com.apple.keylayout.us",
            "com.apple.keylayout.british",
        ]
        for id in englishIDs {
            XCTAssertFalse(InputMethodManager.isChineseID(id),  "Should not be Chinese: \(id)")
            XCTAssertTrue(InputMethodManager.isEnglishLayoutID(id), "Expected English: \(id)")
        }
    }
}
