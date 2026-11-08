import XCTest
import AVFoundation

/// Âm thanh phím riêng (28/09/2026): TẮT ⇒ click hệ thống như cũ; BẬT ⇒ KeySound, không kêu đôi.
final class KeySoundTests: XCTestCase {
    override func tearDown() {
        KeyboardView.customSoundEnabled = false
        KeyboardView.pianoEnabled = false
        KeyboardView.pianoPedal = PianoPedal()
        KeyboardView.debugLastClickRoute = nil
        // Việc nền còn xếp hàng (dựng nốt ngân sau pedal ~MB, restart sau config change) không được
        // tràn sang test sau — từng làm playPiano của test sau trượt lock và đo heap UserLM lệch.
        KeySound.shared.debugDrain()
        super.tearDown()
    }

    func testSettingDefaultsAndClamp() {
        let s = KeyboardSettings()
        XCTAssertFalse(s.keySound)
        XCTAssertEqual(s.keySoundVolume, 50)
        let d = UserDefaults(suiteName: "vt-keysound-test")!
        d.removePersistentDomain(forName: "vt-keysound-test")
        d.set(true, forKey: "keySound")
        d.set(250, forKey: "keySoundVolume")
        let saved = UserDefaultsProvider.shared
        UserDefaultsProvider.shared = d
        defer { UserDefaultsProvider.shared = saved; d.removePersistentDomain(forName: "vt-keysound-test") }
        var l = KeyboardSettings.load()
        XCTAssertTrue(l.keySound)
        XCTAssertEqual(l.keySoundVolume, 100)
        d.set(-5, forKey: "keySoundVolume")
        l = KeyboardSettings.load()
        XCTAssertEqual(l.keySoundVolume, 0)
    }

    func testGainCurve() {
        XCTAssertEqual(KeySoundSynth.gain(forPercent: 0), 0)
        XCTAssertEqual(KeySoundSynth.gain(forPercent: 50), 0.25, accuracy: 1e-6)
        XCTAssertEqual(KeySoundSynth.gain(forPercent: 100), 1)
        XCTAssertEqual(KeySoundSynth.gain(forPercent: 300), 1)
    }

    /// TẮT ⇒ đường click hệ thống; BẬT ⇒ đường riêng, KHÔNG gọi playInputClick.
    func testRouteOffSystemOnCustom() {
        KeyboardView.customSoundEnabled = false
        KeyboardView.clickLetter()
        XCTAssertEqual(KeyboardView.debugLastClickRoute, "system")
        KeyboardView.clickDelete()
        XCTAssertEqual(KeyboardView.debugLastClickRoute, "system")

        KeyboardView.customSoundEnabled = true
        KeyboardView.clickLetter()
        XCTAssertEqual(KeyboardView.debugLastClickRoute, "custom:letter")
        KeyboardView.clickDelete()
        XCTAssertEqual(KeyboardView.debugLastClickRoute, "custom:delete")
        KeyboardView.clickModifier()
        XCTAssertEqual(KeyboardView.debugLastClickRoute, "custom:modifier")
    }

    /// Chỉ bật đường riêng khi có cả setting lẫn Full Access — và kiểu không phải "iOS".
    func testActivationNeedsFullAccess() {
        XCTAssertFalse(KeyboardViewController.customKeySoundActive(setting: false, style: "subtle", fullAccess: true))
        XCTAssertFalse(KeyboardViewController.customKeySoundActive(setting: true, style: "subtle", fullAccess: false))
        XCTAssertTrue(KeyboardViewController.customKeySoundActive(setting: true, style: "subtle", fullAccess: true))
        XCTAssertTrue(KeyboardViewController.customKeySoundActive(setting: true, style: "rock", fullAccess: true))
        // "iOS" (19/10/2026): click hệ thống, có hay không Full Access đều KHÔNG dùng đường riêng.
        XCTAssertFalse(KeyboardViewController.customKeySoundActive(setting: true, style: "system", fullAccess: true))
        XCTAssertFalse(KeyboardViewController.customKeySoundActive(setting: true, style: "system", fullAccess: false))
        // Giá trị lạ ⇒ mặc định (tổng hợp) ⇒ vẫn đường riêng.
        XCTAssertTrue(KeyboardViewController.customKeySoundActive(setting: true, style: "loud", fullAccess: true))
    }

    /// Trang "Âm thanh gõ": "iOS" đầu, "Âm của bạn" cuối, mỗi kiểu đúng một lần; chỉ "iOS" không cần engine.
    func testMenuOrderAndSystemStyle() {
        XCTAssertEqual(KeySoundStyle.menuOrder.first, .system)
        XCTAssertEqual(KeySoundStyle.menuOrder.last, .custom)
        XCTAssertEqual(Set(KeySoundStyle.menuOrder), Set(KeySoundStyle.allCases))
        XCTAssertEqual(KeySoundStyle.menuOrder.count, KeySoundStyle.allCases.count)
        XCTAssertEqual(KeySoundStyle.defaultStyle, .subtle, "bật công tắc ⇒ Nhẹ nhàng, không phải click hệ thống")
        for st in KeySoundStyle.allCases { XCTAssertEqual(st.usesEngine, st != .system, "\(st)") }
        XCTAssertFalse(KeySoundStyle.needsEngine("system"))
        XCTAssertTrue(KeySoundStyle.needsEngine("water"))
        XCTAssertTrue(KeySoundStyle.needsEngine(nil))
        XCTAssertTrue(KeySoundStyle.needsEngine("xyz"))
        XCTAssertFalse(KeySoundStyle.presets.contains(.system))
        XCTAssertFalse(KeySoundStyle.presets.contains(.custom))
        // Chỉ số case = seed nhiễu: các kiểu cũ giữ nguyên vị trí (mẫu + checksum không đổi).
        XCTAssertEqual(KeySoundStyle.allCases.map(\.rawValue),
                       ["subtle", "wood", "mechanical", "typewriter", "bubble", "custom", "system", "rock", "pop", "water", "vintage",
                        "phao", "jingle", "piano", "dantranh", "scifi", "trong", "boo", "guitar", "bop", "chip", "ai", "club", "dream", "airy", "mo", "bell", "rain", "plate", "twinkle", "thump", "bloop", "clink"])
        XCTAssertEqual(L10n.en["iOS"], "System click")
        for st in KeySoundStyle.allCases { XCTAssertNotNil(L10n.en[st.viTitle], "\(st) thiếu bản EN") }
        XCTAssertNotNil(L10n.en["Âm thanh gõ"])
    }

    /// Kiểu "iOS": KeySound không dựng AVAudioEngine dù bị gọi prepare/startNow (0 chi phí như TẮT).
    func testSystemStyleBuildsNoEngine() {
        let ks = KeySound.shared
        ks.debugWant(false); ks.stopNow()
        XCTAssertFalse(ks.hasEngine)
        ks.setStyle("system")
        defer { ks.setStyle(KeySoundStyle.defaultStyle.rawValue); ks.debugWant(false); ks.stopNow() }
        ks.prepare()
        ks.debugWant(true)
        XCTAssertFalse(ks.startNow())
        XCTAssertFalse(ks.play(.letter))
        // play() khi engine vắng hẹn khởi động lại nền — chờ cho queue chạy rồi kiểm lại.
        let deadline = Date().addingTimeInterval(0.3)
        while Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        XCTAssertFalse(ks.hasEngine)
        XCTAssertFalse(ks.isRunning)
    }

    /// Nghe thử khi chọn kiểu: chữ + lặng + xoá + lặng + chức năng, đúng thứ tự.
    func testPreviewSequence() {
        let bank = KeySoundKind.allCases.map { KeySoundSynth.samples(.rock, $0) }
        let gap = Int((0.16 * KeySoundSynth.sampleRate).rounded())
        let seq = KeySoundSynth.previewSequence(bank)
        XCTAssertEqual(seq.count, bank.map(\.count).reduce(0, +) + 2 * gap)
        XCTAssertEqual(Array(seq[0..<bank[0].count]), bank[0])
        let d0 = bank[0].count + gap
        XCTAssertEqual(Array(seq[d0..<d0 + bank[1].count]), bank[1])
        XCTAssertTrue(seq[bank[0].count..<d0].allSatisfy { $0 == 0 })
        XCTAssertEqual(Array(seq.suffix(bank[2].count)), bank[2])
    }

    func testSamplesDeterministicNonEmptyDistinct() {
        for st in KeySoundStyle.presets {
            var all: [[Float]] = []
            for k in KeySoundKind.allCases {
                let a = KeySoundSynth.samples(st, k), b = KeySoundSynth.samples(st, k)
                XCTAssertEqual(a, b, "\(st)/\(k) phải tất định")
                XCTAssertGreaterThan(a.count, 1000)
                // ≤ 60 ms ở 44.1 kHz; Mõ gỗ 0,12 s / Chuông nhỏ 0,36 s ngân theo thiết kế; Chuông sao 2822 mẫu (≡ Android).
                XCTAssertLessThan(a.count, [.mo, .bell].contains(st) ? 17000 : 3000, "\(st)/\(k)")
                let peak = a.map(abs).max() ?? 0
                XCTAssertEqual(Double(peak), KeySoundSynth.baseRecipe(st).peak, accuracy: 1e-4)
                XCTAssertEqual(a.first ?? 1, 0, accuracy: 1e-6)   // mở/đóng mềm — không "bụp"
                XCTAssertEqual(a.last ?? 1, 0, accuracy: 1e-6)
                let e = a.reduce(0) { $0 + $1 * $1 }
                let tail = a[(a.count / 2)...].reduce(0) { $0 + $1 * $1 }
                XCTAssertLessThan(tail / e, 0.08, "\(st)/\(k): năng lượng phải dồn đầu mẫu")
                all.append(a)
            }
            XCTAssertNotEqual(all[0], all[1]); XCTAssertNotEqual(all[1], all[2])
        }
        XCTAssertEqual(KeySoundSynth.samples(.letter), KeySoundSynth.samples(.subtle, .letter))
    }

