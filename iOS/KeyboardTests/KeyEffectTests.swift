// "Hiệu ứng khi bấm phím" (Plus, 19/10/2026): model cài đặt, cổng Plus, điều kiện tự tắt, trần hạt,
// overlay không nhận chạm / không rò, và A/B chi phí main thread mỗi phím (bộ chậm).
// Ràng buộc từ Phil: chèn chữ TRƯỚC rồi mới vẽ; tắt = 0 chi phí (không tạo overlay); ≤ ~20 hạt;
// tăng > ~0,3 ms/phím trên main thread thì không phát hành.
import XCTest
import UIKit

final class KeyEffectTests: XCTestCase {
    private var savedDefaults: UserDefaults!
    private var savedPaywall = true
    private let plusSuite = "vt-keyeffect-plus"
    private let suite = "vt-keyeffect"

    override func setUp() {
        super.setUp()
        savedDefaults = PlusGate.defaults
        savedPaywall = PlusGate.paywallEnabled
        UserDefaults(suiteName: plusSuite)!.removePersistentDomain(forName: plusSuite)
        PlusGate.defaults = UserDefaults(suiteName: plusSuite)!
        #if DEBUG
        KeyEffectOverlay.drawsOffscreen = true
        #endif
    }

    override func tearDown() {
        PlusGate.defaults = savedDefaults
        PlusGate.paywallEnabled = savedPaywall
        #if DEBUG
        KeyEffectOverlay.drawsOffscreen = false
        #endif
        super.tearDown()
    }

    // MARK: model

    func testIdsMatchAndroidAndDefaultIsNone() {
        // Cùng id với android/keyboard/.../KeyEffect.kt (sao lưu chéo nền tảng).
        XCTAssertEqual(KeyEffect.allCases.map(\.rawValue), ["none", "heart", "bubble", "ripple", "petal", "firework", "flash", "matrix", "lightning", "emojiword", "blossom", "combo", "ink", "wave", "snow", "meteor", "lantern", "smoke", "string", "plasma", "shake", "laser", "glitch", "tone", "keyword", "letters", "sand", "sea", "tokens", "dancefloor", "goal", "fishfeed", "ice"])
        XCTAssertEqual(KeyEffect.key, "keyEffect")
        XCTAssertEqual(KeyEffect.defaultValue, .none)
        XCTAssertEqual(KeyEffect.parse(nil), .none)
        XCTAssertEqual(KeyEffect.parse("sparkle"), .none, "id lạ ⇒ Không")
        XCTAssertEqual(KeyEffect.parse(3), .none)
        XCTAssertEqual(KeyEffect.parse("heart"), .heart)
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        XCTAssertEqual(KeyEffect.load(d), .none)
        d.set("firework", forKey: KeyEffect.key)
        XCTAssertEqual(KeyEffect.load(d), .firework)
        d.removePersistentDomain(forName: suite)
    }

    func testOnlyNoneIsFree() {
        XCTAssertFalse(KeyEffect.none.isPlus)
        for e in KeyEffect.allCases where e != .none { XCTAssertTrue(e.isPlus, e.rawValue) }
    }

    func testBackupSpecWhitelistsIds() {
        let spec = BackupSettings.all.first { $0.key == KeyEffect.key }
        XCTAssertEqual(spec?.kind, .string("none", ["none", "heart", "bubble", "ripple", "petal", "firework", "flash", "matrix", "lightning", "emojiword", "blossom", "combo", "ink", "wave", "snow", "meteor", "lantern", "smoke", "string", "plasma", "shake", "laser", "glitch", "tone", "keyword", "letters", "sand", "sea", "tokens", "dancefloor", "goal", "fishfeed", "ice"]))
    }

    func testTitlesBilingual() {
        for e in KeyEffect.allCases {
            XCTAssertNotNil(L10n.en[e.title], "thiếu bản dịch: \(e.title)")
        }
        XCTAssertNotNil(L10n.en["Hiệu ứng khi bấm phím"])
    }

    // MARK: cổng Plus

    func testPlusGate() {
        PlusGate.paywallEnabled = true
        PlusGate.defaults.set(false, forKey: PlusConfig.unlockedKey)
        PlusGate.defaults.set(false, forKey: PlusConfig.debugOverrideKey)
        XCTAssertFalse(KeyEffectGate.allows)
        XCTAssertTrue(KeyEffectGate.allows(.none))
        XCTAssertFalse(KeyEffectGate.allows(.heart))
        PlusGate.defaults.set(true, forKey: PlusConfig.unlockedKey)
        XCTAssertTrue(KeyEffectGate.allows(.heart))
        PlusGate.paywallEnabled = false
        PlusGate.defaults.set(false, forKey: PlusConfig.unlockedKey)
        XCTAssertTrue(KeyEffectGate.allows(.firework), "chưa bật thanh toán ⇒ mở hết")
    }

    /// Đã chọn Trái tim rồi hết Plus (hoàn tiền / máy mới) ⇒ bàn phím không vẽ; giá trị lưu giữ nguyên.
    func testLapsedPlusDisablesButKeepsSetting() {
        PlusGate.paywallEnabled = true
        PlusGate.defaults.set(false, forKey: PlusConfig.unlockedKey)
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        d.set("heart", forKey: KeyEffect.key)
        XCTAssertEqual(KeyEffectPolicy.current(d), .none)
        XCTAssertEqual(KeyEffect.load(d), .heart)
        PlusGate.defaults.set(true, forKey: PlusConfig.unlockedKey)
        XCTAssertEqual(KeyEffectPolicy.current(d), .heart)
        d.removePersistentDomain(forName: suite)
    }

    // MARK: tự tắt

    func testAutoDisableConditions() {
        XCTAssertEqual(KeyEffectPolicy.active(setting: .heart, plus: true, lowPower: false), .heart)
        XCTAssertEqual(KeyEffectPolicy.active(setting: .heart, plus: false, lowPower: false), .none)
        XCTAssertEqual(KeyEffectPolicy.active(setting: .heart, plus: true, lowPower: true), .none,
                       "Chế độ nguồn điện thấp ⇒ tắt")
        // Giảm chuyển động không còn tắt hiệu ứng (Phil 19/10/2026) — chính sách không có tham số đó.
        XCTAssertEqual(KeyEffectPolicy.active(setting: .none, plus: true, lowPower: false), .none)
    }

    // MARK: hạt / quỹ đạo

    func testPoolCapsAndRecyclesOldest() {
        XCTAssertLessThanOrEqual(KeyEffectPool.cap, 20)
        var p = KeyEffectPool()
        var seen = Set<Int>()
        for _ in 0..<200 { let i = p.next(); XCTAssertTrue((0..<KeyEffectPool.cap).contains(i)); seen.insert(i) }
        XCTAssertEqual(seen.count, KeyEffectPool.cap)
        var q = KeyEffectPool()
        let first = q.next()
        for _ in 1..<KeyEffectPool.cap { _ = q.next() }
        XCTAssertEqual(q.next(), first, "đầy ⇒ thay ô cũ nhất")
        XCTAssertEqual(KeyEffectPool(capacity: 0).capacity, 1)
    }

    func testParticlesPerTapFitInPool() {
        for e in KeyEffect.allCases {
            XCTAssertLessThanOrEqual(e.particlesPerTap, KeyEffectPool.cap / 2, e.rawValue)
            XCTAssertEqual(e.variantCount, e.particlesPerTap * 2)
            XCTAssertLessThanOrEqual(e.burstSlots * e.layersPerBurst, KeyEffectPool.cap, e.rawValue)
            if e.isParticle { XCTAssertGreaterThanOrEqual(e.burstSlots, 3, "gõ nhanh vẫn thấy vài lần bấm gần nhất") }
        }
        XCTAssertEqual(KeyEffect.none.particlesPerTap, 0)
    }

    /// Hạt của MỘT lần bấm dùng quỹ đạo khác nhau (tim trái/giữa/phải, pháo hoa toả đều); mọi quỹ đạo
    /// gọn (không bay quá ~72pt, ≤ 1 s) — Android dùng y hệt số này.
    func testTrajectoriesDistinctAndBounded() {
        for e in KeyEffect.particleCases {
            for seed in 0..<5 {
                let vs = (0..<e.particlesPerTap).map { e.variant(particle: $0, seed: seed) }
                XCTAssertEqual(Set(vs).count, vs.count, "\(e.rawValue) seed \(seed)")
                for v in vs { XCTAssertTrue((0..<e.variantCount).contains(v)) }
            }
            for v in 0..<e.variantCount {
                let t = e.trajectory(v)
                XCTAssertLessThanOrEqual(hypot(t.dx, t.dy), 72, "\(e.rawValue) #\(v)")
                XCTAssertGreaterThan(t.duration, 0.2)
                XCTAssertLessThanOrEqual(t.duration, 1.2)
                XCTAssertGreaterThan(t.scaleTo, 0)
            }
        }
        XCTAssertLessThan(KeyEffect.heart.trajectory(0).dy, 0, "tim bay lên")
        XCTAssertLessThan(KeyEffect.heart.trajectory(0).dx, 0)
        XCTAssertGreaterThan(KeyEffect.heart.trajectory(5).dx, 0)
        XCTAssertEqual(KeyEffect.firework.trajectory(0).dx, 30, accuracy: 1e-9)
        XCTAssertEqual(KeyEffect.firework.trajectory(3).dy, 36, accuracy: 1e-9)
    }

    func testShapesAreVectorPaths() {
        for e in KeyEffect.allCases {
            let p = KeyEffectShapes.path(e)
            if !e.isParticle && e != .wave { XCTAssertNil(p, e.rawValue) } else {
                XCTAssertNotNil(p, e.rawValue)
                XCTAssertFalse(p!.boundingBoxOfPath.isEmpty, e.rawValue)
                XCTAssertLessThanOrEqual(p!.boundingBoxOfPath.width, 44)
            }
        }
    }

    // MARK: overlay

    @MainActor func testInstallNoneCreatesNothing() {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        XCTAssertNil(KeyEffectOverlay.install(.none, color: .red, in: host, existing: nil))
        XCTAssertTrue(host.subviews.isEmpty)
        let o = KeyEffectOverlay.install(.heart, color: .red, in: host, existing: nil)
        XCTAssertNotNil(o)
        XCTAssertTrue(o?.superview === host)
        XCTAssertNil(KeyEffectOverlay.install(.none, color: .red, in: host, existing: o), "đổi sang Không ⇒ gỡ")
        XCTAssertTrue(host.subviews.isEmpty)
    }

