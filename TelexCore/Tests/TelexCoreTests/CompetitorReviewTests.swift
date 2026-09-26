import XCTest
@testable import TelexCore

/// Regression từ review người dùng của bàn phím tiếng Việt KHÁC (Laban, SwiftKey,
/// Gboard, "Telex Keyboard") — các chuỗi họ gõ hỏng (research 26/09/2026, mục 7).
/// Mục tiêu: chắc VietTelex không mắc cùng lỗi, hoặc ghi rõ khi hành vi khác là do
/// CHÍNH SÁCH đã quyết của repo (không đổi engine để chiều review).
///
/// Cấu hình = DEFAULT CỦA APP (AppState.init): freeMarking ON, liveSpellCheck ON,
/// teencode OFF, contextualEnglish ON, collisionPrefersVietnamese ON, modernTone OFF,
/// autoRestore ON. Harness giống controller thật: chữ cái → feed, ký tự khác (`.`,
/// space) → commitBoundary rồi in ký tự đó; `<` = ⌫. Màn hình mô phỏng áp đúng
/// TelexAction, nên kiểm được cả chữ HIỆN giữa chừng lẫn chữ chốt cuối.
final class CompetitorReviewTests: XCTestCase {

    private static func appDefault(_ e: inout TelexEngine) {
        e.freeMarking = true
        e.liveSpellCheck = true
        e.teencode = false
        e.contextualEnglish = true
        e.collisionPrefersVietnamese = true
        e.modernTone = false
    }

    /// Gõ `keys` (`<` = ⌫, không phải chữ cái = boundary), chốt từ cuối, trả về màn
    /// hình cuối + từng bước.
    private func type(_ keys: String,
                      config: (inout TelexEngine) -> Void = CompetitorReviewTests.appDefault)
        -> (screen: String, steps: [String], engine: TelexEngine) {
        var e = TelexEngine(); config(&e)
        var s: [Character] = []
        var steps: [String] = []
        func apply(_ a: TelexAction, _ c: Character?) {
            switch a {
            case .passthrough:
                if let c { s.append(c) } else if !s.isEmpty { s.removeLast() }
            case .replace(let bs, let ins):
                precondition(bs <= s.count)
                s.removeLast(bs); s.append(contentsOf: ins)
            case .none: break
            }
        }
        for ch in keys {
            if ch == "<" {
                apply(e.backspace(), nil)
            } else if ch.isLetter {
                apply(e.feed(ch), ch)
            } else {
                apply(e.commitBoundary(autoRestore: true), nil)
                s.append(ch)
            }
            steps.append(String(s))
        }
        apply(e.commitBoundary(autoRestore: true), nil)
        return (String(s), steps, e)
    }

    private func out(_ keys: String) -> String { type(keys).screen }

    // MARK: - Link / ô tìm kiếm

    /// Review: "now.vn" thành "nơ.vn". VietTelex CŨNG ra "nơ.vn" — CHÍNH SÁCH, không
    /// phải lỗi: `nơ` nằm trong protect-list của gen-english (now ≡ cách gõ Telex chuẩn
    /// của từ Việt thật "nơ" → tiếng Việt thắng, xem docs/REGRESSION.md "Protect-list"),
    /// và POLICY V3 mặc định ưu tiên tiếng Việt khi trùng. Engine không biết đang ở ô
    /// URL. Đường thoát hai chiều: gõ đúp `noww` → "now".
    func testNowDotVnFollowsProtectListPolicy() {
        XCTAssertEqual(out("now.vn"), "nơ.vn", "protect-list: now ≡ nơ, tiếng Việt thắng")
        XCTAssertEqual(out("noww.vn"), "now.vn", "escape gõ đúp w phải cho ra link đúng")
        XCTAssertEqual(out("noww"), "now")
    }

