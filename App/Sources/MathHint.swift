// MathHint.swift — gợi ý cạnh con trỏ cho macOS: "Hiện kết quả phép tính" ("12*3=" ⇒ "= 36")
// và "Chip số" (chỉ dạng tiền: "1tr2␣" ⇒ "1.200.000 ₫"). Logic chung iOS/Android:
// iOS/Keyboard/MathResults.swift + NumberChips.swift (fixture math-results.txt / number-chips.txt).
// KHÔNG tự chèn — chỉ đề xuất; Tab (phép tính: cả Enter) mới áp dụng, phím khác thì tắt.
//
// Hai kiểu hiển thị:
//  • Ô ứng viên HỆ THỐNG (IMKCandidates) — đường IMK (app in-place/marked) khi client
//    báo được rect con trỏ (firstRect) hợp lệ: cửa sổ ứng viên chuẩn của macOS, đặt
//    ngay dưới con trỏ bàn phím.
//  • Ô nổi riêng (NSPanel không lấy focus) — đường tap (terminal, Chromium, Office) và
//    app IMK có firstRect hỏng. Vị trí: firstRect của client IMK (nếu cùng app) → rect
//    dòng của client IMK → AX bounds con trỏ → AX bounds ký tự trước con trỏ → ước lượng
//    theo số dòng AX → góc TRÁI-dưới của ô đang gõ (không bao giờ khung CẢ CỬA SỔ). Mọi
//    rect "con trỏ" phải nằm trong cửa sổ đang trước (CGWindowList), không dính góc
//    trên-trái cửa sổ, không suy biến, và (firstRect) phải dời theo con trỏ — Edge trả gốc
//    cửa sổ khi không biết con trỏ (#104: ô hiện ở góc trên-trái cửa sổ).
//    Không nguồn nào tin được (Firefox, Edge rác) ⇒ vị trí DỰ ĐOÁN ĐƯỢC thay vì không hiện:
//    ngay dưới con trỏ chuột nếu chuột nằm trong cửa sổ đang trước (thường là chỗ vừa
//    click vào ô gõ), không thì giữa-đáy cửa sổ đó; không biết cửa sổ ⇒ không hiện.
//
// Ô AX không đọc được (Firefox: Gecko không bật AX cho process ngoài — #104): văn bản
// trước con trỏ dựng từ chính dòng phím mình thấy gõ kể từ lần dời con trỏ gần nhất
// (ShortcutTail.knownText); Tab chỉ thay khi dòng phím còn xác nhận (keyStreamConfirms).
//
// Chi phí: chỉ chạy NGAY SAU phím "=" / dấu cách sau một cụm có chữ số (một lần đọc
// ~64 ký tự trước con trỏ qua IMK hoặc AX) — phím khác chỉ đọc một cờ dưới khoá.
//  • IMK: TelexInputController.handle gọi `afterEquals` / `afterNumberSpace`, `keyAction`.
//  • Tap: TerminalTap gọi cùng các hàm với client nil trên TAP-thread — trạng thái nằm
//    dưới `lock`. "=" thấy ở cả hai đường chỉ tính một lần (`lastCheck`).
import AppKit
import Carbon.HIToolbox
import InputMethodKit

enum MathHintLogic {
    /// Phím vừa gõ là "=" trơn (không ⌘/⌃/⌥) ⇒ thử tính.
    static func isTrigger(characters: String?, modifiers: NSEvent.ModifierFlags) -> Bool {
        characters == "=" && modifiers.intersection([.command, .control, .option]).isEmpty
    }

    /// Văn bản trước con trỏ (đã có "=" ở cuối) → chữ kết quả để chèn, nil nếu không phải
    /// phép tính (cùng quy tắc với chip iOS/Android — fixture math-results.txt).
    static func result(beforeCaret: String) -> String? {
        MathResults.chip(before: beforeCaret)?.insert
    }

    /// Chữ hiện trong ô: "= 36".
    static func label(_ result: String) -> String { "= " + result }
}

/// Một gợi ý đang chờ: `replace` = đuôi văn bản trước con trỏ sẽ bị thay (rỗng = chỉ
/// chèn thêm — kết quả phép tính), `insert` = chữ chèn vào.
struct CaretSuggestion: Equatable {
    /// math/number: MathHint.swift; typo/tones/date: CaretSuggestions.swift;
    /// predict: gợi ý từ (WordPrediction.swift); email: đuôi email "user@g" → gmail.com
    /// (EmailDomainPrediction, WordPrediction.swift) — cùng họ gợi ý từ (ô nổi, click được,
    /// nhường gợi ý khác) nhưng chèn nguyên văn, không dấu cách, không học.
    /// retro: đề xuất "Tự sửa từ phía trước" khi công tắc tắt (RetroEnglishApply.swift) —
    /// thắng mọi gợi ý khác (chỉ hiện khi mạch tiếng Anh đã chắc).
    enum Kind: Equatable {
        case math, number, typo, tones, date, predict, email, retro
        /// Họ gợi ý từ (cài đặt "Show inline predictive text").
        var isPrediction: Bool { self == .predict || self == .email }
    }
    let kind: Kind
    let display: String
    let replace: String
    let insert: String
}

/// Logic THUẦN của gợi ý cạnh con trỏ (test được, không AppKit sống).
enum CaretHintLogic {
    /// Thứ tự gợi ý ranh giới từ (sau ngày giờ): có lỗi gõ đáng xét thì xét trước; KHÔNG ra
    /// sửa lỗi nào thì vẫn xét Thêm dấu (`typoThenTones`). Bug 18/10/2026: nhánh lỗi gõ
    /// return luôn ⇒ bật Sửa lỗi gõ là mất gợi ý thêm dấu ("toi di hoc").
    enum WordHintPlan: Equatable { case none, typo, tones, typoThenTones }
    static func wordHintPlan(typo: Bool, tones: Bool) -> WordHintPlan {
        switch (typo, tones) {
        case (true, true): return .typoThenTones
        case (true, false): return .typo
        case (false, true): return .tones
        case (false, false): return .none
        }
    }

    /// Gợi ý mới `new` có nhường gợi ý đang hiện `current` không (true ⇒ không hiện `new`).
    /// Sửa ngược tiếng Anh thắng tất cả; gợi ý từ nhường mọi loại khác.
    static func yields(_ new: CaretSuggestion.Kind, to current: CaretSuggestion.Kind?) -> Bool {
        guard let current, new != .retro else { return false }
        if current == .retro { return true }
        return new.isPrediction && !current.isPrediction
    }

    // MARK: Phím khi gợi ý đang hiện

    enum KeyAction: Equatable {
        case accept          // áp dụng gợi ý, nuốt phím
        case dismissConsume  // Esc: tắt gợi ý, nuốt phím
        case dismissPass     // phím khác: tắt gợi ý, phím đi tiếp như thường
    }

    static let kTab = 48, kReturn = 36, kKeypadEnter = 76, kEscape = 53

