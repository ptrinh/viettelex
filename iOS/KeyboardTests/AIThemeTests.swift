// Theme "AI" (11/2026): hiệu ứng Token AI (TokenStream + ShimmerGate), Mắt AI (AIEye, nhân vật BuddyCharacter.ai),
// motif "neural", "borderFx":"aurora" (AuroraFx), âm "ai". Số tham chiếu GIỐNG HỆT android AIThemeTests.kt /
// AIThemeViewTest.kt. Ảnh xem thử: đặt VT_THEME_SNAPSHOT_DIR (TEST_RUNNER_VT_THEME_SNAPSHOT_DIR=…).
import XCTest
import UIKit

final class AIThemeTests: XCTestCase {
    private let suite = "vt-ai-theme"
    private let plusSuite = "vt-ai-theme-plus"
    private var savedPaywall = false
    private var savedDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        savedPaywall = PlusGate.paywallEnabled
        savedDefaults = PlusGate.defaults
        UserDefaults(suiteName: plusSuite)!.removePersistentDomain(forName: plusSuite)
        PlusGate.defaults = UserDefaults(suiteName: plusSuite)!
        #if DEBUG
        KeyEffectOverlay.drawsOffscreen = true
        #endif
    }

    override func tearDown() {
        PlusGate.paywallEnabled = savedPaywall
        PlusGate.defaults = savedDefaults
        UserDefaults(suiteName: plusSuite)!.removePersistentDomain(forName: plusSuite)
        #if DEBUG
        KeyEffectOverlay.drawsOffscreen = false
        #endif
        super.tearDown()
    }

    // MARK: Token AI — model

    func testTokensEffectIdAndHooks() {
        XCTAssertEqual(KeyEffect.allCases.firstIndex(of: .sea)! + 1, KeyEffect.allCases.firstIndex(of: .tokens)!)   // thêm sau Biển (Night Club theo sau)
        XCTAssertEqual(KeyEffect.tokens.rawValue, "tokens")
        XCTAssertEqual(KeyEffect.parse("tokens"), .tokens)
        XCTAssertTrue(KeyEffect.tokens.isPlus)
        XCTAssertTrue(KeyEffect.tokens.isQueued)
        XCTAssertTrue(KeyEffect.tokens.needsComposeDiff)
        XCTAssertFalse(KeyEffect.tokens.needsBoundaryWord)
        XCTAssertFalse(KeyEffect.tokens.isParticle)
        XCTAssertEqual(KeyEffect.tokens.band, .aboveKeys)
        XCTAssertTrue(KeyEffectOverlay.clipped.contains(.tokens), "cắt theo bàn phím (#151)")
        XCTAssertEqual(L10n.en["Token AI"], "AI tokens")
        XCTAssertTrue(ThemeExtraIds.effects.contains("tokens"))
    }

    func testTokenChipCountAndCaps() {
        let want: [String: Int] = ["b": 3, "a": 4, "đ": 4, "á": 5, "ế": 6, "ợ": 6, "ơ": 5, "": 3, "7": 4, ",": 3]
        for (g, n) in want { XCTAssertEqual(TokenStream.chipCount(g), n, g) }
        for c in "aăâbcdđeêghiklmnoôơpqrstuưvxyáàảãạấầẩẫậếềểễệốồổỗộớờởỡợứừửữựíìỉĩị" {
            XCTAssertTrue((TokenStream.minChips...TokenStream.maxChips).contains(TokenStream.chipCount(String(c))), String(c))
        }
        XCTAssertEqual(TokenStream.cap, 24)
        XCTAssertEqual(TokenStream.lifetime, 0.08 + 5 * 0.035 + 0.55, accuracy: 1e-9)
        XCTAssertEqual(TokenStream.colors.count, 3)
    }

    /// Mốc chung android tokenPathParity: phím (100,150) → đích (195,22), 5 chip, khung 390×260.
    func testTokenPathParity() {
        let want: [(Double, Double, Double, Double)] = [(88, 150, 138.2776, 83.3063), (94, 150, 133.7842, 77.5446),
                                                        (100, 150, 128.9507, 72.2329), (106, 150, 123.7753, 67.4180),
                                                        (112, 150, 118.2602, 63.1492)]
        for i in 0..<5 {
            let s = TokenStream.start(key: (100, 150), chip: i, of: 5, width: 390, height: 260)
            let c = TokenStream.control(from: s, to: (195, 22), chip: i, of: 5, width: 390, height: 260)
            XCTAssertEqual(s.x, want[i].0, accuracy: 1e-4); XCTAssertEqual(s.y, want[i].1, accuracy: 1e-4)
            XCTAssertEqual(c.x, want[i].2, accuracy: 1e-4); XCTAssertEqual(c.y, want[i].3, accuracy: 1e-4)
        }
        var c = TokenStream.control(from: (300, 200), to: (300, 20), chip: 0, of: 3, width: 390, height: 260)
        XCTAssertEqual(c.x, 304.2, accuracy: 1e-4); XCTAssertEqual(c.y, 110, accuracy: 1e-4)
        c = TokenStream.control(from: (380, 5), to: (10, 5), chip: 2, of: 3, width: 390, height: 260)
        XCTAssertEqual(c.x, 195, accuracy: 1e-4); XCTAssertEqual(c.y, 2, accuracy: 1e-4)
        let p0 = TokenStream.point((1, 2), (3, 4), (5, 6), t: 0), p1 = TokenStream.point((1, 2), (3, 4), (5, 6), t: 1)
        XCTAssertEqual(p0.x, 1); XCTAssertEqual(p0.y, 2); XCTAssertEqual(p1.x, 5); XCTAssertEqual(p1.y, 6)
        XCTAssertEqual(TokenStream.ease(0.5), 0.25, accuracy: 1e-12)
        XCTAssertEqual(TokenStream.alpha(-0.1), 0); XCTAssertEqual(TokenStream.alpha(0.5), 1)
        XCTAssertEqual(TokenStream.alpha(1), 0, accuracy: 1e-12)
        XCTAssertEqual(TokenStream.scale(1), TokenStream.endScale, accuracy: 1e-12)
    }

    /// Mọi điểm trên mọi đường bay (phím sát mép / góc, đích ngoài khung) nằm TRONG bàn phím — bao lồi Bézier.
    func testTokenPathsStayInsideKeyboard() {
        let w = 390.0, h = 260.0
        let keys: [(Double, Double)] = [(0, 0), (390, 0), (0, 260), (390, 260), (195, 130), (20, 240), (370, 10)]
        let targets: [(Double, Double)] = [(195, 22), (-50, -50), (500, 10), (370, 20), (10, 250)]
        for k in keys { for t0 in targets { for n in 3...6 { for i in 0..<n {
            let t = TokenStream.clamp(t0, width: w, height: h)
            let s = TokenStream.start(key: k, chip: i, of: n, width: w, height: h)
            let c = TokenStream.control(from: s, to: t, chip: i, of: n, width: w, height: h)
            for j in 0...20 {
                let p = TokenStream.point(s, c, t, t: Double(j) / 20)
                XCTAssertTrue(p.x >= TokenStream.inset - 1e-9 && p.x <= w - TokenStream.inset + 1e-9, "\(k)→\(t0) #\(i)")
                XCTAssertTrue(p.y >= TokenStream.inset - 1e-9 && p.y <= h - TokenStream.inset + 1e-9, "\(k)→\(t0) #\(i)")
            }
        } } } }
    }

    /// Vệt sáng chỉ khi gợi ý đổi thật — mốc chung android shimmerTriggersOnlyOnChange.
    func testShimmerTriggersOnlyOnChange() {
        var g = ShimmerGate()
        XCTAssertFalse(g.update([], at: 10), "rỗng ⇒ không")
        XCTAssertTrue(g.update(["xin", "chào"], at: 10))
        XCTAssertFalse(g.update(["xin", "chào"], at: 10.1), "y nguyên ⇒ không")
        XCTAssertFalse(g.update(["xin", "chào", "bạn"], at: 10.2), "đổi quá dồn ⇒ bỏ")
        XCTAssertFalse(g.update(["xin", "chào", "bạn"], at: 20), "y nguyên (đã ghi lần bỏ) ⇒ không")
        XCTAssertTrue(g.update(["cảm", "ơn"], at: 20))
        XCTAssertFalse(g.update(["cảm", "ơn"], at: 30))
        XCTAssertFalse(g.update([], at: 31), "về rỗng ⇒ không quét")
        XCTAssertTrue(g.update(["cảm", "ơn"], at: 32), "rỗng → có lại ⇒ quét")
        g.reset(); XCTAssertTrue(g.update(["cảm", "ơn"], at: 32.1))
        XCTAssertEqual(ShimmerGate.left(0, width: 300), -0.35 * 300, accuracy: 1e-9)
        XCTAssertEqual(ShimmerGate.left(1, width: 300), 300, accuracy: 1e-9)
        XCTAssertEqual(ShimmerGate.duration, 0.3)
    }

    // MARK: Token AI — overlay

    /// Host dời gốc bounds (#151): chùm token dùng chung hệ toạ độ, cắt theo bàn phím, đích nằm trong khung; pool có trần;
    /// không có chữ ⇒ không hẹn vẽ.
    @MainActor func testTokenOverlayInsideKeyboardAndCapped() throws {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 470))
        host.bounds.origin.y = -180
        let o = try XCTUnwrap(KeyEffectOverlay.install(.tokens, color: .systemPurple, in: host, existing: nil))
        XCTAssertEqual(o.frame, host.bounds)
        XCTAssertEqual(o.bounds.origin, host.bounds.origin)
        XCTAssertTrue(o.clipsToBounds)
        o.tokenTarget = { CGPoint(x: 195, y: -500) }   // đích ngoài khung ⇒ kẹp vào trong
        o.emit(key: CGRect(x: 50, y: 100, width: 34, height: 42))
        XCTAssertFalse(o.debugScheduled, "chưa có chữ ⇒ không hẹn vẽ")
        let glyphs = ["ế", "b", "ợ", "a", "á", "đ", "ế", "ơ", "x", "y"]
        for (i, g) in glyphs.enumerated() {
            o.queueToken(g)
            o.emit(key: CGRect(x: CGFloat(i % 10) * 39, y: CGFloat(i % 3) * 90, width: 34, height: 42)); o.flush()
        }
        XCTAssertEqual(o.debugTokenRoots.count, TokenStream.pool, "pool chùm dùng lại")
        XCTAssertLessThanOrEqual(o.debugTokenChipCounts.reduce(0, +), TokenStream.cap)
        // Chùm xoay vòng: 10 lần bắn vào pool 4 ⇒ ô 1 = lần cuối ("y"), ô 3 = lần 8 ("ơ").
        XCTAssertEqual(o.debugTokenChipCounts[1], TokenStream.chipCount("y"))
        XCTAssertEqual(o.debugTokenChipCounts[3], TokenStream.chipCount("ơ"))
        for path in o.debugTokenPaths {
            let box = path.boundingBoxOfPath
            XCTAssertTrue(o.bounds.insetBy(dx: -0.5, dy: -0.5).contains(box), "\(box) ngoài \(o.bounds)")
        }
        o.halt()
        XCTAssertTrue(o.debugTokenRoots.allSatisfy(\.isHidden), "ẩn bàn phím ⇒ không còn chip")
        _ = KeyEffectOverlay.install(.none, color: .red, in: host, existing: o)
    }

    @MainActor func testShimmerLayerOnlyOnSuggestionChange() throws {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 260))
        let o = try XCTUnwrap(KeyEffectOverlay.install(.tokens, color: .systemPurple, in: host, existing: nil))
        let bar = CGRect(x: 40, y: 0, width: 300, height: 44)
        o.suggestionsChanged([], bar: bar)
        XCTAssertNil(o.debugShimmerLayer, "chưa đổi gì ⇒ chưa dựng lớp nào")
        o.suggestionsChanged(["xin", "chào"], bar: bar)
        let band = try XCTUnwrap(o.debugShimmerLayer)
        XCTAssertEqual(o.debugShimmerFrame, bar)
        XCTAssertNotNil(band.animation(forKey: "shimmer"))
        XCTAssertEqual(band.animation(forKey: "shimmer")?.duration ?? 0, ShimmerGate.duration, accuracy: 1e-9)
        band.removeAllAnimations()
        o.suggestionsChanged(["xin", "chào"], bar: bar)
        XCTAssertNil(band.animation(forKey: "shimmer"), "y nguyên ⇒ không quét")
        // Kiểu khác: không làm gì.
        let h = try XCTUnwrap(KeyEffectOverlay.install(.heart, color: .red, in: host, existing: o))
        h.suggestionsChanged(["cảm", "ơn"], bar: bar)
        XCTAssertNil(h.debugShimmerLayer)
        _ = KeyEffectOverlay.install(.none, color: .red, in: host, existing: h)
    }

    // MARK: Mắt AI — model

    func testAIBuddyCharacter() {
        XCTAssertEqual(BuddyCharacter.allCases.last, .ai)
        XCTAssertEqual(BuddyCharacter.ai.rawValue, "ai")
        XCTAssertEqual(BuddyCharacter.parse("ai"), .ai)
        XCTAssertTrue(BuddyCharacter.ai.isPlus)
        XCTAssertFalse(BuddyCharacter.ai.isRigged)
        XCTAssertNil(BuddyRig.rig(.ai))
        XCTAssertEqual(BuddyRig.checksum(.ai), 0)
        XCTAssertEqual(BuddyCharacter.rigged, BuddyCharacter.allCases.filter { $0 != .off && $0 != .ai })
        XCTAssertEqual(BuddyStyle.sprite.resolved(for: .ai), .vector)
        XCTAssertEqual(L10n.en["Mắt AI"], "AI Eye")
        XCTAssertEqual(BuddyPolicy.active(setting: .ai, plus: true), .ai)
        XCTAssertEqual(BuddyPolicy.active(setting: .ai, plus: false), .off)
    }

    /// Mốc chung android eyePupilClamp.
    func testEyePupilClamp() {
        var o = AIEye.pupilOffset(eye: (0, 0), target: (60, 80), radius: 10)
        XCTAssertEqual(o.dx, 5, accuracy: 1e-9); XCTAssertEqual(o.dy, 20.0 / 3, accuracy: 1e-9)
        o = AIEye.pupilOffset(eye: (0, 0), target: (600, 800), radius: 10)
        XCTAssertEqual(o.dx, 6, accuracy: 1e-9); XCTAssertEqual(o.dy, 8, accuracy: 1e-9)
        o = AIEye.pupilOffset(eye: (5, 5), target: (5, 5), radius: 10)
        XCTAssertEqual(o.dx, 0); XCTAssertEqual(o.dy, 0)
        XCTAssertEqual(AIEye.maxOffset(side: 44), 5.72, accuracy: 1e-9)
        XCTAssertEqual(AIEye.maxOffset(side: -1), 0)
        let r = AIEye.maxOffset(side: 44)
        for a in 0..<72 {
            for d in [0.5, 10, 119, 120, 400, 5000] {
                let tx = cos(Double(a) * .pi / 36) * d, ty = sin(Double(a) * .pi / 36) * d
                let p = AIEye.pupilOffset(eye: (0, 0), target: (tx, ty), radius: r)
                XCTAssertLessThanOrEqual(hypot(p.dx, p.dy), r + 1e-9)
                XCTAssertGreaterThanOrEqual(p.dx * tx + p.dy * ty, 0, "cùng hướng")
                XCTAssertLessThanOrEqual(hypot(p.dx, p.dy) + AIEye.pupil * 44, AIEye.iris * 44 + 1e-9, "đồng tử trong mống mắt")
            }
        }
        XCTAssertEqual(AIEye.pupilScale(level: 0), 1); XCTAssertEqual(AIEye.pupilScale(level: 9), 0.62)
        XCTAssertEqual(AIEye.glow(level: -3), 0.6); XCTAssertEqual(AIEye.glow(level: 3), 1)
        for lv in 1...3 {
            XCTAssertLessThan(AIEye.pupilScale(level: lv), AIEye.pupilScale(level: lv - 1))
            XCTAssertGreaterThan(AIEye.glow(level: lv), AIEye.glow(level: lv - 1))
        }
    }

    /// Nghỉ ⇒ thở đúng 3 nhịp rồi lim dim; lim dim = không hẹn gì nữa — mốc chung android eyeIdleBreathingBounded.
    func testEyeIdleBreathingBounded() throws {
        XCTAssertEqual(AIEye.phase(sinceLastPress: 0), .active)
        XCTAssertEqual(AIEye.phase(sinceLastPress: 1.999), .active)
        XCTAssertEqual(AIEye.phase(sinceLastPress: 2), .breathing)
        XCTAssertEqual(AIEye.phase(sinceLastPress: 6.79), .breathing)
        XCTAssertEqual(AIEye.phase(sinceLastPress: 6.81), .resting, "2 + 1,6 × 3 (dấu phẩy động) ⇒ mốc sát trên 6,8")
        XCTAssertEqual(AIEye.phase(sinceLastPress: .greatestFiniteMagnitude), .resting)
        XCTAssertEqual(AIEye.breathEnd, 6.8, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(AIEye.nextDeadline(sinceLastPress: 0.5)), 1.5, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(AIEye.nextDeadline(sinceLastPress: 5)), 1.8, accuracy: 1e-12)
        XCTAssertNil(AIEye.nextDeadline(sinceLastPress: 6.81)); XCTAssertNil(AIEye.nextDeadline(sinceLastPress: 1e9))
        XCTAssertEqual(AIEye.breathGlow(0), AIEye.restGlow, accuracy: 1e-12)
        XCTAssertEqual(AIEye.breathGlow(0.8), AIEye.restGlow + AIEye.breathAmp, accuracy: 1e-12)
        XCTAssertEqual(AIEye.breathGlow(1.6), AIEye.restGlow, accuracy: 1e-9)
        XCTAssertEqual(AIEye.breathGlow(4.8), AIEye.restGlow)
        XCTAssertEqual(AIEye.breathGlow(100), AIEye.restGlow)
        var s = 0.0
        while s < 6 {
            let g = AIEye.breathGlow(s)
            XCTAssertTrue(g >= AIEye.restGlow - 1e-12 && g <= 0.85 + 1e-12)
            s += 0.01
        }
        var ck = AIEyeClock()
        XCTAssertEqual(ck.phase(at: 0), .resting)
        XCTAssertNil(ck.nextDeadline(at: 0))
        let blinks = (1...27).filter { AIEye.blinks(press: ck.press(at: 100 + Double($0) * 0.1)) }
        XCTAssertEqual(blinks, [9, 18, 27])
        XCTAssertEqual(try XCTUnwrap(ck.nextDeadline(at: 102.7)), 102.7 + 2, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(ck.nextDeadline(at: 105)), 102.7 + 6.8, accuracy: 1e-9)
        XCTAssertNil(ck.nextDeadline(at: 102.7 + 6.81))
        XCTAssertEqual(ck.press(at: 104), 28)
        XCTAssertEqual(ck.press(at: 200), 1, "lim dim ⇒ chuỗi mới")
        XCTAssertEqual(AIEye.openness(.resting), 0.5); XCTAssertEqual(AIEye.openness(.breathing), 1)
        XCTAssertEqual(AIEye.lidEdge(openness: 1, radius: 10), 0); XCTAssertEqual(AIEye.lidEdge(openness: 0.5, radius: 10), 10)
        XCTAssertEqual(AIEye.lidEdge(openness: -1, radius: 10), 20)
    }

    // MARK: Mắt AI — view

    @MainActor func testEyeViewPupilClampedAndIdleBounded() throws {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 300))
        let e = AIEyeView(lowPower: false)
        host.addSubview(e)
        e.frame = CGRect(x: 340, y: 0, width: 44, height: 44)
        e.layoutIfNeeded()
        XCTAssertEqual(e.debugPhase, .resting)
        XCTAssertFalse(e.debugTickScheduled, "chưa gõ ⇒ không hẹn gì")
        XCTAssertEqual(e.debugLidEdge, e.debugRadius, accuracy: 0.01, "lim dim: mí che nửa")
        e.keyPressed(at: CGPoint(x: 20, y: 250))            // phím dưới-trái
        let p = e.debugPupilOffset
        XCTAssertLessThan(p.x, 0); XCTAssertGreaterThan(p.y, 0)
        XCTAssertLessThanOrEqual(hypot(p.x, p.y), e.debugMaxOffset + 0.01)
        XCTAssertEqual(e.debugPhase, .active)
        XCTAssertTrue(e.debugTickScheduled)
        XCTAssertEqual(e.debugLidEdge, 0, accuracy: 0.01, "gõ ⇒ mở mắt")
        // Gõ nhanh ⇒ đồng tử co, quầng mạnh.
        for _ in 0..<ComboMeter.thresholds[2] { e.keyPressed(at: CGPoint(x: 20, y: 250)) }
        XCTAssertEqual(e.debugPupilScale, CGFloat(AIEye.pupilScale(level: 3)), accuracy: 0.001)
        XCTAssertEqual(e.debugGlow, Float(AIEye.glow(level: 3)), accuracy: 0.001)
        // Nghỉ 2 s ⇒ thở ĐÚNG số nhịp (animation hữu hạn), rồi lim dim ⇒ 0 animation, 0 hẹn giờ.
        e.debugBackdate(AIEye.idleAfter)
        e.debugTick(at: CACurrentMediaTime())
        XCTAssertEqual(e.debugPhase, .breathing)
        XCTAssertEqual(e.debugBreathRepeat, Float(AIEye.breathCycles))
        e.debugBackdate(AIEye.breathEnd + 0.1)
        e.debugTick(at: CACurrentMediaTime())
        XCTAssertEqual(e.debugPhase, .resting)
        e.halt()
        XCTAssertEqual(e.debugAnimationCount, 0)
        XCTAssertFalse(e.debugTickScheduled)
        XCTAssertEqual(e.debugGlow, Float(AIEye.restGlow), accuracy: 0.001)
        XCTAssertEqual(e.debugLidEdge, e.debugRadius, accuracy: 0.01)
    }

    @MainActor func testEyeLowPowerHasNoAnimation() {
        let e = AIEyeView(lowPower: true)
        e.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        e.layoutIfNeeded()
        e.keyPressed(at: CGPoint(x: 0, y: 200))
        e.tickle()
        XCTAssertEqual(e.debugAnimationCount, 0, "tiết kiệm pin ⇒ không hoạt ảnh")
    }

    // MARK: KeyboardView — Mắt AI là nhân vật, token bay vào mắt

    @MainActor private func withKeyboard(buddy: String?, effect: String?, _ body: (KeyboardView) throws -> Void) rethrows {
        PlusGate.paywallEnabled = true
        PlusGate.defaults.set(true, forKey: PlusConfig.unlockedKey)
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        if let buddy { d.set(buddy, forKey: BuddyCharacter.key) }
        if let effect { d.set(effect, forKey: KeyEffect.key) }
        d.set(false, forKey: KeyboardView.keyPreviewKey)
        let saved = UserDefaultsProvider.shared
        UserDefaultsProvider.shared = d
        defer { UserDefaultsProvider.shared = saved; d.removePersistentDomain(forName: suite) }
        let win = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 300))
        win.isHidden = false
        let kb = KeyboardView(needsGlobe: false, inputController: nil) { _ in }
        kb.frame = win.bounds
        win.addSubview(kb)
        kb.applyAppearance(.light, style: .light)
        kb.setSuggestionsEnabled(true)
        kb.layoutIfNeeded()
        try body(kb)
        win.isHidden = true
        kb.tearDown()
    }

    @MainActor func testEyeOnlyWhenSelectedAndTokensFlyIntoIt() throws {
        try withKeyboard(buddy: nil, effect: "tokens") { kb in
            XCTAssertNil(kb.aiEye, "không chọn ⇒ không view")
            XCTAssertFalse(kb.subviews.contains { $0 is AIEyeView })
            let o = try XCTUnwrap(kb.keyEffects)
            XCTAssertEqual(o.effect, .tokens)
            let t = try XCTUnwrap(o.tokenTarget?())
            XCTAssertEqual(t, kb.tokenTargetPoint())
            XCTAssertTrue(kb.bounds.contains(t))
            XCTAssertLessThan(t.y, kb.debugRowsMinY, "đích = dải gợi ý (trên hàng phím)")
        }
        try withKeyboard(buddy: "ai", effect: "tokens") { kb in
            let e = try XCTUnwrap(kb.aiEye)
            XCTAssertNil(kb.buddy, "Mắt AI thay nhân vật vẽ")
            XCTAssertFalse(e.isUserInteractionEnabled)
            XCTAssertFalse(e.isHidden)
            XCTAssertLessThanOrEqual(e.frame.maxY, kb.debugRowsMinY + 0.5, "mắt nằm trong dải gợi ý, không đè phím")
            // Phil 08/11: tâm mắt thẳng hàng chữ gợi ý (± 1 pt), quầng sáng (cả khung) không chạm mép trên.
            XCTAssertEqual(e.eyeCenter.y, kb.debugSuggestionBarFrame.midY, accuracy: 1, "tâm mắt = tâm dọc dòng chữ gợi ý — mắt \(e.frame), bar \(kb.debugSuggestionBarFrame), hàng phím \(kb.debugRowsMinY)")
            XCTAssertGreaterThanOrEqual(e.frame.minY, 0, "không vượt mép trên")
            XCTAssertLessThan(e.frame.height, kb.debugRowsMinY, "nhỏ hơn strip ⇒ có khoảng thở")
            XCTAssertLessThanOrEqual(e.frame.maxX, kb.bounds.maxX + 0.5)
            XCTAssertEqual(kb.keyEffects?.tokenTarget?(), e.eyeCenter, "token bay vào mắt")
        }
        try withKeyboard(buddy: "ai", effect: nil) { kb in
            XCTAssertNotNil(kb.aiEye)
            XCTAssertNil(kb.keyEffects, "mắt không kéo theo hiệu ứng")
        }
        try withKeyboard(buddy: "cat", effect: nil) { kb in
            XCTAssertNil(kb.aiEye)
            XCTAssertNotNil(kb.buddy)
        }
    }

    func testAIEyeFramePure() {
        let f = KeyboardView.aiEyeFrame(width: 390, strip: 44, rowMid: 24)
        XCTAssertEqual(f.size, CGSize(width: 38, height: 38), "44 × 0,86 → 38")
        XCTAssertEqual(f.midY, 24, accuracy: 1, "tâm dọc = tâm dòng chữ gợi ý")
        XCTAssertEqual(f.minY, 5)
        XCTAssertLessThanOrEqual(f.maxX, 390)
        let zone = KeyboardView.buddyZoneFrame(width: 390, strip: 44)
        XCTAssertEqual(f.maxX, 390, accuracy: 0.5, "rộng hơn ô chừa ⇒ kẹp sát mép phải")
        XCTAssertTrue(f.intersects(zone))
        var big = BuddyPlacement.standard; big.size = 10
        let g = KeyboardView.aiEyeFrame(width: 390, strip: 44, rowMid: 24, placement: big, height: 260)
        XCTAssertGreaterThan(g.height, f.height, "cỡ lớn hơn ⇒ mắt to hơn")
        XCTAssertLessThanOrEqual(g.maxX, 390.5, "không vượt mép phải")
        XCTAssertEqual(g.minY, f.minY, accuracy: 0.5, "lớn dần xuống phím, đỉnh giữ nguyên")
        XCTAssertEqual(KeyboardView.aiEyeFrame(width: 390, strip: 44).midY, 22, accuracy: 0.5, "không biết dòng chữ ⇒ giữa strip")
    }

    /// Khung cỡ gốc của Mắt AI: cạnh = round(strip × 0,86), tâm dọc = tâm dòng chữ gợi ý, kẹp trong strip.
    /// CÙNG SỐ Android AIThemeTests.eyeSlotCentersOnSuggestionRow.
    func testEyeSlotCentersOnSuggestionRow() {
        XCTAssertEqual(AIEye.slotSize, 0.86)
        // (strip, rowMid) → (top, side)
        let cases: [(Double, Double, Double, Double)] = [
            (44, 24, 5, 38), (44, 21, 2, 38), (44, 22, 3, 38), (52, 26, 3.5, 45), (40, 19, 2, 34),
            (35, 22, 9, 26),   // strip bị bóp (máy test 300 pt): mắt nhỏ lại, vẫn đúng tâm
            (44, 10, 0, 22),   // chữ sát mép trên ⇒ cạnh tối thiểu nửa strip, kẹp mép trên
            (44, 40, 22, 22),  // chữ sát đáy ⇒ kẹp đáy strip (không đè phím)
        ]
        for (strip, mid, top, side) in cases {
            let s = AIEye.slot(strip: strip, rowMid: mid)
            XCTAssertEqual(s.top, top, accuracy: 1e-9, "\(strip) \(mid)")
            XCTAssertEqual(s.side, side, accuracy: 1e-9, "\(strip) \(mid)")
            XCTAssertGreaterThanOrEqual(s.top, 0); XCTAssertLessThanOrEqual(s.top + s.side, strip)
            if mid - side / 2 >= 0, mid + side / 2 <= strip { XCTAssertEqual(s.top + s.side / 2, mid, accuracy: 1) }
        }
    }

    // MARK: Theme AI, motif neural, aurora, âm

    func testAITheme() throws {
        XCTAssertEqual(KeyboardTheme.allCases.firstIndex(of: .timeOfDay)! + 1, KeyboardTheme.allCases.firstIndex(of: .ai)!)
        let spec = try XCTUnwrap(KeyboardTheme.ai.spec)
        XCTAssertTrue(KeyboardTheme.ai.isPlus)
        XCTAssertEqual(spec.nameVi, "AI"); XCTAssertEqual(spec.nameEn, "AI"); XCTAssertEqual(L10n.en["AI"], "AI")
        XCTAssertEqual(spec.effect, "tokens"); XCTAssertEqual(spec.sound, "ai"); XCTAssertEqual(spec.swipe, "neon")
        XCTAssertNil(spec.corner)
        for dark in [false, true] {
            let p = KeyboardTheme.ai.palette(systemDark: dark)
            XCTAssertTrue(p.auroraBorder); XCTAssertFalse(p.rainbowBorder)
            XCTAssertEqual(p.decoration?.motif, .neural)
            XCTAssertTrue(p.isDark)
            XCTAssertGreaterThanOrEqual(RGBA.contrast(p.ink, p.keyFill), 4.5, "chữ trắng trên phím kính")
        }
        XCTAssertEqual(KeyboardTheme.ai.palette(systemDark: false), KeyboardTheme.ai.palette(systemDark: true))
        XCTAssertEqual(KeyboardTheme.ai.systemBackdropKey, "systemBackdropAi")
        XCTAssertTrue(BackupSettings.all.contains { $0.key == "systemBackdropAi" })
    }

    func testAuroraBorderParseAndPatch() throws {
        let base = ##"{"v":1,"name":{"vi":"x"},"light":{"key":"#000000","special":"#111111","ink":"#FFFFFF","accent":"#7C4DFF","borderFx":"aurora"}}"##
        let s = try XCTUnwrap(ThemeSpecParser.parse(base).spec)
        XCTAssertEqual(s.light.borderFx, "aurora")
        XCTAssertTrue(s.palette(dark: false).auroraBorder); XCTAssertFalse(s.palette(dark: false).rainbowBorder)
        XCTAssertTrue(s.canonical.contains(#""borderFx":"aurora""#))
        XCTAssertEqual(ThemeSpecParser.parse(s.canonical).spec?.canonical, s.canonical)
        XCTAssertEqual(ThemeSpec.slots(from: s.palette(dark: false)).borderFx, "aurora")
        XCTAssertEqual(AuroraFx.bandOpacity(0), 0.32, accuracy: 1e-12)
        XCTAssertEqual(AuroraFx.bandOpacity(28), 0.08, accuracy: 1e-12)
        XCTAssertEqual(AuroraFx.bandOpacity(56), 0); XCTAssertEqual(AuroraFx.bandOpacity(-1), 0)
        XCTAssertEqual(AuroraFx.border.count, 3); XCTAssertEqual(AuroraFx.band.count, 4)
        XCTAssertEqual(AuroraFx.border.last?.location, 1); XCTAssertEqual(AuroraFx.band.last?.location, 1)
        // Viền tĩnh: không bao giờ có animation.
        let v = RainbowBorderView(aurora: true)
        v.frame = CGRect(x: 0, y: 0, width: 390, height: 260)
        v.layoutIfNeeded()
        v.setKeys([CGRect(x: 10, y: 10, width: 30, height: 40)], radii: [6])
        for _ in 0..<20 { v.poke() }
        XCTAssertEqual(v.debugAnimationCount, 0)
        XCTAssertEqual(v.debugStrip.opacity, Float(AuroraFx.borderAlpha), accuracy: 1e-6)
        XCTAssertNotNil(v.debugMaskPath)
    }

    /// Motif "neural": nút + dây trong ô ±0.5, chấm lưới trải ngang (|y| ≤ 0.45), cùng chiều quay, mốc chung android.
    func testNeuralMotif() {
        XCTAssertEqual(KeyboardDecoration.Motif.allCases.firstIndex(of: .neural)! + 1, KeyboardDecoration.Motif.allCases.firstIndex(of: .swirl)!)
        XCTAssertTrue(KeyboardDecoration.Motif.allCases.contains(.neural))
        XCTAssertEqual(KeyboardDecoration.Motif.allCases.firstIndex(of: .bubbles)! + 1, KeyboardDecoration.Motif.allCases.firstIndex(of: .neural)!)
        let subs = KeyboardDecoration.shape(.neural)
        XCTAssertEqual(subs.count, 12)
        var sum = 0.0
        for (k, sub) in subs.enumerated() {
            var pts: [(Double, Double)] = [sub.start]
            for g in sub.segs { var i = 0; while i < g.count { pts.append((g[i], g[i + 1])); i += 2 } }
            var a = 0.0
            for i in pts.indices { let p = pts[i], q = pts[(i + 1) % pts.count]; a += p.0 * q.1 - q.0 * p.1 }
            XCTAssertGreaterThan(a, 0, "#\(k) chiều quay")
            for p in pts {
                XCTAssertLessThanOrEqual(abs(p.1), 0.45, "#\(k)")
                if k < 6 { XCTAssertLessThanOrEqual(abs(p.0), 0.5, "#\(k) nút/dây trong ô") }
                sum += p.0 * 3 + p.1 * 7
            }
        }
        XCTAssertEqual(sum, 20.15, accuracy: 1e-6)
    }

    func testAISynthBlip() {
        let golden: [(KeySoundKind, Double)] = [(.letter, 165.6180), (.delete, 166.9984), (.modifier, 195.0660)]
        for (k, want) in golden {
            let wood = KeySoundSynth.samples(.wood, k), a = KeySoundSynth.samples(.ai, k)
            XCTAssertLessThan(KeySoundSynth.rms(a), KeySoundSynth.rms(wood), "\(k)")
            XCTAssertLessThan(a.map(abs).max() ?? 1, wood.map(abs).max() ?? 0, "\(k)")
            XCTAssertLessThan(Double(a.count) / KeySoundSynth.sampleRate, 0.061, "\(k)")
            XCTAssertEqual(a.reduce(0.0) { $0 + Double(abs($1)) }, want, accuracy: 0.01, "\(k)")
        }
        XCTAssertEqual(KeySoundStyle.allCases.firstIndex(of: .chip)! + 1, KeySoundStyle.allCases.firstIndex(of: .ai)!)
        XCTAssertTrue(KeySoundStyle.presets.contains(.ai))
        XCTAssertTrue(KeySoundStyle.presetIDs.contains("ai"))
        XCTAssertEqual(L10n.en["Synth AI"], "AI synth")
    }

    // MARK: Ảnh xem thử (chỉ khi đặt VT_THEME_SNAPSHOT_DIR)

    @MainActor func testWriteAIThemeSnapshot() throws {
        guard let dir = ProcessInfo.processInfo.environment["VT_THEME_SNAPSHOT_DIR"] else {
            throw XCTSkip("đặt VT_THEME_SNAPSHOT_DIR để xuất ảnh theme")
        }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        PlusGate.paywallEnabled = false
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        d.set(KeyboardTheme.ai.rawValue, forKey: ThemeSettings.themeKey)
        d.set("ai", forKey: BuddyCharacter.key)
        d.set("tokens", forKey: KeyEffect.key)
        d.set(false, forKey: KeyboardView.keyPreviewKey)
        let saved = UserDefaultsProvider.shared
        UserDefaultsProvider.shared = d
        defer { UserDefaultsProvider.shared = saved; d.removePersistentDomain(forName: suite) }
        let w: CGFloat = 402
        let win = UIWindow(frame: CGRect(x: 0, y: 0, width: w, height: 320))
        win.overrideUserInterfaceStyle = .dark
        win.backgroundColor = UIColor(white: 0.11, alpha: 1)
        win.isHidden = false
        defer { win.isHidden = true }
        let kb = KeyboardView(needsGlobe: false, inputController: nil, onKey: { _ in })
        win.addSubview(kb)
        kb.frame = win.bounds
        kb.applyAppearance(.dark, style: .dark)
        kb.setSuggestionsEnabled(true)
        kb.configureInputKind(.normal)
        kb.setNeedsLayout(); kb.layoutIfNeeded()
        kb.showSuggestions(.init(nextWords: ["Xin", "chào", "AI"]))
        let h = kb.systemLayoutSizeFitting(CGSize(width: w, height: 0)).height
        win.frame.size.height = max(h, 200); kb.frame = win.bounds
        win.layoutIfNeeded(); kb.layoutIfNeeded()
        // Mắt đang nhìn phím vừa gõ (mở mắt) — như lúc gõ.
        kb.aiEye?.keyPressed(at: CGPoint(x: 60, y: kb.bounds.maxY - 60))
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        let rb = kb.rainbow
        rb?.isHidden = true
        let img = UIGraphicsImageRenderer(bounds: win.bounds).image { ctx in
            win.backgroundColor?.setFill(); ctx.fill(win.bounds)
            kb.layer.render(in: ctx.cgContext)
            if let rb {
                ctx.cgContext.saveGState()
                ctx.cgContext.translateBy(x: rb.frame.minX, y: rb.frame.minY)
                rb.debugDraw(in: ctx.cgContext)
                ctx.cgContext.restoreGState()
            }
        }
        rb?.isHidden = false
        try XCTUnwrap(img.pngData()).write(to: URL(fileURLWithPath: dir).appendingPathComponent("ai-theme-ios.png"))
        kb.tearDown()
    }
}
