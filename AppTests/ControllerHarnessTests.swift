import XCTest
import InputMethodKit
import TelexCore
@testable import VietTelex

/// Văn bản giả của một app (IMKTextInput) — NSMutableString + con trỏ + vùng marked —
/// để chạy TelexInputController.handle(_:client:) đầu-cuối mà không cần IMKServer.
/// Phím handle() trả false = app tự gõ ký tự đó (như AppKit thật).
final class FakeIMKClient: NSObject, IMKTextInput {
    let text = NSMutableString()
    var caret = 0
    var marked = NSRange(location: NSNotFound, length: 0)
    let bundleID: String
    var log: [String] = []
    /// Số lần IME đọc văn bản (attributedSubstring) — kiểm "tắt = không đọc màn hình".
    var reads = 0

    init(bundleID: String, text initial: String = "") {
        self.bundleID = bundleID
        text.append(initial)
        caret = text.length
    }

    var string: String { text as String }

    /// Mô phỏng app áp insertText BẤT ĐỒNG BỘ (WhatsApp desktop, field 03/11/2026):
    /// mỗi lệnh được NHẬN ngay nhưng chỉ áp vào văn bản khi `settle()` (run loop của
    /// app quay một vòng); selectedRange/đọc màn hình trả trạng thái ĐÃ ÁP (cũ). Lúc
    /// nhận, một replacementRange vượt quá văn bản đã áp bị coi như "không có range"
    /// ⇒ chèn tại con trỏ (APPEND) — đúng dạng hỏng "looix" → "loôiỗi".
    var asyncApply = false
    private var pending: [() -> Void] = []
    var pendingCount: Int { pending.count }

    /// App áp hết các lệnh đang chờ, đúng thứ tự nhận.
    func settle() {
        let ops = pending
        pending.removeAll()
        for op in ops { op() }
    }

    func insertText(_ string: Any!, replacementRange: NSRange) {
        let s = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        if asyncApply {
            var r: NSRange? = replacementRange.location == NSNotFound ? nil : replacementRange
            if let rr = r, rr.location + rr.length > text.length {
                log.append("range ignored (pending edits) @\(rr.location)+\(rr.length) len=\(text.length)")
                r = nil
            }
            log.append("queue \(s.debugDescription)" + (r.map { " @\($0.location)+\($0.length)" } ?? " @caret"))
            pending.append { [unowned self] in
                if s == "\u{7f}" {                 // ⌫ native
                    guard self.caret > 0 else { return }
                    self.text.deleteCharacters(in: NSRange(location: self.caret - 1, length: 1))
                    self.caret -= 1
                    return
                }
                let rr = r ?? NSRange(location: self.caret, length: 0)
                self.text.replaceCharacters(in: rr, with: s)
                self.caret = rr.location + (s as NSString).length
            }
            return
        }
        var r = replacementRange
        if r.location == NSNotFound {
            r = marked.location != NSNotFound ? marked : NSRange(location: caret, length: 0)
        }
        log.append("insert \(s.debugDescription) @\(r.location)+\(r.length)")
        text.replaceCharacters(in: r, with: s)
        caret = r.location + (s as NSString).length
        marked = NSRange(location: NSNotFound, length: 0)
    }

    func setMarkedText(_ string: Any!, selectionRange: NSRange, replacementRange: NSRange) {
        let s = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        let r = marked.location != NSNotFound ? marked : NSRange(location: caret, length: 0)
        log.append("mark \(s.debugDescription) @\(r.location)+\(r.length)")
        text.replaceCharacters(in: r, with: s)
        let n = (s as NSString).length
        marked = n > 0 ? NSRange(location: r.location, length: n) : NSRange(location: NSNotFound, length: 0)
        caret = r.location + n
    }

