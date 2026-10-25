import XCTest
@testable import TelexCore

/// ⌫ trong từ bị đóng băng vì phím dấu thanh VIẾT HOA giữa từ chữ thường.
///
/// Phím dấu thanh hoa sau một chữ thường ("VieeJ", "OmS", "SaaS") là tín hiệu
/// English/code: cả từ đóng băng về phím thô và các phím sau gõ thẳng ("VieeJt").
/// Lỗi cũ: ⌫ dựng lại từ mà không nhớ lý do đóng băng đó (parse đóng băng coi mọi
/// phím là chữ thô nên cờ upper-tone đọc ra false), màn hình nhảy: "VieeJt" ⌫ →
/// "Việ", "uxuJxwl" ⌫ → "ữu". Cùng gốc: phép gỡ đóng băng kéo dài ("VieeJ"+tt)
/// cũng gỡ nhầm đóng băng upper-tone ("Việtt").
///
/// Bất biến: khi phím cuối được chèn thẳng (màn hình = màn hình của các phím trước
/// + phím đó), ⌫ phải cho đúng màn hình gõ lại các phím trừ phím cuối trên engine
/// mới cùng thiết lập. (Khi phím cuối biến đổi chữ, ⌫ xoá cả chữ hiển thị — "khoo"
/// ⌫ → "kh" — nên bất biến chỉ áp cho phím chèn thẳng.)
final class UpperToneBackspaceTests: XCTestCase {

    private func type(_ s: String, _ e: inout TelexEngine) {
        for ch in s { _ = e.feed(ch) }
    }

    // Single-line asserts below are ported to Kotlin/C++ by
    // android/telexcore/scripts/port-swift-tests.py — keep helper configs in sync.

    /// Free marking + live spell-check, then one ⌫.
    private func bs(_ keys: String) -> String {
        var e = TelexEngine(); e.freeMarking = true; e.liveSpellCheck = true
        type(keys, &e); _ = e.backspace()
        return e.composed
    }

    /// Free marking, live spell-check OFF, then one ⌫.
    private func bsNoSpell(_ keys: String) -> String {
        var e = TelexEngine(); e.freeMarking = true
        type(keys, &e); _ = e.backspace()
        return e.composed
    }

    /// Simple Telex + live spell-check, then one ⌫.
    private func bsSimple(_ keys: String) -> String {
        var e = TelexEngine(); e.liveSpellCheck = true; e.simpleTelex = true
        type(keys, &e); _ = e.backspace()
        return e.composed
    }

    /// Free marking + live spell-check, screen only.
    private func screen(_ keys: String) -> String {
        var e = TelexEngine(); e.freeMarking = true; e.liveSpellCheck = true
        type(keys, &e)
        return e.composed
    }

    func testUpperToneFreezeSurvivesBackspace() {
        XCTAssertEqual(screen("VieeJt"), "VieeJt")
        XCTAssertEqual(bs("VieeJt"), "VieeJ")
        XCTAssertEqual(screen("uxuJxwl"), "uxuJxwl")
        XCTAssertEqual(bs("uxuJxwl"), "uxuJxw")
        XCTAssertEqual(bs("SaaSa"), "SaaS")
        XCTAssertEqual(bs("OmSs"), "OmS")
        XCTAssertEqual(bsNoSpell("VieeJt"), "VieeJ")
        XCTAssertEqual(bsNoSpell("uxuJxwl"), "uxuJxw")
        XCTAssertEqual(bsNoSpell("SaaSa"), "SaaS")
    }

    func testUpperToneKeyLastStillDeletesIt() {
        XCTAssertEqual(bs("ToiJ"), "Toi")
        XCTAssertEqual(bs("VieetJ"), "Viêt")
        XCTAssertEqual(bs("DduowcJ"), "Đươc")
        XCTAssertEqual(bsNoSpell("ToiJ"), "Toi")
        XCTAssertEqual(bsNoSpell("VieetJ"), "Viêt")
    }

    /// The elongation unfreeze ("quafaaaa" → "quàaaa") must not lift an upper-tone
    /// freeze, and ⌫ replays it only on the key forward typing fires it on.
    func testElongationUnfreezeAndUpperTone() {
        XCTAssertEqual(screen("VieeJtt"), "VieeJtt")
        XCTAssertEqual(bs("VieeJtt"), "VieeJt")
        XCTAssertEqual(screen("quafaaaa"), "quàaaa")
        XCTAssertEqual(bs("YnnnSc"), "YnnnS")
        XCTAssertEqual(bsSimple("ASUUuz"), "ASUUu")
    }

    /// Property: for deterministic pseudo-random mixed-case words, every prefix whose
    /// last key was inserted literally deletes back to exactly the screen of retyping
    /// without that key — across live spell-check / free marking / Simple Telex /
    /// teencode combinations, and in VNI.
    func testBackspaceEqualsRetypeWithoutLastKey() {
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> UInt64 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return seed >> 33
        }
        func engine(_ cfg: Int) -> TelexEngine {
            var e = TelexEngine()
            e.liveSpellCheck = cfg & 1 != 0
            e.freeMarking = cfg & 2 != 0
            e.simpleTelex = cfg & 4 != 0
            e.teencode = cfg & 8 != 0
            e.vniMode = cfg & 16 != 0
            return e
        }
        let telexKeys = Array("aeiouydwsfrxjzntcghl")
        let vniKeys = Array("aeiouydntcgh1234567890")
        var checked = 0
        for cfg in 0..<32 {
            let keys = cfg & 16 != 0 ? vniKeys : telexKeys
            for _ in 0..<600 {
                var word: [Character] = []
                for _ in 0..<(3 + Int(next() % 6)) {
                    var c = keys[Int(next() % UInt64(keys.count))]
                    if next() % 3 == 0 { c = Character(c.uppercased()) }
                    word.append(c)
                }
                // Always include the two reported sequences in the first config pass.
                if checked == 0 { word = Array("uxuJxwl") }
                for n in 2...word.count {
                    let prefix = String(word[0..<(n - 1)])
                    var e = engine(cfg); type(prefix + String(word[n - 1]), &e)
                    var f = engine(cfg); type(prefix, &f)
                    guard e.composed == f.composed + String(word[n - 1]) else { continue }
                    checked += 1
                    _ = e.backspace()
                    XCTAssertEqual(e.composed, f.composed, "cfg=\(cfg) keys=\(prefix)\(word[n - 1]) ⌫")
                }
            }
        }
        for keys in ["VieeJt", "uxuJxwl"] {
            for cfg in 0..<16 {
                var e = engine(cfg); type(keys, &e); _ = e.backspace()
                var f = engine(cfg); type(String(keys.dropLast()), &f)
                XCTAssertEqual(e.composed, f.composed, "cfg=\(cfg) keys=\(keys) ⌫")
            }
        }
        XCTAssertGreaterThan(checked, 20_000)
    }
}
