// CaretHintTests — gợi ý cạnh con trỏ (MathHint.swift): máy trạng thái phím (hiện → Tab/
// Enter áp dụng, Esc tắt + nuốt, phím khác tắt + đi tiếp), chip số chỉ-dạng-tiền (fixture
// chung number-chips.txt), điều kiện kích hoạt ở dấu cách, và thứ tự nguồn vị trí con trỏ
// (firstRect IMK → AX caret → AX ký tự trước → ước lượng dòng → mép TRÁI ô), kiểm rect
// theo cửa sổ đang trước + firstRect đứng yên, và vị trí dự phòng (#104: Edge/Firefox —
// dưới chuột trong cửa sổ, không thì giữa-đáy cửa sổ). Không tạo cửa sổ nào.
import AppKit
import XCTest
import InputMethodKit
@testable import VietTelex

final class CaretHintTests: XCTestCase {
    private typealias L = CaretHintLogic
    private static let fixture = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("iOS/KeyboardTests/Fixtures/number-chips.txt")

    override func tearDown() { CaretHint.shared.setPendingForTesting(nil) }

    /// Hồi quy (Phil 16/10/2026): bảng cột dọc luôn cao ~9 dòng dù chỉ 1–3 gợi ý ⇒ một hàng ngang.
    /// Đo 16/10/2026: TextMate rect đúng dòng ⇒ 4pt; Notes rect thấp hơn chân chữ ⇒ 14pt.
    func testHintPanelGapPerApp() {
        XCTAssertEqual(CaretHintLogic.panelGap(for: "com.macromates.TextMate"), 4)
        XCTAssertEqual(CaretHintLogic.panelGap(for: nil), 4)
        XCTAssertEqual(CaretHintLogic.panelGap(for: "com.apple.Notes"), 14)
        let caret = NSRect(x: 100, y: 500, width: 0, height: 16)
        let o = TextToolsPanelLogic.origin(caret: caret, panelSize: NSSize(width: 120, height: 28),
                                           visible: NSRect(x: 0, y: 0, width: 1440, height: 900),
                                           gap: CaretHintLogic.panelGap(for: "com.apple.Notes"))
        XCTAssertEqual(o.y + 28, caret.minY - 14)
    }

    func testCandidateWindowIsSingleRow() {
        XCTAssertEqual(CaretHint.candidatePanelType, kIMKSingleRowSteppingCandidatePanel)
    }

    // MARK: Phím

    func testKeyActionsMath() {
        XCTAssertEqual(L.action(kind: .math, keyCode: L.kTab, plain: true), .accept)
        XCTAssertEqual(L.action(kind: .math, keyCode: L.kReturn, plain: true), .accept)
        XCTAssertEqual(L.action(kind: .math, keyCode: L.kKeypadEnter, plain: true), .accept)
        XCTAssertEqual(L.action(kind: .math, keyCode: L.kEscape, plain: true), .dismissConsume)
        XCTAssertEqual(L.action(kind: .math, keyCode: 18 /* "1" */, plain: true), .dismissPass)
        XCTAssertEqual(L.action(kind: .math, keyCode: 0 /* a */, plain: true), .dismissPass)
        XCTAssertEqual(L.action(kind: .math, keyCode: L.kTab, plain: false), .dismissPass)      // ⇧Tab
        XCTAssertEqual(L.action(kind: .math, keyCode: L.kReturn, plain: false), .dismissPass)   // ⇧Enter
    }

    /// Chip số: chỉ Tab — Enter sau "50k␣" là gửi/xuống dòng, không được cướp.
    func testKeyActionsNumber() {
        XCTAssertEqual(L.action(kind: .number, keyCode: L.kTab, plain: true), .accept)
        XCTAssertEqual(L.action(kind: .number, keyCode: L.kReturn, plain: true), .dismissPass)
        XCTAssertEqual(L.action(kind: .number, keyCode: L.kEscape, plain: true), .dismissConsume)
        XCTAssertEqual(L.action(kind: .number, keyCode: 49 /* space */, plain: true), .dismissPass)
    }