    /// AppKit gõ ký tự của phím mà IME trả lại.
    /// "\u{7f}" = ⌫ native (xoá một ký tự trước con trỏ).
    func typeNatively(_ s: String) {
        if s == "\u{7f}", !asyncApply {
            log.append("native ⌫")
            if caret > 0 { text.deleteCharacters(in: NSRange(location: caret - 1, length: 1)); caret -= 1 }
            return
        }
        insertText(s, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    func selectedRange() -> NSRange { NSRange(location: caret, length: 0) }
    func markedRange() -> NSRange { marked }
    func attributedSubstring(from range: NSRange) -> NSAttributedString! {
        guard range.location != NSNotFound, range.location >= 0,
              range.location + range.length <= text.length else { return nil }
        reads += 1
        return NSAttributedString(string: text.substring(with: range))
    }
    func length() -> Int { text.length }
    func characterIndex(for point: NSPoint, tracking mappingMode: IMKLocationToOffsetMappingMode,
                        inMarkedRange: UnsafeMutablePointer<ObjCBool>!) -> Int { caret }
    func attributes(forCharacterIndex index: Int, lineHeightRectangle lineRect: UnsafeMutablePointer<NSRect>!) -> [AnyHashable: Any]! {
        lineRect?.pointee = NSRect(x: 100, y: 100, width: 1, height: 16)
        return [:]
    }
    func validAttributesForMarkedText() -> [Any]! { [] }
    func overrideKeyboard(withKeyboardNamed keyboardUniqueName: String!) {}
    func selectMode(_ modeIdentifier: String!) {}
    func supportsUnicode() -> Bool { true }
    func bundleIdentifier() -> String! { bundleID }
    func windowLevel() -> CGWindowLevel { 0 }
    func supportsProperty(_ property: TSMDocumentPropertyTag) -> Bool { false }
    func uniqueClientIdentifierString() -> String! { "fake-\(bundleID)" }
    func string(from range: NSRange, actualRange: NSRangePointer!) -> String! {
        attributedSubstring(from: range)?.string
    }
    func firstRect(forCharacterRange aRange: NSRange, actualRange: NSRangePointer!) -> NSRect {
        NSRect(x: 100, y: 100, width: 1, height: 16)
    }
}

/// Lái TelexInputController như IMK thật: phím → handle(); false ⇒ app tự gõ.
final class ControllerHarness {
    let controller = TelexInputController()
    let client: FakeIMKClient
    private var ts: TimeInterval = 1000
    /// AppKit (NSTextView — TextEdit) gọi commitComposition lên IME sau khi TỰ xử lý
    /// một phím IME trả lại (đo trên TextEdit, commit 1483053e: ⌫ echo đi native ⇒
    /// commitComposition). Bật = mô phỏng đúng hành vi đó.
    var appKitCommitsAfterNativeKey = true

    static let keyCodes: [Character: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19,
        "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29,
        "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "'": 39, "k": 40,
        ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, " ": 49, "-": 27, "\"": 39, "*": 28, "@": 19,
    ]

    init(bundleID: String, text: String = "") {
        client = FakeIMKClient(bundleID: bundleID, text: text)
        AppState.shared.currentBundleID = bundleID
        FrontmostApp.shared._testSetBundleID(bundleID)
    }

    @discardableResult
    func key(_ ch: Character, gap: TimeInterval = 0.15) -> Bool {
        ts += gap
        let lower = Character(ch.lowercased())
        let code = Self.keyCodes[lower] ?? 0
        let shift = ch.isUppercase || ch == "\"" || ch == "*" || ch == "@"
        let s = String(ch)
        let ev = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: shift ? [.shift] : [],
                                  timestamp: ts, windowNumber: 0, context: nil, characters: s,
                                  charactersIgnoringModifiers: String(lower), isARepeat: false, keyCode: code)!
        let handled = controller.handle(ev, client: client)
        if !handled {
            client.typeNatively(s)
            if appKitCommitsAfterNativeKey { controller.commitComposition(client) }
        }
        return handled
    }

    func type(_ s: String, gap: TimeInterval = 0.15) { for c in s { key(c, gap: gap) } }

    /// Phím không có ký tự in được (Tab = 48, Esc = 53…).
    @discardableResult
    func keyCode(_ code: UInt16, chars: String = "", gap: TimeInterval = 0.15) -> Bool {
        ts += gap
        let ev = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ts,
                                  windowNumber: 0, context: nil, characters: chars,
                                  charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
        let handled = controller.handle(ev, client: client)
        if !handled, !chars.isEmpty { client.typeNatively(chars) }
        return handled
    }

    /// Phím Return thật. handle() trả false ⇒ app tự chèn xuống dòng (và AppKit gọi
    /// commitComposition như mọi phím native khác).
    @discardableResult
    func enter(gap: TimeInterval = 0.15) -> Bool { key(code: 36, chars: "\r", gap: gap) }

    /// Phím có mã + ký tự bất kỳ (Return…) như key(_:) — false ⇒ app tự gõ.
    @discardableResult
    func key(code: UInt16, chars: String, gap: TimeInterval = 0.15) -> Bool {
        ts += gap
        let ev = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ts,
                                  windowNumber: 0, context: nil, characters: chars,
                                  charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
        let handled = controller.handle(ev, client: client)
        if !handled {
            client.typeNatively(chars == "\r" ? "\n" : chars)
            if appKitCommitsAfterNativeKey { controller.commitComposition(client) }
        }
        return handled
    }

    // MARK: Phím IME post (re-post Return/Tab, phím vượt — SyntheticKeyboard._testPostKeyHook)

    struct Posted: Equatable { let key: CGKeyCode; let flags: CGEventFlags; let privateSource: Bool }
    /// Phím controller đã "post" vào hàng sự kiện mà window server chưa giao lại.
    var posted: [Posted] = []

    /// Gắn test seam: post ⇒ xếp vào `posted` (không bao giờ post CGEvent thật).
    func capturePosts() {
        SyntheticKeyboard._testPostKeyHook = { [weak self] k, f, p in
            self?.posted.append(Posted(key: k, flags: f, privateSource: p))
        }
    }

    static let charsForKeyCode: [UInt16: (plain: String, shifted: String)] = {
        var m: [UInt16: (String, String)] = [:]
        for (c, code) in keyCodes where c != "\"" && c != "*" && c != "@" {
            let s = String(c)
            m[code] = (s, s == "'" ? "\"" : s.uppercased())
        }
        m[36] = ("\r", "\r"); m[48] = ("\t", "\t"); m[28] = ("8", "*"); m[24] = ("=", "+")
        return m
    }()

    /// Window server giao lại các phím đã post, đúng thứ tự post (kể cả phím được post
    /// thêm trong lúc giao). `magicIntact` = macOS cũ giữ magic của nguồn riêng; macOS 26
    /// xoá magic trước IMKit (đo 08/2026) — cả hai phải đúng.
    func deliverPosted(magicIntact: Bool = false) {
        while !posted.isEmpty {
            let p = posted.removeFirst()
            let shift = p.flags.contains(.maskShift)
            let chars = Self.charsForKeyCode[UInt16(p.key)].map { shift ? $0.shifted : $0.plain } ?? ""
            guard let cg = CGEvent(keyboardEventSource: nil, virtualKey: p.key, keyDown: true) else { continue }
            cg.flags = p.flags
            let units = Array(chars.utf16)
            cg.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            if p.privateSource && magicIntact { cg.setIntegerValueField(.eventSourceUserData, value: SyntheticKeyboard.magic) }
            guard let ev = NSEvent(cgEvent: cg) else { continue }
            let handled = controller.handle(ev, client: client)
            if !handled {
                client.typeNatively(chars == "\r" ? "\n" : chars)
                if appKitCommitsAfterNativeKey { controller.commitComposition(client) }
            }
        }
    }

    /// Gõ `raw`, cho gợi ý từ `word` hiện (như hết idleDelay), rồi Tab nhận.
    func acceptPrediction(typing raw: String, typed: String, word: String) {
        type(raw)
        CaretHint.shared.setPendingForTesting(PredictionLogic.suggestion([word], typed: typed))
        keyCode(48, chars: "\t")
    }
}

/// Đầu-cuối qua handle(): cài đặt Nhập văn bản của macOS (SystemAutoText) trên app
/// in-place built-in (TextEdit). Phil 16/10/2026: "word␣␣" không ra "word. " trên TextEdit.
final class ControllerHarnessTests: XCTestCase {
    private var savedDebug = false
    private var savedBreaker = true

