// KeyLayout — bảng tỉ lệ phím THUẦN (không UIKit) để unit-test được. KeyboardView
// dựng constraint từ đây. Quy tắc (bug 26/09/2026: nút 🌐 hàng đáy iPad nhảy
// size; hàng 1 iPad thành 12 phím bằng nhau sau khi từ mẫu câu về): mỗi hàng chỉ
// được ĐÚNG MỘT phím co giãn (units = nil), hoặc không phím nào nếu hàng đó là
// hàng neo quyết định bề rộng phím chữ. Hai phím "tự do" = UIKit chia tuỳ lúc.
import CoreGraphics

enum KeyLayout {
    struct Key { let id: String; let units: CGFloat? }   // nil = co giãn

    /// iPad plane chữ — units = bội số bề rộng phím chữ q. Hàng 1 KHÔNG có phím
    /// co giãn: nó quyết định q. Đo ảnh iPad Pro 11" stock.
    static let padRows: [[Key]] = [
        [Key(id: "tab", units: 1.31)] + letters("qwertyuiop") + [Key(id: "back", units: 1.31)],
        [Key(id: "caps", units: 1.67)] + letters("asdfghjkl") + [Key(id: "return", units: nil)],
        [Key(id: "shiftL", units: 2.2)] + letters("zxcvbnm")
            + [Key(id: "!,", units: 1), Key(id: "?.", units: 1), Key(id: "shiftR", units: nil)],
    ]
    static let padAnchorRow = 0

    /// Hàng phím số tuỳ chọn (Settings → "Hàng phím số"), nằm TRÊN hàng tab.
    /// Cùng 12 phím như hàng neo nên số 1…0 thẳng cột q…p: "-" rộng như tab,
    /// "=" co giãn (= đúng phần của ⌫). Không có ký tự phụ vuốt xuống.
    static let padNumberRow: [Key] =
        [Key(id: "-", units: 1.31)] + letters("1234567890") + [Key(id: "=", units: nil)]
    static let digits = "1234567890".map { String($0) }

    /// Hàng số thấp hơn hàng chữ như Gboard — tổng bàn phím tăng ít.
    static let numberRowRatio: CGFloat = 0.75

    /// Tổng chiều cao vùng phím. `base` = 4 hàng chuẩn, `adjust` = ±pt MỖI hàng
    /// (Settings). Hàng số bật → thêm 0.75 hàng, cho MỌI plane (bàn phím không đổi
    /// chiều cao khi chuyển 123/emoji — host relayout dở dang, xem updateSuggestionChrome).
    static func keyAreaHeight(base: CGFloat, adjust: CGFloat, numberRow: Bool) -> CGFloat {
        let unit = (base + adjust * 4) / 4
        return unit * (numberRow ? 4 + numberRowRatio : 4)
    }

    // MARK: Chiều cao bàn phím (bug tester 1.2.x: phím co lại ở Notes/Facebook, lúc
    // ngẫu nhiên, và khi tìm emoji). Quy tắc: vùng phím LUÔN đủ `keyArea`.

    /// Chế độ bố trí dọc: phím thường (strip ở trên), lưới emoji (lấn strip), tìm emoji
    /// (ô tìm + 4 hàng chữ — ô tìm KHÔNG ăn vào chiều cao phím).
    enum ChromeMode { case keys, emoji, emojiSearch }
    struct Chrome: Equatable {
        var rowsTop: CGFloat   // strip phía trên vùng hàng
        var rows: CGFloat      // chiều cao vùng hàng (kể cả ô tìm emoji)
        var total: CGFloat     // chiều cao xin host
        /// Sàn khoảng trên hàng phím khi host cấp THIẾU (strip chỉ nhường tới đây).
        var minTop: CGFloat = 0
    }

    /// Khoảng trống tối thiểu phía trên hàng phím đầu cho balloon/popup ký tự phụ.
    /// Extension KHÔNG vẽ được ra ngoài inputView ⇒ chỗ này phải nằm trong bàn phím.
    /// Bug Phil 30/09/2026: tắt/thu gọn thanh gợi ý (strip 0/14) hoặc host cấp thiếu
    /// (strip nhường hết) ⇒ balloon "3" trên phím "e" bị cắt nửa ở mép trên. Stock cũng
    /// chừa đệm trên. 20pt + khe hàng 10 ⇒ bubble ≥ 24pt (chữ co cho vừa, không cắt).
    static let balloonHeadroom: CGFloat = 20

