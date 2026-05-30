import Foundation

enum CJKVDetector {
    private static let cjkvIDPrefixes: Set<String> = [
        "com.apple.inputmethod.korean.",
        "com.apple.inputmethod.kotoeri.",
        "com.apple.inputmethod.scim.",
        "com.apple.inputmethod.tcim.",
        "com.apple.inputmethod.tyim.",
        "com.apple.inputmethod.vi.",
        "com.apple.keylayout.2setkorean",
        "com.apple.keylayout.3setkorean",
        "com.apple.keylayout.korean.",
        "com.apple.keylayout.russian.",
    ]

    private static let cjkvKeywords: Set<String> = [
        "chinese", "pinyin", "scim", "tcim", "sogou", "wubi", "baidu",
        "shuangpin", "rime", "squirrel", "cangjie", "zhuyin", "stroke", "itabc",
        "korean", "kotoeri", "hiragana", "katakana",
        "russian", "vietnamese", "tyim",
    ]

    static func isCJKV(sourceID: String) -> Bool {
        let lower = sourceID.lowercased()
        if cjkvIDPrefixes.contains(where: { lower.hasPrefix($0) }) {
            return true
        }
        return cjkvKeywords.contains(where: { lower.contains($0) })
    }

    static func isEnglishLayout(sourceID: String) -> Bool {
        let lower = sourceID.lowercased()
        guard lower.hasPrefix("com.apple.keylayout.") else { return false }
        return !isCJKV(sourceID: lower)
    }
}
