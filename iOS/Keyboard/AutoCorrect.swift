// AutoCorrect — TỰ SỬA TỪ GÕ SAI (Thử nghiệm, mặc định TẮT — maintainer 27/09/2026).
// Port 1:1 Android AutoCorrect.kt.
//
// Chỉ ở ranh giới từ (`triggers`), chỉ khi từ vừa gõ KHÔNG là âm tiết Việt (kể cả dạng
// thiếu dấu / tiền tố — người gõ không dấu) và không là từ đã biết (tiếng Anh, từ người
// dùng, Thay thế văn bản / danh bạ, từng hoàn tác). Ứng viên = thay ĐÚNG MỘT phím bằng
// phím kề (AdjacentKeyFixer.oneEditCandidates) mà điểm chạm thật nghiêng về phím đó
// (`evidence`), hoặc bỏ một phím chạm đúp ("anhh" → anh, `repeatCandidates`); chỉ sửa khi ứng
// viên đủ phổ biến VÀ bỏ xa ứng viên thứ hai (`Params`). Thanh gợi ý tô nền đúng bản sửa này
// (ONBOARDING-SPEC §8, `plan` + `decide` dùng chung với dấu cách).
// Không có điểm chạm (từ vuốt, từ mở lại, bàn phím cứng) ⇒ không sửa. ⌫ ngay sau đó trả
// lại chữ gốc. Ngưỡng dò bằng Android AutoCorrectEvalTests (mô phỏng chạm TouchSim).
#if canImport(UIKit)
import UIKit
#endif
import Foundation
import TelexCore

enum AutoCorrect {
    /// `minFreq`: tần suất lexicon (0–255) tối thiểu của ứng viên — chỉ từ phổ biến (không,
    /// này, tôi…; "phím" = 120 không đủ); `margin`: hơn tần suất ứng viên thứ hai ít nhất bấy
    /// nhiêu; `minEv`: điểm chạm phải lệch về phía phím sửa ít nhất bấy nhiêu (`evidence`) —
    /// không thì loại ứng viên đó (cũng không tính là đối thủ).
    struct Params: Equatable {
        let minLen: Int
        let minFreq: Int
        let margin: Int
        let minEv: Float
    }

    // Dò trên DEV (27/09/2026): P 98.4% R 26.8%. Hạ ngưỡng tần suất (kể cả khi chỉ một ứng
    // viên) hay cộng điểm theo độ lệch chạm đều tụt P dưới 97%. 18/10/2026 (vnlexicon tần suất
    // corpus hội thoại): 170 → 175 giữ P DEV 98.7% (170: 98.0%; cũ 98.8%), R 26.8 → 27.0%. GIỮ Y HỆT bản Kotlin.
    static let defaults = Params(minLen: 3, minFreq: 175, margin: 30, minEv: 0.1)

    /// Điểm chạm của một phím: lệch so với TÂM phím đã ra, theo cỡ mặt phím (x phải, y xuống).
    struct Touch: Equatable {
        let dx: Float
        let dy: Float
    }

    /// Điểm chạm lệch về phía phím `to` bao nhiêu (so với phím đã ra `from`): hình chiếu lên
    /// vectơ tâm→tâm, 0 = giữa phím, ~0.5 = sát mép giáp phím kia.
    static func evidence(_ t: Touch, from: Character, to: Character) -> Float {
        guard let a = AdjacentKeyFixer.keyPosition(from), let b = AdjacentKeyFixer.keyPosition(to) else { return 0 }
        let dc = Float(b.x - a.x), dr = Float(b.row - a.row)
        return (t.dx * dc + t.dy * dr) / (dc * dc + dr * dr)
    }

    /// Ranh giới được sửa: khoảng trắng (không Enter — có thể đã gửi tin, không hoàn tác
    /// được) và dấu câu chắc chắn kết thúc từ. KHÔNG . : ' ’ " (tên miền, giờ, "don't").
    static func triggers(_ boundary: String) -> Bool {
        guard let c = boundary.first else { return false }
        return c == " " || c == "\u{00A0}" || ",;!?)".contains(c)
    }

    /// Chữ trước từ (`before` = context đã bỏ từ) là đầu câu: rỗng hoặc sau . ! ? xuống dòng.
    static func isSentenceStart(_ before: String) -> Bool {
        var t = Substring(before)
        while let l = t.last, l == " " || l == "\u{00A0}" || l == "\t" { t = t.dropLast() }
        guard let l = t.last else { return true }
        return ".!?\n…".contains(l)
    }