    /// Bo 2 góc trên của nền theme tự vẽ (OLED, pastel, ảnh nền) theo khung kính bàn phím
    /// iPhone iOS 26+: khung hệ thống bo góc trên ĐÚNG ở mép trên cửa sổ extension, nền đục
    /// góc vuông che mất ⇒ góc đen vuông lòi trên nền app. Đo Safari iOS 27 sim (iPhone 17,
    /// 05/10/2026): profile góc khớp cung TRÒN bán kính 25pt (75px @3x) — cornerCurve .circular.
    /// iPad / iOS < 26: 0 (chưa đo — giữ góc vuông như cũ).
    static func backdropCornerRadius(phone: Bool, systemMajor: Int) -> CGFloat {
        phone && systemMajor >= 26 ? 25 : 0
    }
    /// Hàng ô tìm emoji (ô 38pt + đệm 5/3) — như dải tìm của stock.
    static let emojiSearchRow: CGFloat = 46
    static func emojiSearchBarHeight(strip: CGFloat) -> CGFloat { max(emojiSearchRow, strip) }

    static func chrome(keyArea: CGFloat, strip: CGFloat, mode: ChromeMode) -> Chrome {
        // Strip hiệu dụng: không thấp hơn headroom balloon (bar tắt / thu gọn vẫn chừa đệm).
        let strip = max(strip, balloonHeadroom)
        switch mode {
        case .keys: return Chrome(rowsTop: strip, rows: keyArea, total: keyArea + strip,
                                  minTop: balloonHeadroom)
        case .emoji: return Chrome(rowsTop: 0, rows: keyArea + strip, total: keyArea + strip)
        case .emojiSearch:
            // Ô tìm nằm chỗ strip (bar gợi ý ẩn); phần nó cao hơn strip thì bàn phím cao
            // thêm như stock — trước đây nó chen vào keyArea ⇒ 4 hàng chữ bị ép còn ~80%.
            // Ô tìm (≥ 46) cao hơn headroom ⇒ balloon hàng chữ đầu có chỗ trong ô tìm.
            let bar = emojiSearchBarHeight(strip: strip)
            return Chrome(rowsTop: 0, rows: keyArea + bar, total: keyArea + bar)
        }
    }

    /// Strip gợi ý: giữ theo CÔNG TẮC toàn cục, không theo từng ô. Trước đây ô từ chối
    /// gợi ý (mật khẩu, autocorrect = .no — ô tìm Facebook, trait Notes đọc chập chờn)
    /// làm bàn phím thấp 34pt rồi cao lại khi đang hiện; host không phải lúc nào cũng
    /// cấp lại chiều cao ⇒ strip (999) thắng, hàng phím (900) bị ép.
    static func stripHeight(reserved: Bool, collapsed: Bool, open: CGFloat) -> CGFloat {
        reserved ? (collapsed ? 14 : open) : 0
    }

    /// iPhone ngang theo BỀ NGANG view (dọc ≤ 440pt, ngang ≥ 568pt) — không tin
    /// interfaceOrientation của scene extension (có lúc lệch với host ⇒ xin 162pt ngang
    /// khi đang dọc = phím lùn). width 0 (chưa layout) thì mới dùng orientation.
    static func isPhoneLandscape(width: CGFloat, sceneLandscape: Bool?) -> Bool {
        if width > 0 { return width > 500 }
        return sceneLandscape ?? false
    }

    /// Hàng đáy — units = PHẦN của bề rộng hàng (multiplier theo stack width).
    /// iPad full plane chữ = stock [🌐][.?123][☺︎][space][.?123][⌨︎] — KHÔNG phím ","
    /// riêng (phím "!," hàng 3 đã có ","; Phil 27/09). Đo stock Pro 11": 58.7 / 88 trên 834.
    static let padBottom: [Key] = [
        Key(id: "globe", units: 0.068), Key(id: "plane", units: 0.068),
        Key(id: "emoji", units: 0.068), Key(id: "space", units: nil),
        Key(id: "plane2", units: 0.102), Key(id: "dismiss", units: 0.102),
    ]
    /// iPhone: đo stock iOS 26/27 (KeyGeometry): 123 / emoji 43.3pt trên 402 (0.108), "."
    /// bằng phím chữ (0.083), return 0.156 — cũ 0.12/0.12/0.075/0.14 làm phẩy lệch phải
    /// 12pt, return 7pt so với chỗ ngón quen.
    static let phoneBottom: [Key] = [
        Key(id: "plane", units: 0.108), Key(id: "globe", units: 0.10),
        Key(id: "emoji", units: 0.108), Key(id: "space", units: nil),
        Key(id: "comma", units: 0.083), Key(id: "return", units: 0.156),
    ]
    /// "," hàng đáy plane CHỮ iPhone hẹp hơn stock "." (0.083 → 0.071 ≈ 28.5pt trên 402,
    /// phím chữ 33.3): phần dư cho space — chạm space hay lẹm sang "," (Phil 06/10/2026,
    /// kèm KeyHitBias). Mép phải giữ nguyên (return không đổi). Plane số / mẫu câu giữ 0.083.
    static let phoneLettersComma: CGFloat = 0.071

