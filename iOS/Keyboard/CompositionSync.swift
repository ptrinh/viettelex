// CompositionSync — logic THUẦN (không UIKit) quyết định từ đang gõ dở còn khớp
// với chữ thật trước con trỏ hay không. Hai việc:
//
// 1. KHÔNG RESET MÙ. Trước đây mọi textWillChange ngoài handle() đều reset engine.
//    Host tự gán lại text mỗi phím (ô tìm kiếm App Store…) gửi textWillChange MUỘN,
//    lúc applyingEdit đã false → reset giữa từ → "không gõ được tiếng Việt". Giờ chỉ
//    reset khi ngữ cảnh LỆCH: context trước con trỏ không còn kết thúc bằng từ đang
//    gõ (con trỏ dời, chọn text, đổi ô, host xoá ô…).
// 2. FAIL-SAFE TRƯỚC KHI XOÁ NHIỀU. deleteBackward × N chỉ an toàn khi N ký tự cuối
//    đúng là thứ mình định xoá; lệch thì xoá lan sang chữ của người dùng. Kiểm
//    context kết thúc bằng nội dung dự kiến trước khi xoá (ý tưởng MirrorSync của
//    dictus-ios: đọc context trước/sau edit trong cùng runloop).
//
// Về nil: iOS 16+ có host trả documentContextBeforeInput = nil thay cho "" (azooKey
// adjustLeftString) — nil = KHÔNG BIẾT, không phải "ô trống". Không biết thì giữ
// đúng hành vi cũ: reset ở (1), cho xoá ở (2). Chỉ khi context CÓ và LỆCH mới chặn.
// So khớp bằng String.hasSuffix (tương đương chuẩn Unicode: host đổi NFC/NFD vẫn khớp).
import Foundation

enum CompositionSync {

    enum Verdict: Equatable {
        /// Context vẫn kết thúc bằng từ đang gõ → giữ composition.
        case keep
        /// Lệch (hoặc không có gì để giữ) → reset engine + ngữ cảnh.
        case reset
        /// Host không cho biết context (nil) → hành xử như cũ (reset).
        case unknown
    }

    /// Sau một thay đổi text/selection từ NGOÀI handle(): giữ hay bỏ từ đang gõ?
    /// `selectedText` (iOS 16+): có vùng chọn khác rỗng = người dùng đang chọn chữ →
    /// gõ tiếp sẽ thay vùng chọn, từ đang gõ không còn là neo → reset.
    static func verdict(context: String?, composed: String, selectedText: String? = nil) -> Verdict {
        guard !composed.isEmpty else { return .reset }
        if let sel = selectedText, !sel.isEmpty { return .reset }
        guard let ctx = context else { return .unknown }
        return ctx.hasSuffix(composed) ? .keep : .reset
    }

    /// Xoá dưới ngưỡng này không đọc context (hot path: mỗi phím). 1 ký tự lệch
    /// thì hại tối đa 1 ký tự; từ 2 trở lên mới đáng trả giá đọc proxy.
    static let verifyThreshold = 2

    /// Được phép xoá `bs` ký tự để sửa `expected` (đang nằm ngay trước con trỏ)?
    /// - bs == 0 hoặc dưới ngưỡng: luôn được (không đọc context).
    /// - bs > expected.count: engine chỉ sửa trong từ của nó — xoá quá từ = sai lệch.
    /// - context nil: không biết → cho (hành vi cũ).
    /// - context có: phải kết thúc bằng `expected`.
    static func canDelete(_ bs: Int, expected: String, context: () -> String?,
                          threshold: Int = verifyThreshold) -> Bool {
        guard bs > 0 else { return true }
        if bs > expected.count { return false }
        guard bs >= threshold else { return true }
        guard let ctx = context() else { return true }
        return ctx.hasSuffix(expected)
    }

    /// Xoá sạch phần trước con trỏ theo từng "cửa sổ" context. Dừng khi context
    /// rỗng/nil, khi chạm `maxChars`, hoặc khi sau một lượt xoá context Y HỆT lượt
    /// trước (host không cập nhật context đồng bộ / bỏ qua deleteBackward) — tránh
    /// xoá mù hàng nghìn lần. (So nội dung, không so độ dài: cửa sổ context có thể
    /// lộ đoạn trước dài hơn sau khi xoá.) Trả số lần deleteBackward đã gửi.
    @discardableResult
    static func clearBefore(context: () -> String?, deleteBackward: () -> Void,
                            maxChars: Int = 20_000) -> Int {
        var sent = 0
        var last: String?
        while let before = context(), !before.isEmpty, sent < maxChars {
            guard before != last else { break }   // lượt trước không có tác dụng
            last = before
            let n = before.count
            for _ in 0..<n { deleteBackward() }
            sent += n
        }
        return sent
    }

