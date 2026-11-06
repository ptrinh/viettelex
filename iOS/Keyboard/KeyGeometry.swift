// KeyGeometry — hình học hàng phím iPhone khớp bàn phím Apple gốc (27/09/2026), THUẦN
// (không UIKit) để unit-test. Người dùng than "cứ 4–5 chữ sai 1": so ảnh cùng máy, hàng
// phím VietTelex nằm CAO hơn stock 5pt (bản đang phát hành: 11pt), phím rộng hơn (lề 3
// thay 6.5) và hàng đáy lệch (phẩy lệch phải 12pt so với "." stock).
//
// Nguồn số đo stock (pt, dọc):
//  • Simulator iPhone 17 (402×874, iOS 27), bàn phím Apple English (US), XCUITest +
//    ảnh chụp @3x: phím chữ 33.3×43.0, bước ngang 39.5, lề 6.67; tâm hàng (tính từ đáy
//    màn hình) 254.5 / 200.5 / 146.5 / 92.5; đáy phím hàng dưới cách đáy màn hình 71.
//    Ô chạm (accessibility frame) mỗi phím = [đỉnh phím, đỉnh phím hàng dưới).
//  • Video người dùng iPhone 393pt iOS 26 (Messenger, English US): 32.5×42.7, bước 38.6,
//    lề 6.5; tâm hàng 254.3 / 200.2 / 146.4 / 92.4 — khớp simulator ±0.3pt.
//  • Extension KHÔNG vẽ được dưới đáy view: đáy view = 75pt trên đáy màn hình (cả hai
//    máy) — thấp hơn đáy phím stock 4pt, nên hàng đáy của mình cao hơn stock tối đa 4pt.
// Bố cục mới (dọc iPhone): 3 hàng chữ bước 54 (khe 10 + phím 44) → đỉnh/tâm phím trùng
// stock ≤0.5pt; hàng đáy = vùng 50, khe trên nó hẹp lại để 3 hàng trên xuống đúng chỗ
// stock. Tổng vùng phím 212 (cũ 218). Phím đáy 43 như stock (khe 7) — bản đầu để 44
// trông cao hơn stock (Phil so ảnh 27/09).
import CoreGraphics
import Foundation

enum KeyGeometry {
    /// Lề trái/phải hàng phím. iPhone như stock (6.5); iPad giữ 3 (đã đo riêng).
    static func sideMargin(pad: Bool) -> CGFloat { pad ? 3 : 6.5 }
    /// Khe giữa 2 hàng phím (lề trên mỗi hàng).
    static let rowGap: CGFloat = 10
    /// Hàng phím số: PHÍM số = 0.8× phím chữ (không tính khe) — KeyLayout.numberRowHeight.
    static let numberKeyRatio: CGFloat = 0.8
    /// Tuỳ chọn "Hàng số cao bằng hàng chữ" (Giao diện, mặc định TẮT; khoá App Group
    /// `numberRowFullHeightKey`) ⇒ phím số = phím chữ (tỉ lệ 1).
    static let numberRowFullHeightKey = "numberRowFullHeight"
    static func numberKeyRatio(fullHeight: Bool) -> CGFloat { fullHeight ? 1 : numberKeyRatio }
    /// Cao hàng số (khe + phím) khi hàng chữ cao `unit` (khe + phím). Dùng chung app (Wallpaper).
    /// `gap` = khe trên mỗi hàng (preset "như bàn phím iPhone" có khe riêng — RowSpec).
    static func numberRowHeight(unit: CGFloat, gap: CGFloat = rowGap, fullHeight: Bool = false) -> CGFloat {
        gap + numberKeyRatio(fullHeight: fullHeight) * max(unit - gap, 0)
    }
    /// Vùng phím chuẩn 4 hàng × 54 trước khi trừ phần cắt ở hàng đáy (iPhone dọc).
    static let phonePortraitBase: CGFloat = 216
    /// iPhone dọc: hàng đáy thấp hơn các hàng khác chừng này (khe trên nó hẹp lại).
    static func bottomRowTrim(pad: Bool, landscape: Bool) -> CGFloat {
        (pad || landscape) ? 0 : 4
    }

    /// Chiều cao phím hàng đáy iPhone dọc = stock 43 (27/09 chiều: Phil so ảnh — hàng đáy
    /// 44 trông cao hơn stock). Vùng hàng đáy giữ 50 → khe trên nó 7 (3 hàng chữ không dời).
    static let phoneBottomKeyHeight: CGFloat = Stock.keyHeight
    /// Lề trên hàng đáy: iPhone dọc = vùng (54 − trim) − phím 43; iPad/ngang = rowGap.
    static func bottomRowTopMargin(pad: Bool, landscape: Bool) -> CGFloat {
        if pad || landscape { return rowGap }
        return phonePortraitBase / 4 - bottomRowTrim(pad: pad, landscape: landscape) - phoneBottomKeyHeight
    }

    /// Bước phím chữ (tâm → tâm) của hàng 10 phím: (W − 2·lề − 9·khe)/10 + khe.
    static func letterPitch(width: CGFloat, margin: CGFloat, gap: CGFloat) -> CGFloat {
        (width - 2 * margin - 9 * gap) / 10 + gap
    }
    /// Lề hàng thụt (hàng a…l = nửa bước phím) — đúng tuyệt đối, không xấp xỉ W/20.
    static func indentedMargin(width: CGFloat, margin: CGFloat, gap: CGFloat, units: CGFloat) -> CGFloat {
        margin + units * letterPitch(width: width, margin: margin, gap: gap)
    }

    /// Chỉ số rect GẦN `p` nhất (khoảng cách tới mép, 0 nếu nằm trong), nil nếu không có
    /// rect nào trong `reach`. Dùng cho khe/mép giữa các nút thật (123, emoji, ⇧, ⌫, số…):
    /// khe chia đôi theo khoảng cách như phím chữ — không còn vùng chết.
    static func nearest(_ p: CGPoint, in rects: [CGRect], reach: CGFloat) -> (index: Int, distance: CGFloat)? {
        var best: (Int, CGFloat)?
        for (i, f) in rects.enumerated() {
            let dx = max(f.minX - p.x, 0, p.x - f.maxX)
            let dy = max(f.minY - p.y, 0, p.y - f.maxY)
            let d = (dx * dx + dy * dy).squareRoot()
            if d <= reach, best == nil || d < best!.1 { best = (i, d) }
        }
        return best.map { (index: $0.0, distance: $0.1) }
    }

    // MARK: Hình học hàng phím (một nguồn cho KeyboardView + ảnh nền trong app)

