// DomainPopup — giữ phím "." ở ô địa chỉ / URL / email để chọn đuôi tên miền như stock
// iOS (issue #113: ô URL bỏ phím ".com" riêng — space rộng như stock, đuôi gom vào giữ "."). Phần THUẦN (không UIKit): danh sách lựa chọn theo loại ô, bố cục hàng ô, chỉ số ô
// dưới ngón theo toạ độ x, luật huỷ khi trượt xa. View chỉ dựng popup khi hết giờ giữ.
import CoreGraphics
import Foundation

enum DomainPopup {
    /// Đuôi tên miền — .com mặc định như stock, .vn / .com.vn kế tiếp cho người dùng Việt
    /// (issue #113). Bản Kotlin song sinh: android/keyboard/…/DomainPopup.kt.
    static let tlds = [".com", ".vn", ".com.vn", ".net", ".org", ".edu"]

    /// Phím `title` ở bàn CHỮ của ô `kind` có popup không. Chỉ phím "." của thanh địa
    /// chỉ/tìm kiếm, ô URL và ô email; ô khác ⇒ rỗng (0 chi phí).
    static func choices(kind: KeyboardView.InputKind, key title: String, lettersPlane: Bool) -> [String] {
        guard lettersPlane else { return [] }
        switch kind {
        case .search: return title == "." ? tlds : []
        case .url: return title == "." ? tlds : []
        case .email: return title == "." ? tlds : []
        default: return []
        }
    }

    /// Bố cục ô (toạ độ vùng chứa). Ô đầu (mặc định) nằm ngay trên tâm phím; hàng loe về phía
    /// còn chỗ (không đủ chỗ bên phải thì lật ngược — ô đầu ở bên phải, hàng loe sang trái —
    /// như stock), rồi kẹp trong [margin, width − margin].
    ///
    /// HAI HÀNG (issue #154): khi một hàng không vừa bề ngang với bề rộng ô mong muốn, HOẶC
    /// phải kẹp mép đẩy ô đầu lệch khỏi tâm phím quá nửa ô ⇒ `perRow` = ⌈n/2⌉ ô mỗi hàng, hàng 0
    /// (ô 0…perRow−1) sát phím, hàng 1 chồng LÊN trên; ô i+perRow ngay trên ô i. Vừa một hàng
    /// mà ô đầu vẫn trên phím ⇒ y như cũ. Bản Kotlin song sinh: android/keyboard/…/DomainPopup.kt.
    struct Layout: Equatable {
        let originX: CGFloat
        let itemWidth: CGFloat
        let count: Int
        /// true ⇒ ô 0 ở bên PHẢI (hàng đọc từ phải sang trái).
        let mirrored: Bool
        /// Số ô mỗi hàng (= `count` khi một hàng).
        var perRow: Int
        /// Cao một hàng — ranh giới hai hàng khi chọn theo y; một hàng thì không dùng.
        var rowHeight: CGFloat = 0

        init(originX: CGFloat, itemWidth: CGFloat, count: Int, mirrored: Bool,
             perRow: Int? = nil, rowHeight: CGFloat = 0) {
            self.originX = originX; self.itemWidth = itemWidth; self.count = count
            self.mirrored = mirrored; self.perRow = perRow ?? count; self.rowHeight = rowHeight
        }

        /// Bề ngang một hàng.
        var width: CGFloat { itemWidth * CGFloat(perRow) }
        /// 1 hoặc 2.
        var rows: Int { perRow > 0 ? (count + perRow - 1) / perRow : 0 }
        /// Hàng của lựa chọn `index`: 0 = sát phím, 1 = phía trên.
        func rowOf(_ index: Int) -> Int { perRow > 0 ? index / perRow : 0 }

        /// Mép trái ô của lựa chọn `index` (toạ độ vùng chứa).
        func slotMinX(_ index: Int) -> CGFloat {
            let col = perRow > 0 ? index % perRow : 0
            let slot = mirrored ? perRow - 1 - col : col
            return originX + CGFloat(slot) * itemWidth
        }
    }

    /// `itemWidth` = bề rộng ô mong muốn (co lại nếu không vừa); `rowHeight` = cao một hàng;
    /// `maxRows` = 1 khi không có chỗ phía trên cho hàng thứ hai (view tự quyết).
    static func layout(keyMidX: CGFloat, itemWidth: CGFloat, count: Int,
                       containerWidth: CGFloat, margin: CGFloat = 2,
                       rowHeight: CGFloat = 0, maxRows: Int = 2) -> Layout {
        let avail = max(containerWidth - 2 * margin, 1)
        let oneW = min(itemWidth, avail / CGFloat(max(count, 1)))
        let one = place(keyMidX: keyMidX, w: oneW, count: count, perRow: count,
                        containerWidth: containerWidth, margin: margin, rowHeight: rowHeight)
        guard maxRows >= 2, count >= 2 else { return one.layout }
        let crowded = itemWidth * CGFloat(count) > avail || one.shift > oneW / 2
        guard crowded else { return one.layout }
        let perRow = (count + 1) / 2
        return place(keyMidX: keyMidX, w: min(itemWidth, avail / CGFloat(perRow)), count: count, perRow: perRow,
                     containerWidth: containerWidth, margin: margin, rowHeight: rowHeight).layout
    }