    /// "Không chói" đo được: trọng tâm phổ thấp (bản cũ ~7 kHz), độ to trong khoảng dễ chịu.
    func testPresetsAreSoft() {
        for st in KeySoundStyle.presets {
            for k in KeySoundKind.allCases {
                let a = KeySoundSynth.samples(st, k)
                let c = KeySoundSynth.spectralCentroid(a)
                XCTAssertLessThan(c, 2500, "\(st)/\(k) centroid \(c)")
                if st == .subtle { XCTAssertLessThan(c, 1000, "mặc định phải trầm-êm: \(c)") }
                let r = KeySoundSynth.rms(a)
                XCTAssertGreaterThan(r, 0.05); XCTAssertLessThan(r, 0.30)
            }
        }
        // Mặc định ở 50 %: đỉnh thực ≤ 0.2 full-scale.
        let p50 = (KeySoundSynth.samples(.subtle, .letter).map(abs).max() ?? 0) * KeySoundSynth.gain(forPercent: 50)
        XCTAssertLessThanOrEqual(p50, 0.2 + 1e-6)
    }

    /// Checksum chung với Android (KeySoundTests.kt) — hai bên tổng hợp giống nhau.
    func testCrossPlatformChecksums() {
        for (st, want) in Self.goldenAbsSum {
            let s = KeySoundSynth.samples(st, .letter).reduce(0.0) { $0 + Double(abs($1)) }
            XCTAssertEqual(s, want, accuracy: 0.01, "\(st)")
        }
    }
    static let goldenAbsSum: [(KeySoundStyle, Double)] = [(.subtle, 169.1699), (.wood, 192.4240), (.mechanical, 239.0849), (.typewriter, 139.7659), (.bubble, 233.6785),
                                                          (.rock, 128.7247), (.pop, 154.4214), (.water, 246.5762), (.vintage, 139.9505),
                                                          (.phao, 61.5246), (.jingle, 206.7064), (.scifi, 128.7368),
                                                          (.trong, 229.6778), (.boo, 217.1955)]

    /// 4 kiểu thêm 19/10/2026: chốt cả mẫu xoá + phím chức năng (Android: crossPlatformChecksumsNewKinds).
    func testCrossPlatformChecksumsNewKinds() {
        let golden: [(KeySoundStyle, Double, Double)] = [(.rock, 125.7988, 176.4305), (.pop, 153.6654, 183.0577),
                                                         (.water, 236.6294, 280.8465), (.vintage, 167.8816, 218.2744),
                                                         (.phao, 69.1895, 93.5815), (.jingle, 212.6919, 254.5561),
                                                         (.scifi, 130.3325, 155.3449),
                                                         (.trong, 238.2098, 276.1584), (.boo, 217.6732, 252.6338)]
        for (st, del, mod) in golden {
            XCTAssertEqual(KeySoundSynth.samples(st, .delete).reduce(0.0) { $0 + Double(abs($1)) }, del, accuracy: 0.01, "\(st)")
            XCTAssertEqual(KeySoundSynth.samples(st, .modifier).reduce(0.0) { $0 + Double(abs($1)) }, mod, accuracy: 0.01, "\(st)")
        }
    }

    /// Pháo (Tết) phải NHỎ hơn các kiểu khác: đỉnh + RMS dưới "Gõ gỗ" ở cả 3 loại phím; Chuông không to hơn.
    func testPhaoQuietJingleModerate() {
        for k in KeySoundKind.allCases {
            let wood = KeySoundSynth.samples(.wood, k), phao = KeySoundSynth.samples(.phao, k), bell = KeySoundSynth.samples(.jingle, k)
            XCTAssertLessThan(KeySoundSynth.rms(phao), KeySoundSynth.rms(wood), "\(k)")
            XCTAssertLessThan(phao.map(abs).max() ?? 1, wood.map(abs).max() ?? 0, "\(k)")
            XCTAssertLessThanOrEqual(KeySoundSynth.rms(bell), KeySoundSynth.rms(wood), "\(k)")
            XCTAssertLessThanOrEqual(bell.map(abs).max() ?? 1, wood.map(abs).max() ?? 0, "\(k)")
        }
        // Mỗi loại phím nổ hơi khác (seed riêng) — tất định.
        XCTAssertNotEqual(KeySoundSynth.samples(.phao, .letter), KeySoundSynth.samples(.phao, .delete))
    }

    /// Bộ đủ món (theme Vũ trụ / Máy chữ cổ): "Bíp sci-fi" NHỎ (đỉnh + RMS < Gõ gỗ cả 3 loại phím); Enter của Máy
    /// chữ = tiếng phím + "ding" (RMS + đỉnh ≤ Gõ gỗ, không chói); kiểu khác không có Enter riêng. Checksum chung
    /// Android (KeySoundTests.kt scifiQuietAndTypewriterDing).
    func testScifiQuietAndTypewriterDing() {
        for k in KeySoundKind.allCases {
            let wood = KeySoundSynth.samples(.wood, k), sci = KeySoundSynth.samples(.scifi, k)
            XCTAssertLessThan(KeySoundSynth.rms(sci), KeySoundSynth.rms(wood), "\(k)")
            XCTAssertLessThan(sci.map(abs).max() ?? 1, wood.map(abs).max() ?? 0, "\(k)")
        }
        let ding = try! XCTUnwrap(KeySoundSynth.returnSamples(.typewriter))
        let wood = KeySoundSynth.samples(.wood, .modifier)
        XCTAssertLessThanOrEqual(KeySoundSynth.rms(ding), KeySoundSynth.rms(wood))
        XCTAssertLessThanOrEqual(ding.map(abs).max() ?? 1, wood.map(abs).max() ?? 0)
        XCTAssertEqual(ding.count, Int((0.28 * KeySoundSynth.sampleRate).rounded()))
        XCTAssertEqual(ding.first ?? 1, 0, accuracy: 1e-6); XCTAssertEqual(ding.last ?? 1, 0, accuracy: 1e-6)
        XCTAssertLessThan(KeySoundSynth.spectralCentroid(Array(ding.prefix(4096))), 2500, "ding không chói")
        XCTAssertEqual(ding.reduce(0.0) { $0 + Double(abs($1)) }, 1168.1703, accuracy: 0.01)
        XCTAssertEqual(KeySoundSynth.returnSamples(.typewriter), ding, "tất định")
        for st in KeySoundStyle.allCases where st != .typewriter { XCTAssertNil(KeySoundSynth.returnSamples(st), "\(st)") }
    }

    /// Trống lân (Trung Thu) / Ma quái (Halloween): KHÔNG to hơn "Gõ gỗ" (đỉnh + RMS cả 3 loại phím), trầm êm
    /// (trọng tâm phổ thấp), ngắn (≤ 60 ms — gõ nhanh không chồng đuôi). Android: trongBooQuiet.
    func testTrongBooQuietAndShort() {
        for k in KeySoundKind.allCases {
            let wood = KeySoundSynth.samples(.wood, k)
            for st in [KeySoundStyle.trong, .boo] {
                let a = KeySoundSynth.samples(st, k)
                XCTAssertLessThan(KeySoundSynth.rms(a), KeySoundSynth.rms(wood), "\(st)/\(k)")
                XCTAssertLessThan(a.map(abs).max() ?? 1, wood.map(abs).max() ?? 0, "\(st)/\(k)")
                XCTAssertLessThan(Double(a.count) / KeySoundSynth.sampleRate, 0.062, "\(st)/\(k)")
                XCTAssertLessThan(KeySoundSynth.spectralCentroid(a), st == .trong ? 400 : 800, "\(st)/\(k)")
            }
        }
        XCTAssertEqual(L10n.en["Trống lân"], "Lion drum"); XCTAssertEqual(L10n.en["Ma quái"], "Spooky")
    }

    /// "Bíp 8-bit" (theme Pixel 8-bit): KHÔNG to hơn "Gõ gỗ" (đỉnh + RMS cả 3 loại phím), ngắn (≤ 55 ms), sáng (trọng
    /// tâm phổ cao — sóng vuông), hai nốt (nốt sau cao hơn); checksum chung Android (KeySoundTests.kt chipBlip).
    func testChipBlipQuietShortAndShared() {
        for k in KeySoundKind.allCases {
            let wood = KeySoundSynth.samples(.wood, k), a = KeySoundSynth.samples(.chip, k)
            XCTAssertLessThan(KeySoundSynth.rms(a), KeySoundSynth.rms(wood), "\(k)")
            XCTAssertLessThan(a.map(abs).max() ?? 1, wood.map(abs).max() ?? 0, "\(k)")
            XCTAssertLessThan(Double(a.count) / KeySoundSynth.sampleRate, 0.056, "\(k)")
            XCTAssertGreaterThan(KeySoundSynth.spectralCentroid(a), 1000, "\(k) sóng vuông sáng")
        }
        let golden: [(KeySoundKind, Double)] = Self.chipGolden
        for (k, want) in golden {
            XCTAssertEqual(KeySoundSynth.samples(.chip, k).reduce(0.0) { $0 + Double(abs($1)) }, want, accuracy: 0.01, "\(k)")
        }
        XCTAssertEqual(L10n.en["Bíp 8-bit"], "8-bit blip")
        XCTAssertTrue(KeySoundStyle.presets.contains(.chip))
    }
    static let chipGolden: [(KeySoundKind, Double)] = [(.letter, 214.9587), (.delete, 213.1522), (.modifier, 237.6303)]

