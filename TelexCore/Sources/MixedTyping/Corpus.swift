// Corpus.swift — câu đích của mô phỏng gõ câu trộn Việt–Anh.
//
// File: TelexCore/Corpus/mixed-typing.tsv (sinh bởi Scripts/gen-mixed-typing-corpus.py).
// Dòng: <split>\t<nhóm>\t<câu>\t<mặt nạ>; mặt nạ một ký tự/từ (e = tiếng Anh, v = Việt).
// "Từ" = dãy Character.isLetter liên tiếp; mọi ký tự khác (cách, số, dấu câu) là ranh giới,
// đúng như controller thật (Telex: chữ số cũng kết thúc từ).

import Foundation

public struct MixedSentence: Sendable {
    public let split: String          // "val" | "test"
    public let category: String
    public let text: String
    /// Xen kẽ: gaps[0] word[0] gaps[1] word[1] … word[n-1] gaps[n].
    public let words: [String]
    public let gaps: [String]
    public let english: [Bool]
}

public enum MixedCorpus {
    /// TelexCore/Corpus/mixed-typing.tsv, định vị từ chính file nguồn này (chạy được cả
    /// `swift run` lẫn `swift test`, không cần resource bundle).
    public static var defaultURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // MixedTyping
            .deletingLastPathComponent()      // Sources
            .deletingLastPathComponent()      // TelexCore
            .appendingPathComponent("Corpus/mixed-typing.tsv")
    }

    public static var goldenURL: URL {
        defaultURL.deletingLastPathComponent().appendingPathComponent("mixed-typing-golden.json")
    }

    public static func load(_ url: URL = defaultURL) throws -> [MixedSentence] {
        let text = try String(contentsOf: url, encoding: .utf8)
        var out: [MixedSentence] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("#") { continue }
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count == 4 else { throw CorpusError.malformed(String(line)) }
            let (words, gaps) = tokenize(f[2])
            let mask = Array(f[3])
            guard mask.count == words.count else { throw CorpusError.maskMismatch(f[2]) }
            out.append(MixedSentence(split: f[0], category: f[1], text: f[2], words: words,
                                     gaps: gaps, english: mask.map { $0 == "e" }))
        }
        return out
    }

    public enum CorpusError: Error { case malformed(String), maskMismatch(String) }

    /// Tách câu thành từ (dãy chữ cái) và khoảng xen giữa (có thể rỗng ở hai đầu).
    public static func tokenize(_ s: String) -> (words: [String], gaps: [String]) {
        var words: [String] = [], gaps: [String] = []
        var cur = "", gap = ""
        for ch in s {
            if ch.isLetter {
                if cur.isEmpty { gaps.append(gap); gap = "" }
                cur.append(ch)
            } else {
                if !cur.isEmpty { words.append(cur); cur = "" }
                gap.append(ch)
            }
        }
        if !cur.isEmpty { words.append(cur) }
        gaps.append(gap)
        return (words, gaps)
    }

    static func words(of s: String) -> [String] { tokenize(s).words }

    /// Khoá so sánh không phụ thuộc VỊ TRÍ dấu thanh: "hoà" ≡ "hòa", "thuý" ≡ "thúy" (kiểu bỏ dấu
    /// cũ/mới là cài đặt, không phải lỗi). Phân biệt hoa/thường và mọi dấu khác.
    public static func canon(_ w: String) -> String {
        var base = String.UnicodeScalarView(), tone: Unicode.Scalar?
        for sc in w.decomposedStringWithCanonicalMapping.unicodeScalars {
            switch sc.value {
            case 0x300, 0x301, 0x303, 0x309, 0x323: tone = sc
            default: base.append(sc)
            }
        }
        var s = String(base)
        if let t = tone { s += "#" + String(t.value, radix: 16) }
        return s
    }
}
