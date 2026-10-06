// Ưu tiên phím ở mép chung (KeyHitBias, Phil 06/10/2026) — song sinh Android HitBiasTest.kt.
//  1. space thắng "," / "." kề trong dải 30% (gõ cuộn < 150 ms sau chữ: 40%);
//  2. chữ thắng ⇧ / ⌫ kề trong dải 20% (gõ nhanh < 200 ms: 35%); tâm phím luôn của nó;
//  3. Caps Lock tắt khi rời plane chữ (123 / emoji), về ABC vẫn đánh giá lại viết hoa đầu câu.
import XCTest
import UIKit

final class KeyHitBiasTests: XCTestCase {
    private typealias B = KeyHitBias

    // Hàng đáy iPhone 402pt: space 98…304, khe 6, "," 310…340 (30 rộng), cao 43.
    private let space = CGRect(x: 98, y: 162, width: 206, height: 43)
    private let comma = CGRect(x: 310, y: 162, width: 30, height: 43)

    func testBandTables() {
        XCTAssertEqual(B.spaceBand(sinceLetter: nil), 0.30)
        XCTAssertEqual(B.spaceBand(sinceLetter: 0.10), 0.40)
        XCTAssertEqual(B.spaceBand(sinceLetter: 0.15), 0.30)      // hết cửa sổ cuộn
        XCTAssertEqual(B.spaceBand(sinceLetter: -1), 0.30)
        XCTAssertEqual(B.letterBand(sinceLetter: nil), 0.20)
        XCTAssertEqual(B.letterBand(sinceLetter: 0.199), 0.35)
        XCTAssertEqual(B.letterBand(sinceLetter: 0.20), 0.20)
        // Dải luôn < nửa phím ⇒ tâm phím thua không bao giờ bị cướp.
        for b in [B.spaceBand, B.spaceBandRolling, B.letterBand, B.letterBandRolling] { XCTAssertLessThan(b, 0.5) }
    }

    func testSpaceWinsNearCommaBoundary() {
        let y = comma.midY
        // (x, since, space thắng?)
        let table: [(CGFloat, TimeInterval?, Bool)] = [
            (307, nil, true),            // khe
            (310.5, nil, true),          // sát mép ","
            (318.9, nil, true),          // 29.7% bề rộng ","
            (319.1, nil, false),         // 30.3%
            (321, nil, false),
            (321, 0.10, true),           // gõ cuộn: dải 40% = 12pt
            (322.1, 0.10, false),
            (321, 0.30, false),          // gõ chậm
            (comma.midX, nil, false),    // tâm ","
            (comma.midX, 0.05, false),
            (comma.maxX - 1, 0.05, false),
        ]
        for (x, since, want) in table {
            let got = B.intrudes(CGPoint(x: x, y: y), loser: comma, winner: space,
                                 band: B.spaceBand(sinceLetter: since))
            XCTAssertEqual(got, want, "x=\(x) since=\(String(describing: since))")
        }
        // Đối xứng: "." BÊN TRÁI space (Android plane số [,][😊][space][.]) — chiều ngược.
        let dot = CGRect(x: 62, y: 162, width: 30, height: 43)
        XCTAssertTrue(B.intrudes(CGPoint(x: 85, y: y), loser: dot, winner: space, band: 0.3))
        XCTAssertFalse(B.intrudes(CGPoint(x: dot.midX, y: y), loser: dot, winner: space, band: 0.3))
        // Không kề (cách xa) ⇒ không bao giờ.
        let far = CGRect(x: 360, y: 162, width: 30, height: 43)
        XCTAssertFalse(B.intrudes(CGPoint(x: 361, y: y), loser: far, winner: space, band: 0.45))
    }

