// Theme "Gym" (11/2026): hiệu ứng Rep (RepsFx — thanh rep, SET ✓, "+1 rep 💪", BEAST MODE), âm "Tạ sắt", motif "treadplate".
// Số mốc CHUNG Android (GymThemeTests.kt / GymRepsViewTest.kt).
import XCTest
import UIKit

@MainActor
final class GymThemeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        #if DEBUG
        KeyEffectOverlay.drawsOffscreen = true
        #endif
    }

    override func tearDown() {
        #if DEBUG
        KeyEffectOverlay.drawsOffscreen = false
        #endif
        super.tearDown()
    }

    // MARK: id

    func testIdsAppendedAndShared() throws {
        XCTAssertEqual(KeyboardTheme.allCases.firstIndex(of: .nightclub)! + 1, KeyboardTheme.allCases.firstIndex(of: .gym)!)
        XCTAssertEqual(KeyboardTheme.gym.rawValue, "gym")
        XCTAssertEqual(KeyEffect.allCases.firstIndex(of: .dancefloor)! + 1, KeyEffect.allCases.firstIndex(of: .reps)!)
        XCTAssertEqual(KeyEffect.reps.rawValue, "reps")
        XCTAssertTrue(KeyEffect.reps.isPlus)
        XCTAssertFalse(KeyEffect.reps.isQueued, "mỗi phím đều lấp thanh rep")
        XCTAssertTrue(KeyEffect.reps.needsBoundaryWord, "từ khoá BEAST MODE ở ranh giới từ")
        XCTAssertFalse(KeyEffect.reps.needsComposeDiff)
        XCTAssertTrue(KeyEffectOverlay.clipped.contains(.reps), "cắt theo bàn phím (#151)")
        XCTAssertEqual(KeySoundStyle.allCases.firstIndex(of: .club)! + 1, KeySoundStyle.allCases.firstIndex(of: .plate)!)
        XCTAssertTrue(KeySoundStyle.presets.contains(.plate))
        XCTAssertTrue(KeySoundStyle.presetIDs.contains("plate"))
        XCTAssertEqual(KeyboardDecoration.Motif(rawValue: "treadplate"), .treadplate)
        XCTAssertEqual(L10n.en["Rep"], "Reps")
        XCTAssertEqual(L10n.en["Tạ sắt"], "Iron plate")
        XCTAssertEqual(L10n.en["Gym"], "Gym")
    }

    // MARK: theme

    func testGymTheme() throws {
        let t = KeyboardTheme.gym
        let spec = try XCTUnwrap(t.spec)
        XCTAssertTrue(t.isPlus)
        XCTAssertTrue(t.isInteractive)
        XCTAssertEqual(ThemePicker.interactiveOrder.last, "gym")
        XCTAssertEqual(spec.nameVi, "Gym"); XCTAssertEqual(spec.nameEn, "Gym")
        XCTAssertEqual(spec.sound, "plate"); XCTAssertEqual(spec.effect, "reps"); XCTAssertEqual(spec.swipe, "neon")
        XCTAssertNil(spec.dark, "dark = same")
        let p = t.palette(systemDark: false)
        XCTAssertEqual(p, t.palette(systemDark: true))
        XCTAssertTrue(p.isDark)
        XCTAssertEqual(p.decoration?.motif, .treadplate)
        XCTAssertNotNil(p.keyBorder, "viền vàng chanh neon")
        let bg = try XCTUnwrap(p.background)
        XCTAssertGreaterThanOrEqual(RGBA.contrast(p.ink, p.keyFill.over(bg)), 4.5)
        XCTAssertGreaterThanOrEqual(RGBA.contrast(p.fnInk, p.fnFill.over(bg)), 4.5)
        XCTAssertTrue(ThemeSpecParser.contrastIssues(spec).isEmpty, "chữ / phím đủ tương phản")
        XCTAssertEqual(t.systemBackdropKey, "systemBackdropGym")
        XCTAssertNotNil(BackupSettings.byKey["systemBackdropGym"])
        XCTAssertTrue(ThemePicker.ordered().contains(.gym))
        XCTAssertEqual(ThemePicker.badge(.gym), L("Tương tác"))
    }

    /// Motif "treadplate": 7 gân hình thoi, cùng chiều quay (tô nonzero = hợp), |y| ≤ 0.45 (không chạm phím), mốc chung Android.
    func testTreadplateMotif() {
        let subs = KeyboardDecoration.shape(.treadplate)
        XCTAssertEqual(subs.count, 7)
        var area = 0.0
        for sub in subs {
            var pts = [sub.start]
            for g in sub.segs { pts.append((g[0], g[1])) }
            XCTAssertEqual(pts.count, 4)
            var a = 0.0
            for i in pts.indices { let p = pts[i], q = pts[(i + 1) % pts.count]; a += p.0 * q.1 - q.0 * p.1 }
            XCTAssertGreaterThan(a, 0, "chiều quay")
            area += a / 2
            for p in pts { XCTAssertLessThanOrEqual(abs(p.1), 0.45); XCTAssertLessThanOrEqual(abs(p.0), 2.75) }
        }
        XCTAssertEqual(area, 7 * 0.62 * 0.18 / 2, accuracy: 1e-9)
        XCTAssertEqual(subs[0].start.0, -2.180797, accuracy: 1e-6)
        XCTAssertEqual(subs[0].start.1, 0.219203, accuracy: 1e-6)
        XCTAssertEqual(subs[1].start.1, -0.219203, accuracy: 1e-6, "gân xen kẽ ±45°")
    }

    // MARK: âm Tạ sắt

    /// "Tạ sắt": không to hơn "Gõ gỗ", ≤ 60 ms, không chói, hoạ âm không điều hoà; seed cố định; checksum chung Android.
    func testPlateSoundSoftAndShared() {
        for k in KeySoundKind.allCases {
            let wood = KeySoundSynth.samples(.wood, k), a = KeySoundSynth.samples(.plate, k)
            XCTAssertLessThan(KeySoundSynth.rms(a), KeySoundSynth.rms(wood), "\(k)")
            XCTAssertLessThan(a.map(abs).max() ?? 1, wood.map(abs).max() ?? 0, "\(k)")
            XCTAssertLessThan(Double(a.count) / KeySoundSynth.sampleRate, 0.061, "\(k)")
            XCTAssertLessThan(KeySoundSynth.spectralCentroid(a), 2500, "\(k) không chói")
        }
        XCTAssertEqual(KeySoundSynth.seed(.plate, .letter), 0x706C_6174 ^ 0x85EB_CA6B)
        for (k, want) in Self.plateGolden {
            XCTAssertEqual(KeySoundSynth.samples(.plate, k).reduce(0.0) { $0 + Double(abs($1)) }, want, accuracy: 0.01, "\(k)")
        }
    }
    static let plateGolden: [(KeySoundKind, Double)] = [(.letter, 113.6273), (.delete, 117.8890), (.modifier, 141.4856)]

    // MARK: RepsFx thuần

    func testCounterSetsAndResets() {
        var c = RepsFx.Counter()
        var events: [RepsFx.Counter.Event] = []
        for i in 0..<10 { events.append(c.press(at: Double(i) * 0.2)) }
        XCTAssertEqual(events.map(\.fill), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
        XCTAssertEqual(events.compactMap(\.completedSet), [1], "10 phím = một hiệp")
        for i in 10..<25 { _ = c.press(at: Double(i) * 0.2) }
        XCTAssertEqual(c.sets, 2); XCTAssertEqual(c.reps, 5)
        // Nghỉ > 60 s ⇒ về 0, phím kế là nấc 1 hiệp mới.
        XCTAssertFalse(c.isIdle(at: 4.8 + 60))
        XCTAssertTrue(c.isIdle(at: 4.8 + 60.01))
        XCTAssertEqual(c.press(at: 4.8 + 61), RepsFx.Counter.Event(fill: 1, completedSet: nil))
        XCTAssertEqual(c.sets, 0)
        // Ẩn bàn phím ⇒ reset().
        for i in 0..<12 { _ = c.press(at: 100 + Double(i)) }
        c.reset()
        XCTAssertEqual(c.reps, 0); XCTAssertEqual(c.sets, 0)
        var d = RepsFx.Counter()
        for i in 0..<9 { _ = d.press(at: Double(i)) }
        XCTAssertEqual(d.press(at: 9).completedSet, 1, "hiệp đầu sau reset vẫn là SET 1")
    }

    func testCurvesShared() {
        XCTAssertEqual(RepsFx.barFill(from: 0, to: 1, dt: 0.06), 0.05, accuracy: 1e-9)
        XCTAssertEqual(RepsFx.barFill(from: 3, to: 4, dt: 1), 0.4, accuracy: 1e-9)
        XCTAssertEqual(RepsFx.barFill(from: 9, to: 10, dt: 0.3), 1, accuracy: 1e-9, "hết hiệp: đầy")
        XCTAssertEqual(RepsFx.barFill(from: 9, to: 10, dt: 0.12 + 0.45 + 0.1), 0.5, accuracy: 1e-9, "rút về")
        XCTAssertEqual(RepsFx.barFill(from: 9, to: 10, dt: RepsFx.setLife), 0, accuracy: 1e-9)
        XCTAssertEqual(RepsFx.badgeScale(0.12), 1.25, accuracy: 1e-9)
        XCTAssertEqual(RepsFx.badgeAlpha(0.06), 0.5, accuracy: 1e-9)
        XCTAssertEqual(RepsFx.badgeAlpha(0.9), 0)
        XCTAssertEqual(RepsFx.slamScale(0.05), 1.65, accuracy: 1e-9)
        XCTAssertEqual(RepsFx.slamAlpha(0.5), 1, accuracy: 1e-9)
        XCTAssertEqual(RepsFx.ringScale(0.35), 1.275, accuracy: 1e-9)
        XCTAssertEqual(RepsFx.ringAlpha(0.35), 0.425, accuracy: 1e-9)
        XCTAssertEqual(RepsFx.ringAlpha(0.05), 0)
        XCTAssertEqual(RepsFx.labelDy(0.4), -28.5, accuracy: 1e-9)
        XCTAssertEqual(RepsFx.labelAlpha(0.06), 0.5, accuracy: 1e-9)
        XCTAssertEqual(RepsFx.labelAlpha(0.8), 0)
        XCTAssertEqual([0, 2, 4, -1].map(RepsFx.labelDrift), [-8, 0, 8, 8])
        XCTAssertEqual(RepsFx.ringRadius(width: 390, height: 260), 44, accuracy: 1e-9)
        XCTAssertEqual(RepsFx.ringRadius(width: 110, height: 84), 24.375, accuracy: 1e-9)
        XCTAssertEqual(RepsFx.slamFont(width: 390), 30, accuracy: 1e-9)
        XCTAssertEqual(RepsFx.slamFont(width: 110), 110 / 8.5, accuracy: 1e-9)
        let o = RepsFx.labelOrigin(keyMidX: 5, keyTop: 10, seed: 2, bounds: (0, -40, 390, 300))
        XCTAssertEqual(o.x, 40, accuracy: 1e-9); XCTAssertEqual(o.y, 10, accuracy: 1e-9)
        let top = RepsFx.labelOrigin(keyMidX: 200, keyTop: -35, seed: 4, bounds: (0, -40, 390, 300))
        XCTAssertEqual(top.x, 208, accuracy: 1e-9); XCTAssertEqual(top.y, 8, accuracy: 1e-9, "cả đường bay trong khung")
        XCTAssertEqual(RepsFx.badgeText(set: 3), "SET 3 ✓")
    }

    func testKeywordTable() {
        XCTAssertEqual(RepsFx.keywords, ["gym", "tập", "fit", "no pain no gain", "beast mode", "lên tạ"])
        for (w, p, p2) in [("gym", nil, nil), ("Gym!", nil, nil), ("tập", nil, nil), ("FIT", nil, nil),
                           ("mode", "beast", nil), ("tạ", "lên", nil), ("gain", "no", "pain")] as [(String, String?, String?)] {
            XCTAssertTrue(RepsFx.isKeyword(word: w, prev: p, prev2: p2), w)
        }
        for (w, p, p2) in [("tap", nil, nil), ("fitness", nil, nil), ("mode", nil, nil), ("gain", "no", nil), ("tạ", nil, nil),
                           ("gain", "no", "rain"), ("", nil, nil)] as [(String, String?, String?)] {
            XCTAssertFalse(RepsFx.isKeyword(word: w, prev: p, prev2: p2), w)
        }
    }

    // MARK: lớp phủ

    /// Host dời gốc bounds (#151): thanh rep / huy hiệu / nhãn / chữ đập nằm TRONG khung; nhãn có trần; ẩn ⇒ hiệp về 0.
    func testRepOverlayInsideShiftedBoundsCappedAndResets() throws {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 300))
        host.bounds.origin.y = -40
        let o = try XCTUnwrap(KeyEffectOverlay.install(.reps, color: .systemGreen, in: host, existing: nil))
        XCTAssertEqual(o.bounds.origin, host.bounds.origin)
        XCTAssertTrue(o.clipsToBounds)
        XCTAssertNil(o.debugRepBarTrack, "chưa gõ ⇒ chưa dựng gì (0 chi phí)")
        for i in 0..<23 {   // gõ dồn (cùng giây) ⇒ combo ⇒ nhãn; phím sát mép trên trái
            o.emit(key: CGRect(x: CGFloat(i % 10) * 39 + 2, y: -38, width: 34, height: 42)); o.flush()
        }
        XCTAssertEqual(o.debugRepCounter.sets, 2); XCTAssertEqual(o.debugRepFill, 3)
        XCTAssertEqual(o.debugRepBadgeText, "SET 2 ✓")
        XCTAssertEqual(o.debugRepLabels.count, RepsFx.labelCap, "pool nhãn dùng lại")
        o.queueBeastMode()
        o.emit(key: CGRect(x: 300, y: 200, width: 34, height: 42)); o.flush()
        let b = o.bounds.insetBy(dx: -0.5, dy: -0.5)
        let track = try XCTUnwrap(o.debugRepBarTrack)
        XCTAssertTrue(b.contains(track.frame), "\(track.frame)")
        XCTAssertEqual(track.frame.minY, o.bounds.minY + CGFloat(RepsFx.barInset), accuracy: 1e-6, "dọc mép trên bàn phím")
        let badge = try XCTUnwrap(o.debugRepBadge)
        let maxBadge = CGFloat(RepsFx.badgeScales.max()!)
        XCTAssertTrue(b.contains(CGRect(x: badge.position.x - badge.bounds.width * maxBadge / 2,
                                        y: badge.position.y - badge.bounds.height * maxBadge / 2,
                                        width: badge.bounds.width * maxBadge, height: badge.bounds.height * maxBadge)))
        for l in o.debugRepLabels {
            let top = l.position.y - CGFloat(RepsFx.labelRise) - l.bounds.height / 2
            XCTAssertGreaterThanOrEqual(top, o.bounds.minY - 1e-6, "nhãn bay lên vẫn trong khung")
            XCTAssertTrue(b.contains(l.frame), "\(l.frame)")
        }
        let slam = try XCTUnwrap(o.debugRepSlam)
        XCTAssertFalse(slam.isHidden)
        XCTAssertEqual(slam.position, CGPoint(x: o.bounds.midX, y: o.bounds.midY))
        let text = try XCTUnwrap(o.debugRepSlamText)
        XCTAssertTrue(b.contains(o.layer.convert(text.bounds, from: text)))
        let ring = try XCTUnwrap(o.debugRepRing?.path?.boundingBoxOfPath)
        let g = CGFloat(RepsFx.ringGrow)
        XCTAssertTrue(b.contains(CGRect(x: slam.position.x + ring.minX * g, y: slam.position.y + ring.minY * g,
                                        width: ring.width * g, height: ring.height * g)))
        // Nghỉ chưa đủ ⇒ giữ; đủ 60 s ⇒ về 0. Ẩn bàn phím (halt) ⇒ về 0.
        o.debugSweepReps(idleFor: 10)
        XCTAssertEqual(o.debugRepFill, 4)
        o.debugSweepReps(idleFor: RepsFx.idleReset + 1)
        XCTAssertEqual(o.debugRepFill, 0); XCTAssertEqual(o.debugRepCounter.sets, 0)
        for _ in 0..<4 { o.emit(key: CGRect(x: 50, y: 100, width: 34, height: 42)); o.flush() }
        o.halt()
        XCTAssertEqual(o.debugRepFill, 0); XCTAssertEqual(o.debugRepCounter.reps, 0)
        XCTAssertTrue(o.debugRepLabels.allSatisfy(\.isHidden))
        XCTAssertEqual(o.debugRepBar?.animationKeys() ?? [], [], "nghỉ = 0 animation trên thanh")
        _ = KeyEffectOverlay.install(.none, color: .red, in: host, existing: o)
    }

    /// Kiểu khác: queueBeastMode không làm gì, không dựng layer Rep.
    func testOtherEffectsIgnoreBeastMode() throws {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 260))
        let o = try XCTUnwrap(KeyEffectOverlay.install(.heart, color: .red, in: host, existing: nil))
        o.queueBeastMode()
        o.emit(key: CGRect(x: 50, y: 100, width: 34, height: 42)); o.flush()
        XCTAssertNil(o.debugRepSlam); XCTAssertNil(o.debugRepBarTrack)
        _ = KeyEffectOverlay.install(.none, color: .red, in: host, existing: o)
    }
}