    @MainActor func testOverlayNeverTakesTouchesAndSitsBelowBalloon() {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        let o = KeyEffectOverlay.install(.bubble, color: .blue, in: host, existing: nil)!
        XCTAssertFalse(o.isUserInteractionEnabled)
        XCTAssertNil(o.hitTest(CGPoint(x: 10, y: 10), with: nil))
        XCTAssertFalse(o.point(inside: CGPoint(x: 10, y: 10), with: nil))
        XCTAssertGreaterThan(o.layer.zPosition, 0, "trên phím")
        XCTAssertLessThan(o.layer.zPosition, 10, "dưới ô phóng to (BalloonView zPosition 10)")
        XCTAssertEqual(o.frame, host.bounds)
        // Một nút phía dưới vẫn nhận chạm xuyên qua overlay.
        let b = UIButton(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        host.insertSubview(b, belowSubview: o)
        XCTAssertTrue(host.hitTest(CGPoint(x: 10, y: 10), with: nil) === b)
    }

    /// emit chỉ ghi điểm + hẹn MỘT lượt runloop (vẽ sau khi chữ đã chèn) — không vẽ đồng bộ.
    @MainActor func testEmitDefersToNextRunloop() {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        let o = KeyEffectOverlay.install(.heart, color: .red, in: host, existing: nil)!
        o.emit(at: CGPoint(x: 50, y: 100))
        o.emit(at: CGPoint(x: 60, y: 100))
        XCTAssertEqual(o.debugBurstCount, 0, "chưa vẽ trong lượt hiện tại")
        XCTAssertTrue(o.debugScheduled)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertFalse(o.debugScheduled)
        XCTAssertEqual(o.debugBurstCount, 2)
        XCTAssertEqual(o.debugParticleCount, 2 * KeyEffect.heart.particlesPerTap)
        XCTAssertEqual(o.debugPendingCount, 0)
    }

    /// Bắn lại một chùm chỉ bằng beginTime: animation chạy lại từ đầu (đọc presentation layer — CA tính
    /// trong process y như render server), xong thì vô hình (opacity 0), không gỡ/không thêm animation.
    @MainActor func testBurstReplaysByBeginTimeOnly() throws {
        let host = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        host.isHidden = false
        defer { host.isHidden = true }
        let o = KeyEffectOverlay.install(.heart, color: .red, in: host, existing: nil)!
        o.emit(at: CGPoint(x: 100, y: 150)); o.flush()
        let burst = try XCTUnwrap(o.layer.sublayers?.first)
        let particle = try XCTUnwrap(burst.sublayers?.first)
        let anim = particle.animation(forKey: "fx")
        XCTAssertNotNil(anim)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let mid = try XCTUnwrap(particle.presentation())
        XCTAssertGreaterThan(mid.opacity, 0.9, "đang bay")
        XCTAssertLessThan(mid.position.y, -5, "tim đã bay lên")
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        XCTAssertEqual(particle.presentation()?.opacity ?? 1, 0, accuracy: 0.01, "bay xong: vô hình")
        // Bắn lại đúng chùm này (vòng hết các chùm khác).
        for _ in 0..<KeyEffect.heart.burstSlots { o.emit(at: CGPoint(x: 40, y: 150)); o.flush() }
        XCTAssertEqual(o.debugBurstCount, KeyEffect.heart.burstSlots, "không dựng thêm chùm")
        XCTAssertNotNil(particle.animation(forKey: "fx"), "animation gắn một lần, không bị gỡ")
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let again = try XCTUnwrap(particle.presentation())
        XCTAssertGreaterThan(again.opacity, 0.9, "chạy lại từ đầu")
        XCTAssertEqual(burst.position, CGPoint(x: 40, y: 150))
    }

    /// 200 phím dồn dập: pool không vượt trần, không dồn điểm chờ, overlay giải phóng khi gỡ (không rò).
    @MainActor func testBurstOf200KeysStaysCappedAndDoesNotLeak() {
        weak var weakOverlay: KeyEffectOverlay?
        let footprint0 = KeyboardBenchTests.footprintMB()
        autoreleasepool {
            let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 260))
            for e in KeyEffect.allCases where e != .none {
                let o = KeyEffectOverlay.install(e, color: .systemPink, keyFill: .white, in: host, existing: nil)!
                for i in 0..<200 {
                    if e == .emojiword { o.queueEmoji(i % 2 == 0 ? "😂" : "❤️") }
                    o.emit(key: CGRect(x: CGFloat(i % 10) * 39, y: CGFloat(i % 3) * 50 + 60, width: 35, height: 42))
                    if i % 3 == 0 { o.flush() }   // gõ chồng: vài phím chung một lượt
                }
                o.flush()
                XCTAssertLessThanOrEqual(o.debugParticleCount, KeyEffectPool.cap, e.rawValue)
                XCTAssertLessThanOrEqual(o.debugStrikeCount, 3, e.rawValue)
                let topLayers = o.layer.sublayers?.count ?? 0
                switch e {
                case .flash: XCTAssertEqual(topLayers, 1, "một lớp nháy duy nhất")
                case .lightning: XCTAssertEqual(topLayers, 3, "≤ 3 cú đánh dùng lại")
                case .matrix: XCTAssertEqual(topLayers, 1, "một gốc Matrix")
                case .string: XCTAssertEqual(topLayers, StringPluck.pool, "pool đoạn dây dùng lại")
                case .plasma: XCTAssertEqual(topLayers, PlasmaArc.pool, "pool tia dùng lại")
                case .laser: XCTAssertEqual(topLayers, LaserBeam.pool)
                case .glitch: XCTAssertEqual(topLayers, GlitchFx.pool)
                case .shake: XCTAssertEqual(topLayers, 0, "rung: không vẽ gì trên overlay")
                case .sand: XCTAssertEqual(topLayers, SandPile.flying + 1, "pool hạt + một layer đống")
                case .sea:
                    XCTAssertEqual(o.debugBurstCount, SeaFx.tapSlots, "chùm bọt / bong bóng dùng lại")
                    XCTAssertLessThanOrEqual(o.debugSeaWaveRoots.count, SeaFx.maxWaves)
                    XCTAssertLessThanOrEqual(topLayers, SeaFx.tapSlots + SeaFx.maxWaves + 1, "chùm + sóng + một con cá")
                case .dancefloor:
                    XCTAssertEqual(o.debugDanceRoots.count, DanceFloor.pool, "pool chùm ô dùng lại")
                    XCTAssertLessThanOrEqual(topLayers, DanceFloor.pool + 1, "pool chùm + một lớp nháy cả bàn phím")
                case .goal:
                    XCTAssertEqual(topLayers, GrassTuft.pool, "Sút!: phím thường = pool túm cỏ dùng lại")
                case .ice:
                    XCTAssertLessThanOrEqual(topLayers, 2 * CafeFx.pool + 2, "pool đá + giọt, phin, một vòng sữa")
                case .fishfeed:
                    XCTAssertLessThanOrEqual(topLayers, AquariumFx.maxFish + AquariumFx.maxPellets, "≤ 6 cá + 8 viên, không mọc thêm")
                case .tone, .keyword, .letters, .tokens:
                    XCTAssertEqual(topLayers, 0, "chưa có sự kiện xếp hàng ⇒ phím thường không vẽ gì")
                default:
                    XCTAssertEqual(o.debugBurstCount, e.burstSlots, e.rawValue)
                    XCTAssertEqual(topLayers, e.burstSlots, "chùm dùng lại, không mọc thêm layer")
                }
                XCTAssertEqual(o.debugPendingCount, 0)
                if e == .emojiword { o.queueEmoji("😂") }
                for i in 0..<10 { o.emit(at: CGPoint(x: CGFloat(i), y: 1)) }
                XCTAssertLessThanOrEqual(o.debugPendingCount, 4, "gõ dồn trong một lượt: chỉ giữ vài điểm mới nhất")
                o.flush()
                o.halt()
                weakOverlay = o
                XCTAssertNil(KeyEffectOverlay.install(.none, color: .red, in: host, existing: o))
            }
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))   // block hẹn giờ (weak self) chạy xong
        XCTAssertNil(weakOverlay, "overlay gỡ ra phải được giải phóng")
        let grew = KeyboardBenchTests.footprintMB() - footprint0
        XCTAssertLessThan(grew, 8, "RAM sau 5 × 200 phím (MB)")
    }

    // MARK: KeyboardView

    @MainActor private func withKeyboard(effect: String?, plus: Bool, _ body: (KeyboardView, UIWindow) throws -> Void) rethrows {
        PlusGate.paywallEnabled = true
        PlusGate.defaults.set(plus, forKey: PlusConfig.unlockedKey)
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
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
        kb.layoutIfNeeded()
        try body(kb, win)
        win.isHidden = true
    }

    /// Mặc định / hết Plus: KHÔNG có overlay (0 chi phí) — gõ vẫn như cũ.
    @MainActor func testKeyboardOffMeansNoOverlay() throws {
        try withKeyboard(effect: nil, plus: true) { kb, _ in
            XCTAssertNil(kb.keyEffects)
            XCTAssertFalse(kb.subviews.contains { $0 is KeyEffectOverlay })
        }
        try withKeyboard(effect: "heart", plus: false) { kb, _ in
            XCTAssertNil(kb.keyEffects, "chưa có Plus ⇒ không tạo overlay")
        }
    }

    /// Bật: gõ chữ ⇒ chữ chèn ngay (đồng bộ), hạt chỉ xuất hiện ở lượt runloop sau, tại phím vừa bấm.
    @MainActor func testKeyboardTypingInsertsFirstThenAnimates() throws {
        var typed: [KeyboardView.Key] = []
        PlusGate.paywallEnabled = true
        PlusGate.defaults.set(true, forKey: PlusConfig.unlockedKey)
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        d.set("heart", forKey: KeyEffect.key)
        let saved = UserDefaultsProvider.shared
        UserDefaultsProvider.shared = d
        defer { UserDefaultsProvider.shared = saved; d.removePersistentDomain(forName: suite) }
        let win = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 300))
        win.isHidden = false
        let kb = KeyboardView(needsGlobe: false, inputController: nil) { typed.append($0) }
        kb.frame = win.bounds
        win.addSubview(kb)
        kb.applyAppearance(.light, style: .light)
        kb.layoutIfNeeded()
        let o = try XCTUnwrap(kb.keyEffects)
        XCTAssertTrue(o.superview === kb)
        let f = try XCTUnwrap(kb.debugLetterFrame("a"))
        kb.benchTap(at: CGPoint(x: f.midX, y: f.midY), time: 1)
        guard case .letter(let ch)? = typed.last else { return XCTFail("không chèn chữ") }
        XCTAssertEqual(String(ch).lowercased(), "a")   // shift đầu câu có thể bật
        XCTAssertEqual(o.debugBurstCount, 0, "chưa vẽ gì trong lượt chạm")
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(o.debugBurstCount, 1)
        XCTAssertEqual(o.debugParticleCount, KeyEffect.heart.particlesPerTap)
        // Chùm đặt tại tâm phím "a".
        let positions = o.debugBurstPositions
        XCTAssertTrue(positions.allSatisfy { abs($0.x - f.midX) < 1 && abs($0.y - f.midY) < 1 }, "\(positions) vs \(f)")
        // ⌫ không mang hiệu ứng (không đánh dấu điểm) — không bắn thêm.
        _ = kb.debugBackspaceSwipe(from: 0, through: [])
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(o.debugBurstCount, 1)
        // Đổi sang Không ở lần hiện kế ⇒ gỡ overlay.
        d.set("none", forKey: KeyEffect.key)
        kb.applyAppearance(.light, style: .light)
        XCTAssertNil(kb.keyEffects)
        XCTAssertFalse(kb.subviews.contains { $0 is KeyEffectOverlay })
        win.isHidden = true
    }

    /// Overlay nằm dưới ô phóng to.
    @MainActor func testOverlayBelowBalloon() throws {
        try withKeyboard(effect: "ripple", plus: true) { kb, _ in
            let o = try XCTUnwrap(kb.keyEffects)
            // Thứ tự Phil: nền → phím → ảnh tiền cảnh (theme JSON) → hiệu ứng → ô phóng to.
            XCTAssertGreaterThan(o.layer.zPosition, kb.debugForegroundView.layer.zPosition, "trên ảnh tiền cảnh")
            kb.debugSetKeyPreview(true)
            let f = try XCTUnwrap(kb.debugLetterFrame("q"))
            kb.benchTap(at: CGPoint(x: f.midX, y: f.midY), time: 1)
            let balloon = kb.subviews.first { $0.layer.zPosition == 10 }
            if let balloon { XCTAssertLessThan(o.layer.zPosition, balloon.layer.zPosition) }
        }
    }

    // MARK: A/B chi phí main thread (bộ chậm)

    /// Cùng process, xen kẽ khối TẮT / BẬT (mỗi kiểu) để trôi nhiệt / nhiễu chia đều. Mỗi phím: thời gian
    /// đồng bộ (chạm → chèn xong) + CPU main gồm lượt vẽ hoãn. In "KEYFX …" cho báo cáo.
    @MainActor func testMainThreadCostPerKeyOnVsOff() throws {
        try SlowTests.require()
        PlusGate.paywallEnabled = false
        let saved = UserDefaultsProvider.shared
        defer { UserDefaultsProvider.shared = saved }
        let keys = Array("xinchaomoinguoihomnaytoiddilamvieccongty")
        func run(_ effect: KeyEffect, rounds: Int) -> (sync: [Double], main: [Double], fx: [Double]) {
            let name = "vt-keyfx-bench-\(effect.rawValue)"
            let d = UserDefaults(suiteName: name)!
            d.removePersistentDomain(forName: name)
            d.set(effect.rawValue, forKey: KeyEffect.key)
            d.set(true, forKey: KeyboardView.keyPreviewKey)
            UserDefaultsProvider.shared = d
            let win = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 290))
            win.isHidden = false
            let kb = KeyboardView(needsGlobe: false, inputController: nil) { _ in }
            kb.frame = win.bounds
            win.addSubview(kb)
            kb.applyAppearance(.light, style: .light)
            kb.layoutIfNeeded()
            XCTAssertEqual(kb.keyEffects?.effect ?? .none, effect)
            var sync: [Double] = [], main: [Double] = [], fx: [Double] = []
            for r in 0..<rounds {
                for c in keys {
                    guard let f = kb.debugLetterFrame(String(c)) else { continue }
                    KeyEffectOverlay.debugCost = 0
                    let c0 = KeyboardBenchTests.mainThreadCPU()
                    let t0 = CACurrentMediaTime()
                    kb.benchTap(at: CGPoint(x: f.midX, y: f.midY), time: t0)
                    let t1 = CACurrentMediaTime()
                    KeyboardBenchTests.spin(0.03)   // lượt vẽ hoãn + commit CA
                    if r > 0 {   // vòng đầu: làm nóng
                        sync.append((t1 - t0) * 1000)
                        main.append((KeyboardBenchTests.mainThreadCPU() - c0) * 1000)
                        fx.append(KeyEffectOverlay.debugCost * 1000)
                    }
                }
            }
            win.isHidden = true
            kb.tearDown()
            d.removePersistentDomain(forName: name)
            return (sync, main, fx)
        }
        let p = KeyboardBenchTests.pct
        _ = run(.none, rounds: 2)   // làm nóng cả process
        // Đo lại vài kiểu: TEST_RUNNER_VT_KEYFX_ONLY=matrix,lightning (xcodebuild chuyển env cho runner).
        let only = Set((ProcessInfo.processInfo.environment["VT_KEYFX_ONLY"] ?? "").split(separator: ",").map(String.init))
        for e in KeyEffect.allCases where e != .none && (only.isEmpty || only.contains(e.rawValue)) {
            var offS: [Double] = [], offM: [Double] = [], onS: [Double] = [], onM: [Double] = [], fx: [Double] = []
            var dMainBlocks: [Double] = [], dSyncBlocks: [Double] = []
            for _ in 0..<6 {   // xen kẽ khối TẮT / BẬT: trôi nhiệt / tải máy chia đều
                let a = run(.none, rounds: 2), b = run(e, rounds: 2)
                offS += a.sync; offM += a.main; onS += b.sync; onM += b.main; fx += b.fx
                dMainBlocks.append(p(b.main, 0.5) - p(a.main, 0.5))
                dSyncBlocks.append(p(b.sync, 0.5) - p(a.sync, 0.5))
            }
            let dMain = p(dMainBlocks, 0.5), dSync = p(dSyncBlocks, 0.5)
            let line = String(format: "KEYFX %@ n=%d | trực tiếp emit+flush p50=%.4f p95=%.4f p99=%.4f ms | A/B main_p50 off=%.3f on=%.3f Δ(trung vị khối)=%.3f | sync_p50 off=%.3f on=%.3f Δ=%.3f | main_p95 off=%.3f on=%.3f",
                              e.rawValue, onS.count, p(fx, 0.5), p(fx, 0.95), p(fx, 0.99),
                              p(offM, 0.5), p(onM, 0.5), dMain, p(offS, 0.5), p(onS, 0.5), dSync,
                              p(offM, 0.95), p(onM, 0.95))
            print(line)
            XCTContext.runActivity(named: line) { _ in }
            // Ngưỡng Phil: tăng > ~0,3 ms/phím trên main là không phát hành. Phần của hiệu ứng đo trực tiếp
            // (chặt); A/B cả đường phím có nhiễu simulator ±0,2 ms nên dùng trung vị các khối xen kẽ.
            XCTAssertLessThan(p(fx, 0.95), 0.3, "\(e.rawValue): emit+flush p95 (ms)")
            XCTAssertLessThan(dMain, 0.3, "\(e.rawValue): CPU main tăng mỗi phím (ms)")
        }
    }
}

// MARK: - Đợt 2 (Phil 19/10/2026): Nháy sáng, Matrix, Tia sét, Emoji theo chữ, Hoa đào / mai, Lửa combo,
// Mực loang, Sóng nước, Tuyết rơi. Số tham chiếu (tia sét, cột Matrix) GIỐNG HỆT android KeyEffectTests.
extension KeyEffectTests {
    /// "Sao băng" (theme Vũ trụ): MỘT hạt / lần bấm, bay CHÉO lên-phải đúng góc của hình (không xoay), tắt trong
    /// 0,5 s; hình giọt một đa giác — số tham chiếu GIỐNG HỆT Android KeyEffectFxTests.meteorParity.
    func testMeteorModelAndShapeParity() {
        let m = KeyEffect.meteor
        XCTAssertTrue(m.isParticle); XCTAssertTrue(m.isPlus); XCTAssertEqual(m.band, .aboveKeys)
        XCTAssertEqual(m.particlesPerTap, 1)
        XCTAssertEqual(m.fixedColors, [0xFFE7A0])
        XCTAssertLessThanOrEqual(m.burstSlots * m.layersPerBurst, KeyEffectPool.cap)
        let ref: [(Double, Double)] = [(45.900289, -32.080578), (52.457473, -36.663517)]
        for v in 0..<m.variantCount {
            let t = m.trajectory(v)
            XCTAssertEqual(t.dx, ref[v].0, accuracy: 1e-5); XCTAssertEqual(t.dy, ref[v].1, accuracy: 1e-5)
            XCTAssertEqual(t.rotation, 0, "vệt không xoay — hình đã đặt theo hướng bay")
            XCTAssertEqual(atan2(t.dy, t.dx), MeteorStreak.angle, accuracy: 1e-9, "bay đúng hướng vệt")
            XCTAssertEqual(t.duration, 0.5, accuracy: 1e-9)
        }
        let poly = MeteorStreak.polygon()
        let want: [(Double, Double)] = [(1.374882, 1.967155), (2.174260, 1.016165), (2.391047, -0.207105), (1.967155, -1.374882),
                                        (1.016165, -2.174260), (-0.207105, -2.391047), (-1.374882, -1.967155), (-21.310848, 14.894554)]
        XCTAssertEqual(poly.count, want.count)
        for (a, b) in zip(poly, want) { XCTAssertEqual(a.x, b.0, accuracy: 1e-5); XCTAssertEqual(a.y, b.1, accuracy: 1e-5) }
        // Đuôi nằm ngược hướng bay (phía dưới-trái), đầu tròn quanh gốc.
        XCTAssertLessThan(poly.last!.x, 0); XCTAssertGreaterThan(poly.last!.y, 0)
        let box = KeyEffectShapes.meteor().boundingBoxOfPath
        XCTAssertLessThan(box.width, 30); XCTAssertLessThan(box.height, 22)
        XCTAssertNotNil(KeyEffectShapes.path(.meteor))
    }

    func testNewEffectsModel() {
        XCTAssertEqual(KeyEffect.allCases.filter { $0.band == .belowKeys }, [.matrix, .ink, .wave, .string])
        for e in KeyEffect.allCases where e != .none { XCTAssertTrue(e.isPlus, e.rawValue) }
        XCTAssertEqual(KeyEffect.blossom.fixedColors, [0xFF8FB1, 0xFFC93C], "đào hồng + mai vàng, không theo màu nhấn")
        XCTAssertEqual(KeyEffect.snow.fixedColors, [0xFFFFFF])
        XCTAssertEqual(KeyEffect.matrix.fixedColors, [0x00FF41])
        XCTAssertTrue(KeyEffect.heart.fixedColors.isEmpty)
        XCTAssertTrue((3...5).contains(KeyEffect.snow.particlesPerTap), "3–5 bông tuyết mỗi phím")
        for v in 0..<KeyEffect.snow.variantCount {
            XCTAssertGreaterThan(KeyEffect.snow.trajectory(v).dy, 0, "tuyết rơi XUỐNG")
            XCTAssertGreaterThan(KeyEffect.snow.trajectory(v).sway, 0, "lắc ngang")
            XCTAssertLessThan(KeyEffect.blossom.trajectory(v % KeyEffect.blossom.variantCount).dy, 0, "hoa bay lên")
        }
        XCTAssertEqual(KeyEffect.snow.trajectory(0).duration, 1.2, accuracy: 1e-9)
    }

    // MARK: Nháy sáng — trần nhịp, đỉnh thấp, tắt dần

