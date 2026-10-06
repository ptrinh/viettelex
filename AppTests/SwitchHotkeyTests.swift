import XCTest
@testable import VietTelex

// Hotkey chuyển bộ gõ chỉ-gồm-modifier (17/08/2026, tiếp nối issue #54). Máy nhận
// diện chord là hàm thuần tap-thread — pin đủ các kịch bản nhả/nhầm/ngắt ở đây vì
// sai một ca là hoặc chuyển bộ gõ giữa lúc user bấm shortcut, hoặc hotkey chết im.
final class SwitchHotkeyTests: XCTestCase {

    private let ctrlShift: CGEventFlags = [.maskControl, .maskShift]

    /// Diễn lại một chuỗi flagsChanged, trả về số lần fire.
    private func run(_ states: [CGEventFlags], target: CGEventFlags,
                     interruptAt: Int? = nil) -> Int {
        var r = ModifierChordRecognizer()
        var fires = 0
        for (i, f) in states.enumerated() {
            // Phím thường / click chen giữa: flags lúc đó = modifier đang giữ (trạng thái trước).
            if i == interruptAt { r.disarm(flags: i > 0 ? states[i - 1] : []) }
            if r.note(flags: f, target: target) { fires += 1 }
        }
        return fires
    }

    func testCleanPressAndReleaseFiresOnce() {
        // ⌃ xuống → ⌃⇧ đủ bộ → nhả sạch: đúng MỘT lần fire (lúc nhả).
        XCTAssertEqual(run([[.maskControl], ctrlShift, []], target: ctrlShift), 1)
        // Nhả từng phím một (⌃⇧ → ⇧ → rỗng): vẫn một lần — fire ở bước nhả đầu,
        // các bước sau không armed nữa.
        XCTAssertEqual(run([ctrlShift, [.maskShift], []], target: ctrlShift), 1)
    }

    func testTypingWhileHeldCancels() {
        // ⌃⇧ đang giữ mà gõ phím (disarm chen giữa) rồi nhả → shortcut thật, 0 fire.
        XCTAssertEqual(run([ctrlShift, []], target: ctrlShift, interruptAt: 1), 0)
    }

    func testAddingAThirdModifierCancels() {
        // ⌃⇧ rồi thêm ⌘ (thành chord khác) rồi nhả hết: không fire lần nào —
        // kể cả khi đường nhả có đi ngang qua đúng tổ hợp ⌃⇧.
        XCTAssertEqual(run([ctrlShift, [.maskControl, .maskShift, .maskCommand], []],
                           target: ctrlShift), 0)
        // Nhưng nếu SAU đó user lại bấm ⌃⇧ sạch thì phải fire lại bình thường.
        XCTAssertEqual(run([ctrlShift, [.maskControl, .maskShift, .maskCommand], [],
                            ctrlShift, []], target: ctrlShift), 1)
    }

    /// #114: ⌃⇧⌘4 (chụp màn hình) — nhả ⌘ trước thì đường nhả đi ngang ⌃⇧; phím 4 chen
    /// giữa. Không được chuyển bộ gõ. Lượt ⌃⇧ sạch kế tiếp vẫn phải fire.
    func testScreenshotChordDoesNotToggle() {
        let all: CGEventFlags = [.maskControl, .maskShift, .maskCommand]
        // ⌃ → ⌃⇧ → ⌃⇧⌘ → (4) → nhả ⌘ còn ⌃⇧ → ⇧ → rỗng.
        XCTAssertEqual(run([[.maskControl], ctrlShift, all, ctrlShift, [.maskShift], []],
                           target: ctrlShift, interruptAt: 3), 0)
        // Không có phím 4 chen giữa cũng vậy (⌃⇧⌘ rồi nhả ⌘ trước).
        XCTAssertEqual(run([ctrlShift, all, ctrlShift, []], target: ctrlShift), 0)
        // Bắt đầu bằng ⌘⇧ rồi thêm ⌃ (⌘⇧⌃4) rồi nhả ⌘: không fire.
        XCTAssertEqual(run([[.maskCommand, .maskShift], all, ctrlShift, []], target: ctrlShift), 0)
        // Phím thường chen khi giữ ⌃⇧, nhả ⇧ trước (còn ⌃) rồi bấm lại ⇧: vẫn bẩn tới khi nhả sạch.
        XCTAssertEqual(run([ctrlShift, [.maskControl], ctrlShift, []], target: ctrlShift,
                           interruptAt: 1), 0)
        // Sau đó một lượt ⌃⇧ sạch: fire đúng 1 lần.
        XCTAssertEqual(run([ctrlShift, all, ctrlShift, [], [.maskControl], ctrlShift, []],
                           target: ctrlShift), 1)
    }

    /// #116: gõ chữ / click KHÔNG giữ modifier (rất thường ngay trước khi chuyển bộ gõ) không
    /// được làm bẩn lượt ⌃⇧ kế tiếp — bản 1.8.11 phải bấm 2 lần.
    func testTypingWithoutModifiersDoesNotSpoilNextChord() {
        var r = ModifierChordRecognizer()
        for _ in 0..<5 { r.disarm(flags: []) }            // gõ "xin chao", click…
        var fires = 0
        for f in [[.maskControl], ctrlShift, []] as [CGEventFlags] where r.note(flags: f, target: ctrlShift) { fires += 1 }
        XCTAssertEqual(fires, 1)
        // Phím thường khi ĐANG giữ ⌃⇧ thì vẫn huỷ (shortcut thật, #114).
        r = ModifierChordRecognizer(); fires = 0
        _ = r.note(flags: ctrlShift, target: ctrlShift)
        r.disarm(flags: ctrlShift)
        if r.note(flags: [], target: ctrlShift) { fires += 1 }
        XCTAssertEqual(fires, 0)
        // Và lượt ⌃⇧ sạch ngay sau đó fire.
        for f in [ctrlShift, []] as [CGEventFlags] where r.note(flags: f, target: ctrlShift) { fires += 1 }
        XCTAssertEqual(fires, 1)
    }

