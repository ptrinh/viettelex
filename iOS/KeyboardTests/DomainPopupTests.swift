// DomainPopupTests — giữ "." ở ô địa chỉ/URL/email ra hàng đuôi tên miền như stock,
// và chip đuôi mail sau "@" ở ô email (EmailDomains).
import XCTest
import UIKit

/// Chip ô URL / thanh địa chỉ (URLChips): chèn tại con trỏ; `https://` chỉ khi ô trống.
final class URLChipsTests: XCTestCase {
    private func labels(_ before: String, _ after: String = "") -> [String] {
        URLChips.chips(before: before, after: after).map(\.label)
    }
    private func insert(_ label: String, _ before: String, _ after: String = "") -> String? {
        URLChips.chips(before: before, after: after).first { $0.label == label }?.insert
    }

    func testEmptyFieldOffersHttps() {
        XCTAssertEqual(labels(""), ["https://", "www.", ".com"])
        XCTAssertEqual(insert("https://", ""), "https://")
    }

    func testHttpsOnlyWhenFieldEmpty() {
        XCTAssertFalse(labels("", "abc").contains("https://"))      // con trỏ đầu ô có chữ
        XCTAssertFalse(labels("https://").contains("https://"))
        XCTAssertFalse(labels("vnexpress").contains("https://"))
    }

    func testStartOfAddressOffersWww() {
        XCTAssertEqual(labels("https://"), ["www.", ".com", ".vn"])
        XCTAssertEqual(labels("", "x"), ["www.", ".com", ".vn"])
        XCTAssertEqual(insert("www.", "https://"), "www.")
    }

    func testTypingDomainOffersTLDs() {
        XCTAssertEqual(labels("vnexpress"), [".com", ".vn"])
        XCTAssertEqual(insert(".vn", "vnexpress"), ".vn")
        XCTAssertEqual(labels("https://www.tuoitre"), [".com", ".vn"])
        // Đã gõ "." ⇒ chỉ chèn phần còn thiếu, không thành "..com".
        XCTAssertEqual(insert(".com", "google."), "com")
        XCTAssertEqual(insert(".vn", "thanhnien."), "vn")
        // Từ cuối sau khoảng trắng (thanh tìm-hoặc-địa-chỉ có thể chứa nhiều từ).
        XCTAssertEqual(labels("tin tuc dantri"), [".com", ".vn"])
    }

    func testNoChipsWhenDoneOrInPath() {
        XCTAssertEqual(labels("google.com"), [])
        XCTAssertEqual(labels("VNEXPRESS.VN"), [])
        XCTAssertEqual(labels("github.com/ptrinh"), [])
        XCTAssertEqual(labels("www."), [])   // "www.com" vô nghĩa — chờ gõ tên miền
    }
}

final class DomainPopupTests: XCTestCase {
    // MARK: lựa chọn theo loại ô

    func testChoicesPerField() {
        let t = DomainPopup.tlds
        XCTAssertEqual(t, [".com", ".vn", ".com.vn", ".net", ".org", ".edu"], ".com mặc định, .vn/.com.vn kế (#113)")
        XCTAssertEqual(DomainPopup.choices(kind: .search, key: ".", lettersPlane: true), t)
        XCTAssertEqual(DomainPopup.choices(kind: .url, key: ".", lettersPlane: true), t)
        XCTAssertEqual(DomainPopup.choices(kind: .url, key: ".com", lettersPlane: true), [], "không còn phím .com (#113)")
        XCTAssertEqual(DomainPopup.choices(kind: .email, key: ".", lettersPlane: true), t)
        XCTAssertEqual(DomainPopup.choices(kind: .url, key: "/", lettersPlane: true), [])
        XCTAssertEqual(DomainPopup.choices(kind: .email, key: "@", lettersPlane: true), [])
        XCTAssertEqual(DomainPopup.choices(kind: .search, key: ",", lettersPlane: true), [])
        XCTAssertEqual(DomainPopup.choices(kind: .normal, key: ".", lettersPlane: true), [], "ô thường: không")
        XCTAssertEqual(DomainPopup.choices(kind: .number, key: ".", lettersPlane: true), [])
        XCTAssertEqual(DomainPopup.choices(kind: .url, key: ".", lettersPlane: false), [], "chỉ bàn chữ")
    }