    func testStateMachineShowAcceptDismiss() {
        let s = CaretSuggestion(kind: .math, display: "= 36", replace: "", insert: "36")
        let hint = CaretHint.shared
        XCTAssertNil(hint.keyAction(keyCode: L.kTab, plain: true))          // chưa hiện: Tab thường
        hint.setPendingForTesting(s)
        XCTAssertTrue(hint.isShowing)
        XCTAssertEqual(hint.candidateStrings, ["= 36"])
        XCTAssertEqual(hint.keyAction(keyCode: L.kTab, plain: true), .accept)
        XCTAssertEqual(hint.take(), s)
        XCTAssertFalse(hint.isShowing)
        XCTAssertNil(hint.take())                                            // chỉ một lần

        hint.setPendingForTesting(s)
        XCTAssertEqual(hint.keyAction(keyCode: 0, plain: true), .dismissPass)
        hint.dismiss()
        XCTAssertFalse(hint.isShowing)
        XCTAssertEqual(hint.candidateStrings, [])
    }

    /// Tap chỉ lo ô nổi; ô ứng viên hệ thống do controller IMK xử lý.
    func testTapIgnoresCandidateSurface() {
        let s = CaretSuggestion(kind: .number, display: "50.000 ₫", replace: "50k ", insert: "50.000 ₫ ")
        CaretHint.shared.setPendingForTesting(s, surface: .candidates)
        XCTAssertNil(CaretHint.shared.keyAction(keyCode: L.kTab, plain: true, panelOnly: true))
        XCTAssertEqual(CaretHint.shared.keyAction(keyCode: L.kTab, plain: true), .accept)
        CaretHint.shared.setPendingForTesting(s, surface: .panel)
        XCTAssertEqual(CaretHint.shared.keyAction(keyCode: L.kTab, plain: true, panelOnly: true), .accept)
    }

    /// Click (ô nổi bỏ qua chuột) ⇒ con trỏ dời ⇒ tắt: Tab sau đó là Tab thường.
    func testClickDismissesPanelHint() {
        CaretHint.shared.setPendingForTesting(CaretSuggestion(kind: .math, display: "= 4", replace: "", insert: "4"))
        CaretHint.shared.dismissForClick(at: CGPoint(x: 10, y: 10))
        XCTAssertFalse(CaretHint.shared.isShowing)
        XCTAssertNil(CaretHint.shared.keyAction(keyCode: L.kTab, plain: true))
    }

    // MARK: Chip số

    func testNumberTriggerOnlyAtSpaceAfterDigits() {
        XCTAssertTrue(L.numberWorthChecking(boundary: " ", run: "1tr2", prevRun: ""))
        XCTAssertTrue(L.numberWorthChecking(boundary: " ", run: "50k", prevRun: "giá"))
        XCTAssertTrue(L.numberWorthChecking(boundary: " ", run: "tỷ", prevRun: "2"))          // "2 tỷ"
        XCTAssertFalse(L.numberWorthChecking(boundary: " ", run: "hello", prevRun: "xin"))
        XCTAssertFalse(L.numberWorthChecking(boundary: " ", run: "", prevRun: "5"))           // dấu cách thứ hai
        XCTAssertFalse(L.numberWorthChecking(boundary: ".", run: "50k", prevRun: ""))
        XCTAssertFalse(L.numberWorthChecking(boundary: nil, run: "50k", prevRun: ""))
    }

    func testMoneyChipOnlyMoneyFormat() {
        XCTAssertEqual(L.moneyChip(before: "giá 1tr2 "),
                       CaretSuggestion(kind: .number, display: "1.200.000 ₫", replace: "1tr2 ", insert: "1.200.000 ₫ "))
        XCTAssertEqual(L.moneyChip(before: "mua 2 tỷ ")?.replace, "2 tỷ ")
        XCTAssertEqual(L.moneyChip(before: "giá 1250000đ ")?.display, "1.250.000đ")
        XCTAssertEqual(L.moneyChip(before: "giá -50k ")?.display, "-50.000 ₫")
        XCTAssertNil(L.moneyChip(before: "giá 1250000 "))        // đọc chữ — không có trên macOS
        XCTAssertNil(L.moneyChip(before: "giá 1.200.000 ₫ "))    // đọc chữ + "đồng"
        XCTAssertNil(L.moneyChip(before: "giá 50k"))              // chưa có dấu cách
        XCTAssertNil(L.moneyChip(before: "giá 50k  "))            // hai dấu cách
        XCTAssertNil(L.moneyChip(before: "gọi 0912345678 "))
    }