    /// `plain` = không ⌘/⌃/⌥/⇧. Tab chấp nhận cả hai loại; Enter chỉ cho phép tính
    /// (sau "50k␣" Enter là gửi tin nhắn / xuống dòng — không được cướp). Phím số KHÔNG
    /// chọn: gõ "5+5=" rồi tự gõ "10" không được thành "1010".
    static func action(kind: CaretSuggestion.Kind, keyCode: Int, plain: Bool) -> KeyAction {
        if keyCode == kEscape, plain { return .dismissConsume }
        guard plain else { return .dismissPass }
        if keyCode == kTab { return .accept }
        if kind == .math, keyCode == kReturn || keyCode == kKeypadEnter { return .accept }
        return .dismissPass
    }

    // MARK: Chip số (chỉ dạng tiền)

    /// Dấu cách vừa gõ sau một cụm có chữ số ("1tr2", "50k") — hoặc cụm đơn vị ngay sau
    /// cụm số ("2 tỷ", "15 triệu") ⇒ đáng đọc màn hình. Không thì không đọc gì cả.
    static func numberWorthChecking(boundary: String?, run: String, prevRun: String) -> Bool {
        guard boundary == " ", !run.isEmpty else { return false }
        if run.contains(where: \.isNumber) { return true }
        return run.count <= 6 && prevRun.contains(where: \.isNumber)
    }

    /// Văn bản trước con trỏ (kết thúc bằng đúng một dấu cách) → gợi ý dạng tiền, nil nếu
    /// không có. Dùng NumberChips.chip chung iOS/Android nhưng CHỈ giữ dạng tiền
    /// ("1.200.000 ₫", "1.250.000đ") — bỏ "đọc số thành chữ" trên macOS.
    static func moneyChip(before: String) -> CaretSuggestion? {
        guard before.hasSuffix(" "), let c = NumberChips.chip(before: before),
              isMoneyFormat(c.display) else { return nil }
        return CaretSuggestion(kind: .number, display: c.display, replace: c.replace, insert: c.insert)
    }

    static func isMoneyFormat(_ display: String) -> Bool {
        let d = display.hasPrefix("-") ? display.dropFirst() : Substring(display)
        return d.first?.isNumber == true
    }

    /// Văn bản dựng lại từ dòng phím (terminal không đọc được AX): cụm trước + cụm vừa
    /// gõ + dấu cách. Chỉ khi cụm đã NEO (thấy khoảng trắng/xuống dòng trước nó).
    static func keyStreamBefore(anchored: Bool, prevRun: String, run: String) -> String? {
        guard anchored, !run.isEmpty else { return nil }
        return (prevRun.isEmpty ? "" : prevRun + " ") + run + " "
    }

    /// Văn bản dựng lại từ dòng phím (AX không đọc được: terminal, Firefox #104):
    /// `known` = ShortcutTail.knownText (chữ chắc chắn trước con trỏ), `pending` = phần
    /// sắp tới app (từ đang soạn, ranh giới vừa gõ). nil khi không biết gì.
    static func keyStreamBefore(known: String?, pending: String) -> String? {
        guard let known else { return nil }
        let s = known + pending
        return s.isEmpty ? nil : s
    }

    /// Tab trong ô AX không đọc được: chỉ thay khi dòng phím còn xác nhận chữ sắp bị
    /// thay nằm NGAY trước con trỏ và đứng riêng (đầu phần đã biết / sau khoảng trắng).
    static func keyStreamConfirms(replace: String, known: String?) -> Bool {
        guard !replace.isEmpty, let known else { return false }
        return standsAlone(before: known, token: replace)
    }

    /// Phần tử AX đang focus có phải "ô" để neo không: Firefox (Gecko không bật AX) báo
    /// focus là CẢ CỬA SỔ (roles=[AXWindow→AXApplication], #104) — khung cửa sổ không
    /// phải ô gõ, neo vào đó là gợi ý nhảy xuống góc dưới cửa sổ.
    static func isFieldRole(_ role: String?) -> Bool {
        role != "AXWindow" && role != "AXApplication"
    }

    // MARK: Vị trí

    // Thứ tự = thứ tự ưu tiên. Rect dòng IMK đứng SAU các nguồn AX: TextMate (04/10/2026)
    // trả firstRect rác (y≈328353) và rect dòng lệch cả x (152→253→340 khi con trỏ đứng ở
    // x=86) lẫn y (thấp hơn ~2 dòng) ⇒ ô gợi ý "nhảy lung tung", đè chữ. AX caret đúng.
    // App AX mù (Firefox, Edge no-focused-element) không có AX ⇒ vẫn rơi xuống rect dòng.
    enum CaretSource: Equatable, CaseIterable {
        case imkFirstRect     // client IMK: firstRect(forCharacterRange: selectedRange)
        case axCaret          // AXBoundsForRange (caret, 0)
        case axPrevChar       // AXBoundsForRange (caret-1, 1) → mép phải ký tự trước
        case imkLineRect      // client IMK: attributes(forCharacterIndex:lineHeightRectangle:)
        case axLineEstimate   // AXInsertionPointLineNumber + cột → ước lượng
        case fieldStart       // khung ô đang gõ → góc TRÁI-dưới (gần đầu chữ)
    }

    static let order: [CaretSource] = CaretSource.allCases

    /// Khoảng cách ô gợi ý ↔ đáy rect con trỏ (pt). Đo 16/10/2026 (nhật ký caret diag):
    /// TextMate trả rect cao đúng dòng (1x16–19) ⇒ 4pt là vừa (10pt bị chê xa); Notes trả
    /// rect 0x16 cho chữ to hơn, đáy rect nằm trên chân chữ ⇒ 4pt và 10pt đều đè/sát chữ.
    static let panelGap: CGFloat = 4
    static let extraGapApps: [String: CGFloat] = ["com.apple.Notes": 14]
    static func panelGap(for bundleID: String?) -> CGFloat {
        bundleID.flatMap { extraGapApps[$0] } ?? panelGap
    }

    /// Rect con trỏ đầu tiên dùng được theo `order`. `provider` được gọi LẦN LƯỢT và dừng
    /// ở nguồn đầu tiên hợp lệ (mỗi nguồn là vài lần gọi AX/IMK — không gọi thừa).
    /// Nguồn "con trỏ" phải nằm trong ô đang gõ (nếu biết `field`), trong cửa sổ đang
    /// trước (nếu biết `window`) và không to cỡ cả ô (Chromium/Electron hay trả khung ô cho
    /// range rỗng). nil ⇒ dùng `fallback` (chuột / đáy cửa sổ).
    static func anchor(field: NSRect?, window: NSRect? = nil, screens: [NSRect],
                       provider: (CaretSource) -> NSRect?) -> (rect: NSRect, source: CaretSource)? {
        for src in order {
            guard let r = provider(src) else { continue }
            if src == .fieldStart {
                guard TextToolsPanelLogic.isUsableCaretRect(r, screens: screens) || r.height >= 400
                else { continue }
                return (fieldStartAnchor(r), src)
            }
            if plausibleCaret(r, field: field, window: window, screens: screens) { return (r, src) }
        }
        return nil
    }

