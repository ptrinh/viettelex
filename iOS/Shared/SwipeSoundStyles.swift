// "Âm thanh nét vuốt" (Gõ vuốt → Âm thanh nét vuốt) — phần THUẦN, dùng chung app (chọn + nghe thử) và bàn phím (phát).
// Song sinh android/keyboard/.../SwipeSound.kt: cùng khoá `swipeSound`, cùng id, cùng số. Trong lúc ngón đang vuốt một
// từ: tiếng lặp liên tục, nhỏ, như dụng cụ lướt trên giấy/bảng — to/nhỏ theo tốc độ ngón (đứng yên ⇒ im), tắt dần
// ~100 ms khi nhấc tay. Mẫu lặp: KeySoundSynth.swipeLoopSamples (tổng hợp, không file âm thanh). Phát: Keyboard/SwipeSound.swift.
//
// "Tắt" (mặc định) + "Bút chì" miễn phí; còn lại Plus (cùng cổng với Hiệu ứng nét vuốt) — chưa có Plus / Chế độ nguồn
// điện thấp ⇒ phát Bút chì, giá trị lưu giữ nguyên.
// Roi vụt / Tia sét / Plasma / Đũa phép: thêm MỘT tiếng ngắn lúc nhấc tay (không khi huỷ), to theo tốc độ ngón ~80 ms cuối
// (SwipeSoundFx.liftGain — ngón gần như đứng yên ⇒ không kêu). Đũa phép thêm lớp hạt dày (× âm lượng²) ⇒ vuốt nhanh dày hơn.
// "Âm của bạn" (custom): file người dùng chọn, xử lý thành vòng lặp (SwipeSoundCustom) — vắng/hỏng ⇒ Bút chì.
import Foundation

enum SwipeSoundStyle: String, CaseIterable {
    case none, pencil, brush, chalk, marker, whip, lightning, plasma, wand, custom

    static let key = "swipeSound"
    static let defaultValue: SwipeSoundStyle = .none
    /// Kiểu miễn phí thay cho kiểu Plus khi chưa có Plus / nguồn điện thấp.
    static let fallback: SwipeSoundStyle = .pencil

    /// Giá trị lạ / thiếu ⇒ Tắt.
    static func parse(_ raw: Any?) -> SwipeSoundStyle {
        (raw as? String).flatMap(SwipeSoundStyle.init(rawValue:)) ?? defaultValue
    }
    static func load(_ d: UserDefaults?) -> SwipeSoundStyle { parse(d?.object(forKey: key)) }
    /// Kiểu hiện ở dòng cài đặt: kiểu Plus khi chưa có Plus ⇒ Bút chì (giá trị lưu giữ nguyên).
    static func displayed(_ raw: Any?, plus: Bool = SwipeSoundGate.allows) -> SwipeSoundStyle {
        let s = parse(raw)
        return s.isPlus && !plus ? fallback : s
    }

    var title: String {
        switch self {
        case .none: return L("Tắt")
        case .pencil: return L("Bút chì")
        case .brush: return L("Chổi lông")
        case .chalk: return L("Phấn bảng")
        case .marker: return L("Bút dạ")
        case .whip: return L("Roi vụt")
        case .lightning: return L("Tia sét")
        case .plasma: return L("Plasma")
        case .wand: return L("Đũa phép")
        case .custom: return L("Âm của bạn")
        }
    }

    /// Tắt + Bút chì miễn phí; còn lại thuộc Plus.
    var isPlus: Bool { self != .none && self != .pencil }
    /// Có tiếng ngắn lúc nhấc tay (KeySoundSynth.swipeLiftSamples).
    var hasLift: Bool { self == .whip || self == .lightning || self == .plasma || self == .wand }
    /// Kiểu tổng hợp (có vòng lặp riêng trong KeySoundSynth) — trừ Tắt và Âm của bạn.
    static let synthesized: [SwipeSoundStyle] = allCases.filter { $0 != .none && $0 != .custom }
}