    // MARK: bố cục + chỉ số dưới ngón

    func testLayoutLeftToRightWhenRoomOnRight() {
        let l = DomainPopup.layout(keyMidX: 60, itemWidth: 56, count: 6, containerWidth: 390)
        XCTAssertFalse(l.mirrored)
        XCTAssertEqual(l.originX, 32)
        XCTAssertEqual(l.slotMinX(0), 32)
        func idx(_ x: CGFloat, _ yy: CGFloat = 20) -> Int? {
            DomainPopup.index(at: CGPoint(x: x, y: yy), layout: l, top: 0, bottom: 60)
        }
        XCTAssertEqual(idx(60), 0, "ô dưới ngón lúc mở = .com")
        XCTAssertEqual(idx(60 + 56), 1)
        XCTAssertEqual(idx(60 + 56 * 5), 5)
        XCTAssertEqual(idx(l.originX + l.width + 10), 5, "lố mép trong ngần: kẹp ô cuối")
        XCTAssertEqual(idx(l.originX - 10), 0)
        XCTAssertNil(idx(l.originX + l.width + DomainPopup.cancelSlackX + 1), "trượt xa ngang ⇒ huỷ")
        XCTAssertNil(idx(l.originX - DomainPopup.cancelSlackX - 1))
        XCTAssertNil(idx(60, -DomainPopup.cancelSlackY - 1), "trượt lên quá ⇒ huỷ")
        XCTAssertNil(idx(60, 60 + DomainPopup.cancelSlackY + 1), "trượt xuống quá ⇒ huỷ")
        XCTAssertEqual(idx(60, 60 + 10), 0, "ngón vẫn trên phím ⇒ chọn")
    }

    func testLayoutMirrorsNearRightEdge() {
        let l = DomainPopup.layout(keyMidX: 350, itemWidth: 56, count: 6, containerWidth: 390)
        XCTAssertTrue(l.mirrored)
        XCTAssertEqual(l.slotMinX(0), 350 - 28, ".com vẫn ngay trên phím")
        XCTAssertGreaterThanOrEqual(l.originX, 2)
        let i = { (x: CGFloat) in DomainPopup.index(at: CGPoint(x: x, y: 10), layout: l, top: 0, bottom: 60) }
        XCTAssertEqual(i(350), 0)
        XCTAssertEqual(i(350 - 56), 1, "loe sang trái: trượt trái ra .vn")
        XCTAssertEqual(i(350 - 56 * 5), 5)
    }

    func testLayoutClampedInsideNarrowContainerWrapsToTwoRows() {
        // 5 ô 56 vừa bề ngang 300 nhưng phải kẹp, ô đầu lệch > 1 ô khỏi phím ⇒ hai hàng (3 + 2).
        let l = DomainPopup.layout(keyMidX: 150, itemWidth: 56, count: 5, containerWidth: 300, rowHeight: 30)
        XCTAssertEqual(l.rows, 2)
        XCTAssertEqual(l.perRow, 3)
        XCTAssertGreaterThanOrEqual(l.originX, 2)
        XCTAssertLessThanOrEqual(l.originX + l.width, 298)
        XCTAssertTrue(l.slotMinX(0) <= 150 && 150 <= l.slotMinX(0) + 56, "ô 0 ngay trên phím")
        XCTAssertEqual(l.slotMinX(3), l.slotMinX(0), "ô 3 ngay trên ô 0")
        XCTAssertEqual(l.rowOf(2), 0); XCTAssertEqual(l.rowOf(3), 1)
        let i = { (x: CGFloat, y: CGFloat) in DomainPopup.index(at: CGPoint(x: x, y: y), layout: l, top: 0, bottom: 100) }
        XCTAssertEqual(i(150, 45), 0)
        XCTAssertEqual(i(150, 15), 3)
        XCTAssertEqual(i(150, 90), 0, "ngón trên phím (dưới popup) ⇒ hàng 0")
        let far = l.mirrored ? l.originX + 1 : l.originX + l.width - 1
        XCTAssertEqual(i(far, 15), 4, "hàng trên thiếu ô ⇒ kẹp ô cuối")
    }