    override func setUp() {
        super.setUp()
        Accessibility.testTrustOverride = true
        FocusedFieldDetector._testSetCached(false)
        FocusedFieldDetector._testSetMarked(false)
        FocusedFieldDetector._testSetPassthrough(false)
        SystemInlinePrediction.setForTesting(false)
        SystemAutoTextSettings.shared._testSet(.init(period: true, capitalize: true, quotes: true, dashes: true))
        savedDebug = AppState.shared.debugLogging
        AppState.shared.debugLogging = true
        // handle() tới từ test không có khoảng cách thời gian thật giữa các phím —
        // bộ phát hiện gõ máy (≥ 6 phím liền < ngưỡng) sẽ nhả thô; tắt cho harness.
        savedBreaker = AppState.shared.tapCascadeBreaker
        AppState.shared.tapCascadeBreaker = false
        DebugLog.clear()
    }

    override func tearDown() {
        CaretHint.shared.setPendingForTesting(nil)
        Accessibility.testTrustOverride = nil
        SystemInlinePrediction.setForTesting(nil)
        AppState.shared.debugLogging = savedDebug
        AppState.shared.tapCascadeBreaker = savedBreaker
        AppState.shared.currentBundleID = nil
        FrontmostApp.shared._testSetBundleID(nil)
        super.tearDown()
    }