    /// Chữ hoa: hoa đầu chỉ nhận ở ĐẦU CÂU (giữa câu = tên riêng); hơn một chữ hoa (VN, HCM,
    /// CamelCase) ⇒ không sửa.
    static func caseAllows(_ raw: String, sentenceStart: Bool) -> Bool {
        let upper = raw.filter(\.isUppercase).count
        if upper == 0 { return true }
        return upper == 1 && raw.first?.isUppercase == true && sentenceStart
    }

    #if canImport(UIKit)   // macOS (App target, CaretSuggestions.swift) không có FieldTraits
    /// Ô được tự sửa: không mật khẩu / passthrough (email, URL, username, OTP), ô app xin
    /// tắt autocorrect, omnibox, ô số, ô tên người (tên riêng).
    static func fieldAllows(_ f: FieldTraits) -> Bool {
        guard !f.secure, !f.passthrough, f.allowsSuggestions, f.inputKind == .normal,
              f.keyboardType != .webSearch else { return false }
        if let c = f.contentType, nameTypes.contains(c) { return false }
        return true
    }
    private static let nameTypes: Set<UITextContentType> = [
        .name, .givenName, .middleName, .familyName, .namePrefix, .nameSuffix, .nickname,
        .organizationName, .username, .emailAddress, .URL, .telephoneNumber,
    ]
    #endif

    /// Từ tiếng Anh (enlexicon + từ mở mạch tiếng Anh của engine) — không sửa sang tiếng Việt.
    static func isEnglish(_ w: String) -> Bool {
        SwipeEnglish.contains(w) || EnglishContextLookup.opensEnglishRun(w)
    }

    /// Từ đã hoàn tác tự sửa (chữ thường) — nhớ tối đa `cap` từ gần nhất. Lưu dạng dòng.
    final class Rejected {
        private var order: [String] = []
        private var set: Set<String> = []
        private let cap: Int
        init(cap: Int = 300) { self.cap = cap }
        func contains(_ w: String) -> Bool { set.contains(w.lowercased()) }
        /// true nếu mới thêm (caller lưu).
        @discardableResult
        func add(_ w: String) -> Bool {
            let k = w.lowercased()
            guard !k.isEmpty, set.insert(k).inserted else { return false }
            order.append(k)
            while order.count > cap { set.remove(order.removeFirst()) }
            return true
        }
        var count: Int { order.count }
        func encode() -> String { order.joined(separator: "\n") }
        static func decode(_ s: String?, cap: Int = 300) -> Rejected {
            let r = Rejected(cap: cap)
            for line in (s ?? "").split(separator: "\n") {
                let t = line.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { r.add(t) }
            }
            return r
        }
    }

    /// Chọn ứng viên theo `p`; nil = không đủ chắc. `touches`: điểm chạm từng phím của `lower`.
    /// Ứng viên chạm đúp (`Candidate.deletion`) không cần bằng chứng hướng chạm nhưng chỉ là PHƯƠNG ÁN
    /// SAU: chỉ xét khi không ứng viên thay phím nào có bằng chứng chạm (trộn chung thì tụt precision:
    /// P TEST 97.3% → 96.5%, Android AutoCorrectEvalTests 05/11/2026).
    static func pick(lower: String, cands: [AdjacentKeyFixer.Candidate], touches: [Touch],
                     p: Params = defaults) -> AdjacentKeyFixer.Candidate? {
        let chars = Array(lower)
        var slips: [String: AdjacentKeyFixer.Candidate] = [:]     // theo từ (cùng từ ⇒ cùng tần suất)
        var repeats: [String: AdjacentKeyFixer.Candidate] = [:]
        for c in cands {
            guard c.pos < touches.count, c.pos < chars.count else { continue }
            if c.deletion { if repeats[c.word] == nil { repeats[c.word] = c }; continue }
            guard evidence(touches[c.pos], from: chars[c.pos], to: c.key) >= p.minEv else { continue }   // chạm không nghiêng về phím này
            if slips[c.word] == nil { slips[c.word] = c }
        }
        return confident(Array((slips.isEmpty ? repeats : slips).values), p: p)
    }