    /// "Nhịp club" (theme Neon Night Club): mỗi loại phím một tiếng — chữ = hi-hat (sáng hơn), xoá / chức năng = kick
    /// (trầm); không to hơn "Gõ gỗ", ≤ 60 ms; seed cố định (không theo vị trí case); checksum chung Android (clubBeat).
    func testClubBeatQuietAndShared() {
        for k in KeySoundKind.allCases {
            let wood = KeySoundSynth.samples(.wood, k), a = KeySoundSynth.samples(.club, k)
            XCTAssertLessThan(KeySoundSynth.rms(a), KeySoundSynth.rms(wood), "\(k)")
            XCTAssertLessThan(a.map(abs).max() ?? 1, wood.map(abs).max() ?? 0, "\(k)")
            XCTAssertLessThan(Double(a.count) / KeySoundSynth.sampleRate, 0.061, "\(k)")
        }
        let hat = KeySoundSynth.samples(.club, .letter), kick = KeySoundSynth.samples(.club, .delete)
        XCTAssertGreaterThan(KeySoundSynth.spectralCentroid(hat), 3 * KeySoundSynth.spectralCentroid(kick), "hat sáng, kick trầm")
        XCTAssertLessThan(KeySoundSynth.spectralCentroid(kick), 600)
        XCTAssertEqual(KeySoundSynth.seed(.club, .letter), 0x636C_7562 ^ 0x85EB_CA6B)
        for (k, want) in Self.clubGolden {
            XCTAssertEqual(KeySoundSynth.samples(.club, k).reduce(0.0) { $0 + Double(abs($1)) }, want, accuracy: 0.01, "\(k)")
        }
        XCTAssertEqual(L10n.en["Nhịp club"], "Club beat")
        XCTAssertTrue(KeySoundStyle.presets.contains(.club))
    }
    static let clubGolden: [(KeySoundKind, Double)] = [(.letter, 47.9893), (.delete, 207.6961), (.modifier, 231.8860)]

    /// Danh sách id DUY NHẤT cho trường "sound" của theme JSON; "theme" (đã bỏ) ⇒ mặc định.
    func testPresetIDsForThemeJSON() {
        XCTAssertEqual(KeySoundStyle.presetIDs, ["subtle", "wood", "mechanical", "typewriter", "bubble", "rock", "pop",
                                                 "water", "vintage", "phao", "jingle", "scifi", "trong", "boo", "bop", "chip", "ai", "club", "dream", "airy", "mo", "bell", "rain", "plate", "twinkle", "thump", "bloop", "clink", "piano", "dantranh",
                                                 "guitar"])
        for bad in ["system", "custom", "theme"] { XCTAssertFalse(KeySoundStyle.presetIDs.contains(bad), bad) }
        XCTAssertEqual(KeySoundStyle.resolve("theme", customAvailable: true), .subtle)
        let d = UserDefaults(suiteName: "vt-keysound-theme")!
        d.removePersistentDomain(forName: "vt-keysound-theme")
        let saved = UserDefaultsProvider.shared
        UserDefaultsProvider.shared = d
        defer { UserDefaultsProvider.shared = saved; d.removePersistentDomain(forName: "vt-keysound-theme") }
        d.set("theme", forKey: "keySoundStyle")
        XCTAssertEqual(KeyboardSettings.load().keySoundStyle, "subtle")
        d.set("piano", forKey: "keySoundStyle")
        XCTAssertEqual(KeyboardSettings.load().keySoundStyle, "piano")
    }

    // MARK: Piano

    /// Ánh xạ phím → nốt (chung Android PianoTests.mapping): ngũ cung C D E G A, trái→phải đi lên,
    /// hàng dưới thấp nhất, hàng số cao hơn hàng trên một quãng tám.
    func testPianoMapping() {
        let rows = PianoMap.rows.enumerated().map { r, row in (0..<row.count).map { PianoMap.midi(row: r, col: $0) } }
        XCTAssertEqual(rows, [[84, 86, 88, 91, 93, 96, 98, 100, 103, 105],
                              [72, 74, 76, 79, 81, 84, 86, 88, 91, 93],
                              [60, 62, 64, 67, 69, 72, 74, 76, 79],
                              [48, 50, 52, 55, 57, 60, 62]])
        XCTAssertEqual(PianoMap.midi(forKey: "q"), 72)
        XCTAssertEqual(PianoMap.midi(forKey: "Q"), 72)
        XCTAssertEqual(PianoMap.midi(forKey: "m"), 62)
        XCTAssertEqual(PianoMap.midi(forKey: "0"), 105)
        XCTAssertEqual(PianoMap.midi(forKey: ","), 69)   // 44 % 10 = 4 ⇒ A4
        XCTAssertEqual(PianoMap.midi(forKey: "đ"), 67)   // 273 % 10 = 3 ⇒ G4
        XCTAssertEqual(PianoMap.midi(forKey: nil), 60)
        XCTAssertEqual(PianoMap.notes.count, 25)
        for m in PianoMap.notes + PianoMap.spaceChord + PianoMap.returnChord {
            XCTAssertTrue([0, 2, 4, 7, 9].contains(m % 12), "\(m) ngoài ngũ cung")
        }
        for c in "1234567890qwertyuiopasdfghjklzxcvbnm,.?!'đ" {
            XCTAssertTrue(PianoMap.notes.contains(PianoMap.midi(forKey: String(c))), "\(c)")
        }
        XCTAssertEqual(PianoMap.returnChord[1] - PianoMap.returnChord[0], 7)   // chủ + năm
    }

    /// Tổng hợp tất định + checksum chung Android (PianoTests.synthChecksums).
    func testPianoSynthParity() {
        XCTAssertEqual(PianoSynth.note(60), PianoSynth.note(60))
        func sum(_ a: [Float]) -> Double { a.reduce(0.0) { $0 + Double(abs($1)) } }
        let golden: [(Int, Double, Double)] = [(48, 850.5462, 1019.8846), (60, 726.9604, 875.0490), (72, 644.0318, 751.4913),
                                               (93, 523.8961, 599.4355), (105, 481.8828, 593.3767)]
        for (m, n, sus) in golden {
            let a = PianoSynth.note(m)
            XCTAssertEqual(a.count, 17_640)
            XCTAssertEqual(sum(a), n, accuracy: 0.02, "\(m)")
            XCTAssertEqual(sum(PianoSynth.note(m, sustain: true)), sus, accuracy: 0.02, "\(m) ngân")
            XCTAssertEqual(Double(a.map(abs).max() ?? 0), PianoSynth.notePeak, accuracy: 1e-4)
            XCTAssertEqual(a.first ?? 1, 0, accuracy: 1e-6); XCTAssertEqual(a.last ?? 1, 0, accuracy: 1e-6)
            // Độ to 50 ms đầu ngang các kiểu khác (Gõ gỗ RMS ≈ 0.18).
            XCTAssertEqual(KeySoundSynth.rms(Array(a[0..<1102])), 0.175, accuracy: 0.03, "\(m)")
        }
        XCTAssertEqual(sum(PianoSynth.space()), 447.8193, accuracy: 0.02)
        XCTAssertEqual(sum(PianoSynth.returnChord()), 375.5216, accuracy: 0.02)
        XCTAssertEqual(sum(PianoSynth.delete()), 159.2696, accuracy: 0.02)
        XCTAssertEqual(sum(PianoSynth.pedal()), 268.6398, accuracy: 0.02)
        XCTAssertEqual(PianoSynth.note(60, sustain: true).count, 27_563)
    }

    /// Bộ nốt dựng lúc hiện: 25 nốt + 4 hợp âm vòng cách (C Am F G, hợp âm đầu dùng làm "cách") + Enter + ⌫ + pedal
    /// ≈ 2.18 MB (trước vòng hợp âm: 1.97 MB, một hợp âm cách cố định) ≤ 2.25 MB; bộ ngân (dựng lười) báo riêng.
    func testPianoMemoryBound() {
        XCTAssertEqual(PianoSynth.normalBankBytes, 2_182_952)
        XCTAssertLessThanOrEqual(PianoSynth.normalBankBytes, 9 * 1024 * 1024 / 4)
        XCTAssertEqual(PianoSynth.sustainBankBytes, 2_756_300)
        let real = PianoMap.notes.reduce(0) { $0 + PianoSynth.note($1).count }
            + (0..<4).reduce(0) { $0 + PianoSynth.chord($1).count }
            + PianoSynth.returnChord().count + PianoSynth.delete().count + PianoSynth.pedal().count
        XCTAssertEqual(real * 4, PianoSynth.normalBankBytes)
        XCTAssertEqual(KeyInstrument.piano.normalBankBytes, PianoSynth.normalBankBytes)
    }

    /// Pedal: Shift một-lần ngân ĐÚNG một nốt; Caps ngân tới khi tắt (damper); Shift tự bật không tính.
    func testPianoPedalStateMachine() {
        var p = PianoPedal()
        XCTAssertFalse(p.noteTyped())
        XCTAssertEqual(p.shiftPressed(.on), .pedalDown)
        XCTAssertTrue(p.noteTyped())
        XCTAssertFalse(p.noteTyped(), "một-lần nhả sau một nốt")
        XCTAssertEqual(p.shiftPressed(.on), .pedalDown)
        XCTAssertEqual(p.shiftPressed(.caps), .pedalDown)   // chạm đúp ⇒ Caps
        XCTAssertTrue(p.noteTyped()); XCTAssertTrue(p.noteTyped())
        XCTAssertEqual(p.shiftPressed(.off), .damper)
        XCTAssertFalse(p.noteTyped())
        XCTAssertEqual(p.shiftPressed(.on), .pedalDown)
        XCTAssertEqual(p.shiftPressed(.off), .none)          // huỷ một-lần: không damper
        XCTAssertFalse(p.isDown)
        _ = p.shiftPressed(.caps)
        XCTAssertEqual(p.shiftChanged(.on), .damper)         // Caps tự tắt (rời plane…)
        XCTAssertEqual(p.shiftChanged(.off), .none)
        XCTAssertEqual(p.state, .off)
    }

    /// Pool giọng: 4 phím cùng lúc ⇒ 4 giọng KHÁC nhau, hạ 1/√4; xoay vòng quay lại giọng 0 sau 8.
    func testVoicePoolChord() {
        var pool = VoicePool(size: 8)
        let v = (0..<4).map { _ in pool.allocate(now: 10) }
        XCTAssertEqual(Set(v).count, 4)
        XCTAssertEqual(pool.simultaneous(now: 10), 4)
        XCTAssertEqual(VoicePool.chordScale(4), 0.5, accuracy: 1e-6)
        XCTAssertEqual(VoicePool.chordScale(1), 1)
        XCTAssertEqual(pool.simultaneous(now: 10.5), 0, "hết cửa sổ hợp âm")
        for _ in 0..<4 { _ = pool.allocate(now: 11) }
        XCTAssertEqual(pool.allocate(now: 12), 0, "round-robin")
        // 8 giọng chồng nhau cực đại: tổng đỉnh × chordScale ≤ 1 (không vỡ tiếng ở 100 %).
        XCTAssertLessThanOrEqual(Double(VoicePool.chordScale(8)) * 8 * PianoSynth.notePeak, 1.0)
    }