    private func dump(_ h: ControllerHarness) -> String {
        "text=\(h.client.string.debugDescription)\nclient:\n" + h.client.log.joined(separator: "\n")
            + "\nlog:\n" + DebugLog.snapshot(header: [])
    }

    func testHarnessTypesPlainTelexInPlace() {
        let h = ControllerHarness(bundleID: "com.apple.TextEdit", text: "a ")
        h.type("vieejt ")
        XCTAssertEqual(h.client.string, "a việt ", dump(h))
    }

    // MARK: Eager English restore (18/10/2026)

    /// "goog" thay vì "gôg" giữa từ: phím g thứ hai là MỘT lần ghi đè giữa từ (⌫1 + "oog")
    /// qua đúng đường in-place của mọi phép biến đổi; dấu cách sau đó không ghi đè gì.
    func testEagerEnglishRestoreInPlaceRewritesMidWordOnce() {
        let saved = AppState.shared.autoRestore
        defer { AppState.shared.autoRestore = saved }
        AppState.shared.autoRestore = true
        let h = ControllerHarness(bundleID: "com.apple.TextEdit", text: "a ")
        h.type("goog")
        XCTAssertEqual(h.client.string, "a goog", dump(h))
        h.type("le ")
        XCTAssertEqual(h.client.string, "a google ", dump(h))
        h.type("windows ")
        XCTAssertEqual(h.client.string, "a google windows ", dump(h))
    }

    /// Tắt tự khôi phục ⇒ không eager (boundary giữ "gôgle" như cũ — chữ chốt không đổi).
    func testEagerEnglishRestoreFollowsAutoRestore() {
        let saved = AppState.shared.autoRestore
        defer { AppState.shared.autoRestore = saved }
        AppState.shared.autoRestore = false
        let h = ControllerHarness(bundleID: "com.apple.TextEdit", text: "a ")
        h.type("goog")
        XCTAssertEqual(h.client.string, "a gôg", dump(h))
        h.type("le ")
        XCTAssertEqual(h.client.string, "a gôgle ", dump(h))
    }

    /// Marked mode: composition hiện "goog" ngay, chốt "google".
    func testEagerEnglishRestoreMarkedMode() {
        let saved = AppState.shared.autoRestore
        defer { AppState.shared.autoRestore = saved; FocusedFieldDetector._testSetMarked(false) }
        AppState.shared.autoRestore = true
        FocusedFieldDetector._testSetMarked(true)
        let h = ControllerHarness(bundleID: "com.apple.TextEdit", text: "a ")
        h.type("goog")
        XCTAssertEqual(h.client.string, "a goog", dump(h))
        h.type("le ")
        XCTAssertEqual(h.client.string, "a google ", dump(h))
    }

    // MARK: Teencode "Dạa" (18/10/2026)

    /// Boundary rewrite ⌫1 + "ạa" qua đường in-place; teencode tắt (mặc định app) = "dậ".
    func testTeencodeToneThenAInPlace() {
        let saved = AppState.shared.teencode
        defer { AppState.shared.teencode = saved }
        AppState.shared.teencode = true
        let h = ControllerHarness(bundleID: "com.apple.TextEdit", text: "a ")
        h.type("daja ")
        XCTAssertEqual(h.client.string, "a dạa ", dump(h))
        AppState.shared.teencode = false
        let g = ControllerHarness(bundleID: "com.apple.TextEdit", text: "a ")
        g.type("daja ")
        XCTAssertEqual(g.client.string, "a dậ ", dump(g))
    }

    // MARK: Dấu chấm khi nhấn đúp phím cách