    // MARK: iPad — hai kiểu bàn phím stock iPadOS 27 (đo simulator 27/09/2026)
    //  • full (Air/Pro 11", 13"): có tab + ⇪, icon/nhãn chức năng dạt góc dưới.
    //  • compact (iPad mini, cạnh ngắn màn hình < 800pt): KHÔNG tab/⇪, ⌫ cuối hàng 1,
    //    ⇧ hai đầu hàng 3, icon + nhãn (123/ABC/#+=) nằm GIỮA phím, chữ nhãn to.
    // Plane số/ký hiệu cùng khung phím với plane chữ của kiểu đó (stock y hệt), ký tự phụ
    // xám phía trên = vuốt xuống / giữ phím. Ô undo/redo của stock: bàn phím bên thứ ba
    // không chạm được undo manager của app → ô undo = ",", ô redo = "₫".
    enum PadStyle: Equatable { case full, compact }
    static func padStyle(screenShortSide s: CGFloat) -> PadStyle { s < 800 ? .compact : .full }

    /// ⌫ / ⇧ phải của kiểu compact = 1.23 phím chữ (stock mini: 79.5 / 66.5 bước phím).
    static let compactWideUnits: CGFloat = 1.23
    /// Khoảng thụt hàng 2 kiểu compact (khoảng trống TRƯỚC a/@/¥, chưa kể khe): stock mini
    /// a lệch q 26.5pt = khe 10 + 16.5 ≈ 0.29 phím chữ.
    static let compactIndentUnits: CGFloat = 0.29

    static func padLetterRows(_ s: PadStyle) -> [[Key]] {
        switch s {
        case .full: return padRows
        case .compact: return [
            letters("qwertyuiop") + [Key(id: "back", units: compactWideUnits)],
            [Key(id: "indent", units: compactIndentUnits)] + letters("asdfghjkl") + [Key(id: "return", units: nil)],
            [Key(id: "shiftL", units: 1)] + letters("zxcvbnm")
                + [Key(id: "!,", units: 1), Key(id: "?.", units: 1), Key(id: "shiftR", units: nil)],
        ]
        }
    }

    /// Plane số (.?123) iPad — thứ tự phím đúng stock. id = ký tự của phím (trừ phím chức
    /// năng: tab/back/return/more/more2/undo/indent; "!," "?." = phím 2 tầng).
    static func padNumberRows(_ s: PadStyle) -> [[Key]] {
        padSymbolic(s, row2: ["@", "#", "$", "&", "*", "(", ")", "'", "\""],
                    row3: ["%", "-", "+", "=", "/", ";", ":", "!,", "?."], slot: "undo")
    }
    /// Plane ký hiệu (#+=) iPad — đúng stock.
    static func padSymbolRows(_ s: PadStyle) -> [[Key]] {
        padSymbolic(s, row2: ["¥", "£", "€", "_", "^", "[", "]", "{", "}"],
                    row3: ["§", "|", "~", "…", "\\", "<", ">", "!", "?"], slot: "redo")
    }
    private static func padSymbolic(_ s: PadStyle, row2: [String], row3: [String], slot: String) -> [[Key]] {
        let digits = letters("1234567890")
        let r2 = row2.map { Key(id: $0, units: 1) }, r3 = row3.map { Key(id: $0, units: 1) }
        switch s {
        case .full: return [
            [Key(id: "tab", units: 1.31)] + digits + [Key(id: "back", units: 1.31)],
            [Key(id: slot, units: 1.67)] + r2 + [Key(id: "return", units: nil)],
            [Key(id: "more", units: 2.2)] + r3 + [Key(id: "more2", units: nil)],
        ]
        case .compact: return [
            digits + [Key(id: "back", units: compactWideUnits)],
            [Key(id: "indent", units: compactIndentUnits)] + r2 + [Key(id: "return", units: nil)],
            [Key(id: "more", units: 1)] + r3 + [Key(id: "more2", units: nil)],
        ]
        }
    }
    /// Nội dung ô undo (plane số) / redo (plane ký hiệu) của stock.
    static func padSlotTitle(_ id: String) -> String? {
        switch id { case "undo": return ","; case "redo": return "₫"; default: return nil }
    }

