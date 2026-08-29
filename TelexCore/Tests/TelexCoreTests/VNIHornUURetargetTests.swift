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
    }
}