    func testLettersWinNearShiftAndBackspace() {
        // Hàng 3 iPhone 402: ⇧ 6.5…49 (42.5), khe 12, z 61…94; ⌫ 353…395.5, m 308…341.
        // Hàng 2: a 26.3…59.5, đáy 98; ⇧ đỉnh 108.
        let shift = CGRect(x: 6.5, y: 108, width: 42.5, height: 43)
        let back = CGRect(x: 353, y: 108, width: 42.5, height: 43)
        let z = CGRect(x: 61, y: 108, width: 33.3, height: 43)
        let m = CGRect(x: 308, y: 108, width: 33.3, height: 43)
        let a = CGRect(x: 26.3, y: 54, width: 33.3, height: 44)
        let letters = [a, z, m]
        let y = shift.midY
        // (điểm, phím thua, since, phím thắng mong đợi: nil = giữ ⇧/⌫)
        let table: [(CGPoint, CGRect, TimeInterval?, Int?)] = [
            (CGPoint(x: 48, y: y), shift, nil, 1),           // sát mép phải ⇧ → z
            (CGPoint(x: 41, y: y), shift, nil, 1),           // 18% → z
            (CGPoint(x: 39, y: y), shift, nil, nil),         // 23% → ⇧
            (CGPoint(x: 39, y: y), shift, 0.1, 1),           // gõ nhanh: 35%
            (CGPoint(x: 33, y: y), shift, 0.1, nil),         // 37% → ⇧
            (CGPoint(x: shift.midX, y: y), shift, 0.05, nil), // tâm ⇧ luôn ⇧
            (CGPoint(x: 20, y: y), shift, 0.05, nil),        // mép trái ⇧
            (CGPoint(x: 40, y: 110), shift, nil, 0),         // đỉnh ⇧ dưới a → a
            (CGPoint(x: 40, y: 118), shift, nil, nil),       // 23% chiều cao → ⇧
            (CGPoint(x: 15, y: 110), shift, nil, nil),       // đỉnh ⇧ nhưng ngoài khoảng x của a
            (CGPoint(x: 354, y: back.midY), back, nil, 2),   // sát mép trái ⌫ → m
            (CGPoint(x: 362, y: back.midY), back, nil, nil), // 21% → ⌫
            (CGPoint(x: 362, y: back.midY), back, 0.1, 2),
            (CGPoint(x: back.midX, y: back.midY), back, 0.1, nil),
        ]
        for (p, loser, since, want) in table {
            let got = B.stealer(p, loser: loser, winners: letters, band: B.letterBand(sinceLetter: since))
            XCTAssertEqual(got, want, "p=\(p) since=\(String(describing: since))")
        }
    }

    // MARK: KeyboardView thật (iPhone 402pt) — đường hitTest / router