    func testFlashPulseRateCapAndGentleCurve() {
        XCTAssertLessThanOrEqual(FlashPulse.peak, 0.25, "đỉnh thấp (nhạy cảm ánh sáng)")
        XCTAssertGreaterThanOrEqual(FlashPulse.minInterval, 0.06)
        var f = FlashPulse()
        XCTAssertTrue(f.trigger(at: 10))
        XCTAssertFalse(f.trigger(at: 10.03), "< 60 ms ⇒ bỏ qua (xung đang chạy, không chồng)")
        XCTAssertFalse(f.trigger(at: 10.059))
        XCTAssertTrue(f.trigger(at: 10.06))
        // 200 phím cách 10 ms (2 s) ⇒ tối đa 2 s / 60 ms + 1 xung.
        var g = FlashPulse()
        let n = (0..<200).filter { g.trigger(at: Double($0) * 0.01) }.count
        XCTAssertLessThanOrEqual(n, 34)
        XCTAssertEqual(FlashPulse.alpha(0), FlashPulse.peak, accuracy: 1e-12)
        XCTAssertEqual(FlashPulse.alpha(FlashPulse.duration), 0)
        XCTAssertEqual(FlashPulse.alpha(-0.01), 0)
        var prev = 1.0
        for k in 0...12 { let a = FlashPulse.alpha(Double(k) * 0.01); XCTAssertLessThanOrEqual(a, prev); prev = a }
    }

    @MainActor func testFlashOverlayIsOneFullLayerAndCapsRate() throws {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 260))
        let o = try XCTUnwrap(KeyEffectOverlay.install(.flash, color: .red, in: host, existing: nil))
        for _ in 0..<8 { o.emit(at: CGPoint(x: 10, y: 10)); o.flush() }   // 8 phím trong < 60 ms
        XCTAssertEqual(o.debugFlashFired, 1, "gõ dồn < 60 ms: một xung")
        let l = try XCTUnwrap(o.debugFlashLayer)
        XCTAssertEqual(l.frame, host.bounds, "phủ cả bàn phím")
        XCTAssertEqual(o.layer.sublayers?.count, 1)
        XCTAssertEqual(l.opacity, 0, "nghỉ: trong suốt")
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        o.emit(at: CGPoint(x: 10, y: 10)); o.flush()
        XCTAssertEqual(o.debugFlashFired, 2)
        XCTAssertEqual(o.layer.sublayers?.count, 1, "không chồng lớp")
    }

    // MARK: Tia sét

    func testLightningBoltDeterministicParity() {
        let p = LightningBolt.points(height: 120, variant: 2)
        XCTAssertEqual(p.count, LightningBolt.segments + 1)
        // Cùng số với android KeyEffectTests.lightningBoltParity.
        let ref: [(Double, Double)] = [(9.434043, -120), (4.295992, -102.857143), (11.736669, -85.714286),
                                       (-4.608798, -68.571429), (6.767128, -51.428571), (8.904401, -34.285714),
                                       (-3.299798, -17.142857), (0, 0)]
        for (a, b) in zip(p, ref) {
            XCTAssertEqual(a.x, b.0, accuracy: 1e-5)
            XCTAssertEqual(a.y, b.1, accuracy: 1e-5)
        }
        XCTAssertEqual(LightningBolt.points(height: 120, variant: 2).map(\.x), p.map(\.x), "tất định")
        XCTAssertNotEqual(LightningBolt.points(height: 120, variant: 3).map(\.x), p.map(\.x))
        for v in 0..<LightningBolt.variants {
            let q = LightningBolt.points(height: 200, variant: v)
            XCTAssertEqual(q.first!.y, -200); XCTAssertEqual(q.last!.x, 0); XCTAssertEqual(q.last!.y, 0)
            for pt in q { XCTAssertLessThanOrEqual(abs(pt.x), 40) }
        }
    }

    func testShardsTileTheKeyExactly() {
        for (w, h) in [(35.0, 42.0), (180.0, 42.0), (50.0, 50.0)] {
            let ps = LightningShards.pieces(width: w, height: h)
            XCTAssertTrue((4...6).contains(ps.count))
            XCTAssertEqual(ps.reduce(0) { $0 + $1.area }, w * h, accuracy: 1e-6, "các mảnh ghép kín đúng phím")
            for p in ps {
                XCTAssertGreaterThan(p.area, 0)
                for q in p.points {
                    XCTAssertLessThanOrEqual(abs(q.x), w / 2 + 1e-9); XCTAssertLessThanOrEqual(abs(q.y), h / 2 + 1e-9)
                }
            }
        }
        for i in 0..<LightningShards.count {
            let d = LightningShards.direction(i)
            XCTAssertEqual(hypot(d.x, d.y), 1, accuracy: 1e-9)
        }
    }

    /// Mảnh vỡ là ẢO GIÁC trên overlay: phím thật vẫn hiện, bấm được, không bị dời / ẩn / animate; chữ
    /// chèn ngay (đồng bộ) trước khi có gì được vẽ.
    @MainActor func testLightningNeverTouchesRealKey() throws {
        var typed = 0
        PlusGate.paywallEnabled = false
        let suiteName = "vt-keyeffect-lightning"
        let d = UserDefaults(suiteName: suiteName)!
        d.removePersistentDomain(forName: suiteName)
        d.set("lightning", forKey: KeyEffect.key)
        let saved = UserDefaultsProvider.shared
        UserDefaultsProvider.shared = d
        defer { UserDefaultsProvider.shared = saved; d.removePersistentDomain(forName: suiteName) }
        let win = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 300))
        win.isHidden = false
        defer { win.isHidden = true }
        let kb = KeyboardView(needsGlobe: false, inputController: nil) { _ in typed += 1 }
        kb.frame = win.bounds
        win.addSubview(kb)
        kb.applyAppearance(.light, style: .light)
        kb.layoutIfNeeded()
        let o = try XCTUnwrap(kb.keyEffects)
        let key = try XCTUnwrap(kb.debugLetterButton("g"))
        let frame0 = key.frame, center0 = key.center, transform0 = key.layer.transform
        let interaction0 = key.isUserInteractionEnabled   // phím nhận chạm qua router của KeyboardView
        let sub0 = key.layer.sublayers?.count ?? 0
        for i in 0..<5 {
            let f = try XCTUnwrap(kb.debugLetterFrame("g"))
            kb.benchTap(at: CGPoint(x: f.midX, y: f.midY), time: Double(i))
            XCTAssertEqual(typed, i + 1, "chữ chèn ngay")
            RunLoop.main.run(until: Date().addingTimeInterval(0.06))
            XCTAssertFalse(key.isHidden); XCTAssertEqual(key.alpha, 1); XCTAssertTrue(key.isEnabled)
            XCTAssertEqual(key.isUserInteractionEnabled, interaction0)
            XCTAssertEqual(key.frame, frame0); XCTAssertEqual(key.center, center0)
            XCTAssertTrue(CATransform3DEqualToTransform(key.layer.transform, transform0), "không dời / xoay phím")
            XCTAssertNil(key.layer.animation(forKey: "fx"), "không animation hiệu ứng nào trên phím thật")
            XCTAssertEqual(key.layer.sublayers?.count ?? 0, sub0, "không thêm layer vào phím thật")
        }
        XCTAssertGreaterThan(o.debugStrikeCount, 0)
        XCTAssertLessThanOrEqual(o.debugStrikeCount, 3, "trần cú đánh")
        for r in o.debugStrikeRoots { XCTAssertTrue(r.superlayer === o.layer, "mảnh vỡ nằm trong overlay") }
        // Overlay không cản chạm.
        let f = try XCTUnwrap(kb.debugLetterFrame("g"))
        XCTAssertFalse(kb.hitTest(CGPoint(x: f.midX, y: f.midY), with: nil) is KeyEffectOverlay)
    }

    // MARK: Matrix / Mực loang / Sóng nước — dải dưới phím

    @MainActor func testBelowKeysBandZOrder() throws {
        for id in ["matrix", "ink", "wave", "string"] {
            try withKeyboardFx(effect: id) { kb in
                let o = try XCTUnwrap(kb.keyEffects, id)
                let subs = kb.subviews
                let oi = try XCTUnwrap(subs.firstIndex(of: o))
                let ki = try XCTUnwrap(subs.firstIndex(of: kb.debugRowsContainer))
                XCTAssertLessThan(oi, ki, "\(id): dưới hàng phím")
                XCTAssertEqual(o.layer.zPosition, kb.debugRowsContainer.layer.zPosition, "\(id): cùng z, thứ tự subview quyết định")
                for b in kb.debugBackdropViews where b.superview === kb {
                    XCTAssertGreaterThan(oi, subs.firstIndex(of: b)!, "\(id): trên nền / ảnh nền")
                    XCTAssertGreaterThanOrEqual(o.layer.zPosition, b.layer.zPosition)
                }
                XCTAssertFalse(o.isUserInteractionEnabled)
            }
        }
        // Kiểu trên phím vẫn ở trên.
        try withKeyboardFx(effect: "lightning") { kb in
            let o = try XCTUnwrap(kb.keyEffects)
            XCTAssertGreaterThan(o.layer.zPosition, kb.debugRowsContainer.layer.zPosition)
        }
    }

    @MainActor private func withKeyboardFx(effect: String, _ body: (KeyboardView) throws -> Void) rethrows {
        PlusGate.paywallEnabled = false
        let name = "vt-keyeffect-band"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        d.set(effect, forKey: KeyEffect.key)
        let saved = UserDefaultsProvider.shared
        UserDefaultsProvider.shared = d
        defer { UserDefaultsProvider.shared = saved; d.removePersistentDomain(forName: name) }
        let win = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 300))
        win.isHidden = false
        defer { win.isHidden = true }
        let kb = KeyboardView(needsGlobe: false, inputController: nil) { _ in }
        kb.frame = win.bounds
        win.addSubview(kb)
        kb.applyAppearance(.dark, style: .dark)
        kb.layoutIfNeeded()
        try body(kb)
    }

    /// Matrix chỉ chạy khi gõ: nghỉ ⇒ mờ dần rồi gỡ SẠCH animation (0 việc cho render server); ẩn bàn phím
    /// ⇒ dừng ngay.
    @MainActor func testMatrixRunsOnlyWhileTypingThenStops() throws {
        let win = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 260))
        win.isHidden = false
        defer { win.isHidden = true }
        let o = try XCTUnwrap(KeyEffectOverlay.install(.matrix, color: .red, dark: true, in: win, existing: nil))
        XCTAssertEqual(o.debugMatrixAnimationCount, 0, "chưa gõ: không animation")
        o.debugSetMatrixIdle(0.15)
        o.emit(at: CGPoint(x: 100, y: 100)); o.flush()
        XCTAssertTrue(o.debugMatrixRunning)
        XCTAssertEqual(o.debugMatrixAnimationCount, MatrixRain.columnCount(width: 390))
        XCTAssertFalse(o.debugMatrixRoot?.isHidden ?? true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        XCTAssertTrue(o.debugMatrixStripsReady, "dải ảnh dựng ngoài main")
        o.emit(at: CGPoint(x: 100, y: 100)); o.flush()   // gõ lại lúc đang mờ dần ⇒ huỷ dừng, chạy tiếp
        XCTAssertTrue(o.debugMatrixRunning)
        XCTAssertGreaterThan(o.debugMatrixRoot?.opacity ?? 0, 0)
        RunLoop.main.run(until: Date().addingTimeInterval(0.15 + MatrixRain.fadeOut + 0.4))
        XCTAssertFalse(o.debugMatrixRunning, "nghỉ ⇒ dừng")
        XCTAssertEqual(o.debugMatrixAnimationCount, 0, "nghỉ: 0 animation")
        XCTAssertTrue(o.debugMatrixRoot?.isHidden ?? false)
        // Gõ lại rồi ẩn bàn phím ⇒ dừng ngay.
        o.emit(at: CGPoint(x: 100, y: 100)); o.flush()
        XCTAssertGreaterThan(o.debugMatrixAnimationCount, 0)
        o.removeFromSuperview()
        XCTAssertEqual(o.debugMatrixAnimationCount, 0, "ẩn bàn phím ⇒ dừng")
        XCTAssertFalse(o.debugMatrixRunning)
    }

    func testMatrixClockAndColumnsParity() {
        var c = MatrixClock()
        XCTAssertTrue(c.poke(at: 1))
        XCTAssertFalse(c.poke(at: 2))
        XCTAssertEqual(c.idleRemaining(at: 3), MatrixRain.idleAfter - 1, accuracy: 1e-9)
        XCTAssertEqual(c.presses, 2)
        c.stop()
        XCTAssertFalse(c.running)
        XCTAssertTrue(c.poke(at: 10))
        XCTAssertLessThan(MatrixRain.maxOpacity(dark: false), MatrixRain.maxOpacity(dark: true), "theme sáng dịu hơn")
        XCTAssertEqual(MatrixRain.intensity(presses: 1), 0.55, accuracy: 1e-9)
        XCTAssertEqual(MatrixRain.intensity(presses: 50), 1)
        // Cùng số Android.
        let c0 = MatrixRain.column(0), c5 = MatrixRain.column(5)
        XCTAssertEqual(c0.strip, 0); XCTAssertEqual(c0.duration, 2.4423575, accuracy: 1e-6)
        XCTAssertEqual(c0.phase, 0.2594339, accuracy: 1e-6); XCTAssertEqual(c5.jitter, -1.7847257, accuracy: 1e-6)
        XCTAssertEqual(MatrixRain.rowAlpha(MatrixRain.rows - 1), 1, accuracy: 1e-9)
        XCTAssertLessThan(MatrixRain.rowAlpha(0), 0.1, "đuôi mờ")
        XCTAssertTrue(MatrixRain.glyphs.contains("đ"))
        XCTAssertLessThanOrEqual(MatrixRain.columnCount(width: 1366), 28)
    }

    // MARK: Lửa combo

    func testComboMeterLevelsAndCooldown() {
        var m = ComboMeter()
        // Chậm (2 phím/giây) ⇒ 0.
        for i in 0..<10 { XCTAssertEqual(m.press(at: Double(i) * 0.5), 0) }
        // Nhanh: 8 phím/giây ⇒ lên dần tới 3.
        var levels: [Int] = []
        for i in 0..<20 { levels.append(m.press(at: 10 + Double(i) * 0.125)) }
        XCTAssertEqual(levels.last, 3)
        XCTAssertEqual(levels, levels.sorted(), "mức chỉ tăng khi gõ đều nhanh")
        XCTAssertTrue(levels.contains(1) && levels.contains(2))
        // Nguội sau ~1 s không gõ.
        XCTAssertGreaterThan(m.level(at: 10 + 19 * 0.125 + 0.9), 0, "còn trong 1 s: còn lửa")
        XCTAssertEqual(m.level(at: 10 + 19 * 0.125 + 1.1), 0)
        XCTAssertEqual(m.press(at: 20), 0, "sau nghỉ: đếm lại từ đầu")
        XCTAssertEqual(ComboMeter.scales.count, 4)
        XCTAssertEqual(ComboMeter.scales, ComboMeter.scales.sorted(), "lửa lớn dần theo mức")
    }

    @MainActor func testComboFlamesGrowWithLevel() throws {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 260))
        let o = try XCTUnwrap(KeyEffectOverlay.install(.combo, color: .red, in: host, existing: nil))
        o.emit(at: CGPoint(x: 50, y: 100)); o.flush()
        XCTAssertEqual(o.debugBurstCount, 0, "một phím lẻ: chưa có lửa")
        for _ in 0..<ComboMeter.thresholds[2] { o.emit(at: CGPoint(x: 50, y: 100)); o.flush() }
        let last = try XCTUnwrap(o.debugBursts.max { $0.beginTime < $1.beginTime })   // chùm vừa bắn
        XCTAssertEqual(last.sublayers?.filter { !$0.isHidden }.count, 3, "mức 3: 3 ngọn")
        XCTAssertGreaterThan(last.transform.m11, 1.2)
    }

    // MARK: Emoji theo chữ

    func testEmojiWordsLookup() {
        XCTAssertTrue((30...60).contains(EmojiWords.entries.count))
        XCTAssertEqual(EmojiWords.entries.count, 56, "cùng bảng Android")
        XCTAssertEqual(EmojiWords.distinctEmojis.count, 17)
        XCTAssertEqual(EmojiWords.lookup(word: "haha", prev: nil), "😂")
        XCTAssertEqual(EmojiWords.lookup(word: "Haha!", prev: nil), "😂")
        XCTAssertEqual(EmojiWords.lookup(word: "yeu", prev: nil), "❤️", "không phân biệt dấu")
        XCTAssertEqual(EmojiWords.lookup(word: "yêu", prev: "em"), "❤️")
        XCTAssertEqual(EmojiWords.lookup(word: "mừng", prev: "chúc"), "🎉", "cụm 2 từ")
        XCTAssertEqual(EmojiWords.lookup(word: "nhật", prev: "Sinh"), "🎉")
        XCTAssertEqual(EmojiWords.lookup(word: "ơn", prev: "cảm"), "🙏")
        XCTAssertEqual(EmojiWords.lookup(word: "on", prev: "cam"), "🙏")
        XCTAssertEqual(EmojiWords.lookup(word: "ngủ", prev: "buồn"), "😴", "cụm thắng từ lẻ")
        XCTAssertEqual(EmojiWords.lookup(word: "ngủ", prev: nil), "😴")
        XCTAssertNil(EmojiWords.lookup(word: "ngu", prev: nil), "mục strict: ngu ≠ ngủ")
        XCTAssertEqual(EmojiWords.lookup(word: "mới", prev: "năm"), "🧧")
        XCTAssertEqual(EmojiWords.lookup(word: "tết", prev: nil), "🧧")
        XCTAssertNil(EmojiWords.lookup(word: "nhà", prev: nil))
        XCTAssertNil(EmojiWords.lookup(word: "", prev: nil))
        // Lọc nhạy cảm: từ tục / cặp tục ⇒ không emoji.
        XCTAssertNil(EmojiWords.lookup(word: "fuck", prev: nil))
        XCTAssertNil(EmojiWords.lookup(word: "haha", prev: "đm"), "từ trước tục ⇒ không")
        let pair = SensitiveWords.pairs.first!
        XCTAssertTrue(EmojiWords.blocked(pair.value.first!, prev: pair.key))
        for (form, _, _) in EmojiWords.entries {
            for w in form.split(separator: " ") { XCTAssertFalse(SensitiveWords.set.contains(String(w)), form) }
        }
    }

    @MainActor func testEmojiWordFiresOnlyAtBoundaryWithQueuedEmoji() throws {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 260))
        let o = try XCTUnwrap(KeyEffectOverlay.install(.emojiword, color: .red, in: host, existing: nil))
        for _ in 0..<5 { o.emit(at: CGPoint(x: 50, y: 100)) }
        XCTAssertEqual(o.debugPendingCount, 0, "phím chữ thường: không hẹn gì")
        XCTAssertFalse(o.debugScheduled)
        o.queueEmoji("😂")
        o.emit(key: CGRect(x: 100, y: 200, width: 160, height: 42))
        o.flush()
        XCTAssertEqual(o.debugBurstCount, 1)
        XCTAssertNotNil(o.debugBursts[0].sublayers?.first?.contents, "ảnh emoji")
        XCTAssertEqual(o.debugBursts[0].position, CGPoint(x: 180, y: 221), "từ phím ranh giới")
        o.emit(at: CGPoint(x: 1, y: 1)); o.flush()
        XCTAssertEqual(o.debugBurstCount, 1, "emoji dùng một lần")
        // Kiểu khác bỏ qua queueEmoji.
        let p = try XCTUnwrap(KeyEffectOverlay.install(.heart, color: .red, in: UIView(frame: host.bounds), existing: nil))
        p.queueEmoji("😂"); p.emit(at: CGPoint(x: 5, y: 5)); p.flush()
        XCTAssertEqual(p.debugParticleCount, KeyEffect.heart.particlesPerTap)
    }

    // MARK: Hoa / tuyết — màu cố định

    @MainActor func testFixedColorParticles() throws {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 260))
        let o = try XCTUnwrap(KeyEffectOverlay.install(.blossom, color: .blue, in: host, existing: nil))
        o.emit(at: CGPoint(x: 50, y: 100)); o.flush()
        let fills = (o.debugBursts[0].sublayers ?? []).compactMap { ($0 as? CAShapeLayer)?.fillColor }
        XCTAssertEqual(fills.count, 3)
        XCTAssertFalse(fills.contains { $0 == UIColor.blue.cgColor }, "không theo màu nhấn")
        let s = try XCTUnwrap(KeyEffectOverlay.install(.snow, color: .blue, dark: true, in: UIView(frame: host.bounds), existing: nil))
        s.emit(at: CGPoint(x: 50, y: 100)); s.flush()
        let sl = (s.debugBursts[0].sublayers ?? []).compactMap { $0 as? CAShapeLayer }
        XCTAssertEqual(sl.count, KeyEffect.snow.particlesPerTap)
        var w: CGFloat = 0
        UIColor(cgColor: sl[0].fillColor!).getWhite(&w, alpha: nil)
        XCTAssertEqual(w, 1, accuracy: 0.01, "tuyết trắng (theme tối)")
    }

    // MARK: Đèn lồng / Sương ma (bộ theme đủ món 10/2026)

    func testLanternSmokeModel() {
        for e in [KeyEffect.lantern, .smoke] {
            XCTAssertTrue(e.isParticle && e.usesGlow && e.isPlus, e.rawValue)
            XCTAssertEqual(e.band, .aboveKeys)
            XCTAssertFalse(e.fixedColors.isEmpty, "màu cố định, không theo màu nhấn")
            for v in 0..<e.variantCount {
                let t = e.trajectory(v)
                XCTAssertLessThan(t.dy, 0, "\(e) bay LÊN")
                XCTAssertGreaterThan(t.sway, 0)
            }
        }
        XCTAssertFalse(KeyEffect.heart.usesGlow)
        // Đèn trời: bay cao + nhỏ dần (xa dần); sương: phồng to, tan.
        XCTAssertLessThan(KeyEffect.lantern.trajectory(0).dy, -50)
        XCTAssertLessThan(KeyEffect.lantern.trajectory(0).scaleTo, KeyEffect.lantern.trajectory(0).scaleFrom)
        XCTAssertGreaterThan(KeyEffect.smoke.trajectory(0).scaleTo, KeyEffect.smoke.trajectory(0).scaleFrom)
        // Mốc chung Android (KeyEffectFxTests.lanternSmokeModel).
        XCTAssertEqual(KeyEffect.lantern.trajectory(3).dx, 10, accuracy: 1e-9)
        XCTAssertEqual(KeyEffect.lantern.trajectory(3).dy, -66, accuracy: 1e-9)
        XCTAssertEqual(KeyEffect.smoke.trajectory(5).duration, 1.1, accuracy: 1e-9)
        XCTAssertEqual(GlowSprite.stops(.lantern).count, 4)
        XCTAssertEqual(L10n.en["Đèn lồng"], "Lantern glow"); XCTAssertEqual(L10n.en["Sương ma"], "Spooky mist")
    }

    /// Đốm sáng: ảnh dựng MỘT lần mỗi màu lúc cài; mỗi lần bấm chỉ dời layer (không vẽ lại ảnh), ≤ trần layer.
    @MainActor func testGlowParticlesUseSharedImages() throws {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 260))
        for e in [KeyEffect.lantern, .smoke] {
            let o = try XCTUnwrap(KeyEffectOverlay.install(e, color: .blue, dark: true, in: host, existing: nil))
            XCTAssertEqual(o.debugGlowCount, e.fixedColors.count)
            for i in 0..<60 { o.emit(at: CGPoint(x: 10 + i, y: 100)); o.flush() }
            XCTAssertLessThanOrEqual(o.debugParticleCount, KeyEffectPool.cap)
            let layers = o.debugBursts.flatMap { $0.sublayers ?? [] }
            XCTAssertTrue(layers.allSatisfy { $0.contents != nil && !($0 is CAShapeLayer) }, e.rawValue)
            let images = Set(layers.map { ObjectIdentifier($0.contents as AnyObject) })
            XCTAssertLessThanOrEqual(images.count, e.fixedColors.count, "dùng chung ảnh, không dựng mỗi phím")
            _ = KeyEffectOverlay.install(.none, color: .blue, in: host, existing: o)
        }
    }

    /// Bộ chậm: Matrix sau khi dừng KHÔNG tốn CPU main (so với không có hiệu ứng). In "KEYFX-IDLE".
    @MainActor func testMatrixIdleCostIsZero() throws {
        try SlowTests.require()
        let win = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 290))
        win.isHidden = false
        defer { win.isHidden = true }
        func cpu(_ sec: Double) -> Double {
            let c0 = KeyboardBenchTests.mainThreadCPU()
            KeyboardBenchTests.spin(sec)
            return (KeyboardBenchTests.mainThreadCPU() - c0) * 1000
        }
        let base = cpu(1.0)
        let o = try XCTUnwrap(KeyEffectOverlay.install(.matrix, color: .red, dark: true, in: win, existing: nil))
        o.debugSetMatrixIdle(0.3)
        let c0 = KeyboardBenchTests.mainThreadCPU()
        for _ in 0..<10 { o.emit(at: CGPoint(x: 100, y: 100)); KeyboardBenchTests.spin(0.05) }
        let typing = (KeyboardBenchTests.mainThreadCPU() - c0) * 1000
        KeyboardBenchTests.spin(1.0)                    // nghỉ → mờ dần → dừng
        XCTAssertEqual(o.debugMatrixAnimationCount, 0)
        let idle = cpu(1.0)
        let line = String(format: "KEYFX-IDLE matrix main CPU: không hiệu ứng=%.3f ms/s | 10 phím (0,5 s)=%.3f ms | sau khi dừng=%.3f ms/s | animations=%d",
                          base, typing, idle, o.debugMatrixAnimationCount)
        print(line)
        XCTContext.runActivity(named: line) { _ in }
        XCTAssertLessThan(idle - base, 0.5, "nghỉ = 0 việc")
    }
}