/// Cổng Plus: như Hiệu ứng nét vuốt (quyền theme cao cấp).
enum SwipeSoundGate {
    static var allows: Bool { PlusGate.isUnlocked(.premiumThemes) }
    static func allows(_ s: SwipeSoundStyle) -> Bool { !s.isPlus || allows }
}

/// Kiểu thực phát — hàm thuần (test). = Android SwipeSoundPolicy.
enum SwipeSoundPolicy {
    /// Tắt / âm lượng 0 ⇒ Tắt (0 chi phí). Kiểu Plus chưa có Plus / nguồn điện thấp ⇒ Bút chì.
    static func active(setting: SwipeSoundStyle, plus: Bool, lowPower: Bool, volumePercent: Int) -> SwipeSoundStyle {
        if setting == .none || volumePercent <= 0 { return .none }
        if setting.isPlus && (!plus || lowPower) { return SwipeSoundStyle.fallback }
        return setting
    }
}

/// Số + hàm thuần dùng chung hai nền tảng (Android SwipeSoundFx cùng số). Tốc độ: pt/s (iOS) = dp/s (Android).
enum SwipeSoundFx {
    /// Dưới tốc độ này ⇒ im (ngón gần như đứng yên).
    static let speedMin = 40.0
    /// Từ tốc độ này trở lên ⇒ to hết cỡ (trần 1).
    static let speedFull = 1500.0
    /// Làm mượt tốc độ (EMA) — hằng thời gian, giây.
    static let speedTau = 0.05
    /// Bước thời gian tối đa đưa vào EMA.
    static let maxDt = 0.1
    /// Điểm gộp cách nhau dưới chừng này giây ⇒ chờ điểm sau (tránh chia cho ~0).
    static let minDt = 0.001
    /// Không có điểm mới quá chừng này ⇒ ngón đứng yên ⇒ đích = 0.
    static let hold = 0.08
    /// Âm lượng tiến về đích — hằng thời gian, giây.
    static let rampTau = 0.03
    /// Nhấc tay / huỷ: tắt dần TUYẾN TÍNH trong chừng này giây.
    static let fadeOut = 0.1
    /// Android: nhịp đặt âm lượng SoundPool (giây). iOS chạy từng mẫu trong render.
    static let tick = 0.025
    /// Tiếng nhấc tay: đo tốc độ trong chừng này giây cuối trước khi nhấc.
    static let liftWindow = 0.08
    /// Dưới tốc độ này (pt/s, trung bình `liftWindow` cuối) ⇒ không có tiếng nhấc tay (ngón gần như đứng yên).
    static let liftMin = 150.0
    /// Bản nghe thử trong app: độ to tiếng nhấc tay cố định (nét mẫu chậm dần về 0 ở cuối).
    static let previewLiftGain = 0.8

    /// Tốc độ (đã làm mượt) → 0…1: căn bậc hai cho cảm giác đều tay, trần 1.
    static func speedGain(_ speed: Double) -> Double {
        if speed <= speedMin { return 0 }
        return min(1, (speed - speedMin) / (speedFull - speedMin)).squareRoot()
    }

    /// Độ to tiếng nhấc tay 0…1 theo tốc độ ~80 ms cuối: dưới `liftMin` ⇒ 0; căn bậc hai, đủ cỡ từ `speedFull`.
    static func liftGain(_ speed: Double) -> Double {
        if speed <= liftMin { return 0 }
        return min(1, (speed - liftMin) / (speedFull - liftMin)).squareRoot()
    }

    /// Đích âm lượng: ngón đứng yên quá `hold` ⇒ 0.
    static func target(_ gain: Double, sinceMove: Double) -> Double { sinceMove > hold ? 0 : gain }

    /// EMA tốc độ: `inst` = tốc độ tức thời, `dt` = giây kể từ điểm trước.
    static func smooth(_ prev: Double, _ inst: Double, dt: Double) -> Double {
        let a = 1 - exp(-min(dt, maxDt) / speedTau)
        return prev + (inst - prev) * a
    }
}