    /// Đường phím: Piano ⇒ nốt theo nhãn + pedal; kiểu khác GIỮ đường 3 tiếng (không đổi).
    func testPianoRoute() {
        KeyboardView.customSoundEnabled = true
        KeyboardView.pianoEnabled = false
        KeyboardView.clickLetter("a")
        XCTAssertEqual(KeyboardView.debugLastClickRoute, "custom:letter")
        KeyboardView.clickSpace()
        XCTAssertEqual(KeyboardView.debugLastClickRoute, "custom:modifier")
        KeyboardView.clickReturn()
        XCTAssertEqual(KeyboardView.debugLastClickRoute, "custom:return", "Enter qua KeySound.playReturn (Máy chữ: ding)")
        KeyboardView.clickShift(.on)
        XCTAssertEqual(KeyboardView.debugLastClickRoute, "custom:modifier")
        XCTAssertEqual(KeyboardView.pianoPedal.state, .off, "kiểu khác không đụng pedal")

        KeyboardView.pianoEnabled = true
        KeyboardView.clickLetter("a")
        XCTAssertEqual(KeyboardView.debugLastClickRoute, "piano:60")
        KeyboardView.clickLetter("p")
        XCTAssertEqual(KeyboardView.debugLastClickRoute, "piano:93")
        KeyboardView.clickSpace()
        XCTAssertEqual(KeyboardView.debugLastClickRoute, "piano:space")
        KeyboardView.clickReturn()
        XCTAssertEqual(KeyboardView.debugLastClickRoute, "piano:returnKey")
        KeyboardView.clickDelete()
        XCTAssertEqual(KeyboardView.debugLastClickRoute, "piano:delete")
        KeyboardView.clickShift(.on)
        KeyboardView.clickLetter("q")
        XCTAssertEqual(KeyboardView.debugLastClickRoute, "piano:72:sustain")
        KeyboardView.clickLetter("q")
        XCTAssertEqual(KeyboardView.debugLastClickRoute, "piano:72")
        // Hệ thống ("iOS") vẫn là click hệ thống.
        KeyboardView.customSoundEnabled = false
        KeyboardView.clickLetter("a")
        XCTAssertEqual(KeyboardView.debugLastClickRoute, "system")
    }

    /// Engine thật (bỏ qua nếu máy test không có audio): 4 nốt cùng khung ⇒ 4 giọng khác nhau cùng kêu.
    func testPianoEngineChord() throws {
        let ks = KeySound.shared
        ks.debugWant(false); ks.stopNow()
        setStyleSettled(ks, "piano")
        ks.debugWant(true)
        defer { ks.setStyle(KeySoundStyle.defaultStyle.rawValue); ks.debugDrain(); ks.debugWant(false); ks.stopNow() }
        guard ks.startNow() else { throw XCTSkip("không có audio output trên máy test") }
        XCTAssertEqual(ks.activeStyle, .piano)
        let voices = try XCTUnwrap(playChordWhenSettled(ks, [60, 64, 67, 72]))
        XCTAssertEqual(voices.count, 4)
        XCTAssertEqual(ks.pianoSimultaneous, 4)
        // Rời Piano ⇒ về đường 3 tiếng.
        setStyleSettled(ks, "wood")
        XCTAssertTrue(ks.startNow())
        XCTAssertEqual(ks.activeStyle, .wood)
        XCTAssertTrue(whenSettled(ks) { ks.play(.letter) })
        XCTAssertFalse(ks.playPiano(.note(60), sustain: false))
    }

    // MARK: Đàn tranh (theme Sen Việt) — cùng hạ tầng Piano (NoteMap / pool / pedal), khác thang + tiếng

    /// Ánh xạ phím → nốt (chung Android PianoTests.danTranhMapping): ngũ cung điệu Bắc C D F G A, cùng vị trí
    /// hàng/cột như Piano (chỉ thang khác).
    func testDanTranhMapping() {
        let m = NoteMap.dantranh
        let rows = NoteMap.rows.enumerated().map { r, row in (0..<row.count).map { m.midi(row: r, col: $0) } }
        XCTAssertEqual(rows, [[84, 86, 89, 91, 93, 96, 98, 101, 103, 105],
                              [72, 74, 77, 79, 81, 84, 86, 89, 91, 93],
                              [60, 62, 65, 67, 69, 72, 74, 77, 79],
                              [48, 50, 53, 55, 57, 60, 62]])
        XCTAssertEqual(m.midi(forKey: "d"), 65)   // Piano: 64 (E4) — đàn tranh: F4 (Xang)
        XCTAssertEqual(m.midi(forKey: "E"), 77)
        XCTAssertEqual(m.midi(forKey: "0"), 105)
        XCTAssertEqual(m.midi(forKey: ","), 69)
        XCTAssertEqual(m.midi(forKey: "đ"), 67)
        XCTAssertEqual(m.midi(forKey: nil), 60)
        XCTAssertEqual(m.notes.count, 25)
        for x in m.notes + m.spaceChord + m.returnChord + [m.deleteNote, m.modifierNote] {
            XCTAssertTrue([0, 2, 5, 7, 9].contains(x % 12), "\(x) ngoài ngũ cung điệu Bắc")
        }
        for c in "1234567890qwertyuiopasdfghjklzxcvbnm,.?!'đ" {
            XCTAssertTrue(m.notes.contains(m.midi(forKey: String(c))), "\(c)")
        }
        // Cùng vị trí với Piano: mỗi phím cùng quãng tám, chỉ bậc E ↔ F khác.
        for c in "qwertyuiopasdfghjklzxcvbnm" {
            let a = PianoMap.midi(forKey: String(c)), b = m.midi(forKey: String(c))
            XCTAssertTrue(a == b || (a % 12 == 4 && b == a + 1), "\(c)")
        }
        // PianoMap giữ nguyên API cũ (uỷ cho NoteMap.piano).
        XCTAssertEqual(PianoMap.notes, NoteMap.piano.notes)
        XCTAssertEqual(KeyInstrument.of("dantranh"), .dantranh)
        XCTAssertEqual(KeyInstrument.of("piano"), .piano)
        XCTAssertNil(KeyInstrument.of("wood")); XCTAssertNil(KeyInstrument.of("system")); XCTAssertNil(KeyInstrument.of(nil))
        XCTAssertEqual(KeyInstrument.dantranh.map, .dantranh)
        XCTAssertEqual(KeyInstrument.dantranh.style, .dantranh)
    }

    /// Tổng hợp tất định + checksum chung Android (PianoTests.danTranhChecksums).
    func testDanTranhSynthParity() {
        XCTAssertEqual(DanTranhSynth.note(60), DanTranhSynth.note(60))
        func sum(_ a: [Float]) -> Double { a.reduce(0.0) { $0 + Double(abs($1)) } }
        let golden: [(Int, Double, Double)] = [(48, 637.1004, 721.6308), (60, 556.5538, 650.7014), (72, 500.1500, 588.8047),
                                               (93, 397.5509, 488.6524), (105, 449.1060, 656.5890)]
        for (m, n, sus) in golden {
            let a = DanTranhSynth.note(m)
            XCTAssertEqual(a.count, 22_050)
            XCTAssertEqual(sum(a), n, accuracy: 0.02, "\(m)")
            XCTAssertEqual(sum(DanTranhSynth.note(m, sustain: true)), sus, accuracy: 0.02, "\(m) ngân")
            XCTAssertEqual(Double(a.map(abs).max() ?? 0), DanTranhSynth.notePeak, accuracy: 1e-4)
            XCTAssertEqual(a.first ?? 1, 0, accuracy: 1e-6); XCTAssertEqual(a.last ?? 1, 0, accuracy: 1e-6)
        }
        XCTAssertEqual(sum(DanTranhSynth.space()), 434.8580, accuracy: 0.02)
        XCTAssertEqual(sum(DanTranhSynth.returnChord()), 367.0031, accuracy: 0.02)
        XCTAssertEqual(sum(DanTranhSynth.delete()), 72.3706, accuracy: 0.02)
        XCTAssertEqual(sum(DanTranhSynth.pedal()), 189.2533, accuracy: 0.02)
        XCTAssertEqual(sum(DanTranhSynth.previewMelody()), 1353.9346, accuracy: 0.05)
        XCTAssertEqual(DanTranhSynth.note(60, sustain: true).count, 27_563)
        XCTAssertNotEqual(DanTranhSynth.note(60), PianoSynth.note(60))
    }

    /// Không to hơn Piano: đỉnh + RMS mỗi nốt / hợp âm / pedal / ⌫ ≤ Piano; 8 giọng chồng nhau không vỡ tiếng.
    /// "Nhấn nhá" chỉ là rung nhẹ: đuôi nốt A4 vẫn ≈ 440 Hz.
    func testDanTranhNotLouderThanPiano() {
        XCTAssertLessThanOrEqual(DanTranhSynth.notePeak, PianoSynth.notePeak)
        XCTAssertLessThanOrEqual(DanTranhSynth.chordPeak, PianoSynth.chordPeak)
        XCTAssertLessThanOrEqual(DanTranhSynth.pedalPeak, PianoSynth.pedalPeak)
        for m in [48, 60, 72, 93, 105] {
            XCTAssertLessThan(KeySoundSynth.rms(DanTranhSynth.note(m)), KeySoundSynth.rms(PianoSynth.note(m)), "\(m)")
        }
        XCTAssertLessThan(KeySoundSynth.rms(DanTranhSynth.space()), KeySoundSynth.rms(PianoSynth.space()))
        XCTAssertLessThan(KeySoundSynth.rms(DanTranhSynth.returnChord()), KeySoundSynth.rms(PianoSynth.returnChord()))
        XCTAssertLessThan(KeySoundSynth.rms(DanTranhSynth.pedal()), KeySoundSynth.rms(PianoSynth.pedal()))
        XCTAssertLessThan(KeySoundSynth.rms(DanTranhSynth.delete()), KeySoundSynth.rms(PianoSynth.delete()))
        XCTAssertLessThanOrEqual(Double(VoicePool.chordScale(8)) * 8 * DanTranhSynth.notePeak, 1.0)
        let a4 = DanTranhSynth.note(69)
        var crossings = 0
        for i in 13_000..<17_400 where (a4[i] <= 0) != (a4[i + 1] <= 0) { crossings += 1 }
        let hz = Double(crossings) / 2 / (4_400.0 / PianoSynth.sampleRate)
        XCTAssertEqual(hz, 440, accuracy: 440 * 0.015, "A4 lệch cao độ")
    }