    /// Hình học dọc + ngang của hàng phím iPhone/iPad. iPhone (không gập mở) = số đo bàn phím
    /// gốc của máy (StockSize) + chỉnh tay; iPad / máy gập mở = bố cục VietTelex (base) + chỉnh tay.
    struct RowSpec: Equatable {
        /// Bước hàng chữ (khe trên + phím).
        var unit: CGFloat
        /// Khe trên mỗi hàng chữ (layoutMargins.top).
        var gap: CGFloat
        /// Hàng đáy = unit − trim. Dương: hàng đáy thấp hơn (3 hàng chữ khớp stock tính từ đáy);
        /// âm: hàng đáy cao hơn, phần thêm là đệm DƯỚI phím đáy (phím stock nằm cao hơn đáy view).
        var bottomTrim: CGFloat
        /// Lề trên hàng đáy (khe giữa hàng 3 và hàng đáy).
        var bottomTop: CGFloat
        /// Lề trái/phải + khe ngang giữa phím.
        var sideMargin: CGFloat
        var keyGap: CGFloat
        /// Hình học theo số đo stock (iPhone) — KeyboardView: strip gợi ý stock.
        var stock: Bool = false

        var bottomRowHeight: CGFloat { unit - bottomTrim }
        /// Đệm dưới phím hàng đáy (chỉ khi trim âm).
        var bottomPad: CGFloat { max(-bottomTrim, 0) }
        /// Phím chữ / phím hàng đáy (không tính khe).
        var letterKeyHeight: CGFloat { unit - gap }
        var bottomKeyHeight: CGFloat { bottomRowHeight - bottomTop - bottomPad }
        /// Tổng vùng phím (4 hàng + hàng số nếu bật; `fullHeight` = hàng số cao bằng hàng chữ).
        func keyArea(numberRow: Bool, fullHeight: Bool = false) -> CGFloat {
            unit * 4 + (numberRow ? numberRowHeight(unit: unit, gap: gap, fullHeight: fullHeight) : 0) - bottomTrim
        }
        /// Hàng số = multiplier × hàng chữ + constant (constraint Auto Layout).
        var numberRowConstant: CGFloat { numberRowConstant(fullHeight: false) }
        func numberRowConstant(fullHeight: Bool) -> CGFloat { (1 - numberKeyRatio(fullHeight: fullHeight)) * gap }
    }

    /// - base: vùng 4 hàng chuẩn khi KHÔNG có số đo stock (iPad 240 / 300; máy gập mở 208 —
    ///   KeyLayout.phoneKeyAreaBase). iPhone thường bỏ qua base.
    /// - adjust: ±pt mỗi hàng (Settings "Chiều cao hàng phím", RowAdjust). iPhone: so với bàn
    ///   phím gốc của máy — bước hàng và phím (cả phím hàng đáy) cùng cao thêm `adjust`; khe
    ///   giữa hàng, phần cắt / đệm dưới hàng đáy giữ như stock ⇒ 0 = đúng bàn phím iPhone.
    ///   iPad / máy gập mở: (base + adjust × 4) / 4 như trước.
    /// - homeButton: iPhone có nút Home (SE) — không có dải 🌐/mic hệ thống dưới bàn phím
    ///   (KeyboardView: needsGlobe trên iPhone).
    static func rowSpec(pad: Bool, landscape: Bool, unfolded: Bool, width: CGFloat,
                        base: CGFloat, adjust: CGFloat, homeButton: Bool = false) -> RowSpec {
        if !pad, !unfolded,
           let m = StockSize.metrics(width: width, landscape: landscape, homeButton: homeButton) {
            let a = RowAdjust.clamp(adjust)
            let trim = m.bottomTrim
            // Lề trên hàng đáy KHÔNG đổi theo adjust: phím đáy cao thêm đúng `a` như phím chữ.
            let top = trim >= 0 ? m.pitch - trim - m.keyHeight : m.pitch - m.keyHeight
            return RowSpec(unit: m.pitch + a, gap: m.rowGap, bottomTrim: trim, bottomTop: top,
                           sideMargin: m.sideMargin, keyGap: m.keyGap, stock: true)
        }
        let unit = (base + RowAdjust.clamp(adjust) * 4) / 4
        let flat = pad || landscape          // máy gập mở cũng "ngang" (không cắt hàng đáy)
        return RowSpec(unit: unit, gap: rowGap,
                       bottomTrim: bottomRowTrim(pad: pad, landscape: flat),
                       bottomTop: bottomRowTopMargin(pad: pad, landscape: flat),
                       sideMargin: sideMargin(pad: pad), keyGap: pad ? 10 : 6)
    }

    /// "Chiều cao hàng phím" (±pt mỗi hàng) + "Nâng bàn phím" (đệm dưới hàng đáy) — khoá App
    /// Group, phạm vi, và chuyển đổi một lần từ bản có công tắc "Kích thước như bàn phím iPhone".
    ///
    /// Từ bản này (12/10/2026) mức 0 của thanh chiều cao hàng trên iPhone = bàn phím gốc của
    /// máy (StockSize). Trước đó: công tắc stock (#119) BẬT ⇒ đúng stock, chỉnh tay bỏ qua;
    /// TẮT ⇒ bước hàng = (216 + A·4)/4 = 54 + A (A = chỉnh tay cũ), khe 10, phím đáy sát đáy view.
    /// Chuyển đổi (RowAdjust.migrated) giữ BƯỚC HÀNG cũ: A' = A + 54 − bước stock của máy
    /// (máy < 420pt: A' = A; máy lớn 420+: A' = A − 2). Sai số còn lại (không biểu diễn được
    /// bằng chỉnh tay + nâng ≥ 0): phím chữ thấp hơn 1pt (khe stock 11 thay 10), strip gợi ý
    /// thấp hơn 5pt; máy lớn: cả khối phím nằm cao hơn ~7–11pt (đệm stock 7 dưới phím đáy +
    /// khe trên hàng đáy 11 thay 7) — đúng vị trí bàn phím iPhone, chính là điều #119 xin;
    /// SE: cao hơn ~4–8pt. iPad: giữ nguyên giá trị (ngữ nghĩa iPad không đổi).
    ///
    /// Lưu: app chạy `migrateIfNeeded` lúc khởi động (ghi cờ trước rồi giá trị). Bàn phím KHÔNG
    /// ghi (không có Toàn quyền thì App Group chỉ đọc) — đọc qua `effectiveAdjust`: chưa có cờ
    /// thì tính chuyển đổi trong bộ nhớ, cùng hàm thuần ⇒ kết quả trùng với app ghi sau đó.
    ///
    /// Sửa 03/11/2026 (tester iPhone: "bàn phím mặc định nhỏ quá, phải tăng mấy nấc mới bằng bàn
    /// phím Apple"): chuyển đổi 12/10 coi người dùng cũ CHƯA từng chỉnh (không có khoá
    /// `rowHeightAdjust`, không có công tắc) như đã chọn bố cục cũ ⇒ máy lớn 420+ (Air / Plus /
    /// Pro Max) bị ghi −2: bước hàng 54 / phím 43 thay stock 56 / 45, cả khối phím thấp hơn stock
    /// 8pt. Giờ: chưa từng chỉnh ⇒ 0 (= bàn phím iPhone, như cài mới). Ai đã chuyển đổi xong:
    /// một lần (`defaultFixKey`) đưa đúng giá trị chuyển đổi đó (−2 trên máy lớn) về 0. Giá trị
    /// khác giữ nguyên. Không phân biệt được −2 do chuyển đổi với −2 tự chọn sau 12/10 trên máy
    /// lớn — trường hợp đó về 0 một lần, chỉnh lại được.
    enum RowAdjust {
        static let key = "rowHeightAdjust"
        static let range: ClosedRange<Int> = -10...10
        /// Cờ đã chuyển sang "0 = bàn phím iPhone".
        static let migratedKey = "rowAdjustStockBase"
        /// Công tắc cũ "Kích thước như bàn phím iPhone" (#119) — chỉ còn đọc để chuyển đổi.
        static let legacyStockKey = "stockKeySize"
        /// Cờ đã sửa mặc định người dùng cũ chưa từng chỉnh (03/11/2026).
        static let defaultFixKey = "rowAdjustDefaultFix"