// MARK: - Rung dây (theme Ghi-ta, 10/2026) — số tham chiếu GIỐNG HỆT Android KeyEffectFxTests.stringPluckParity
extension KeyEffectTests {
    /// Sóng dừng tắt dần: khung 0 = biên độ đỉnh, khung cuối = 0 (dây đứng yên), hai đầu dây cố định; khe gần nhất.
    func testStringPluckModel() {
        XCTAssertEqual(KeyEffect.string.band, .belowKeys)
        XCTAssertFalse(KeyEffect.string.isParticle)
        XCTAssertTrue(KeyEffect.string.fixedColors.isEmpty, "màu nhấn theme (vàng hổ phách ở Ghi-ta)")
        XCTAssertEqual(KeyEffect.string.burstSlots, StringPluck.pool)
        XCTAssertEqual(L10n.en[KeyEffect.string.title], "String vibration")
        XCTAssertEqual(StringPluck.amplitude(frame: 0), StringPluck.amplitude)
        XCTAssertEqual(StringPluck.amplitude(frame: StringPluck.frames), 0)
        let amps = (0...StringPluck.frames).map { StringPluck.amplitude(frame: $0) }
        let golden = [3.0, 0.4329, -1.9465, -0.8606, 1.0957, 0.9104, -0.4938, -0.7711, 0.1184, 0.5666, 0.0818, -0.3676, -0.1626,
                      0.2069, 0.1720, -0.0933, -0.1456, 0.0224, 0.0]
        for (a, g) in zip(amps, golden) { XCTAssertEqual(a, g, accuracy: 1e-4) }
        for f in 1..<StringPluck.frames {   // tắt dần: không vượt bao e^(−t/τ)
            let t = Double(f) / Double(StringPluck.frames) * StringPluck.duration
            XCTAssertLessThanOrEqual(abs(amps[f]), StringPluck.amplitude * exp(-t / StringPluck.decay) + 1e-9)
        }
        let s = StringPluck.shape(frame: 0)
        XCTAssertEqual(s.count, StringPluck.points + 1)
        XCTAssertEqual(s.first!.x, -50); XCTAssertEqual(s.last!.x, 50)
        XCTAssertEqual(s.first!.y, 0, accuracy: 1e-12); XCTAssertEqual(s.last!.y, 0, accuracy: 1e-12)
        XCTAssertEqual(s[StringPluck.points / 2].y, StringPluck.amplitude, accuracy: 1e-12, "bụng sóng giữa dây")
        XCTAssertEqual(StringPluck.length(keyWidth: 33), 72.6, accuracy: 1e-9)
        XCTAssertEqual(StringPluck.length(keyWidth: 10), StringPluck.minLength)
        XCTAssertEqual(StringPluck.length(keyWidth: 200), StringPluck.maxLength)
        typealias G = KeyboardDecoration.Gap
        let gaps = [G(center: 93.5, height: 11), G(center: 146.5, height: 11), G(center: 199.5, height: 11)]
        XCTAssertEqual(StringPluck.target(keyTop: 46, keyBottom: 88, gaps: gaps).index, 0, "hàng trên ⇒ khe dưới nó")
        XCTAssertEqual(StringPluck.target(keyTop: 99, keyBottom: 141, gaps: gaps).index, 1, "giữa hai khe ⇒ khe dưới (dây trầm hơn)")
        XCTAssertEqual(StringPluck.target(keyTop: 205, keyBottom: 247, gaps: gaps).index, 2, "hàng cuối ⇒ khe trên nó")
        XCTAssertEqual(StringPluck.target(keyTop: 205, keyBottom: 247, gaps: gaps).y, 199.5)
        XCTAssertEqual(StringPluck.sweepDelay(sinceLastPluck: 0), 0.35, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(StringPluck.sweepDelay(sinceLastPluck: 0.35), 0)
        let none = StringPluck.target(keyTop: 10, keyBottom: 50, gaps: [])
        XCTAssertEqual(none.y, 54); XCTAssertEqual(none.index, 0)
    }

    /// Bàn phím thật: overlay nhận khe hàng lúc layout; mỗi lần gảy = MỘT đoạn dây (pool 4) đặt đúng tâm khe, animation
    /// TỰ GỠ khi xong (mô hình vô hình) ⇒ nghỉ gõ = 0 animation; ẩn ⇒ gỡ ngay; chi phí main < 0,3 ms/phím.
    @MainActor func testStringEffectGapsPoolIdleAndCost() throws {
        try withKeyboardFx(effect: "string") { kb in
            let o = try XCTUnwrap(kb.keyEffects)
            XCTAssertEqual(o.effect, .string)
            XCTAssertGreaterThanOrEqual(o.stringGaps.count, 3, "4 hàng phím ⇒ ≥ 3 khe")
            KeyEffectOverlay.debugCost = 0
            let key = CGRect(x: 40, y: o.stringGaps[0].center + 6, width: 33, height: 42)
            for i in 0..<10 { o.emit(key: key.offsetBy(dx: CGFloat(i * 30), dy: 0)); o.flush() }
            let perKey = KeyEffectOverlay.debugCost * 1000 / 10
            print(String(format: "KEYFX string emit+flush %.4f ms/phím", perKey))
            XCTAssertLessThan(perKey, 0.3)
            let layers = o.debugStringLayers
            XCTAssertEqual(layers.count, StringPluck.pool, "pool: gõ nhanh không dồn layer")
            let gapYs = Set(o.stringGaps.map { CGFloat($0.center) })
            for l in layers {
                XCTAssertTrue(gapYs.contains(l.position.y), "dây nằm đúng tâm khe")
                XCTAssertEqual(l.opacity, 0, "mô hình vô hình — hết animation là không còn gì vẽ")
                XCTAssertNil(l.fillColor)
                XCTAssertNotNil(l.animation(forKey: "fx"))
            }
            let a = o.debugStringAnimation
            XCTAssertTrue(a.isRemovedOnCompletion); XCTAssertEqual(a.fillMode, .removed)
            XCTAssertEqual(a.duration, StringPluck.duration, accuracy: 1e-9)
            XCTAssertEqual(a.repeatCount, 0)
            XCTAssertEqual((a.animations?.first as? CAKeyframeAnimation)?.values?.count, StringPluck.frames + 1)
            o.halt()
            XCTAssertEqual(o.debugStringAnimationCount, 0, "ẩn bàn phím ⇒ gỡ ngay")
            // Gảy rồi nghỉ: render server chạy xong 0,3 s ⇒ CA gỡ animation ⇒ 0 việc.
            o.emit(key: key); o.flush()
            XCTAssertEqual(o.debugStringAnimationCount, 1)
            KeyboardBenchTests.spin(0.8)
            XCTAssertEqual(o.debugStringAnimationCount, 0, "nghỉ gõ = 0 animation")
        }
    }

    /// Issue #151 (video 08/11): overlay gắn lúc host đang cao tạm thời (gốc bounds dời lên) giữ khung cũ
    /// ⇒ khi gốc về 0, toạ độ phím lệch cả phần dư — tia sét đánh lên thanh trạng thái. Overlay phải
    /// luôn cùng hệ toạ độ với host.
    @MainActor func testOverlayFollowsHostBoundsOrigin() {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 470))
        host.bounds.origin.y = -180                      // khung cao tạm: phần dư nằm trên nội dung
        let o = KeyEffectOverlay.install(.lightning, color: .yellow, in: host, existing: nil)!
        let key = CGRect(x: 30, y: 120, width: 34, height: 42)
        XCTAssertEqual(o.convert(key, from: host), key, "khi gắn: cùng hệ toạ độ")
        host.frame = CGRect(x: 0, y: 0, width: 400, height: 290)
        host.bounds.origin.y = 0                         // host đo lại: hết dư
        KeyEffectOverlay.match(o, to: host)
        XCTAssertEqual(o.convert(key, from: host), key, "gốc host đổi: overlay theo")
        XCTAssertEqual(o.frame, host.bounds)
    }
}

