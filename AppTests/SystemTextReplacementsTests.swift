import XCTest
@testable import VietTelex

/// Issue #117 (1.8.11, macOS 27, Lark): gõ tắt VietTelex "h" → "giờ" trùng Text
/// Replacements của macOS "h" → "giờ"; gõ "h␣" ra "giờiờ" (log: tap-emit bs=1 ins=3
/// rồi bs=0 ins=1 — mình nở một lần, macOS nở thêm vào range cũ của "h"). Video 2: "H"
/// → bong bóng "GIỜ" (macOS khớp không phân biệt hoa thường).
final class SystemTextReplacementsTests: XCTestCase {

    // Đúng dạng `defaults read -g NSUserDictionaryReplacementItems`.
    private let items: [Any] = [
        ["on": 1, "replace": "h", "with": "giờ"],
        ["on": 1, "replace": "omw", "with": "On my way!"],
        ["on": 0, "replace": "ko", "with": "không"],              // tắt ⇒ bỏ
        ["replace": "Vn", "with": "Việt Nam"],                    // không có "on" ⇒ bật
        ["on": 1, "replace": "", "with": "x"],                    // rỗng ⇒ bỏ
        "rác",
    ]

    func testParseKeepsEnabledEntriesLowercased() {
        let t = SystemTextReplacements.parse(items)
        XCTAssertEqual(t, ["h": "giờ", "omw": "On my way!", "vn": "Việt Nam"])
        XCTAssertEqual(SystemTextReplacements.parse(nil), [:])
    }

    func testConflictsListSharedKeysCaseInsensitive() {
        let sys = SystemTextReplacements.parse(items)
        let ours = ["h": "giờ", "VN": "Việt Nam!", "ko": "không", "->": "→"]
        let c = SystemTextReplacements.conflicts(ours: ours, system: sys)
        XCTAssertEqual(c.map(\.key), ["VN", "h"])
        XCTAssertTrue(c[1].sameExpansion)
        XCTAssertFalse(c[0].sameExpansion)                         // khác nội dung vẫn là trùng
        XCTAssertEqual(SystemTextReplacements.conflicts(ours: ours, system: [:]), [])
    }

    /// Reporter tắt CẢ HAI khoá ⇒ hết lỗi. Chỉ coi là tắt khi cả hai tắt hẳn; chưa đặt = bật.
    func testSubstitutionEnabledOnlyOffWhenBothOff() {
        XCTAssertTrue(SystemTextReplacements.substitutionEnabled(web: nil, appKit: nil))
        XCTAssertTrue(SystemTextReplacements.substitutionEnabled(web: false, appKit: nil))
        XCTAssertTrue(SystemTextReplacements.substitutionEnabled(web: nil, appKit: false))
        XCTAssertTrue(SystemTextReplacements.substitutionEnabled(web: true, appKit: false))
        XCTAssertFalse(SystemTextReplacements.substitutionEnabled(web: false, appKit: false))
    }

    /// Bố cục Contents/Frameworks đo trên máy 06/10/2026.
    func testChromiumFamilyDetection() {
        let helpers: Set<String> = ["Google Chrome Framework.framework", "Lark Framework.framework"]
        func fam(_ f: [String]) -> Bool {
            SystemTextReplacements.isChromiumFamily(frameworks: f) { helpers.contains($0) }
        }
        XCTAssertTrue(fam(["Google Chrome Framework.framework"]))            // Chrome
        XCTAssertTrue(fam(["Lark Framework.framework", "Notification.app"])) // LarkSuite
        XCTAssertTrue(fam(["Electron Framework.framework", "Squirrel.framework"])) // Slack…
        XCTAssertTrue(fam(["Chromium Embedded Framework.framework"]))        // Spotify (CEF)
        XCTAssertFalse(fam(["TextFramework.framework"]))                     // không có " Framework"
        XCTAssertFalse(fam(["Other Framework.framework"]))                   // không có Helpers
        XCTAssertFalse(fam([]))                                              // app Cocoa thuần
    }

    func testDeferOnlyForSystemKeyInSubstitutingApp() {
        let sys = SystemTextReplacements.parse(items)
        // #117: "h␣" ở Lark ⇒ để macOS nở, VietTelex không nở.
        XCTAssertTrue(SystemTextReplacements.shouldDefer(onScreen: "h", systemKeys: sys, appSubstitutes: true))
        XCTAssertTrue(SystemTextReplacements.shouldDefer(onScreen: "H", systemKeys: sys, appSubstitutes: true))
        // App không áp thay thế macOS (Terminal, Office, Firefox, hoặc đã tắt) ⇒ VietTelex nở.
        XCTAssertFalse(SystemTextReplacements.shouldDefer(onScreen: "h", systemKeys: sys, appSubstitutes: false))
        // Khoá chỉ có bên VietTelex ⇒ nở như cũ.
        XCTAssertFalse(SystemTextReplacements.shouldDefer(onScreen: "ko", systemKeys: sys, appSubstitutes: true))
        XCTAssertFalse(SystemTextReplacements.shouldDefer(onScreen: "", systemKeys: sys, appSubstitutes: true))
        XCTAssertFalse(SystemTextReplacements.shouldDefer(onScreen: "h", systemKeys: [:], appSubstitutes: true))
    }
}