        /// "Nâng bàn phím" (như Android #112, cùng khoá sao lưu): 0…48pt bước 4, đệm trống
        /// dưới hàng phím đáy.
        static let raiseKey = "keyboardRaise"
        static let raiseMax = 48
        static let raiseStep = 4

        static func clamp(_ a: Int) -> Int { min(max(a, range.lowerBound), range.upperBound) }
        static func clamp(_ a: CGFloat) -> CGFloat {
            min(max(a, CGFloat(range.lowerBound)), CGFloat(range.upperBound))
        }
        static func clampRaise(_ r: Int) -> Int { min(max(r, 0), raiseMax) }
        static func raise(_ d: UserDefaults?) -> Int { clampRaise(d?.integer(forKey: raiseKey) ?? 0) }

        /// Bề ngang dọc lớn hơn mức này = màn hình mở của máy gập (base 208, không stock) ⇒
        /// không biết cỡ máy khi gập, giữ nguyên giá trị.
        static let maxPhonePortraitWidth: CGFloat = 500

        /// Giá trị mới (thuần). `oldAdjust` nil = chưa từng chỉnh (không có khoá) ⇒ 0 trên iPhone
        /// (mặc định = bàn phím iPhone, 03/11/2026). `legacyStock` = khoá công tắc cũ (nil = chưa
        /// có); `fresh` = App Group chưa có cài đặt nào của người dùng (StockSize.initialValue) —
        /// cài mới coi như bật.
        static func migrated(oldAdjust: Int?, legacyStock: Bool?, fresh: Bool,
                             pad: Bool, portraitWidth: CGFloat) -> Int {
            let a = clamp(oldAdjust ?? 0)
            if pad { return a }
            if legacyStock ?? fresh { return 0 }
            // Chưa từng chỉnh và chưa từng tắt công tắc stock ⇒ mặc định mới (bàn phím iPhone).
            // Tắt công tắc một cách tường minh (false) ⇒ đã chọn bố cục cũ, giữ như trước.
            if oldAdjust == nil, legacyStock == nil { return 0 }
            guard portraitWidth > 0, portraitWidth <= maxPhonePortraitWidth,
                  let m = StockSize.metrics(width: portraitWidth, landscape: false) else { return a }
            return clamp(a + Int((phonePortraitBase / 4 - m.pitch).rounded()))
        }

        /// Đọc trạng thái cũ trong `d` rồi tính giá trị mới (không ghi).
        static func migrated(_ d: UserDefaults, pad: Bool, portraitWidth: CGFloat,
                             extraStateKeys: [String] = []) -> Int {
            let legacy: Bool? = d.object(forKey: legacyStockKey) != nil ? d.bool(forKey: legacyStockKey) : nil
            let fresh = legacy == nil && StockSize.initialValue(
                existingKeys: Set(d.dictionaryRepresentation().keys),
                stateKeys: StockSize.userStateKeys.union(extraStateKeys))
            let old: Int? = d.object(forKey: key) != nil ? d.integer(forKey: key) : nil
            return migrated(oldAdjust: old, legacyStock: legacy, fresh: fresh,
                            pad: pad, portraitWidth: portraitWidth)
        }

        /// Sửa một lần cho người đã qua chuyển đổi 12/10 (thuần): giá trị ĐÚNG BẰNG kết quả chuyển
        /// đổi của bố cục mặc định cũ (máy lớn: −2) ⇒ 0; mọi giá trị khác, iPad, máy thường
        /// (chuyển đổi cho 0 sẵn), máy gập mở ⇒ giữ nguyên.
        static func defaultFixed(_ value: Int, pad: Bool, portraitWidth: CGFloat) -> Int {
            let v = clamp(value)
            if pad || v == 0 { return v }
            let legacyDefault = migrated(oldAdjust: 0, legacyStock: false, fresh: false,
                                         pad: false, portraitWidth: portraitWidth)
            return v == legacyDefault ? 0 : v
        }

        /// Giá trị dùng để vẽ (bàn phím): đã chuyển ⇒ đọc thẳng (+ sửa mặc định nếu app chưa
        /// ghi cờ sửa); chưa ⇒ tính trong bộ nhớ.
        static func effectiveAdjust(_ d: UserDefaults?, pad: Bool, portraitWidth: CGFloat) -> Int {
            guard let d else { return 0 }
            if d.bool(forKey: migratedKey) {
                let v = clamp(d.integer(forKey: key))
                return d.bool(forKey: defaultFixKey) ? v : defaultFixed(v, pad: pad, portraitWidth: portraitWidth)
            }
            return migrated(d, pad: pad, portraitWidth: portraitWidth)
        }