    func testOneRowUnchangedWhenItFits() {
        XCTAssertEqual(DomainPopup.layout(keyMidX: 60, itemWidth: 56, count: 6, containerWidth: 390, rowHeight: 46).rows, 1)
        XCTAssertEqual(DomainPopup.layout(keyMidX: 350, itemWidth: 56, count: 6, containerWidth: 390, rowHeight: 46).rows, 1)
        XCTAssertEqual(DomainPopup.layout(keyMidX: 150, itemWidth: 56, count: 5, containerWidth: 300, maxRows: 1).rows, 1)
    }

    func testTooWideForOneRowWraps() {
        let l = DomainPopup.layout(keyMidX: 250, itemWidth: 34, count: 10, containerWidth: 320)
        XCTAssertEqual(l.rows, 2)
        XCTAssertEqual(l.itemWidth, 34)
        let one = DomainPopup.layout(keyMidX: 250, itemWidth: 34, count: 10, containerWidth: 320, maxRows: 1)
        XCTAssertEqual(one.rows, 1)
        XCTAssertTrue(one.originX >= 2 && one.originX + one.width <= 318.001)
    }

    /// #154: MỌI ô với tới được ở MỌI chỗ đặt phím (kể cả hàng bị kẹp mép): mở ở tâm phím,
    /// quét ngón ngang trong màn hình (chừa 1 pt mép) trên từng hàng ⇒ chọn được đủ mọi ô.
    func testEveryCellReachableAnywhere() {
        let rowH: CGFloat = 46
        for w: CGFloat in [280, 320, 360, 390, 430, 600] {
            for n in 1...12 {
                for iw: CGFloat in [34, 38, 48, 56] {
                    for maxRows in 1...2 {
                        var kx: CGFloat = 10
                        while kx < w - 10 {
                            let l = DomainPopup.layout(keyMidX: kx, itemWidth: iw, count: n, containerWidth: w,
                                                       rowHeight: rowH, maxRows: maxRows)
                            let keyY = rowH * CGFloat(l.rows) + 28, bottom = keyY + 20
                            var t = DomainPopup.Track(layout: l, top: 0, bottom: bottom, start: CGPoint(x: kx, y: keyY))
                            XCTAssertEqual(t.selection, 0)
                            var got = Set<Int>()
                            for r in 0..<l.rows {
                                let cy = CGFloat(l.rows - 1 - r) * rowH + rowH / 2
                                var x: CGFloat = 1
                                while x <= w - 1 {
                                    t.move(to: CGPoint(x: x, y: cy))
                                    if let s = t.selection { got.insert(s) }
                                    x += 1
                                }
                            }
                            XCTAssertEqual(got, Set(0..<n), "w=\(w) n=\(n) iw=\(iw) kx=\(kx) rows=\(l.rows)")
                            kx += 7
                        }
                    }
                }
            }
        }
    }

    /// Hàng một dòng kẹp mép trái ⇒ bù kéo ≤ nửa ô (trước #154 bù trọn ⇒ ô xa ngoài màn hình).
    func testDragOffsetCappedAtHalfCell() {
        let l = DomainPopup.layout(keyMidX: 127, itemWidth: 34, count: 10, containerWidth: 390, maxRows: 1)
        XCTAssertEqual(l.originX, 48, accuracy: 0.001)
        XCTAssertEqual(abs(DomainPopup.dragOffset(startX: 127, layout: l)), 17, accuracy: 0.001)
        var t = DomainPopup.Track(layout: l, top: 0, bottom: 100, start: CGPoint(x: 127, y: 80))
        t.move(to: CGPoint(x: 40, y: 20))
        let farLeft = t.selection
        t.move(to: CGPoint(x: 388, y: 20))
        XCTAssertEqual(Set([farLeft, t.selection]), Set([0, 9]), "hai đầu hàng đều chọn được")
    }

    func testJitterKeepsPreselectUntilEngaged() {
        let l = DomainPopup.layout(keyMidX: 300, itemWidth: 34, count: 10, containerWidth: 360, maxRows: 1)
        var t = DomainPopup.Track(layout: l, top: 0, bottom: 100, start: CGPoint(x: 300, y: 80))
        XCTAssertFalse(t.move(to: CGPoint(x: 303, y: 82)))
        XCTAssertEqual(t.selection, 0)
        XCTAssertTrue(t.move(to: CGPoint(x: 300 - 3 * 34, y: 80)))
        XCTAssertNotEqual(t.selection, 0)
    }