    @MainActor private func makeKeyboard(onKey: @escaping (KeyboardView.Key) -> Void = { _ in })
        -> (KeyboardView, UIView) {
        let kb = KeyboardView(needsGlobe: false, inputController: nil, onKey: onKey)
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 402, height: 212))
        host.addSubview(kb)
        kb.frame = host.bounds
        kb.configureInputKind(.normal)
        kb.layoutIfNeeded()
        host.frame.size.height = kb.debugRequestedHeight; kb.frame = host.bounds
        kb.layoutIfNeeded()
        return (kb, host)
    }

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    @MainActor func testSpaceBarStealsCommaEdgeInKeyboard() throws {
        try XCTSkipIf(isPad)
        let (kb, host) = makeKeyboard()
        _ = host
        let space = try XCTUnwrap(kb.debugControl("Dấu cách"))
        let comma = try XCTUnwrap(kb.debugKeyButton(","))
        let cf = kb.convert(comma.bounds, from: comma), sf = kb.convert(space.bounds, from: space)
        // Hình phím: "," hẹp (0.071 W), space nhận phần dư; tâm space/"," vẫn là chính nó.
        XCTAssertEqual(cf.width, 402 * KeyLayout.phoneLettersComma, accuracy: 1)
        XCTAssertTrue(kb.hitTest(CGPoint(x: sf.midX, y: sf.midY), with: nil) === space)
        XCTAssertTrue(kb.hitTest(CGPoint(x: cf.midX, y: cf.midY), with: nil) === comma)
        XCTAssertTrue(kb.hitTest(CGPoint(x: cf.minX + 0.2 * cf.width, y: cf.midY), with: nil) === space)
        XCTAssertTrue(kb.hitTest(CGPoint(x: cf.minX - 1, y: cf.midY), with: nil) === space, "khe")
        XCTAssertTrue(kb.hitTest(CGPoint(x: cf.minX + 0.4 * cf.width, y: cf.midY), with: nil) === comma)
    }

    @MainActor func testLettersStealShiftAndBackspaceEdges() throws {
        try XCTSkipIf(isPad)
        var typed: [Character] = []
        let (kb, host) = makeKeyboard { if case .letter(let c) = $0 { typed.append(c) } }
        _ = host
        let shift = try XCTUnwrap(kb.debugControl("Shift"))
        let back = try XCTUnwrap(kb.debugControl("Xoá"))
        let sf = kb.convert(shift.bounds, from: shift), bf = kb.convert(back.bounds, from: back)
        XCTAssertTrue(kb.hitTest(CGPoint(x: sf.midX, y: sf.midY), with: nil) === shift, "tâm ⇧")
        XCTAssertTrue(kb.hitTest(CGPoint(x: bf.midX, y: bf.midY), with: nil) === back, "tâm ⌫")
        let nearZ = CGPoint(x: sf.maxX - 0.1 * sf.width, y: sf.midY)
        let nearM = CGPoint(x: bf.minX + 0.1 * bf.width, y: bf.midY)
        XCTAssertTrue(kb.hitTest(nearZ, with: nil) === kb, "mép ⇧ sát z → router chữ")
        XCTAssertTrue(kb.hitTest(nearM, with: nil) === kb, "mép ⌫ sát m → router chữ")
        // Router ra đúng chữ kề (kể cả khi ngoài tầm 21pt của phím chữ gần nhất).
        kb.debugTouch(from: nearZ, through: [], start: 100)
        kb.debugTouch(from: nearM, through: [], start: 101)
        XCTAssertEqual(typed.map { Character($0.lowercased()) }, ["z", "m"])
    }

    // MARK: Caps Lock tắt khi đổi plane

    func testPolicyClearsShiftOnlyForSymbolAndEmojiPlanes() {
        XCTAssertTrue(PlanePolicy.clearsShiftLeavingLetters(to: .symbols))
        XCTAssertTrue(PlanePolicy.clearsShiftLeavingLetters(to: .emoji))
        XCTAssertTrue(PlanePolicy.clearsShiftLeavingLetters(to: .emojiSearch))
        XCTAssertFalse(PlanePolicy.clearsShiftLeavingLetters(to: .templates))
        XCTAssertFalse(PlanePolicy.clearsShiftLeavingLetters(to: .letters))
    }

    @MainActor private func capsLock(_ kb: KeyboardView) throws {
        let shift = try XCTUnwrap(kb.debugControl("Shift"))
        kb.setAutoShift(false)
        shift.sendActions(for: .touchDown)
        try XCTUnwrap(kb.debugControl("Shift")).sendActions(for: .touchDown)   // chạm đôi
        XCTAssertTrue(kb.debugShiftCaps)
    }

    @MainActor func testCapsLockOffAfter123RoundTrip() throws {
        let (kb, host) = makeKeyboard()
        _ = host
        try capsLock(kb)
        kb.autoShiftProbe = { false }                                 // giữa câu
        try XCTUnwrap(kb.debugControl("Số")).sendActions(for: .touchDown)
        XCTAssertEqual(kb.debugPlaneName, "numbers")
        XCTAssertFalse(kb.debugShiftOn)
        try XCTUnwrap(kb.debugControl("Chữ")).sendActions(for: .touchDown)
        XCTAssertEqual(kb.debugPlaneName, "letters")
        XCTAssertFalse(kb.debugShiftCaps, "Caps Lock phải tắt sau 123 → ABC")
        XCTAssertFalse(kb.debugShiftOn)
    }

    @MainActor func testCapsLockRoundTripStillAutoCapitalizes() throws {
        let (kb, host) = makeKeyboard()
        _ = host
        try capsLock(kb)
        kb.autoShiftProbe = { true }                                  // đầu câu
        try XCTUnwrap(kb.debugControl("Số")).sendActions(for: .touchDown)
        try XCTUnwrap(kb.debugControl("Chữ")).sendActions(for: .touchDown)
        XCTAssertFalse(kb.debugShiftCaps)
        XCTAssertTrue(kb.debugShiftOn, "về ABC đầu câu: shift một-lần")
    }

    @MainActor func testOneShotShiftClearedByEmojiAndReevaluatedOnABC() throws {
        let (kb, host) = makeKeyboard()
        _ = host
        kb.setAutoShift(true)
        XCTAssertTrue(kb.debugShiftOn)
        kb.debugShowEmojiPlane()
        XCTAssertFalse(kb.debugShiftOn)
        kb.autoShiftProbe = { true }
        kb.debugEmojiABC()
        XCTAssertEqual(kb.debugPlaneName, "letters")
        XCTAssertTrue(kb.debugShiftOn)
    }
}
