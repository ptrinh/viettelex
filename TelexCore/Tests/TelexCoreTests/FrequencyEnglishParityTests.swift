import XCTest
@testable import TelexCore

// Fixture đối chiếu 3 port cho "một từ Anh mạnh" (sửa ngược) + "Từ trùng theo tần suất" (lật lại):
// iOS/KeyboardTests/Fixtures/frequency-english-parity.txt — Swift GHI (VT_RECORD_PARITY=1), Kotlin
// (android/telexcore FrequencyEnglishTest.kt) và C++ (windows/engine/tests/retro_tests.cpp) ĐỌC
// lại, gõ cùng phím, phải ra y hệt. Swift cũng tự kiểm (file đã commit = engine hiện tại).
//
// Dòng: <phím>\t<retro tự áp>\t<retro chỉ mời + tần suất>\t<retro tự áp + tần suất>
// Cách gõ (mọi port giống hệt): chữ cái → feed; ký tự khác → commitText(autoRestore: true), áp
// phép sửa đang chờ nếu (tự áp và ký tự không phải "\n") hoặc là phép LẬT LẠI, chèn ký tự, báo
// noteBoundaryCharacter. Hết chuỗi: commitText rồi áp như một "\n". Áp = kiểm `expected` là
// đuôi màn hình rồi takeRetroCorrection.
// Nguồn phím: cột phím của retro-english-eval.txt (Tatoeba CC BY 2.0 FR + tự soạn) — chỉ giữ dòng
// mà một trong ba cột khác bản tắt tính năng, cộng 1/8 số dòng còn lại (ca âm) — và các ca tay dưới.

private let manualCases = [
    "His car is fast.", "His car is very fast", "his huwngr", "His huwngr quas", "his his",
    "His His", "his his his vui ghee", "Hif hif", "How how", "His ha his huwngr", "last nuwax",
    "Last nuwax anh veef", "This sinh ddeens muoonj", "sao is", "em is aj", "cho con bus",
    "thawts now", "cais now ddor", "its nhaats", "Mai car team hopj", "been treen",
    "Test xong roofi nhes", "Is it ok?", "How are you?", "Tooi ddi. His dog is cute.",
    "his huwngr\nHis car is fast.\n", "He is here.", "the bus", "here now", "His car is here now.",
]

func parityType(_ keys: String, auto: Bool, frequency: Bool) -> String {
    var e = TelexEngine()
    e.freeMarking = true
    e.liveSpellCheck = true
    e.eagerEnglishRestore = true
    e.teencode = false
    e.contextualEnglish = true
    e.collisionPrefersVietnamese = true
    e.retroactiveEnglish = true
    e.englishByFrequency = frequency
    var screen: [Unicode.Scalar] = []
    func apply(enter: Bool) {
        guard let c = e.pendingRetroCorrection, c.flipBack || (auto && !enter) else { return }
        let tail = String(String.UnicodeScalarView(screen.suffix(c.backspaces)))
        guard tail == c.expected else { return }
        _ = e.takeRetroCorrection()
        screen.removeLast(c.backspaces)
        screen.append(contentsOf: c.insert.unicodeScalars)
    }
    for ch in keys {
        if ch.isASCII, ch.isLetter {
            _ = e.feed(ch)
        } else {
            screen += e.commitText(autoRestore: true).unicodeScalars
            apply(enter: ch == "\n")
            screen += String(ch).unicodeScalars
            e.noteBoundaryCharacter(ch)
        }
    }
    screen += e.commitText(autoRestore: true).unicodeScalars
    apply(enter: true)
    return String(String.UnicodeScalarView(screen))
}

final class FrequencyEnglishParityTests: XCTestCase {
    private var fixtures: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("iOS/KeyboardTests/Fixtures")
    }

    private func esc(_ s: String) -> String { s.replacingOccurrences(of: "\n", with: "\\n") }

    func testParityFixtureMatchesEngine() throws {
        let eval = try String(contentsOf: fixtures.appendingPathComponent("retro-english-eval.txt"), encoding: .utf8)
        var keys: [String] = []
        var n = 0
        var lines: [String] = []
        for l in eval.split(separator: "\n") where !l.hasPrefix("#") {
            let p = l.split(separator: "\t", omittingEmptySubsequences: false)
            guard p.count == 3 else { continue }
            keys.append(String(p[1]))
        }
        keys += manualCases
        for k in keys {
            let off = parityType(k, auto: false, frequency: false)
            let a = parityType(k, auto: true, frequency: false)
            let b = parityType(k, auto: false, frequency: true)
            let c = parityType(k, auto: true, frequency: true)
            n += 1
            let manual = manualCases.contains(k)
            guard manual || a != off || b != off || c != off || n % 8 == 0 else { continue }
            lines.append([esc(k), esc(a), esc(b), esc(c)].joined(separator: "\t"))
        }
        let header = "# frequency-english-parity v1 — SINH bởi TelexCoreTests/FrequencyEnglishParityTests.swift "
            + "(VT_RECORD_PARITY=1 swift test --filter FrequencyEnglishParity). <phím>\\t<retro tự áp>\\t"
            + "<retro mời + tần suất>\\t<retro tự áp + tần suất>; \\n = Enter. Phím: retro-english-eval.txt "
            + "(câu Tatoeba CC BY 2.0 FR, https://tatoeba.org + tự soạn MIT) + ca tay."
        let text = ([header] + lines).joined(separator: "\n") + "\n"
        let url = fixtures.appendingPathComponent("frequency-english-parity.txt")
        if ProcessInfo.processInfo.environment["VT_RECORD_PARITY"] != nil {
            try text.write(to: url, atomically: true, encoding: .utf8)
            print("PARITY wrote \(lines.count) lines → \(url.path)")
            return
        }
        let committed = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(committed, text, "fixture lệch engine — chạy VT_RECORD_PARITY=1 rồi xem diff")
        XCTAssertGreaterThan(lines.count, 500)
    }
}
