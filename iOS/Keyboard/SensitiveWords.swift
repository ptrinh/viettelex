// SensitiveWords — bộ lọc từ tục/nhạy cảm khỏi THANH GỢI Ý (chuẩn ngành:
// Gboard/SwiftKey đều chặn mặc định). Từ vẫn nằm trong datastore và vẫn được
// HỌC bình thường — chỉ không chủ động gợi ý khi bộ lọc bật. Từ bạo lực phổ
// thông (cướp, giết, trộm — từ vựng báo chí/đời thường) KHÔNG nằm trong lọc.
// Cặp chửi/tục ghép từ hai TỪ THƯỜNG (thằng chó, sờ chim, nâng bi…) lọc theo từ không chặn được ⇒
// bảng cặp `pairs` (SensitivePairs, sinh từ Scripts/seed-curated.txt [sensitive-bigram]): lọc bật
// thì từ đó không được gợi ý NGAY SAU từ trước tương ứng (`filter(_:after:enabled:)`) và cặp không
// thưởng ngữ cảnh (`dropPairs` — vuốt, xếp gợi ý đang gõ, Thêm dấu).
// Bộ ba (19/10/2026, [sensitive-trigram]): "ngu như chó", "thằng mất dạy", "óc bã đậu"… — cặp cuối là cụm
// thường ⇒ chặn ở mức BA từ (`triples`, cần `prev2`); `chains` = chuỗi seed ba từ (từ kế tiếp đứng đầu sau
// đúng hai từ đó, `SuggestRank.nextFill(chain:)`) — lọc bật thì chuỗi nhạy cảm bị `filter` bỏ như mọi gợi ý.
import Foundation

enum SensitiveWords {
    static func filter(_ words: [String], enabled: Bool) -> [String] {
        enabled ? words.filter { !set.contains($0.lowercased()) } : words
    }

    /// Gợi ý cho vị trí đứng SAU `prev` (từ kế tiếp / hoàn thành từ / phương án vuốt): bỏ từ nhạy cảm,
    /// từ tạo cặp nhạy cảm với `prev` (`pairs`) và từ tạo bộ ba nhạy cảm với (`prev2`, `prev`)
    /// (`triples` — "ngu như" → chó; cặp "như chó" vẫn hiện). Tắt lọc ⇒ nguyên văn.
    static func filter(_ words: [String], after prev: String?, prev2: String? = nil, enabled: Bool) -> [String] {
        guard enabled else { return words }
        let gated = prev.flatMap { pairs[$0.lowercased()] }
        let gated3 = tripleGate(prev2, prev)
        return words.filter { w in
            let l = w.lowercased()
            return !set.contains(l) && gated?.contains(l) != true && gated3?.contains(l) != true
        }
    }

    /// Chỉ phần CẶP / BỘ BA — cho tập ngữ cảnh (từ kế tiếp cá nhân/seed làm điểm thưởng): lọc bật ⇒ cặp
    /// (bộ ba) nhạy cảm sau `prev` (`prev2 prev`) không thưởng (vd "sờ" không đẩy "chim" khi vuốt / gõ dở).
    static func dropPairs(_ words: [String], after prev: String?, prev2: String? = nil, enabled: Bool) -> [String] {
        guard enabled else { return words }
        let g = prev.flatMap { pairs[$0.lowercased()] }, g3 = tripleGate(prev2, prev)
        guard g != nil || g3 != nil else { return words }
        return words.filter { w in
            let l = w.lowercased()
            return g?.contains(l) != true && g3?.contains(l) != true
        }
    }

    /// (prev, word) có trong bảng cặp nhạy cảm (không phân biệt hoa/thường).
    static func isPair(_ prev: String?, _ word: String) -> Bool {
        guard let prev else { return false }
        return pairs[prev.lowercased()]?.contains(word.lowercased()) == true
    }

    /// (prev2, prev, word) có trong bảng bộ ba nhạy cảm (không phân biệt hoa/thường).
    static func isTriple(_ prev2: String?, _ prev: String?, _ word: String) -> Bool {
        tripleGate(prev2, prev)?.contains(word.lowercased()) == true
    }

    /// Chuỗi seed ba từ sau (`prev2`, `prev`) — CHƯA lọc (người gọi lọc bằng `filter(_:after:prev2:enabled:)`).
    static func chain(after prev: String?, prev2: String?) -> [String] {
        guard let prev, let prev2, !chains.isEmpty else { return [] }
        return chains[prev2.lowercased() + " " + prev.lowercased()] ?? []
    }

    private static func tripleGate(_ prev2: String?, _ prev: String?) -> Set<String>? {
        guard let prev, let prev2 else { return nil }
        return triples[prev2.lowercased() + " " + prev.lowercased()]
    }

    static let set: Set<String> = [
        "đcm", "đm", "dm", "dcm", "vcl", "vkl", "vl", "cl", "clgt", "cmnr",
        "cứt", "lồn", "cặc", "buồi", "đĩ", "điếm", "đụ", "địt",
        "tml", "sml", "dâm", "đkm", "dkm", "buscu",
        "đéo", "nứng", "chịch", "trym", "loz", "cmm", "cmn", "đmm", "dmm", "đcmm", "dcmm", "clm", "clg", "vcc", "dume",
        "cc", "đb", "lìn", "fuckboy",
        "fuck", "shit", "bitch", "wtf", "motherfucker", "asshole", "bullshit", "dick", "dickhead", "pussy",
        "bastard", "dumbass", "fucking", "fucked", "fucker", "shitty", "stfu",
    ]

