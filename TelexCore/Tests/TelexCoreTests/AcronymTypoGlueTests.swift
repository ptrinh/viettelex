import XCTest
@testable import TelexCore

// 30/10/2026: ALL-CAPS acronyms, Vietnamese one-slip typos, words glued to a code
// separator / a number, and the ⌫ undo record of a boundary restore. Engine-level; the
// Kotlin and C++ ports match through the golden corpus (GenGolden "acronyms…" block).
final class AcronymTypoGlueTests: XCTestCase {

    /// Controller-like replay: letters compose, anything else commits the word, is
    /// inserted, then reported with `noteBoundaryCharacter` (the platform contract).
    private func type(_ keys: String, free: Bool = false, live: Bool = true,
                      context: Bool = false, retro: Bool = false) -> String {
        var e = TelexEngine()
        e.liveSpellCheck = live; e.freeMarking = free
        e.contextualEnglish = context; e.retroactiveEnglish = retro
        var out = ""
        for ch in keys {
            if let a = ch.asciiValue, isLetter(a) { _ = e.feed(ch); continue }
            out += e.commitText(autoRestore: true)
            out.append(ch)
            e.noteBoundaryCharacter(ch)
            if let c = e.takeRetroCorrection() { out = String(out.dropLast(c.backspaces)) + c.insert }
        }
        return out + e.commitText(autoRestore: true)
    }

    // MARK: A. ALL-CAPS acronyms

    func testRareAllCapsSyllableIsAnAcronym() {
        for (k, want) in [("NAS", "NAS"), ("OS", "OS"), ("AWS", "AWS"), ("SAS", "SAS"), ("RAS", "RAS"),
                          ("TOAS", "TOAS"), ("IFS", "IFS")] {
            XCTAssertEqual(type(k), want, k)
            XCTAssertEqual(type(k, free: true), want, k + " (free marking)")
        }
    }

    func testCommonAllCapsVietnameseStays() {
        XCTAssertEqual(type("VIEEJT NAM"), "VIỆT NAM")
        XCTAssertEqual(type("DDAF NAWXNG"), "ĐÀ NẴNG")
        XCTAssertEqual(type("HDDND"), "HĐND")
        XCTAssertEqual(type("VNDD"), "VNĐ")
        XCTAssertEqual(type("CONG HOAF XAX HOOIJ CHUR NGHIAX"), "CONG HÒA XÃ HỘI CHỦ NGHĨA")
        XCTAssertEqual(type("DDOOCJ LAAPJ TUWJ DO HANHJ PHUSC"), "ĐỘC LẬP TỰ DO HẠNH PHÚC")
        XCTAssertEqual(type("QUYEETS DDINHJ TOWF TRINHF"), "QUYẾT ĐỊNH TỜ TRÌNH")
        XCTAssertEqual(type("NHOOM GUWNFG BUWOWRI"), "NHÔM GỪNG BƯỞI")
        XCTAssertEqual(type("COS"), "CÓ")
    }

    func testDoublerLettersCountOnceAndMidWordToneIsSpelling() {
        XCTAssertEqual(type("AA"), "Â")           // one letter, not an acronym
        XCTAssertEqual(type("DDA"), "ĐA")
        XCTAssertEqual(type("DAJA"), "DẠA")       // tone key mid-word: chat elongation, not an acronym
        XCTAssertEqual(type("Nas"), "Ná")         // one capital: ordinary word
    }

    func testModernTonePlacementReadsTheSameTable() {
        var e = TelexEngine(); e.modernTone = true
        for ch in "HOAF" { _ = e.feed(ch) }
        XCTAssertEqual(e.commitText(autoRestore: true), "HOÀ")
    }

    func testAcronymNeverFlipsThePreviousWord() {
        XCTAssertEqual(type("bene ASL", free: true, context: true, retro: true), "bên ASL")
        XCTAssertEqual(type("bene NAS API", free: true, context: true, retro: true), "bên NAS API")
        XCTAssertEqual(type("cas ASL USB", context: true, retro: true), "cá ASL USB")
        var e = TelexEngine(); e.contextualEnglish = true
        for w in ["ASL", "USB"] {
            for ch in w { _ = e.feed(ch) }
            _ = e.commitBoundary(autoRestore: true)
        }
        XCTAssertFalse(e.previousWordEnglish, "acronyms are neutral: they never open an English run")
    }

