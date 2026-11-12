// "Âm thanh nét vuốt" (12/11/2026): model + id chung Android, sao lưu, cổng Plus (hết Plus / nguồn điện thấp ⇒ Bút chì,
// giá trị giữ), chính sách bật (Full Access, gõ vuốt, âm lượng 0), đường cong tốc độ → âm lượng, vỏ âm lượng (tắt dần
// 100 ms), mẫu lặp tất định + checksum, chỗ nối vòng liền mạch, bản nghe thử, vòng đời engine (Tắt = không dựng gì), và chi
// phí main mỗi điểm vuốt. Số tham chiếu GIỐNG HỆT Android SwipeSoundTests.kt.
import XCTest

final class SwipeSoundTests: XCTestCase {
    private var savedDefaults: UserDefaults!
    private var savedPaywall = true
    private let plusSuite = "vt-swipesound-plus"

    override func setUp() {
        super.setUp()
        savedDefaults = PlusGate.defaults
        savedPaywall = PlusGate.paywallEnabled
        UserDefaults(suiteName: plusSuite)!.removePersistentDomain(forName: plusSuite)
        PlusGate.defaults = UserDefaults(suiteName: plusSuite)!
    }

    override func tearDown() {
        PlusGate.defaults = savedDefaults
        PlusGate.paywallEnabled = savedPaywall
        super.tearDown()
    }

    private func setPlus(_ on: Bool) {
        PlusGate.paywallEnabled = true
        PlusGate.defaults.set(false, forKey: PlusConfig.debugOverrideKey)
        PlusGate.defaults.set(on, forKey: PlusConfig.unlockedKey)
    }

    // MARK: model / id / sao lưu

    func testIdsTitlesAndDefaults() {
        XCTAssertEqual(SwipeSoundStyle.allCases.map(\.rawValue), ["none", "pencil", "brush", "chalk", "marker"])
        XCTAssertEqual(SwipeSoundStyle.key, "swipeSound")
        XCTAssertEqual(SwipeSoundStyle.defaultValue, .none)
        XCTAssertEqual(SwipeSoundStyle.parse(nil), .none)
        XCTAssertEqual(SwipeSoundStyle.parse("loud"), .none)
        XCTAssertEqual(SwipeSoundStyle.parse(7), .none)
        XCTAssertEqual(SwipeSoundStyle.parse("chalk"), .chalk)
        XCTAssertEqual(SwipeSoundStyle.allCases.map(\.isPlus), [false, false, true, true, true])
        for s in SwipeSoundStyle.allCases { XCTAssertNotNil(L10n.en[s.title], "thiếu bản dịch: \(s.title)") }
        XCTAssertNotNil(L10n.en["Âm thanh nét vuốt"])
        let spec = BackupSettings.all.first { $0.key == SwipeSoundStyle.key }
        XCTAssertEqual(spec?.kind, .string("none", ["none", "pencil", "brush", "chalk", "marker"]))
    }

    func testPlusGateAndPolicy() {
        XCTAssertEqual(SwipeSoundStyle.displayed("marker", plus: false), .pencil)
        XCTAssertEqual(SwipeSoundStyle.displayed("marker", plus: true), .marker)
        XCTAssertEqual(SwipeSoundStyle.displayed("none", plus: false), .none)
        typealias P = SwipeSoundPolicy
        XCTAssertEqual(P.active(setting: .none, plus: true, lowPower: false, volumePercent: 50), .none)
        XCTAssertEqual(P.active(setting: .pencil, plus: true, lowPower: false, volumePercent: 0), .none, "âm lượng 0 ⇒ không dựng gì")
        XCTAssertEqual(P.active(setting: .pencil, plus: false, lowPower: true, volumePercent: 50), .pencil)
        XCTAssertEqual(P.active(setting: .brush, plus: false, lowPower: false, volumePercent: 50), .pencil)
        XCTAssertEqual(P.active(setting: .chalk, plus: true, lowPower: true, volumePercent: 50), .pencil)
        XCTAssertEqual(P.active(setting: .marker, plus: true, lowPower: false, volumePercent: 1), .marker)
        // Controller: thiếu Full Access / gõ vuốt tắt ⇒ Tắt.
        typealias K = KeyboardViewController
        XCTAssertEqual(K.swipeSoundStyle(setting: .pencil, swipeOn: true, fullAccess: false, plus: true, lowPower: false, volumePercent: 50), .none)
        XCTAssertEqual(K.swipeSoundStyle(setting: .pencil, swipeOn: false, fullAccess: true, plus: true, lowPower: false, volumePercent: 50), .none)
        XCTAssertEqual(K.swipeSoundStyle(setting: .chalk, swipeOn: true, fullAccess: true, plus: true, lowPower: false, volumePercent: 50), .chalk)
        // Cổng = cổng Hiệu ứng nét vuốt.
        setPlus(false)
        XCTAssertFalse(SwipeSoundGate.allows)
        XCTAssertTrue(SwipeSoundGate.allows(.pencil)); XCTAssertFalse(SwipeSoundGate.allows(.chalk))
        setPlus(true)
        XCTAssertEqual(SwipeSoundGate.allows, SwipeTrailGate.allows); XCTAssertTrue(SwipeSoundGate.allows(.chalk))
    }