    /// Lỗi gốc: AppKit gọi commitComposition sau dấu cách native ⇒ shortcutTail.reset()
    /// ⇒ phím cách thứ hai không còn thấy "d␣" ⇒ hai dấu cách thường ("a word  ").
    func testDoubleSpaceInsertsPeriodInTextEdit() {
        let h = ControllerHarness(bundleID: "com.apple.TextEdit", text: "a ")
        h.type("word ")
        h.key(" ", gap: 0.12)
        XCTAssertEqual(h.client.string, "a word. ", dump(h))
        // Gõ tiếp ngay sau: chữ đầu câu mới viết hoa.
        h.type("ban")
        XCTAssertEqual(h.client.string, "a word. Ban", dump(h))
    }

    func testDoubleSpaceAfterVietnameseWord() {
        let h = ControllerHarness(bundleID: "com.apple.TextEdit", text: "a ")
        h.type("dduwowcj ")
        h.key(" ", gap: 0.12)
        XCTAssertEqual(h.client.string, "a được. ", dump(h))
    }

    /// Không Trợ năng: cụm vẫn bị commitComposition xoá (giữ hành vi cũ) — dấu thời gian
    /// của dấu cách đầu + đọc 2–4 ký tự trước con trỏ vẫn quyết được.
    func testDoubleSpaceWithoutAccessibility() {
        Accessibility.testTrustOverride = false
        let h = ControllerHarness(bundleID: "com.apple.TextEdit", text: "a ")
        h.type("word ")
        h.key(" ", gap: 0.12)
        XCTAssertEqual(h.client.string, "a word. ", dump(h))
    }

    /// App không gọi commitComposition sau phím native (Chromium, app khác): vẫn đúng.
    func testDoubleSpaceWithoutAppKitCommit() {
        let h = ControllerHarness(bundleID: "com.apple.TextEdit", text: "a ")
        h.appKitCommitsAfterNativeKey = false
        h.type("word ")
        h.key(" ", gap: 0.12)
        XCTAssertEqual(h.client.string, "a word. ", dump(h))
    }

    func testDoubleSpaceAfterPunctuationStaysPlain() {
        let h = ControllerHarness(bundleID: "com.apple.TextEdit", text: "a ")
        h.type("word. ")
        h.key(" ", gap: 0.12)
        XCTAssertEqual(h.client.string, "a word.  ", dump(h))
        Accessibility.testTrustOverride = false
        let h2 = ControllerHarness(bundleID: "com.apple.TextEdit", text: "a ")
        h2.type("word. ")
        h2.key(" ", gap: 0.12)
        XCTAssertEqual(h2.client.string, "a word.  ", dump(h2))
    }

    func testTripleSpaceAddsOnlyOnePeriod() {
        let h = ControllerHarness(bundleID: "com.apple.TextEdit", text: "a ")
        h.type("word ")
        h.key(" ", gap: 0.12)
        h.key(" ", gap: 0.12)
        XCTAssertEqual(h.client.string, "a word.  ", dump(h))
    }

    /// Tắt cài đặt ⇒ không đổi gì và KHÔNG đọc màn hình ở phím cách (chi phí 0).
    func testPeriodOffIsPlainAndReadsNothing() {
        SystemAutoTextSettings.shared._testSet(.init())
        let h = ControllerHarness(bundleID: "com.apple.TextEdit", text: "a ")
        h.type("word ")
        let reads = h.client.reads
        h.key(" ", gap: 0.12)
        XCTAssertEqual(h.client.string, "a word  ", dump(h))
        XCTAssertEqual(h.client.reads, reads, "phím cách khi tắt không được đọc màn hình")
    }

    func testTerminalNeverGetsPeriod() {
        XCTAssertFalse(SystemAutoText.appAllowed("com.apple.Terminal"))
    }

    // MARK: Gạch dài

    func testDoubleHyphenBecomesEmDashInTextEdit() {
        let h = ControllerHarness(bundleID: "com.apple.TextEdit", text: "a ")
        h.type("word --")
        XCTAssertEqual(h.client.string, "a word —", dump(h))
    }

    // MARK: Dấu câu ngay sau khi nhận gợi ý từ (dấu cách tự thêm)