    // MARK: B. Vietnamese one-slip typo vs English

    func testOneSlipVietnameseTypoKeepsTheScreen() {
        XCTAssertEqual(type("lanwm", free: true), "lănm")
        XCTAssertEqual(type("tieengsm"), "tiếngm")
        XCTAssertEqual(type("tieengsm", free: true), "tiếngm")
    }

    func testEnglishShapesStillRestore() {
        for w in ["deepseek", "teamwork", "keep", "deep", "meet", "root", "loop", "wal", "wan",
                  "casual", "tester", "school", "google", "seed", "good"] {
            XCTAssertEqual(type(w), w, w)
            XCTAssertEqual(type(w, free: true), w, w + " (free marking)")
        }
        XCTAssertEqual(type("lanwm"), "lanwm")      // strict Telex: "lanưm" has two vowel groups
        XCTAssertEqual(type("PhuwowngT"), "PhuwowngT")  // a capital after lowercase is no slip
    }

    // MARK: C. Glued separators and digits

    func testCodeSeparatorGlue() {
        XCTAssertEqual(type("my_var"), "my_var")
        XCTAssertEqual(type("x_y_bas"), "x_y_bas")
        XCTAssertEqual(type("self.bar"), "self.bar")
        XCTAssertEqual(type("user/repo"), "user/repo")
        XCTAssertEqual(type("ok.ddi"), "ok.đi")             // a typed mark stays
        XCTAssertEqual(type("haha.thooi"), "haha.thôi")
    }

    func testVietnameseSeparatorsKeepComposing() {
        XCTAssertEqual(type("vaf/hoawcj"), "và/hoặc")
        XCTAssertEqual(type("anh/chij"), "anh/chị")
        XCTAssertEqual(type("chij/anh"), "chị/anh")
        XCTAssertEqual(type("TP.Hoof"), "TP.Hồ")
        XCTAssertEqual(type("Uwf...thooi"), "Ừ...thôi")
        XCTAssertEqual(type("ddi. Mai"), "đi. Mai")
        XCTAssertEqual(type("xong. vaf"), "xong. và")
    }

    func testDigitGlue() {
        XCTAssertEqual(type("100W"), "100W")
        XCTAssertEqual(type("1w"), "1w")
        XCTAssertEqual(type("10kW"), "10kW")
        XCTAssertEqual(type("4G"), "4G")
        XCTAssertEqual(type("5s"), "5s")
        XCTAssertEqual(type("5trawm"), "5trăm")
        XCTAssertEqual(type("2tieengs"), "2tiếng")
        XCTAssertEqual(type("100dd"), "100đ")
        XCTAssertEqual(type("5tuw"), "5tư")
        XCTAssertEqual(type("1 W"), "1 Ư")                  // a space ends the glue
    }

    func testGlueNeedsTheBoundaryReport() {
        // Without noteBoundaryCharacter the engine knows nothing about the separator.
        var e = TelexEngine()
        for ch in "my" { _ = e.feed(ch) }
        _ = e.commitBoundary(autoRestore: true)
        for ch in "var" { _ = e.feed(ch) }
        XCTAssertEqual(e.commitText(autoRestore: true), "vả")
    }

    func testResetDropsTheGlue() {
        var e = TelexEngine()
        _ = e.commitBoundary(autoRestore: true)
        e.noteBoundaryCharacter("_")
        e.reset()
        for ch in "var" { _ = e.feed(ch) }
        XCTAssertEqual(e.commitText(autoRestore: true), "vả")
    }

    // MARK: D. ⌫ undo record of a boundary restore