    /// Một PHIÊN gõ thật trên CÙNG một recognizer (không tạo mới mỗi kịch bản — lỗ hổng làm
    /// #116 lọt test): gõ chữ, click, ⌃⇧, chụp màn hình ⌃⇧⌘4, ⌘C… xen kẽ. Mỗi ⌃⇧ sạch phải
    /// chuyển đúng 1 lần, mọi tổ hợp khác 0 lần.
    func testRealisticSessionSequence() {
        enum Ev { case key(CGEventFlags), flags(CGEventFlags) }   // key = keyDown/click với flags đang giữ
        let cs = ctrlShift
        let csc: CGEventFlags = [.maskControl, .maskShift, .maskCommand]
        let typing: [Ev] = Array(repeating: .key([]), count: 6)    // "xin chao"
        let toggle: [Ev] = [.flags([.maskControl]), .flags(cs), .flags([.maskShift]), .flags([])]
        let screenshot: [Ev] = [.flags([.maskControl]), .flags(cs), .flags(csc), .key(csc),
                                .flags(cs), .flags([.maskShift]), .flags([])]
        let copy: [Ev] = [.flags([.maskCommand]), .key([.maskCommand]), .flags([])]
        let shiftLetter: [Ev] = [.flags([.maskShift]), .key([.maskShift]), .flags([])]
        let ctrlShiftKey: [Ev] = [.flags(cs), .key(cs), .flags([])]   // ⌃⇧T của app: không chuyển
        let script: [([Ev], Int)] = [
            (typing, 0), (toggle, 1), (typing, 0), (.init(repeating: .key([]), count: 1), 0), // click
            (toggle, 1), (screenshot, 0), (toggle, 1), (copy, 0), (toggle, 1),
            (shiftLetter, 0), (toggle, 1), (ctrlShiftKey, 0), (toggle, 1), (typing, 0), (toggle, 1),
        ]
        var r = ModifierChordRecognizer()
        for (i, (events, expected)) in script.enumerated() {
            var fires = 0
            for e in events {
                switch e {
                case .key(let f): r.disarm(flags: f)
                case .flags(let f): if r.note(flags: f, target: cs) { fires += 1 }
                }
            }
            XCTAssertEqual(fires, expected, "bước \(i)")
        }
    }

    func testWrongComboNeverFires() {
        XCTAssertEqual(run([[.maskCommand, .maskShift], []], target: ctrlShift), 0)
        XCTAssertEqual(run([[.maskShift], []], target: ctrlShift), 0)
    }

    func testIrrelevantFlagsAreIgnored() {
        // Caps Lock / bit device-dependent không được phá so khớp: ⌃⇧ + capsLock
        // đang bật vẫn là ⌃⇧.
        let withCaps: CGEventFlags = [.maskControl, .maskShift, .maskAlphaShift]
        XCTAssertEqual(run([withCaps, [.maskAlphaShift]], target: ctrlShift), 1)
    }

    func testChoiceMapping() {
        XCTAssertEqual(SwitchHotkey.targetFlags(for: "ctrl-shift"), [.maskControl, .maskShift])
        XCTAssertEqual(SwitchHotkey.targetFlags(for: "opt-shift"), [.maskAlternate, .maskShift])
        XCTAssertEqual(SwitchHotkey.targetFlags(for: "cmd-shift"), [.maskCommand, .maskShift])
        XCTAssertNil(SwitchHotkey.targetFlags(for: "off"))
        XCTAssertNil(SwitchHotkey.targetFlags(for: "rác-từ-bản-cũ"))   // không crash, coi như tắt
    }

    func testLastOtherSourceOnlyRemembersNonVietTelex() {
        SwitchHotkey.noteSelection(isVietTelex: false, currentID: "com.apple.keylayout.ABC")
        XCTAssertEqual(SwitchHotkey.lastOtherSourceID, "com.apple.keylayout.ABC")
        // Chọn VietTelex không được ghi đè đích quay-về.
        SwitchHotkey.noteSelection(isVietTelex: true, currentID: "com.viettelex.inputmethod.telex.vi")
        XCTAssertEqual(SwitchHotkey.lastOtherSourceID, "com.apple.keylayout.ABC")
        // nil id (TIS trả lỗi thoáng qua) không xoá mất đích cũ.
        SwitchHotkey.noteSelection(isVietTelex: false, currentID: nil)
        XCTAssertEqual(SwitchHotkey.lastOtherSourceID, "com.apple.keylayout.ABC")
    }

    /// #103: Anh → Việt → (chuyển nhanh) Trung → hotkey về Việt → hotkey phải ra Anh, không
    /// quay lại Trung. Bộ gõ không Latinh không thành đích quay-về.
    func testNonLatinSourceIsNotReturnTarget() {
        SwitchHotkey.noteSelection(isVietTelex: false, currentID: "com.apple.keylayout.US")
        SwitchHotkey.noteSelection(isVietTelex: true, currentID: "com.viettelex.inputmethod.telex.vi")
        SwitchHotkey.noteSelection(isVietTelex: false, currentID: "com.apple.inputmethod.SCIM.ITABC", latin: false)
        SwitchHotkey.noteSelection(isVietTelex: true, currentID: "com.viettelex.inputmethod.telex.vi")
        XCTAssertEqual(SwitchHotkey.lastOtherSourceID, "com.apple.keylayout.US")
    }
}