/// Đo tốc độ ngón (main, mỗi điểm vuốt) — struct, không cấp phát (vòng đệm cấp một lần). = Android SwipeSoundMeter.
struct SwipeSoundMeter {
    private(set) var speed = 0.0
    private var lastX = 0.0, lastY = 0.0, lastT = 0.0
    /// Vòng đệm các đoạn gần nhất (quãng đường, giờ cuối đoạn) — cho tốc độ `liftWindow` cuối lúc nhấc tay.
    static let ring = 32
    private var segD = [Double](repeating: 0, count: Self.ring), segT = [Double](repeating: 0, count: Self.ring)
    private var head = 0, filled = 0

    mutating func reset(x: Double, y: Double, t: Double) { lastX = x; lastY = y; lastT = t; speed = 0; filled = 0 }

    /// Một điểm mới (toạ độ pt, thời gian giây).
    mutating func move(x: Double, y: Double, t: Double) {
        let dt = t - lastT
        guard dt >= SwipeSoundFx.minDt else { return }   // điểm gộp trùng giờ: đo từ điểm cũ ở lần sau
        let dist = hypot(x - lastX, y - lastY)
        speed = SwipeSoundFx.smooth(speed, dist / dt, dt: dt)
        lastX = x; lastY = y; lastT = t
        segD[head] = dist; segT[head] = t
        head = (head + 1) % Self.ring
        filled = min(filled + 1, Self.ring)
    }

    var gain: Double { SwipeSoundFx.speedGain(speed) }

    /// Tốc độ trung bình trong `liftWindow` giây trước `now` (quãng đường các đoạn kết thúc trong cửa sổ / cửa sổ).
    /// Ngón đứng yên lâu hơn cửa sổ trước khi nhấc ⇒ 0.
    func recentSpeed(at now: Double) -> Double {
        let from = now - SwipeSoundFx.liftWindow
        var sum = 0.0
        for k in 0..<filled {
            let j = (head - 1 - k + Self.ring) % Self.ring
            if segT[j] < from { break }
            if segT[j] <= now + 1e-9 { sum += segD[j] }
        }
        return sum / SwipeSoundFx.liftWindow
    }
}

/// Vỏ âm lượng 0…1 theo bước `step` giây (iOS: 1 mẫu; Android: tick). Đang vuốt: tiến về đích (rampTau); nhấc tay
/// (`release`): giảm tuyến tính về 0 trong `fadeOut`. = Android SwipeSoundEnvelope.
struct SwipeSoundEnvelope {
    private let k: Double
    private let fadeFrac: Double
    private(set) var gain = 0.0
    private(set) var releasing = false
    private var fadeStep = 0.0

    init(step: Double) {
        k = 1 - exp(-step / SwipeSoundFx.rampTau)
        fadeFrac = step / SwipeSoundFx.fadeOut
    }

    mutating func begin() { releasing = false }

    mutating func release() {
        guard !releasing else { return }
        releasing = true
        fadeStep = max(gain * fadeFrac, 1e-9)
    }

    @discardableResult
    mutating func next(_ target: Double) -> Double {
        gain = releasing ? max(0, gain - fadeStep) : gain + (target - gain) * k
        return gain
    }

    /// Đã tắt hẳn sau nhấc tay.
    var finished: Bool { releasing && gain <= 0 }

    mutating func reset() { gain = 0; releasing = false; fadeStep = 0 }
}

/// "Âm của bạn": file người dùng chọn → MỘT vòng lặp liền mạch (22,05 kHz mono). Xử lý thuần (= Android SwipeSoundCustom):
/// giải mã ở app (AVAudioFile, KeySoundImport.decode) → `process` → WAV trong App Group (`fileURL`; bàn phím đọc — cần Full
/// Access). Chỉ trên máy này: không tải lên đâu, KHÔNG vào file sao lưu (như âm phím tự chọn — chỉ key `swipeSound` đi theo).
enum SwipeSoundCustom {
    /// Tối đa chừng này giây làm vòng lặp (phần sau bị cắt).
    static let maxDuration = 3.0
    /// Âm ngắn hơn ⇒ lặp lại nối tiếp cho đủ (vòng quá ngắn nghe như rè).
    static let minLoop = 0.5
    /// Cùng đỉnh với vòng lặp tổng hợp (Bút chì / Phấn bảng).
    static let targetPeak: Float = 0.30
    static let fileName = "swipesound-custom.wav"

