// "Âm thanh nét vuốt" (Gõ vuốt → Âm thanh nét vuốt) — phần THUẦN, dùng chung app (chọn + nghe thử) và bàn phím (phát).
// Song sinh android/keyboard/.../SwipeSound.kt: cùng khoá `swipeSound`, cùng id, cùng số. Trong lúc ngón đang vuốt một
// từ: tiếng lặp liên tục, nhỏ, như dụng cụ lướt trên giấy/bảng — to/nhỏ theo tốc độ ngón (đứng yên ⇒ im), tắt dần
// ~100 ms khi nhấc tay. Mẫu lặp: KeySoundSynth.swipeLoopSamples (tổng hợp, không file âm thanh). Phát: Keyboard/SwipeSound.swift.
//
// "Tắt" (mặc định) + "Bút chì" miễn phí; còn lại Plus (cùng cổng với Hiệu ứng nét vuốt) — chưa có Plus / Chế độ nguồn
// điện thấp ⇒ phát Bút chì, giá trị lưu giữ nguyên.
import Foundation

enum SwipeSoundStyle: String, CaseIterable {
    case none, pencil, brush, chalk, marker

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
        }
    }

    /// Tắt + Bút chì miễn phí; còn lại thuộc Plus.
    var isPlus: Bool { self != .none && self != .pencil }
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

    /// Tốc độ (đã làm mượt) → 0…1: căn bậc hai cho cảm giác đều tay, trần 1.
    static func speedGain(_ speed: Double) -> Double {
        if speed <= speedMin { return 0 }
        return min(1, (speed - speedMin) / (speedFull - speedMin)).squareRoot()
    }

    /// Đích âm lượng: ngón đứng yên quá `hold` ⇒ 0.
    static func target(_ gain: Double, sinceMove: Double) -> Double { sinceMove > hold ? 0 : gain }

    /// EMA tốc độ: `inst` = tốc độ tức thời, `dt` = giây kể từ điểm trước.
    static func smooth(_ prev: Double, _ inst: Double, dt: Double) -> Double {
        let a = 1 - exp(-min(dt, maxDt) / speedTau)
        return prev + (inst - prev) * a
    }
}

/// Đo tốc độ ngón (main, mỗi điểm vuốt) — struct, không cấp phát. = Android SwipeSoundMeter.
struct SwipeSoundMeter {
    private(set) var speed = 0.0
    private var lastX = 0.0, lastY = 0.0, lastT = 0.0

    mutating func reset(x: Double, y: Double, t: Double) { lastX = x; lastY = y; lastT = t; speed = 0 }

    /// Một điểm mới (toạ độ pt, thời gian giây).
    mutating func move(x: Double, y: Double, t: Double) {
        let dt = t - lastT
        guard dt >= SwipeSoundFx.minDt else { return }   // điểm gộp trùng giờ: đo từ điểm cũ ở lần sau
        let inst = hypot(x - lastX, y - lastY) / dt
        speed = SwipeSoundFx.smooth(speed, inst, dt: dt)
        lastX = x; lastY = y; lastT = t
    }

    var gain: Double { SwipeSoundFx.speedGain(speed) }
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