        /// App gọi lúc khởi động; chạy một lần (cờ), gọi lại không đổi gì. Trả giá trị hiện hành.
        @discardableResult
        static func migrateIfNeeded(_ d: UserDefaults?, pad: Bool, portraitWidth: CGFloat,
                                    extraStateKeys: [String] = []) -> Int {
            guard let d else { return 0 }
            if d.bool(forKey: migratedKey) {
                let v = clamp(d.integer(forKey: key))
                if d.bool(forKey: defaultFixKey) { return v }
                let fixed = defaultFixed(v, pad: pad, portraitWidth: portraitWidth)
                d.set(true, forKey: defaultFixKey)
                if fixed != v { d.set(fixed, forKey: key) }
                return fixed
            }
            let v = migrated(d, pad: pad, portraitWidth: portraitWidth, extraStateKeys: extraStateKeys)
            // Cờ trước: tiến trình kia (bàn phím) thấy cờ thì không chuyển lần hai.
            d.set(true, forKey: migratedKey)
            d.set(true, forKey: defaultFixKey)
            if v != 0 || d.object(forKey: key) != nil { d.set(v, forKey: key) }
            d.removeObject(forKey: legacyStockKey)
            return v
        }
    }

    /// Số đo bàn phím iPhone gốc = mức 0 của "Chiều cao hàng phím" trên iPhone (trước là công
    /// tắc "Kích thước như bàn phím iPhone", issue #119, iPhone 16 Pro Max / iOS 27: "+4
    /// mỗi hàng vẫn lệch, gõ nhầm vì quen phím iPhone"). Số đo bàn phím Apple English (US)
    /// trên simulator iOS 27.0 (12/10/2026, XCUITest frame + ảnh @3x, đo pixel mép phím; máy:
    /// SE 3, 17e, 17, 17 Pro, Air, 16 Plus, 17 Pro Max):
    ///
    ///   máy (bề ngang dọc)         bước hàng  phím  khe ngang  lề    kính→đỉnh phím  đáy phím→đáy màn
    ///   17e 390, 17/17 Pro 402         54      43       6     6.67   13 / 40 (gợi ý)        71
    ///   Air 420, 16 Plus 430, PM 440   56      45       6     6.67   12.7 / 39.7            82
    ///   SE 375 (nút Home, @2x)         54      42       6     6.5    13.5 / 40.5             4
    ///   ngang (mọi máy có tai thỏ)     40      32      6.67   4.33   7 / 51                 22
    ///
    /// View extension VietTelex (đo cùng simulator, bàn phím bật qua AppleKeyboards): đáy view
    /// cách đáy màn hình 75pt ở dọc trên CẢ 402 lẫn 440 (dải 🌐/mic hệ thống không đổi), 20pt
    /// ở ngang. Máy lớn: phím stock đáy 82 ⇒ phím đáy mình phải nằm CAO hơn đáy view 7pt; bố cục
    /// mặc định (bước 54, phím đáy sát đáy view) đặt hàng Q thấp hơn stock ~18pt trên 16/17 Pro
    /// Max — đúng lỗi #119 ("+4 mỗi hàng" vẫn lệch 3–7pt, phím cao 48 thay 45).
    enum StockSize {
        /// Bề ngang dọc từ đây trở lên = nhóm máy lớn (Air 420, Plus/Pro Max 430/440).
        static let largeMinWidth: CGFloat = 420

        struct Metrics: Equatable {
            var pitch: CGFloat
            var keyHeight: CGFloat
            var keyGap: CGFloat
            var sideMargin: CGFloat
            /// Mép trên khung kính → đỉnh phím hàng 1 khi KHÔNG / CÓ thanh dự đoán.
            var topPad: CGFloat
            var predictiveTopPad: CGFloat
            /// Đáy view extension − đáy phím hàng đáy stock (pt). Dương: phím stock thấp hơn
            /// đáy view mình ⇒ cắt hàng đáy (3 hàng chữ vẫn trùng stock). Âm: phím stock cao hơn
            /// đáy view ⇒ đệm dưới phím đáy.
            var bottomTrim: CGFloat
            var rowGap: CGFloat { pitch - keyHeight }
        }

        /// Dọc máy thường: đáy view 75, phím đáy stock 71 ⇒ cắt 4 (như bố cục mặc định).
        static let standardPortrait = Metrics(pitch: 54, keyHeight: 43, keyGap: 6, sideMargin: 6.67,
                                              topPad: 13, predictiveTopPad: 40, bottomTrim: 4)
        /// Dọc máy lớn: đáy view 75, phím đáy stock 82 ⇒ đệm dưới 7.
        static let largePortrait = Metrics(pitch: 56, keyHeight: 45, keyGap: 6, sideMargin: 6.67,
                                           topPad: 12.67, predictiveTopPad: 39.67, bottomTrim: -7)
        /// Ngang (máy có tai thỏ): đáy view 20, phím đáy stock 22 ⇒ đệm dưới 2.
        static let landscape = Metrics(pitch: 40, keyHeight: 32, keyGap: 6.67, sideMargin: 4.33,
                                       topPad: 7, predictiveTopPad: 51, bottomTrim: -2)
        /// SE (nút Home): bàn phím sát đáy màn hình, phím đáy stock cách đáy 4 ⇒ đệm dưới 4.
        static let homeButtonPortrait = Metrics(pitch: 54, keyHeight: 42, keyGap: 6, sideMargin: 6.5,
                                                topPad: 13.5, predictiveTopPad: 40.5, bottomTrim: -4)
        /// SE ngang: dọc như stock (đo lại bằng VietTelex: hàng đáy trùng 339–371). Ngang KHÔNG
        /// theo stock — stock SE chỉ dùng giữa màn hình (phím 46, lề ~72), view mình full bề ngang
        /// ⇒ giữ lề/khe mặc định.
        static let homeButtonLandscape = Metrics(pitch: 40, keyHeight: 32, keyGap: 6, sideMargin: 6.5,
                                                 topPad: 7, predictiveTopPad: 51, bottomTrim: -4)

        /// Bề ngang chưa layout (0, lúc dựng view): đoán dọc máy thường — cùng khe/lề với dọc
        /// máy lớn nên khi có bề ngang thật không phải dựng lại phím.
        static func metrics(width: CGFloat, landscape: Bool, homeButton: Bool = false) -> Metrics? {
            if homeButton { return landscape ? homeButtonLandscape : homeButtonPortrait }
            if landscape { return Self.landscape }
            return width >= largeMinWidth ? largePortrait : standardPortrait
        }

        /// Strip gợi ý mở theo preset: đỉnh view → đỉnh phím = như thanh dự đoán stock
        /// (dọc 29 + khe 11 = 40 ≈ 39.7–40). Ngang giữ 34 (stock 44 — không cao thêm cho đủ).
        static func openStrip(width: CGFloat, landscape: Bool, homeButton: Bool = false) -> CGFloat? {
            guard let m = metrics(width: width, landscape: landscape, homeButton: homeButton) else { return nil }
            return min(defaultOpenStrip, (m.predictiveTopPad - m.rowGap).rounded())
        }
        /// KeyboardView.openStrip / Wallpaper.suggestionStrip.
        static let defaultOpenStrip: CGFloat = 34

