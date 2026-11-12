// "Âm thanh nét vuốt" (12/11/2026): model + id chung Android, sao lưu, cổng Plus (hết Plus / nguồn điện thấp ⇒ Bút chì,
// giá trị giữ), chính sách bật (Full Access, gõ vuốt, âm lượng 0), đường cong tốc độ → âm lượng, vỏ âm lượng (tắt dần
// 100 ms), mẫu lặp tất định + checksum, chỗ nối vòng liền mạch, bản nghe thử, vòng đời engine (Tắt = không dựng gì), và chi
// phí main mỗi điểm vuốt. Số tham chiếu GIỐNG HỆT Android SwipeSoundTests.kt.
import XCTest
import AVFoundation

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
        XCTAssertEqual(SwipeSoundStyle.allCases.map(\.rawValue),
                       ["none", "pencil", "brush", "chalk", "marker", "whip", "lightning", "plasma", "wand", "custom"])
        XCTAssertEqual(SwipeSoundStyle.key, "swipeSound")
        XCTAssertEqual(SwipeSoundStyle.defaultValue, .none)
        XCTAssertEqual(SwipeSoundStyle.parse(nil), .none)
        XCTAssertEqual(SwipeSoundStyle.parse("loud"), .none)
        XCTAssertEqual(SwipeSoundStyle.parse(7), .none)
        XCTAssertEqual(SwipeSoundStyle.parse("chalk"), .chalk)
        XCTAssertEqual(SwipeSoundStyle.allCases.map(\.isPlus), [false, false, true, true, true, true, true, true, true, true])
        XCTAssertEqual(SwipeSoundStyle.allCases.filter(\.hasLift), [.whip, .lightning, .plasma, .wand])
        XCTAssertEqual(SwipeSoundStyle.synthesized.count, 8)
        XCTAssertFalse(SwipeSoundStyle.synthesized.contains(.custom))
        XCTAssertEqual(SwipeSoundStyle.parse("wand"), .wand)
        XCTAssertEqual(SwipeSoundStyle.parse("custom"), .custom)
        for s in SwipeSoundStyle.allCases { XCTAssertNotNil(L10n.en[s.title], "thiếu bản dịch: \(s.title)") }
        XCTAssertNotNil(L10n.en["Âm thanh nét vuốt"])
        let spec = BackupSettings.all.first { $0.key == SwipeSoundStyle.key }
        XCTAssertEqual(spec?.kind, .string("none", ["none", "pencil", "brush", "chalk", "marker", "whip", "lightning",
                                                    "plasma", "wand", "custom"]))
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
        for s in [SwipeSoundStyle.whip, .lightning, .plasma, .wand, .custom] {
            XCTAssertEqual(P.active(setting: s, plus: false, lowPower: false, volumePercent: 50), .pencil, "\(s) cần Plus")
            XCTAssertEqual(P.active(setting: s, plus: true, lowPower: false, volumePercent: 50), s)
            XCTAssertEqual(SwipeSoundStyle.displayed(s.rawValue, plus: false), .pencil)
        }
        // Controller: thiếu Full Access / gõ vuốt tắt ⇒ Tắt.
        typealias K = KeyboardViewController
        XCTAssertEqual(K.swipeSoundStyle(setting: .pencil, swipeOn: true, fullAccess: false, plus: true, lowPower: false, volumePercent: 50), .none)
        XCTAssertEqual(K.swipeSoundStyle(setting: .pencil, swipeOn: false, fullAccess: true, plus: true, lowPower: false, volumePercent: 50), .none)
        XCTAssertEqual(K.swipeSoundStyle(setting: .chalk, swipeOn: true, fullAccess: true, plus: true, lowPower: false, volumePercent: 50), .chalk)
        // Cổng = cổng Hiệu ứng nét vuốt.
        setPlus(false)
        XCTAssertFalse(SwipeSoundGate.allows)
        XCTAssertTrue(SwipeSoundGate.allows(.pencil)); XCTAssertFalse(SwipeSoundGate.allows(.chalk))
        XCTAssertFalse(SwipeSoundGate.allows(.whip)); XCTAssertFalse(SwipeSoundGate.allows(.custom))
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

    static let golden: [SwipeSoundStyle: Double] = [.pencil: 1060.9227, .brush: 1786.0301, .chalk: 932.4742, .marker: 1379.6404,
                                                    .whip: 1272.6721, .lightning: 878.1293, .plasma: 1586.8690, .wand: 1352.8294]
    static let previewGolden: [SwipeSoundStyle: Double] = [.pencil: 593.6883, .brush: 842.1863, .chalk: 364.0651, .marker: 786.1841,
                                                           .whip: 786.1677, .lightning: 579.4536, .plasma: 1061.6143,
                                                           .wand: 1066.6231]
    static let liftGolden: [SwipeSoundStyle: Double] = [.whip: 94.7710, .lightning: 239.0145, .plasma: 434.8444, .wand: 581.7851]
    static let layerGolden = 906.3455

    func testLoopsAreDeterministicSoftAndSeamless() {
        let sr = KeySoundSynth.swipeSampleRate
        XCTAssertTrue(KeySoundSynth.swipeLoopSamples(.none).isEmpty)
        XCTAssertTrue(KeySoundSynth.swipePreviewSamples(.none).isEmpty)
        XCTAssertEqual(KeySoundSynth.swipeLoopSamples(.custom), KeySoundSynth.swipeLoopSamples(.pencil), "Âm của bạn: dự phòng Bút chì")
        for s in SwipeSoundStyle.synthesized {
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
        XCTAssertGreaterThan(centroid(.whip), centroid(.brush) + 1000, "roi vụt sáng/gió hơn chổi lông")
        XCTAssertLessThan(centroid(.plasma), centroid(.whip), "plasma ù trầm")
    }

    /// Lớp hạt dày (chỉ Đũa phép) + tiếng nhấc tay (Roi vụt, Tia sét, Plasma, Đũa phép): tất định, độ dài, đỉnh, checksum chung.
    func testLayerAndLiftSamples() {
        let sr = KeySoundSynth.swipeSampleRate
        for s in SwipeSoundStyle.allCases where s != .wand { XCTAssertTrue(KeySoundSynth.swipeLayerSamples(s).isEmpty, "\(s)") }
        let layer = KeySoundSynth.swipeLayerSamples(.wand)
        XCTAssertEqual(layer, KeySoundSynth.swipeLayerSamples(.wand))
        XCTAssertEqual(layer.count, KeySoundSynth.swipeLoopSamples(.wand).count)
        XCTAssertEqual(Double(layer.map(abs).max() ?? 0), KeySoundSynth.swipeLayerPeak, accuracy: 1e-6)
        XCTAssertNotEqual(Array(layer[0..<2000]), Array(KeySoundSynth.swipeLoopSamples(.wand)[0..<2000]))
        let lsum = layer.reduce(0.0) { $0 + Double(abs($1)) }
        print("SWIPE-LAYER-GOLDEN wand=\(String(format: "%.4f", lsum))")
        XCTAssertEqual(lsum, Self.layerGolden, accuracy: 0.01)
        for s in SwipeSoundStyle.allCases where !s.hasLift { XCTAssertTrue(KeySoundSynth.swipeLiftSamples(s).isEmpty, "\(s)") }
        for s in SwipeSoundStyle.allCases where s.hasLift {
            let x = KeySoundSynth.swipeLiftSamples(s)
            XCTAssertEqual(x, KeySoundSynth.swipeLiftSamples(s), "tất định \(s)")
            XCTAssertTrue((Int(0.12 * sr)...Int(0.35 * sr)).contains(x.count), "ngắn: \(s) \(x.count)")
            let peak = Double(x.map(abs).max() ?? 0)
            XCTAssertLessThanOrEqual(peak, 0.55 + 1e-6, "không chói: \(s)")
            XCTAssertGreaterThan(peak, 0.3)
            XCTAssertLessThan(abs(x[x.count - 1]), 1e-3, "đóng mềm \(s)")
            let sum = x.reduce(0.0) { $0 + Double(abs($1)) }
            print("SWIPE-LIFT-GOLDEN \(s.rawValue)=\(String(format: "%.4f", sum))")
            XCTAssertEqual(sum, Self.liftGolden[s]!, accuracy: 0.01, "checksum chung Android: \(s)")
        }
        // Roi vụt: tiếng "chát" — đỉnh trong 10 ms đầu, đuôi nhiễu ngắn (20 ms đầu ≫ 50 ms cuối), dài 120–200 ms.
        let crack = KeySoundSynth.swipeLiftSamples(.whip)
        XCTAssertTrue((Int(0.12 * sr)...Int(0.2 * sr)).contains(crack.count))
        let iPeak = crack.indices.max { abs(crack[$0]) < abs(crack[$1]) } ?? 0
        XCTAssertLessThan(iPeak, Int(0.01 * sr), "đỉnh ở đầu")
        let w = Int(0.02 * sr), tail = Int(0.05 * sr)
        XCTAssertGreaterThan(KeySoundSynth.rms(Array(crack[0..<w])), 5 * KeySoundSynth.rms(Array(crack[(crack.count - tail)...])))
        // Plasma "víu" đi lên: trọng tâm phổ nửa sau > nửa đầu.
        let zw = KeySoundSynth.swipeLiftSamples(.plasma), h = zw.count / 2
        XCTAssertGreaterThan(KeySoundSynth.spectralCentroid(Array(zw[h...]), sampleRate: sr),
                             KeySoundSynth.spectralCentroid(Array(zw[..<h]), sampleRate: sr))
    }

    /// Độ to tiếng nhấc tay theo tốc độ 80 ms cuối: đứng yên / rê chậm ⇒ 0; nhanh ⇒ to; tốc độ đo đúng cửa sổ.
    func testLiftGainFollowsLastWindowSpeed() {
        typealias F = SwipeSoundFx
        XCTAssertEqual(F.liftGain(0), 0)
        XCTAssertEqual(F.liftGain(F.liftMin), 0, "gần như đứng yên ⇒ không kêu")
        XCTAssertEqual(F.liftGain(F.speedFull), 1, accuracy: 1e-12)
        XCTAssertEqual(F.liftGain(9000), 1)
        XCTAssertEqual(F.liftGain(525), 0.527046, accuracy: 1e-6)   // số tham chiếu chung Android
        var m = SwipeSoundMeter()
        m.reset(x: 0, y: 0, t: 0)
        var t = 0.0, x = 0.0
        for _ in 0..<60 { t += 1.0 / 120; x += 8; m.move(x: x, y: 0, t: t) }   // 960 pt/s
        XCTAssertEqual(m.recentSpeed(at: t), 960, accuracy: 960 * 0.15, "nhấc ngay: ~tốc độ 80 ms cuối")
        XCTAssertEqual(m.recentSpeed(at: t + 0.1), 0, "dừng 100 ms rồi mới nhấc ⇒ 0")
        XCTAssertEqual(F.liftGain(m.recentSpeed(at: t + 0.1)), 0)
        // Nhanh rồi chậm hẳn 100 ms cuối ⇒ chỉ tính đoạn chậm (60 pt/s) ⇒ không kêu.
        for _ in 0..<12 { t += 1.0 / 120; x += 0.5; m.move(x: x, y: 0, t: t) }
        XCTAssertLessThan(m.recentSpeed(at: t), 100)
        XCTAssertEqual(F.liftGain(m.recentSpeed(at: t)), 0)
        // Vòng đệm đầy (240 Hz, 0,5 s) vẫn đúng; reset ⇒ 0.
        var n = SwipeSoundMeter()
        n.reset(x: 0, y: 0, t: 0)
        var tt = 0.0
        for i in 1...120 { tt = Double(i) / 240; n.move(x: Double(i) * 5, y: 0, t: tt) }   // 1200 pt/s
        XCTAssertEqual(n.recentSpeed(at: tt), 1200, accuracy: 1200 * 0.1)
        n.reset(x: 0, y: 0, t: tt)
        XCTAssertEqual(n.recentSpeed(at: tt), 0)
    }

    // MARK: Âm của bạn

    private func tmpDir() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("ss-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private func sine(_ seconds: Double, rate: Double, freq: Double = 440, amp: Float = 0.9, lead: Double = 0) -> [Float] {
        let n = Int((seconds + lead) * rate)
        return (0..<n).map { i in
            let t = Double(i) / rate - lead
            return t < 0 ? 0 : amp * Float(sin(2 * .pi * freq * t))
        }
    }

    /// Xử lý: bỏ lặng, cắt ≤ 3 s (báo cắt), chuẩn hoá đỉnh như vòng tổng hợp, chỗ nối vòng liền (mẫu cuối → mẫu đầu).
    func testCustomProcessTrimsNormalisesAndLoopsSeamlessly() throws {
        let sr = KeySoundSynth.swipeSampleRate
        let long = try SwipeSoundCustom.process(sine(5, rate: 44_100, lead: 0.3), sampleRate: 44_100)
        XCTAssertTrue(long.truncated)
        XCTAssertEqual(long.samples.count, Int(SwipeSoundCustom.maxDuration * sr), "đúng 3 s")
        XCTAssertEqual(long.samples.map(abs).max() ?? 0, SwipeSoundCustom.targetPeak, accuracy: 1e-4)
        XCTAssertEqual(Double(SwipeSoundCustom.targetPeak), KeySoundSynth.swipePeak(.pencil), accuracy: 1e-6)
        XCTAssertGreaterThan(KeySoundSynth.rms(Array(long.samples[0..<Int(0.05 * sr)])), 0.1, "lặng đầu đã bỏ")
        for r in [long.samples, try SwipeSoundCustom.process(sine(1.5, rate: 48_000, freq: 523), sampleRate: 48_000).samples] {
            var maxStep: Float = 0
            for i in 1..<r.count { maxStep = max(maxStep, abs(r[i] - r[i - 1])) }
            XCTAssertLessThanOrEqual(abs(r[0] - r[r.count - 1]), maxStep * 1.05, "nối vòng không tách")
        }
        let mid = try SwipeSoundCustom.process(sine(1.5, rate: sr), sampleRate: sr)
        XCTAssertFalse(mid.truncated)
        XCTAssertEqual(mid.samples.count, Int(1.5 * sr) - Int((KeySoundSynth.swipeCrossfade * sr).rounded()), accuracy: 2)
        // Âm rất ngắn (0,1 s) ⇒ lặp lại cho đủ ≥ 0,5 s.
        let short = try SwipeSoundCustom.process(sine(0.1, rate: sr), sampleRate: sr)
        XCTAssertGreaterThanOrEqual(short.samples.count, Int(SwipeSoundCustom.minLoop * sr))
        XCTAssertLessThanOrEqual(short.samples.count, Int(SwipeSoundCustom.maxDuration * sr))
        XCTAssertThrowsError(try SwipeSoundCustom.process([], sampleRate: sr))
        XCTAssertThrowsError(try SwipeSoundCustom.process([Float](repeating: 0, count: 5000), sampleRate: sr))
    }

    /// Vắng / hỏng / quá dài ⇒ nil ⇒ phát Bút chì; nhập file thật (AVAudioFile) ⇒ đọc lại đúng.
    func testCustomLoadFallbackAndImport() throws {
        let d = tmpDir(); defer { try? FileManager.default.removeItem(at: d) }
        let dst = d.appendingPathComponent(SwipeSoundCustom.fileName)
        XCTAssertNil(SwipeSoundCustom.load(nil))
        XCTAssertNil(SwipeSoundCustom.load(dst), "vắng")
        XCTAssertEqual(SwipeSoundCustom.resolvedLoop(SwipeSoundCustom.load(dst)), KeySoundSynth.swipeLoopSamples(.pencil))
        try Data("not a wav".utf8).write(to: dst)
        XCTAssertNil(SwipeSoundCustom.load(dst), "hỏng")
        try KeySoundSynth.wav(sine(4, rate: KeySoundSynth.swipeSampleRate), sampleRate: Int(KeySoundSynth.swipeSampleRate)).write(to: dst)
        XCTAssertNil(SwipeSoundCustom.load(dst), "quá dài ⇒ không tin")
        XCTAssertNil(SwipeSoundImport.storedDuration(dst))
        // Nhập thật: stereo 48 kHz, lặng 0,25 s + 4 s sine ⇒ 3 s, đỉnh 0,30.
        let src = d.appendingPathComponent("long.wav")
        let rate = 48_000.0, fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        let mono = sine(4, rate: rate, lead: 0.25)
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(mono.count))!
        buf.frameLength = AVAudioFrameCount(mono.count)
        for c in 0..<2 { for i in 0..<mono.count { buf.floatChannelData![c][i] = mono[i] } }
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 2,
                                       AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false]
        do { let f = try AVAudioFile(forWriting: src, settings: settings); try f.write(from: buf) }
        let o = try SwipeSoundImport.importFile(src, to: dst)
        XCTAssertTrue(o.truncated)
        XCTAssertEqual(o.duration, SwipeSoundCustom.maxDuration, accuracy: 1e-3)
        let loop = try XCTUnwrap(SwipeSoundCustom.load(dst))
        XCTAssertEqual(Double(loop.count) / KeySoundSynth.swipeSampleRate, SwipeSoundCustom.maxDuration, accuracy: 1e-3)
        XCTAssertEqual(loop.map(abs).max() ?? 0, SwipeSoundCustom.targetPeak, accuracy: 2e-3)
        XCTAssertEqual(SwipeSoundImport.storedDuration(dst) ?? 0, SwipeSoundCustom.maxDuration, accuracy: 1e-3)
        XCTAssertEqual(SwipeSoundCustom.resolvedLoop(loop), loop)
        // Nghe thử dùng đúng vòng lặp đó, tắt dần sau nhấc tay.
        let pv = KeySoundSynth.swipePreview(loop: loop)
        XCTAssertEqual(pv.count, Int(KeySoundSynth.swipePreview * KeySoundSynth.swipeSampleRate))
        SwipeSoundImport.remove(dst)
        XCTAssertNil(SwipeSoundCustom.load(dst), "Xoá ⇒ vắng ⇒ Bút chì")
    }

    func testPreviewFollowsDemoSwipeAndFadesOut() {
        let sr = KeySoundSynth.swipeSampleRate
        XCTAssertEqual(KeySoundSynth.swipeDemoSpeed(0), 0)
        XCTAssertEqual(KeySoundSynth.swipeDemoSpeed(KeySoundSynth.swipePreviewLift), 0)
        XCTAssertEqual(KeySoundSynth.swipeDemoSpeed(KeySoundSynth.swipePreviewLift / 2), 675, accuracy: 1e-9)   // giữa nét: chậm ở phím
        for s in SwipeSoundStyle.synthesized {
            let p = KeySoundSynth.swipePreviewSamples(s)
            let shot = KeySoundSynth.swipeLiftSamples(s)
            let liftAt = Int((KeySoundSynth.swipePreviewLift * sr).rounded())
            XCTAssertEqual(p.count, max(Int(KeySoundSynth.swipePreview * sr), liftAt + shot.count))
            XCTAssertEqual(p, KeySoundSynth.swipePreviewSamples(s))
            let lift = Int(KeySoundSynth.swipePreviewLift * sr)
            let fadeEnd = lift + Int(SwipeSoundFx.fadeOut * sr) + 2
            for i in fadeEnd..<p.count {
                let k = i - liftAt
                let want: Float = k < shot.count ? Float(Double(shot[k]) * SwipeSoundFx.previewLiftGain) : 0
                if p[i] != want { XCTFail("sau tắt dần chỉ còn tiếng nhấc tay (\(s)) @\(i)"); break }
            }
            XCTAssertLessThan(abs(p[0]), 1e-3, "mở từ 0")
            let cap = KeySoundSynth.swipePeak(s) + (s == .wand ? KeySoundSynth.swipeLayerPeak : 0)
                + (shot.map(abs).max().map { Double($0) } ?? 0) * SwipeSoundFx.previewLiftGain
            XCTAssertLessThanOrEqual(Double(p.map(abs).max() ?? 0), cap + 1e-6)
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

    /// Tiếng nhấc tay: chỉ khi NHẤC (không khi huỷ), chỉ kiểu có tiếng, chỉ khi ngón còn đang đi; độ to theo tốc độ cuối.
    func testLiftShotOnlyOnReleaseWithSpeed() {
        let s = SwipeSound.shared
        func swipe(_ start: Double, speed: Double) -> Double {
            s.begin(x: 0, y: 0, t: start)
            var t = start, x = 0.0
            for _ in 0..<30 { t += 1.0 / 120; x += speed / 120; s.move(x: x, y: 0, t: t) }
            return t
        }
        s.configure(style: .whip, volumePercent: 50)
        let c0 = s.debugLift.count
        var t = swipe(100, speed: 960)
        s.end(liftAt: t)
        XCTAssertEqual(s.debugLift.count, c0 + 1, "nhấc tay ⇒ một tiếng")
        XCTAssertEqual(s.debugLift.gain, SwipeSoundFx.liftGain(960), accuracy: 0.08)
        t = swipe(t + 1, speed: 960)
        s.end()                                          // huỷ
        XCTAssertEqual(s.debugLift.count, c0 + 1, "huỷ ⇒ không kêu")
        t = swipe(t + 1, speed: 960)
        s.end(liftAt: t + 0.2)                           // dừng 200 ms rồi mới nhấc
        XCTAssertEqual(s.debugLift.count, c0 + 1, "ngón đứng yên ⇒ không kêu")
        t = swipe(t + 1, speed: 100)
        s.end(liftAt: t)                                 // rê chậm
        XCTAssertEqual(s.debugLift.count, c0 + 1, "rê chậm ⇒ không kêu")
        t = swipe(t + 1, speed: 1500)
        s.end(liftAt: t)
        XCTAssertEqual(s.debugLift.count, c0 + 2)
        XCTAssertGreaterThan(s.debugLift.gain, SwipeSoundFx.liftGain(960), "nhanh hơn ⇒ to hơn")
        s.configure(style: .pencil, volumePercent: 50)
        t = swipe(t + 1, speed: 1500)
        s.end(liftAt: t)
        XCTAssertEqual(s.debugLift.count, c0 + 2, "Bút chì không có tiếng nhấc tay")
        s.shutdown(); s.debugDrain()
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