// MARK: - Đợt 3 (11/2026): Plasma, Rung combo, Laser, Glitch, Dấu thanh, Từ khoá, Chữ bay, Hạt cát.
// Số tham chiếu GIỐNG HỆT android KeyEffectFx3Tests.
extension KeyEffectTests {
    private static let fx3: [KeyEffect] = [.plasma, .shake, .laser, .glitch, .tone, .keyword, .letters, .sand]

    func testFx3ModelZeroCostHooks() {
        for e in Self.fx3 {
            XCTAssertTrue(e.isPlus, e.rawValue)
            XCTAssertEqual(e.band, .aboveKeys, e.rawValue)
            XCTAssertFalse(e.isParticle, e.rawValue)
            XCTAssertEqual(e.particlesPerTap, 0)
            XCTAssertNil(KeyEffectShapes.path(e))
        }
        XCTAssertEqual(KeyEffect.allCases.filter(\.needsComposeDiff), [.tone, .letters, .tokens])
        XCTAssertEqual(KeyEffect.allCases.filter(\.needsBoundaryWord), [.emojiword, .keyword])
        XCTAssertEqual(KeyEffect.allCases.filter(\.isQueued), [.emojiword, .tone, .keyword, .letters, .tokens])
    }

    // MARK: Dấu thanh

    func testToneDetection() {
        let cases: [(String, String, ToneFx)] = [
            ("a", "á", .sac), ("ban", "bàn", .huyen), ("ca", "cả", .hoi), ("ma", "mã", .nga), ("ho", "họ", .nang),
            ("hoa", "hoá", .sac), ("bá", "bà", .huyen), ("A", "Á", .sac), ("a", "a\u{301}", .sac),
            ("a", "â", .hat), ("a", "ă", .hat), ("e", "ê", .hat), ("o", "ô", .hat), ("á", "ấ", .hat),
            ("o", "ơ", .horn), ("u", "ư", .horn), ("tuong", "tương", .horn), ("d", "đ", .stroke), ("D", "Đ", .stroke),
            ("tiê", "tiế", .sac), ("nguyen", "nguyễn", .nga),
        ]
        for (b, a, want) in cases { XCTAssertEqual(ToneMarks.detect(before: b, after: a), want, "\(b) → \(a)") }
        for (b, a) in [("á", "as"), ("hoa", "hoan"), ("hóa", "hoá"), ("", "a"), ("a", ""), ("â", "âu"), ("đ", "đi"),
                       ("tương", "tươn"), ("abc", "abcd")] {
            XCTAssertNil(ToneMarks.detect(before: b, after: a), "\(b) → \(a)")
        }
    }

    func testToneTrajectories() {
        for i in 0..<ToneBurst.sparks {
            let s = ToneBurst.trajectory(.sac, i); XCTAssertTrue(s.dx > 0 && s.dy < 0, "sắc lên-phải")
            let h = ToneBurst.trajectory(.huyen, i); XCTAssertTrue(h.dx < 0 && h.dy > 0, "huyền xuống-trái")
        }
        XCTAssertGreaterThan(ToneBurst.trajectory(.nang, 0).dy, 0, "nặng rơi")
        XCTAssertTrue(ToneBurst.easeIn(.nang)); XCTAssertTrue(ToneBurst.stretchesX(.nga))
        for k in [ToneFx.hoi, .nga, .hat, .horn, .stroke] { XCTAssertLessThan(ToneBurst.trajectory(k, 0).dy, 0) }
        for k in ToneFx.allCases {
            XCTAssertFalse(ToneBurst.path(k).boundingBoxOfPath.isEmpty && k != .stroke, "\(k)")
            for i in 0..<ToneBurst.count(k) {
                let t = ToneBurst.trajectory(k, i)
                XCTAssertLessThanOrEqual(hypot(t.dx, t.dy), 40); XCTAssertTrue((0.3...0.6).contains(t.duration))
            }
        }
        XCTAssertEqual(ToneFx.allCases.count, 8)
        let s0 = ToneBurst.trajectory(.sac, 0)
        XCTAssertEqual(s0.dx, 9.2904, accuracy: 1e-3); XCTAssertEqual(s0.dy, -24.2835, accuracy: 1e-3)
    }

    // MARK: Từ khoá

    func testKeywordTable() {
        XCTAssertEqual(KeywordBursts.entries.map { "\($0.form):\($0.kind)" }.joined(separator: " "),
                       "haha:laugh hihi:laugh hehe:laugh kkk:laugh yêu:love thương:love love:love giận:angry bực:angry "
                       + "tết:tet năm mới:tet lì xì:tet lixi:tet")
        let hit: [String: KeywordKind] = ["haha": .laugh, "hahaha": .laugh, "HIHI": .laugh, "kkkk": .laugh, "hehehe": .laugh,
                                          "Yêu": .love, "thương!": .love, "LOVE": .love, "giận": .angry, "Bực": .angry,
                                          "Tết": .tet, "tết,": .tet, "lixi": .tet]
        for (w, k) in hit { XCTAssertEqual(KeywordBursts.lookup(word: w, prev: nil), k, w) }
        for w in ["tet", "yeu", "thường", "thuong", "gian", "buc", "kk", "ha", "hah", "hahah", "", "!!", "khóc"] {
            XCTAssertNil(KeywordBursts.lookup(word: w, prev: nil), w)
        }
        XCTAssertEqual(KeywordBursts.lookup(word: "mới", prev: "năm"), .tet, "chúc mừng năm mới")
        XCTAssertEqual(KeywordBursts.lookup(word: "xì", prev: "lì"), .tet)
        XCTAssertNil(KeywordBursts.lookup(word: "mới", prev: "mừng"))
        XCTAssertNil(KeywordBursts.lookup(word: "moi", prev: "nam"))
    }

    func testKeywordParticlesCapped() {
        XCTAssertEqual(KeywordKind.allCases.map { KeywordBursts.particles($0).count }, [3, 5, 5, 20])
        for k in KeywordKind.allCases {
            XCTAssertLessThanOrEqual(KeywordBursts.lifetime(k), 2)
            for p in KeywordBursts.particles(k) {
                XCTAssertLessThanOrEqual(abs(p.x0 + p.traj.dx) + abs(p.traj.sway), 90)
                XCTAssertLessThanOrEqual(abs(p.y0 + p.traj.dy), 90)
                if p.shape == .emoji { XCTAssertLessThan(Int(p.color), KeywordBursts.emojis(k).count) }
            }
        }
        let tet = KeywordBursts.particles(.tet)
        XCTAssertTrue(tet.contains { $0.shape == .cracker } && tet.contains { $0.shape == .spark }, "pháo đỏ nổ")
        XCTAssertTrue(tet.filter { $0.shape == .paper }.allSatisfy { $0.traj.dy > 0 && $0.easeIn }, "xác pháo rơi")
        XCTAssertTrue(tet.filter { $0.shape == .envelope }.allSatisfy { $0.traj.dy < 0 }, "lì xì bay lên")
    }

    // MARK: Rung combo

    /// Số tham chiếu — Android KeyEffectFx3Tests.shakeNumbersAndMeter giữ y hệt.
    func testShakeNumbersAndMeter() {
        XCTAssertEqual(ShakeFx.max, 7)
        XCTAssertEqual(ShakeFx.amps, [0, 3, 5, 7])
        XCTAssertEqual(ShakeFx.duration, 0.245, accuracy: 1e-12)
        for lv in -1...5 { XCTAssertLessThanOrEqual(ShakeFx.amplitude(level: lv), ShakeFx.max) }
        XCTAssertEqual(ShakeFx.amplitude(level: 0), 0)
        XCTAssertEqual((1...3).map { ShakeFx.amplitude(level: $0) }, [3, 5, 7])
        // 3–4 nhịp tắt dần: dấu x đổi chiều mỗi khung, |x| giảm dần.
        let mid = Array(ShakeFx.xs.dropFirst().dropLast())
        XCTAssertGreaterThanOrEqual(zip(mid, mid.dropFirst()).filter { $0 * $1 < 0 }.count, 5)
        XCTAssertTrue(zip(mid, mid.dropFirst()).allSatisfy { abs($0) > abs($1) })
        XCTAssertTrue(ShakeFx.ys.allSatisfy { abs($0) < 0.5 }, "dọc nhẹ hơn ngang")

        // Gõ nhanh bình thường: phím thứ 4 trong 1,2 s đã rung (≈ 3,5 phím/s).
        var m = ShakeMeter()
        XCTAssertEqual((0..<4).map { m.press(at: Double($0) * 0.3) }, [0, 0, 0, 1])
        m.reset()
        XCTAssertEqual((0..<9).map { m.press(at: Double($0) * 0.1) }, [0, 0, 0, 1, 1, 2, 2, 3, 3])
        XCTAssertEqual(m.press(at: 0.8 + 2), 0, "nghỉ ⇒ về 0")
        m.reset()
        XCTAssertEqual((0..<6).map { m.press(at: Double($0) * 0.5) }, [0, 0, 0, 0, 0, 0], "gõ chậm (2 phím/s) không rung")

        let amp = ShakeFx.amplitude(level: 3)
        for t in stride(from: -0.01, through: 0.3, by: 0.001) {
            XCTAssertLessThanOrEqual(abs(ShakeFx.offsetX(t, amp: amp)), amp + 1e-9)
            XCTAssertLessThanOrEqual(abs(ShakeFx.offsetY(t, amp: amp)), amp + 1e-9)
        }
        XCTAssertEqual(ShakeFx.offsetX(0, amp: amp), 0)
        XCTAssertEqual(ShakeFx.offsetX(ShakeFx.duration, amp: amp), 0)
        XCTAssertEqual(ShakeFx.offsetX(0.035, amp: 7), 7, accuracy: 1e-9)
        XCTAssertEqual(ShakeFx.offsetX(0.070, amp: 5), -4.25, accuracy: 1e-9)
        XCTAssertEqual(ShakeFx.offsetY(0.035, amp: 7), -2.45, accuracy: 1e-9)
        XCTAssertEqual(ShakeFx.offsetX(0.014, amp: 3), 1.2, accuracy: 1e-9)
    }

    /// Rung trên bàn phím thật, qua đường gõ thật (router → tapped → emit → flush): chỉ animation cộng dồn trên layer
    /// hàng phím ĐANG HIỆN — giữa chừng presentation lệch rõ (≥ 2pt), khung + hit-test không đổi, tự gỡ.
    /// Giảm chuyển động bật hay tắt đều rung (Phil 08/11/2026).
    @MainActor func testShakeOnKeyboardMovesDrawingOnly() throws {
        try withKeyboardFx(effect: "shake") { kb in
            let o = try XCTUnwrap(kb.keyEffects)
            XCTAssertEqual(o.effect, .shake)
            let rows = kb.debugRowsContainer
            XCTAssertTrue(o.shakeTarget === rows)
            XCTAssertNotNil(rows.window, "hàng phím đang trên màn hình")
            XCTAssertTrue(rows.isDescendant(of: kb))
            let frame0 = rows.frame
            let fA = try XCTUnwrap(kb.debugLetterFrame("a"))
            let hit0 = kb.hitTest(CGPoint(x: fA.midX, y: fA.midY), with: nil)

            // 3 phím: chưa rung.
            for (i, s) in ["t", "o", "i"].enumerated() { kb.debugTapLetter(s, at: Double(i) * 0.1); o.flush() }
            XCTAssertNil(rows.layer.animation(forKey: KeyEffectOverlay.shakeKey), "dưới ngưỡng: chưa rung")
            // Phím thứ 4 trong 1,2 s ⇒ rung.
            kb.debugTapLetter("a", at: 0.3); o.flush()
            let a = try XCTUnwrap(rows.layer.animation(forKey: KeyEffectOverlay.shakeKey) as? CAKeyframeAnimation)
            XCTAssertEqual(a.keyPath, "position")
            XCTAssertTrue(a.isAdditive)
            XCTAssertTrue(a.isRemovedOnCompletion)
            XCTAssertEqual(a.duration, ShakeFx.duration, accuracy: 1e-9)
            let pts = (a.values as? [NSValue] ?? []).map(\.cgPointValue)
            XCTAssertEqual(pts.count, ShakeFx.xs.count)
            XCTAssertEqual(pts.map { abs($0.x) }.max() ?? 0, 3, accuracy: 1e-6, "mức 1 = 3pt")
            XCTAssertEqual(rows.frame, frame0, "khung nhận chạm không đổi")
            XCTAssertTrue(kb.hitTest(CGPoint(x: fA.midX, y: fA.midY), with: nil) === hit0, "hit-test không đổi")

            // Giữa animation: hình (presentation) thật sự lệch khỏi model.
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
            let model = rows.layer.position
            let p = try XCTUnwrap(rows.layer.presentation()?.position)
            XCTAssertGreaterThan(hypot(p.x - model.x, p.y - model.y), 1, "presentation lệch giữa chừng")
            XCTAssertEqual(rows.frame, frame0)

            // Gõ dồn ⇒ mức 3 = 7pt.
            for i in 0..<6 { kb.debugTapLetter("e", at: 0.4 + Double(i) * 0.05); o.flush() }
            let a3 = try XCTUnwrap(rows.layer.animation(forKey: KeyEffectOverlay.shakeKey) as? CAKeyframeAnimation)
            XCTAssertEqual((a3.values as? [NSValue] ?? []).map { abs($0.cgPointValue.x) }.max() ?? 0, 7, accuracy: 1e-6)
            XCTAssertEqual(o.layer.sublayers?.count ?? 0, 0, "rung: không vẽ gì trên overlay")
            XCTAssertEqual(rows.frame, frame0)

            // Xong: hình về đúng chỗ (animation không fillMode giữ lại; isRemovedOnCompletion gỡ ở lần commit kế).
            RunLoop.main.run(until: Date(timeIntervalSinceNow: ShakeFx.duration + 0.15))
            let q = try XCTUnwrap(rows.layer.presentation()?.position)
            XCTAssertEqual(q.x, rows.layer.position.x, accuracy: 0.01, "hết rung: về chỗ")
            XCTAssertEqual(q.y, rows.layer.position.y, accuracy: 0.01)
            o.halt()
            XCTAssertNil(rows.layer.animation(forKey: KeyEffectOverlay.shakeKey))
        }
    }

    /// Giảm chuyển động KHÔNG tắt Rung combo (như mọi hiệu ứng): overlay không còn đọc cài đặt đó.
    @MainActor func testShakeIgnoresReduceMotion() throws {
        XCTAssertEqual(KeyEffectPolicy.active(setting: .shake, plus: true, lowPower: false), .shake)
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        let keys = UIView(frame: host.bounds)
        host.addSubview(keys)
        let o = try XCTUnwrap(KeyEffectOverlay.install(.shake, color: .red, in: host, keys: keys, existing: nil))
        for _ in 0..<ShakeMeter.thresholds[0] { o.emit(key: CGRect(x: 10, y: 10, width: 30, height: 40)); o.flush() }
        XCTAssertNotNil(keys.layer.animation(forKey: KeyEffectOverlay.shakeKey))
    }

