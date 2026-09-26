// SwipeTyping.swift — glue gõ vuốt giữa KeyboardView (đường vuốt) và EngineBridge
// (chèn/seed từ). Không UIKit: test được với MockProxy (SwipeTypingTests).
//
// Luồng: KeyboardView phân loại chạm→vuốt (GestureClassifier) → `begin` HUỶ chữ
// đầu đã chèn lúc chạm xuống (checkpoint engine, không ⌫) → nhấc tay → `finish`:
// decode top-5 dạng không dấu (ngữ cảnh = từ kế tiếp hay gặp sau từ trước, theo
// UserLangModel) → expand dạng thắng thành âm tiết có dấu → chèn top-1 (dấu cách
// treo + seed engine, xem EngineBridge.insertSwipeWord) → thanh gợi ý hiện biến thể.
//
// SwipeDecoder KHÔNG thread-safe: MỌI truy cập đi qua một hàng đợi serial (`queue`);
// prepare() chạy nền ở đó, decode gọi `queue.sync` từ main (lần vuốt đầu ngay sau khi
// hiện bàn phím có thể chờ prepare xong — vài chục ms, một lần).
import Foundation

final class SwipeTyping {
    struct Outcome: Equatable {
        /// Từ trước đó vừa được chốt (để caller học), nếu có.
        let committed: EngineBridge.SettledCommit?
        /// Từ đã chèn (đã áp chữ hoa).
        let word: String
        /// Phương án khác cho thanh gợi ý (đã áp chữ hoa), ≤ 3.
        let alternatives: [String]
    }

    private let decoder = SwipeDecoder()
    private let queue = DispatchQueue(label: "com.viettelex.swipe", qos: .userInitiated)
    /// Layout lần cuối đã gửi xuống hàng đợi (chỉ đọc/ghi trên main).
    private(set) var layout: SwipeLayout?

    /// Điểm ngữ cảnh (log-domain, GIỐNG bản Android): +1.5 nếu là từ kế tiếp hay gặp
    /// sau từ trước (UserLangModel.nextWords); +0.4·ln(1+count) cho từ hay gõ, trần 1.5.
    static let nextWordBonus: Float = 1.5
    static let personalWeight: Float = 0.4
    static let personalCap: Float = 1.5

    /// Điểm ngữ cảnh của một âm tiết có dấu.
    static func contextScore(_ w: String, next: Set<String>, count: (String) -> Int) -> Float {
        let c = count(w)
        let personal = c > 0 ? min(personalCap, personalWeight * log(1 + Float(c))) : 0
        return (next.contains(w) ? nextWordBonus : 0) + personal
    }

    /// Đặt layout (khác lần trước mới gửi); `prepare` = dựng template ngay ở nền.
    func setLayout(_ l: SwipeLayout, prepare: Bool) {
        guard l != layout else { return }
        layout = l
        let d = decoder
        queue.async {
            d.setLayout(l)
            if prepare { d.prepare() }
        }
    }

    /// Cú vuốt bắt đầu: huỷ chữ đầu (đã chèn lúc chạm xuống). Không huỷ được (màn hình
    /// lệch) ⇒ ⌫ như iPad vuốt xuống.
    func begin(bridge: EngineBridge, proxy: TextProxyLike) {
        if !bridge.undoLastLetter(proxy: proxy) {
            TouchLog.write("swipe: undo chữ đầu thất bại → ⌫")
            bridge.backspace(proxy: proxy)
        }
    }

    /// Giải mã (đồng bộ trên hàng đợi decoder) → dạng thắng + phương án.
    /// `contextWords` = từ hay theo sau từ trước (UserLangModel.nextWords), có dấu;
    /// `count` = số lần user đã gõ một âm tiết (UserLangModel.count).
    func resolve(_ path: SwipePath, contextWords: [String], count: @escaping (String) -> Int = { _ in 0 },
                 case sc: SwipeCase) -> (word: String, alternatives: [String])? {
        guard layout != nil, path.count >= 2 else { return nil }
        let next = Set(contextWords.map { $0.lowercased() })
        let d = decoder
        // Dạng không dấu: điểm = điểm tốt nhất trong các âm tiết của nó (tối đa 8).
        let folded: (String) -> Float = { f in
            var best: Float = 0
            for w in SwipeDecoder.expand(f, limit: 8) {
                best = max(best, Self.contextScore(w.word, next: next, count: count))
            }
            return best
        }
        let cands = queue.sync { d.decode(path, topK: 5, context: folded) }
        return Self.pick(cands.map(\.folded), contextWords: next, count: count, case: sc)
    }

    /// Phần thuần: từ top-K dạng không dấu → từ chèn + phương án. Phương án = các biến
    /// thể dấu khác của dạng thắng xen với top-1 có dấu của dạng không dấu hạng 2/3
    /// (vd. vuốt "cho": chó · co · chờ).
    static func pick(_ folded: [String], contextWords: Set<String>,
                     count: @escaping (String) -> Int = { _ in 0 }, case sc: SwipeCase)
        -> (word: String, alternatives: [String])? {
        let ctx: (String) -> Float = { contextScore($0, next: contextWords, count: count) }
        guard let top = folded.first else { return nil }
        let expanded = SwipeDecoder.expand(top, limit: 6, context: ctx)
        guard let best = expanded.first else { return nil }
        let variants = expanded.dropFirst().map(\.word)
        let others = folded.dropFirst().prefix(2).compactMap {
            SwipeDecoder.expand($0, limit: 1, context: ctx).first?.word
        }
        var alts: [String] = []
        var vi = variants.makeIterator(), oi = others.makeIterator()
        while alts.count < 3 {
            var added = false
            for next in [vi.next(), oi.next()] {
                guard let w = next else { continue }
                added = true
                if w != best.word, !alts.contains(w), alts.count < 3 { alts.append(w) }
            }
            if !added { break }
        }
        return (sc.apply(best.word), alts.map(sc.apply))
    }

    /// Nhấc tay: giải mã rồi chèn. nil = không nhận ra gì (không đụng màn hình).
    func finish(_ path: SwipePath, case sc: SwipeCase, contextWords: [String],
                count: @escaping (String) -> Int = { _ in 0 },
                bridge: EngineBridge, proxy: TextProxyLike) -> Outcome? {
        guard let r = resolve(path, contextWords: contextWords, count: count, case: sc) else {
            TouchLog.write("swipe: không có ứng viên (pts=\(path.count))")
            return nil
        }
        let committed = bridge.insertSwipeWord(r.word, proxy: proxy)
        if TouchLog.enabled {
            TouchLog.write(String(format: "swipe: pts=%d len=%.0f ms=%.0f alts=%d",
                                  path.count, path.length, path.duration * 1000, r.alternatives.count))
        }
        return Outcome(committed: committed, word: r.word, alternatives: r.alternatives)
    }

    /// Bỏ dấu tiếng Việt (đ → d), chữ thường — khoá so với dạng không dấu của lexicon.
    static func fold(_ w: String) -> String {
        w.lowercased().replacingOccurrences(of: "đ", with: "d")
            .folding(options: .diacriticInsensitive, locale: nil)
    }
}