    // MARK: tốc độ → âm lượng, vỏ âm lượng

    func testSpeedToVolume() {
        typealias F = SwipeSoundFx
        XCTAssertEqual(F.speedGain(0), 0)
        XCTAssertEqual(F.speedGain(F.speedMin), 0, "đứng yên / rê chậm ⇒ im")
        XCTAssertEqual(F.speedGain(F.speedMin + 0.25 * (F.speedFull - F.speedMin)), 0.5, accuracy: 1e-12)
        XCTAssertEqual(F.speedGain(F.speedFull), 1, accuracy: 1e-12)
        XCTAssertEqual(F.speedGain(9000), 1, "trần 1")
        XCTAssertEqual(F.speedGain(525), 0.576361, accuracy: 1e-6)   // số tham chiếu chung Android
        var last = -1.0
        for v in stride(from: 0, through: 2000, by: 50) { let g = F.speedGain(Double(v)); XCTAssertGreaterThanOrEqual(g, last); last = g }
        XCTAssertEqual(F.target(0.7, sinceMove: 0.05), 0.7)
        XCTAssertEqual(F.target(0.7, sinceMove: F.hold + 0.001), 0, "ngón dừng quá hold ⇒ im")
        XCTAssertEqual(F.smooth(0, 1, dt: F.speedTau), 0.632121, accuracy: 1e-6)
        XCTAssertEqual(F.smooth(0, 1, dt: F.maxDt), F.smooth(0, 1, dt: 5), "dt kẹp maxDt")
    }

    func testMeterFollowsFingerSpeed() {
        var m = SwipeSoundMeter()
        m.reset(x: 0, y: 0, t: 0)
        var t = 0.0, x = 0.0
        for _ in 0..<60 { t += 1.0 / 120; x += 5; m.move(x: x, y: 0, t: t) }
        XCTAssertEqual(m.speed, 600, accuracy: 1)
        XCTAssertEqual(m.gain, SwipeSoundFx.speedGain(m.speed))
        let before = m.speed
        m.move(x: x + 50, y: 0, t: t)                 // điểm gộp trùng giờ: bỏ qua
        XCTAssertEqual(m.speed, before)
        m.move(x: x + 10, y: 0, t: t + 1.0 / 60)
        XCTAssertEqual(m.speed, before, accuracy: 1)  // 10 pt / (1/60 s) = 600 pt/s
        m.reset(x: 0, y: 0, t: 1)
        XCTAssertEqual(m.speed, 0)
    }

    func testEnvelopeRampsAndFadesOutIn100ms() {
        let sr = KeySoundSynth.swipeSampleRate
        var e = SwipeSoundEnvelope(step: 1 / sr)
        for _ in 0..<Int(0.2 * sr) { e.next(0.8) }
        XCTAssertEqual(e.gain, 0.8, accuracy: 2e-3, "tiến về đích")
        e.release()
        var n = 0
        while !e.finished { e.next(1); n += 1; if n > Int(sr) { XCTFail("không tắt"); break } }
        XCTAssertEqual(Double(n), SwipeSoundFx.fadeOut * sr, accuracy: 2, "tắt dần ~fadeOut")
        XCTAssertEqual(e.gain, 0)
        e.begin(); e.next(1); XCTAssertGreaterThan(e.gain, 0); XCTAssertLessThan(e.gain, 0.01)
        var a = SwipeSoundEnvelope(step: SwipeSoundFx.tick)
        for _ in 0..<20 { a.next(0.5) }
        a.release()
        var k = 0
        while !a.finished { a.next(0.5); k += 1 }
        XCTAssertEqual(k, 4, "fadeOut / tick (Android)")
        var b = SwipeSoundEnvelope(step: 1 / sr)
        for _ in 0..<Int(0.2 * sr) { b.next(1) }
        for _ in 0..<Int(SwipeSoundFx.rampTau * sr) { b.next(0) }
        XCTAssertEqual(b.gain, 0.367879, accuracy: 2e-3)
    }

