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

/// Tiếng vọng TRỄ của host (web view — Gmail, WKWebView). Host báo text/selection đổi sau MỖI
/// lệnh sửa của bàn phím, có khi tới SAU khi phím kế đã áp cục bộ: lúc đó context đọc được là
/// trạng thái CŨ của chính mình (thiếu phím vừa gõ). Trước đây đối chiếu thấy lệch ⇒ reset từ
/// đang gõ giữa chừng ⇒ phím dấu sau đó đi đường với lại từ (đọc context, xoá + gõ lại cả từ —
/// thêm lệnh host, thêm tiếng vọng) hoặc ra sai ("vieejt" ⇒ "vieẹt"). Đo 28/10/2026
/// (Feedback1028Tests, tiếng vọng trễ một phím): chuỗi phím dấu hỏng gần hết, 3,4 lượt đọc
/// context/phím.
///
/// Cách giữ: chụp context sau mỗi edit của mình (chỉ khi host đã lộ là vọng trễ — `armed`;
/// host thường: không chụp gì). Context host báo mà khớp một ảnh chụp CŨ (không phải ảnh mới
/// nhất) trong `window` giây sau edit ⇒ tiếng vọng trễ của chính mình: coi context là ảnh mới
/// nhất (trạng thái host sẽ tới khi xử lý xong các lệnh đã gửi). Thuần, pinned by tests.
struct EchoGuard {
    static let capacity = 8
    static let window: Double = 1.0
    /// So khớp phần đuôi tối đa này (ký tự) — context host có thể cắt đầu khác nhau.
    static let tail = 48

    /// Host đã lộ là vọng trễ (đối chiếu lệch ngay sau edit của mình) ⇒ bắt đầu chụp.
    private(set) var armed = false
    private var snaps: [String] = []
    private var lastEdit = -Double.infinity

    /// Callback host tới trong `window` giây sau edit của mình?
    func recentEdit(now: Double) -> Bool { now - lastEdit <= Self.window }

    mutating func arm() { armed = true }

    /// Bỏ mọi ảnh chụp. (Đối chiếu lệch KHÔNG gọi: ảnh cũ vô hại — chỉ khớp khi host hiện lại
    /// đúng trạng thái cũ của mình trong `window` giây, tức chính là tiếng vọng trễ.)
    mutating func clear() { snaps.removeAll() }

    /// Sau mỗi edit của mình: context cục bộ (đã áp). Chưa `armed` ⇒ chỉ ghi giờ.
    mutating func record(_ ctx: String?, now: Double) {
        lastEdit = now
        guard armed else { return }
        guard let ctx else { snaps.removeAll(); return }
        if snaps.last == ctx { return }
        snaps.append(ctx)
        if snaps.count > Self.capacity { snaps.removeFirst() }
    }

    /// Context host báo ⇒ context dự kiến (ảnh mới nhất) nếu đây là trạng thái cũ của chính
    /// mình; nil ⇒ không phải (dùng context thật).
    func settled(_ ctx: String?, now: Double) -> String? {
        guard armed, let ctx, let cur = snaps.last, snaps.count > 1, recentEdit(now: now) else { return nil }
        if Self.matches(ctx, cur) { return nil }                 // đã cập nhật
        for old in snaps.dropLast().reversed() where Self.matches(ctx, old) { return cur }
        return nil
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