    static func plausibleCaret(_ r: NSRect, field: NSRect?, window: NSRect? = nil, screens: [NSRect]) -> Bool {
        guard TextToolsPanelLogic.isUsableCaretRect(r, screens: screens), r.width <= 60,
              r.height >= 4 else { return false }                      // suy biến (cao 0) ⇒ rác
        if let w = usableWindow(window, screens: screens), !insideWindow(r, w) { return false }
        guard let f = field, f.width > 0, f.height > 0 else { return true }
        let probe = NSPoint(x: r.minX, y: r.midY)
        return f.insetBy(dx: -4, dy: -4).contains(probe)
    }

    /// Cửa sổ đang trước dùng được để kiểm: đủ lớn, hữu hạn, nằm trên một màn hình.
    static func usableWindow(_ w: NSRect?, screens: [NSRect]) -> NSRect? {
        guard let w, w.width >= 50, w.height >= 50, w.origin.x.isFinite, w.origin.y.isFinite,
              screens.contains(where: { $0.intersects(w) }) else { return nil }
        return w
    }

    /// Rect con trỏ nằm TRONG cửa sổ và KHÔNG dính góc trên-trái của nó. Edge/Chromium
    /// (#104) trả gốc cửa sổ khi không biết con trỏ — rect sát mép trái (±4pt) với đỉnh
    /// (hoặc đáy) sát đỉnh cửa sổ. Không con trỏ thật nào nằm ở đó (thanh tiêu đề/tab).
    static func insideWindow(_ r: NSRect, _ w: NSRect) -> Bool {
        let probe = NSPoint(x: r.minX, y: r.midY)
        guard w.insetBy(dx: -2, dy: -2).contains(probe) else { return false }
        let nearLeft = abs(r.minX - w.minX) <= 4
        let nearTop = abs(r.maxY - w.maxY) <= 4 || abs(r.minY - w.maxY) <= 4
        return !(nearLeft && nearTop)
    }

    // MARK: firstRect đứng yên

    /// firstRect IMK trả CÙNG một rect cho các vị trí con trỏ khác nhau ⇒ rác (client không
    /// biết con trỏ, trả hằng số — #104 Edge). So với mẫu lần hiện trước (cùng app) — không
    /// thăm dò thêm lúc gõ; app trả rect con trỏ bất kể range vẫn qua được vì con trỏ dời
    /// thì rect dời. Rect đã chứng minh đứng yên được nhớ (tối đa 4/app) để lần sau gặp lại
    /// (kể cả cùng vị trí) cũng bị loại. Chỉ dùng trên MAIN.
    struct StaticRectTracker {
        private var last: (app: String, offset: Int, rect: NSRect)?
        private var junk: [String: [NSRect]] = [:]

        static func same(_ a: NSRect, _ b: NSRect) -> Bool {
            abs(a.minX - b.minX) <= 0.5 && abs(a.minY - b.minY) <= 0.5
                && abs(a.width - b.width) <= 0.5 && abs(a.height - b.height) <= 0.5
        }

        /// Ghi mẫu và trả về rect có tin được không.
        mutating func trust(app: String, offset: Int, rect: NSRect) -> Bool {
            if junk[app]?.contains(where: { Self.same($0, rect) }) == true { return false }
            defer { last = (app, offset, rect) }
            guard let l = last, l.app == app, l.offset != offset, Self.same(l.rect, rect) else { return true }
            junk[app] = Array(((junk[app] ?? []) + [rect]).suffix(4))
            return false
        }
    }

    // MARK: Không có con trỏ tin được

    enum FallbackBasis: Equatable { case pointer, windowBottom }

    /// Vị trí dự phòng khi không nguồn con trỏ nào tin được (Firefox, Edge trả rác):
    ///  1. chuột nằm trong cửa sổ đang trước ⇒ ngay DƯỚI chuột (canh trái theo chuột) —
    ///     thường là chỗ vừa click vào ô gõ; đặt dưới dòng nên không che chữ đang gõ;
    ///  2. không ⇒ giữa-đáy cửa sổ đang trước (24pt trên mép dưới, phần thấy được);
    ///  3. không biết cửa sổ ⇒ nil (không hiện — không có gì để neo).
    /// Chỉ dùng khi `anchor` trả nil, nên không bao giờ thay một rect con trỏ thật.
    static func fallback(window: NSRect?, mouse: NSPoint,
                         screens: [(frame: NSRect, visible: NSRect)],
                         panelSize: NSSize) -> (origin: NSPoint, basis: FallbackBasis)? {
        guard let w = usableWindow(window, screens: screens.map(\.frame)) else { return nil }
        let fallbackVisible = screens.first?.visible ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        func visible(at p: NSPoint) -> NSRect {
            screens.first { $0.frame.insetBy(dx: -1, dy: -1).contains(p) }?.visible ?? fallbackVisible
        }
        if w.insetBy(dx: 4, dy: 4).contains(mouse) {
            // Rect giả cao 20pt quanh điểm nóng của chuột (I-beam cao ~18pt) ⇒ ô hiện dưới nó.
            let pseudo = NSRect(x: mouse.x, y: mouse.y - 10, width: 0, height: 20)
            return (TextToolsPanelLogic.origin(caret: pseudo, panelSize: panelSize, visible: visible(at: mouse)),
                    .pointer)
        }
        let vis = visible(at: NSPoint(x: w.midX, y: w.midY))
        let area = w.intersection(vis).isEmpty ? w : w.intersection(vis)
        let o = NSPoint(x: area.midX - panelSize.width / 2, y: area.minY + 24)
        return (TextToolsPanelLogic.clamp(o, panelSize: panelSize, visible: vis), .windowBottom)
    }

    /// Nguồn cuối: khung ô ⇒ neo ở mép TRÁI (lề 8pt), đáy ô — ô gợi ý hiện ngay dưới
    /// đầu ô gõ thay vì tít mép phải.
    static func fieldStartAnchor(_ field: NSRect) -> NSRect {
        let h = min(field.height, 22)
        return NSRect(x: field.minX + 8, y: field.minY, width: 0, height: h)
    }

    /// Ước lượng rect con trỏ từ số dòng AX (0-based) và cột (số ký tự sau "\n" cuối).
    /// Ô một dòng (thấp) ⇒ giữa ô theo chiều dọc. x kẹp trong ô.
    static func lineEstimate(field: NSRect, line: Int, column: Int,
                             lineHeight: CGFloat = 18, charWidth: CGFloat = 7.5, inset: CGFloat = 8) -> NSRect {
        let x = min(field.minX + inset + CGFloat(max(0, column)) * charWidth, field.maxX - inset)
        let y: CGFloat
        if field.height < 44 {
            y = field.midY - lineHeight / 2
        } else {
            y = max(field.minY, field.maxY - 4 - CGFloat(max(0, line) + 1) * lineHeight)
        }
        return NSRect(x: x, y: y, width: 0, height: lineHeight)
    }

    /// Cột con trỏ theo văn bản trước nó.
    static func column(before: String) -> Int {
        guard let i = before.lastIndex(where: { $0 == "\n" || $0 == "\r" }) else { return before.count }
        return before.distance(from: before.index(after: i), to: before.endIndex)
    }

    // MARK: Kiểu hiển thị

    enum Surface: Equatable { case candidates, panel }