    // MARK: Sàn nhảy LED — flash phím cách

    /// Số tham chiếu — Android KeyEffectFx3Tests.beatFlashNumbersAndGate giữ y hệt.
    func testBeatFlashNumbersAndGate() {
        XCTAssertEqual(BeatFlash.rise, 0.02); XCTAssertEqual(BeatFlash.fall, 0.11)
        XCTAssertEqual(BeatFlash.duration, 0.13, accuracy: 1e-12)
        XCTAssertEqual(BeatFlash.peak, 0.6); XCTAssertEqual(BeatFlash.maxPerSecond, 3)
        XCTAssertEqual(BeatFlash.alpha(-0.001), 0)
        XCTAssertEqual(BeatFlash.alpha(0), 0)
        XCTAssertEqual(BeatFlash.alpha(0.01), 0.3, accuracy: 1e-9)
        XCTAssertEqual(BeatFlash.alpha(0.02), 0.6, accuracy: 1e-9)
        XCTAssertEqual(BeatFlash.alpha(0.075), 0.15, accuracy: 1e-9)
        XCTAssertEqual(BeatFlash.alpha(0.13), 0)
        for t in stride(from: 0.0, through: 0.2, by: 0.001) {
            XCTAssertLessThanOrEqual(BeatFlash.alpha(t), BeatFlash.peak + 1e-12)
            if t > 0.0205 { XCTAssertLessThanOrEqual(BeatFlash.alpha(t), BeatFlash.alpha(t - 0.001) + 1e-12, "tắt đơn điệu") }
        }
        XCTAssertEqual(BeatFlash.tint(0), 0xFFB6EF)
        XCTAssertEqual(BeatFlash.tint(1), 0xDCC6FF)
        XCTAssertEqual(BeatFlash.tint(2), 0xB6F6FF)
        XCTAssertEqual(BeatFlash.tint(3), BeatFlash.tint(0))

        // ≤ 3 lần trong MỌI khoảng 1 s: 10 nhịp trong 1 s ⇒ 3.
        let g = BeatFlash.Gate()
        XCTAssertEqual((0..<10).map { g.trigger(at: Double($0) * 0.1) }.filter { $0 }.count, 3)
        XCTAssertEqual(g.fired, 3)
        XCTAssertFalse(g.trigger(at: 0.99))
        XCTAssertTrue(g.trigger(at: 1.0), "đủ 1 s sau nhịp cũ nhất ⇒ lại được")
        let h = BeatFlash.Gate()
        XCTAssertEqual((0..<12).map { h.trigger(at: Double($0) * 0.34) }.filter { $0 }.count, 12, "~3 nhịp/s đều đặn: không bỏ")
        let w = BeatFlash.Gate()
        var times: [Double] = []
        for i in 0..<200 { let t = Double(i) * 0.047; if w.trigger(at: t) { times.append(t) } }
        for (i, t) in times.enumerated() where i >= 3 { XCTAssertGreaterThanOrEqual(t - times[i - 3], 1.0 - 1e-9) }
    }

    /// Bàn phím thật, kiểu Sàn nhảy LED: lớp flash ngay DƯỚI hàng phím, phủ đúng bàn phím; phím chữ không flash,
    /// phím cách flash; 10 phím cách trong 1 s ⇒ ≤ 3 flash; nháy cả bàn phím dùng chung cổng. Kiểu khác ⇒ không có lớp.
    @MainActor func testBeatFlashOnSpaceOnlyBehindKeys() throws {
        try withKeyboardFx(effect: "dancefloor") { kb in
            let f = try XCTUnwrap(kb.beatFlash)
            let o = try XCTUnwrap(kb.keyEffects)
            XCTAssertTrue(o.flashGate === f.gate)
            let rows = kb.debugRowsContainer
            let i = try XCTUnwrap(kb.subviews.firstIndex(of: f)), k = try XCTUnwrap(kb.subviews.firstIndex(of: rows))
            XCTAssertEqual(i, k - 1, "ngay sau (dưới) hàng phím")
            XCTAssertEqual(f.frame, kb.bounds, "phủ trọn bàn phím, cùng hệ toạ độ")
            XCTAssertEqual(f.bounds.origin, kb.bounds.origin)
            XCTAssertFalse(f.isUserInteractionEnabled)
            XCTAssertNil(f.hitTest(CGPoint(x: 10, y: 10), with: nil))
            XCTAssertEqual(f.layer.opacity, 0, "nghỉ: trong suốt")

            for s in ["t", "e", "t"] { kb.debugTapLetter(s, at: 0) }
            XCTAssertNil(f.layer.animation(forKey: BeatFlashView.animKey), "phím chữ: không flash")
            XCTAssertEqual(f.gate.fired, 0)

            kb.debugTapped(.space)
            XCTAssertNotNil(f.layer.animation(forKey: BeatFlashView.animKey), "phím cách: flash")
            XCTAssertEqual(f.gate.fired, 1)
            let c = try XCTUnwrap(f.layer.backgroundColor?.components)
            let t = BeatFlash.tint(0)
            XCTAssertEqual(c[0], CGFloat((t >> 16) & 0xFF) / 255, accuracy: 1e-3)
            XCTAssertEqual(c[1], CGFloat((t >> 8) & 0xFF) / 255, accuracy: 1e-3)
            XCTAssertEqual(c[2], CGFloat(t & 0xFF) / 255, accuracy: 1e-3)
            for _ in 0..<9 { kb.debugTapped(.space) }
            XCTAssertEqual(f.gate.fired, 3, "10 phím cách trong 1 s ⇒ ≤ 3 flash")

            // Giữa flash: presentation sáng lên, phím vẫn trên lớp flash.
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
            if let p = f.layer.presentation() { XCTAssertGreaterThan(p.opacity, 0.05) }
            XCTAssertEqual(kb.subviews.firstIndex(of: f), (kb.subviews.firstIndex(of: rows) ?? 0) - 1)
        }
        try withKeyboardFx(effect: "heart") { kb in XCTAssertNil(kb.beatFlash, "kiểu khác: 0 lớp") }
    }

    // MARK: Plasma / Laser / Glitch

    func testPlasmaChainAndArcParity() {
        var c = PlasmaChain()
        XCTAssertFalse(c.press((10, 10), at: 1.0))
        XCTAssertTrue(c.press((80, 20), at: 1.2)); XCTAssertEqual(c.prev.x, 10); XCTAssertEqual(c.prev.y, 10)
        XCTAssertFalse(c.press((81, 21), at: 1.3), "cùng phím")
        XCTAssertFalse(c.press((10, 10), at: 1.3 + PlasmaArc.chainWindow + 0.001), "nghỉ lâu")
        for v in 0..<PlasmaArc.variants {
            let pts = PlasmaArc.points(from: (0, 0), to: (100, 40), variant: v)
            XCTAssertEqual(pts.count, PlasmaArc.segments + 1)
            XCTAssertEqual(pts.last!.x, 100)
            for (i, q) in pts.enumerated() {
                let f = Double(i) / Double(PlasmaArc.segments)
                XCTAssertLessThanOrEqual(hypot(q.x - 100 * f, q.y - 40 * f), PlasmaArc.maxJitter + 1e-9)
            }
        }
        let p = PlasmaArc.points(from: (0, 0), to: (100, 0), variant: 3)
        XCTAssertEqual(p[1].y, 2.0967, accuracy: 1e-4)
        XCTAssertEqual(p[4].y, 3.5963, accuracy: 1e-4)
        XCTAssertEqual(PlasmaArc.alpha(0), 1); XCTAssertEqual(PlasmaArc.alpha(PlasmaArc.duration), 0)
    }

    func testLaserAndGlitchParity() {
        let space = CGRect(x: 100, y: 200, width: 200, height: 40)
        XCTAssertFalse(LaserBeam.fires(space: space, key: CGPoint(x: 150, y: 220)))
        XCTAssertTrue(LaserBeam.fires(space: space, key: CGPoint(x: 150, y: 120)))
        XCTAssertEqual(LaserBeam.reach(0), 0); XCTAssertEqual(LaserBeam.reach(LaserBeam.travel), 1)
        XCTAssertEqual(LaserBeam.alpha(0.01), 1); XCTAssertEqual(LaserBeam.alpha(LaserBeam.duration), 0)
        XCTAssertEqual(GlitchFx.step(0), 0); XCTAssertEqual(GlitchFx.step(0.119), 3); XCTAssertEqual(GlitchFx.step(0.12), 4)
        for v in 0..<GlitchFx.variants { for st in 0..<GlitchFx.steps {
            for s in GlitchFx.slices(step: st, variant: v) {
                XCTAssertGreaterThanOrEqual(s.y, 0); XCTAssertLessThanOrEqual(s.y + s.h, 1 + 1e-9)
                XCTAssertLessThanOrEqual(abs(s.dx), 1)
            }
        } }
        let g = GlitchFx.slices(step: 1, variant: 2).flatMap { [$0.y, $0.h, $0.dx] }
        let want = [0.8370, 0.1115, 0.9431, 0.2958, 0.2180, -0.2651, 0.5173, 0.1869, -0.4911]
        for (a, b) in zip(g, want) { XCTAssertEqual(a, b, accuracy: 1e-4) }
    }

    // MARK: Chữ bay / Hạt cát

    func testFlyingLetterGlyph() {
        XCTAssertEqual(FlyingLetters.glyph(before: "hoa", after: "hoá", typed: "s"), "á")
        XCTAssertEqual(FlyingLetters.glyph(before: "hoan", after: "hoán", typed: "s"), "á")
        XCTAssertEqual(FlyingLetters.glyph(before: "tuong", after: "tương", typed: "w"), "ơ")
        XCTAssertEqual(FlyingLetters.glyph(before: "", after: "a", typed: "a"), "a")
        XCTAssertEqual(FlyingLetters.glyph(before: "", after: "A", typed: "A"), "A")
        XCTAssertEqual(FlyingLetters.glyph(before: "d", after: "đ", typed: "d"), "đ")
        XCTAssertEqual(FlyingLetters.glyph(before: "á", after: "as", typed: "s"), "s")
        XCTAssertEqual(FlyingLetters.glyph(before: "abc", after: "", typed: "."), ".")
        XCTAssertEqual(FlyingLetters.glyph(before: "", after: "", typed: "😂"), "😂")
        XCTAssertNil(FlyingLetters.glyph(before: "", after: "", typed: " "))
        XCTAssertNil(FlyingLetters.glyph(before: "", after: "", typed: "ab"))
        XCTAssertNil(FlyingLetters.glyph(before: "abc", after: "abc", typed: "x"))
        XCTAssertNil(FlyingLetters.glyph(before: "", after: "", typed: nil))
        for s in 0..<50 {
            XCTAssertLessThanOrEqual(abs(FlyingLetters.drift(s)), 12); XCTAssertLessThanOrEqual(abs(FlyingLetters.spin(s)), 0.3)
        }
        XCTAssertEqual(FlyingLetters.drift(5), 5.2726, accuracy: 1e-4)
        XCTAssertEqual(FlyingLetters.spin(5), 0.2413, accuracy: 1e-4)
    }

    func testSandPileCapsSlopeAndSinks() {
        var p = SandPile(width: 390)
        XCTAssertEqual(p.columns, 130)
        XCTAssertTrue(p.isEmpty)
        for _ in 0..<2000 { p.deposit(195) }
        XCTAssertLessThanOrEqual(p.maxHeightNow, SandPile.maxHeight + 1e-9)
        XCTAssertGreaterThan(p.heights[p.column(195) - 5], 0); XCTAssertGreaterThan(p.heights[p.column(195) + 5], 0)
        for c in 1..<p.columns {
            XCTAssertLessThanOrEqual(abs(p.heights[c] - p.heights[c - 1]), SandPile.slope + SandPile.grain + 1e-9)
        }
        for i in 0..<5000 { p.deposit(Double(i * 37 % 390)) }
        XCTAssertLessThanOrEqual(p.maxHeightNow, SandPile.maxHeight + 1e-9, "trần — không che phím đáy")
        XCTAssertEqual(SandPile.sinkFactor(idle: 0), 1)
        XCTAssertEqual(SandPile.sinkFactor(idle: SandPile.idleAfter), 1)
        XCTAssertEqual(SandPile.sinkFactor(idle: SandPile.idleAfter + SandPile.sinkTime / 2), 0.5, accuracy: 1e-9)
        XCTAssertEqual(SandPile.sinkFactor(idle: SandPile.idleAfter + SandPile.sinkTime), 0)
        p.scale(0.5); XCTAssertLessThanOrEqual(p.maxHeightNow, SandPile.maxHeight / 2 + 1e-9)
        p.clear(); XCTAssertTrue(p.isEmpty)
        XCTAssertEqual(SandPile.fallTime(200), sqrt(2 * 200 / 1800.0), accuracy: 1e-12)
        XCTAssertEqual(p.column(-5), 0); XCTAssertEqual(p.column(1e6), 129)
        XCTAssertEqual(SandPile.spread(1, seed: 4), -4.2766, accuracy: 1e-4)
    }

    // MARK: overlay — trong khung bàn phím (#151), trần, không bắn khi chưa có sự kiện