    /// Mọi ca chip dạng-tiền (có dấu cách cuối) của fixture chung iOS/Android phải ra đúng
    /// cùng kết quả; ca đọc-chữ thì macOS không gợi ý.
    func testSharedFixtureMoneyCases() throws {
        let text = try String(contentsOf: Self.fixture, encoding: .utf8)
        var money = 0
        for line in text.split(separator: "\n") where line.hasPrefix("chip|") {
            let c = line.split(separator: "|", omittingEmptySubsequences: false)
                .map { String($0).replacingOccurrences(of: "␣", with: " ") }
            let before = c[1].hasSuffix(" ") ? c[1] : c[1] + " "
            let got = L.moneyChip(before: before)
            if c[2] == "-" || !L.isMoneyFormat(c[2]) {
                if c[2] == "-" || c[1].hasSuffix(" ") { XCTAssertNil(got, "«\(c[1])»") }
                continue
            }
            money += 1
            XCTAssertEqual(got?.display, c[2], "«\(c[1])»")
            XCTAssertEqual(got?.replace.trimmingCharacters(in: .whitespaces),
                           c[3].trimmingCharacters(in: .whitespaces), "«\(c[1])»")
            XCTAssertEqual(got?.insert, c[2] + " ", "«\(c[1])»")
        }
        XCTAssertGreaterThan(money, 8)
    }

    func testKeyStreamBefore() {
        XCTAssertEqual(L.keyStreamBefore(anchored: true, prevRun: "2", run: "tỷ"), "2 tỷ ")
        XCTAssertEqual(L.keyStreamBefore(anchored: true, prevRun: "", run: "50k"), "50k ")
        XCTAssertNil(L.keyStreamBefore(anchored: false, prevRun: "", run: "50k"))
    }

    // MARK: Firefox — AX mù, văn bản từ dòng phím (#104)
    //
    // Field report #104 (v1.8.3, macOS 27): Firefox trên docs.google.com / google.com gõ
    // "50k␣" và "12*3=" không hiện gợi ý (Edge/Zen thì có). Log: đường tap (sel=true), và
    // `field-scan org.mozilla.firefox: … host=? roles=[AXWindow→AXApplication→no-parent]`
    // — Gecko không lộ phần tử văn bản AX, AX đọc chữ/caret đều nil. Cụm gõ ngay sau
    // click chưa NEO nên keyStreamBefore(anchored:) cũng nil ⇒ không có nguồn văn bản.

    /// Click vào ô rồi gõ "50k␣" (đường tap: "50" là ranh giới, "k" chốt ở dấu cách).
    private func tailAfterClick(_ pieces: [String]) -> ShortcutTail {
        var t = ShortcutTail()
        t.caretMoved()
        for p in pieces { t.append(p) }
        return t
    }

    func testFirefoxNumberChipFromKeyStreamAfterClick() {
        let t = tailAfterClick(["5", "0", "k"])
        XCTAssertFalse(t.anchored)                                                   // gốc bug: chưa neo
        XCTAssertNil(L.keyStreamBefore(anchored: t.anchored, prevRun: "", run: t.run))
        let before = L.keyStreamBefore(known: t.knownText, pending: " ")
        XCTAssertEqual(before, "50k ")
        let s = L.moneyChip(before: before!)
        XCTAssertEqual(s?.display, "50.000 ₫")
        // Tab: dòng phím (đã nối dấu cách) xác nhận chữ cần thay ⇒ được ⌫ + gõ lại.
        var after = t; after.append(" ")
        XCTAssertTrue(L.keyStreamConfirms(replace: s!.replace, known: after.knownText))
    }