        /// Cài mới hay không: App Group chưa có khoá nào của người dùng ⇒ true (RowAdjust:
        /// cài mới không có trạng thái cũ để chuyển đổi).
        static func initialValue(existingKeys: Set<String>, stateKeys: Set<String> = userStateKeys) -> Bool {
            existingKeys.isDisjoint(with: stateKeys)
        }
        /// Khoá chỉ xuất hiện khi người dùng đã dùng app/bàn phím (đổi cài đặt, thêm mẫu câu,
        /// bàn phím đã chạy với Toàn quyền…).
        static let userStateKeys: Set<String> = [
            "rowHeightAdjust", "numberRow", "showSuggestions", "simpleTelex", "templatesEnabled",
            "userTemplates", "kbLastSeen", "kbFullAccess", "keyboardTheme", "showSpaceLogo",
            "splitKeyboard", "keyPreviewEnabled", "hapticFeedback", "swipeTyping", "uiLanguage",
            "numberRowFullHeight",
        ]
    }

    /// Số đo stock iOS 26/27 (xem đầu file) — tâm phím tính từ ĐÁY MÀN HÌNH, pt.
    enum Stock {
        static let rowCentersFromScreenBottom: [CGFloat] = [254.5, 200.5, 146.5, 92.5]
        static let keyHeight: CGFloat = 43
        static let sideMargin: CGFloat = 6.6
        /// Đáy view extension so với đáy màn hình (vùng 🌐/mic hệ thống bên dưới).
        static let viewBottomAboveScreenBottom: CGFloat = 75
        /// Hàng đáy stock trên máy 402pt: 123 / emoji tâm x.
        static let planeKeyMidX: CGFloat = 28.3, emojiKeyMidX: CGFloat = 77.7
        /// Hàng đáy (ô có "."): tâm "." và return, quy từ máy 393 → 402 theo tỉ lệ.
        static let periodMidXFraction: CGFloat = 302.5 / 393, returnMidXFraction: CGFloat = 355.9 / 393
    }

    /// Chữ trên phím iPhone khớp stock iOS 26/27 (đo 27/09/2026, ảnh @3x simulator iPhone 17,
    /// dark, English US; khớp bbox 25 chữ hoa + 23 chữ thường, sai số rms 0.4–0.6px @3x):
    ///  • Stock dùng SF COMPACT (không phải SF Pro): chữ O/C/G/o/c hẹp — SF Pro cỡ nào cũng
    ///    rộng hơn 4–6px. Lấy qua `SystemDesign("NSCTFontUIFontDesignCompact")`.
    ///  • Chữ THƯỜNG to hơn chữ HOA: thường 24.5pt, hoa/số/ký hiệu 22.7pt (Regular). Trước:
    ///    SF Pro 23 cho tất cả → chữ thường nhỏ hơn stock (x-height 35 vs 38px), chữ hoa to hơn.
    ///  • Mọi phím chung MỘT baseline: 28pt dưới đỉnh phím 43 (15pt trên đáy) — x-height chữ
    ///    thường nằm giữa phím, chữ hoa nhô lên 1pt. UIButton căn giữa hộp dòng (ascender +
    ///    descender) → baseline thấp hơn stock 1.3–2.3pt ("chữ nằm thấp").
    ///  • 123/ABC hàng đáy: Compact 18.9 (trước SF 16). #+=/123 hàng 3 plane số: 16.
    enum Typography {
        static let lowercaseSize: CGFloat = 24.5
        static let keycapSize: CGFloat = 22.7
        static let planeKeySize: CGFloat = 18.9
        static let rowToggleSize: CGFloat = 16
        /// Máy không có SF Compact: SF Pro khớp bbox stock tốt nhất ở cỡ này.
        static let fallbackLowercaseSize: CGFloat = 24.5
        static let fallbackKeycapSize: CGFloat = 21.3
        static let stockBaselineFromTop: CGFloat = 28

        /// Nhãn là chữ thường (a, đ, ư…) → cỡ lớn; chữ hoa, số, ký hiệu → cỡ keycap.
        static func isLowercase(_ title: String) -> Bool {
            !title.isEmpty && title == title.lowercased() && title != title.uppercased()
        }
        static func size(for title: String, compact: Bool) -> CGFloat {
            isLowercase(title) ? (compact ? lowercaseSize : fallbackLowercaseSize)
                               : (compact ? keycapSize : fallbackKeycapSize)
        }
        /// Baseline tính từ đỉnh phím cao `h`. Phím ≥43: đáy trùng stock, phần dư nằm trên
        /// (hàng chữ 44 của mình nhô 1pt lên trên) → baseline cách đáy 15 như stock. Phím
        /// thấp hơn (ngang, hàng số): theo tỉ lệ 28/43.
        static func baselineFromTop(keyHeight h: CGFloat) -> CGFloat {
            let k = Stock.keyHeight
            return h >= k ? h - (k - stockBaselineFromTop) : stockBaselineFromTop * h / k
        }
        /// Dịch dọc (âm = lên) cho nhãn đang căn giữa phím bằng hộp dòng của font
        /// (ascender > 0, descender < 0) để baseline về đúng `baselineFromTop`.
        static func titleOffsetY(keyHeight h: CGFloat, ascender: CGFloat, descender: CGFloat) -> CGFloat {
            let natural = h / 2 + (ascender + descender) / 2
            return baselineFromTop(keyHeight: h) - natural
        }
        /// Dịch dọc để baseline hộp dòng (căn giữa phím cao `h`) về `target` pt dưới đỉnh.
        static func offsetY(toBaseline target: CGFloat, keyHeight h: CGFloat,
                            ascender: CGFloat, descender: CGFloat) -> CGFloat {
            target - (h / 2 + (ascender + descender) / 2)
        }

