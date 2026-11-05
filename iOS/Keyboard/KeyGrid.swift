// KeyGrid — lưới phím XẾP TAY (thay UIStackView + Auto Layout cho bàn chữ / số / ký hiệu).
//
// Khởi động lạnh (đo 11/2026, KeyboardStartupTests): ~30–40% thời gian tới khung đầu là Auto
// Layout giải lưới phím (stack .fillEqually + ràng buộc giữa các hàng + thang ưu tiên
// 997/998/999/900). Ở đây mọi khung tính bằng số học trong một lượt layoutSubviews:
//   • KeyRowLayout (THUẦN, unit-test được) — bề rộng từng phím của một hàng theo luật cũ của
//     stack: bằng nhau (phím chữ), cố định, phần bề rộng hàng (hàng đáy), bội số phím neo
//     (iPad, z = q), co giãn (space, ⇧/⌫ chia đôi phần còn lại), tỉ lệ nội dung (hàng 3 bàn số —
//     đúng thứ tự ưu tiên .fillProportionally của UIStackView), + chiều cao từng hàng.
//   • Mép mỗi khung làm tròn về pixel ĐỘC LẬP (như Auto Layout) ⇒ khung y hệt bản stack.
//   • KeyRow / KeyGridView — view rỗng, không constraint; hàng tự xếp phím theo bounds của nó
//     (dùng được cả trong UIStackView của plane mẫu câu).
import UIKit

enum KeyRowLayout {
    /// Luật bề rộng một phần tử trong hàng.
    enum Width: Equatable {
        /// Bề rộng cố định (bàn tách đôi).
        case fixed(CGFloat)
        /// Phần bề rộng CẢ hàng (kể cả lề) — hàng đáy (KeyLayout.phoneBottom…).
        case fraction(CGFloat)
        /// Bội số bề rộng phím neo (iPad: q / 1; iPhone hàng 3: z…m = q).
        case units(CGFloat)
        /// Nhóm bằng nhau (phím ký tự thường của hàng) — chia phần còn lại.
        case equal
        /// Co giãn: chia đều phần còn lại (space; ⇧ = ⌫ hàng 3).
        case flex
    }

    /// Bề rộng từng phần tử. `inner` = bề ngang hàng trừ lề trái/phải; `rowWidth` = cả hàng
    /// (cho .fraction); `spacing` = tổng khe; `ref` = bề rộng phím neo (nil = hàng này tự là neo).
    static func widths(_ items: [Width], rowWidth: CGFloat, inner: CGFloat, spacing: CGFloat,
                       ref: CGFloat?) -> [CGFloat] {
        var known: CGFloat = 0
        var equal = 0, flex = 0
        var unitsSum: CGFloat = 0
        for w in items {
            switch w {
            case .fixed(let v): known += v
            case .fraction(let f): known += f * rowWidth
            case .units(let u): unitsSum += u
            case .equal: equal += 1
            case .flex: flex += 1
            }
        }
        let free = inner - spacing - known
        // Hàng neo (chỉ units, không phím co giãn): bề rộng neo = phần còn lại / tổng units.
        let r: CGFloat = ref ?? (equal == 0 && flex == 0 && unitsSum > 0 ? free / unitsSum : 0)
        let rest = free - unitsSum * r
        let share: CGFloat = equal > 0 ? rest / CGFloat(equal) : 0
        let flexShare: CGFloat = equal == 0 && flex > 0 ? rest / CGFloat(flex) : 0
        return items.map { w in
            switch w {
            case .fixed(let v): return v
            case .fraction(let f): return f * rowWidth
            case .units(let u): return u * r
            case .equal: return share
            case .flex: return flexShare
            }
        }
    }

    /// Bề rộng phím neo của hàng neo (`items` không có .flex) — các hàng khác dùng .units theo nó.
    static func anchorWidth(_ items: [Width], rowWidth: CGFloat, inner: CGFloat, spacing: CGFloat) -> CGFloat {
        let w = widths(items, rowWidth: rowWidth, inner: inner, spacing: spacing, ref: nil)
        for (i, it) in items.enumerated() {
            switch it {
            case .equal: return w[i]
            case .units(let u) where u > 0: return w[i] / u
            default: continue
            }
        }
        return 0
    }