    /// Ô ứng viên hệ thống chỉ khi: đường IMK (client + controller), có IMKServer, và
    /// firstRect của client là nguồn thắng (hệ thống đặt cửa sổ theo chính client đó).
    /// Gợi ý từ: LUÔN ô nổi ("được  ⇥ Tab", click được) — ô hệ thống đánh số "1" trước ứng
    /// viên, gợi ý từ chỉ có một ứng viên, không số thứ tự (Phil 16/10/2026).
    static func surface(kind: CaretSuggestion.Kind, imkPath: Bool, hasCandidateWindow: Bool,
                        source: CaretSource) -> Surface {
        guard !kind.isPrediction else { return .panel }
        return imkPath && hasCandidateWindow && source == .imkFirstRect ? .candidates : .panel
    }
}

final class CaretHint {
    static let shared = CaretHint()
    private let lock = NSLock()
    private var pending: CaretSuggestion?                   // guarded by lock
    private var pendingSurface: CaretHintLogic.Surface?     // guarded by lock
    private var lastCheck: UInt64 = 0                       // guarded by lock
    private var shownFrameCG: CGRect?                       // guarded by lock (toạ độ CG, gốc trên-trái)
    private var window: NSPanel?                            // main only
    private var hideWork: DispatchWorkItem?                 // main only
    private var firstRectTracker = CaretHintLogic.StaticRectTracker()   // main only
    /// Thế hệ phím: +1 mỗi phím (keyAction) — việc chạy nền (sửa lỗi gõ, Thêm dấu) chỉ hiện
    /// kết quả khi chưa có phím nào mới từ lúc kích hoạt ("gõ tiếp là huỷ").
    private var keyGen: UInt64 = 0                          // guarded by lock
    /// Từ người dùng đã Esc gợi ý sửa (chữ thường, trong phiên) / cụm không dấu đã Esc.
    private let rejectedTypos = AutoCorrect.Rejected()      // guarded by lock
    private var declinedTones: String?                      // guarded by lock
    private var fruitlessTones = ToneRunLogic.FruitlessMemo()   // guarded by lock
    /// Gợi ý từ: chữ đang gõ đã Esc (không gợi ý lại khi từ vẫn bắt đầu bằng nó).
    private var declinedPrediction: String?                 // guarded by lock
    /// Đuôi email đã Esc: không mời lại tới khi bắt đầu cụm mới (dấu cách / "@" mới).
    private var declinedEmail = false                       // guarded by lock
    /// Gợi ý từ: hẹn giờ dừng-gõ đang chờ (MAIN).
    private var predictWork: DispatchWorkItem?
    /// Click ô nổi (gợi ý từ, đường IMK) → controller áp dụng (MAIN).
    private weak var pickController: TelexInputController?
    /// Hàng đợi nền nối tiếp: tính gợi ý + mô hình "Học từ bạn gõ" (LearnedWords — cùng hàng đợi
    /// ⇒ xếp hạng đọc dữ liệu học không cần khoá).
    let work = DispatchQueue(label: "com.viettelex.caretsuggest", qos: .userInitiated)
    /// Cờ bật/tắt: GHI trên main (reloadSetting), ĐỌC nhiều lần mỗi phím ở TAP-thread lẫn
    /// main — trước là var trơn (data race giữa hai thread). Giờ là một snapshot dưới khoá
    /// RIÊNG (`flagsLock`, không phải `lock`: không bao giờ lồng khoá NSLock không đệ quy);
    /// mỗi lần đọc một lần lock không tranh chấp (~tens of ns), không đụng UserDefaults.
    struct Flags: Equatable {
        var math = false, number = false, typo = false, tones = false, date = false
        /// "Lọc từ nhạy cảm" (AppState.filterSensitive) — gợi ý từ + sửa lỗi gõ.
        var filterSensitive = true
        /// "Học từ bạn gõ" (AppState.learnWords — LearnedWords.swift); chỉ có tác dụng khi gợi ý
        /// từ chạy (SystemInlinePrediction).
        var learn = true
        static func current() -> Flags {
            Flags(math: AppState.shared.mathResults, number: AppState.shared.numberChips,
                  typo: AppState.shared.typoHints, tones: AppState.shared.toneHints,
                  date: AppState.shared.dateHints, filterSensitive: AppState.shared.filterSensitive,
                  learn: AppState.shared.learnWords)
        }
    }
    private let flagsLock = NSLock()
    private var flags: Flags                                // guarded by flagsLock
    var flagsSnapshot: Flags { flagsLock.withLock { flags } }
    var mathEnabled: Bool { flagsSnapshot.math }
    var numberEnabled: Bool { flagsSnapshot.number }
    var typoEnabled: Bool { flagsSnapshot.typo }
    var tonesEnabled: Bool { flagsSnapshot.tones }
    var dateEnabled: Bool { flagsSnapshot.date }
    /// Có loại gợi ý ranh-giới-từ nào bật không — tắt hết ⇒ controller không làm gì thêm.
    var wordHintsEnabled: Bool { let f = flagsSnapshot; return f.typo || f.tones || f.date }

    private init() { flags = Flags.current() }
    func reloadSetting() { setFlags(Flags.current()) }
    /// Bất kỳ thread (test + reloadSetting).
    func setFlags(_ f: Flags) { flagsLock.withLock { flags = f } }

    var isShowing: Bool { lock.withLock { pending != nil } }
    var current: CaretSuggestion? { lock.withLock { pending } }

    /// Một HÀNG ngang: bảng cột dọc (SingleColumnScrolling) luôn cao ~9 dòng dù chỉ có
    /// một ứng viên (Phil 16/10/2026).
    static let candidatePanelType = kIMKSingleRowSteppingCandidatePanel

    /// Ô ứng viên hệ thống dùng chung (một IMKServer ⇒ một cửa sổ). nil trong test host.
    private static let candidateWindow: IMKCandidates? = {
        guard let server = telexServer,
              let c = IMKCandidates(server: server, panelType: candidatePanelType)
        else { return nil }
        // Phím tới controller TRƯỚC (mặc định cửa sổ ứng viên ăn trước ⇒ Enter/số/mũi tên
        // bị nó xử lý): mình tự quyết Tab/Enter/Esc; phím khác ẩn cửa sổ rồi mới đi tiếp.
        c.setAttributes([IMKCandidatesSendServerKeyEventFirst as String: NSNumber(value: true)])
        return c
    }()

    // MARK: Kích hoạt