        /// Chữ trên phím iPad khớp stock iPadOS 27 (đo 27/09/2026, ảnh @2x simulator iPad
        /// Pro 11" M5 / iPad mini A17 / iPad Pro 13" M5, English US, dark + light):
        ///  • Cũng SF COMPACT Regular, nhưng chữ HOA và thường CÙNG cỡ (khác iPhone):
        ///    khớp bbox stock ≈ 21.5 dọc / 26.6 ngang — y hệt trên cả 3 máy (cỡ theo hướng,
        ///    không theo máy). Cỡ đặt: dọc 22 (UIKit vẽ Compact 21.5 dọc nhỏ hơn stock ~1px,
        ///    đo lại ảnh VietTelex → 22 khớp), ngang 26.6. Trước: SF Pro 23 cả hai hướng.
        ///  • Chữ + ký tự phụ (vuốt xuống) là một khối căn theo TÂM phím: baseline chữ dưới tâm
        ///    18.25 (dọc) / 22.25 (ngang), baseline ký tự phụ trên tâm 8.75 / 12 trên phím
        ///    stock 54.5 / 74 (mọi máy) — co theo tỉ lệ chiều cao phím mình (xem dưới).
        ///    Plane số (@ % …) có ký tự phụ: cùng số đo với phím chữ.
        ///  • Ký tự phụ: Compact 12.5 / 15.5, alpha 0.30 tối / 0.25 sáng (trước SF 13, 0.4).
        ///  • Phím số/ký hiệu không có ký tự phụ (căn giữa): 22 / 26.8, baseline dưới tâm
        ///    8.5 / 9.25.
        ///  • Nhãn phím chức năng (.?123, ABC, #+=, 123): Compact 14.6 / 19.4 (trước SF 14),
        ///    dạt góc dưới: baseline cách đáy 8.5 / 13.5, mép chữ cách cạnh 7.5 / 10.
        ///  • Icon (tab ⇪ ⇧ ⌫ return 🌐 ⌨︎): SF Symbol 22.5 / 23.5pt, mép icon cách cạnh
        ///    5.5 / 8.5, cách đáy 5.5 / 9.5.
        ///  • Phím dấu 2 tầng (! trên , / ? trên .): Compact 20.3 / 30, baseline trên
        ///    −1.25 / −0.5, dưới +16.5 / +19.5 so với tâm.
        ///  • Kiểu compact (iPad mini — KeyLayout.PadStyle): icon GIỮA phím 23.5 / 25pt, nhãn
        ///    123/ABC giữa phím Compact 20 / 27, #+= 18 / 23 (đo ink mini: cao 14 / 19, 12 / 15).
        ///
        /// Đo lại 27/09 tối (Phil: "icon/text gần bottom quá"): phím stock cao 54.5 dọc / 74
        /// ngang, phím mình 50 / 65 (bàn phím gọn hơn stock — ý Phil 24/07). Số đo "dưới/trên
        /// tâm" ở trên là của phím STOCK → co theo tỉ lệ chiều cao phím thật (`scaled`), không
        /// thì chữ dạt đáy (khe đáy chữ 6.5 thay 9.5). Nhãn/icon góc dưới giữ khoảng cách
        /// tuyệt đối tới đáy như stock (đo ink: icon cách đáy 5 / 9, nhãn 7.5 / 13).
        enum Pad {
            struct Metrics: Equatable {
                var stockKeyHeight: CGFloat
                var letterSize: CGFloat
                var letterBaselineBelowCenter: CGFloat
                var hintSize: CGFloat
                var hintBaselineAboveCenter: CGFloat
                var digitSize: CGFloat
                var digitBaselineBelowCenter: CGFloat
                var labelSize: CGFloat
                var labelBaselineAboveBottom: CGFloat
                var labelSideInset: CGFloat
                var iconPointSize: CGFloat
                var iconSideInset: CGFloat
                var iconBottomInset: CGFloat
                var punctSize: CGFloat
                var punctUpperBaselineBelowCenter: CGFloat
                var punctLowerBaselineBelowCenter: CGFloat
                var centerIconPointSize: CGFloat
                var centerLabelSize: CGFloat
                var centerToggleLabelSize: CGFloat

                /// Khoảng cách đo trên phím stock → phím cao `h` (giữ tỉ lệ so với tâm).
                func scaled(_ v: CGFloat, keyHeight h: CGFloat) -> CGFloat {
                    h > 0 ? v * h / stockKeyHeight : v
                }
            }
            static let portrait = Metrics(
                stockKeyHeight: 54.5,
                letterSize: 22, letterBaselineBelowCenter: 18.25,
                hintSize: 12.5, hintBaselineAboveCenter: 8.75,
                digitSize: 22, digitBaselineBelowCenter: 8.5,
                labelSize: 14.6, labelBaselineAboveBottom: 8.5, labelSideInset: 7.5,
                iconPointSize: 22.5, iconSideInset: 5.5, iconBottomInset: 5.5,
                punctSize: 20.3, punctUpperBaselineBelowCenter: -1.25, punctLowerBaselineBelowCenter: 16.5,
                centerIconPointSize: 23.5, centerLabelSize: 20, centerToggleLabelSize: 18)
            static let landscape = Metrics(
                stockKeyHeight: 74,
                letterSize: 26.6, letterBaselineBelowCenter: 22.25,
                hintSize: 15.5, hintBaselineAboveCenter: 12,
                digitSize: 26.8, digitBaselineBelowCenter: 9.25,
                labelSize: 19.4, labelBaselineAboveBottom: 13.5, labelSideInset: 10,
                iconPointSize: 23.5, iconSideInset: 8.5, iconBottomInset: 9.5,
                punctSize: 30, punctUpperBaselineBelowCenter: -0.5, punctLowerBaselineBelowCenter: 19.5,
                centerIconPointSize: 25, centerLabelSize: 27, centerToggleLabelSize: 23)
            static func metrics(landscape: Bool) -> Metrics { landscape ? Self.landscape : portrait }
            /// Alpha ký tự phụ (vuốt xuống) trên nền phím, như stock: tối trắng 0.30 (xám 124
            /// trên phím 68), sáng đen 0.25 (191 trên phím trắng).
            static func hintAlpha(dark: Bool) -> CGFloat { dark ? 0.30 : 0.25 }
            /// Ảnh SF Symbol có lề trong quanh nét (≈ 6% cỡ ngang, 9% dưới — đo ở 17pt:
            /// 1 / 1.5pt) → contentEdgeInset = mép-nét-mong-muốn − lề trong.
            static func iconContentInsets(_ m: Metrics) -> (side: CGFloat, bottom: CGFloat) {
                (max(m.iconSideInset - 0.06 * m.iconPointSize, 0),
                 max(m.iconBottomInset - 0.09 * m.iconPointSize, 0))
            }
        }
    }
}