    /// Hàng .fillProportionally của UIStackView (hàng 3 bàn số iPhone: #+= . , ? ! ' ⌫): mỗi phần
    /// tử muốn `nội dung_i / (Σ nội dung + Σ khe) × (bề ngang trong)` với ưu tiên GIẢM DẦN theo thứ
    /// tự (999, 998…), các phím cùng `group` buộc bằng nhau, `minimum` bắt buộc; phần tử cuối
    /// chưa chốt nhận phần còn lại. Thuần — khớp lời giải Auto Layout (đo 11/2026).
    static func proportional(intrinsic: [CGFloat], group: [Int], minimum: [CGFloat],
                             inner: CGFloat, spacing: CGFloat) -> [CGFloat] {
        let n = intrinsic.count
        guard n > 0 else { return [] }
        let total = intrinsic.reduce(0, +) + spacing
        var chosen: [Int: CGFloat] = [:]
        let groups = Array(Set(group))
        func count(_ g: Int) -> Int { group.filter { $0 == g }.count }
        func minOf(_ g: Int) -> CGFloat { zip(group, minimum).filter { $0.0 == g }.map(\.1).max() ?? 0 }
        var remaining = inner - spacing
        for i in 0..<n {
            let g = group[i]
            guard chosen[g] == nil else { continue }
            let others = groups.filter { $0 != g && chosen[$0] == nil }
            let c = CGFloat(count(g))
            if others.isEmpty {
                chosen[g] = max(remaining / c, 0)
                remaining = 0
                break
            }
            let want = total > 0 ? intrinsic[i] / total * inner : 0
            let reserve = others.reduce(CGFloat(0)) { $0 + minOf($1) * CGFloat(count($1)) }
            let hi = (remaining - reserve) / c
            let w = max(min(want, hi), minOf(g))
            chosen[g] = w
            remaining -= w * c
        }
        return group.map { chosen[$0] ?? 0 }
    }

    /// Chiều cao các hàng: `header` cố định ở đầu (ô tìm emoji), còn lại theo `spec`.
    enum Heights: Equatable {
        /// Mọi hàng bằng nhau (iPad không hàng số).
        case equal
        /// Hàng = r; hàng cuối = r − trim; hàng số (nếu có) = mult·r + const.
        case ref(numberRow: NumberRow?, trim: CGFloat)
        struct NumberRow: Equatable { var multiplier: CGFloat; var constant: CGFloat }
    }

    static func heights(total: CGFloat, count n: Int, spec: Heights, header: CGFloat?) -> [CGFloat] {
        guard n > 0 else { return header.map { [$0] } ?? [] }
        let h = total - (header ?? 0)
        var out: [CGFloat] = header.map { [$0] } ?? []
        switch spec {
        case .equal:
            out += Array(repeating: h / CGFloat(n), count: n)
        case .ref(let num, let trim):
            if let num, n >= 2 {
                let r = (h - num.constant + trim) / (num.multiplier + CGFloat(n - 1))
                out.append(num.multiplier * r + num.constant)
                out += Array(repeating: r, count: n - 2)
                out.append(r - trim)
            } else {
                let r = (h + trim) / CGFloat(n)
                out += Array(repeating: r, count: n - 1)
                out.append(r - trim)
            }
        }
        return out
    }

    /// Vùng hàng phím theo thang ưu tiên cũ (rows ↔ view): đáy = đáy view − `bottomInset` (bắt
    /// buộc); cao ≤ `rows` + 60 và đỉnh ≥ 0 (bắt buộc); đỉnh ≥ `minTop` (999); cao ≥ `rows`
    /// (998); đỉnh = `top` (997); cao = `rows` (900). Trả (đỉnh, cao). Lý do từng bậc:
    ///   • host thường cấp NHIỀU hơn mức xin (~25pt, iOS 26) ⇒ phím hấp thụ phần dư thay vì dải
    ///     trống trên đỉnh (user 2026-07-24); trần +60 để cú áp khung khổng lồ lúc host đang settle
    ///     không kéo phím giãn vô hạn (vụ 'flash' cũ) — quá trần thì phần dư tràn lên trên;
    ///   • host cấp THIẾU ⇒ strip gợi ý co trước, phím giữ đủ cao (bug 1.2.x: phím lùn ở
    ///     Notes/Facebook); đỉnh ≥ 0 chặn hàng phím tràn khỏi đỉnh khi thiếu cả vùng phím;
    ///   • sàn đỉnh = headroom balloon: strip nhường tới đó rồi phím mới co — balloon hàng đầu
    ///     luôn có chỗ (bug 30/09/2026);
    ///   • đáy = đáy view − safe area máy gập (tránh vạch home) − "Nâng bàn phím".
    static func rowsArea(viewHeight: CGFloat, bottomInset: CGFloat, top: CGFloat, rows: CGFloat,
                         minTop: CGFloat) -> (top: CGFloat, height: CGFloat) {
        let b = viewHeight - bottomInset
        let upper = max(min(rows + 60, b, b - minTop), 0)
        let lower = min(rows, upper)
        let h = min(max(b - top, lower), upper)
        return (b - h, h)
    }