    /// Đặt hàng `perRow` ô rộng `w`; kèm độ dời do kẹp mép (ô đầu lệch khỏi tâm phím bao nhiêu).
    private static func place(keyMidX: CGFloat, w: CGFloat, count: Int, perRow: Int,
                              containerWidth: CGFloat, margin: CGFloat,
                              rowHeight: CGFloat) -> (layout: Layout, shift: CGFloat) {
        let rowW = w * CGFloat(perRow)
        let rightFits = keyMidX - w / 2 + rowW <= containerWidth - margin
        let leftFits = keyMidX + w / 2 - rowW >= margin
        // Không bên nào vừa ⇒ loe về bên nhiều chỗ hơn (ô đầu bớt lệch khi kẹp).
        let roomRight = containerWidth - margin - (keyMidX - w / 2)
        let roomLeft = keyMidX + w / 2 - margin
        let mirrored = !rightFits && (leftFits || roomLeft > roomRight)
        let raw = mirrored ? keyMidX + w / 2 - rowW : keyMidX - w / 2
        let x = min(max(raw, margin), max(margin, containerWidth - margin - rowW))
        return (Layout(originX: x, itemWidth: w, count: count, mirrored: mirrored,
                       perRow: perRow, rowHeight: rowHeight), abs(x - raw))
    }

    /// Ngón trượt ra ngoài hàng quá ngần này (ngang) ⇒ huỷ.
    static let cancelSlackX: CGFloat = 30
    /// Ngón trượt lên trên đỉnh popup / xuống dưới đáy phím quá ngần này ⇒ huỷ.
    static let cancelSlackY: CGFloat = 40
    /// Lúc mở luôn chọn ô 0; ngón phải dời quá ngần này mới đổi ô — run tay không đổi ô.
    static let engageDistance: CGFloat = 8

    /// Độ bù ngang của một lượt kéo: chỗ mở coi như tâm ô 0 (ngón chạm lệch trong phím vẫn là
    /// ô 0, trượt một ô ra ô kế — cảm giác cũ), nhưng bù tối đa NỬA Ô. Issue #154: trước đây bù
    /// trọn độ lệch; hàng bị kẹp mép (ô 0 lệch xa phím) thì ô ở đầu kia cần ngón ra ngoài màn
    /// hình. Bù ≤ nửa ô ⇒ ô đầu/cuối luôn với tới trong nửa ô tính từ mép popup.
    static func dragOffset(startX: CGFloat, layout l: Layout) -> CGFloat {
        let half = l.itemWidth / 2
        return min(max(l.slotMinX(0) + half - startX, -half), half)
    }

    /// Ô dưới điểm (x đã cộng `dragOffset`). Lố hai đầu hàng trong ngần slack ⇒ kẹp ô đầu /
    /// cuối. Hai hàng: cao hơn `top + rowHeight` ⇒ hàng trên; hàng trên thiếu ô ⇒ ô cuối.
    /// nil = huỷ (ra ngoài quá slack). `top` = đỉnh popup, `bottom` = đáy phím.
    static func index(at p: CGPoint, layout l: Layout, top: CGFloat, bottom: CGFloat) -> Int? {
        guard l.count > 0, l.perRow > 0,
              p.x >= l.originX - cancelSlackX, p.x <= l.originX + l.width + cancelSlackX,
              p.y >= top - cancelSlackY, p.y <= bottom + cancelSlackY else { return nil }
        let slot = min(max(Int(((p.x - l.originX) / l.itemWidth).rounded(.down)), 0), l.perRow - 1)
        let col = l.mirrored ? l.perRow - 1 - slot : slot
        let row = l.rows > 1 && p.y < top + l.rowHeight ? 1 : 0
        return min(row * l.perRow + col, l.count - 1)
    }

    /// Một lượt kéo trên popup đang mở: lúc mở chọn ô 0; ngón dời quá `engageDistance` ⇒
    /// chọn ô dưới ngón + `dragOffset`. Thuần — view giữ một bản, gọi `move` mỗi lần ngón đi.
    struct Track: Equatable {
        let layout: Layout
        let top: CGFloat
        let bottom: CGFloat
        let start: CGPoint
        let dx: CGFloat
        private(set) var engaged = false
        private(set) var selection: Int?