    func testRestoreUndoRecord() {
        var e = TelexEngine(); e.liveSpellCheck = true
        for ch in "NAS" { _ = e.feed(ch) }
        XCTAssertEqual(e.commitBoundary(autoRestore: true), .replace(backspaces: 1, insert: "AS"))
        XCTAssertEqual(e.pendingRestoreUndo, RestoreUndo(restored: "NAS", vietnamese: "NÁ"))
        e.noteBoundaryCharacter(" ")                         // reporting the boundary keeps it
        XCTAssertEqual(e.takeRestoreUndo(), RestoreUndo(restored: "NAS", vietnamese: "NÁ"))
        XCTAssertNil(e.takeRestoreUndo(), "taking consumes it")
    }

    func testRestoreUndoOnlyForARealVietnameseAlternative() {
        func record(_ w: String, autoRestore: Bool = true, setup: (inout TelexEngine) -> Void = { _ in }) -> RestoreUndo? {
            var e = TelexEngine(); e.liveSpellCheck = true; setup(&e)
            for ch in w { _ = e.feed(ch) }
            _ = e.commitBoundary(autoRestore: autoRestore)
            return e.takeRestoreUndo()
        }
        XCTAssertNil(record("google"))                       // "gôgle" is no syllable
        XCTAssertNil(record("vieetj"))                       // nothing restored
        XCTAssertNil(record("NAS", autoRestore: false))
        XCTAssertNil(record("iss"))                          // deliberate cancel: kept
        XCTAssertEqual(record("is") { $0.contextualEnglish = true; _ = $0.feed("h"); _ = $0.feed("e")
                                      _ = $0.commitBoundary(autoRestore: true) },
                       RestoreUndo(restored: "is", vietnamese: "í"))
        var g = TelexEngine()
        _ = g.commitBoundary(autoRestore: true)
        g.noteBoundaryCharacter("_")
        for ch in "var" { _ = g.feed(ch) }
        _ = g.commitBoundary(autoRestore: true)
        XCTAssertNil(g.takeRestoreUndo(), "code glue: a ⌫ there is editing, not undo")
    }

    func testAnyOtherCallDropsTheRecord() {
        let drops: [(String, (inout TelexEngine) -> Void)] = [
            ("feed", { _ = $0.feed("a") }),
            ("backspace", { _ = $0.backspace() }),
            ("commit", { _ = $0.commitBoundary(autoRestore: true) }),
            ("commitText", { _ = $0.commitText(autoRestore: true) }),
            ("reset", { $0.reset() }),
            ("forget", { $0.forgetLastCommit() }),
        ]
        for (name, op) in drops {
            var e = TelexEngine()
            for ch in "NAS" { _ = e.feed(ch) }
            _ = e.commitBoundary(autoRestore: true)
            op(&e)
            XCTAssertNil(e.pendingRestoreUndo, name)
        }
    }

    func testUndoAppliedEndsTheEnglishRun() {
        var e = TelexEngine(); e.contextualEnglish = true
        for w in ["the", "is"] {
            for ch in w { _ = e.feed(ch) }
            _ = e.commitBoundary(autoRestore: true)
        }
        XCTAssertNotNil(e.takeRestoreUndo())
        XCTAssertTrue(e.previousWordEnglish)
        e.restoreUndoApplied()
        XCTAssertFalse(e.previousWordEnglish)
        XCTAssertFalse(e.canReopenLastCommit)
        XCTAssertTrue(e.isEmpty)
    }

    func testCommitTextPathRecordsToo() {
        var e = TelexEngine()
        for ch in "NAS" { _ = e.feed(ch) }
        XCTAssertEqual(e.commitText(autoRestore: true), "NAS")
        XCTAssertEqual(e.takeRestoreUndo(), RestoreUndo(restored: "NAS", vietnamese: "NÁ"))
    }

    func testCommonSyllableTableIsSortedAndDecodable() {
        XCTAssertGreaterThan(CommonSyllables.count, 3000)
        var key: [UInt8] = Array("vieetj".utf8)
        XCTAssertTrue(key.withUnsafeMutableBufferPointer { CommonSyllables.contains($0, count: 6) })
        key = Array("nas".utf8)
        XCTAssertFalse(key.withUnsafeMutableBufferPointer { CommonSyllables.contains($0, count: 3) })
    }
}