    /// Review: "cheese.co" thành "cheé.co". VietTelex không ra "cheé" nhưng ở cấu hình
    /// mặc định lại ra "chese" (MẤT một chữ e) — LỖI THẬT, xem báo cáo trong commit.
    /// Nguyên nhân: `chees` → chế; `e` thứ ba huỷ mũ (cancel mark kề nhau TRONG letter
    /// space) → "chée" không còn là prefix hợp lệ → liveSpellCheck freeze + pFoldTones
    /// gập phím `s` về chữ thường → "chese". Ở boundary shouldRestoreRaw(): markCancelled,
    /// toneCancelAt == -1 (mark doubler) và composedHasDiacritic() == false (tone đã bị
    /// gập) → coi như escape cố ý kiểu "gooogle" → giữ "chese". Chỉ freeMarking hoặc chỉ
    /// liveSpellCheck thì đều restore đúng "cheese".
    func testCheeseDotCoKnownBug() {
        // Không mắc lỗi của review: không bao giờ chốt "cheé".
        XCTAssertFalse(out("cheese.co").contains("é"))
        // Từng cờ riêng lẻ thì đúng.
        XCTAssertEqual(type("cheese", config: { $0.freeMarking = true }).screen, "cheese")
        XCTAssertEqual(type("cheese", config: { $0.liveSpellCheck = true }).screen, "cheese")
        XCTExpectFailure("BUG: freeMarking+liveSpellCheck (default app) chốt 'chese' — tone bị fold làm mất tín hiệu composedHasDiacritic") {
            XCTAssertEqual(out("cheese.co"), "cheese.co")
            XCTAssertEqual(out("cheese"), "cheese")
            XCTAssertEqual(out("geese"), "geese")
            XCTAssertEqual(out("cheeses"), "cheeses")
        }
    }

    // MARK: - Từ tiếng Anh

    /// Review: "search" thành "sẻach". Với liveSpellCheck (default) chữ không bao giờ
    /// mang dấu, kể cả giữa chừng.
    func testSearchNeverShowsDiacritic() {
        let r = type("search")
        XCTAssertEqual(r.screen, "search")
        XCTAssertEqual(r.steps, ["s", "se", "sea", "sear", "searc", "search"])
    }

    /// Review: "Huawei" thành "Hưawei". Chốt ra "Huawei". Giữa chừng màn hình có
    /// hiện "Hưaei" (w đã thành móc trước khi từ hỏng — dấu đã đặt giữ tới boundary,
    /// thiết kế của liveSpellCheck: "cosmetic until boundary restore").
    func testHuaweiRestoresAtBoundary() {
        XCTAssertEqual(out("Huawei"), "Huawei")
        XCTAssertEqual(out("huawei"), "huawei")
        XCTAssertEqual(out("Huawei.com"), "Huawei.com")
    }

    /// `casse` → "case": ss là gõ đúp GIỮA từ, "casse" không có trong bảng English →
    /// giữ cái màn hình hiện (escape).
    func testCasseKeepsCase() {
        XCTAssertEqual(out("casse"), "case")
    }

    /// Review: "kaspersky" bỏ dấu lung tung. Chốt đúng nguyên văn; từ phím `e` trở đi
    /// không còn dấu nào (freeze).
    func testKasperskyRestores() {
        let r = type("kaspersky")
        XCTAssertEqual(r.screen, "kaspersky")
        XCTAssertEqual(Array(r.steps[4...]), ["kaspe", "kasper", "kaspers", "kaspersk", "kaspersky"])
        XCTAssertEqual(out("Kaspersky"), "Kaspersky")
    }

    /// `uaww`/`uawww`: CHÍNH SÁCH PR#75 (10/09/2026) — w thứ hai trên vần ưa HUỶ ư
    /// (huaww→huaw) chứ không breve chữ a còn lại; mỗi w thêm là một chữ w.
    func testUawwFollowsPR75() {
        XCTAssertEqual(out("uaww"), "uaw")
        XCTAssertEqual(out("uawww"), "uaww")
        XCTAssertEqual(out("huaww"), "huaw")
    }

    // MARK: - Tiếng Việt

    func testUotCapitalized() {
        XCTAssertEqual(out("Uwowts"), "Ướt")
        XCTAssertEqual(out("Uwowst"), "Ướt")
        XCTAssertEqual(out("Uwots"), "Ướt")
        XCTAssertEqual(out("UWOWTS"), "ƯỚT")
    }

    func testOiCapitalized() {
        XCTAssertEqual(out("Owif"), "Ời")
        XCTAssertEqual(out("Owis"), "Ới")
    }