    /// Đẩy con trỏ về cuối ô theo từng cửa sổ context sau con trỏ; cùng luật dừng
    /// như clearBefore (context sau y hệt = host không nhận lệnh dời).
    @discardableResult
    static func moveToEnd(contextAfter: () -> String?, adjust: (Int) -> Void,
                          maxChars: Int = 20_000) -> Int {
        var moved = 0
        var last: String?
        while let after = contextAfter(), !after.isEmpty, moved < maxChars {
            guard after != last else { break }
            last = after
            let n = after.count
            adjust(n)
            moved += n
        }
        return moved
    }

    /// `context` kết thúc ĐÚNG bằng `word` (so từng Unicode scalar — KHÔNG tương đương
    /// chuẩn: ô NFD phải lệch, vì deleteBackward sẽ cắt vào dấu tổ hợp) và ký tự ngay
    /// trước `word` (nếu có) không phải chữ — từ đứng riêng, không phải đuôi từ khác.
    static func endsWithWord(_ context: String, _ word: String) -> Bool {
        let c = Array(context.unicodeScalars), w = Array(word.unicodeScalars)
        guard !w.isEmpty, c.count >= w.count, Array(c.suffix(w.count)) == w else { return false }
        guard c.count > w.count else { return true }
        return !Character(c[c.count - w.count - 1]).isLetter
    }

    /// Từ (dãy chữ liền) ngay trước con trỏ, nil nếu ký tự cuối không phải chữ hoặc
    /// văn bản không ở dạng dựng sẵn (NFC) — sửa dấu trên ô NFD là cắt vào dấu tổ hợp.
    static func trailingWord(_ context: String) -> String? {
        var start = context.endIndex
        while start > context.startIndex {
            let prev = context.index(before: start)
            guard context[prev].isLetter else { break }
            start = prev
        }
        guard start < context.endIndex else { return nil }
        let word = String(context[start...])
        guard word.unicodeScalars.elementsEqual(
            word.precomposedStringWithCanonicalMapping.unicodeScalars) else { return nil }
        return word
    }

    /// Dòng log chẩn đoán: CHỈ độ dài context + cờ khớp — không bao giờ nội dung.
    /// len = -1 khi host trả nil.
    static func diagnostic(context: String?, composed: String) -> (len: Int, suffix: Bool) {
        guard let ctx = context else { return (-1, false) }
        return (ctx.count, !composed.isEmpty && ctx.hasSuffix(composed))
    }
}

/// Bản sao phía bàn phím của chữ trước con trỏ — bù tiếng vọng TRỄ của host.
///
/// Proxy của iOS cập nhật context LẠC QUAN ngay khi bàn phím gửi lệnh, nhưng host (web view —
/// Gmail, ô có gợi ý/autocomplete…) xử lý lệnh trễ rồi đẩy trạng thái CỦA NÓ về, đè lên bản lạc
/// quan: context đọc được thiếu các phím chưa xử lý. Phím kế áp lệnh lạc quan lên nền cũ đó ⇒ cả
/// context lẫn mọi phép kiểm fail-safe đều dựa trên chữ SAI. Hậu quả (góp ý tester 03/11/2026 —
/// "gõ nhanh chữ nhảy lung tung", "looix" ⇒ "lôõ", "xin chào" ⇒ "xin chaò", ⌫ rồi gõ lại ⇒ chữ
/// nhảy sang chữ khác): từ đang gõ bị reset giữa chừng, nạp lại từ trước con trỏ từ context cũ
/// rồi xoá N ký tự của chữ THẬT (khác hẳn) ⇒ rác. Trước đây EchoGuard chụp context đọc NGAY sau
/// edit (chính là nền cũ + lệnh lạc quan ⇒ ảnh chụp sai) và chỉ bật sau lần lệch đầu tiên.
///
/// Ở đây bàn phím tự TÍNH `belief` = chữ host sẽ có khi xử lý hết lệnh của mình (đọc nền một lần
/// lúc chưa biết, rồi áp từng insert/⌫ — không đọc proxy mỗi phím), giữ ảnh `belief` sau mỗi lệnh
/// gần đây. Host đẩy context về:
///   • khớp `belief`                   ⇒ đồng bộ;
///   • khớp một ảnh CŨ (≤ `window` s)  ⇒ tiếng vọng trễ của chính mình: `lagging`, đọc context
///                                        trả `belief` cho tới khi host đuổi kịp;
///   • khác hết                        ⇒ thay đổi thật (chạm chỗ khác, host xoá ô, host nuốt lệnh):
///                                        nhận context host làm `belief` mới.
/// Ô trống chỉ coi là tiếng vọng khi chính ⌫ của mình làm trống (host xoá ô khi gửi tin là thay
/// đổi thật). Thuần.
struct HostMirror {
    static let capacity = 32
    static let window: Double = 1.0
    /// So khớp phần đuôi tối đa này (ký tự) — context host có thể cắt đầu khác nhau.
    static let tail = 48
    /// Giữ tối đa chừng này ký tự cuối của `belief`.
    static let cap = 512