    func testFirefoxMathFromKeyStream() {
        // "12*3=": mọi phím là ranh giới; "=" chưa vào tail lúc keyDown ⇒ pending "=".
        let t = tailAfterClick(["1", "2", "*", "3"])
        let before = L.keyStreamBefore(known: t.knownText, pending: "=")
        XCTAssertEqual(before, "12*3=")
        XCTAssertEqual(MathHintLogic.result(beforeCaret: before!), "36")
        // Có dấu cách: "12 * 3 =" — cụm ShortcutTail chỉ còn "" nhưng recent giữ cả dòng.
        let spaced = tailAfterClick(["1", "2", " ", "*", " ", "3", " "])
        XCTAssertEqual(MathHintLogic.result(beforeCaret: L.keyStreamBefore(known: spaced.knownText, pending: "=")!), "36")
        // Dấu phân cách suy từ cả biểu thức, có dấu cách quanh phép tính (Phil: "26,160 * 2,500=").
        for (typed, want) in [("26,160 * 2,500", "65,400,000"), ("26,160 * 2500", "65,400,000"),
                              ("26.163 * 2,5", "65.407,5"), ("26,163 * 2.5", "65,407.5")] {
            let t = tailAfterClick(typed.map { String($0) })
            let before = L.keyStreamBefore(known: t.knownText, pending: "=")
            XCTAssertEqual(before, typed + "=")
            XCTAssertEqual(MathHintLogic.result(beforeCaret: before!), want, typed)
        }
    }

    func testKeyStreamUnknownWithoutCaretJumpOrSpace() {
        // Gõ tiếp từ chỗ con trỏ không biết (không click, không khoảng trắng): không đoán.
        var t = ShortcutTail()
        t.append("50k")
        XCTAssertNil(t.knownText)
        XCTAssertNil(L.keyStreamBefore(known: t.knownText, pending: " "))
        XCTAssertFalse(L.keyStreamConfirms(replace: "50k ", known: t.knownText))
        // Có khoảng trắng mình thấy gõ: phần từ đó về sau là chắc.
        t.append(" 20k")
        XCTAssertEqual(t.knownText, " 20k")
        XCTAssertEqual(L.moneyChip(before: L.keyStreamBefore(known: t.knownText, pending: " ")!)?.display,
                       "20.000 ₫")
    }

    func testKeyStreamConfirmRejectsGluedOrStale() {
        XCTAssertFalse(L.keyStreamConfirms(replace: "50k ", known: " a50k "))        // dính chữ trước
        XCTAssertFalse(L.keyStreamConfirms(replace: "50k ", known: "50k"))           // chưa có dấu cách
        XCTAssertFalse(L.keyStreamConfirms(replace: "50k ", known: nil))
        XCTAssertFalse(L.keyStreamConfirms(replace: "", known: "x"))
        XCTAssertTrue(L.keyStreamConfirms(replace: "2 tỷ ", known: " 2 tỷ "))
    }

    func testFirefoxWindowIsNotAField() {
        XCTAssertFalse(L.isFieldRole("AXWindow"))                                   // log #104
        XCTAssertFalse(L.isFieldRole("AXApplication"))
        XCTAssertTrue(L.isFieldRole("AXTextArea"))
        XCTAssertTrue(L.isFieldRole(nil))
    }

    func testWordEventStreams() {
        var ev = CaretHint.WordEvent(boundary: " ", run: "nay", prevRun: "hôm", raw: "nay",
                                     anchored: false, tones: nil, known: "hôm nay")
        XCTAssertEqual(ev.dateStream, "hôm nay ")                                    // sau click, chưa neo
        XCTAssertEqual(ev.typoStream, "hôm nay ")
        ev.known = nil
        XCTAssertNil(ev.dateStream); XCTAssertNil(ev.typoStream)
        ev.anchored = true
        XCTAssertEqual(ev.dateStream, "hôm nay ")                                   // hành vi cũ giữ nguyên
        XCTAssertEqual(ev.typoStream, "nay ")
    }

    // MARK: Vị trí

    private let screens = [NSRect(x: 0, y: 0, width: 1440, height: 900)]
    private let field = NSRect(x: 100, y: 400, width: 800, height: 30)