    /// Ký tự phụ (xám, trên) của phím plane số iPad — stock iPadOS 27. Vuốt xuống / giữ → ra.
    static let padNumberHints: [String: String] = [
        "@": "¥", "#": "£", "$": "€", "&": "_", "*": "^", "(": "[", ")": "]", "'": "{", "\"": "}",
        "%": "§", "-": "|", "+": "~", "=": "…", "/": "\\", ";": "<", ":": ">",
    ]

    /// Hàng đáy iPad theo kiểu + plane. `letters`: [🌐][.?123][☺︎][space][.?123][⌨︎] (stock,
    /// full lẫn mini — "," nằm ở phím "!," hàng 3);
    /// plane số/ký hiệu full: [🌐][ABC][☺︎][space][ABC][⌨︎] (stock không có phẩy);
    /// compact số/ký hiệu: [🌐][ABC][☺︎][space][ô undo/redo][ABC][⌨︎].
    /// units = phần bề rộng hàng (compact: stock mini 59 / 93.5 trên 744).
    static func padBottomRow(_ s: PadStyle, letters: Bool) -> [Key] {
        switch (s, letters) {
        case (.full, true): return padBottom
        case (.full, false): return [
            Key(id: "globe", units: 0.068), Key(id: "plane", units: 0.068),
            Key(id: "emoji", units: 0.068), Key(id: "space", units: nil),
            Key(id: "plane2", units: 0.102), Key(id: "dismiss", units: 0.102),
        ]
        case (.compact, true): return [
            Key(id: "globe", units: 0.079), Key(id: "plane", units: 0.079),
            Key(id: "emoji", units: 0.079), Key(id: "space", units: nil),
            Key(id: "plane2", units: 0.126),
            Key(id: "dismiss", units: 0.126),
        ]
        case (.compact, false): return [
            Key(id: "globe", units: 0.079), Key(id: "plane", units: 0.079),
            Key(id: "emoji", units: 0.079), Key(id: "space", units: nil),
            Key(id: "slot", units: 0.079), Key(id: "plane2", units: 0.079),
            Key(id: "dismiss", units: 0.079),
        ]
        }
    }

    /// Vuốt XUỐNG trên phím iPad (ký tự phụ): đi xuống quá ngưỡng và dọc nhiều hơn ngang.
    static func isPadFlick(dx: CGFloat, dy: CGFloat, threshold: CGFloat) -> Bool {
        dy > threshold && dy > abs(dx)
    }

    static func units(_ id: String, in row: [Key]) -> CGFloat? {
        row.first { $0.id == id }?.units
    }

    private static func letters(_ s: String) -> [Key] {
        s.map { Key(id: String($0), units: 1) }
    }

    // MARK: kiểm tra (test dùng)

    static func flexCount(_ row: [Key]) -> Int { row.filter { $0.units == nil }.count }

    /// Bề rộng phím chữ q do hàng neo quyết định.
    static func padLetterWidth(rowWidth w: CGFloat, gap: CGFloat, margin: CGFloat) -> CGFloat {
        padLetterWidth(anchor: padRows[padAnchorRow], rowWidth: w, gap: gap, margin: margin)
    }
    static func padLetterWidth(anchor row: [Key], rowWidth w: CGFloat, gap: CGFloat, margin: CGFloat) -> CGFloat {
        let units = row.compactMap(\.units).reduce(0, +)
        return (w - 2 * margin - gap * CGFloat(row.count - 1)) / units
    }

    /// Bề rộng phím co giãn của hàng `i` (≤ 0 = tràn hàng).
    static func padFlexWidth(row i: Int, rowWidth w: CGFloat, gap: CGFloat, margin: CGFloat) -> CGFloat {
        padFlexWidth(padRows[i], rowWidth: w, gap: gap, margin: margin)
    }
    static func padFlexWidth(_ row: [Key], anchor: [Key]? = nil, rowWidth w: CGFloat,
                             gap: CGFloat, margin: CGFloat) -> CGFloat {
        let q = padLetterWidth(anchor: anchor ?? padRows[padAnchorRow], rowWidth: w, gap: gap, margin: margin)
        let fixed = row.compactMap(\.units).reduce(0, +) * q
        return w - 2 * margin - gap * CGFloat(row.count - 1) - fixed
    }
}