    /// Bất kỳ thread. Gọi khi phím "=" vừa gõ. `client` nil ⇒ đường tap (đọc AX; AX
    /// không đọc được ⇒ `keyStream` = văn bản dựng từ dòng phím, đã gồm "=" — #104).
    func afterEquals(client: IMKTextInput?, controller: TelexInputController?, keyStream: String? = nil) {
        guard mathEnabled, !dedupe() else { return }
        // Đợi app nhận "=" (tap: phím đi native; IMK: insertText vừa gọi) rồi mới đọc.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            guard let self,
                  let before = Self.textBeforeCaret(client: client) ?? (client == nil ? keyStream : nil),
                  let r = MathHintLogic.result(beforeCaret: before) else { return }
            let s = CaretSuggestion(kind: .math, display: MathHintLogic.label(r), replace: "", insert: r)
            self.present(s, before: before, client: client, controller: controller)
        }
    }

    /// Bất kỳ thread. Dấu cách vừa gõ sau cụm có chữ số. `keyStream` = văn bản dựng từ
    /// dòng phím (tap, khi AX không đọc được — terminal). `canReplace` = đường gọi thay
    /// được chữ đã chốt (IMK: app đã chứng minh in-place).
    func afterNumberSpace(client: IMKTextInput?, controller: TelexInputController?,
                          keyStream: String?, canReplace: Bool) {
        guard numberEnabled, canReplace else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            guard let self else { return }
            let before = Self.textBeforeCaret(client: client) ?? (client == nil ? keyStream : nil)
            guard let before, let s = CaretHintLogic.moneyChip(before: before) else { return }
            self.present(s, before: before, client: client, controller: controller)
        }
    }

    // MARK: Sửa ngược tiếng Anh — đề xuất (RetroEnglishApply.swift)

    /// Bất kỳ thread, NGAY sau phím ranh giới (caller đã xác nhận kênh + màn hình trước ranh
    /// giới). Đợi ký tự ranh giới tới app rồi đọc lại: văn bản trước con trỏ phải kết thúc
    /// đúng bằng `s.replace` — không thì không hiện. Có phím mới trước đó ⇒ không hiện.
    func offerRetro(_ s: CaretSuggestion, client: IMKTextInput?, controller: TelexInputController?) {
        let gen = keyGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            guard let self, self.keyGeneration == gen, !IsSecureEventInputEnabled() else { return }
            let window = s.replace.utf16.count + RetroApply.displayLookback
            guard let before = Self.textBeforeCaret(client: client, window: window),
                  let display = RetroApply.offerDisplay(before: before, replace: s.replace, insert: s.insert) else {
                DebugLog.log("retro offer: screen disagrees → no hint")
                return
            }
            self.present(CaretSuggestion(kind: .retro, display: display, replace: s.replace, insert: s.insert),
                         before: before, client: client, controller: controller)
        }
    }

    // MARK: Ranh giới từ (CaretSuggestions.swift): sửa lỗi gõ / thêm dấu / ngày giờ

    /// Ranh giới từ vừa gõ. `run` = cụm đã chốt ngay trước ranh giới (ShortcutTail.run),
    /// `prevRun` = cụm trước nó, `raw` = phím thô của từ vừa chốt ("" = không có từ / nở gõ
    /// tắt), `anchored` = dòng phím thấy khoảng trắng trước cụm (dựng lại được văn bản khi
    /// terminal không đọc được AX), `tones` = kích hoạt Thêm dấu từ ToneRunLogic.Tracker.
    struct WordEvent {
        var boundary: String
        var run: String
        var prevRun: String
        var raw: String
        var anchored: Bool
        var tones: ToneRunLogic.Trigger?
        /// ShortcutTail.knownText TRƯỚC ranh giới (tap; nil = không biết / đường IMK).
        var known: String? = nil

        /// Văn bản dựng từ dòng phím khi AX không đọc được — sửa lỗi gõ: phần đã biết
        /// (đủ để xét đầu câu), không thì cụm đã neo.
        var typoStream: String? {
            known.map { $0 + boundary } ?? (anchored ? run + boundary : nil)
        }
        /// Ngày giờ: cụm trước + cụm đã neo như cũ (cụm trước có thể dính chữ không
        /// biết — vẫn đúng), không thì phần đã biết (sau lần dời con trỏ, #104).
        var dateStream: String? {
            anchored && !prevRun.isEmpty ? prevRun + " " + run + " " : known.map { $0 + boundary }
        }
    }

    var keyGeneration: UInt64 { lock.withLock { keyGen } }

    /// Bất kỳ thread (IMK: main; tap: TAP-thread), SAU khi ranh giới đã xử lý. Chỉ gọi khi
    /// `wordHintsEnabled`. Phần ở đây chỉ so chuỗi / kiểm âm tiết (không tra dữ liệu); tra
    /// lexicon và process con Thêm dấu chạy trên hàng đợi nền, đọc màn hình trên main.
    func afterWord(_ ev: WordEvent, client: IMKTextInput?, controller: TelexInputController?,
                   canReplace: Bool) {
        guard canReplace else { return }
        let gen = keyGeneration
        let f = flagsSnapshot
        if f.date, let phrase = DateHintLogic.detect(boundary: ev.boundary, prevRun: ev.prevRun, run: ev.run,
                                                          isEnglish: TypoFixLogic.isEnglish) {
            let stream = ev.dateStream
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
                self?.showIfCurrent(gen, client: client, controller: controller, keyStream: stream) { before in
                    DateHintLogic.suggestion(before: before, prevRun: ev.prevRun, run: ev.run, phrase: phrase, now: Date())
                }
            }
            return
        }
        let typoWorth = f.typo && !ev.raw.isEmpty
            && TypoFixLogic.worthChecking(boundary: ev.boundary, raw: ev.raw, word: ev.run)
            && !lock.withLock({ rejectedTypos.contains(ev.run) })
        let tonesTrigger = f.tones ? ev.tones : nil
        switch CaretHintLogic.wordHintPlan(typo: typoWorth, tones: tonesTrigger != nil) {
        case .none: return
        case .tones: scheduleTones(ev, trigger: tonesTrigger!, gen: gen, client: client, controller: controller)
        case .typo, .typoThenTones:
            let flags = AppState.shared.engineFlags()
            let stream = ev.typoStream
            work.async { [weak self] in
                guard let fix = TypoFixLogic.lexiconCorrection(raw: ev.raw, flags: flags,
                                                              filterSensitive: f.filterSensitive) else {
                    // Không có lỗi gõ ⇒ vẫn xét Thêm dấu cho cụm (trước 18/10/2026: return luôn ⇒
                    // "toi di hoc " không bao giờ được gợi ý thêm dấu khi bật Sửa lỗi gõ).
                    if let t = tonesTrigger {
                        DispatchQueue.main.async {
                            self?.scheduleTones(ev, trigger: t, gen: gen, client: client, controller: controller)
                        }
                    }
                    return
                }
                DispatchQueue.main.async {
                    self?.showIfCurrent(gen, client: client, controller: controller, keyStream: stream) { before in
                        TypoFixLogic.suggestion(before: before, word: ev.run, boundary: ev.boundary, raw: ev.raw, fix: fix)
                    }
                }
            }
        }
    }

    /// MAIN. Thêm dấu cho cụm không dấu: chờ `pauseDelay` (dừng gõ) hoặc 0.04 s (cuối câu),
    /// đọc màn hình, chạy process con, hiện nếu cụm còn đứng riêng.
    private func scheduleTones(_ ev: WordEvent, trigger t: ToneRunLogic.Trigger, gen: UInt64,
                               client: IMKTextInput?, controller: TelexInputController?) {
        let delay = t == .pause ? ToneRunLogic.pauseDelay : 0.04
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            // Nhật ký gỡ lỗi (chỉ độ dài/cờ, không chữ người gõ): vì sao gợi ý thêm dấu không hiện.
            guard self.keyGeneration == gen, !self.isShowing, !IsSecureEventInputEnabled() else {
                DebugLog.log("tones: skip gen=\(self.keyGeneration == gen) showing=\(self.isShowing)")
                return
            }
            guard let before = Self.textBeforeCaret(client: client, window: ToneRunLogic.window) else {
                DebugLog.log("tones: no text before caret"); return
            }
            guard let run = ToneRunLogic.run(before: before) else {
                DebugLog.log("tones: no run (before \(before.count) chars)"); return
            }
            guard self.lock.withLock({ !(self.declinedTones.map { run.hasPrefix($0) } ?? false)
                                        && self.fruitlessTones.allows(run, trigger: t) }) else {
                DebugLog.log("tones: declined/fruitless run \(run.count) chars"); return
            }
            self.work.async {
                // Process con (dữ liệu Thêm dấu không vào process IME); ~0.2 s.
                guard self.keyGeneration == gen else { return }
                let restored = TextActionTransform.addTonesViaHelper(run, timeout: 3)
                guard let restored, ToneRunLogic.suggestion(run: run, restored: restored) != nil else {
                    DebugLog.log("tones: helper \(restored == nil ? "failed" : "no change") run \(run.count) chars")
                    // Vô ích cho cụm này: đừng spawn lại ở mỗi lần dừng gõ kế tiếp.
                    self.lock.withLock { self.fruitlessTones.note(fruitless: run) }
                    return
                }
                DebugLog.log("tones: suggestion ready run \(run.count) chars")
                DispatchQueue.main.async {
                    self.showIfCurrent(gen, client: client, controller: controller, keyStream: nil,
                                       window: ToneRunLogic.window) { before in
                        guard CaretHintLogic.standsAlone(before: before, token: run) else {
                            DebugLog.log("tones: run no longer stands alone (before \(before.count) chars)")
                            return nil
                        }
                        return ToneRunLogic.suggestion(run: run, restored: restored)
                    }
                }
            }
        }
    }

    /// MAIN. Hiện gợi ý do `make` dựng từ văn bản trước con trỏ — chỉ khi chưa có phím mới
    /// kể từ lúc kích hoạt (`gen`) và không ở Secure Input.
    private func showIfCurrent(_ gen: UInt64, client: IMKTextInput?, controller: TelexInputController?,
                               keyStream: String?, window: Int = CaretHint.window64,
                               make: (String) -> CaretSuggestion?) {
        guard keyGeneration == gen, !IsSecureEventInputEnabled() else { return }
        let before = Self.textBeforeCaret(client: client, window: window) ?? (client == nil ? keyStream : nil)
        guard let before, let s = make(before) else { return }
        present(s, before: before, client: client, controller: controller)
    }

    private func dedupe() -> Bool {
        let now = DispatchTime.now().uptimeNanoseconds
        return lock.withLock { () -> Bool in
            defer { lastCheck = now }
            return now &- lastCheck < 150_000_000
        }
    }

    // MARK: Phím

    /// Bất kỳ thread. Việc cần làm với phím này khi gợi ý đang hiện (nil = không hiện gì).
    /// `panelOnly` (tap) ⇒ chỉ nhận gợi ý dạng ô nổi — ô ứng viên IMK do controller lo.
    func keyAction(keyCode: Int, plain: Bool, panelOnly: Bool = false) -> CaretHintLogic.KeyAction? {
        lock.withLock {
            keyGen &+= 1
            guard let p = pending, !panelOnly || pendingSurface == .panel else { return nil }
            return CaretHintLogic.action(kind: p.kind, keyCode: keyCode, plain: plain)
        }
    }

    /// Bất kỳ thread. Lấy gợi ý để áp dụng (và tắt ô).
    func take() -> CaretSuggestion? {
        let r: CaretSuggestion? = lock.withLock {
            defer { pending = nil; pendingSurface = nil; shownFrameCG = nil }
            return pending
        }
        if r != nil { hideUI() }
        return r
    }

    /// Bất kỳ thread. Tắt gợi ý (không chặn phím). Trên main: ẩn NGAY — cửa sổ ứng viên
    /// phải biến mất trước khi phím đi tiếp, không thì nó xử lý phím đó.
    func dismiss() {
        let had = lock.withLock { () -> Bool in
            defer { pending = nil; pendingSurface = nil; shownFrameCG = nil }
            return pending != nil
        }
        if had { hideUI() }
    }

    /// Esc: tắt gợi ý và nhớ lời từ chối — sửa lỗi gõ: không gợi ý lại từ đó (trong phiên);
    /// thêm dấu: không mời lại cụm bắt đầu bằng cụm vừa từ chối (gõ tiếp cùng câu).
    func decline() {
        lock.withLock {
            guard let p = pending else { return }
            switch p.kind {
            case .typo: rejectedTypos.add(String(p.replace.dropLast(1)))   // bỏ ký tự ranh giới
            case .tones: declinedTones = p.replace
            case .predict: declinedPrediction = p.replace.isEmpty ? nil : p.replace
            case .email: declinedEmail = true
            default: break
            }
        }
        dismiss()
    }

    /// TAP-thread (chuột xuống). Click ngoài ô ứng viên đang hiện ⇒ tắt. `point` toạ độ
    /// CGEvent (gốc trên-trái màn hình chính).
    func dismissForClick(at point: CGPoint) {
        LearnedWords.shared.noteClick()      // con trỏ có thể dời: ngữ cảnh học bị cắt
        let inside = lock.withLock { () -> Bool? in
            keyGen &+= 1                      // con trỏ có thể dời: việc nền đang chờ thôi hiện
            guard pending != nil else { return nil }
            return shownFrameCG?.contains(point) ?? false
        }
        if inside == false { dismiss() }
    }

    /// Chỉ cho test: đặt trạng thái như vừa hiện (không tạo cửa sổ).
    func setPendingForTesting(_ s: CaretSuggestion?, surface: CaretHintLogic.Surface = .panel) {
        lock.withLock { pending = s; pendingSurface = s == nil ? nil : surface }
    }

    /// Chỉ cho test: lời từ chối đã nhớ (decline).
    func isTypoRejectedForTesting(_ w: String) -> Bool { lock.withLock { rejectedTypos.contains(w) } }
    func isTonesDeclinedForTesting(_ run: String) -> Bool {
        lock.withLock { declinedTones.map { run.hasPrefix($0) } ?? false }
    }

    /// Chuỗi hiện trong ô ứng viên (IMKInputController.candidates(_:)).
    var candidateStrings: [String] { lock.withLock { pending.map { [$0.display] } ?? [] } }

    // MARK: Gợi ý từ (WordPrediction.swift)

    /// MAIN (đường IMK, sau khi phím đã xử lý xong). Hẹn giờ dừng-gõ; có phím mới trước khi hết
    /// giờ ⇒ không làm gì (thế hệ phím). `typed` = từ đang soạn ("" = vừa gõ dấu cách),
    /// `raw` = phím thô, `english` = ngữ cảnh tiếng Anh. Chỉ gọi khi
    /// SystemInlinePrediction.isOn và app thay được chữ đã chốt.
    func schedulePrediction(typed: String, raw: String, english: Bool,
                            client: IMKTextInput, controller: TelexInputController) {
        predictWork?.cancel()
        let gen = keyGeneration
        let busy = lock.withLock { () -> Bool in
            if typed.isEmpty { declinedPrediction = nil; declinedEmail = false }   // từ mới / "@" mới
            return pending != nil || PredictionLogic.muted(typed: typed, declined: declinedPrediction)
        }
        guard !busy else { return }
        let w = DispatchWorkItem { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.runPrediction(gen, typed: typed, raw: raw, english: english, client: client, controller: controller)
        }
        predictWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + PredictionLogic.idleDelay, execute: w)
    }

    /// MAIN, đã dừng gõ `idleDelay`: đọc màn hình MỘT lần → tính nền → hiện nếu vẫn hiện hành.
    private func runPrediction(_ gen: UInt64, typed: String, raw: String, english: Bool,
                               client: IMKTextInput, controller: TelexInputController) {
        guard keyGeneration == gen, !isShowing, !IsSecureEventInputEnabled(), !SecureFieldDetector.isSecure,
              SystemInlinePrediction.isOn,
              let before = Self.textBeforeCaret(client: client, window: PredictionLogic.window)
        else { return }
        // Đuôi email ("user@", "user@g"): chỉ so chuỗi — hiện ngay, không qua hàng đợi nền.
        if EmailDomainPrediction.looksLikeEmailToken(before) {
            guard !lock.withLock({ declinedEmail }),
                  let s = EmailDomainPrediction.suggestion(before: before, typed: typed, raw: raw) else { return }
            present(s, before: before, client: client, controller: controller)
            return
        }
        guard let req = PredictionLogic.request(before: before, typed: typed, english: english) else { return }
        work.async { [weak self] in
            guard let self, self.keyGeneration == gen else { return }
            let t0 = DispatchTime.now().uptimeNanoseconds
            let f = self.flagsSnapshot
            let words = PredictionModel.shared.candidates(req, raw: raw, filterSensitive: f.filterSensitive,
                                                          learned: f.learn ? LearnedWords.shared.modelForRanking() : nil)
            let us = (DispatchTime.now().uptimeNanoseconds - t0) / 1000
            guard let s = PredictionLogic.suggestion(words, typed: req.typed) else { return }
            DispatchQueue.main.async { [weak self, weak controller] in
                guard let self, let controller, self.keyGeneration == gen, !self.isShowing,
                      !IsSecureEventInputEnabled() else { return }
                if AppState.shared.debugLogging {
                    DebugLog.log("predict: \(req.typed.isEmpty ? "next" : "complete") \(us)µs")
                }
                self.present(s, before: before, client: client, controller: controller)
            }
        }
    }

    /// Cài đặt hệ thống vừa tắt: huỷ hẹn giờ, bỏ bảng seed (trên hàng đợi nền của nó).
    func predictionDisabled() {
        predictWork?.cancel(); predictWork = nil
        work.async { if PredictionModel.shared.isLoaded { PredictionModel.shared.unload() } }
        LearnedWords.shared.unload()
    }

    private func hideUI() {
        if Thread.isMainThread { hideWindows() } else { DispatchQueue.main.async { self.hideWindows() } }
    }

    // MARK: Đọc văn bản trước con trỏ

    private static let window64 = MathResults.maxLength + 2

    private static func textBeforeCaret(client: IMKTextInput?, window: Int = window64) -> String? {
        if let client {
            let sel = client.selectedRange()
            guard sel.location != NSNotFound, sel.length == 0, sel.location > 0 else { return nil }
            let start = max(0, sel.location - window)
            return client.attributedSubstring(from: NSRange(location: start, length: sel.location - start))?.string
        }
        guard let caret = AXTextEdit.readCaret(), caret > 0 else { return nil }
        let start = max(0, caret - window)
        return AXTextEdit.readString(at: start, length: caret - start)
    }

    // MARK: Hiển thị

    private func present(_ s: CaretSuggestion, before: String, client: IMKTextInput?,
                         controller: TelexInputController?) {
        // Gợi ý từ nhường mọi gợi ý khác đang hiện (sửa lỗi gõ, thêm dấu, ngày giờ…); mọi
        // gợi ý nhường đề xuất sửa ngược tiếng Anh (CaretHintLogic.yields).
        if lock.withLock({ CaretHintLogic.yields(s.kind, to: pending?.kind) }) { return }
        hideWindows()
        pickController = s.kind.isPrediction ? controller : nil
        let screens = NSScreen.screens.map(\.frame)
        // Client IMK cho vị trí: đường IMK dùng chính client; đường tap mượn client của
        // controller đang active NẾU cùng app đang trước (firstRect thường đúng hơn AX).
        let posClient = client ?? TelexInputController.activeClientForFrontApp()
        let ax = AXTextEdit.focusedGeometryReader()
        let field = CaretHintLogic.isFieldRole(ax?.role()) ? ax?.fieldFrame() : nil
        let prevIsNewline = before.last == "\n" || before.last == "\r"
        let frontWindow = FrontWindow.frame()
        if AppState.shared.debugLogging {
            // Chẩn đoán vị trí (#104/TextMate): mọi nguồn + kết quả kiểm — chỉ khi bật nhật ký.
            func f(_ r: NSRect?) -> String { r.map { String(format: "(%.0f,%.0f %.0fx%.0f)", $0.minX, $0.minY, $0.width, $0.height) } ?? "nil" }
            let fr = posClient.flatMap(Self.imkCaretRect), lr = posClient.flatMap(Self.imkLineRect)
            let ac = ax?.caretBounds()
            func ok(_ r: NSRect?) -> String { r.map { CaretHintLogic.plausibleCaret($0, field: field, window: frontWindow, screens: screens) ? "ok" : "rej" } ?? "-" }
            let diag = "caret diag \(posClient?.bundleIdentifier() ?? "?"): sel=\(posClient?.selectedRange().location ?? -1) first=\(f(fr))\(ok(fr)) line=\(f(lr))\(ok(lr)) ax=\(f(ac))\(ok(ac)) field=\(f(field)) win=\(f(frontWindow)) mouse=\(f(NSRect(origin: NSEvent.mouseLocation, size: .zero)))"
            DebugLog.log(diag)
            // Cũng ra unified log (chỉ khi bật nhật ký): đo vị trí con trỏ theo app bằng
            // `log show` mà không cần người dùng chép nhật ký.
            Signposts.log.notice("\(diag, privacy: .public)")
        }
        let found = CaretHintLogic.anchor(field: field, window: frontWindow, screens: screens) { src in
            switch src {
            case .imkFirstRect:
                guard let c = posClient, let r = Self.imkCaretRect(c) else { return nil }
                let app = c.bundleIdentifier() ?? "?"
                return firstRectTracker.trust(app: app, offset: c.selectedRange().location, rect: r) ? r : nil
            case .imkLineRect: return posClient.flatMap(Self.imkLineRect)
            case .axCaret: return ax?.caretBounds()
            case .axPrevChar:
                guard !prevIsNewline, let r = ax?.previousCharBounds() else { return nil }
                return NSRect(x: r.maxX, y: r.minY, width: 0, height: r.height)
            case .axLineEstimate:
                guard let f = field, let line = ax?.insertionLine() else { return nil }
                return CaretHintLogic.lineEstimate(field: f, line: line, column: CaretHintLogic.column(before: before))
            case .fieldStart: return field
            }
        }
        guard let found else {
            // Không con trỏ tin được (#104 Firefox/Edge) ⇒ dưới chuột / giữa-đáy cửa sổ.
            let basis = showPanel(s) { size in
                CaretHintLogic.fallback(window: frontWindow, mouse: NSEvent.mouseLocation,
                                        screens: NSScreen.screens.map { ($0.frame, $0.visibleFrame) },
                                        panelSize: size)
            }
            guard let basis else {
                DebugLog.log("caret hint \(s.kind): no caret position, no front window → not shown")
                return
            }
            lock.withLock { pending = s; pendingSurface = .panel }
            scheduleAutoHide()
            DebugLog.log("caret hint \(s.kind): len=\(s.insert.count) via fallback(\(basis)) → panel")
            return
        }
        let surface = CaretHintLogic.surface(kind: s.kind, imkPath: client != nil && controller != nil,
                                             hasCandidateWindow: Self.candidateWindow != nil,
                                             source: found.source)
        lock.withLock { pending = s; pendingSurface = surface }
        if surface == .candidates, let c = Self.candidateWindow {
            showCandidates(c, s, caret: found.rect)
            let f = c.candidateFrame()
            let primaryH = NSScreen.screens.first?.frame.height ?? 0
            let cg = CGRect(x: f.minX, y: primaryH - f.maxY, width: f.width, height: f.height)
            lock.withLock { shownFrameCG = cg }
        } else {
            let caret = found.rect             // ignoresMouseEvents: mọi click đều "ngoài"
            showPanel(s) { size in
                (TextToolsPanelLogic.origin(caret: caret, panelSize: size, visible: Self.visibleFrame(for: caret),
                                            gap: CaretHintLogic.panelGap(for: AppState.shared.currentBundleID)), ())
            }
        }
        scheduleAutoHide()
        DebugLog.log("caret hint \(s.kind): len=\(s.insert.count) via \(found.source) → \(surface)")
        if AppState.shared.debugLogging {
            let r = found.rect
            Signposts.log.notice("caret hint \(String(describing: s.kind), privacy: .public) via \(String(describing: found.source), privacy: .public) rect=(\(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))x\(Int(r.height)))")
        }
    }

    private func scheduleAutoHide() {
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
    }

    private static func imkCaretRect(_ client: IMKTextInput) -> NSRect? {
        let sel = client.selectedRange()
        guard sel.location != NSNotFound else { return nil }
        var actual = NSRange(location: NSNotFound, length: 0)
        return client.firstRect(forCharacterRange: NSRange(location: sel.location, length: 0), actualRange: &actual)
    }

    private static func imkLineRect(_ client: IMKTextInput) -> NSRect? {
        let sel = client.selectedRange()
        guard sel.location != NSNotFound else { return nil }
        var line = NSRect.zero
        _ = client.attributes(forCharacterIndex: sel.location, lineHeightRectangle: &line)
        return line == .zero ? nil : line
    }

    private static func visibleFrame(for caret: NSRect) -> NSRect {
        let probe = NSPoint(x: caret.minX, y: caret.midY)
        let screen = NSScreen.screens.first { $0.frame.insetBy(dx: -1, dy: -1).contains(probe) } ?? NSScreen.main
        return screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private func showCandidates(_ c: IMKCandidates, _ s: CaretSuggestion, caret: NSRect) {
        c.setCandidateData([s.display])
        c.show(kIMKLocateCandidatesBelowHint)
        // Hệ thống tự đặt theo client; đặt lại theo rect đã kiểm (cùng nguồn firstRect)
        // để không bao giờ lệch khỏi con trỏ, và lật lên trên khi sát đáy màn hình.
        let size = c.candidateFrame().size
        if size.width > 0, size.height > 0 {
            let o = TextToolsPanelLogic.origin(caret: caret, panelSize: size, visible: Self.visibleFrame(for: caret),
                                               gap: CaretHintLogic.panelGap(for: AppState.shared.currentBundleID))
            c.setCandidateFrameTopLeft(NSPoint(x: o.x, y: o.y + size.height))
        }
    }

    /// Dựng ô nổi; `place` nhận kích thước ô, trả góc dưới-trái + ghi chú, hoặc nil ⇒
    /// không hiện. Trả ghi chú khi đã hiện.
    @discardableResult
    private func showPanel<Note>(_ s: CaretSuggestion,
                                 place: (NSSize) -> (origin: NSPoint, basis: Note)?) -> Note? {
        // Một nhãn + "⇥ Tab" cho mọi loại; gợi ý từ (đường IMK) thì click cả ô = nhận.
        let clickable = s.kind.isPrediction && pickController != nil
        let label = HintLabel(labelWithString: s.display)
        label.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        let hint = HintLabel(labelWithString: "⇥ Tab")
        hint.font = .systemFont(ofSize: 11, weight: .medium)
        hint.textColor = .secondaryLabelColor
        if clickable {
            for l in [label, hint] { l.onClick = { [weak self] in self?.pick() } }
        }
        let stack = NSStackView(views: [label, hint])
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        let size = stack.fittingSize
        guard let placed = place(size) else { return nil }

        let fx = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        fx.material = .popover
        fx.state = .active
        fx.wantsLayer = true
        fx.layer?.cornerRadius = 8
        fx.layer?.masksToBounds = true
        stack.frame = fx.bounds
        fx.addSubview(stack)

        let w = HintWindow(contentRect: NSRect(origin: .zero, size: size),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.level = .popUpMenu
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        w.ignoresMouseEvents = !clickable
        w.contentView = fx
        w.setFrameOrigin(placed.origin)
        w.orderFrontRegardless()
        window = w
        if clickable {
            // click TRONG ô không được tắt ô (dismissForClick của tap) trước khi tới nhãn
            let f = w.frame
            let primaryH = NSScreen.screens.first?.frame.height ?? 0
            let cg = CGRect(x: f.minX, y: primaryH - f.maxY, width: f.width, height: f.height)
            lock.withLock { shownFrameCG = cg }
        }
        return placed.basis
    }

    /// MAIN. Click ô nổi (gợi ý từ, đường IMK) ⇒ controller áp dụng như Tab.
    private func pick() {
        guard let c = pickController else { dismiss(); return }
        c.applyCaretHintChoice()
    }

    private func hideWindows() {
        hideWork?.cancel(); hideWork = nil
        window?.orderOut(nil)
        window = nil
        if let c = Self.candidateWindow, c.isVisible() { c.hide() }
    }
}

/// Nhãn click được trên ô nổi không-key (click đầu tiên vẫn tới — acceptsFirstMouse).
private final class HintLabel: NSTextField {
    var onClick: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { onClick == nil ? nil : super.hitTest(point) }
    override func mouseDown(with event: NSEvent) {
        if let onClick { onClick() } else { super.mouseDown(with: event) }
    }
}

/// Ô không bao giờ thành key/main: app đang gõ giữ focus.
private final class HintWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