    /// Bộ nốt dựng lúc hiện (Float32): 25 nốt 1.0 s + cách/Enter + ⌫ + pedal ≈ 2.45 MB (Piano 1.97 MB, 0.8 s);
    /// bộ ngân dựng lười cùng cỡ Piano. Android lưu PCM16 ⇒ một nửa.
    func testDanTranhMemoryBound() {
        XCTAssertEqual(DanTranhSynth.normalBankBytes, 2_447_552)
        XCTAssertLessThanOrEqual(DanTranhSynth.normalBankBytes, 5 * 1024 * 1024 / 2)
        XCTAssertEqual(DanTranhSynth.sustainBankBytes, PianoSynth.sustainBankBytes)
        let i = KeyInstrument.dantranh
        let real = i.map.notes.reduce(0) { $0 + i.note($1).count } + i.space().count + i.returnChord().count
            + i.delete().count + i.pedal().count
        XCTAssertEqual(real * 4, i.normalBankBytes)
    }

    /// Đàn tranh đi CHUNG đường Piano ở bàn phím: nốt theo bảng đàn tranh, cách/Enter/⌫ riêng, Shift = pedal
    /// (cùng máy trạng thái PianoPedal: một-lần ngân đúng một nốt, Caps giữ tới khi tắt).
    func testDanTranhRouteReusesPianoPedal() {
        let saved = KeyboardView.pianoMap
        defer { KeyboardView.pianoMap = saved; KeyboardView.pianoEnabled = false; KeyboardView.pianoPedal = PianoPedal() }
        KeyboardView.customSoundEnabled = true
        KeyboardView.pianoEnabled = true
        KeyboardView.pianoMap = KeyInstrument.dantranh.map
        KeyboardView.pianoPedal = PianoPedal()
        KeyboardView.clickLetter("d")
        XCTAssertEqual(KeyboardView.debugLastClickRoute, "piano:65")
        KeyboardView.clickSpace()
        XCTAssertEqual(KeyboardView.debugLastClickRoute, "piano:space")
        KeyboardView.clickReturn()
        XCTAssertEqual(KeyboardView.debugLastClickRoute, "piano:returnKey")
        KeyboardView.clickDelete()
        XCTAssertEqual(KeyboardView.debugLastClickRoute, "piano:delete")
        KeyboardView.clickShift(.on)
        XCTAssertEqual(KeyboardView.pianoPedal.state, .once)
        KeyboardView.clickLetter("e")
        XCTAssertEqual(KeyboardView.debugLastClickRoute, "piano:77:sustain")
        KeyboardView.clickLetter("e")
        XCTAssertEqual(KeyboardView.debugLastClickRoute, "piano:77")
        KeyboardView.clickShift(.caps)
        KeyboardView.clickLetter("a"); XCTAssertEqual(KeyboardView.debugLastClickRoute, "piano:60:sustain")
        KeyboardView.clickLetter("s"); XCTAssertEqual(KeyboardView.debugLastClickRoute, "piano:62:sustain")
        KeyboardView.clickShift(.off)
        XCTAssertEqual(KeyboardView.pianoPedal.state, .off)
        KeyboardView.customSoundEnabled = false
    }

    /// Engine thật (bỏ qua nếu không có audio): đàn tranh dựng bằng đường Piano — 4 nốt cùng khung ⇒ 4 giọng; đổi
    /// Piano ⇄ Đàn tranh dựng lại bộ nốt, giữ pool; rời nhạc cụ ⇒ đường 3 tiếng.
    func testDanTranhEngineChordAndSwitch() throws {
        let ks = KeySound.shared
        ks.debugWant(false); ks.stopNow()
        setStyleSettled(ks, "piano")
        ks.debugWant(true)
        defer { ks.setStyle(KeySoundStyle.defaultStyle.rawValue); ks.debugDrain(); ks.debugWant(false); ks.stopNow() }
        guard ks.startNow() else { throw XCTSkip("không có audio output trên máy test") }
        XCTAssertEqual(ks.instrument, .piano)
        setStyleSettled(ks, "dantranh")
        XCTAssertTrue(ks.startNow())
        XCTAssertEqual(ks.activeStyle, .dantranh)
        XCTAssertEqual(ks.instrument, .dantranh)
        let voices = try XCTUnwrap(playChordWhenSettled(ks, [60, 65, 67, 72]))
        XCTAssertEqual(voices.count, 4)
        XCTAssertEqual(ks.pianoSimultaneous, 4)
        XCTAssertTrue(playWhenSettled(ks, .space))
        XCTAssertTrue(playWhenSettled(ks, .pedal))
        setStyleSettled(ks, "wood")
        XCTAssertTrue(ks.startNow())
        XCTAssertEqual(ks.activeStyle, .wood)
        XCTAssertFalse(ks.playPiano(.note(60), sustain: false))
    }

    // MARK: Vòng hợp âm phím cách (ChordProgression — Piano / Ghi-ta; Đàn tranh không dùng)

    /// Máy trạng thái thuần (chung Android ChordProgressionTests): tiến mỗi lần cách, vòng lại sau hợp âm cuối, nghỉ
    /// > 3 s ⇒ về đầu, kết câu (. ! ?) ⇒ về đầu, Enter ⇒ chủ rồi về đầu, gõ chữ giữa câu dài không reset.
    func testChordProgressionPure() {
        var p = ChordProgression(count: 4)
        XCTAssertEqual((0..<6).map { p.space(now: 1 + Double($0) * 0.5) }, [0, 1, 2, 3, 0, 1], "tiến + vòng lại")
        // Nghỉ gõ: 2.9 s vẫn tiếp vòng, > 3 s về đầu.
        XCTAssertEqual(p.space(now: 6.4), 2)
        XCTAssertEqual(p.space(now: 9.5), 0, "nghỉ 3.1 s ⇒ về hợp âm đầu")
        // Gõ chữ liên tục (câu dài > 3 s giữa hai lần cách) KHÔNG reset vì mỗi phím cập nhật thời điểm.
        for k in 1...8 { p.typed(now: 9.5 + Double(k) * 0.6, sentenceEnd: false) }
        XCTAssertEqual(p.space(now: 14.5), 1, "đang gõ ⇒ vòng tiếp tục")
        // Kết câu ⇒ về đầu.
        p.typed(now: 14.8, sentenceEnd: true)
        XCTAssertEqual(p.space(now: 15.0), 0)
        XCTAssertEqual(p.space(now: 15.2), 1)
        // Enter ⇒ hợp âm chủ (bàn phím phát returnChord) rồi về đầu.
        p.returnKey(now: 15.4)
        XCTAssertEqual(p.index, 0)
        XCTAssertEqual(p.space(now: 15.6), 0)
        // Nghỉ rồi gõ chữ (không cách) cũng tính là đoạn mới.
        p.typed(now: 30, sentenceEnd: false)
        XCTAssertEqual(p.space(now: 30.2), 0)
        p.reset()
        XCTAssertEqual(p, ChordProgression(count: 4))
        // count 0 (Đàn tranh) luôn 0, không crash.
        var z = ChordProgression(count: 0)
        XCTAssertEqual([z.space(now: 0), z.space(now: 0.1)], [0, 0])
        for k in [".", "!", "?"] { XCTAssertTrue(ChordProgression.isSentenceEnd(k), k) }
        for k in [",", "a", "", "..", ";", nil] { XCTAssertFalse(ChordProgression.isSentenceEnd(k), "\(String(describing: k))") }
        XCTAssertEqual(ChordProgression.idleReset, 3.0)
    }

    /// Bảng vòng: Piano C → Am → F → G (ba nốt, trầm gọn), Ghi-ta Am → F → C → G (6 dây, thế bấm mở), Enter Ghi-ta = C
    /// trưởng; Đàn tranh không có vòng. Nốt hợp âm không thêm buffer nốt lẻ (bảng nốt vẫn 25).
    func testProgressionTables() {
        func classes(_ c: [Int]) -> Set<Int> { Set(c.map { $0 % 12 }) }
        XCTAssertEqual(NoteMap.piano.progression.map(classes), [[0, 4, 7], [9, 0, 4], [5, 9, 0], [7, 11, 2]])
        XCTAssertEqual(NoteMap.guitar.progression.map(classes), [[9, 0, 4], [5, 9, 0], [0, 4, 7], [7, 11, 2]])
        XCTAssertEqual(NoteMap.guitar.progression.map { $0.first! % 12 }, [4, 5, 7, 7])   // Am/E, F, C/G, G — bass dây 6
        for c in NoteMap.guitar.progression { XCTAssertEqual(c.count, 6); XCTAssertEqual(c, c.sorted(), "quạt trầm → cao") }
        XCTAssertEqual(classes(NoteMap.guitar.returnChord), [0, 4, 7])
        XCTAssertEqual(NoteMap.guitar.returnChord.count, 6)
        XCTAssertTrue(NoteMap.dantranh.progression.isEmpty)
        XCTAssertTrue(KeyInstrument.piano.hasProgression); XCTAssertTrue(KeyInstrument.guitar.hasProgression)
        XCTAssertFalse(KeyInstrument.dantranh.hasProgression)
        XCTAssertEqual(NoteMap.guitar.notes, NoteMap.piano.notes)
        XCTAssertEqual(NoteMap.piano.notes.count, 25)
        XCTAssertEqual(PianoMap.returnChord, [60, 67, 72], "Enter Piano giữ hợp âm chủ")
    }