    /// Host dời gốc bounds (khung cao tạm, #151): mọi layer của hiệu ứng đợt 3 nằm TRONG bàn phím (overlay cắt theo
    /// bounds + cùng hệ toạ độ), số layer có trần.
    @MainActor func testFx3OverlaysStayInsideKeyboardAndCapped() throws {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 470))
        host.bounds.origin.y = -180
        let keysView = UIView(frame: host.bounds)
        host.addSubview(keysView)
        for e in Self.fx3 {
            let o = try XCTUnwrap(KeyEffectOverlay.install(e, color: .systemPurple, keyFill: .white, in: host, keys: keysView,
                                                           existing: nil))
            XCTAssertEqual(o.frame, host.bounds, e.rawValue)
            XCTAssertEqual(o.bounds.origin, host.bounds.origin, e.rawValue)
            if e != .shake { XCTAssertTrue(o.clipsToBounds, "\(e.rawValue): cắt theo bàn phím") }
            // Phím sát mép trên (y = 0 nội dung) và sát góc: chùm không được tràn.
            let keys = [CGRect(x: 0, y: 0, width: 34, height: 42), CGRect(x: 356, y: 248, width: 34, height: 42),
                        CGRect(x: 180, y: 120, width: 34, height: 42)]
            for i in 0..<40 {
                switch e {
                case .tone: o.queueTone(ToneFx(rawValue: i % 8)!)
                case .keyword: o.queueKeyword(KeywordKind(rawValue: i % 4)!)
                case .letters: o.queueLetter("ế")
                default: break
                }
                o.emit(key: keys[i % keys.count]); o.flush()
            }
            let roots = o.debugFx3Roots
            switch e {
            case .shake: XCTAssertTrue(roots.isEmpty)
            case .plasma: XCTAssertEqual(roots.count, PlasmaArc.pool)
            case .laser: XCTAssertEqual(roots.count, LaserBeam.pool)
            case .glitch: XCTAssertEqual(roots.count, GlitchFx.pool)
            case .tone: XCTAssertEqual(roots.count, ToneFx.allCases.count * ToneBurst.pool)
            case .keyword: XCTAssertEqual(roots.count, KeywordKind.allCases.count * KeywordBursts.pool)
            case .letters: XCTAssertEqual(roots.count, FlyingLetters.pool)
            case .sand: XCTAssertEqual(roots.count, SandPile.flying + 1)
            default: break
            }
            // Điểm phát (vị trí model của gốc) trong bàn phím.
            for r in roots where !(r is CAShapeLayer && r === o.debugSandLayer) {
                let pt = o.layer.convert(r.position, from: r.superlayer)
                XCTAssertTrue(o.bounds.insetBy(dx: -1, dy: -1).contains(pt), "\(e.rawValue): \(pt) ngoài \(o.bounds)")
            }
            if e == .sand {
                let l = try XCTUnwrap(o.debugSandLayer)
                XCTAssertEqual(l.frame.maxY, o.bounds.maxY, accuracy: 0.5, "đống cát nằm sát đáy bàn phím")
                XCTAssertLessThanOrEqual(l.frame.height, CGFloat(SandPile.maxHeight) + 1)
            }
            o.halt()
            if e == .sand { XCTAssertTrue(o.debugSand?.isEmpty ?? true, "ẩn bàn phím ⇒ đống cát về 0") }
            _ = KeyEffectOverlay.install(.none, color: .red, in: host, existing: o)
        }
    }

    /// Hiệu ứng theo sự kiện: phím thường không hẹn gì; có sự kiện ⇒ bắn đúng một lần ở lượt kế.
    @MainActor func testQueuedFx3FireOnlyWithEvent() throws {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 260))
        for e in [KeyEffect.tone, .keyword, .letters] {
            let o = try XCTUnwrap(KeyEffectOverlay.install(e, color: .red, in: host, existing: nil))
            o.emit(key: CGRect(x: 50, y: 100, width: 34, height: 42))
            XCTAssertFalse(o.debugScheduled, "\(e.rawValue): không có sự kiện ⇒ không hẹn vẽ")
            o.queueTone(.hoi); o.queueKeyword(.tet); o.queueLetter("ữ")
            o.emit(key: CGRect(x: 50, y: 100, width: 34, height: 42))
            XCTAssertTrue(o.debugScheduled)
            o.flush()
            XCTAssertEqual(o.debugFx3Roots.count, 1, e.rawValue)
            if e == .letters { XCTAssertEqual(o.debugLetters.first?.string as? String, "ữ") }
            o.emit(key: CGRect(x: 50, y: 100, width: 34, height: 42))
            XCTAssertFalse(o.debugScheduled, "sự kiện đã dùng")
            _ = KeyEffectOverlay.install(.none, color: .red, in: host, existing: o)
        }
    }

    /// Hạt cát: hạt đáp ⇒ đống tăng (trần), path đống chỉ là MỘT layer; nghỉ ⇒ có animation lún; halt ⇒ sạch.
    @MainActor func testSandAccumulatesThenSinks() throws {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 260))
        let o = try XCTUnwrap(KeyEffectOverlay.install(.sand, color: .red, in: host, existing: nil))
        for i in 0..<300 { o.emit(key: CGRect(x: 180 + CGFloat(i % 5), y: 100, width: 34, height: 42)); o.flush(); o.debugLandSand() }
        let s = try XCTUnwrap(o.debugSand)
        XCTAssertFalse(s.isEmpty)
        XCTAssertLessThanOrEqual(s.maxHeightNow, SandPile.maxHeight + 1e-9)
        let l = try XCTUnwrap(o.debugSandLayer)
        XCTAssertNotNil(l.path)
        XCTAssertNotNil(l.animation(forKey: "sink"), "đặt sẵn animation lún sau khi nghỉ")
        o.halt()
        XCTAssertTrue(o.debugSand?.isEmpty ?? true)
        XCTAssertNil(l.path)
        XCTAssertNil(l.animation(forKey: "sink"))
    }

    /// Laser trên bàn phím thật: gốc tia là phím cách (khung phím cách theo toạ độ overlay).
    @MainActor func testLaserOriginIsSpaceBar() throws {
        try withKeyboardFx(effect: "laser") { kb in
            let o = try XCTUnwrap(kb.keyEffects)
            let s = try XCTUnwrap(o.laserOrigin?())
            XCTAssertTrue(kb.bounds.contains(CGPoint(x: s.midX, y: s.minY)))
            XCTAssertGreaterThan(s.width, 100, "phím cách rộng")
            XCTAssertGreaterThan(s.minY, kb.bounds.midY, "phím cách ở nửa dưới")
        }
        try withKeyboardFx(effect: "plasma") { kb in XCTAssertNil(kb.keyEffects?.laserOrigin) }
    }
}

// MARK: - Biển (theme Biển, 11/2026): sóng vỗ bờ + bọt bắn + bong bóng + cá. Số tham chiếu GIỐNG HỆT android KeyEffectSeaTests.
extension KeyEffectTests {
    func testSeaModelAndCaps() {
        let e = KeyEffect.sea
        XCTAssertEqual(KeyEffect.allCases.firstIndex(of: .sand)! + 1, KeyEffect.allCases.firstIndex(of: .sea)!, "thêm sau Hạt cát")
        XCTAssertTrue(e.isPlus); XCTAssertFalse(e.isParticle); XCTAssertFalse(e.isQueued)
        XCTAssertFalse(e.needsComposeDiff); XCTAssertFalse(e.needsBoundaryWord)
        XCTAssertEqual(e.band, .aboveKeys)
        XCTAssertTrue(KeyEffectOverlay.clipped.contains(e), "cắt theo bàn phím (#151)")
        XCTAssertEqual(e.title, L("Biển")); XCTAssertEqual(L10n.en["Biển"], "Sea")
        XCTAssertNil(KeyEffectShapes.path(e))
        // Trần: chùm bọt + bong bóng trong pool chung; sóng nối nhau không bao giờ cướp sóng đang chạy.
        XCTAssertEqual(SeaFx.layersPerTap, 5)
        XCTAssertEqual(e.burstSlots * e.layersPerBurst, 20)
        XCTAssertLessThanOrEqual(e.burstSlots * e.layersPerBurst, KeyEffectPool.cap)
        XCTAssertEqual(SeaFx.maxWaves, 3)
        XCTAssertGreaterThanOrEqual(Double(SeaFx.maxWaves) * SeaFx.launchGap, SeaFx.life, "đủ ô cho mọi sóng còn sống")
        XCTAssertEqual(SeaFx.life, 3.0, accuracy: 1e-12)
        XCTAssertEqual(SeaFx.launchGap, 1.0)
        XCTAssertFalse(SeaFx.shouldLaunch(sinceLast: 0.2), "gõ dồn: chỉ bọt + bong bóng")
        XCTAssertFalse(SeaFx.shouldLaunch(sinceLast: 0.99))
        XCTAssertTrue(SeaFx.shouldLaunch(sinceLast: 1.0))
        // iOS: keyframe đủ mịn cho đời sóng dài (≥ 20 khung / giây).
        XCTAssertGreaterThanOrEqual(Double(SeaFx.frames) / SeaFx.life, 20)
        XCTAssertEqual((0...5).map { SeaFx.size(level: $0) }, [1.0, 1.2, 1.4, 1.65, 1.65, 1.65])
        XCTAssertEqual(SeaFx.size(level: -1), 1.0)
    }

    /// Đường cong sóng: cuộn nhanh dần từ đỉnh tới bờ, vỡ (thân tan, bọt dâng) rồi rút để lại vệt ướt mờ dần, hết hẳn ở `life`.
    func testSeaWaveCurveBreakAndRecede() {
        XCTAssertEqual(SeaFx.travel(-1), 0); XCTAssertEqual(SeaFx.travel(0), 0)
        XCTAssertEqual(SeaFx.travel(0.23), 0.0944, accuracy: 1e-12)
        XCTAssertEqual(SeaFx.travel(0.575), 0.35, accuracy: 1e-12)
        XCTAssertEqual(SeaFx.travel(0.8625), 0.646875, accuracy: 1e-12)
        XCTAssertEqual(SeaFx.travel(1.15), 1); XCTAssertEqual(SeaFx.travel(5), 1)
        var last = -1.0
        for i in 0...115 { let v = SeaFx.travel(Double(i) * 0.01); XCTAssertGreaterThan(v, last); last = v }
        // Sóng lừng: khởi chậm nhưng không đứng (tốc độ 0,3 trung bình), cuối chỉ nhanh hơn chút (≤ 1,5; u² cũ = 2).
        let h = 1e-6, speed = { (t: Double) in (SeaFx.travel(t + h) - SeaFx.travel(t)) / h * SeaFx.roll }
        XCTAssertEqual(speed(0), 0.3, accuracy: 1e-3)
        XCTAssertEqual(speed(SeaFx.roll / 2), 1.05, accuracy: 1e-3)
        XCTAssertEqual(speed(SeaFx.roll - 2 * h), 1.5, accuracy: 1e-3)
        XCTAssertEqual(SeaFx.driftX(0.575), 8, accuracy: 1e-12); XCTAssertEqual(SeaFx.driftX(5), 16)
        XCTAssertEqual(SeaFx.crestOffset(0, phase: 0), 0.592875, accuracy: 1e-5)
        XCTAssertEqual(SeaFx.crestOffset(30, phase: 0.9), 1.300941, accuracy: 1e-5)
        XCTAssertEqual(SeaFx.crestOffset(77, phase: 1.8), 0.140812, accuracy: 1e-5)
        XCTAssertEqual(SeaFx.bodyTop(10, phase: 0.9), -26.198922, accuracy: 1e-5)
        XCTAssertEqual(SeaFx.washTop(20, phase: 0), -13.236323, accuracy: 1e-5)
        XCTAssertEqual(SeaFx.phase(1), 0.9, accuracy: 1e-12)
        for x in stride(from: -110.0, through: 500, by: 3) {
            XCTAssertLessThanOrEqual(abs(SeaFx.crestOffset(x, phase: 0.9)), SeaFx.crestAmp * 1.3 + 1e-9)
            XCTAssertLessThan(SeaFx.bodyTop(x, phase: 0.9), SeaFx.crestOffset(x, phase: 0.9), "thân sóng nằm sau mép")
        }
        // Vỡ — rút.
        XCTAssertEqual(SeaFx.waveAlpha(0.6), 1); XCTAssertEqual(SeaFx.waveAlpha(1.425), 0.5, accuracy: 1e-9)
        XCTAssertEqual(SeaFx.waveAlpha(1.7), 0); XCTAssertEqual(SeaFx.waveAlpha(-0.1), 0)
        XCTAssertEqual(SeaFx.washHeight(1.0, size: 1), 0, "chưa tới bờ: chưa có bọt tràn")
        XCTAssertEqual(SeaFx.washHeight(1.425, size: 1.4), 14.7, accuracy: 1e-9)
        XCTAssertEqual(SeaFx.washHeight(1.7, size: 1.65), 23.1, accuracy: 1e-9, "đỉnh bọt tràn = washMax × cỡ")
        XCTAssertEqual(SeaFx.washHeight(2.35, size: 1), 7, accuracy: 1e-9)
        XCTAssertEqual(SeaFx.washHeight(SeaFx.life, size: 1.65), 0)
        XCTAssertEqual(SeaFx.wetAlpha(1.65), 0, "vệt ướt chỉ hiện khi nước rút")
        XCTAssertEqual(SeaFx.wetAlpha(1.7), 0.3, accuracy: 1e-9)
        XCTAssertEqual(SeaFx.wetAlpha(2.35), 0.15, accuracy: 1e-9)
        XCTAssertEqual(SeaFx.wetAlpha(SeaFx.life), 0)
        // Hết đời sóng: không còn gì vẽ (nghỉ gõ = 0 việc).
        for t in [SeaFx.life, SeaFx.life + 0.5] {
            XCTAssertEqual(SeaFx.waveAlpha(t), 0); XCTAssertEqual(SeaFx.washHeight(t, size: 1.65), 0); XCTAssertEqual(SeaFx.wetAlpha(t), 0)
        }
        for i in 0...300 {
            XCTAssertLessThanOrEqual(SeaFx.washHeight(Double(i) * 0.01, size: 1.65), SeaFx.washMax * 1.65 + 1e-9)
        }
    }

    /// Tiếng sóng vỗ: chỉ khi Âm thanh phím bật (không bật ⇒ im), to hơn chút khi sóng to; mẫu tất định (checksum chung
    /// Android), mềm hơn mọi tiếng phím, dâng chậm rồi vỡ ĐÚNG lúc sóng chạm bờ (roll), đóng về 0.
    @MainActor func testSeaSurfSoundRespectsKeySoundAndLandsWithWave() {
        XCTAssertFalse(SeaFx.shouldSurf(customSound: false)); XCTAssertTrue(SeaFx.shouldSurf(customSound: true))
        XCTAssertEqual(SeaFx.surfVoices, 2)
        XCTAssertEqual(SeaFx.surfVolume(size: 1), 0.7, accuracy: 1e-12)
        XCTAssertEqual(SeaFx.surfVolume(size: 1.4), 0.884615, accuracy: 1e-5)
        XCTAssertEqual(SeaFx.surfVolume(size: 1.65), 1, accuracy: 1e-12)
        XCTAssertEqual(SeaFx.surfVolume(size: 9), 1); XCTAssertEqual(SeaFx.surfVolume(size: 0), 0.7)
        let saved = KeyboardView.customSoundEnabled
        defer { KeyboardView.customSoundEnabled = saved }
        let n0 = KeyboardView.debugSurfs
        KeyboardView.customSoundEnabled = false
        KeyboardView.seaSurf(size: 1.65)
        XCTAssertEqual(KeyboardView.debugSurfs, n0, "Âm thanh phím tắt ⇒ không có tiếng sóng")
        KeyboardView.customSoundEnabled = true
        KeyboardView.seaSurf(size: 1)
        XCTAssertEqual(KeyboardView.debugSurfs, n0 + 1)
        // Mẫu.
        XCTAssertEqual(KeySoundSynth.surfCrash, SeaFx.roll, "tiếng vỡ trùng lúc sóng chạm bờ")
        let x = KeySoundSynth.surfSamples()
        XCTAssertEqual(x, KeySoundSynth.surfSamples(), "tất định")
        let sr = KeySoundSynth.surfSampleRate
        XCTAssertEqual(x.count, Int((KeySoundSynth.surfDuration * sr).rounded()))
        XCTAssertEqual(x.count, 35_280)
        let sum = x.reduce(0.0) { $0 + Double(abs($1)) }
        print("SEA-SURF-GOLDEN sum=\(String(format: "%.4f", sum))")
        XCTAssertEqual(sum, Self.goldenSurf, accuracy: 0.01)
        let peak = Double(x.map(abs).max() ?? 1)
        XCTAssertEqual(peak, KeySoundSynth.surfPeak, accuracy: 1e-6)
        let softestKey = KeySoundStyle.presets.map { Double(KeySoundSynth.samples($0, .letter).map(abs).max() ?? 0) }.min() ?? 0
        XCTAssertLessThan(peak, softestKey, "nhỏ hơn mọi tiếng phím")
        XCTAssertLessThan(KeySoundSynth.rms(x), 0.05)
        XCTAssertEqual(x.first ?? 1, 0, accuracy: 1e-6); XCTAssertEqual(x.last ?? 1, 0, accuracy: 1e-6)
        let crash = Int(KeySoundSynth.surfCrash * sr)
        XCTAssertLessThan(KeySoundSynth.spectralCentroid(Array(x[crash..<(crash + 4096)]), sampleRate: sr), 2500, "ào, không chói")
        // Vỏ âm: khung 50 ms to nhất nằm ngay sau lúc vỡ; nửa giây đầu chỉ rì rầm nhỏ (dâng chậm).
        let w = Int(0.05 * sr)
        let rmsW = stride(from: 0, to: x.count - w, by: w).map { KeySoundSynth.rms(Array(x[$0..<($0 + w)])) }
        let loud = rmsW.indices.max { rmsW[$0] < rmsW[$1] }!
        XCTAssertGreaterThanOrEqual(Double(loud * w) / sr, KeySoundSynth.surfCrash - 0.05)
        XCTAssertLessThanOrEqual(Double(loud * w) / sr, KeySoundSynth.surfCrash + 0.15)
        XCTAssertLessThan(KeySoundSynth.rms(Array(x[0..<Int(0.5 * sr)])), 0.15 * rmsW[loud])
        // KeySound: bỏ chọn Biển ⇒ không giữ buffer tiếng sóng.
        KeySound.shared.setSurfEnabled(false)
        KeySound.shared.debugDrain()
        XCTAssertFalse(KeySound.shared.hasSurf)
    }
    static let goldenSurf = 854.8853