        init(layout: Layout, top: CGFloat, bottom: CGFloat, start: CGPoint) {
            self.layout = layout; self.top = top; self.bottom = bottom; self.start = start
            dx = DomainPopup.dragOffset(startX: start.x, layout: layout)
            selection = DomainPopup.index(at: CGPoint(x: start.x + dx, y: start.y), layout: layout,
                                          top: top, bottom: bottom) != nil ? 0 : nil
        }

        /// true nếu ô chọn đổi.
        @discardableResult
        mutating func move(to p: CGPoint) -> Bool {
            if !engaged, hypot(p.x - start.x, p.y - start.y) < DomainPopup.engageDistance { return false }
            engaged = true
            let s = DomainPopup.index(at: CGPoint(x: p.x + dx, y: p.y), layout: layout, top: top, bottom: bottom)
            guard s != selection else { return false }
            selection = s
            return true
        }
    }
}

/// Ô email: vừa gõ "@" (hoặc tiền tố tên miền sau "@") ⇒ chip đuôi mail trên thanh gợi ý
/// ("@gmail.com" trước). Chạm chip chèn PHẦN CÒN THIẾU (không lặp "@" / tiền tố đã gõ).
/// Thuần — controller chỉ gọi ở ô `.email` (ô khác 0 việc).
enum EmailDomains {
    static let providers = ["gmail.com", "icloud.com", "yahoo.com", "outlook.com"]

    struct Chip: Equatable {
        /// Nhãn trên thanh gợi ý, vd "@gmail.com".
        let label: String
        /// Chữ chèn sau con trỏ, vd "gmail.com" sau "phuc@", "ail.com" sau "phuc@gm".
        let insert: String
    }

    /// Chip cho chữ trước con trỏ. Token cuối (sau khoảng trắng / "," / ";") phải có đúng
    /// một "@", phần trước "@" không rỗng; phần sau là tiền tố (không phân biệt hoa thường)
    /// của tên miền và chưa gõ đủ.
    static func chips(before: String, limit: Int = 3) -> [Chip] {
        guard limit > 0, let at = before.lastIndex(of: "@") else { return [] }
        let partial = before[before.index(after: at)...]
        guard partial.count < 12,
              partial.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") })
        else { return [] }
        let local = before[..<at].reversed().prefix { !$0.isWhitespace && $0 != "," && $0 != ";" && $0 != "<" }
        guard !local.isEmpty, !local.contains("@") else { return [] }
        let p = partial.lowercased()
        return Array(providers.lazy
            .filter { $0.hasPrefix(p) && $0 != p }
            .prefix(limit)
            .map { Chip(label: "@" + $0, insert: String($0.dropFirst(p.count))) })
    }
}

/// Ô URL / thanh địa chỉ (StripMode.tools + FieldTraits.wantsURLChips): chip gõ nhanh địa chỉ
/// thay cho dải trống. Chạm chèn TẠI CON TRỎ. Thuần — controller tính lại từ context lúc chạm
/// (con trỏ có thể đã dời), lệch thì bỏ.
/// - ô trống (trước + sau con trỏ đều rỗng): `https://` `www.` `.com`
/// - đầu một địa chỉ (trước con trỏ rỗng / khoảng trắng / "://"): `www.` `.com` `.vn`
/// - đang gõ tên miền: `.com` `.vn` (bỏ đuôi đã có; sau "." chỉ chèn "com"/"vn")
/// - đã sang đường dẫn ("/" sau tên miền): không chip
enum URLChips {
    typealias Chip = EmailDomains.Chip
    static let https = "https://", www = "www.", tlds = [".com", ".vn"]

    static func chips(before: String, after: String) -> [Chip] {
        if before.isEmpty && after.isEmpty {
            return [Chip(label: https, insert: https), Chip(label: www, insert: www),
                    Chip(label: tlds[0], insert: tlds[0])]
        }
        let token = before.reversed().prefix { !$0.isWhitespace }.reversed()
        var host = Substring(String(token))
        if let r = host.range(of: "://") { host = host[r.upperBound...] }
        if host.isEmpty {
            return [Chip(label: www, insert: www)] + tlds.map { Chip(label: $0, insert: $0) }
        }
        guard !host.contains("/") else { return [] }
        let h = host.lowercased()
        if tlds.contains(where: { h.hasSuffix($0) }) || h == "www." { return [] }
        return tlds.map { t in Chip(label: t, insert: h.hasSuffix(".") ? String(t.dropFirst()) : t) }
    }
}