    /// Làm tròn một toạ độ (toạ độ gốc lưới) về pixel như Auto Layout làm tròn từng mép khung:
    /// gần nhất; đúng NỬA pixel (kể cả sai số cộng dồn ±1e-4) thì làm tròn LÊN.
    static func px(_ v: CGFloat, _ scale: CGFloat) -> CGFloat {
        let t = v * scale
        let f = t.rounded(.down)
        if abs(t - f - 0.5) < 1e-4 { return (f + 1) / scale }
        return t.rounded() / scale
    }

    /// Khung đã làm tròn mép (toạ độ tuyệt đối) của đoạn [x0, x1] × [y0, y1].
    static func rounded(x0: CGFloat, x1: CGFloat, y0: CGFloat, y1: CGFloat, scale: CGFloat) -> CGRect {
        let a = px(x0, scale), b = px(x1, scale), c = px(y0, scale), d = px(y1, scale)
        return CGRect(x: a, y: c, width: max(b - a, 0), height: max(d - c, 0))
    }
}

/// Ô trống trong hàng (khe giữa hai nửa bàn tách đôi, ô thụt iPad compact) — không nhận chạm.
final class KeySpacer: UIView {
    var rowWidth: KeyRowLayout.Width
    init(_ w: KeyRowLayout.Width) {
        rowWidth = w
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// Một hàng phím (thay UIStackView ngang): phần tử + luật bề rộng, khe, lề — tự xếp khung
/// trong layoutSubviews theo bounds (hoặc khung chính xác cha đặt, để làm tròn như Auto Layout).
final class KeyRow: UIView {
    private(set) var arrangedSubviews: [UIView] = []
    var spacing: CGFloat { didSet { if spacing != oldValue { setNeedsLayout() } } }
    var margins: UIEdgeInsets { didSet { if margins != oldValue { setNeedsLayout() } } }
    private var customSpacing: [ObjectIdentifier: CGFloat] = [:]
    /// Luật của từng phần tử (mặc định: phím ký tự thường = .equal, còn lại = .flex).
    private var rules: [ObjectIdentifier: KeyRowLayout.Width] = [:]
    /// Hàng neo bề rộng phím cho .units (nil = hàng này tự neo / không dùng units).
    weak var anchor: KeyRow?
    /// Hàng .fillProportionally (hàng 3 bàn số iPhone): nội dung / nhóm bằng nhau / tối thiểu.
    var proportional: (intrinsic: (UIView) -> CGFloat, group: (UIView) -> Int, minimum: (UIView) -> CGFloat)?
    /// Bề rộng của hàng khi làm phần tử của hàng cha (nửa trái/phải bàn tách đôi).
    var rowWidth: KeyRowLayout.Width = .flex
    /// Khung CHÍNH XÁC (chưa làm tròn, toạ độ gốc lưới = KeyboardView) do cha đặt + gốc đã làm
    /// tròn của chính view này. Như Auto Layout: mọi mép tính chính xác rồi làm tròn theo toạ độ
    /// gốc; khung local = khung đã tròn − gốc đã tròn của cha. nil ⇒ bounds (hàng trong UIStackView).
    var exactFrame: CGRect?
    var roundedOrigin: CGPoint = .zero

    init(_ views: [UIView], spacing: CGFloat, margins: UIEdgeInsets) {
        self.spacing = spacing
        self.margins = margins
        super.init(frame: .zero)
        insetsLayoutMarginsFromSafeArea = false   // không dùng layoutMargins; safe area chỉ qua safeBottom
        isMultipleTouchEnabled = true
        for v in views { addArrangedSubview(v) }
    }
    required init?(coder: NSCoder) { fatalError() }

    func addArrangedSubview(_ v: UIView) {
        arrangedSubviews.append(v)
        addSubview(v)
        setNeedsLayout()
    }
    func setCustomSpacing(_ s: CGFloat, after v: UIView) {
        customSpacing[ObjectIdentifier(v)] = s
        setNeedsLayout()
    }
    func setWidth(_ w: KeyRowLayout.Width, for v: UIView) {
        rules[ObjectIdentifier(v)] = w
        setNeedsLayout()
    }
    func width(for v: UIView) -> KeyRowLayout.Width {
        if let r = rules[ObjectIdentifier(v)] { return r }
        if let s = v as? KeySpacer { return s.rowWidth }
        if let r = v as? KeyRow { return r.rowWidth }
        if let b = v as? KeyboardView.KeyButton { return b.rowWidth ?? (b.isSpecial ? .flex : .equal) }
        return .flex
    }
    /// Gỡ phần tử khỏi danh sách khi view rời hàng (removeFromSuperview từ ngoài).
    override func willRemoveSubview(_ subview: UIView) {
        super.willRemoveSubview(subview)
        if let i = arrangedSubviews.firstIndex(where: { $0 === subview }) { arrangedSubviews.remove(at: i) }
    }

    /// Phần tử đang hiện (UIStackView bỏ qua view ẩn) + khe sau từng cái (trừ cái cuối).
    private var visible: [UIView] { arrangedSubviews.filter { !$0.isHidden } }
    private var spacings: [CGFloat] {
        let v = visible
        guard v.count > 1 else { return [] }
        return v.dropLast().map { customSpacing[ObjectIdentifier($0)] ?? spacing }
    }

    /// Bề rộng phím neo nếu hàng này là neo, theo bề ngang `w`.
    func anchorWidth(rowWidth w: CGFloat) -> CGFloat {
        KeyRowLayout.anchorWidth(visible.map(width(for:)), rowWidth: w,
                                 inner: w - margins.left - margins.right, spacing: spacings.reduce(0, +))
    }

    /// Bề rộng từng phần tử theo bề ngang `w` của hàng.
    func itemWidths(rowWidth w: CGFloat) -> [CGFloat] {
        let views = visible
        let gaps = spacings.reduce(0, +)
        let inner = w - margins.left - margins.right
        if let p = proportional {
            return KeyRowLayout.proportional(intrinsic: views.map(p.intrinsic), group: views.map(p.group),
                                             minimum: views.map(p.minimum), inner: inner, spacing: gaps)
        }
        let rules = views.map(width(for:))
        // Hàng khác neo ⇒ bề rộng neo tính từ hàng neo (mọi hàng cùng bề ngang); tự neo ⇒ nil.
        let ref: CGFloat? = anchor.flatMap { $0 === self ? nil : $0.anchorWidth(rowWidth: w) }
        return KeyRowLayout.widths(rules, rowWidth: w, inner: inner, spacing: gaps, ref: ref)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutItems()
    }

    private var scale: CGFloat {
        let s = traitCollection.displayScale
        return s > 0 ? s : UIScreen.main.scale
    }

    /// Xếp khung phần tử: toạ độ chính xác (gốc lưới) → làm tròn từng mép → trừ gốc đã làm tròn.
    func layoutItems() {
        let ex = exactFrame ?? CGRect(origin: roundedOrigin, size: bounds.size)
        let views = visible
        guard !views.isEmpty else { return }
        let ws = itemWidths(rowWidth: ex.width)
        let k = scale
        let y0 = ex.minY + margins.top, y1 = ex.maxY - margins.bottom
        var x = ex.minX + margins.left
        for (i, v) in views.enumerated() {
            let w = ws[i]
            let r = KeyRowLayout.rounded(x0: x, x1: x + w, y0: y0, y1: max(y1, y0), scale: k)
            let f = r.offsetBy(dx: -roundedOrigin.x, dy: -roundedOrigin.y)
            let exact = CGRect(x: x, y: y0, width: w, height: max(y1 - y0, 0))
            if let row = v as? KeyRow {
                if row.exactFrame != exact || row.roundedOrigin != r.origin {
                    row.exactFrame = exact; row.roundedOrigin = r.origin; row.setNeedsLayout()
                }
            } else if let b = v as? KeyboardView.KeyButton, b.exactFrame != exact || b.roundedOrigin != r.origin {
                b.exactFrame = exact; b.roundedOrigin = r.origin
                b.setNeedsLayout()
            }
            if v.frame != f { v.frame = f }
            x += w + (customSpacing[ObjectIdentifier(v)] ?? spacing)
        }
    }
}

/// Vùng hàng phím (thay UIStackView dọc `rowsContainer`). Hai chế độ:
///   • lưới (chữ / số / ký hiệu / tìm emoji): hàng là KeyRow, khung tính tay (KeyRowLayout.heights);
///   • stack (emoji / mẫu câu / bàn số lớn): plane cũ nằm nguyên trong một UIStackView dọc con
///     (tạo lười — khởi động không tạo).
final class KeyGridView: UIView {
    enum Mode { case grid, stack }
    private(set) var mode: Mode = .grid
    private var rows: [UIView] = []
    private var legacyStack: UIStackView?
    /// Chiều cao hàng (chế độ lưới).
    var heights: KeyRowLayout.Heights = .equal { didSet { if heights != oldValue { setNeedsLayout() } } }
    /// Hàng đầu cao cố định (ô tìm emoji) — nil = không có.
    var headerHeight: CGFloat? { didSet { if headerHeight != oldValue { setNeedsLayout() } } }
    /// Khung chính xác (toạ độ cha, chưa làm tròn) do KeyboardView đặt.
    var exactFrame: CGRect = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Chuyển chế độ — gọi khi plane trống (rebuild đã gỡ hàng cũ).
    func setMode(_ m: Mode) {
        guard m != mode else { return }
        mode = m
        if m == .stack {
            let s = legacyStack ?? {
                let s = UIStackView()
                s.axis = .vertical
                s.distribution = .fillEqually
                s.spacing = 0
                s.isMultipleTouchEnabled = true
                s.frame = bounds
                s.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                legacyStack = s
                return s
            }()
            if s.superview !== self { addSubview(s) }
        } else {
            legacyStack?.removeFromSuperview()
        }
        setNeedsLayout()
    }

    var arrangedSubviews: [UIView] { mode == .grid ? rows : (legacyStack?.arrangedSubviews ?? []) }
    var distribution: UIStackView.Distribution {
        get { legacyStack?.distribution ?? .fillEqually }
        set { legacyStack?.distribution = newValue }
    }
    func addArrangedSubview(_ v: UIView) {
        if mode == .grid { rows.append(v); addSubview(v); setNeedsLayout() }
        else { legacyStack?.addArrangedSubview(v) }
    }
    func insertArrangedSubview(_ v: UIView, at i: Int) {
        if mode == .grid { rows.insert(v, at: min(i, rows.count)); addSubview(v); setNeedsLayout() }
        else { legacyStack?.insertArrangedSubview(v, at: i) }
    }
    override func willRemoveSubview(_ subview: UIView) {
        super.willRemoveSubview(subview)
        if let i = rows.firstIndex(where: { $0 === subview }) { rows.remove(at: i) }
    }

    private var scale: CGFloat {
        let s = traitCollection.displayScale
        return s > 0 ? s : UIScreen.main.scale
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if mode == .stack {
            if let s = legacyStack, s.frame != bounds { s.frame = bounds }
            return
        }
        layoutRows()
    }

    /// Xếp hàng (chế độ lưới): chiều cao theo `heights`, mép làm tròn theo toạ độ tuyệt đối.
    func layoutRows() {
        guard !rows.isEmpty else { return }
        let ex = exactFrame
        let origin = frame.origin
        let n = rows.count - (headerHeight == nil ? 0 : 1)
        let hs = KeyRowLayout.heights(total: ex.height, count: max(n, 0), spec: heights, header: headerHeight)
        var y = ex.minY
        let k = scale
        for (i, v) in rows.enumerated() where i < hs.count {
            let h = hs[i]
            let r = KeyRowLayout.rounded(x0: ex.minX, x1: ex.maxX, y0: y, y1: y + h, scale: k)
            let f = r.offsetBy(dx: -origin.x, dy: -origin.y)
            if let row = v as? KeyRow {
                let exact = CGRect(x: ex.minX, y: y, width: ex.width, height: h)
                if row.exactFrame != exact || row.roundedOrigin != r.origin {
                    row.exactFrame = exact; row.roundedOrigin = r.origin; row.setNeedsLayout()
                }
            }
            if v.frame != f { v.frame = f }
            y += h
        }
    }
}