    func testSeaSplashBubblesAndFishRule() {
        let d = SeaFx.droplet(1, 0.5)
        XCTAssertEqual(d.x, 1.5, accuracy: 1e-12); XCTAssertEqual(d.y, -19, accuracy: 1e-12)
        XCTAssertEqual(SeaFx.droplet(0, 0).x, 0); XCTAssertEqual(SeaFx.droplet(0, 0).y, 0)
        XCTAssertEqual(SeaFx.droplet(2, 1).y, SeaFx.dropletSink, accuracy: 1e-12, "giọt rơi xuống dưới phím")
        let b = SeaFx.bubble(1, 0.5)
        XCTAssertEqual(b.x, 9.5, accuracy: 1e-9); XCTAssertEqual(b.y, -42, accuracy: 1e-9)
        XCTAssertEqual(b.scale, 0.835294, accuracy: 1e-5); XCTAssertEqual(b.alpha, 1)
        let p = SeaFx.bubble(0, 0.9)
        XCTAssertEqual(p.x, -2.168441, accuracy: 1e-5); XCTAssertEqual(p.y, -43.56, accuracy: 1e-9)
        XCTAssertEqual(p.scale, 1.266667, accuracy: 1e-5); XCTAssertEqual(p.alpha, 0.666667, accuracy: 1e-5)
        XCTAssertEqual(SeaFx.bubble(0, 1).scale, SeaFx.popScale, accuracy: 1e-9, "vỡ thành vòng")
        XCTAssertEqual(SeaFx.bubble(0, 1).alpha, 0, accuracy: 1e-9)
        // Cá: chỉ khi mức combo VỪA lên fishLevel, nghỉ ≥ fishCooldown.
        XCTAssertTrue(SeaFx.fishShouldSwim(level: 2, previous: 1, sinceLastFish: 100))
        XCTAssertTrue(SeaFx.fishShouldSwim(level: 3, previous: 0, sinceLastFish: 4))
        XCTAssertFalse(SeaFx.fishShouldSwim(level: 1, previous: 0, sinceLastFish: 100), "chưa đủ combo")
        XCTAssertFalse(SeaFx.fishShouldSwim(level: 3, previous: 2, sinceLastFish: 100), "đang combo: không bơi lại")
        XCTAssertFalse(SeaFx.fishShouldSwim(level: 2, previous: 1, sinceLastFish: 3.9), "trong thời gian nghỉ cá")
        XCTAssertEqual(SeaFx.fishY(3, height: 260), 125.752758, accuracy: 1e-5)
        XCTAssertEqual(SeaFx.fishY(0, height: 260), 134.036973, accuracy: 1e-5)
        XCTAssertTrue(SeaFx.fishRightToLeft(0)); XCTAssertFalse(SeaFx.fishRightToLeft(1))
        XCTAssertEqual(SeaFx.fishX(0, width: 390, rightToLeft: true), 376)
        XCTAssertEqual(SeaFx.fishX(1, width: 390, rightToLeft: true), 14)
        XCTAssertEqual(SeaFx.fishX(0.5, width: 390, rightToLeft: false), 195)
        XCTAssertEqual(SeaFx.fishAlpha(0.05), 0.5, accuracy: 1e-9); XCTAssertEqual(SeaFx.fishAlpha(0.5), 1); XCTAssertEqual(SeaFx.fishAlpha(1), 0)
        for s in 0..<40 {
            let y = SeaFx.fishY(s, height: 260)
            XCTAssertGreaterThanOrEqual(y - SeaFx.fishBob - SeaFx.fishSize / 2, 0)
            XCTAssertLessThanOrEqual(y + SeaFx.fishBob + SeaFx.fishSize / 2, 260)
        }
    }

    /// Bàn phím cao tạm (gốc bounds dời, #151): sóng (đỉnh → bờ = đáy bàn phím), bọt, cá đều nằm trong bàn phím; gõ dồn
    /// chỉ một sóng; gõ nhịp đều ⇒ sóng nối nhau, tối đa maxWaves gốc; combo ⇒ sóng to hơn + cá bơi một lần.
    @MainActor func testSeaOverlayInsideShiftedKeyboardAndCapped() throws {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 470))
        host.bounds.origin.y = -180
        let keysView = UIView(frame: host.bounds)
        host.addSubview(keysView)
        let o = try XCTUnwrap(KeyEffectOverlay.install(.sea, color: .systemTeal, keyFill: .white, in: host, keys: keysView, existing: nil))
        XCTAssertEqual(o.frame, host.bounds); XCTAssertEqual(o.bounds.origin, host.bounds.origin)
        XCTAssertTrue(o.clipsToBounds)
        XCTAssertTrue(o.debugSeaWaveRoots.isEmpty, "chưa gõ: không dựng gì")
        let keys = [CGRect(x: 0, y: -180, width: 34, height: 42), CGRect(x: 356, y: 248, width: 34, height: 42),
                    CGRect(x: 180, y: 120, width: 34, height: 42)]
        var surfSizes: [Double] = []
        o.onSeaWave = { surfSizes.append($0) }
        for i in 0..<30 { o.emit(key: keys[i % keys.count]); o.flush() }
        XCTAssertEqual(o.debugSeaWaveRoots.count, 1, "gõ dồn trong cùng lúc: một con sóng")
        XCTAssertEqual(o.debugSeaWaveSizes.first ?? 0, 1, "sóng đầu: cỡ thường")
        XCTAssertEqual(surfSizes, [1], "tiếng sóng: MỘT lần cho cả tràng phím (mỗi sóng, không mỗi phím)")
        XCTAssertNotNil(o.debugSeaFish, "tràng phím nhanh ⇒ cá bơi")
        XCTAssertNotNil(o.debugSeaFish?.animation(forKey: "fx"))
        // Gõ nhịp đều qua nhiều chu kỳ sóng (combo vẫn giữ: nghỉ < 1 s — chùm phím giữa chu kỳ, không bắn sóng).
        for _ in 0..<5 {
            KeyboardBenchTests.spin((SeaFx.launchGap + 0.02) / 2)
            for _ in 0..<7 { o.emit(key: keys[2]); o.flush() }
            KeyboardBenchTests.spin((SeaFx.launchGap + 0.02) / 2)
            o.emit(key: keys[2]); o.flush()
        }
        XCTAssertEqual(surfSizes.count, 6, "mỗi con sóng mới đúng một tiếng sóng")
        XCTAssertEqual(surfSizes.last ?? 0, 1.65, "gõ nhanh ⇒ sóng to ⇒ tiếng to hơn")
        XCTAssertEqual(o.debugSeaWaveRoots.count, SeaFx.maxWaves, "pool sóng có trần")
        XCTAssertGreaterThan(o.debugSeaWaveSizes.max() ?? 0, 1, "gõ nhanh ⇒ sóng to hơn")
        for r in o.debugSeaWaveRoots {
            XCTAssertEqual(r.position, o.bounds.origin, "sóng xuất phát ở đỉnh bàn phím (không phải đỉnh phần dư)")
            for sub in r.sublayers ?? [] {
                let p = o.layer.convert(sub.position, from: r)
                XCTAssertTrue(o.bounds.insetBy(dx: -1, dy: -1).contains(p), "\(p) ngoài \(o.bounds)")
            }
            let shore = try XCTUnwrap(r.sublayers?.last)
            XCTAssertEqual(o.layer.convert(shore.position, from: r).y, o.bounds.maxY, accuracy: 0.5, "bờ = đáy bàn phím")
        }
        for b in o.debugBursts { XCTAssertTrue(o.bounds.insetBy(dx: -1, dy: -1).contains(b.position)) }
        XCTAssertLessThanOrEqual(o.debugParticleCount, KeyEffectPool.cap)
        let fish = try XCTUnwrap(o.debugSeaFish)
        XCTAssertTrue(o.bounds.contains(fish.position), "cá trong bàn phím")
        o.halt()
        for r in o.debugSeaWaveRoots { XCTAssertTrue(r.isHidden, "ẩn bàn phím ⇒ không còn sóng") }
        XCTAssertNil(fish.animation(forKey: "fx"))
        _ = KeyEffectOverlay.install(.none, color: .red, in: host, existing: o)
    }

    /// Phủ chung mọi kiểu (#151): host dời gốc bounds ⇒ overlay luôn cùng hệ toạ độ, gõ ở mép trên / góc dưới không
    /// làm điểm phát chùm nào ra ngoài bàn phím; host về gốc 0 vẫn theo.
    @MainActor func testEveryEffectSharesShiftedOrigin() throws {
        for e in KeyEffect.allCases where e != .none {
            let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 470))
            host.bounds.origin.y = -180
            let keysView = UIView(frame: host.bounds)
            host.addSubview(keysView)
            let o = try XCTUnwrap(KeyEffectOverlay.install(e, color: .systemTeal, keyFill: .white, in: host, keys: keysView,
                                                           existing: nil))
            XCTAssertEqual(o.frame, host.bounds, e.rawValue)
            XCTAssertEqual(o.bounds.origin, host.bounds.origin, e.rawValue)
            for k in [CGRect(x: 0, y: -180, width: 34, height: 42), CGRect(x: 356, y: 248, width: 34, height: 42)] {
                if e == .emojiword { o.queueEmoji("😂") }
                if e == .letters { o.queueLetter("ơ") }
                if e == .tone { o.queueTone(.hoi) }
                if e == .keyword { o.queueKeyword(.love) }
                o.emit(key: k); o.flush()
            }
            for b in o.debugBursts {
                XCTAssertTrue(o.bounds.insetBy(dx: -1, dy: -1).contains(b.position), "\(e.rawValue): \(b.position) ngoài \(o.bounds)")
            }
            host.frame = CGRect(x: 0, y: 0, width: 390, height: 290)
            host.bounds.origin.y = 0
            KeyEffectOverlay.match(o, to: host)
            XCTAssertEqual(o.frame, host.bounds, e.rawValue)
            XCTAssertEqual(o.bounds.origin, .zero, e.rawValue)
            o.halt()
            _ = KeyEffectOverlay.install(.none, color: .red, in: host, existing: o)
        }
    }
}

// MARK: - Hiệu ứng phải nằm TRÊN bàn phím ở mọi host (tester 08/11/2026, 1.2.32)
// "Chỉ còn thấy trên Zalo" — mà trên Zalo cũng hiện gần tai thỏ. Host đo controller ở khung cả màn hình
// TRƯỚC viewWillAppear ⇒ #151 dời gốc bounds KeyboardView lên vài trăm pt đúng lúc cấu hình ⇒ overlay 1.2.32
// gắn với frame.y âm (autoresizing chỉ co chiều cao) rồi kẹt ở đó: app thường vẽ hẳn ra ngoài phần bàn phím
// đang hiện (không thấy), host dư ít hơn vẽ lên đỉnh màn hình. Sửa ở 206454e7 (overlay theo gốc bounds mỗi
// lượt layout); test này chốt cả đường controller thật: bắn ĐÚNG phím ở mọi hình dạng host.
@MainActor
final class KeyEffectHostTests: XCTestCase {
    private let suite = "vt-keyeffect-host-tests"

    final class Host: UIViewController {
        override var shouldAutomaticallyForwardAppearanceMethods: Bool { false }
    }

    /// Vị trí (toạ độ KeyboardView) của mọi chùm hạt / cú đánh đã bắn.
    private func firedPoints(_ kb: KeyboardView) -> [CGPoint] {
        guard let o = kb.keyEffects else { return [] }
        let roots = o.debugBursts.filter { !$0.isHidden } + o.debugStrikeRoots.filter { !$0.isHidden }
        return roots.map { kb.layer.convert($0.position, from: o.layer) }
    }

    func testEffectsLandOnTappedKeyInEveryHostShape() throws {
        for effect in [KeyEffect.petal, .lightning, .meteor] {
            let saved = UserDefaultsProvider.shared
            let savedPaywall = PlusGate.paywallEnabled
            defer {
                UserDefaultsProvider.shared = saved
                PlusGate.paywallEnabled = savedPaywall
                UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            }
            let d = UserDefaults(suiteName: suite)!
            d.removePersistentDomain(forName: suite)
            d.set(true, forKey: "showSuggestions")
            d.set(effect.rawValue, forKey: KeyEffect.key)
            PlusGate.paywallEnabled = false
            UserDefaultsProvider.shared = d

            let w: CGFloat = 402, H: CGFloat = 874
            let win = UIWindow(frame: CGRect(x: 0, y: 0, width: w, height: H))
            let host = Host()
            win.rootViewController = host
            win.isHidden = false
            let vc = KeyboardViewController()
            vc.debugProxy = KeyboardBenchTests.BenchProxy()
            vc.debugFullAccess = false
            vc.loadViewIfNeeded()
            host.addChild(vc); host.view.addSubview(vc.view); vc.didMove(toParent: host)
            func prime() {
                vc.debugKeyboard.debugScreenSize = CGSize(width: w, height: H)
                vc.debugKeyboard.debugSetSafeBottom(0)
            }
            prime()
            defer {
                vc.beginAppearanceTransition(false, animated: false); vc.endAppearanceTransition()
                vc.willMove(toParent: nil); vc.view.removeFromSuperview(); vc.removeFromParent()
                win.isHidden = true
            }
            func pass() {
                vc.view.setNeedsLayout(); vc.view.layoutIfNeeded()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
                vc.view.layoutIfNeeded()
            }
            var t: TimeInterval = 1
            func tapAndCheck(_ why: String) throws {
                let kb = vc.debugKeyboard
                let o = try XCTUnwrap(kb.keyEffects, "\(effect) phải bật: \(why)")
                XCTAssertTrue(o.superview === kb && o.window != nil && !o.isHidden && o.alpha > 0, "\(effect): \(why)")
                XCTAssertEqual(o.frame, kb.bounds, "\(effect) overlay phủ đúng phần đang hiện: \(why)")
                XCTAssertEqual(o.bounds.origin, kb.bounds.origin, "\(effect) cùng gốc toạ độ: \(why)")
                let f = try XCTUnwrap(kb.debugLetterFrame("g"))
                XCTAssertTrue(kb.bounds.contains(f), "phím nằm trong bàn phím: \(why)")
                t += 1
                kb.benchTap(at: CGPoint(x: f.midX, y: f.midY), time: t)
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
                let pts = firedPoints(kb)
                XCTAssertTrue(pts.contains { abs($0.x - f.midX) < 1 && abs($0.y - f.midY) < 1 },
                              "\(effect) phải bắn ĐÚNG phím g \(f) (thấy \(pts)): \(why)")
                for p in pts {
                    XCTAssertTrue(kb.bounds.insetBy(dx: -1, dy: -1).contains(p),
                                  "\(effect) \(p) ngoài bàn phím \(kb.bounds): \(why)")
                }
            }

            // Host đo controller ở khung cả màn hình TRƯỚC viewWillAppear (WhatsApp / Zalo).
            vc.view.frame = CGRect(x: 0, y: 0, width: w, height: H)
            pass()
            vc.beginAppearanceTransition(true, animated: false)
            let req = vc.debugKeyboard.debugRequestedHeight
            vc.endAppearanceTransition()
            vc.view.frame = CGRect(x: 0, y: H - req, width: w, height: req); pass()
            XCTAssertEqual(vc.debugKeyboard.oversizeShift, 0)
            try tapAndCheck("đo trước ở cả màn hình rồi về vừa đủ")
            // Host bình thường (dư ~25pt) — gốc bounds vẫn 0.
            vc.view.frame = CGRect(x: 0, y: H - req - 25, width: w, height: req + 25); pass()
            try tapAndCheck("dư bình thường")
            // Cao tạm (gốc bounds dời) rồi trở lại.
            let tall = req + 195
            vc.view.frame = CGRect(x: 0, y: H - tall, width: w, height: tall); pass()
            XCTAssertGreaterThan(vc.debugKeyboard.oversizeShift, 0)
            try tapAndCheck("khung cao tạm")
            vc.view.frame = CGRect(x: 0, y: H - req, width: w, height: req); pass()
            try tapAndCheck("cao tạm rồi về vừa đủ")
            // Dựng lại hàng phím (plane số rồi về chữ).
            vc.debugKeyboard.debugCycleThroughNumbers(); pass()
            try tapAndCheck("sau rebuild")
            // Ẩn rồi hiện lại (cây view xé + KeyboardView mới), host lại đo cả màn hình trước.
            vc.beginAppearanceTransition(false, animated: false); vc.endAppearanceTransition()
            vc.view.frame = CGRect(x: 0, y: 0, width: w, height: H)
            vc.beginAppearanceTransition(true, animated: false)
            prime()
            vc.endAppearanceTransition()
            pass()
            vc.view.frame = CGRect(x: 0, y: H - req, width: w, height: req); pass()
            try tapAndCheck("hiện lại sau khi xé")
        }
    }
}