    func testPeriodAfterAcceptedPredictionAttachesAndCapitalizes() {
        let h = ControllerHarness(bundleID: "com.apple.TextEdit", text: "a ")
        h.acceptPrediction(typing: "dduw", typed: "đư", word: "được")
        XCTAssertEqual(h.client.string, "a được ", dump(h))
        h.key(".")
        XCTAssertEqual(h.client.string, "a được. ", "dấu chấm dính vào từ, dấu cách dời ra sau: " + dump(h))
        h.type("ban")
        XCTAssertEqual(h.client.string, "a được. Ban", "chữ đầu câu mới viết hoa: " + dump(h))
    }

    func testCommaAfterAcceptedPredictionThenSpaceIsSwallowed() {
        let h = ControllerHarness(bundleID: "com.apple.TextEdit", text: "a ")
        h.acceptPrediction(typing: "dduw", typed: "đư", word: "được")
        h.key(",")
        XCTAssertEqual(h.client.string, "a được, ", dump(h))
        h.key(" ")
        XCTAssertEqual(h.client.string, "a được, ", "dấu cách kế bị nuốt (không thành hai): " + dump(h))
        h.type("ok")
        XCTAssertEqual(h.client.string, "a được, ok", dump(h))
    }

    func testOtherKeysAfterAcceptedPredictionAreUntouched() {
        let h = ControllerHarness(bundleID: "com.apple.TextEdit", text: "a ")
        h.acceptPrediction(typing: "dduw", typed: "đư", word: "được")
        h.type("ban")
        XCTAssertEqual(h.client.string, "a được ban", dump(h))
        h.key(".")
        XCTAssertEqual(h.client.string, "a được ban.", "chỉ phím NGAY SAU: " + dump(h))
        // "/" chỉ gỡ dấu cách; dấu cách thứ hai = chấm câu nhấn đúp như thường.
        let h2 = ControllerHarness(bundleID: "com.apple.TextEdit", text: "a ")
        h2.acceptPrediction(typing: "dduw", typed: "đư", word: "được")
        h2.key("/")
        XCTAssertEqual(h2.client.string, "a được/", dump(h2))
        let h3 = ControllerHarness(bundleID: "com.apple.TextEdit", text: "a ")
        h3.acceptPrediction(typing: "dduw", typed: "đư", word: "được")
        h3.key(" ", gap: 0.12)
        XCTAssertEqual(h3.client.string, "a được. ", "dấu cách kế = chấm câu nhấn đúp: " + dump(h3))
        // Nháy thẳng: thường là nháy MỞ của từ kế — không gỡ.
        let h4 = ControllerHarness(bundleID: "com.apple.TextEdit", text: "a ")
        h4.acceptPrediction(typing: "dduw", typed: "đư", word: "được")
        XCTAssertFalse(PredictionLogic.acceptSpaceReaction("\"") != .keep)
    }

    func testAcceptedSpaceReReadsScreen() {
        let h = ControllerHarness(bundleID: "com.apple.TextEdit", text: "a ")
        h.acceptPrediction(typing: "dduw", typed: "đư", word: "được")
        h.client.text.append("x")            // app đổi chữ (tự động hoàn thành, dán…)
        h.client.caret = h.client.text.length
        h.key(".")
        XCTAssertEqual(h.client.string, "a được x.", "màn hình lệch ⇒ không đụng gì: " + dump(h))
    }

    // MARK: Đuôi email (EmailDomainPrediction)

    /// Tab chèn NGUYÊN VĂN phần còn thiếu, không dấu cách; chữ gõ tiếp không bị bỏ dấu ngược
    /// vào tên miền ("coms" không thành "cóm").
    func testEmailDomainAcceptInsertsRawAndResetsEngine() {
        let savedReEdit = AppState.shared.reEditWord
        defer { AppState.shared.reEditWord = savedReEdit }
        AppState.shared.reEditWord = true      // re-edit bật là ca dễ hỏng nhất ("com" + s → "cóm")
        let h = ControllerHarness(bundleID: "com.apple.TextEdit", text: "mail ")
        h.type("user@gm")
        XCTAssertEqual(h.client.string, "mail user@gm", dump(h))
        CaretHint.shared.setPendingForTesting(
            EmailDomainPrediction.suggestion(before: h.client.string, typed: "gm", raw: "gm"))
        h.keyCode(48, chars: "\t")
        XCTAssertEqual(h.client.string, "mail user@gmail.com", dump(h))
        h.type("s")
        XCTAssertEqual(h.client.string, "mail user@gmail.coms", "engine reset — không bỏ dấu ngược: " + dump(h))
        // Chỉ phím NGAY SAU: re-edit bình thường trở lại cho chữ gõ tay sau đó.
    }