    /// Đường phím: Piano / Ghi-ta ⇒ cách phát hợp âm theo vòng; Đàn tranh ⇒ hợp âm cách cố định (`.space`).
    /// Phiên thật trên CÙNG một trạng thái: chữ, cách, ⌫, ".", nghỉ, Enter xen kẽ.
    func testSpaceProgressionRoute() {
        let savedMap = KeyboardView.pianoMap, savedClock = KeyboardView.progressionClock
        var now = 100.0
        KeyboardView.progressionClock = { now }
        defer {
            KeyboardView.pianoMap = savedMap; KeyboardView.progressionClock = savedClock
            KeyboardView.chordProgression = ChordProgression(count: 0)
            KeyboardView.pianoEnabled = false; KeyboardView.customSoundEnabled = false; KeyboardView.pianoPedal = PianoPedal()
        }
        KeyboardView.customSoundEnabled = true
        KeyboardView.pianoEnabled = true
        for inst in [KeyInstrument.piano, .guitar] {
            KeyboardView.pianoMap = inst.map
            KeyboardView.chordProgression = ChordProgression(count: inst.map.progression.count)
            var routes: [String] = []
            func space() { now += 0.4; KeyboardView.clickSpace(); routes.append(KeyboardView.debugLastClickRoute ?? "") }
            KeyboardView.clickLetter("a"); XCTAssertEqual(KeyboardView.debugLastClickRoute, "piano:60")
            space(); space(); space(); space(); space()
            XCTAssertEqual(routes, ["piano:chord(0)", "piano:chord(1)", "piano:chord(2)", "piano:chord(3)", "piano:chord(0)"], "\(inst)")
            now += 0.2; KeyboardView.clickDelete(); XCTAssertEqual(KeyboardView.debugLastClickRoute, "piano:delete")
            space(); XCTAssertEqual(routes.last, "piano:chord(1)")
            now += 0.2; KeyboardView.clickLetter(sentenceEnd: true)   // "." hàng đáy
            space(); XCTAssertEqual(routes.last, "piano:chord(0)", "kết câu ⇒ về đầu")
            now += 0.2; KeyboardView.clickLetter("!")
            space(); XCTAssertEqual(routes.last, "piano:chord(0)")
            space(); XCTAssertEqual(routes.last, "piano:chord(1)")
            now += 3.5                                                  // nghỉ gõ
            space(); XCTAssertEqual(routes.last, "piano:chord(0)", "nghỉ > 3 s ⇒ về đầu")
            space()
            now += 0.2; KeyboardView.clickReturn(); XCTAssertEqual(KeyboardView.debugLastClickRoute, "piano:returnKey")
            space(); XCTAssertEqual(routes.last, "piano:chord(0)", "Enter ⇒ chủ rồi về đầu")
            now += 0.2; KeyboardView.chordSentenceEnd()               // cách đúp ⇒ ". "
            space(); XCTAssertEqual(routes.last, "piano:chord(0)")
        }
        // Đàn tranh: không vòng — mọi lần cách là hợp âm dây buông.
        KeyboardView.pianoMap = KeyInstrument.dantranh.map
        KeyboardView.chordProgression = ChordProgression(count: KeyInstrument.dantranh.map.progression.count)
        for _ in 0..<3 { now += 0.4; KeyboardView.clickSpace(); XCTAssertEqual(KeyboardView.debugLastClickRoute, "piano:space") }
        KeyboardView.clickReturn(); XCTAssertEqual(KeyboardView.debugLastClickRoute, "piano:returnKey")
    }

    // MARK: Ghi-ta mộc (theme Ghi-ta) — cùng hạ tầng Piano, dây gảy họ Đàn tranh

    /// Ghi-ta dùng CHUNG vị trí + thang ngũ cung với Piano.
    func testGuitarMapping() {
        let m = NoteMap.guitar
        for c in "1234567890qwertyuiopasdfghjklzxcvbnm,.?!'đ" {
            XCTAssertEqual(m.midi(forKey: String(c)), PianoMap.midi(forKey: String(c)), "\(c)")
        }
        XCTAssertEqual(KeyInstrument.of("guitar"), .guitar)
        XCTAssertEqual(KeyInstrument.guitar.style, .guitar)
        XCTAssertEqual(KeyInstrument.guitar.map, .guitar)
        XCTAssertEqual(KeySoundStyle.guitar.viTitle, "Ghi-ta mộc")
        XCTAssertEqual(L10n.en["Ghi-ta mộc"], "Acoustic guitar")
    }

    /// Tổng hợp tất định + checksum chung Android (PianoTests.guitarChecksums).
    func testGuitarSynthParity() {
        XCTAssertEqual(GuitarSynth.note(60), GuitarSynth.note(60))
        func sum(_ a: [Float]) -> Double { a.reduce(0.0) { $0 + Double(abs($1)) } }
        let golden: [(Int, Double, Double)] = [(48, 691.3709, 675.6130), (60, 700.1426, 708.1190), (72, 558.9103, 561.0567),
                                               (93, 446.2891, 575.5285), (105, 593.3481, 840.8058)]
        for (m, n, sus) in golden {
            let a = GuitarSynth.note(m)
            XCTAssertEqual(a.count, 26_460)
            XCTAssertEqual(sum(a), n, accuracy: 0.02, "\(m)")
            XCTAssertEqual(sum(GuitarSynth.note(m, sustain: true)), sus, accuracy: 0.02, "\(m) ngân")
            XCTAssertEqual(Double(a.map(abs).max() ?? 0), GuitarSynth.notePeak, accuracy: 1e-4)
            XCTAssertEqual(a.first ?? 1, 0, accuracy: 1e-6); XCTAssertEqual(a.last ?? 1, 0, accuracy: 1e-6)
        }
        let chords = [651.0677, 618.7805, 683.5506, 505.9570]
        for (i, c) in chords.enumerated() {
            XCTAssertEqual(sum(GuitarSynth.chord(i)), c, accuracy: 0.02, "hợp âm \(i)")
            XCTAssertEqual(GuitarSynth.chord(i).count, 26_460)
        }
        XCTAssertEqual(GuitarSynth.space(), GuitarSynth.chord(0))
        XCTAssertEqual(sum(GuitarSynth.returnChord()), 620.5448, accuracy: 0.02)
        XCTAssertEqual(sum(GuitarSynth.delete()), 69.6841, accuracy: 0.02)
        XCTAssertEqual(sum(GuitarSynth.pedal()), 140.4053, accuracy: 0.02)
        XCTAssertEqual(sum(GuitarSynth.previewMelody()), 1959.4907, accuracy: 0.05)
        XCTAssertNotEqual(GuitarSynth.note(60), DanTranhSynth.note(60))
        // Piano: hợp âm vòng (C Am F G) — checksum chung.
        let pc = [411.0733, 514.2972, 461.2571, 445.9170]
        for (i, c) in pc.enumerated() { XCTAssertEqual(sum(PianoSynth.chord(i)), c, accuracy: 0.02, "Piano hợp âm \(i)") }
    }

    /// Quạt 6 dây cách nhau 25 ms (Enter: 35 ms): mẫu bắt đầu dây j = round(j·strum·22050); trước dây thứ hai chỉ có
    /// dây đầu (tỉ lệ với bản một dây).
    func testGuitarStrumTiming() {
        let sr = PianoSynth.sampleRate
        XCTAssertEqual((0..<6).map { GuitarSynth.onset($0, strum: GuitarSynth.strum, sampleRate: sr) }, [0, 551, 1103, 1654, 2205, 2756])
        XCTAssertEqual((0..<6).map { GuitarSynth.onset($0, strum: GuitarSynth.tonicStrum, sampleRate: sr) }, [0, 772, 1544, 2315, 3087, 3859])
        XCTAssertEqual(GuitarSynth.strum, 0.025)
        let chord = NoteMap.guitar.progression[0]
        let a = GuitarSynth.samples(chord, kind: .normal, peak: 1, strum: GuitarSynth.strum)
        let one = GuitarSynth.samples([chord[0]], kind: .normal, peak: 1)
        // finish() chỉ chuẩn hoá đỉnh ⇒ trước dây 2: a = k·one (k hằng).
        let k = Double(a[300]) / Double(one[300])
        for i in stride(from: 40, to: 548, by: 7) where abs(one[i]) > 1e-4 {
            XCTAssertEqual(Double(a[i]) / Double(one[i]), k, accuracy: 1e-3, "mẫu \(i)")
        }
        // Sau dây 2 thì khác hẳn.
        var diff = 0.0
        for i in 560..<1100 { diff += abs(Double(a[i]) - k * Double(one[i])) }
        XCTAssertGreaterThan(diff, 1)
    }

    /// Không to hơn Piano (đỉnh + RMS): nốt, hợp âm vòng (6 dây ≤ hợp âm Piano to nhất), chủ, ⌫, pedal.
    /// Không vibrato: đuôi nốt A4 đúng 440 Hz (±0.5 %).
    func testGuitarNotLouderThanPiano() {
        XCTAssertLessThanOrEqual(GuitarSynth.notePeak, PianoSynth.notePeak)
        XCTAssertLessThanOrEqual(GuitarSynth.chordPeak, PianoSynth.chordPeak)
        XCTAssertLessThanOrEqual(GuitarSynth.pedalPeak, PianoSynth.pedalPeak)
        XCTAssertLessThanOrEqual(GuitarSynth.deletePeak, PianoSynth.notePeak)
        for m in [48, 60, 72, 93, 105] {
            XCTAssertLessThan(KeySoundSynth.rms(GuitarSynth.note(m)), KeySoundSynth.rms(PianoSynth.note(m)), "\(m)")
        }
        let pianoChordMax = (0..<4).map { KeySoundSynth.rms(PianoSynth.chord($0)) }.max()!
        for i in 0..<4 { XCTAssertLessThanOrEqual(KeySoundSynth.rms(GuitarSynth.chord(i)), pianoChordMax, "hợp âm \(i)") }
        XCTAssertLessThanOrEqual(KeySoundSynth.rms(GuitarSynth.returnChord()), KeySoundSynth.rms(PianoSynth.returnChord()))
        XCTAssertLessThan(KeySoundSynth.rms(GuitarSynth.delete()), KeySoundSynth.rms(PianoSynth.delete()))
        XCTAssertLessThan(KeySoundSynth.rms(GuitarSynth.pedal()), KeySoundSynth.rms(PianoSynth.pedal()))
        XCTAssertLessThanOrEqual(Double(VoicePool.chordScale(8)) * 8 * GuitarSynth.notePeak, 1.0)
        let a4 = GuitarSynth.note(69)
        var crossings = 0
        for i in 13_000..<17_400 where (a4[i] <= 0) != (a4[i + 1] <= 0) { crossings += 1 }
        let hz = Double(crossings) / 2 / (4_400.0 / PianoSynth.sampleRate)
        XCTAssertEqual(hz, 440, accuracy: 440 * 0.005, "A4 lệch cao độ / có rung")
    }