    // MARK: mẫu lặp

    static let golden: [SwipeSoundStyle: Double] = [.pencil: 1060.9227, .brush: 1786.0301, .chalk: 932.4742, .marker: 1379.6404]
    static let previewGolden: [SwipeSoundStyle: Double] = [.pencil: 593.6883, .brush: 842.1863, .chalk: 364.0651, .marker: 786.1841]

    func testLoopsAreDeterministicSoftAndSeamless() {
        let sr = KeySoundSynth.swipeSampleRate
        XCTAssertTrue(KeySoundSynth.swipeLoopSamples(.none).isEmpty)
        XCTAssertTrue(KeySoundSynth.swipePreviewSamples(.none).isEmpty)
        for s in SwipeSoundStyle.allCases where s != .none {
            let x = KeySoundSynth.swipeLoopSamples(s)
            XCTAssertEqual(x, KeySoundSynth.swipeLoopSamples(s), "tất định \(s)")
            XCTAssertEqual(x.count, Int((KeySoundSynth.swipeLoopSeconds(s) * sr).rounded()))
            XCTAssertTrue((Int(0.8 * sr)...Int(1.5 * sr)).contains(x.count))
            let peak = Double(x.map(abs).max() ?? 0)
            XCTAssertEqual(peak, KeySoundSynth.swipePeak(s), accuracy: 1e-6)
            XCTAssertLessThanOrEqual(peak, 0.34 + 1e-6, "nhỏ: \(s)")
            let r = KeySoundSynth.rms(x)
            XCTAssertTrue((0.02...0.12).contains(r), "êm, không câm: \(s) rms=\(r)")
            var maxStep = 0.0
            for i in 1..<x.count { maxStep = max(maxStep, Double(abs(x[i] - x[i - 1]))) }
            let seam = Double(abs(x[0] - x[x.count - 1]))
            XCTAssertLessThanOrEqual(seam, maxStep * 0.9, "nối vòng \(s): \(seam) vs \(maxStep)")
            let w = Int(0.02 * sr)
            let head = KeySoundSynth.rms(Array(x[0..<w])), tail = KeySoundSynth.rms(Array(x[(x.count - w)...]))
            XCTAssertTrue((0.4...2.5).contains(head / tail), "vỏ quanh chỗ nối \(s): \(head) / \(tail)")
            let sum = x.reduce(0.0) { $0 + Double(abs($1)) }
            print("SWIPE-SOUND-GOLDEN \(s.rawValue)=\(String(format: "%.4f", sum))")
            XCTAssertEqual(sum, Self.golden[s]!, accuracy: 0.01, "checksum chung Android: \(s)")
        }
        func centroid(_ s: SwipeSoundStyle) -> Double {
            KeySoundSynth.spectralCentroid(Array(KeySoundSynth.swipeLoopSamples(s)[4000..<6048]), sampleRate: sr)
        }
        XCTAssertLessThan(centroid(.brush), 2600, "chổi lông trầm-trung")
        XCTAssertGreaterThan(centroid(.pencil), centroid(.marker))
        XCTAssertGreaterThan(centroid(.pencil), centroid(.brush))
        XCTAssertGreaterThan(centroid(.chalk), centroid(.brush))
    }