    private func pick(_ values: [L.CaretSource: NSRect], field: NSRect?) -> (L.CaretSource?, [L.CaretSource]) {
        var asked: [L.CaretSource] = []
        let r = L.anchor(field: field, screens: screens) { src in asked.append(src); return values[src] }
        return (r?.source, asked)
    }

    func testAnchorOrderStopsAtFirstGoodSource() {
        let caret = NSRect(x: 180, y: 405, width: 1, height: 18)
        var (src, asked) = pick([.imkFirstRect: caret, .axCaret: caret], field: field)
        XCTAssertEqual(src, .imkFirstRect); XCTAssertEqual(asked, [.imkFirstRect])   // không gọi AX thừa
        (src, asked) = pick([.axCaret: caret], field: field)
        XCTAssertEqual(src, .axCaret); XCTAssertEqual(asked, [.imkFirstRect, .axCaret])
        (src, _) = pick([.imkLineRect: caret, .axCaret: caret], field: field)
        XCTAssertEqual(src, .axCaret)                                                // TextMate: AX đúng hơn rect dòng
        (src, _) = pick([.imkLineRect: caret], field: field)
        XCTAssertEqual(src, .imkLineRect)                                            // #104 Firefox: AX mù
        (src, _) = pick([.axPrevChar: caret], field: field)
        XCTAssertEqual(src, .axPrevChar)
        (src, _) = pick([.axLineEstimate: caret, .fieldStart: field], field: field)
        XCTAssertEqual(src, .axLineEstimate)
        (src, asked) = pick([:], field: field)
        XCTAssertNil(src)                                                            // không chuột
        XCTAssertEqual(asked, L.order)
    }

    /// Chromium/Electron: rect "con trỏ" cỡ cả ô, rect ngoài ô, rect rỗng ở gốc ⇒ bỏ qua.
    func testAnchorRejectsImplausibleCaretRects() {
        let wholeField = field
        let outside = NSRect(x: 1300, y: 100, width: 1, height: 18)
        let zero = NSRect.zero
        let good = NSRect(x: 150, y: 405, width: 0, height: 18)
        let (src, _) = pick([.imkFirstRect: wholeField, .axCaret: outside, .axPrevChar: zero,
                             .axLineEstimate: good], field: field)
        XCTAssertEqual(src, .axLineEstimate)
    }

    /// Nguồn cuối: mép TRÁI-dưới của ô (không phải mép phải như ảnh chụp lỗi).
    func testFieldStartAnchorsLeftBottom() {
        let r = L.anchor(field: field, screens: screens) { $0 == .fieldStart ? self.field : nil }
        XCTAssertEqual(r?.source, .fieldStart)
        XCTAssertEqual(r?.rect.minX, field.minX + 8)
        XCTAssertEqual(r?.rect.minY, field.minY)
        let origin = TextToolsPanelLogic.origin(caret: r!.rect, panelSize: NSSize(width: 120, height: 28),
                                                visible: screens[0])
        XCTAssertLessThan(origin.x, field.midX)
        XCTAssertLessThan(origin.y, field.minY)                                      // dưới ô
    }

    func testLineEstimate() {
        let one = L.lineEstimate(field: field, line: 0, column: 7)
        XCTAssertEqual(one.minX, field.minX + 8 + 7 * 7.5)
        XCTAssertEqual(one.midY, field.midY, accuracy: 0.01)                         // ô một dòng: giữa
        let tall = NSRect(x: 100, y: 100, width: 600, height: 300)
        let l2 = L.lineEstimate(field: tall, line: 2, column: 500)
        XCTAssertEqual(l2.minX, tall.maxX - 8)                                       // kẹp trong ô
        XCTAssertEqual(l2.minY, tall.maxY - 4 - 3 * 18)
        XCTAssertEqual(L.column(before: "abc\n12*3="), 5)
        XCTAssertEqual(L.column(before: "12*3="), 5)
    }

    // MARK: #104 — kiểm theo cửa sổ, firstRect đứng yên, vị trí dự phòng

