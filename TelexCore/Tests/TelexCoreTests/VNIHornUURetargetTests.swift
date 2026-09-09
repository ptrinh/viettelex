import XCTest
@testable import TelexCore

/// Issue #66 (29/08/2026): VNI "uu7" ra "uư" — mark digit 7 (horn) scan-back đặt
/// lên chữ u CUỐI, thiếu luật "uu nucleus → horn chữ u đầu" mà w-handler Telex đã
/// có từ trước ("luuw"→lưu). Hai bên giờ chung luật, chung ngoại lệ "qu".
final class VNIHornUURetargetTests: XCTestCase {
    private func vni(_ keys: String) -> String {
        var e = TelexEngine()
        e.vniMode = true
        for ch in keys { _ = e.feed(ch) }
        return e.composed
    }

    func testHornOnDoubleUTargetsFirstU() {
        XCTAssertEqual(vni("uu7"), "ưu")      // the reported bug
        XCTAssertEqual(vni("luu7"), "lưu")
        XCTAssertEqual(vni("cuu71"), "cứu")
        XCTAssertEqual(vni("u7u"), "ưu")      // đặt sớm vẫn thế (đã đúng từ trước)
    }

    func testSingleUAndUaUnchanged() {
        XCTAssertEqual(vni("mua7"), "mưa")    // scan-back skips 'a', horns the u
        XCTAssertEqual(vni("tu7"), "tư")
    }

    func testQuGlideExcluded() {
        // "qu" glide: chữ u sau q không phải target horn-retarget (giống Telex).
        XCTAssertEqual(vni("quu7"), "quư")
        XCTAssertEqual(vni("quu77"), "quu7")   // cancel the last-u horn, not retarget
    }

    /// Second 7 undoes ư on the first u (Telex `luuww`→luuw), instead of horning
    /// the leftover u (`lưư`). Cancel must follow the retargeted `target`.
    func testSecondHornCancelsFirstU() {
        XCTAssertEqual(vni("luu77"), "luu7")
        XCTAssertEqual(vni("uu77"), "uu7")
        XCTAssertEqual(vni("cuu775"), "cuu75")  // further digits stay literal
        XCTAssertEqual(vni("tu77"), "tu7")      // single u: cancel still on that u
        XCTAssertEqual(vni("hua77"), "hua7")    // 7 never targets a; second 7 cancels ư
    }
}
