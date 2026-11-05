import XCTest
@testable import TelexCore

/// Issue #149 (05/11/2026, Android): "cấm" + `w` ra "cấmw" thay vì "cắm". Phím dấu mũ /
/// móc / trăng giờ ĐỔI qua lại được trên nguyên âm đã có dấu, dấu thanh
/// giữ nguyên:
///   Telex  â + w → ă · ô + w → ơ (ươ nhờ render khi có u trước, vần đóng)
///          ă + a → â · ơ + o → ô (đã có từ 26/09, ươ → uô)
///   VNI    â + 8 → ă · ă + 6 → â · ô + 7 → ơ · ơ + 6 → ô
/// Gõ lại đúng phím của dấu đang có vẫn là HUỶ như cũ (aaa → aa, aww → aw, a66 → a6).
/// Free marking cho phím đổi vượt phụ âm cuối như mọi phím dấu ("caamw" → căm); strict
/// thì chỉ khi kề nhau. Rủi ro tiếng Anh: "away" → "ây" (âm tiết hợp lệ) — thêm vào
/// englishExceptions để boundary vẫn khôi phục "away"; aware/award/awake/hawaii không
/// hợp lệ nên vẫn tự khôi phục.
final class MarkSwapTests: XCTestCase {

    private func compose(_ keys: String) -> String {
        var e = TelexEngine()
        for ch in keys { _ = e.feed(ch) }
        return e.composed
    }

    private func composeFree(_ keys: String) -> String {
        var e = TelexEngine(); e.freeMarking = true
        for ch in keys { _ = e.feed(ch) }
        return e.composed
    }

    private func vni(_ keys: String) -> String {
        var e = TelexEngine(); e.vniMode = true
        for ch in keys { _ = e.feed(ch) }
        return e.composed
    }

    /// Cấu hình mặc định của app (giống CompetitorReviewTests.commitApp).
    private func commitApp(_ keys: String) -> String {
        var e = TelexEngine()
        e.freeMarking = true; e.liveSpellCheck = true; e.teencode = false
        e.contextualEnglish = true; e.collisionPrefersVietnamese = true
        for ch in keys { _ = e.feed(ch) }
        return e.commitText(autoRestore: true)
    }

    func testIssue149CircumflexPlusWGivesBreve() {
        XCTAssertEqual(composeFree("caasmw"), "cắm")   // the reported sequence: cấm + w
        XCTAssertEqual(composeFree("caamsw"), "cắm")
        XCTAssertEqual(composeFree("caamw"), "căm")
        XCTAssertEqual(composeFree("caamws"), "cắm")
        XCTAssertEqual(compose("caaw"), "că")
        XCTAssertEqual(compose("caasw"), "cắ")
        XCTAssertEqual(commitApp("caasmw"), "cắm")
        XCTAssertEqual(commitApp("Caasmw"), "Cắm")
        XCTAssertEqual(commitApp("CAASMW"), "CẮM")
    }

    func testCircumflexOPlusWGivesHorn() {
        XCTAssertEqual(compose("tooiw"), "tơi")
        XCTAssertEqual(compose("tooiws"), "tới")
        XCTAssertEqual(compose("toosiw"), "tới")
        XCTAssertEqual(composeFree("muoonw"), "mươn")   // uô + w → ươ (render mirrors)
        XCTAssertEqual(composeFree("nguooiwf"), "người")
        XCTAssertEqual(commitApp("tooiw"), "tơi")
        XCTAssertEqual(commitApp("nguooiwf"), "người")
    }

    func testBrevePlusAGivesCircumflex() {
        XCTAssertEqual(compose("cawa"), "câ")
        XCTAssertEqual(compose("cawsa"), "cấ")
        XCTAssertEqual(composeFree("cawma"), "câm")     // reach-back over the coda
        XCTAssertEqual(composeFree("cawsma"), "cấm")
        XCTAssertEqual(commitApp("cawsma"), "cấm")
    }

    func testSwapsChainBackAndForth() {
        XCTAssertEqual(compose("caawa"), "câ")          // â → ă → â
        XCTAssertEqual(compose("cawaw"), "că")          // ă → â → ă
        XCTAssertEqual(compose("toowo"), "tô")          // ô → ơ → ô
    }

    func testStrictModeStillAdjacentOnly() {
        XCTAssertEqual(compose("caamw"), "câmw")        // strict: w never crosses a coda
        XCTAssertEqual(compose("cawma"), "căma")
    }

    func testSameKeyStillCancels() {
        XCTAssertEqual(compose("caaa"), "caa")
        XCTAssertEqual(compose("caww"), "caw")
        XCTAssertEqual(compose("caaww"), "caw")         // â → ă, then ww cancels the breve
        XCTAssertEqual(compose("cooo"), "coo")
    }

    func testEnglishWordsStillRestore() {
        XCTAssertEqual(commitApp("away"), "away")
        XCTAssertEqual(commitApp("Away"), "Away")
        XCTAssertEqual(commitApp("aware"), "aware")
        XCTAssertEqual(commitApp("award"), "award")
        XCTAssertEqual(commitApp("awake"), "awake")
        XCTAssertEqual(commitApp("hawaii"), "hawaii")
        XCTAssertEqual(commitApp("ottawa"), "ottawa")
        XCTAssertEqual(commitApp("awareness"), "awareness")
        XCTAssertEqual(commitApp("kawasaki"), "kawasaki")
    }

    func testVNISwapsHats() {
        XCTAssertEqual(vni("ca61m8"), "cắm")
        XCTAssertEqual(vni("ca81m6"), "cấm")
        XCTAssertEqual(vni("ca68"), "că")
        XCTAssertEqual(vni("ca86"), "câ")
        XCTAssertEqual(vni("to6i7"), "tơi")
        XCTAssertEqual(vni("to7i6"), "tôi")
        XCTAssertEqual(vni("muo6n7"), "mươn")
        XCTAssertEqual(vni("luo7n6"), "luôn")           // ươ + 6 → uô
        XCTAssertEqual(vni("ca66"), "ca6")              // same digit still cancels
        XCTAssertEqual(vni("ca88"), "ca8")
        XCTAssertEqual(vni("d99"), "d9")
    }
}