    /// iPhone thật: giữ "$" bàn 123 (9 biến thể) — ô xa nhất ("¢") trước đây cần ngón ra ngoài
    /// màn hình (hàng kẹp mép, chọn theo độ dời). Mọi biến thể chọn được bằng cách trượt tới ô
    /// của nó, ngón luôn trong màn hình.
    @MainActor func testEveryDollarVariantReachableOnPhone() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad)
        for width: CGFloat in [320, 375, 390, 430] {
            var out: [String] = []
            let (kb, host) = makeKeyboard(.normal, width: width) { out.append($0) }
            kb.debugSetPlane(numbers: true); kb.layoutIfNeeded()
            let choices = KeyVariants.variants(for: "$", symbolPlane: true)
            XCTAssertEqual(choices.count, 9)
            kb.debugDomainHold("$")
            let l = try XCTUnwrap(kb.debugLastDomainLayout)
            let key = try XCTUnwrap(kb.debugDomainKeyFrame("$"))
            let top = try XCTUnwrap(kb.debugLastDomainTop)
            let dx = DomainPopup.dragOffset(startX: key.midX, layout: l)
            for i in 0..<choices.count {
                out = []
                kb.debugSetPlane(numbers: true); kb.layoutIfNeeded()
                let cx = l.slotMinX(i) + l.itemWidth / 2 - dx
                let cy = top + 46 * CGFloat(l.rows - 1 - l.rowOf(i)) + 23
                XCTAssertTrue(cx > 0 && cx < width)
                kb.debugDomainHold("$", dx: cx - key.midX, dy: cy - key.midY)
                XCTAssertEqual(out, ["T" + choices[i]], "w=\(width) ô \(i) rows=\(l.rows)")
            }
            withExtendedLifetime(host) {}
        }
    }

    // MARK: KeyboardView (iPhone) — đường action thật

    @MainActor private func makeKeyboard(_ kind: KeyboardView.InputKind, width: CGFloat = 390,
                                         log: @escaping (String) -> Void) -> (KeyboardView, UIView) {
        let kb = KeyboardView(needsGlobe: false, inputController: nil) { k in
            switch k {
            case .letter(let c): log("L\(c.lowercased())")
            case .text(let s): log("T\(s)")
            default: log("?")
            }
        }
        let host = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 320))
        host.addSubview(kb)
        kb.frame = host.bounds
        kb.configureInputKind(kind)
        kb.layoutIfNeeded()
        return (kb, host)
    }

    @MainActor func testHoldPeriodInsertsSelectedTLD() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad)
        for kind in [KeyboardView.InputKind.url, .search, .email] {
            var out: [String] = []
            let (kb, host) = makeKeyboard(kind) { out.append($0) }
            XCTAssertFalse(kb.debugDomainPopupMade)
            XCTAssertTrue(kb.debugDomainHold(".", fire: false), "\(kind)")
            XCTAssertEqual(out, ["T."], "chạm thường vẫn ra \".\" (\(kind))")
            XCTAssertFalse(kb.debugDomainPopupMade, "chưa đủ giờ ⇒ không dựng view")
            out = []
            kb.debugDomainHold(".")
            XCTAssertEqual(out, ["T.com"], "\(kind)")
            XCTAssertTrue(kb.debugDomainPopupMade)
            XCTAssertFalse(kb.debugDomainPopupVisible, "nhấc ⇒ popup tắt")
            out = []
            let l = try XCTUnwrap(kb.debugLastDomainLayout)
            kb.debugDomainHold(".", dx: l.mirrored ? -56 : 56)
            XCTAssertEqual(out, ["T.vn"], "\(kind)")
            out = []
            kb.debugDomainHold(".", dy: -300)                     // trượt xa ⇒ huỷ
            XCTAssertEqual(out, [], "\(kind)")
            out = []
            kb.debugDomainHold(".", secondTouch: "a")             // ngón khác chạm: đuôi chốt TRƯỚC
            XCTAssertEqual(out, ["T.com", "La"], "\(kind)")
            withExtendedLifetime(host) {}
        }
    }

    @MainActor func testPopupStaysOpenWhileHeld() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad)
        var out: [String] = []
        let (kb, host) = makeKeyboard(.url) { out.append($0) }
        kb.debugDomainHold(".", keepOpen: true)
        XCTAssertTrue(kb.debugDomainPopupVisible)
        XCTAssertEqual(kb.debugDomainSelection, ".com")
        XCTAssertEqual(out, [])
        withExtendedLifetime(host) {}
    }

    /// Issue #113: ô URL không còn phím ".com" — space rộng như stock, "/" vẫn còn.
    @MainActor func testURLRowHasNoDotComKey() throws {
        let (kb, host) = makeKeyboard(.url) { _ in }
        XCTAssertFalse(kb.debugDomainHold(".com", fire: false), "không có phím .com")
        var out: [String] = []
        let (kb2, host2) = makeKeyboard(.url) { out.append($0) }
        XCTAssertFalse(kb2.debugDomainHold("/"))
        XCTAssertEqual(out, ["T/"], "\"/\" vẫn ở hàng đáy")
        withExtendedLifetime((kb, host, host2)) {}
    }

    @MainActor func testOtherFieldsHaveNoPopup() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad)
        var out: [String] = []
        let (kb, host) = makeKeyboard(.url) { out.append($0) }
        XCTAssertFalse(kb.debugDomainHold("/"), "\"/\" không có popup")
        XCTAssertEqual(out, ["T/"])
        let (kb2, host2) = makeKeyboard(.normal) { _ in }
        XCTAssertFalse(kb2.debugDomainHold("."), "ô thường không có phím \".\" hàng đáy")
        XCTAssertFalse(kb2.debugDomainPopupMade)
        withExtendedLifetime((host, host2)) {}
    }

    // MARK: chip đuôi mail (ô email)

    func testEmailChipsAfterAt() {
        let c = EmailDomains.chips(before: "phuc@")
        XCTAssertEqual(c.map(\.label), ["@gmail.com", "@icloud.com", "@yahoo.com"], "gmail trước, tối đa 3")
        XCTAssertEqual(c.first?.insert, "gmail.com", "không lặp \"@\"")
        XCTAssertEqual(EmailDomains.chips(before: "phuc@", limit: 4).map(\.label).last, "@outlook.com")
        XCTAssertEqual(EmailDomains.chips(before: "To: a, phuc@").first?.insert, "gmail.com")
    }

    func testEmailChipsCompletePrefix() {
        XCTAssertEqual(EmailDomains.chips(before: "phuc@gm"), [.init(label: "@gmail.com", insert: "ail.com")])
        XCTAssertEqual(EmailDomains.chips(before: "phuc@GM").first?.insert, "ail.com")
        XCTAssertEqual(EmailDomains.chips(before: "phuc@o").map(\.label), ["@outlook.com"])
        XCTAssertEqual(EmailDomains.chips(before: "phuc@gmail.").first?.insert, "com")
        XCTAssertEqual(EmailDomains.chips(before: "phuc@gmail.co").first?.insert, "m")
    }

    func testEmailChipsGone() {
        XCTAssertEqual(EmailDomains.chips(before: ""), [])
        XCTAssertEqual(EmailDomains.chips(before: "phuc"), [])
        XCTAssertEqual(EmailDomains.chips(before: "@"), [], "phần trước @ rỗng")
        XCTAssertEqual(EmailDomains.chips(before: "hi @"), [])
        XCTAssertEqual(EmailDomains.chips(before: "phuc@gmail.com"), [], "đã đủ")
        XCTAssertEqual(EmailDomains.chips(before: "phuc@abc."), [], "có \".\" mà không khớp")
        XCTAssertEqual(EmailDomains.chips(before: "ban@congty"), [])
        XCTAssertEqual(EmailDomains.chips(before: "a@b@"), [], "hai @")
        XCTAssertEqual(EmailDomains.chips(before: "phuc@ "), [], "đã sang token khác")
        XCTAssertEqual(EmailDomains.chips(before: "phuc@", limit: 0), [])
    }

    func testEmailFieldAlwaysHasBar() {
        XCTAssertTrue(FieldTraits(keyboardType: .emailAddress, autocorrection: .no).allowsSuggestions)
        XCTAssertFalse(FieldTraits(keyboardType: .emailAddress, secure: true).allowsSuggestions)
        XCTAssertFalse(FieldTraits(keyboardType: .URL, autocorrection: .no).allowsSuggestions)
        XCTAssertFalse(FieldTraits(autocorrection: .no).allowsSuggestions)
    }
}