/// Khung ô phóng to chữ (balloon) quanh phím — THUẦN để unit-test (tester 1.2.8: "bấm q, p, -
/// sát viền không có hiệu ứng phóng to"). Như stock: bubble đặt giữa phím, nhưng sát mép màn
/// hình thì DỜI VÀO TRONG (bubble lệch, cổ lệch về phía phím) thay vì tràn ra ngoài bị cắt.
/// Đỉnh không vượt `topLimit` (extension không vẽ được trên bounds của nó).
enum BalloonGeometry {
    /// Bubble rộng hơn phím 24pt, tối thiểu 52; cao trên phím tối đa 52.
    static let extraWidth: CGFloat = 24, minWidth: CGFloat = 52, rise: CGFloat = 52
    /// Ô phóng to tối thiểu hiện chừng này (giây) sau khi chạm: iOS có thể giữ touch ở sát mép
    /// màn hình (phân xử cử chỉ hệ thống) rồi giao began + ended CÙNG lúc ⇒ balloon hiện rồi ẩn
    /// trong cùng một vòng runloop, không bao giờ lên màn hình. Gõ thường (≥ 70ms/chạm) không
    /// bị ảnh hưởng; chạm phím mới luôn dời balloon sang phím mới ngay.
    static let minVisible: Double = 0.07

    static func frame(keyRect k: CGRect, containerWidth W: CGFloat, topLimit: CGFloat) -> CGRect {
        let w = max(k.width + extraWidth, minWidth)
        let top = max(k.minY - rise, topLimit)
        var x = k.midX - w / 2
        if W >= w { x = min(max(x, 0), W - w) }
        // Phím luôn nằm trọn dưới bubble (cổ nối được xuống footprint phím).
        x = min(x, k.minX)
        x = max(x, k.maxX - w)
        return CGRect(x: x, y: top, width: w, height: max(k.maxY - top, 0))
    }

    /// Ẩn balloon ngay (0) hay đợi thêm (giây) — `shownFor` = thời gian đã hiện.
    static func hideDelay(shownFor: Double) -> Double {
        shownFor >= minVisible ? 0 : minVisible - shownFor
    }
}

/// "Phím cạnh dấu cách" (Tính năng → Phím & cử chỉ; khoá App Group `spaceSideKey`, cùng chuỗi
/// với Android Keys.SPACE_SIDE_KEY): phím hẹp bên phải space ở hàng đáy bàn CHỮ iPhone, ô thường.
///  • `.comma` (mặc định, bố cục cũ): "," — giữ ra "." (khi bật giữ phím ra ký tự phụ).
///  • `.period`: "." cùng chỗ cùng cỡ — giữ ra ",".
///  • `.both` (16/10/2026, "Cả hai"): "," TRÁI space + "." PHẢI space, mỗi phím cùng cỡ phím hẹp
///    cũ, space co lại. "," giữ ra "." như mặc định; "." không có giữ phím (như iPad).
///  • `.off`: không phím; space rộng thêm. Chạm space hai lần vẫn ra ". ".
/// iPad, ô email / URL / thanh địa chỉ, plane số / ký hiệu / mẫu câu không đổi. Đọc lúc
/// dựng hàng đáy (applyAppearance) — 0 chi phí mỗi phím.
enum SpaceSideKey: String, CaseIterable {
    case comma, period, both, off
    static let key = "spaceSideKey"
    static let defaultValue: SpaceSideKey = .comma

    /// Ký tự của phím CÓ GIỮ PHÍM (nil = không có phím): `.both` ⇒ "," (bên trái space).
    var char: String? {
        switch self { case .comma, .both: return ","; case .period: return "."; case .off: return nil }
    }
    /// Ký tự giữ phím [char] ra (phím còn lại của cặp , / .).
    var holdAlt: String? {
        switch self { case .comma, .both: return "."; case .period: return ","; case .off: return nil }
    }
    /// Phím hẹp BÊN TRÁI space (chỉ `.both`).
    var left: String? { self == .both ? "," : nil }
    /// Phím hẹp BÊN PHẢI space.
    var right: String? {
        switch self { case .comma: return ","; case .period, .both: return "."; case .off: return nil }
    }
    /// Giá trị lạ / thiếu ⇒ mặc định.
    static func parse(_ raw: Any?) -> SpaceSideKey {
        (raw as? String).flatMap(SpaceSideKey.init(rawValue:)) ?? defaultValue
    }
    static func load(_ d: UserDefaults?) -> SpaceSideKey { parse(d?.object(forKey: key)) }
}

/// "Về bàn chữ sau ký hiệu" (Tính năng → Phím & cử chỉ; khoá App Group `symbolReturn`, cùng chuỗi
/// với Android Keys.SYMBOL_RETURN; 06/11/2026). Chạm một ký tự ở plane 123/#+= rồi:
///  • `.auto` (mặc định, "Tự động"): dấu kết vế . , ? ! ) " ' : ; (… ” ’ ») về chữ ngay; ký hiệu khác ở lại.
///  • `.always` ("Luôn"): MỌI ký hiệu về chữ ngay; chữ số ở lại.
///  • `.off` ("Tắt"): không về sau ký hiệu — chỉ dấu cách đưa về chữ.
/// Ngay sau chữ số thì . , : ở lại (2.5, 1,000, 10:30); ô số không bao giờ về. Dấu cách vẫn đưa
/// về chữ ở cả ba chế độ (PlanePolicy.returnToLettersOnSpace). Đọc lúc hiện — 0 chi phí mỗi phím.
enum SymbolReturn: String, CaseIterable {
    case auto, always, off
    static let key = "symbolReturn"
    static let defaultValue: SymbolReturn = .auto
    /// Giá trị lạ / thiếu ⇒ mặc định.
    static func parse(_ raw: Any?) -> SymbolReturn {
        (raw as? String).flatMap(SymbolReturn.init(rawValue:)) ?? defaultValue
    }
    static func load(_ d: UserDefaults?) -> SymbolReturn { parse(d?.object(forKey: key)) }
}

/// "Phím to" (Tính năng → Phím & cử chỉ; khoá App Group `largeKeys`, mặc định TẮT ⇒ bố cục y
/// hệt bàn phím iPhone). Góp ý người dùng 04/11/2026: "," "." cạnh phím cách nhỏ quá — hay chạm
/// nhầm phím cách; ⇧ / ⌫ hàng Z chừa khe trống mỗi bên. Bật (chỉ iPhone — iPad không đổi):
///  • Hàng đáy iPhone (plane chữ / số / ký hiệu / mẫu câu, cả bàn tách đôi): phím "," / "."
///    rộng bằng phím emoji (= phím 123, 0.108 bề ngang hàng). Phím cách co lại đúng phần đó
///    nhưng phần của nó (kể cả khe) không dưới `minSpaceUnits` — chỉ chạm tới khi SE có 🌐
///    + "Cả hai" ("," và "."): khi đó hai phím rộng ít hơn, không bao giờ hẹp hơn lúc tắt.
///    Phím "@" (ô email), "/" (ô URL) giữ nguyên.
///  • Hàng Z plane chữ iPhone: khe ⇧↔z và m↔⌫ = khe giữa chữ (6 thay 12) ⇒ ⇧ / ⌫ mỗi phím
///    rộng thêm đúng phần khe đó; z…m giữ nguyên cỡ và vị trí (hàng đối xứng).
/// Đọc lúc dựng hàng (applyAppearance → rebuild) — chỉ đổi hằng số constraint, 0 chi phí mỗi
/// phím; tắt = đúng các số cũ (test).
enum LargeKeys {
    static let key = "largeKeys"
    static let defaultValue = false
    static func load(_ d: UserDefaults?) -> Bool { d?.bool(forKey: key) ?? defaultValue }