    static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppFlavor.appGroup)?
            .appendingPathComponent(fileName)
    }

    enum Failure: Error, Equatable { case empty, silent }
    struct Result: Equatable {
        let samples: [Float]
        /// true ⇒ âm gốc (sau khi bỏ lặng) dài hơn `maxDuration`, đã cắt.
        let truncated: Bool
    }

    /// mono ở `rate` → 22,05 kHz, bỏ lặng đầu/cuối, cắt ≤ `maxDuration`, nối đuôi vào đầu bằng trộn công suất đều 80 ms
    /// (như vòng tổng hợp ⇒ không "tách"), chuẩn hoá đỉnh `targetPeak`.
    static func process(_ mono: [Float], sampleRate rate: Double) throws -> Result {
        guard !mono.isEmpty, rate > 0 else { throw Failure.empty }
        let sr = KeySoundSynth.swipeSampleRate
        let x = KeySoundCustom.resample(mono, from: rate, to: sr)
        let peak = x.reduce(Float(0)) { max($0, abs($1)) }
        guard peak >= 0.001 else { throw Failure.silent }
        let thr = max(peak * 0.05, 0.001)
        let first = x.firstIndex { abs($0) >= thr } ?? 0
        let last = x.lastIndex { abs($0) >= thr } ?? (x.count - 1)
        let f = Int((KeySoundSynth.swipeCrossfade * sr).rounded())
        let cap = Int((maxDuration * sr).rounded())
        let avail = last + 1 - first
        let truncated = avail > cap + f
        var y = Array(x[first..<(first + min(avail, cap + f))])
        let need = Int((minLoop * sr).rounded()) + f
        if y.count < need {
            // Âm ngắn: mở/đóng 5 ms rồi lặp lại nối tiếp cho đủ.
            let e = min(y.count / 2, Int((0.005 * sr).rounded()))
            for i in 0..<e {
                let w = Float(0.5 - 0.5 * cos(Double.pi * Double(i) / Double(e)))
                y[i] *= w; y[y.count - 1 - i] *= w
            }
            var z = [Float]()
            z.reserveCapacity(need + y.count)
            while z.count < need { z += y }
            y = z
        }
        let len = y.count - f
        var out = [Float](repeating: 0, count: len)
        for i in 0..<len {
            if i < f {
                let w = Double(i) / Double(f)
                out[i] = Float(Double(y[i]) * sin(Double.pi / 2 * w) + Double(y[len + i]) * cos(Double.pi / 2 * w))
            } else {
                out[i] = y[i]
            }
        }
        let p2 = out.reduce(Float(0)) { max($0, abs($1)) }
        guard p2 > 0 else { throw Failure.silent }
        let g = targetPeak / p2
        return Result(samples: out.map { $0 * g }, truncated: truncated)
    }

    /// Vòng lặp đã xử lý (WAV 22,05 kHz mono). nil ⇒ vắng/hỏng.
    static func load(_ url: URL?) -> [Float]? {
        guard let url, let d = try? Data(contentsOf: url), let w = KeySoundSynth.parseWav(d), !w.samples.isEmpty,
              w.samples.count <= Int(maxDuration * KeySoundSynth.swipeSampleRate) + 16
        else { return nil }
        return KeySoundCustom.resample(w.samples, from: w.sampleRate, to: KeySoundSynth.swipeSampleRate)
    }

    /// Vòng lặp phát cho "Âm của bạn": file hợp lệ, không thì Bút chì (giá trị lưu giữ nguyên).
    static func resolvedLoop(_ custom: [Float]?) -> [Float] {
        if let c = custom, !c.isEmpty { return c }
        return KeySoundSynth.swipeLoopSamples(.pencil)
    }
}