    /// Cửa sổ Edge (Cocoa, gốc dưới-trái): x 200…1200, y 100…800 (đỉnh = 800).
    private let edgeWindow = NSRect(x: 200, y: 100, width: 1000, height: 700)

    /// Edge (#104): firstRect trả gốc cửa sổ (góc trên-trái) — trước đây ô hiện ở đó.
    func testEdgeJunkAtWindowTopLeftRejected() {
        let junkBelowTop = NSRect(x: 200, y: 782, width: 0, height: 18)      // đỉnh rect = đỉnh cửa sổ
        let junkAboveTop = NSRect(x: 200, y: 800, width: 0, height: 18)      // đáy rect = đỉnh cửa sổ
        let nearJunk = NSRect(x: 203, y: 779, width: 0, height: 18)          // lệch ≤ 4pt vẫn là rác
        for r in [junkBelowTop, junkAboveTop, nearJunk] {
            XCTAssertTrue(TextToolsPanelLogic.isUsableCaretRect(r, screens: screens) || r == junkAboveTop)
            XCTAssertFalse(L.plausibleCaret(r, field: nil, window: edgeWindow, screens: screens), "\(r)")
        }
        // Đúng log của reporter: AX không có ô (no-focused-element), chỉ firstRect + rect dòng rác.
        let r = L.anchor(field: nil, window: edgeWindow, screens: screens) { src in
            switch src {
            case .imkFirstRect: return junkBelowTop
            case .imkLineRect: return NSRect(x: 200, y: 782, width: 1000, height: 18)
            default: return nil
            }
        }
        XCTAssertNil(r)                                                       // ⇒ dùng fallback
        // Không biết cửa sổ ⇒ hành vi cũ (không loại thêm).
        XCTAssertTrue(L.plausibleCaret(junkBelowTop, field: nil, window: nil, screens: screens))
    }

    func testCaretMustBeInsideFrontWindow() {
        let real = NSRect(x: 420, y: 300, width: 0, height: 18)              // ô bình luận giữa trang
        XCTAssertTrue(L.plausibleCaret(real, field: nil, window: edgeWindow, screens: screens))
        let realTopLine = NSRect(x: 260, y: 760, width: 0, height: 18)       // dòng trên cùng, không sát góc
        XCTAssertTrue(L.plausibleCaret(realTopLine, field: nil, window: edgeWindow, screens: screens))
        let outside = NSRect(x: 1300, y: 300, width: 0, height: 18)          // cửa sổ khác / màn khác
        XCTAssertFalse(L.plausibleCaret(outside, field: nil, window: edgeWindow, screens: screens))
        let degenerate = NSRect(x: 420, y: 300, width: 0, height: 0)          // cao 0
        XCTAssertFalse(L.plausibleCaret(degenerate, field: nil, window: edgeWindow, screens: screens))
        // Cửa sổ vô nghĩa (nhỏ / ngoài màn) ⇒ bỏ qua kiểm cửa sổ.
        XCTAssertTrue(L.plausibleCaret(outside, field: nil, window: NSRect(x: 0, y: 0, width: 10, height: 10),
                                       screens: screens))
        XCTAssertTrue(L.plausibleCaret(outside, field: nil, window: NSRect(x: 5000, y: 0, width: 800, height: 600),
                                       screens: screens))
    }

    /// firstRect không dời khi con trỏ dời ⇒ rác; app trả rect con trỏ thật (dời theo) ⇒ tin.
    func testStaticFirstRectRejected() {
        var t = L.StaticRectTracker()
        let junk = NSRect(x: 300, y: 500, width: 0, height: 18)
        XCTAssertTrue(t.trust(app: "edge", offset: 3, rect: junk))           // lần đầu: chưa biết
        XCTAssertFalse(t.trust(app: "edge", offset: 12, rect: junk))         // vị trí khác, rect y hệt
        XCTAssertFalse(t.trust(app: "edge", offset: 12, rect: junk))         // đã nhớ: vẫn loại
        XCTAssertFalse(t.trust(app: "edge", offset: 3, rect: junk))          // kể cả cùng vị trí cũ
        let moved = NSRect(x: 360, y: 500, width: 0, height: 18)
        XCTAssertTrue(t.trust(app: "edge", offset: 20, rect: moved))         // ô khác, con trỏ thật

        var u = L.StaticRectTracker()
        XCTAssertTrue(u.trust(app: "a", offset: 5, rect: junk))
        XCTAssertTrue(u.trust(app: "a", offset: 5, rect: junk))              // cùng vị trí: không kết luận
        XCTAssertTrue(u.trust(app: "b", offset: 9, rect: junk))              // app khác: không so
        XCTAssertTrue(u.trust(app: "b", offset: 10, rect: junk.offsetBy(dx: 7.5, dy: 0)))   // dời theo chữ
    }

