import XCTest
@testable import TelexCore

// Từ trùng theo tần suất + lật lại (TelexEngine.englishByFrequency, THỬ NGHIỆM) và "một từ Anh
// mạnh chốt mạch" của sửa ngược (RetroEnglish.plan). Cùng ca ở android/telexcore
// FrequencyEnglishTest.kt và windows/engine/tests/retro_tests.cpp.

private func appEngine(retro: Bool = true, frequency: Bool = true, teencode: Bool = false) -> TelexEngine {
    var e = TelexEngine()
    e.freeMarking = true
    e.liveSpellCheck = true
    e.eagerEnglishRestore = true
    e.teencode = teencode
    e.contextualEnglish = true
    e.collisionPrefersVietnamese = true
    e.retroactiveEnglish = retro
    e.englishByFrequency = frequency
    return e
}

/// Gõ như controller: chữ → feed; ký tự khác → commitText, (áp phép sửa đang chờ nếu `auto` hoặc
/// là phép LẬT LẠI — luôn tự áp), chèn ký tự, báo noteBoundaryCharacter. "\n" = Enter: chỉ phép
/// lật lại được áp, TRƯỚC khi Enter đi. Hết chuỗi = như Enter.
private func type(_ keys: String, _ e: inout TelexEngine, auto: Bool, flips: inout Int) -> String {
    var screen: [Unicode.Scalar] = []
    func apply(enter: Bool) {
        guard let c = e.pendingRetroCorrection, c.flipBack || (auto && !enter) else { return }
        let tail = String(String.UnicodeScalarView(screen.suffix(c.backspaces)))
        XCTAssertEqual(tail, c.expected, "expected-text mismatch in \(keys)")
        guard tail == c.expected else { return }
        _ = e.takeRetroCorrection()
        screen.removeLast(c.backspaces)
        screen.append(contentsOf: c.insert.unicodeScalars)
        if c.flipBack { flips += 1 }
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

private func typed(_ keys: String, retro: Bool = true, frequency: Bool = true, auto: Bool = false,
                   teencode: Bool = false) -> String {
    var e = appEngine(retro: retro, frequency: frequency, teencode: teencode)
    var n = 0
    return type(keys, &e, auto: auto, flips: &n)
}

final class FrequencyEnglishTests: XCTestCase {

    // MARK: Bảng

    private func scores(_ w: String) -> (en: UInt8, vn: UInt8)? {
        var w = w
        return w.withUTF8 { EnglishFrequency.scores($0, count: $0.count) }
    }

    private func pair(_ p: String) -> Bool {
        var p = p
        return p.withUTF8 { EnglishFrequency.hasPair($0, count: $0.count) }
    }

    func testTableLookups() {
        let his = scores("his")
        XCTAssertNotNil(his)
        XCTAssertGreaterThan(his!.vn, 0)                         // hí
        XCTAssertGreaterThan(Int(his!.en), Int(his!.vn) + 45)    // his ≫ hí
        XCTAssertEqual(scores("very")?.vn, 0)                    // mạnh: không đọc ra âm tiết Việt
        XCTAssertEqual(scores("fast")?.vn, 0)
        XCTAssertGreaterThanOrEqual(scores("fast")!.en, EnglishFrequency.strongMin)
        XCTAssertNil(scores("zzzz"))
        XCTAssertNil(scores(""))
        XCTAssertTrue(pair("his>huwngr"))                        // hí hửng
        XCTAssertTrue(pair("last>nuwax"))                        // lát nữa
        XCTAssertTrue(pair("this>sinh"))                         // thí sinh
        XCTAssertFalse(pair("his>car"))
        XCTAssertFalse(pair("his>huwng"))
        XCTAssertTrue(RetroEnglish.isStrongRaw("fast"))
        XCTAssertFalse(RetroEnglish.isStrongRaw("his"))
    }

    // MARK: Một từ Anh mạnh chốt mạch (sửa ngược, không cần cờ tần suất)

    func testStrongWordCompletesRun() {
        XCTAssertEqual(typed("His car is fast.", frequency: false, auto: true), "His car is fast.")
        XCTAssertEqual(typed("His car is fast.", frequency: false, auto: false), "Hí cả í fast.")
        // Bắn sớm hơn một từ: ngay ở "very".
        var e = appEngine(frequency: false)
        for k in ["His", "car", "is"] {
            for ch in k { _ = e.feed(ch) }
            _ = e.commitText(autoRestore: true)
            e.noteBoundaryCharacter(" ")
            XCTAssertNil(e.pendingRetroCorrection)
        }
        for ch in "very" { _ = e.feed(ch) }
        _ = e.commitText(autoRestore: true)
        XCTAssertEqual(e.pendingRetroCorrection?.insert, "is car is very")
        XCTAssertEqual(e.pendingRetroCorrection?.flipBack, false)
    }

    func testStrongWordNeedsTwoPicksAndAnchor() {
        // Một ứng viên thôi thì không đủ: "Mai cả team họp", "làm cả review code".
        for keys in ["Mai car team hopj", "lamf car review code", "Guwir file cho car nhaf",
                     "car team meeting", "is fast"] {
            XCTAssertEqual(typed(keys, frequency: false, auto: true), typed(keys, retro: false, frequency: false), keys)
        }
        XCTAssertEqual(typed("is fast", frequency: false, auto: true), "í fast")
    }

    // MARK: Luật tần suất

    func testFrequencyRuleRestoresSentenceInitialEnglish() {
        XCTAssertEqual(typed("His car is fast.", auto: true), "His car is fast.")
        XCTAssertEqual(typed("His dog is cute.", auto: false), "His dog is cute.")
        XCTAssertEqual(typed("Is it ok?", auto: false), "Is it ok?")
        XCTAssertEqual(typed("How are you?", auto: false), "How are you?")
        // Sau dấu chấm câu mới: "Tôi đi. His dog is cute."
        XCTAssertEqual(typed("Tooi ddi. His dog is cute.", auto: false), "Tôi đi. His dog is cute.")
    }

    /// RetroEnglishTests.testKnownLimits' "His car is here now" (no English run without the flag).
    func testHereNowWithFrequencyRule() {
        XCTAssertEqual(typed("His car is here now.", auto: true), "His car is here now.")
        XCTAssertEqual(typed("His car is here now.", auto: false), "His cả is here now.")
        XCTAssertEqual(typed("His car is here now.", frequency: false, auto: true), "Hí cả í hể nơ.")
    }

    func testFrequencyRuleNeedsNoVietnameseOnTheLeft() {
        XCTAssertEqual(typed("sao is"), "sao í")
        XCTAssertEqual(typed("em is aj"), "em í ạ")
        XCTAssertEqual(typed("cho con bus"), "cho con bú")
        XCTAssertEqual(typed("thawts now"), "thắt nơ")
        XCTAssertEqual(typed("cais now ddor"), "cái nơ đỏ")
    }

    func testCommonVietnameseSyllablesStay() {
        XCTAssertEqual(typed("its nhaats"), "ít nhất")
        XCTAssertEqual(typed("Its nhaats laf vaayj"), "Ít nhất là vậy")
        XCTAssertEqual(typed("Mai car team hopj"), "Mai cả team họp")
        XCTAssertEqual(typed("Car nhaf owi"), "Cả nhà ơi")
        XCTAssertEqual(typed("been treen"), "bên trên")
    }

    // MARK: Lật lại

    func testFlipBackOnVietnamesePair() {
        XCTAssertEqual(typed("his huwngr"), "hí hửng")
        XCTAssertEqual(typed("His huwngr quas"), "Hí hửng quá")
        XCTAssertEqual(typed("last nuwax goij laij nhes"), "lát nữa gọi lại nhé")
        XCTAssertEqual(typed("Last nuwax anh veef"), "Lát nữa anh về")
        XCTAssertEqual(typed("This sinh ddeens muoonj"), "Thí sinh đến muộn")
        XCTAssertEqual(typed("his huwngr\n"), "hí hửng\n")             // Enter: lật trước khi gửi
    }

    func testFlipBackOnReduplication() {
        XCTAssertEqual(typed("his his"), "hí hí")
        XCTAssertEqual(typed("His His"), "Hí Hí")
        XCTAssertEqual(typed("his his his vui ghee"), "hí hí hí vui ghê")
        XCTAssertEqual(typed("Hif hif"), "Hì hì")
        XCTAssertEqual(typed("hows hows"), "hớ hớ")
        XCTAssertEqual(typed("How how"), "Hơ hơ")
        XCTAssertEqual(typed("uwf uwf"), "ừ ừ")
        // Lặp qua một từ Việt (tiếng cười "hí ha hí hửng").
        XCTAssertEqual(typed("His ha his huwngr"), "Hí ha hí hửng")
    }

    func testFlipCorrectionShape() {
        var e = appEngine()
        for ch in "His" { _ = e.feed(ch) }
        XCTAssertEqual(e.commitText(autoRestore: true), "His")
        e.noteBoundaryCharacter(" ")
        XCTAssertNil(e.pendingRetroCorrection)
        for ch in "huwngr" { _ = e.feed(ch) }
        XCTAssertEqual(e.commitText(autoRestore: true), "hửng")
        XCTAssertEqual(e.pendingRetroCorrection,
                       RetroCorrection(backspaces: 7, expected: "is hửng", insert: "í hửng", words: 1, flipBack: true))
        e.noteBoundaryCharacter(" ")
        XCTAssertEqual(e.takeRetroCorrection()?.insert, "í hửng ")
        // Lịch sử ghi lại chữ Việt: không bị đổi sang Anh lần nữa.
        XCTAssertEqual(e.debugRetroHistory.first?.shown, "Hí")
        XCTAssertEqual(e.debugRetroHistory.first?.english, false)
    }

    /// Không lật lại khi từ kế là tiếng Anh, hay tiếng Việt không có bằng chứng cặp ("Test xong").
    func testNoFlipWithoutEvidence() {
        XCTAssertEqual(typed("Test xong roofi nhes"), "Test xong rồi nhé")
        XCTAssertEqual(typed("His car"), "His cả")
    }

    // MARK: Cổng

    func testInertWhenOffOrWithoutRetro() {
        let corpus = ["His car is fast.", "his huwngr", "His His", "sao is", "Test xong roofi nhes",
                      "Is it ok?", "last nuwax"]
        for k in corpus {
            XCTAssertEqual(typed(k, frequency: false), typed(k, retro: true, frequency: false), k)
            // Cần sửa ngược đang chạy: không có nó thì cờ tần suất trơ.
            XCTAssertEqual(typed(k, retro: false, frequency: true), typed(k, retro: false, frequency: false), k)
        }
        var e = appEngine(retro: false)
        XCTAssertFalse(e.englishByFrequencyActive)
        e.retroactiveEnglish = true
        XCTAssertTrue(e.englishByFrequencyActive)
        e.vniMode = true
        XCTAssertFalse(e.englishByFrequencyActive)
    }

    /// Teencode bật: tần suất Việt đếm trên corpus đã chuẩn hoá teencode ⇒ luật tắt.
    func testTeencodeDisablesFrequencyRule() {
        XCTAssertEqual(typed("bits gofi khoor lawms", teencode: true), "bít gòi khổ lắm")
    }
}
