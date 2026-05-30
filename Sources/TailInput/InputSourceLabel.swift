import Foundation

enum InputSourceLabel {
    private static let labelMap: [String: String] = [
        // Korean
        "com.apple.inputmethod.Korean.2SetKorean": "한",
        "com.apple.inputmethod.Korean.3SetKorean": "한",
        "com.apple.inputmethod.Korean.390Sebulshik": "한",
        "com.apple.inputmethod.Korean.GongjinCheongRomaja": "한",
        "com.apple.inputmethod.Korean.HNCRomaja": "한",

        // Japanese
        "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese": "あ",
        "com.apple.inputmethod.Kotoeri.KanaTyping.Japanese": "あ",

        // English layouts
        "com.apple.keylayout.ABC": "A",
        "com.apple.keylayout.US": "US",
        "com.apple.keylayout.USExtended": "A",
        "com.apple.keylayout.British": "GB",
        "com.apple.keylayout.British-PC": "GB",
        "com.apple.keylayout.Australian": "AU",
        "com.apple.keylayout.Canadian": "CA",
        "com.apple.keylayout.Dvorak": "DV",
        "com.apple.keylayout.Colemak": "CO",
        "com.apple.keylayout.ABC-India": "IN",

        // TCIM (Traditional Chinese)
        "com.apple.inputmethod.TCIM.Cangjie": "倉",
        "com.apple.inputmethod.TCIM.Pinyin": "繁拼",
        "com.apple.inputmethod.TCIM.Shuangpin": "雙",
        "com.apple.inputmethod.TCIM.WBH": "畫",
        "com.apple.inputmethod.TCIM.Jianyi": "速",
        "com.apple.inputmethod.TCIM.Zhuyin": "注",
        "com.apple.inputmethod.TCIM.ZhuyinEten": "注",

        // TYIM (Cantonese)
        "com.apple.inputmethod.TYIM.Sucheng": "速",
        "com.apple.inputmethod.TYIM.Stroke": "畫",
        "com.apple.inputmethod.TYIM.Phonetic": "粤拼",
        "com.apple.inputmethod.TYIM.Cangjie": "倉",

        // SCIM (Simplified Chinese)
        "com.apple.inputmethod.SCIM.WBX": "五",
        "com.apple.inputmethod.SCIM.WBH": "画",
        "com.apple.inputmethod.SCIM.Shuangpin": "双",
        "com.apple.inputmethod.SCIM.ITABC": "拼",
    ]

    // 按优先级排列：品牌名在前，通用词在后
    private static let fallbackRules: [(keyword: String, label: String)] = [
        ("squirrel", "鼠"),
        ("sogou", "搜"),
        ("baidu", "百"),
        ("rime", "鼠"),
        ("wubi", "五"),
        ("shuangpin", "双"),
        ("cangjie", "倉"),
        ("zhuyin", "注"),
        ("korean", "한"),
        ("japanese", "あ"),
        ("vietnamese", "VI"),
        ("russian", "RU"),
        ("pinyin", "拼"),
    ]

    static func shortLabel(for sourceID: String, localizedName: String? = nil) -> String {
        if let label = labelMap[sourceID] {
            return label
        }

        let lowerID = sourceID.lowercased()
        for (keyword, label) in fallbackRules {
            if lowerID.contains(keyword) {
                return label
            }
        }

        if let name = localizedName {
            if name.contains("拼音") || name.lowercased().contains("pinyin") { return "拼" }
            if name.contains("五笔") || name.lowercased().contains("wubi") { return "五" }
            if name.contains("双拼") || name.lowercased().contains("shuangpin") { return "双" }
            if name.contains("仓颉") || name.lowercased().contains("cangjie") { return "倉" }
            if name.contains("注音") || name.lowercased().contains("zhuyin") { return "注" }
            if name.contains("韩") || name.lowercased().contains("korean") { return "한" }
            if name.contains("日") || name.lowercased().contains("japanese") { return "あ" }
            if #available(macOS 13, *) {
                if let first = name.first { return String(first) }
            } else {
                return String(name.prefix(1))
            }
        }

        return "?"
    }
}