    private var screenPairs: [(frame: NSRect, visible: NSRect)] {
        [(frame: screens[0], visible: NSRect(x: 0, y: 0, width: 1440, height: 875))]
    }
    private let hintSize = NSSize(width: 150, height: 28)

    /// Firefox (#104): không nguồn nào (AX mù, firstRect nil) ⇒ chuột trong cửa sổ ⇒ ngay
    /// dưới chuột, canh trái theo chuột.
    func testFallbackNearPointerInsideWindow() {
        let none = L.anchor(field: nil, window: edgeWindow, screens: screens) { _ in nil }
        XCTAssertNil(none)
        let mouse = NSPoint(x: 500, y: 400)
        let f = L.fallback(window: edgeWindow, mouse: mouse, screens: screenPairs, panelSize: hintSize)
        XCTAssertEqual(f?.basis, .pointer)
        XCTAssertEqual(f?.origin.x, 500)
        XCTAssertEqual(f!.origin.y + hintSize.height, mouse.y - 10 - 4, accuracy: 0.01)   // dưới dòng của chuột
    }

    /// Chuột ngoài cửa sổ đang trước (gõ bằng phím, chuột để ở Dock…) ⇒ giữa-đáy cửa sổ.
    func testFallbackWindowBottomCentre() {
        let f = L.fallback(window: edgeWindow, mouse: NSPoint(x: 1350, y: 40), screens: screenPairs,
                           panelSize: hintSize)
        XCTAssertEqual(f?.basis, .windowBottom)
        XCTAssertEqual(f!.origin.x + hintSize.width / 2, edgeWindow.midX, accuracy: 0.01)
        XCTAssertEqual(f?.origin.y, edgeWindow.minY + 24)
        // Cửa sổ tràn xuống dưới màn hình ⇒ phần thấy được, kẹp trong visibleFrame.
        let tall = NSRect(x: 200, y: -300, width: 1000, height: 1100)
        let g = L.fallback(window: tall, mouse: NSPoint(x: 1350, y: 40), screens: screenPairs, panelSize: hintSize)
        XCTAssertEqual(g?.origin.y, 24)
    }

    /// Không biết cửa sổ ⇒ không hiện (không đoán bừa trên màn hình).
    func testFallbackNeedsWindow() {
        XCTAssertNil(L.fallback(window: nil, mouse: NSPoint(x: 500, y: 400), screens: screenPairs, panelSize: hintSize))
        XCTAssertNil(L.fallback(window: NSRect(x: 0, y: 0, width: 20, height: 20), mouse: .zero,
                                screens: screenPairs, panelSize: hintSize))
    }

    func testSurfaceChoice() {
        XCTAssertEqual(L.surface(kind: .typo, imkPath: true, hasCandidateWindow: true, source: .imkFirstRect), .candidates)
        // Sửa từ phía trước: cụm nhiều từ, ô hệ thống cắt chữ ⇒ luôn ô nổi tự giãn.
        XCTAssertEqual(L.surface(kind: .retro, imkPath: true, hasCandidateWindow: true, source: .imkFirstRect), .panel)
        XCTAssertEqual(L.surface(kind: .typo, imkPath: true, hasCandidateWindow: true, source: .axCaret), .panel)
        XCTAssertEqual(L.surface(kind: .typo, imkPath: false, hasCandidateWindow: true, source: .imkFirstRect), .panel)
        XCTAssertEqual(L.surface(kind: .typo, imkPath: true, hasCandidateWindow: false, source: .imkFirstRect), .panel)
        // Gợi ý từ: luôn ô nổi một ứng viên — ô hệ thống đánh số "1" (Phil 16/10/2026).
        XCTAssertEqual(L.surface(kind: .predict, imkPath: true, hasCandidateWindow: true, source: .imkFirstRect), .panel)
    }