    /// Bộ nốt dựng lúc hiện (Float32): 25 nốt 1.2 s + 4 hợp âm + chủ + ⌫ + pedal ≈ 3.24 MB (Piano 2.18, Đàn tranh 2.45);
    /// Android PCM16 ⇒ một nửa (~1.62 MB). Bộ ngân dựng lười cùng cỡ Piano.
    func testGuitarMemoryBound() {
        XCTAssertEqual(GuitarSynth.normalBankBytes, 3_241_352)
        XCTAssertLessThanOrEqual(GuitarSynth.normalBankBytes, 7 * 1024 * 1024 / 2)
        XCTAssertLessThanOrEqual(Double(GuitarSynth.normalBankBytes) / Double(PianoSynth.normalBankBytes), 1.5)
        XCTAssertEqual(GuitarSynth.sustainBankBytes, PianoSynth.sustainBankBytes)
        let i = KeyInstrument.guitar
        let real = i.map.notes.reduce(0) { $0 + i.note($1).count } + (0..<4).reduce(0) { $0 + i.chord($1).count }
            + i.returnChord().count + i.delete().count + i.pedal().count
        XCTAssertEqual(real * 4, i.normalBankBytes)
    }

    /// Engine thật (bỏ qua nếu không có audio): Piano / Ghi-ta dựng 4 âm đặc biệt + 4 hợp âm vòng; Đàn tranh chỉ 4.
    /// `playPiano` chỉ `lock.try()` (cố ý: không bao giờ chặn main) và trả false khi việc nền đang
    /// giữ lock (dựng lại sau AVAudioEngineConfigurationChange, idle check, dựng nốt ngân do test
    /// trước đạp pedal) hoặc engine vừa bị dừng (tự dựng lại trên queue). Đó là "bỏ một tiếng" hợp
    /// lệ, không phải lỗi ⇒ test chờ queue rồi thử lại. Lỗi thật (thiếu buffer / giọng) false mọi lần.
    private func playWhenSettled(_ ks: KeySound, _ ev: PianoEvent) -> Bool {
        whenSettled(ks) { ks.playPiano(ev, sustain: false) }
    }
    /// Như trên cho mọi lệnh phát `lock.try()` (`play`, `playPiano`).
    private func whenSettled(_ ks: KeySound, _ play: () -> Bool) -> Bool {
        for _ in 0..<20 {
            ks.debugDrain()
            if play() { return true }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return false
    }

    /// Bấm hợp âm (các nốt liền nhau trong cửa sổ hợp âm). Trượt lock giữa chừng ⇒ đợi quá cửa sổ
    /// rồi bấm lại CẢ hợp âm (thử lại từng nốt sẽ kéo giãn hợp âm). nil = không lần nào trọn vẹn.
    private func playChordWhenSettled(_ ks: KeySound, _ notes: [Int]) -> Set<Int>? {
        for _ in 0..<20 {
            ks.debugDrain()
            var voices = Set<Int>()
            var ok = true
            for m in notes {
                guard ks.playPiano(.note(m), sustain: false) else { ok = false; break }
                voices.insert(ks.lastPianoVoice)
            }
            if ok { return voices }
            Thread.sleep(forTimeInterval: VoicePool.chordWindow + 0.02)
        }
        return nil
    }

    /// Đổi kiểu rồi chờ: `setStyle` xếp hàng lên queue nếu lock đang bận ⇒ phải drain trước
    /// startNow, không thì startNow dựng lại kiểu CŨ (flaky: pianoExtraCount 8 thay vì 4).
    private func setStyleSettled(_ ks: KeySound, _ raw: String) {
        ks.setStyle(raw)
        ks.debugDrain()
    }

    func testProgressionEngineBuffers() throws {
        let ks = KeySound.shared
        ks.debugDrain()                    // việc nền còn sót của test trước (nốt ngân, idle…)
        ks.debugWant(false); ks.stopNow()
        setStyleSettled(ks, "guitar")
        ks.debugWant(true)
        defer { ks.setStyle(KeySoundStyle.defaultStyle.rawValue); ks.debugDrain(); ks.debugWant(false); ks.stopNow() }
        guard ks.startNow() else { throw XCTSkip("không có audio output trên máy test") }
        XCTAssertEqual(ks.instrument, .guitar)
        XCTAssertEqual(ks.pianoExtraCount, 8)
        for i in 0..<4 { XCTAssertTrue(playWhenSettled(ks, .chord(i)), "hợp âm \(i)") }
        XCTAssertTrue(playWhenSettled(ks, .chord(9)), "chỉ số lạ ⇒ hợp âm cách, không crash")
        XCTAssertTrue(playWhenSettled(ks, .returnKey))
        XCTAssertTrue(playWhenSettled(ks, .delete))
        setStyleSettled(ks, "piano"); XCTAssertTrue(ks.startNow()); XCTAssertEqual(ks.pianoExtraCount, 8)
        setStyleSettled(ks, "dantranh"); XCTAssertTrue(ks.startNow()); XCTAssertEqual(ks.pianoExtraCount, 4)
        XCTAssertTrue(playWhenSettled(ks, .space))
    }

    func testStyleResolveAndBankFallback() {
        XCTAssertEqual(KeySoundStyle.resolve(nil, customAvailable: true), .subtle)
        XCTAssertEqual(KeySoundStyle.resolve("xyz", customAvailable: true), .subtle)
        XCTAssertEqual(KeySoundStyle.resolve("wood", customAvailable: false), .wood)
        XCTAssertEqual(KeySoundStyle.resolve("custom", customAvailable: false), .subtle)
        XCTAssertEqual(KeySoundStyle.resolve("custom", customAvailable: true), .custom)
        XCTAssertEqual(KeySoundStyle.resolve("system", customAvailable: false), .system)
        XCTAssertEqual(KeySoundStyle.resolve("vintage", customAvailable: false), .vintage)
        let miss = KeySoundSynth.bank("custom", custom: nil)
        XCTAssertEqual(miss.style, .subtle)
        XCTAssertEqual(miss.samples[0], KeySoundSynth.samples(.subtle, .letter))
        let c: [Float] = [0, 0.5, -0.5, 0]
        let hit = KeySoundSynth.bank("custom", custom: c)
        XCTAssertEqual(hit.style, .custom)
        XCTAssertEqual(hit.samples[0], c)
        XCTAssertEqual(hit.samples.count, 3)
        // File vắng/hỏng ⇒ load nil ⇒ mặc định.
        let dir = tmpDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent(KeySoundCustom.fileName)
        XCTAssertNil(KeySoundCustom.load(f))
        try? Data("not a wav".utf8).write(to: f)
        XCTAssertNil(KeySoundCustom.load(f))
        XCTAssertEqual(KeySoundSynth.bank("custom", custom: KeySoundCustom.load(f)).style, .subtle)
    }

    func testWavRoundTrip() {
        let s = KeySoundSynth.samples(.wood, .delete)
        let w = KeySoundSynth.wav(s)
        XCTAssertEqual(w.count, 44 + s.count * 2)
        let back = KeySoundSynth.parseWav(w)!
        XCTAssertEqual(back.sampleRate, 44_100)
        XCTAssertEqual(back.samples.count, s.count)
        for (a, b) in zip(s, back.samples) { XCTAssertEqual(a, b, accuracy: 1.0 / 16_000) }
        XCTAssertNil(KeySoundSynth.parseWav(Data([1, 2, 3])))
    }

    // MARK: âm tự chọn

    private func tmpDir() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("ks-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// Ghi file thử bằng AVAudioFile: stereo 48 kHz, lặng `lead` s rồi sine `tone` s biên độ `amp`.
    private func writeTestFile(_ url: URL, lead: Double, tone: Double, amp: Float, freq: Double = 440) throws {
        let rate = 48_000.0
        let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        let n = Int((lead + tone) * rate)
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n))!
        buf.frameLength = AVAudioFrameCount(n)
        for c in 0..<2 {
            let p = buf.floatChannelData![c]
            for i in 0..<n {
                let t = Double(i) / rate - lead
                p[i] = t < 0 ? 0 : amp * Float(sin(2 * .pi * freq * t))
            }
        }
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate,
                                       AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16,
                                       AVLinearPCMIsFloatKey: false]
        try? FileManager.default.removeItem(at: url)
        let f = try AVAudioFile(forWriting: url, settings: settings)
        try f.write(from: buf)
    }

    /// File dài + to + có lặng đầu ⇒ bỏ lặng, cắt ≤ 300 ms (báo cắt), đỉnh/RMS an toàn.
    func testCustomImportTrimsCapsNormalizes() throws {
        let d = tmpDir(); defer { try? FileManager.default.removeItem(at: d) }
        let src = d.appendingPathComponent("long.wav"), dst = d.appendingPathComponent(KeySoundCustom.fileName)
        try writeTestFile(src, lead: 0.25, tone: 0.8, amp: 1.0)
        let o = try KeySoundImport.importFile(src, to: dst)
        XCTAssertTrue(o.truncated)
        XCTAssertLessThanOrEqual(o.duration, 0.3 + 1e-3)
        XCTAssertGreaterThan(o.duration, 0.29)
        let s = try XCTUnwrap(KeySoundCustom.load(dst))
        let peak = s.map(abs).max() ?? 0
        XCTAssertLessThanOrEqual(peak, KeySoundCustom.targetPeak + 1e-3)
        XCTAssertLessThanOrEqual(KeySoundSynth.rms(s), KeySoundCustom.maxRMS + 1e-3)
        // Lặng đầu đã bỏ: 5 ms đầu đã có tiếng.
        XCTAssertGreaterThan(s[..<220].map(abs).max() ?? 0, 0.05)
        XCTAssertEqual(s.last ?? 1, 0, accuracy: 1e-3)   // đóng mềm
        // Khoá bộ mẫu đổi khi file đổi ⇒ bàn phím nạp lại.
        let k1 = KeySoundCustom.bankKey(style: "custom", customURL: dst)
        try writeTestFile(src, lead: 0, tone: 0.05, amp: 0.05)
        try KeySoundImport.importFile(src, to: dst)
        XCTAssertNotEqual(k1, KeySoundCustom.bankKey(style: "custom", customURL: dst))
        XCTAssertEqual(KeySoundCustom.bankKey(style: "wood", customURL: dst), "wood")
    }

    /// Click ngắn + nhỏ ⇒ không cắt, được nâng lên đỉnh chuẩn.
    func testCustomImportShortQuietIsBoosted() throws {
        let d = tmpDir(); defer { try? FileManager.default.removeItem(at: d) }
        let src = d.appendingPathComponent("tick.wav"), dst = d.appendingPathComponent(KeySoundCustom.fileName)
        try writeTestFile(src, lead: 0.02, tone: 0.03, amp: 0.05, freq: 300)
        let o = try KeySoundImport.importFile(src, to: dst)
        XCTAssertFalse(o.truncated)
        XCTAssertLessThan(o.duration, 0.06)
        let s = try XCTUnwrap(KeySoundCustom.load(dst))
        // Nâng từ 0.05 lên; sine đặc ⇒ trần RMS (độ to ngang các kiểu có sẵn) giữ đỉnh dưới 0.8.
        let peak = s.map(abs).max() ?? 0
        XCTAssertGreaterThan(peak, 0.25); XCTAssertLessThanOrEqual(peak, KeySoundCustom.targetPeak + 1e-3)
        XCTAssertEqual(KeySoundSynth.rms(s), KeySoundCustom.maxRMS, accuracy: 0.01)
        XCTAssertEqual(KeySoundSynth.bank("custom", custom: s).style, .custom)
    }

    func testCustomImportErrors() throws {
        let d = tmpDir(); defer { try? FileManager.default.removeItem(at: d) }
        let silent = d.appendingPathComponent("silent.wav")
        try writeTestFile(silent, lead: 0.5, tone: 0, amp: 0)
        XCTAssertThrowsError(try KeySoundImport.importFile(silent, to: d.appendingPathComponent("o.wav"))) {
            XCTAssertEqual($0 as? KeySoundImport.Failure, .silent)
        }
        let junk = d.appendingPathComponent("junk.mp3")
        try Data(repeating: 7, count: 4000).write(to: junk)
        XCTAssertThrowsError(try KeySoundImport.importFile(junk, to: d.appendingPathComponent("o.wav"))) {
            XCTAssertEqual($0 as? KeySoundImport.Failure, .unreadable)
        }
        XCTAssertThrowsError(try KeySoundImport.importFile(junk, to: nil)) {
            XCTAssertEqual($0 as? KeySoundImport.Failure, .noStorage)
        }
        XCTAssertThrowsError(try KeySoundCustom.process([], sampleRate: 44_100))
    }

    func testResampleLength() {
        let x = [Float](repeating: 0.5, count: 48_000)
        XCTAssertEqual(KeySoundCustom.resample(x, from: 48_000, to: 44_100).count, 44_100)
        XCTAssertEqual(KeySoundCustom.resample(x, from: 44_100, to: 44_100).count, 48_000)
    }

    // MARK: nghe thử + pin

    func testPreviewThrottle() {
        var t = PreviewThrottle(interval: 0.12)
        XCTAssertTrue(t.shouldFire(value: 50, now: 0, final: false))
        XCTAssertFalse(t.shouldFire(value: 55, now: 0.05, final: false))   // quá sớm
        XCTAssertTrue(t.shouldFire(value: 55, now: 0.13, final: false))
        XCTAssertFalse(t.shouldFire(value: 55, now: 0.30, final: false))   // cùng giá trị khi kéo
        XCTAssertFalse(t.shouldFire(value: 55, now: 0.20, final: true))    // vừa phát đúng giá trị này
        XCTAssertTrue(t.shouldFire(value: 60, now: 0.21, final: true))     // thả ở giá trị mới ⇒ luôn phát
        XCTAssertTrue(t.shouldFire(value: 60, now: 0.50, final: true))     // thả sau lâu ⇒ phát lại
    }

    func testIdleDecision() {
        XCTAssertTrue(KeySound.idleDecision(now: 20, lastPlay: 10, timeout: 8).stop)
        let d = KeySound.idleDecision(now: 15, lastPlay: 10, timeout: 8)
        XCTAssertFalse(d.stop); XCTAssertEqual(d.recheck, 3, accuracy: 1e-9)
        XCTAssertEqual(KeySound.idleDecision(now: 17.99, lastPlay: 10, timeout: 8).recheck, 0.05, accuracy: 1e-9)
    }

    /// Nghỉ sau idle ⇒ engine dừng; phím kế tiếp khởi động lại nền (không chặn), rồi phát được.
    func testIdlePauseAndRestart() throws {
        let ks = KeySound.shared
        ks.debugWant(true)
        defer { ks.debugWant(false); ks.stopNow() }
        guard ks.startNow() else { throw XCTSkip("không có audio output trên máy test") }
        XCTAssertTrue(ks.isRunning)
        ks.debugSetLastPlay(ago: 100)
        ks.debugIdleCheck()
        XCTAssertFalse(ks.isRunning, "quá idleTimeout ⇒ engine nghỉ")
        let t0 = CACurrentMediaTime()
        _ = ks.play(.letter)                           // không chặn: chỉ hẹn khởi động lại
        XCTAssertLessThan(CACurrentMediaTime() - t0, 0.005)
        let deadline = Date().addingTimeInterval(3)
        while !ks.isRunning && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertTrue(ks.isRunning)
        XCTAssertTrue(ks.play(.delete))
    }

    func testStyleSettingLoad() {
        XCTAssertEqual(KeyboardSettings().keySoundStyle, "subtle")
        let d = UserDefaults(suiteName: "vt-keysound-style")!
        d.removePersistentDomain(forName: "vt-keysound-style")
        let saved = UserDefaultsProvider.shared
        UserDefaultsProvider.shared = d
        defer { UserDefaultsProvider.shared = saved; d.removePersistentDomain(forName: "vt-keysound-style") }
        d.set("mechanical", forKey: "keySoundStyle")
        XCTAssertEqual(KeyboardSettings.load().keySoundStyle, "mechanical")
        d.set("system", forKey: "keySoundStyle")
        XCTAssertEqual(KeyboardSettings.load().keySoundStyle, "system")
        d.set("loud", forKey: "keySoundStyle")
        XCTAssertEqual(KeyboardSettings.load().keySoundStyle, "subtle")
    }

    /// Sao lưu: 2 key đi qua khứ hồi; âm lượng ngoài phạm vi bị kẹp 0…100.
    func testBackupRoundTripAndClamp() throws {
        let p = BackupPayload(createdAt: nil, platform: "ios",
                              settings: ["keySound": .bool(true), "keySoundVolume": .int(35)],
                              shortcuts: [:], templates: nil, learnedWords: nil)
        XCTAssertEqual(try BackupCodec.decode(BackupCodec.encode(p)).settings, p.settings)
        let raw = #"{"format":"viettelex-backup","version":1,"minReaderVersion":1,"platform":"android","settings":{"keySound":true,"keySoundVolume":250}}"#
        let back = try BackupCodec.decode(Data(raw.utf8))
        XCTAssertEqual(back.settings?["keySoundVolume"], .int(100))
        XCTAssertEqual(back.settings?["keySound"], .bool(true))
        let st = #"{"format":"viettelex-backup","version":1,"minReaderVersion":1,"platform":"android","settings":{"keySoundStyle":"bubble"}}"#
        XCTAssertEqual(try BackupCodec.decode(Data(st.utf8)).settings?["keySoundStyle"], .string("bubble"))
        for id in ["system", "rock", "pop", "water", "vintage", "phao", "jingle", "piano", "dantranh", "trong", "boo", "guitar"] {
            let j = #"{"format":"viettelex-backup","version":1,"minReaderVersion":1,"platform":"android","settings":{"keySoundStyle":"\#(id)"}}"#
            XCTAssertEqual(try BackupCodec.decode(Data(j.utf8)).settings?["keySoundStyle"], .string(id), id)
        }
        let bad = #"{"format":"viettelex-backup","version":1,"minReaderVersion":1,"platform":"android","settings":{"keySoundStyle":"loud"}}"#
        XCTAssertNil(try BackupCodec.decode(Data(bad.utf8)).settings?["keySoundStyle"])
        let theme = #"{"format":"viettelex-backup","version":1,"minReaderVersion":1,"platform":"android","settings":{"keySoundStyle":"theme"}}"#
        XCTAssertNil(try BackupCodec.decode(Data(theme.utf8)).settings?["keySoundStyle"], "\"Theo giao diện\" đã bỏ")
    }

    /// Đo trên simulator: chi phí gọi play() ở đường nóng + độ trễ output engine báo.
    func testEngineStartAndPlayCost() throws {
        let ks = KeySound.shared
        ks.debugWant(true)
        defer { ks.debugWant(false); ks.stopNow() }
        let t0 = CACurrentMediaTime()
        guard ks.startNow() else { throw XCTSkip("không có audio output trên máy test") }
        let startMs = (CACurrentMediaTime() - t0) * 1000
        _ = ks.play(.letter)                                   // hâm nóng
        let n = 200
        let t1 = CACurrentMediaTime()
        for i in 0..<n { XCTAssertTrue(ks.play(KeySoundKind(rawValue: i % 3)!)) }
        let perUs = (CACurrentMediaTime() - t1) / Double(n) * 1e6
        let s = AVAudioSession.sharedInstance()
        print(String(format: "KEYSOUND start=%.1fms play=%.1fµs io=%.1fms out=%.1fms",
                     startMs, perUs, s.ioBufferDuration * 1000, s.outputLatency * 1000))
        XCTAssertLessThan(perUs, 1000)   // đường nóng < 1 ms/lần
    }
}