    /// Phần tiếng Anh của `set` (⊂ set, test). enlexicon.bin chặn hết từ tục tiếng Anh (gen-enlexicon
    /// BLOCK) ⇒ gợi ý tiếng Anh trên máy tính lấy từ đây khi TẮT lọc (WordPrediction.candidates);
    /// từ nhẹ (damn, hell, piss) KHÔNG lọc. Song sinh windows word_prediction.cpp kEnglishVulgar.
    static let english: [String] = [
        "asshole", "bastard", "bitch", "bullshit", "dick", "dickhead", "dumbass", "fuck", "fucked", "fucker",
        "fucking", "motherfucker", "pussy", "shit", "shitty", "stfu", "wtf",
    ]
    /// Tần suất (thang enlexicon 0–255) khi trộn `english` vào gợi ý tiếng Anh lúc TẮT lọc — như sàn
    /// vuốt từ tục (SwipeVocab.sensitiveFloor): sau từ thường phổ biến cùng tiền tố ("fu" → full, fun…),
    /// lên đầu khi tiền tố đủ riêng ("fuc" → fuck).
    static let englishFreq = 150

    // BEGIN GENERATED SensitivePairs — Scripts/gen-seed-data.py từ Scripts/seed-curated.txt [sensitive-bigram] / [trigram] / [sensitive-trigram]; KHÔNG sửa tay.
    static let pairs: [String: Set<String>] = [
        "bú": ["cu"],
        "bố": ["mày"],
        "chó": ["chết", "má"],
        "chúa": ["phòng"],
        "chơi": ["cave", "gái"],
        "clip": ["nóng"],
        "cái": ["mâm"],
        "cò": ["hương"],
        "damn": ["it"],
        "fuck": ["boy"],
        "kích": ["dục"],
        "láo": ["chó"],
        "lùn": ["tịt"],
        "lộ": ["clip"],
        "massage": ["kích"],
        "má": ["mày"],
        "móc": ["lốp"],
        "mẹ": ["mày"],
        "như": ["cột"],
        "nâng": ["bi"],
        "não": ["phẳng"],
        "nện": ["nhau"],
        "phang": ["nhau"],
        "phim": ["heo"],
        "piss": ["off"],
        "quay": ["tay"],
        "rờ": ["cu"],
        "sờ": ["chim", "cu"],
        "thằng": ["chó", "khốn", "mặt", "ngu", "điên"],
        "vãi": ["đái"],
        "xoạc": ["nhau"],
        "óc": ["lợn"],
        "đù": ["má"],
        "đậu": ["má"],
        "đồ": ["chó", "khốn", "ngu", "điên"],
    ]
    /// Chuỗi seed BA từ ("prev2 prev" → từ kế tiếp, nặng trước; [trigram] + [sensitive-trigram] trọng-số > 0):
    /// từ kế tiếp đứng đầu sau đúng hai từ đó (`chain`) — gọi qua `filter(_:after:prev2:enabled:)`.
    static let chains: [String: [String]] = [
        "bố mày": ["đây"],
        "bố tiên": ["sư"],
        "cha mày": ["chứ"],
        "con đĩ": ["mẹ"],
        "cái máu": ["lồn"],
        "cút con": ["mẹ"],
        "mả cha": ["mày"],
        "mặt dày": ["vãi"],
        "mặt lồn": ["ra"],
        "mẹ kiếp": ["mày"],
        "ngu như": ["chó", "lợn"],
        "real hay": ["fake"],
        "thằng ất": ["ơ"],
        "tiên sư": ["bố"],
        "tổ cha": ["mày"],
        "vãi cả": ["lồn", "chưởng"],
        "óc bã": ["đậu"],
        "ông mày": ["đây"],
        "đcm thằng": ["này"],
        "đéo ai": ["thèm"],
        "đéo hiểu": ["sao"],
        "địt con": ["mẹ"],
        "địt cụ": ["mày"],
        "đồ chó": ["má"],
        "đồ ăn": ["hại"],
    ]
    /// Bộ ba nhạy cảm ("prev2 prev" → từ): lọc bật ⇒ không gợi ý từ đó sau đúng hai từ (cặp prev → từ vẫn hiện).
    static let triples: [String: Set<String>] = [
        "bố mày": ["đây"],
        "bố tiên": ["sư"],
        "cha mày": ["chứ"],
        "con mất": ["dạy"],
        "con đĩ": ["mẹ"],
        "câm mồm": ["lại"],
        "cút con": ["mẹ"],
        "im mồm": ["đi"],
        "mả cha": ["mày"],
        "mặt dày": ["vãi"],
        "mặt lồn": ["ra"],
        "mẹ kiếp": ["mày"],
        "ngu như": ["bò", "chó", "lợn"],
        "thằng khốn": ["nạn"],
        "thằng mất": ["dạy"],
        "thằng ất": ["ơ"],
        "tiên sư": ["bố"],
        "tổ cha": ["mày"],
        "vcl thật": ["sự"],
        "óc bã": ["đậu"],
        "ông mày": ["đây"],
        "đcm thằng": ["này"],
        "đm cuộc": ["đời"],
        "đéo ai": ["thèm"],
        "đéo hiểu": ["sao"],
        "đéo quan": ["tâm"],
        "địt con": ["mẹ"],
        "địt cụ": ["mày"],
        "đồ con": ["lợn"],
        "đồ khốn": ["nạn"],
        "đồ mất": ["dạy"],
        "đồ ăn": ["hại"],
    ]
    // END GENERATED SensitivePairs
}