// MARK: Khung hệ thống cao hơn input view (Phil 05/10/2026, iPhone thật iOS 27, WhatsApp,
// theme đen): thỉnh thoảng một dải kính xám bo góc ~15–20pt lộ RA TRÊN nền đen của mình —
// container (superview/window) hệ thống cấp cho bàn phím cao hơn input view, view mình neo
// đáy. Sửa: xin cao thêm ĐÚNG phần hệ thống đã cấp (phím hấp thụ như khi host cấp dư) —
// không bao giờ xin hơn mức đã cấp, chờ một lượt layout xác nhận (bỏ khung tạm lúc xoay /
// animation hiện), và nếu container lại cao vượt mức đã xin (dấu hiệu vòng lặp "xin thêm →
// cấp thêm → …") thì trả về 0 và khoá tới lần hiện sau.

/// Quyết định thuần (unit-test được) cho việc lấp dải container hệ thống phía trên view.
struct HostFill {
    enum Decision: Equatable {
        case none                 // không làm gì
        case wait                 // thấy khoảng hở — chờ lượt layout sau xác nhận
        case apply(CGFloat)       // đặt phần xin thêm (pt) = giá trị này
    }
    /// Trần phần xin thêm: dải quan sát ~15–20pt; khung khổng lồ lúc host settle / window cỡ
    /// màn hình vượt trần ⇒ bỏ qua (không bao giờ kéo bàn phím cao vô hạn).
    static let maxExtra: CGFloat = 48
    /// Sai số làm tròn pixel.
    static let tolerance: CGFloat = 1

    private(set) var extra: CGFloat = 0
    /// Đã thấy dấu hiệu vòng lặp — tắt tới reset().
    private(set) var locked = false
    private var pending: CGFloat?
    private var width: CGFloat = 0

    /// Lần hiện mới: về trạng thái gốc (không xin thêm).
    mutating func reset() { self = HostFill() }

    /// Khoảng từ đỉnh container tới đáy view (toạ độ container) nếu view NEO ĐÁY container;
    /// nil nếu không neo đáy (không phải dải phía trên) hoặc chưa có hình học.
    static func allocated(viewFrame: CGRect, container: CGRect) -> CGFloat? {
        guard viewFrame.height > 0, container.height > 0,
              abs(container.maxY - viewFrame.maxY) < tolerance else { return nil }
        return viewFrame.maxY - container.minY
    }

    /// - base: chiều cao bàn phím tự xin (KeyLayout.chrome total, CHƯA cộng extra).
    /// - viewHeight: chiều cao view thật hệ thống cấp (có thể > mức xin — phím hấp thụ).
    /// - allocated: đỉnh container → đáy view (`allocated(viewFrame:container:)`), nil = không biết.
    /// - animating: đang animation hiện/xoay ⇒ khung tạm, chỉ chờ.
    mutating func observe(base: CGFloat, viewHeight: CGFloat, allocated: CGFloat?,
                          width: CGFloat, animating: Bool) -> Decision {
        if width != self.width {
            // Xoay / Split View: hình học mới hoàn toàn — bỏ phần xin thêm cũ.
            let had = extra
            self.width = width; pending = nil; extra = 0
            if had != 0 { return .apply(0) }
        }
        guard !locked, let allocated, base > 0, viewHeight > 0 else { pending = nil; return .none }
        let band = allocated - viewHeight
        guard band >= Self.tolerance else { pending = nil; return .none }   // không hở: giữ nguyên
        if extra > 0 {
            pending = nil
            // Container cao HƠN cả mức đã xin ⇒ nó chạy theo mức xin (vòng lặp) — trả về
            // như cũ, khoá. Còn trong mức đã xin = hệ thống chưa kịp cấp lại view: chờ.
            guard allocated - (base + extra) >= Self.tolerance else { return .none }
            locked = true; extra = 0
            return .apply(0)
        }
        if animating { pending = nil; return .wait }
        let target = (allocated - base).rounded()
        guard target > 0, target <= Self.maxExtra else { pending = nil; return .none }
        if let p = pending, abs(p - allocated) < Self.tolerance {
            pending = nil; extra = target
            return .apply(target)
        }
        pending = allocated
        return .wait
    }
}