    func testNumberChipsSettingRoundTrip() {
        let before = AppState.shared.numberChips
        defer { AppState.shared.numberChips = before }
        AppState.shared.numberChips = false
        XCTAssertFalse(CaretHint.shared.numberEnabled)
        AppState.shared.numberChips = true
        XCTAssertTrue(CaretHint.shared.numberEnabled)
    }

    /// Cờ CaretHint ghi trên main, đọc ở TAP-thread mỗi phím: snapshot dưới khoá, không
    /// bao giờ đọc ra trạng thái nửa vời (trước là 5 var trơn — data race).
    func testFlagsAreLockedSnapshot() {
        let hint = CaretHint.shared
        defer { hint.reloadSetting() }
        let on = CaretHint.Flags(math: true, number: true, typo: true, tones: true, date: true)
        let off = CaretHint.Flags()
        // The host app may reloadSetting() concurrently (settings observers) — that
        // writes the persisted flags, also a whole snapshot.
        let persisted = CaretHint.Flags.current()
        DispatchQueue.concurrentPerform(iterations: 2000) { i in
            if i % 2 == 0 {
                hint.setFlags(i % 4 == 0 ? on : off)
            } else {
                let f = hint.flagsSnapshot
                XCTAssertTrue(f == on || f == off || f == persisted, "torn snapshot \(f)")
            }
        }
        hint.setFlags(on)
        XCTAssertTrue(hint.mathEnabled && hint.numberEnabled && hint.wordHintsEnabled)
        hint.setFlags(off)
        XCTAssertFalse(hint.mathEnabled || hint.numberEnabled || hint.wordHintsEnabled)
    }
}

/// TextMate (Phil 04/10/2026, log "caret diag"): firstRect rác, rect dòng IMK lệch, AX đúng.
/// Ô gợi ý phải neo theo AX — nằm ngay dưới chữ đang gõ, không theo rect dòng.
final class CaretHintTextMateTests: XCTestCase {
    typealias L = CaretHintLogic
    func testTextMatePrefersAXOverIMKLineRect() {
        let screens = [NSRect(x: 0, y: 0, width: 1710, height: 1112)]
        let win = NSRect(x: 0, y: 62, width: 1710, height: 1011)
        let field = NSRect(x: 43, y: 87, width: 1667, height: 958)
        let cases: [(first: NSRect, line: NSRect, ax: NSRect)] = [
            (NSRect(x: 0, y: 328353, width: 0, height: 1), NSRect(x: 152, y: 954, width: 1, height: 19), NSRect(x: 86, y: 989, width: 1, height: 16)),
            (NSRect(x: 0, y: 328357, width: 0, height: 1), NSRect(x: 253, y: 922, width: 1, height: 19), NSRect(x: 86, y: 957, width: 1, height: 16)),
            (NSRect(x: 0, y: 328361, width: 0, height: 1), NSRect(x: 340, y: 890, width: 1, height: 19), NSRect(x: 86, y: 925, width: 1, height: 16)),
        ]
        for c in cases {
            let r = L.anchor(field: field, window: win, screens: screens) { src in
                switch src {
                case .imkFirstRect: return c.first
                case .imkLineRect: return c.line
                case .axCaret: return c.ax
                default: return nil
                }
            }
            XCTAssertEqual(r?.source, .axCaret)
            XCTAssertEqual(r?.rect, c.ax)
            // Ô gợi ý đặt DƯỚI dòng đang gõ: đỉnh ô ≤ đáy rect con trỏ.
            let size = NSSize(width: 140, height: 28)
            let o = TextToolsPanelLogic.origin(caret: c.ax, panelSize: size, visible: screens[0])
            XCTAssertLessThanOrEqual(o.y + size.height, c.ax.minY + 0.5)
        }
    }
}

