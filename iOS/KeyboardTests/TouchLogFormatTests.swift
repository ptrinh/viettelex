// Log Debug mode (TouchLog): header đủ bối cảnh, gộp dòng lặp "×N", cắt file giữ header,
// và không bao giờ mang nội dung gõ tắt (chỉ đếm).
import XCTest

final class TouchLogFormatTests: XCTestCase {
    private func context() -> TouchLogFormat.Context {
        var c = TouchLogFormat.Context()
        c.version = "1.2.31"; c.build = "52"; c.os = "iOS 26.1"; c.device = "iPhone17,3"; c.idiom = "phone"
        c.install = "testflight"; c.locale = "vi_VN"; c.keyboards = ["vi", "en-US"]; c.fullAccess = true
        c.uiLanguage = "vi"
        return c
    }

    func testHeaderHasContextAndSettings() {
        var s = KeyboardSettings()
        s.vniMode = true
        var a = TouchLogFormat.Appearance()
        a.theme = "sakura"; a.effect = "heart"
        let h = TouchLogFormat.header(context(), settings: s, appearance: a)
        XCTAssertEqual(h[0], "=== VietTelex iOS 1.2.31 (52) keyboard debug log")
        XCTAssertEqual(h[1], "device: iPhone17,3 phone · iOS 26.1 · install testflight")
        XCTAssertEqual(h[2], "locale: vi_VN · ui vi · keyboards: vi,en-US")
        XCTAssertEqual(h[3], "access: fullAccess=1")
        XCTAssertTrue(h[4].hasPrefix("typing: method=vni "))
        XCTAssertTrue(h.contains { $0.hasPrefix("ui: theme=sakura effect=heart ") })
        s.vniMode = false; s.simpleTelex = false
        XCTAssertTrue(TouchLogFormat.header(context(), settings: s, appearance: a)[4].hasPrefix("typing: method=telex "))
    }

    func testHeaderCountsShortcutsNeverContent() {
        var s = KeyboardSettings()
        s.shortcuts = ShortcutTable(["vn": "Việt Nam bí mật"])
        let text = TouchLogFormat.header(context(), settings: s, appearance: .init()).joined(separator: "\n")
        XCTAssertTrue(text.contains("shortcuts: on:1 "))
        XCTAssertFalse(text.contains("Việt Nam"))
    }

    func testCollapserFoldsRepeats() {
        var c = TouchLogFormat.Collapser()
        XCTAssertEqual(c.push("a"), ["a"])
        XCTAssertEqual(c.push("a"), [])
        XCTAssertEqual(c.push("a"), [])
        XCTAssertEqual(c.push("b"), ["  ×3", "b"])
        XCTAssertEqual(c.push("c"), ["c"])
        XCTAssertEqual(c.flush(), [])
        XCTAssertEqual(c.push("c"), [])
        XCTAssertEqual(c.flush(), ["  ×2"])
        XCTAssertEqual(c.push("c"), ["c"], "sau flush là chuỗi mới")
    }

    func testTrimKeepsNewestLinesBehindHeader() {
        let body = (1...100).map { "10:00:00.000 line \($0)" }.joined(separator: "\n") + "\n"
        let out = String(decoding: TouchLogFormat.trimmed(Data(body.utf8), keep: 200, header: ["=== H1", "h2"]),
                         as: UTF8.self)
        let lines = out.split(separator: "\n").map(String.init)
        XCTAssertEqual(Array(lines.prefix(3)), ["=== H1", "h2", "… (older lines trimmed)"])
        XCTAssertEqual(lines.last, "10:00:00.000 line 100")
        // Cắt ở đầu dòng: không có mảnh dòng dở.
        XCTAssertTrue(lines.dropFirst(3).allSatisfy { $0.hasPrefix("10:00:00.000 line ") })
        XCTAssertLessThan(out.utf8.count, 260)
    }

    func testTrimSmallFileKeepsEverything() {
        let out = String(decoding: TouchLogFormat.trimmed(Data("a\nb\n".utf8), keep: 1000, header: []), as: UTF8.self)
        XCTAssertEqual(out, "… (older lines trimmed)\na\nb\n")
    }
}