    func testEmailDomainRightAfterAtThenTab() {
        let h = ControllerHarness(bundleID: "com.apple.TextEdit", text: "mail ")
        h.type("user@")
        XCTAssertEqual(h.client.string, "mail user@", dump(h))
        CaretHint.shared.setPendingForTesting(EmailDomainPrediction.suggestion(before: h.client.string, typed: "", raw: ""))
        h.keyCode(48, chars: "\t")
        XCTAssertEqual(h.client.string, "mail user@gmail.com", "không lặp @: " + dump(h))
        h.key(" ")
        h.type("ok")
        XCTAssertEqual(h.client.string, "mail user@gmail.com ok", dump(h))
    }

    /// Màn hình lệch (app đổi chữ) ở nhánh thay từ đang soạn ⇒ không đụng gì.
    func testEmailDomainReplaceReReadsScreen() {
        let h = ControllerHarness(bundleID: "com.apple.TextEdit", text: "user@")
        CaretHint.shared.setPendingForTesting(
            CaretSuggestion(kind: .email, display: "yahoo.com", replace: "yahô", insert: "yahoo.com"))
        h.keyCode(48, chars: "\t")
        XCTAssertEqual(h.client.string, "user@", dump(h))
        let h2 = ControllerHarness(bundleID: "com.apple.TextEdit", text: "user@yahô")
        CaretHint.shared.setPendingForTesting(
            CaretSuggestion(kind: .email, display: "yahoo.com", replace: "yahô", insert: "yahoo.com"))
        h2.keyCode(48, chars: "\t")
        XCTAssertEqual(h2.client.string, "user@yahoo.com", dump(h2))
    }

    func testAcceptSpaceReactionTable() {
        typealias L = PredictionLogic
        for p in [".", ",", "?", "!", ";", ":", ")", "]", "}", "\u{201D}", "\u{2019}", "»"] {
            XCTAssertEqual(L.acceptSpaceReplacement(p), p + " ", p)
        }
        XCTAssertEqual(L.acceptSpaceReplacement("/"), "/")
        for p in ["a", " ", "\"", "'", "(", "-", "1", "ab"] { XCTAssertNil(L.acceptSpaceReplacement(p), p) }
    }

    // MARK: Viết hoa đầu câu

    func testCapitalizeAfterTypedPeriod() {
        FocusedRole._testOverride = true
        defer { FocusedRole._testOverride = nil }
        let h = ControllerHarness(bundleID: "com.apple.TextEdit", text: "")
        h.type("xin chao. ban")
        XCTAssertEqual(h.client.string, "Xin chao. Ban", dump(h))
    }

    func testCapitalizeAfterTypedPeriodWithoutAccessibility() {
        Accessibility.testTrustOverride = false
        let h = ControllerHarness(bundleID: "com.apple.TextEdit", text: "a ")
        h.type("xin chao. ban")
        XCTAssertEqual(h.client.string, "a xin chao. Ban", dump(h))
    }

    func testCapitalizeTelexWordAtSentenceStart() {
        let h = ControllerHarness(bundleID: "com.apple.TextEdit", text: "a. ")
        h.type("dduwowcj")
        XCTAssertEqual(h.client.string, "a. Được", dump(h))
    }

    func testCapitalizeTelexWordAtDocumentStart() {
        FocusedRole._testOverride = true
        defer { FocusedRole._testOverride = nil }
        let h = ControllerHarness(bundleID: "com.apple.TextEdit", text: "")
        h.type("dduwowcj")
        XCTAssertEqual(h.client.string, "Được", dump(h))
    }

    /// Ô một dòng (không phải AXTextArea) ở đầu văn bản: không viết hoa.
    func testNoCapitalizeAtStartOfSingleLineField() {
        FocusedRole._testOverride = false
        defer { FocusedRole._testOverride = nil }
        let h = ControllerHarness(bundleID: "com.apple.TextEdit", text: "")
        h.type("xin")
        XCTAssertEqual(h.client.string, "xin", dump(h))
    }
}

