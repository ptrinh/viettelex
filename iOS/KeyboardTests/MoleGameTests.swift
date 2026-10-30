// Theme "Đập chuột" (game "mole"): máy trạng thái thuần (thả / cửa sổ đập / nghỉ / một con một lúc), đoán phím sắp
// gõ (seed ⇒ tất định, không bao giờ phím chức năng), điểm + thống kê, bật CHỈ khi theme có "game":"mole" (+ Plus,
// không Nguồn điện thấp / VoiceOver), 0 lớp khi tắt, lớp chuột không chặn chạm (phím vẫn gõ), "éc" theo Âm thanh
// phím, âm "bop", theme JSON khứ hồi, chi phí mỗi phím ("MOLE-COST"). Số tham chiếu chung Android (MoleGameTests.kt).
import XCTest
import UIKit

final class MoleGameTests: XCTestCase {
    private var savedPaywall = false
    private var savedProvider: UserDefaults?
    private var savedSound = false
    private let suite = "vt-mole-tests"

    override func setUp() {
        super.setUp()
        savedPaywall = PlusGate.paywallEnabled
        PlusGate.paywallEnabled = false
        savedProvider = UserDefaultsProvider.shared
        savedSound = KeyboardView.customSoundEnabled
    }

    override func tearDown() {
        PlusGate.paywallEnabled = savedPaywall
        UserDefaultsProvider.shared = savedProvider
        KeyboardView.customSoundEnabled = savedSound
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    // MARK: máy trạng thái (thuần, mốc thời gian)

    /// Gõ đều 0,2 s/phím: con đầu ra khi thời gian gõ ≥ khoảng rút ngẫu nhiên ∈ [2, 6] s; chờ đặt thì không báo thêm.
    func testSpawnTimingFollowsTypingTime() {
        var g = MoleGame(seed: 42)
        let first = g.nextSpawn
        XCTAssertTrue((MoleGame.spawnMin...MoleGame.spawnMax).contains(first))
        var t = 0.0, spawnAt: Double?
        for _ in 0..<60 {
            t += 0.2
            if g.key(nil, at: t) == .spawn { spawnAt = t; break }
        }
        let s = try! XCTUnwrap(spawnAt)
        // Phím đầu không tính khe ⇒ con đầu ra ở phím thứ ceil(first / 0.2) + 1.
        XCTAssertEqual(s, 0.2 * (ceil(first / 0.2 - 1e-9) + 1), accuracy: 1e-9)
        XCTAssertTrue(g.pending)
        for _ in 0..<20 { t += 0.2; XCTAssertEqual(g.key("a", at: t), .none, "đang chờ đặt ⇒ không thả thêm") }
        g.place("a", at: t)
        XCTAssertEqual(g.mole, "a"); XCTAssertFalse(g.pending)
    }

    /// Cửa sổ đập: trúng trong upTime ⇒ hit (+ điểm, chuỗi); đúng phím nhưng hết giờ ⇒ thụt (trượt, chuỗi về 0);
    /// sai phím ⇒ không gì.
    func testHitWindowAndScoring() {
        var g = MoleGame(seed: 1)
        /// Gõ đều tới lúc thả rồi đặt chuột `k`; trả mốc đặt.
        func spawnNow(_ k: Character, _ t0: Double) -> Double {
            var x = t0
            while g.key(nil, at: x) != .spawn { x += 0.25 }
            g.place(k, at: x)
            return x
        }
        var t = spawnNow("n", 100)
        XCTAssertEqual(g.key("m", at: t + 0.5), .none, "sai phím")
        XCTAssertEqual(g.key("n", at: t + 1.49), .hit("n"))
        XCTAssertEqual(g.hits, 1); XCTAssertEqual(g.streak, 1); XCTAssertNil(g.mole)
        t = spawnNow("h", t + 1.6)
        XCTAssertEqual(g.key("h", at: t + 0.3), .hit("h"))
        XCTAssertEqual(g.streak, 2); XCTAssertEqual(g.bestStreak, 2)
        t = spawnNow("a", t + 0.4)
        XCTAssertEqual(g.key("x", at: t + 1.0), .none)
        XCTAssertEqual(g.key("a", at: t + 1.5), .duck, "hết upTime ⇒ trượt dù đúng phím")
        XCTAssertEqual(g.streak, 0); XCTAssertEqual(g.bestStreak, 2); XCTAssertEqual(g.misses, 1); XCTAssertEqual(g.hits, 2)
        // Phím không phải chữ (cách / xoá) không bao giờ đập.
        t = spawnNow("t", t + 1.6)
        XCTAssertEqual(g.key(nil, at: t + 0.2), .none)
        XCTAssertNotNil(g.mole)
    }

    /// Đồng hồ: hết upTime ⇒ thụt; nghỉ ≥ idleAfter ⇒ phím kế không thả (đếm lại từ đầu), không thụt hai lần.
    func testDuckAndIdleStop() {
        var g = MoleGame(seed: 3)
        var t = 0.0
        while g.key(nil, at: t) != .spawn { t += 0.25 }
        g.place("c", at: t)
        XCTAssertEqual(g.tick(at: t + 1.0), .none)
        XCTAssertEqual(g.tick(at: t + MoleGame.upTime), .duck)
        XCTAssertEqual(g.tick(at: t + 2), .none, "đã thụt")
        XCTAssertEqual(g.misses, 1)
        // Nghỉ 3,5 s rồi gõ tiếp: không thả, đếm lại.
        t += 5
        XCTAssertEqual(g.key("a", at: t), .none)
        XCTAssertEqual(g.typed, 0)
        // Nghỉ quá lâu ⇒ không bao giờ có chuột tự ra (chỉ thả khi có phím).
        var g2 = MoleGame(seed: 3)
        _ = g2.key(nil, at: 0)
        XCTAssertEqual(g2.tick(at: 100), .none)
        XCTAssertNil(g2.mole); XCTAssertFalse(g2.pending)
        // Chuột đang lên + nghỉ ⇒ phím sau quãng nghỉ = thụt (main bận, đồng hồ chưa chạy).
        var g3 = MoleGame(seed: 3)
        t = 0
        while g3.key(nil, at: t) != .spawn { t += 0.25 }
        g3.place("o", at: t)
        XCTAssertEqual(g3.key("o", at: t + 3.2), .duck)
    }

    /// Một con một lúc: suốt lúc chuột đang lên, gõ bao nhiêu cũng không báo `.spawn`; khe dài bị kẹp `gapCap`.
    func testOneAtATimeAndGapCap() {
        var g = MoleGame(seed: 9)
        var t = 0.0
        while g.key(nil, at: t) != .spawn { t += 0.1 }
        g.place("i", at: t)
        for _ in 0..<14 { t += 0.1; XCTAssertNotEqual(g.key("x", at: t), .spawn) }
        var h = MoleGame(seed: 9)
        _ = h.key(nil, at: 0)
        _ = h.key(nil, at: 2.5)                      // khe 2,5 s (< idleAfter) chỉ tính 1 s
        XCTAssertEqual(h.typed, MoleGame.gapCap, accuracy: 1e-12)
        // Đổi bảng phím: dẹp chuột không tính trượt.
        g.hide()
        XCTAssertNil(g.mole); XCTAssertEqual(g.misses, 0)
    }

    // MARK: đoán phím sắp gõ

    func testNextKeyFromPrefixAndCandidates() {
        var r = FxRandom(seed: 5)
        XCTAssertEqual(MoleTarget.next(prefix: "nh", candidates: ["nhưng", "nhà"], rng: &r), "u")
        XCTAssertEqual(MoleTarget.next(prefix: "", candidates: ["đi", "được"], rng: &r), "d", "đầu từ kế tiếp")
        XCTAssertEqual(MoleTarget.next(prefix: "Đư", candidates: ["Đường"], rng: &r), "o", "bỏ dấu + thường hoá")
        XCTAssertEqual(MoleTarget.next(prefix: "cá", candidates: ["cá", "cái"], rng: &r), "i", "ứng viên bằng tiền tố bị bỏ qua")
        XCTAssertEqual(MoleTarget.next(prefix: "xa", candidates: ["nhà", "xa1", "xa ", "xanh"], rng: &r), "n",
                       "không khớp / không phải a–z ⇒ ứng viên sau")
        XCTAssertEqual(MoleTarget.fold("Nguyễn Đức"), "nguyen duc")
        // Không ứng viên ⇒ chữ phổ biến; luôn a–z; bộ lọc phím có thật được tôn trọng.
        for seed in 0..<200 {
            var q = FxRandom(seed: seed)
            let c = MoleTarget.next(prefix: "zzz", candidates: [], rng: &q)
            XCTAssertTrue(MoleTarget.isAZ(c)); XCTAssertTrue(MoleTarget.common.contains(c))
            var q2 = FxRandom(seed: seed)
            XCTAssertEqual(MoleTarget.next(prefix: "", candidates: ["123"], rng: &q2, allowed: { $0 == "t" }), "t")
        }
        XCTAssertFalse(MoleTarget.isAZ(" ")); XCTAssertFalse(MoleTarget.isAZ("1")); XCTAssertFalse(MoleTarget.isAZ("é"))
    }

    /// Seed ⇒ tất định; số tham chiếu chung Android (MoleGameTests.kt seededParity).
    func testSeededDeterminismParity() {
        var a = MoleGame(seed: 2026), b = MoleGame(seed: 2026)
        XCTAssertEqual(a.nextSpawn, b.nextSpawn)
        var picks = ""
        for _ in 0..<12 { picks.append(a.chooseTarget(prefix: "", candidates: [])) }
        var picks2 = ""
        for _ in 0..<12 { picks2.append(b.chooseTarget(prefix: "", candidates: [])) }
        XCTAssertEqual(picks, picks2)
        print("MOLE-GOLDEN nextSpawn(2026)=\(String(format: "%.6f", MoleGame(seed: 2026).nextSpawn)) picks=\(picks)")
        XCTAssertEqual(MoleGame(seed: 2026).nextSpawn, Self.goldenNextSpawn, accuracy: 1e-6)
        XCTAssertEqual(picks, Self.goldenPicks)
    }
    static let goldenNextSpawn = 4.39127183947509
    static let goldenPicks = "ttnmmdyhmntc"

    // MARK: thống kê

    func testStatsRecordDayRolloverAndPersistence() {
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        XCTAssertEqual(MoleStats.load(d), MoleStats())
        var s = MoleStats()
        s.record(hits: 1, streak: 1, day: 20261019)
        s.record(hits: 1, streak: 2, day: 20261019)
        XCTAssertEqual(s.count(on: 20261019), 2); XCTAssertEqual(s.best, 2)
        s.record(hits: 1, streak: 1, day: 20261020)
        XCTAssertEqual(s.count(on: 20261020), 1, "ngày mới đếm lại")
        XCTAssertEqual(s.count(on: 20261019), 0)
        XCTAssertEqual(s.total, 3); XCTAssertEqual(s.best, 2)
        s.save(d)
        XCTAssertEqual(MoleStats.load(d), s)
        XCTAssertEqual(MoleStats.dayNumber(Date(timeIntervalSince1970: 0), calendar: Calendar(identifier: .gregorian).with(tz: "UTC")), 19700101)
        XCTAssertEqual(L10n.en["Đập chuột"], "Whack-a-mole")
        XCTAssertNotNil(L10n.en["Hôm nay đập %@ con chuột 🐭"])
        XCTAssertNotNil(L10n.en["Chuỗi dài nhất: %@ · Tổng: %@"])
    }

    // MARK: bật / tắt theo theme

    func testPolicy() {
        XCTAssertTrue(MolePolicy.active(game: "mole", plus: true, lowPower: false, voiceOver: false))
        XCTAssertFalse(MolePolicy.active(game: nil, plus: true, lowPower: false, voiceOver: false))
        XCTAssertFalse(MolePolicy.active(game: "other", plus: true, lowPower: false, voiceOver: false))
        XCTAssertFalse(MolePolicy.active(game: "mole", plus: false, lowPower: false, voiceOver: false))
        XCTAssertFalse(MolePolicy.active(game: "mole", plus: true, lowPower: true, voiceOver: false), "Nguồn điện thấp")
        XCTAssertFalse(MolePolicy.active(game: "mole", plus: true, lowPower: false, voiceOver: true), "VoiceOver")
        XCTAssertTrue(MolePolicy.shouldSqueak(customSound: true))
        XCTAssertFalse(MolePolicy.shouldSqueak(customSound: false))
    }

    /// Theme "Đập chuột": bãi cỏ + phím hang đất, chữ kem ≥ 4.5:1, âm "bop", game "mole", Plus; theme khác không có game.
    func testMoleThemeSpecAndContrast() throws {
        let t = KeyboardTheme.mole
        let spec = try XCTUnwrap(t.spec)
        XCTAssertEqual(spec.game, "mole"); XCTAssertEqual(spec.sound, "bop"); XCTAssertNil(spec.effect)
        XCTAssertEqual(spec.nameEn, "Whack-a-mole")
        XCTAssertTrue(t.isPlus)
        XCTAssertEqual(KeyboardTheme.allCases[KeyboardTheme.allCases.firstIndex(of: .neutral)! - 1], .mole, "thêm CUỐI (sau đó: Xám trung tính)")
        XCTAssertEqual(ThemeSettings(theme: .mole).effectiveKeyStyle.game, "mole")
        for o in KeyboardTheme.allCases where o != .mole {
            XCTAssertNil(ThemeSettings(theme: o).effectiveKeyStyle.game, o.rawValue)
        }
        for dark in [false, true] {
            let p = t.palette(systemDark: dark)
            let bg = try XCTUnwrap(p.background)
            XCTAssertGreaterThanOrEqual(RGBA.contrast(p.ink, p.keyFill.over(bg)), 4.5, "chữ / phím")
            XCTAssertGreaterThanOrEqual(RGBA.contrast(p.fnInk, p.fnFill.over(bg)), 4.5, "chữ / phím chức năng")
            XCTAssertGreaterThanOrEqual(RGBA.contrast(p.accentInk, p.accent.over(bg)), 4.5, "chữ / nhấn")
            XCTAssertEqual(p.decoration?.motif, .flowers)
            XCTAssertTrue(p.isDark)
        }
        XCTAssertTrue(ThemeSpecParser.contrastIssues(spec).isEmpty)
    }

    /// "game" trong JSON: chỉ "mole"; khứ hồi (chép / dán / chuẩn hoá / bản vá KeyStyle); theme tự tạo bật được trò.
    func testThemeJSONGameRoundTrip() throws {
        let text = try XCTUnwrap(ThemeJSONActions.copyText(.builtin(.mole), settings: ThemeSettings(theme: .mole), store: [:]))
        XCTAssertTrue(text.contains("\"game\""), text)
        let back = try XCTUnwrap(ThemeSpecParser.parse(text).spec)
        XCTAssertEqual(back.game, "mole"); XCTAssertEqual(back.sound, "bop")
        XCTAssertEqual(ThemeSpecParser.parse(back.json.canonical).spec, back)
        let base = ##"{"v":1,"name":{"vi":"x"},"light":{"key":"#FFFFFF","special":"#DDDDDD","ink":"#000000","accent":"#000000"}"##
        XCTAssertEqual(ThemeSpecParser.parse(base + #","game":"mole"}"#).spec?.game, "mole")
        XCTAssertEqual(ThemeSpecParser.parse(base + #","game":"tetris"}"#).errors.map(\.code), [.badValue])
        XCTAssertEqual(ThemeSpecParser.parse(base + #","game":1}"#).errors.map(\.code), [.wrongType])
        XCTAssertNil(ThemeSpecParser.parse(base + "}").spec?.game)
        // Theme tự tạo có "game":"mole" ⇒ kiểu thực dùng mang game (bàn phím bật trò).
        var custom = try XCTUnwrap(ThemeSpecParser.parse(base + #","game":"mole"}"#).spec)
        custom.id = "my-mole"
        var s = ThemeSettings()
        s.select(custom: custom)
        XCTAssertEqual(s.effectiveKeyStyle.game, "mole")
        // Bản vá theme có sẵn (KeyStyleStore) giữ "game".
        var st = KeyStyle(); st.game = "mole"
        let raw = KeyStyleStore.serialize(["sky": st])
        XCTAssertEqual(raw, #"{"sky":{"game":"mole"}}"#)
        XCTAssertEqual(KeyStyleStore.parse(raw)["sky"]?.game, "mole")
        var sky = ThemeSettings(theme: .sky); sky.setStyle(st, for: .sky)
        XCTAssertEqual(sky.effectiveKeyStyle.game, "mole")
        XCTAssertTrue(ThemeExtraIds.games == ["mole"])
    }

    // MARK: bàn phím thật

    @MainActor private func keyboard(_ theme: KeyboardTheme, in win: UIWindow? = nil,
                                     onKey: @escaping (KeyboardView.Key) -> Void = { _ in }) -> KeyboardView {
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        d.set(theme.rawValue, forKey: ThemeSettings.themeKey)
        UserDefaultsProvider.shared = d
        let kb = KeyboardView(needsGlobe: false, inputController: nil, onKey: onKey)
        let host: UIView = win ?? UIView(frame: CGRect(x: 0, y: 0, width: 402, height: 400))
        host.addSubview(kb)
        kb.frame = CGRect(x: 0, y: 0, width: 402, height: 290)
        kb.applyAppearance(.dark, style: .dark)
        kb.setNeedsLayout(); kb.layoutIfNeeded()
        return kb
    }

    private static func moleViews(_ v: UIView) -> Int {
        (v is MoleOverlayView ? 1 : 0) + v.subviews.reduce(0) { $0 + moleViews($1) }
    }

    /// 0 lớp khi tắt: mọi theme khác (và Đập chuột khi hết Plus) ⇒ không có overlay, không mẫu "éc".
    @MainActor func testOnlyMoleThemeCreatesOverlay() throws {
        for t in KeyboardTheme.allCases where t != .mole {
            let kb = keyboard(t)
            XCTAssertNil(kb.mole, "\(t): 0 lớp")
            XCTAssertEqual(Self.moleViews(kb), 0, t.rawValue)
        }
        let kb = keyboard(.mole)
        let v = try XCTUnwrap(kb.mole)
        XCTAssertGreaterThan(v.layerCount, 10)
        XCTAssertFalse(v.isMoleUp)
        // Hết Plus (paywall bật, chưa mua) ⇒ theme về Hệ thống ⇒ không có overlay.
        PlusGate.paywallEnabled = true
        let saved = PlusGate.defaults
        PlusGate.defaults = UserDefaults(suiteName: suite + "-plus")!
        defer { PlusGate.defaults = saved; UserDefaults(suiteName: suite + "-plus")?.removePersistentDomain(forName: suite + "-plus") }
        XCTAssertNil(keyboard(.mole).mole, "hết Plus ⇒ tắt")
    }

    /// Lớp chuột không chặn chạm: hitTest nil, phím dưới chuột vẫn gõ đúng chữ; gõ trúng ⇒ đập + thống kê.
    @MainActor func testOverlayNeverBlocksTouchesAndHitScores() throws {
        let win = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 400))
        win.isHidden = false
        defer { win.isHidden = true }
        var typed: [String] = []
        let kb = keyboard(.mole, in: win) { k in if case .letter(let c) = k { typed.append(String(c)) } }
        let v = try XCTUnwrap(kb.mole)
        v.statsDefaults = UserDefaults(suiteName: suite)
        KeyboardView.customSoundEnabled = false
        let mole = forceSpawn(v, on: "a")
        XCTAssertEqual(mole, "a")
        XCTAssertTrue(v.isMoleUp)
        XCTAssertFalse(v.debugHolderHidden)
        let f = try XCTUnwrap(kb.debugLetterFrame("a"))
        XCTAssertEqual(v.debugHolderFrame.midX, f.midX, accuracy: 1, "chuột trên đúng phím")
        XCTAssertFalse(v.isUserInteractionEnabled)
        XCTAssertNil(v.hitTest(CGPoint(x: f.midX, y: f.midY), with: nil))
        XCTAssertNotEqual(kb.hitTest(CGPoint(x: f.midX, y: f.midY), with: nil), v)
        kb.debugTapLetter("a", at: CACurrentMediaTime())
        XCTAssertEqual(typed.map { $0.lowercased() }, ["a"], "phím vẫn gõ (đầu câu ⇒ A)")
        KeyboardBenchTests.spin(0.05)
        XCTAssertEqual(v.game.hits, 1)
        XCTAssertEqual(v.debugBonks, 1)
        XCTAssertFalse(v.isMoleUp)
        XCTAssertEqual(MoleStats.load(UserDefaults(suiteName: suite)).count(on: MoleStats.dayNumber()), 1)
        // Trượt: chuột tự thụt sau upTime, hộp ẩn.
        _ = forceSpawn(v, on: "e")
        KeyboardBenchTests.spin(MoleGame.upTime + 0.4)
        XCTAssertFalse(v.isMoleUp)
        XCTAssertTrue(v.debugHolderHidden)
        XCTAssertEqual(v.game.misses, 1)
        // Ẩn bàn phím ⇒ dừng.
        _ = forceSpawn(v, on: "o")
        kb.removeFromSuperview()
        XCTAssertFalse(v.isMoleUp)
    }

    /// "Éc" theo Âm thanh phím: tắt ⇒ không phát; bật ⇒ phát (qua KeySound). Mẫu "éc" + "bop" nhỏ hơn Gõ gỗ.
    @MainActor func testSqueakRespectsKeySoundSetting() throws {
        let kb = keyboard(.mole)
        let v = try XCTUnwrap(kb.mole)
        v.statsDefaults = UserDefaults(suiteName: suite)
        KeyboardView.customSoundEnabled = false
        _ = forceSpawn(v, on: "n")
        v.bonk("n")
        XCTAssertEqual(v.debugSqueaks, 0, "Âm thanh phím tắt ⇒ im")
        KeyboardView.customSoundEnabled = true
        _ = forceSpawn(v, on: "n")
        v.bonk("n")
        XCTAssertEqual(v.debugSqueaks, 1)
        // Mẫu: tất định, êm (đỉnh + RMS ≤ Gõ gỗ), đầu/cuối 0.
        let sq = KeySoundSynth.squeakSamples()
        XCTAssertEqual(sq, KeySoundSynth.squeakSamples())
        XCTAssertEqual(sq.count, Int((0.130 * KeySoundSynth.sampleRate).rounded()))
        let wood = KeySoundSynth.samples(.wood, .letter)
        XCTAssertLessThanOrEqual(sq.map(abs).max() ?? 1, wood.map(abs).max() ?? 0)
        print("MOLE-GOLDEN squeak=\(String(format: "%.4f", sq.reduce(0.0) { $0 + Double(abs($1)) })) bop=\(KeySoundKind.allCases.map { k in String(format: "%.4f", KeySoundSynth.samples(.bop, k).reduce(0.0) { $0 + Double(abs($1)) }) })")
        XCTAssertEqual(sq.reduce(0.0) { $0 + Double(abs($1)) }, Self.goldenSqueak, accuracy: 0.01)
        for k in KeySoundKind.allCases {
            let b = KeySoundSynth.samples(.bop, k), w = KeySoundSynth.samples(.wood, k)
            XCTAssertLessThan(KeySoundSynth.rms(b), KeySoundSynth.rms(w), "\(k)")
            XCTAssertLessThan(b.map(abs).max() ?? 1, w.map(abs).max() ?? 0, "\(k)")
            XCTAssertLessThan(KeySoundSynth.spectralCentroid(b), 700, "bop trầm êm \(k)")
            XCTAssertEqual(b.reduce(0.0) { $0 + Double(abs($1)) }, Self.goldenBop[k.rawValue], accuracy: 0.01, "\(k)")
        }
        XCTAssertEqual(L10n.en["Búa gỗ"], "Mallet bop")
        // KeySound: chỉ dựng mẫu "éc" khi theme bật trò (engine chưa có ⇒ chưa dựng gì).
        KeySound.shared.setSqueakEnabled(false)
        XCTAssertFalse(KeySound.shared.hasSqueak)
    }
    static let goldenSqueak = 534.9296
    static let goldenBop: [Double] = [171.8268, 181.9607, 215.5216]

    /// Chi phí main thread mỗi phím do trò chơi (MoleOverlayView.typed) — gồm cả phím thả / trúng. In "MOLE-COST".
    @MainActor func testCostPerKey() throws {
        let win = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 400))
        win.isHidden = false
        defer { win.isHidden = true }
        let kb = keyboard(.mole, in: win)
        let v = try XCTUnwrap(kb.mole)
        v.statsDefaults = UserDefaults(suiteName: suite)
        let keys = Array("xinchaomoinguoihomnaytoiddilamvieccongty")
        var costs: [Double] = []
        for _ in 0..<6 {
            for c in keys {
                guard let f = kb.debugLetterFrame(String(c)) else { continue }
                MoleOverlayView.debugCost = 0
                kb.benchTap(at: CGPoint(x: f.midX, y: f.midY), time: CACurrentMediaTime())
                costs.append(MoleOverlayView.debugCost * 1000)
                KeyboardBenchTests.spin(0.06)
            }
        }
        // Thuần: 100k phím của máy trạng thái.
        var g = MoleGame(seed: 1)
        let t0 = CACurrentMediaTime()
        var t = 0.0
        for i in 0..<100_000 {
            t += 0.15
            if g.key(i % 7 == 0 ? nil : "a", at: t) == .spawn { g.place("b", at: t) }
        }
        let pure = (CACurrentMediaTime() - t0) / 100_000 * 1e6
        let p = KeyboardBenchTests.pct
        let line = String(format: "MOLE-COST typed p50=%.4f p95=%.4f max=%.4f ms/phím (n=%d, chuột ra %d lần) | máy trạng thái thuần %.3f µs/phím",
                          p(costs, 0.5), p(costs, 0.95), costs.max() ?? 0, costs.count, v.game.spawns, pure)
        print(line)
        XCTContext.runActivity(named: line) { _ in }
        XCTAssertGreaterThan(v.game.spawns, 0, "đã thả chuột trong lúc gõ")
        XCTAssertLessThan(p(costs, 0.95), 0.1, "< 0,1 ms/phím")
    }

    // MARK: ảnh chụp (chuột lên / bị đập) — chỉ khi VT_MOLE_SHOTS=<thư mục>

    @MainActor func testScreenshots() throws {
        guard let dir = ProcessInfo.processInfo.environment["VT_MOLE_SHOTS"] else { throw XCTSkip("VT_MOLE_SHOTS chưa đặt") }
        let win = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 400))
        win.isHidden = false
        defer { win.isHidden = true }
        let kb = keyboard(.mole, in: win)
        let v = try XCTUnwrap(kb.mole)
        v.statsDefaults = UserDefaults(suiteName: suite)
        func shot(_ name: String) throws {
            let r = UIGraphicsImageRenderer(bounds: kb.bounds)
            let img = r.image { kb.layer.render(in: $0.cgContext) }
            try img.pngData()?.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
        }
        _ = forceSpawn(v, on: "h")
        KeyboardBenchTests.spin(0.4)
        try shot("mole-up.png")
        v.debugPoseBonk()                            // render(in:) vẽ model ⇒ dựng khung giữa lúc bẹp
        try shot("mole-bonk.png")
    }

    /// Ép thả chuột ngay trên `c` (đường thật: spawn → đoán phím từ ứng viên → keyFrame → vẽ).
    @MainActor private func forceSpawn(_ v: MoleOverlayView, on c: Character) -> Character? {
        v.debugForceSpawn(prefix: "", candidates: [String(c) + "zz"])
        return v.debugSpawnKey
    }
}

private extension Calendar {
    func with(tz: String) -> Calendar { var c = self; c.timeZone = TimeZone(identifier: tz)!; return c }
}