    /// Bỏ dấu tự do (freeMarking, default app ON): đ / móc / thanh gõ ở cuối vẫn về đúng.
    func testFreeMarkingLateMarks() {
        XCTAssertEqual(out("dduocwj"), "được")
        XCTAssertEqual(out("duocdwj"), "được")
        XCTAssertEqual(out("daud"), "đau")
        XCTAssertEqual(out("roio"), "rôi")
        // Setting: freeMarking OFF (Minimal Telex) thì các dạng này giữ nguyên phím.
        XCTAssertEqual(type("daud", config: { _ in }).screen, "daud")
        XCTAssertEqual(type("roio", config: { _ in }).screen, "roio")
    }

    /// `xoas` phụ thuộc setting modernTone (Chính tả kiểu mới).
    func testXoasFollowsModernTone() {
        XCTAssertEqual(out("xoas"), "xóa")
        XCTAssertEqual(type("xoas", config: { e in
            CompetitorReviewTests.appDefault(&e); e.modernTone = true
        }).screen, "xoá")
    }

    /// Review: "cửu" thành "cuử". Thanh phải nằm trên ư dù gõ trước hay sau u cuối.
    func testCuuTonePlacement() {
        XCTAssertEqual(out("cuwru"), "cửu")
        XCTAssertEqual(out("cuwur"), "cửu")
    }

    /// `ưo` + chữ tiếp theo → ươ (móc lan sang o). Riêng "ưo" đứng một mình không là
    /// âm tiết → khôi phục phím gốc.
    func testUoPropagatesHorn() {
        XCTAssertEqual(out("muwon"), "mươn")
        XCTAssertEqual(out("tuwoi"), "tươi")
        XCTAssertEqual(out("dduwocj"), "được")
        XCTAssertEqual(out("huwowu"), "hươu")
        let r = type("tuwoi")
        XCTAssertEqual(r.steps, ["t", "tu", "tư", "tưo", "tươi"])
    }

    /// Review: "lươn" + `o` → "luôn" (đổi móc thành mũ, kiểu UniKey). VietTelex CHƯA
    /// hỗ trợ — THIẾU TÍNH NĂNG, xem báo cáo trong commit. Hiện: màn hình "lươno", chốt
    /// raw "luwowno". Nguyên nhân: nhánh circumflex doubler (a/e/o) trong parseStep
    /// chỉ nhắm nguyên âm cùng base có mark == .none (hoặc .circumflex để huỷ), cả nhánh
    /// kề nhau lẫn reach-back freeMarking; chữ ơ (.horn) bị bỏ qua nên `o` thành chữ
    /// thường, không có retarget ơ→ô kèm ư→u.
    func testLuonRetargetKnownGap() {
        XCTAssertEqual(out("luwown"), "lươn")
        XCTExpectFailure("GAP: 'o' trên ươ chưa đổi thành uô (UniKey làm được)") {
            XCTAssertEqual(out("luwowno"), "luôn")
        }
    }

    // MARK: - ⌫ trên từ tiếng Anh đã khôi phục

    /// Review: xoá lùi trên từ tiếng Anh vừa được khôi phục thì dấu hiện lại. Ở
    /// VietTelex từ đã restore về raw KHÔNG được chụp để re-open (captureReopen bỏ qua
    /// khi restored) → ⌫ xoá ký tự như thường, từ giữ nguyên tiếng Anh.
    func testBackspaceAfterRestoredWordKeepsEnglish() {
        for (keys, expect) in [("Huawei <", "Huawei"), ("Huawei <<", "Huawe"),
                               ("kaspersky <", "kaspersky"), ("kaspersky <<", "kaspersk")] {
            XCTAssertEqual(out(keys), expect, keys)
        }
        var e = TelexEngine(); CompetitorReviewTests.appDefault(&e)
        for ch in "Huawei" { _ = e.feed(ch) }
        XCTAssertEqual(e.commitBoundary(autoRestore: true), .replace(backspaces: 4, insert: "uawei"))  // "Hưaei" → giữ H
        XCTAssertFalse(e.canReopenLastCommit, "từ đã restore không được re-open")
        XCTAssertNil(e.reopenLastCommit())
        // ⌫ trong lúc gõ từ đã freeze: không tái áp dấu lên phần đuôi.
        XCTAssertEqual(out("search<"), "searc")
        XCTAssertEqual(out("kaspersky<"), "kaspersk")
    }
}