    /// Ứng viên phổ biến nhất nếu đủ phổ biến VÀ bỏ xa ứng viên thứ hai.
    private static func confident(_ cands: [AdjacentKeyFixer.Candidate], p: Params) -> AdjacentKeyFixer.Candidate? {
        let sorted = cands.sorted { $0.freq != $1.freq ? $0.freq > $1.freq : $0.word < $1.word }
        guard let top = sorted.first, top.freq >= p.minFreq else { return nil }
        if sorted.count > 1, top.freq - sorted[1].freq < p.margin { return nil }
        return top
    }

    /// Ứng viên CHẠM ĐÚP: một phím bị bấm hai lần liền ("anhh" → anh) — bỏ phím lặp thứ hai. Hai lần
    /// chạm cùng một phím nên không có hướng lệch để làm bằng chứng; vẫn qua cùng ngưỡng tần suất /
    /// khoảng cách (`pick`). Bỏ qua phím mà gõ đôi có nghĩa trong Telex (`telexDoubles`: aa ee oo dd
    /// ww, phím thanh gõ lại để bỏ dấu).
    static func repeatCandidates(_ lower: String, compose: (String) -> String,
                                 frequency: (String) -> Int?) -> [AdjacentKeyFixer.Candidate] {
        let c0 = Array(lower)
        let current = compose(lower)
        var out: [AdjacentKeyFixer.Candidate] = []
        for i in c0.indices.dropFirst() where c0[i] == c0[i - 1] && !telexDoubles.contains(c0[i]) {
            var c = c0; c.remove(at: i)
            let w = compose(String(c))
            guard w != current, let f = frequency(w) else { continue }
            out.append(.init(word: w, freq: f, pos: i, key: c0[i], deletion: true))
        }
        return out
    }
    private static let telexDoubles = Set("aeodwsfrxjz")

    /// Phần THUẦN, không cần trạng thái của tự sửa (chạy được ở hàng đợi nền cùng thanh gợi ý): từ
    /// đang soạn `raw` có phải từ gõ sai không và các ứng viên sửa. nil = không sửa (từ hợp lệ /
    /// đang gõ dở một từ / quá ngắn / có ký tự không phải chữ).
    struct Plan {
        let raw: String
        let lower: String
        let current: String
        let cands: [AdjacentKeyFixer.Candidate]
    }

    static func plan(raw: String, compose: (String) -> String, frequency: (String) -> Int?,
                     hasCompletion: (String) -> Bool, p: Params = defaults) -> Plan? {
        guard (p.minLen...10).contains(raw.count), raw.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        let lower = raw.lowercased()
        let current = compose(lower)
        if frequency(current) != nil || hasCompletion(current) { return nil }
        let cands = AdjacentKeyFixer.oneEditCandidates(lower, compose: compose, frequency: frequency,
                                                       hasCompletion: hasCompletion)
            + repeatCandidates(lower, compose: compose, frequency: frequency)
        return Plan(raw: raw, lower: lower, current: current, cands: cands)
    }

    /// QUYẾT ĐỊNH sửa cho `plan` — dùng CHUNG cho ô tô nền trên thanh gợi ý và dấu cách
    /// (ONBOARDING-SPEC §8: dấu cách không bao giờ ra chữ khác ô đã tô). `isKnown`: dạng chữ thường
    /// (phím thô VÀ dạng hiển thị) là từ đã biết — tiếng Anh / từ người dùng / từng hoàn tác ⇒ không sửa.
    static func decide(_ plan: Plan, touches: [Touch], isKnown: (String) -> Bool,
                       p: Params = defaults) -> String? {
        guard touches.count == plan.raw.count else { return nil }
        if isKnown(plan.lower) { return nil }
        if plan.current != plan.lower, isKnown(plan.current.lowercased()) { return nil }
        guard let best = pick(lower: plan.lower, cands: plan.cands, touches: touches, p: p) else { return nil }
        if plan.raw.first?.isUppercase == true, let f = best.word.first {
            return f.uppercased() + best.word.dropFirst()
        }
        return best.word
    }

    /// Bản sửa cho từ vừa gõ (phím thô `raw`) hoặc nil — `plan` rồi `decide`.
    static func correction(raw: String, touches: [Touch],
                           compose: (String) -> String,
                           frequency: (String) -> Int?,
                           hasCompletion: (String) -> Bool,
                           isKnown: (String) -> Bool,
                           p: Params = defaults) -> String? {
        guard touches.count == raw.count,
              let plan = plan(raw: raw, compose: compose, frequency: frequency, hasCompletion: hasCompletion, p: p)
        else { return nil }
        return decide(plan, touches: touches, isKnown: isKnown, p: p)
    }
}