    /// Dòng cài đặt "Cỡ phím chấm và phẩy" chỉ hiện khi có phím cạnh dấu cách (Tắt ⇒ ẩn; giá trị giữ nguyên).
    static func settingVisible(_ side: SpaceSideKey) -> Bool { side != .off }

    /// Bề rộng "," / "." khi bật = phím emoji / 123 của hàng đáy iPhone (KeyLayout.phoneBottom).
    static let punctUnits: CGFloat = 0.108
    /// Phần tối thiểu của hàng (phím cách + khe/lề quanh nó) dành cho phím cách: ≈ 86pt phím
    /// cách trên SE 375 có 🌐 + "Cả hai" (trường hợp chật nhất) — đủ chỗ giữ-kéo con trỏ, vuốt
    /// đổi ngôn ngữ và logo Vᴛ / VI·EN.
    static let minSpaceUnits: CGFloat = 0.36

    /// Phím hàng đáy được nở khi bật.
    static func widens(_ title: String) -> Bool { title == "," || title == "." }

    /// Tỉ lệ bề rộng (phần bề ngang hàng) của các phím dấu câu hàng đáy theo thứ tự `puncts`.
    /// `otherUnits` = tổng phần các phím cố định khác (123, 🌐, 😊, return). Tắt ⇒ trả nguyên.
    static func punctUnits(_ puncts: [(title: String, units: CGFloat)], otherUnits: CGFloat,
                           on: Bool) -> [CGFloat] {
        let off = puncts.map(\.units)
        guard on else { return off }
        let grow = puncts.filter { widens($0.title) }.count
        guard grow > 0 else { return off }
        let fixed = otherUnits + puncts.filter { !widens($0.title) }.reduce(0) { $0 + $1.units }
        let target = min(punctUnits, (1 - minSpaceUnits - fixed) / CGFloat(grow))
        return puncts.map { widens($0.title) ? max($0.units, target) : $0.units }
    }

    /// Khe ⇧↔z, m↔⌫ hàng Z iPhone: bật ⇒ bằng khe giữa chữ.
    static func shiftGap(on: Bool, standard: CGFloat, keyGap: CGFloat) -> CGFloat {
        on ? keyGap : standard
    }

    // MARK: Mô hình hàng phím (test) — như UIStackView .fill: phím có `units` = units × bề
    // ngang hàng (constraint multiplier theo stack.widthAnchor), đúng MỘT phím co giãn (nil)
    // ăn phần còn lại sau lề hai bên và khe.

    struct Span: Equatable { var x: CGFloat; var width: CGFloat; var maxX: CGFloat { x + width } }

    static func rowSpans(width: CGFloat, margin: CGFloat, gaps: [CGFloat], units: [CGFloat?]) -> [Span] {
        precondition(gaps.count == max(units.count - 1, 0))
        let fixed = units.compactMap { $0 }.reduce(0, +) * width
        let flex = width - 2 * margin - gaps.reduce(0, +) - fixed
        var x = margin, out: [Span] = []
        for (i, u) in units.enumerated() {
            let w = u.map { $0 * width } ?? flex
            out.append(Span(x: x, width: w))
            x += w + (i < gaps.count ? gaps[i] : 0)
        }
        return out
    }

    /// Hàng Z iPhone (KeyboardView.buildLetters): [⇧] khe sg [z … m] khe sg [⌫]; phím chữ =
    /// phím q hàng 1 ((W − 2·lề − 9·khe)/10), ⇧ = ⌫ ăn phần còn lại.
    static func zRowSpans(width: CGFloat, margin: CGFloat, keyGap: CGFloat, standardShiftGap: CGFloat,
                          on: Bool) -> [Span] {
        let letter = (width - 2 * margin - 9 * keyGap) / 10
        let sg = shiftGap(on: on, standard: standardShiftGap, keyGap: keyGap)
        let side = (width - 2 * margin - 7 * letter - 6 * keyGap - 2 * sg) / 2
        var x = margin, out = [Span(x: x, width: side)]
        x += side + sg
        for i in 0..<7 { out.append(Span(x: x, width: letter)); x += letter + (i < 6 ? keyGap : sg) }
        out.append(Span(x: x, width: side))
        return out
    }
}

/// "Nút emoji" (Tính năng → Phím & cử chỉ; khoá App Group `emojiKeyPlacement`, cùng chuỗi với
/// Android Keys.EMOJI_KEY_PLACEMENT):
///  • `.bottom` (mặc định): phím 😊 ở hàng đáy bàn chữ như cũ.
///  • `.top` ("Thanh trên"): bỏ 😊 khỏi hàng đáy bàn CHỮ iPhone (space ăn chỗ), nút 😊 lên thanh
///    gợi ý (sát mép phải, trái 📋). Thanh gợi ý không hiện ở ô này (tắt gợi ý,
///    ô mật khẩu…) ⇒ giữ 😊 ở hàng đáy để emoji không bao giờ mất lối vào ([emojiInBar]).
/// iPad / bàn tách đôi / plane số, ký hiệu không đổi. Đọc lúc dựng hàng đáy — 0 chi phí mỗi phím.
enum EmojiKeyPlacement: String, CaseIterable {
    case bottom, top
    static let key = "emojiKeyPlacement"
    static let defaultValue: EmojiKeyPlacement = .bottom
    static func parse(_ raw: Any?) -> EmojiKeyPlacement {
        (raw as? String).flatMap(EmojiKeyPlacement.init(rawValue:)) ?? defaultValue
    }
    static func load(_ d: UserDefaults?) -> EmojiKeyPlacement { parse(d?.object(forKey: key)) }

    /// Nút 😊 nằm trên thanh gợi ý (và KHÔNG ở hàng đáy bàn chữ)? Chỉ khi chọn `.top`, thanh
    /// gợi ý đang bật cho ô này, và iPhone (iPad giữ hàng đáy stock).
    static func emojiInBar(_ p: EmojiKeyPlacement, barShown: Bool, pad: Bool) -> Bool {
        p == .top && barShown && !pad
    }
}
