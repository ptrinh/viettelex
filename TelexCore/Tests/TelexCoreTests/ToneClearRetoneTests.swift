import XCTest
@testable import TelexCore

/// Issue #78 (11/09/2026): "tooiszs" ra "tôis" — sau khi z xóa dấu, mọi dấu tiếp
/// theo bị khóa vì z đi chung latch pCancelled với cử chỉ gõ-đúp (ss/ff = "từ này
/// tiếng Anh"). z (và VNI 0) là lệnh XÓA DẤU tường minh: dấu sau đó phải gõ lại
/// được, đúng hợp đồng Unikey/OpenKey. Cử chỉ gõ-đúp giữ nguyên.
final class ToneClearRetoneTests: XCTestCase {
    private func telex(_ keys: String) -> (live: String, commit: String) {
        var e = TelexEngine(); e.liveSpellCheck = true; e.contextualEnglish = true
        for ch in keys { _ = e.feed(ch) }
        return (e.composed, e.commitText(autoRestore: true))
    }
    private func vni(_ keys: String) -> String {
        var e = TelexEngine(); e.vniMode = true
        for ch in keys { _ = e.feed(ch) }
        return e.composed
    }

    func testZClearsThenToneReapplies() {
        XCTAssertEqual(telex("tooiszs").live, "tối")     // the report
        XCTAssertEqual(telex("tooiszs").commit, "tối")
        XCTAssertEqual(telex("tooiszf").live, "tồi")     // a different tone after z
        XCTAssertEqual(telex("tooisz").live, "tôi")      // z alone still clears
        XCTAssertEqual(telex("vieejtzj").live, "việt")
    }

    func testVNIZeroClearsThenToneReapplies() {
        XCTAssertEqual(vni("toi610"), "tôi")
        XCTAssertEqual(vni("toi6101"), "tối")
    }

    func testEnglishDoubleTapGestureUnchanged() {
        // z with no tone to clear stays literal; the ss/ff escape still freezes.
        XCTAssertEqual(telex("pizza").live, "pizza")
        XCTAssertEqual(telex("jazz").live, "jazz")
        XCTAssertEqual(telex("tessted").commit, "tested")
        XCTAssertEqual(telex("hosts").commit, "hosts")
    }

    func testBackspaceRawInvariantAcrossZ() {
        var e = TelexEngine()
        for ch in "tooiszs" { _ = e.feed(ch) }
        XCTAssertEqual(e.composed, "tối")
        while !e.isEmpty {
            _ = e.backspace()
            var f = TelexEngine(); for ch in e.rawKeystrokes { _ = f.feed(ch) }
            XCTAssertEqual(f.composed, e.composed, "raw \"\(e.rawKeystrokes)\" must regenerate composed")
        }
    }
}