    /// Chữ trước con trỏ khi host xử lý xong mọi lệnh của mình; nil = không biết.
    private(set) var belief: String?
    /// Đã thử đọc nền mà host trả nil ⇒ không đọc lại mỗi lệnh (tới lần invalidate / host đẩy).
    private var unknownHost = false
    /// `belief` sau các lệnh gần đây (cũ trước), phần tử cuối == `belief`. `emptied`: ô trống do
    /// chính ⌫ của mình (khác ô trống host báo — host xoá ô khi gửi tin là thay đổi thật).
    private var snaps: [(text: String, emptied: Bool)] = []
    private var lastEdit = -Double.infinity
    /// Lần đẩy gần nhất của host là trạng thái CŨ của chính mình (host chưa đuổi kịp).
    private(set) var lagging = false

    /// Đang trong `window` giây sau lệnh của mình.
    func recentEdit(now: Double) -> Bool { now - lastEdit <= Self.window }

    /// Context nên dùng thay cho context proxy: `belief` khi host đang trễ (và mới có lệnh),
    /// nil = đọc proxy như thường.
    func override(now: Double) -> String? {
        guard lagging, recentEdit(now: now) else { return nil }
        return belief
    }

    /// Không còn biết chữ trước con trỏ (dời con trỏ, đổi ô, marked text).
    mutating func invalidate() {
        belief = nil; unknownHost = false; snaps.removeAll(); lagging = false
    }

    /// Ngay TRƯỚC một lệnh của mình: chưa biết nền ⇒ đọc một lần.
    mutating func willEdit(read: () -> String?) {
        guard belief == nil, !unknownHost else { return }
        if let ctx = read() { adopt(ctx) } else { unknownHost = true }
    }

    mutating func inserted(_ text: String, now: Double) {
        lastEdit = now
        guard var b = belief else { return }
        b += text
        if b.count > Self.cap { b = String(b.suffix(Self.cap)) }
        belief = b
        snap(b)
    }

    mutating func deletedBackward(now: Double) {
        lastEdit = now
        guard var b = belief else { return }
        // Cửa sổ context có thể giấu chữ phía trước: xoá quá phần đã biết ⇒ không biết nữa.
        guard !b.isEmpty else { belief = nil; snaps.removeAll(); lagging = false; return }
        b.removeLast()
        belief = b
        snap(b, emptied: b.isEmpty)
    }

    /// Host đẩy context `ctx` về (callback textDidChange/selectionDidChange…). Trả context hiệu
    /// lực (đã bù tiếng vọng trễ).
    mutating func hostReported(_ ctx: String?, now: Double) -> String? {
        unknownHost = false
        guard let ctx else { belief = nil; snaps.removeAll(); lagging = false; return nil }
        guard let b = belief else { adopt(ctx); return ctx }
        if recentEdit(now: now) {
            // Ảnh SỚM nhất khớp: một trạng thái có thể lặp lại (⌫ dấu cách vừa gõ ⇒ lại đúng chữ
            // lúc trước; "l" trước "lo" và sau khi xoá "o") — khớp ảnh mới nhất chưa chắc host đã
            // đuổi kịp, và bỏ nhầm các ảnh ở giữa thì tiếng vọng kế không nhận ra.
            if let i = snaps.firstIndex(where: { Self.matches(ctx, $0.text) || ($0.emptied && ctx.isEmpty) }) {
                if i == snaps.count - 1 { adopt(ctx); return ctx }        // đã đuổi kịp
                snaps.removeFirst(i)                                      // host đã qua các ảnh cũ hơn
                lagging = true
                return b
            }
            // Khác hết ngay sau lệnh của mình: có thể host còn lệnh chưa xử lý (hoặc vừa đổi
            // thật) ⇒ không đoán; lệnh kế đọc lại nền từ proxy.
            belief = nil; snaps.removeAll(); lagging = false
            return ctx
        }
        adopt(ctx)                                                        // thay đổi thật
        return ctx
    }

    private mutating func adopt(_ ctx: String) {
        let c = ctx.count > Self.cap ? String(ctx.suffix(Self.cap)) : ctx
        belief = c
        snaps = [(c, false)]
        lagging = false
    }

    private mutating func snap(_ b: String, emptied: Bool = false) {
        if snaps.last?.text == b { return }
        snaps.append((b, emptied))
        if snaps.count > Self.capacity { snaps.removeFirst() }
    }

    /// `ctx` là trạng thái `snap`: so ≤ `tail` ký tự cuối (≥ 8 — chuỗi ngắn hơn chỉ khớp khi
    /// bằng hẳn, kẻo khớp nhầm); host cắt context ngắn hơn ảnh chụp ⇒ ảnh chụp kết thúc bằng nó.
    static func matches(_ ctx: String, _ snap: String) -> Bool {
        if snap.isEmpty { return false }                         // ô trống: host xoá ô là thay đổi thật
        if ctx == snap { return true }
        let n = min(tail, snap.count)
        if ctx.count >= n { return n >= 8 && ctx.hasSuffix(String(snap.suffix(n))) }
        return ctx.count >= 8 && snap.hasSuffix(ctx)
    }
}