    func testPreviewFollowsDemoSwipeAndFadesOut() {
        let sr = KeySoundSynth.swipeSampleRate
        XCTAssertEqual(KeySoundSynth.swipeDemoSpeed(0), 0)
        XCTAssertEqual(KeySoundSynth.swipeDemoSpeed(KeySoundSynth.swipePreviewLift), 0)
        XCTAssertEqual(KeySoundSynth.swipeDemoSpeed(KeySoundSynth.swipePreviewLift / 2), 675, accuracy: 1e-9)   // giữa nét: chậm ở phím
        for s in SwipeSoundStyle.allCases where s != .none {
            let p = KeySoundSynth.swipePreviewSamples(s)
            XCTAssertEqual(p.count, Int(KeySoundSynth.swipePreview * sr))
            XCTAssertEqual(p, KeySoundSynth.swipePreviewSamples(s))
            let lift = Int(KeySoundSynth.swipePreviewLift * sr)
            let fadeEnd = lift + Int(SwipeSoundFx.fadeOut * sr) + 2
            XCTAssertTrue(p[fadeEnd...].allSatisfy { $0 == 0 }, "im sau khi tắt dần (\(s))")
            XCTAssertLessThan(abs(p[0]), 1e-3, "mở từ 0")
            XCTAssertLessThanOrEqual(Double(p.map(abs).max() ?? 0), KeySoundSynth.swipePeak(s) + 1e-6)
            let sum = p.reduce(0.0) { $0 + Double(abs($1)) }
            print("SWIPE-PREVIEW-GOLDEN \(s.rawValue)=\(String(format: "%.4f", sum))")
            XCTAssertEqual(sum, Self.previewGolden[s]!, accuracy: 0.01)
        }
    }

    // MARK: phát (bàn phím)

    /// Tắt ⇒ không dựng gì; bật ⇒ begin/move/end chỉ ghi khối điều khiển (main), engine + vòng lặp dựng NỀN; ẩn ⇒ nhả hết.
    func testLifecycleAndControlBlock() {
        let s = SwipeSound.shared
        s.configure(style: .none, volumePercent: 50)
        s.debugDrain()
        XCTAssertFalse(s.debugHasEngine)
        s.begin(x: 0, y: 0, t: 0)                       // Tắt: không làm gì
        XCTAssertFalse(s.debugIsSwiping)
        s.configure(style: .pencil, volumePercent: 50)
        s.debugDrain()
        XCTAssertFalse(s.debugHasBuffer, "chưa vuốt ⇒ chưa dựng (lười)")
        let b0 = s.debugControl.begins, e0 = s.debugControl.ends
        s.begin(x: 0, y: 0, t: 10)
        var t = 10.0, x = 0.0
        for _ in 0..<30 { t += 1.0 / 120; x += 8; s.move(x: x, y: 0, t: t) }
        XCTAssertEqual(s.debugControl.target, SwipeSoundFx.speedGain(960), accuracy: 0.05, "đích theo tốc độ ~960 pt/s")
        s.end()
        XCTAssertEqual(s.debugControl.begins, b0 + 1); XCTAssertEqual(s.debugControl.ends, e0 + 1)
        XCTAssertFalse(s.debugIsSwiping)
        s.move(x: 999, y: 0, t: t + 0.1)                // sau nhấc tay: bỏ qua
        s.debugDrain()
        // Simulator có thể không có thiết bị âm thanh: nếu engine chạy được thì buffer = vòng lặp Bút chì.
        if s.debugHasEngine { XCTAssertEqual(s.debugBuiltStyle, .pencil); XCTAssertTrue(s.debugHasBuffer) }
        s.shutdown()
        s.debugDrain()
        XCTAssertFalse(s.debugHasEngine); XCTAssertFalse(s.debugHasBuffer)
        XCTAssertEqual(s.style, .none)
    }

    /// Chi phí main mỗi điểm vuốt (đo, không phải giả định): ≪ 1 µs — gõ vuốt không chậm đi.
    func testPerPointCostIsTiny() {
        let s = SwipeSound.shared
        s.configure(style: .pencil, volumePercent: 50)
        s.begin(x: 0, y: 0, t: 0)
        let n = 200_000
        let t0 = CACurrentMediaTime()
        for i in 0..<n { s.move(x: Double(i % 300), y: 0, t: Double(i) / 120) }
        let per = (CACurrentMediaTime() - t0) / Double(n) * 1e6
        print("SWIPE-SOUND-MOVE-COST \(String(format: "%.3f", per)) µs/điểm")
        XCTAssertLessThan(per, 2.0)
        s.end()
        s.shutdown(); s.debugDrain()
    }
}
