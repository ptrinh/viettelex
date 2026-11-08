// "Hiệu ứng khi bấm phím" (Plus, Phil 19/10/2026): Trái tim, Bong bóng, Gợn sóng,
// Cánh hoa, Pháo hoa, Nháy sáng, Matrix, Tia sét, Emoji theo chữ, Hoa đào / mai, Lửa combo, Mực loang,
// Sóng nước, Tuyết rơi, Sao băng, Đèn lồng, Sương ma, Rung dây; "Không" = mặc định. Song sinh android/keyboard/.../KeyEffect.kt (cùng khoá
// `keyEffect`, cùng id, cùng quỹ đạo / cùng hàm thuần: tia sét, mảnh vỡ, combo, nháy sáng, emoji).
//
// Luật hiệu năng (feature-flags-perf-policy — gõ mượt là số 1):
//  • TẮT (mặc định) / chưa có Plus / Chế độ nguồn điện thấp ⇒ KeyboardView không
//    tạo overlay (`keyEffects == nil`) — đường phím chỉ đọc một biến optional.
//  • BẬT: chữ chèn TRƯỚC (KeyboardView.tapped → onKey), overlay chỉ ghi khung phím rồi hẹn MỘT lượt
//    DispatchQueue.main.async — lượt vẽ chạy sau khi xử lý xong sự kiện chạm.
//  • Chỉ Core Animation: animation gắn MỘT lần lúc dựng layer (pool), bấm chỉ đổi vài thuộc tính +
//    `beginTime` ⇒ render server chạy phần còn lại, không timer/display link, không vẽ CPU mỗi khung.
//  • Hai dải z: TRÊN phím (zPosition 5, dưới ô phóng to 10) cho đa số kiểu; DƯỚI phím (trên nền / ảnh
//    nền, `KeyEffectBand.belowKeys`) cho Matrix / Mực loang / Sóng nước / Rung dây (dây ở khe hàng, trên hoạ tiết).
import UIKit

/// Kiểu hiệu ứng (giá trị lưu App Group / sao lưu = rawValue).
enum KeyEffect: String, CaseIterable {
    case none, heart, bubble, ripple, petal, firework
    case flash, matrix, lightning
    case emojiword, blossom, combo, ink, wave
    case snow
    // Bộ đủ món (theme Vũ trụ, 10/2026). Chỉ thêm CUỐI (id sao lưu / theme JSON).
    case meteor
    // Bộ theme đủ món 10/2026: Đèn lồng (Trung Thu), Sương ma (Halloween) — đốm sáng mềm dựng sẵn (GlowSprite).
    case lantern, smoke
    // Theme Ghi-ta (10/2026): Rung dây — đoạn dây ở khe hàng gần phím rung sóng dừng rồi đứng yên (StringPluck).
    case string

    static let key = "keyEffect"
    static let defaultValue: KeyEffect = .none

    /// Giá trị lạ / thiếu ⇒ Không.
    static func parse(_ raw: Any?) -> KeyEffect {
        (raw as? String).flatMap(KeyEffect.init(rawValue:)) ?? defaultValue
    }
    static func load(_ d: UserDefaults?) -> KeyEffect { parse(d?.object(forKey: key)) }

    var title: String {
        switch self {
        case .none: return L("Không")
        case .heart: return L("Trái tim")
        case .bubble: return L("Bong bóng")
        case .ripple: return L("Gợn sóng")
        case .petal: return L("Cánh hoa")
        case .firework: return L("Pháo hoa")
        case .flash: return L("Nháy sáng")
        case .matrix: return L("Matrix")
        case .lightning: return L("Tia sét")
        case .emojiword: return L("Emoji theo chữ")
        case .blossom: return L("Hoa đào / mai")
        case .combo: return L("Lửa combo")
        case .ink: return L("Mực loang")
        case .wave: return L("Sóng nước")
        case .snow: return L("Tuyết rơi")
        case .meteor: return L("Sao băng")
        case .lantern: return L("Đèn lồng")
        case .smoke: return L("Sương ma")
        case .string: return L("Rung dây")
        }
    }

    /// Mọi kiểu trừ "Không" thuộc Plus.
    var isPlus: Bool { self != .none }

    /// Kiểu "hạt bay ra từ phím" (chùm hạt vector, quỹ đạo `trajectory`).
    static let particleCases: [KeyEffect] = [.heart, .bubble, .ripple, .petal, .firework, .blossom, .combo, .snow, .meteor,
                                             .lantern, .smoke]
    /// Hạt là ẢNH đốm sáng mềm dựng sẵn (GlowSprite — một lần mỗi màu), không path: Đèn lồng, Sương ma.
    var usesGlow: Bool { self == .lantern || self == .smoke }
    var isParticle: Bool { Self.particleCases.contains(self) }

    /// Dải z: Matrix / Mực loang / Sóng nước vẽ trên nền nhưng DƯỚI phím.
    var band: KeyEffectBand {
        switch self {
        case .matrix, .ink, .wave, .string: return .belowKeys
        default: return .aboveKeys
        }
    }

    /// Màu cố định (không theo màu nhấn) — hạt thứ i dùng màu i % count. Rỗng = màu nhấn.
    var fixedColors: [UInt32] {
        switch self {
        case .blossom: return [0xFF8FB1, 0xFFC93C]            // đào hồng, mai vàng
        case .combo: return [0xFF7A1A, 0xFFC21A, 0xFF3B30]     // cam, vàng, đỏ
        case .snow: return [0xFFFFFF]
        case .meteor: return [MeteorStreak.color]
        case .matrix: return [MatrixRain.green]
        case .lantern: return [0xFFA03C, 0xFFD27A]                // cam đèn lồng, vàng nến
        case .smoke: return [0xA594C8, 0x8B7BAA, 0xC2B8D6]        // tím xám

        default: return []
        }
    }

    /// Số hạt mỗi lần bấm (Lửa combo: tối đa — mức combo quyết định số hạt thật).
    var particlesPerTap: Int {
        switch self {
        case .heart, .bubble, .petal, .blossom, .combo: return 3
        case .ripple, .meteor: return 1
        case .firework: return 6
        case .snow: return 4
        case .lantern: return 2
        case .smoke: return 3
        default: return 0
        }
    }

    /// Số chùm xoay vòng của overlay (mỗi lần bấm một chùm) — tổng hạt ≤ KeyEffectPool.cap; gõ nhanh
    /// hơn số chùm thì chùm cũ nhất bị bắn lại.
    var burstSlots: Int {
        switch self {
        case .ink: return 4
        case .wave: return 3              // 3 vòng mỗi chùm ⇒ 9 layer
        case .string: return StringPluck.pool
        case .emojiword: return 3
        default:
            guard particlesPerTap > 0 else { return 1 }
            return max(1, min(8, KeyEffectPool.cap / particlesPerTap))
        }
    }

    /// Số layer con mỗi chùm.
    var layersPerBurst: Int {
        switch self {
        case .ink, .emojiword, .string: return 1
        case .wave: return WaveRings.rings
        default: return particlesPerTap
        }
    }

    /// Số quỹ đạo dựng sẵn (bội của particlesPerTap): hạt i của lần bấm dùng quỹ đạo
    /// `i * stride + seed % stride` — trái/giữa/phải (tim) hay toả đều (pháo hoa) nhưng mỗi lần lệch chút.
    var variantCount: Int { particlesPerTap * 2 }

    /// Quỹ đạo thứ `v` (pt, giây, radian) — hàm thuần, Android dùng y hệt.
    func trajectory(_ v: Int) -> KeyEffectTrajectory {
        let n = max(variantCount, 1)
        let t = n > 1 ? (Double(v) - Double(n - 1) / 2) / (Double(n - 1) / 2) : 0   // −1…1
        switch self {
        case .heart:
            return KeyEffectTrajectory(dx: t * 24, dy: -(46 + Double(v % 3) * 7), scaleFrom: 0.5,
                                       scaleTo: 1.0 + Double(v % 2) * 0.15, rotation: t * 0.35,
                                       duration: 0.8 + Double(v % 3) * 0.05)
        case .bubble:
            return KeyEffectTrajectory(dx: t * 16, dy: -(52 + Double(v % 3) * 8), scaleFrom: 0.4,
                                       scaleTo: 1.0 + Double(v % 2) * 0.2, rotation: 0,
                                       duration: 0.9 + Double(v % 2) * 0.1)
        case .ripple:
            return KeyEffectTrajectory(dx: 0, dy: 0, scaleFrom: 0.35, scaleTo: 1.6 + Double(v % 2) * 0.2,
                                       rotation: 0, duration: 0.45)
        case .petal:
            return KeyEffectTrajectory(dx: t * 34, dy: 12 + Double(v % 3) * 8, scaleFrom: 0.7, scaleTo: 1.0,
                                       rotation: t * 2.4 + 0.6, duration: 0.95)
        case .firework:
            let a = Double(v) * 2 * Double.pi / Double(n)
            let d = 30.0 + Double(v % 2) * 6
            return KeyEffectTrajectory(dx: cos(a) * d, dy: sin(a) * d, scaleFrom: 1.0, scaleTo: 0.4,
                                       rotation: 0, duration: 0.55)
        case .blossom:   // bay lên, trôi ngang, xoay chậm
            return KeyEffectTrajectory(dx: t * 30, dy: -(40 + Double(v % 3) * 9), scaleFrom: 0.6, scaleTo: 1.0,
                                       rotation: t * 1.6 + 0.4, duration: 1.0, sway: 6)
        case .combo:     // ngọn lửa bốc thẳng, co lại
            return KeyEffectTrajectory(dx: t * 8, dy: -(26 + Double(v % 3) * 6), scaleFrom: 1.0, scaleTo: 0.35,
                                       rotation: 0, duration: 0.5)
        case .snow:      // rơi XUỐNG, lắc ngang nhẹ
            return KeyEffectTrajectory(dx: t * 14, dy: 40 + Double(v % 3) * 8, scaleFrom: 0.8,
                                       scaleTo: 1.0 + Double(v % 2) * 0.15, rotation: t * 1.2,
                                       duration: 1.2, sway: 7)
        case .meteor:    // vệt sáng lao CHÉO lên phải theo đúng góc của hình (không xoay), dài ra rồi tắt
            let d = MeteorStreak.distance + Double(v % 2) * 8
            return KeyEffectTrajectory(dx: cos(MeteorStreak.angle) * d, dy: sin(MeteorStreak.angle) * d,
                                       scaleFrom: 0.55, scaleTo: 1.0, rotation: 0, duration: MeteorStreak.duration)
        case .lantern:   // đốm sáng bay LÊN chậm như đèn trời, nhỏ dần (xa dần), lắc nhẹ
            return KeyEffectTrajectory(dx: t * 10, dy: -(56 + Double(v % 2) * 10), scaleFrom: 1.0,
                                       scaleTo: 0.55 + Double(v % 2) * 0.1, rotation: 0,
                                       duration: 1.2 - Double(1 - v % 2) * 0.1, sway: 4)
        case .smoke:     // làn sương phồng to, bốc lên ít, tan
            return KeyEffectTrajectory(dx: t * 12, dy: -(26 + Double(v % 3) * 6), scaleFrom: 0.5,
                                       scaleTo: 1.7 + Double(v % 2) * 0.3, rotation: 0,
                                       duration: 0.9 + Double(v % 3) * 0.1, sway: 5)
        default:
            return KeyEffectTrajectory(dx: 0, dy: 0, scaleFrom: 1, scaleTo: 1, rotation: 0, duration: 0)
        }
    }

    /// Quỹ đạo của hạt `i` trong lần bấm số `seed`.
    func variant(particle i: Int, seed: Int) -> Int {
        let stride = max(variantCount / max(particlesPerTap, 1), 1)
        return (i * stride + abs(seed) % stride) % max(variantCount, 1)
    }
}

enum KeyEffectBand { case aboveKeys, belowKeys }

struct KeyEffectTrajectory: Equatable {
    var dx: Double, dy: Double
    var scaleFrom: Double, scaleTo: Double
    var rotation: Double
    var duration: Double
    /// Lắc ngang (pt): x cộng thêm sway·sin(2π·f) — tuyết / hoa trôi.
    var sway: Double = 0
}

/// Đốm sáng mềm (Đèn lồng / Sương ma): ảnh gradient tròn dựng MỘT lần mỗi màu lúc đổi kiểu — bấm phím chỉ
/// dời / co giãn / mờ layer (GPU), không vẽ CPU. Điểm dừng gradient (vị trí 0…1, độ đậm) = Android GlowSprite.
enum GlowSprite {
    /// Đường kính ảnh (pt / dp).
    static let size = 26.0
    /// Lõi sáng ấm của đèn lồng (tâm đốm).
    static let core: UInt32 = 0xFFF4D6
    static func stops(_ e: KeyEffect) -> [(pos: Double, alpha: Double)] {
        switch e {
        case .lantern: return [(0, 1), (0.28, 0.9), (0.6, 0.35), (1, 0)]
        default: return [(0, 0.5), (0.45, 0.32), (1, 0)]      // sương: mờ, mép tan
        }
    }
}

/// "Rung dây" (theme Ghi-ta, 10/2026): bấm phím ⇒ đoạn DÂY ngang ở khe hàng gần phím nhất (trên hoặc dưới) rung
/// sóng dừng tắt dần ~0.3 s rồi đứng yên. Hàm thuần — Android StringPluck y hệt (test số chung).
/// - Hình: đoạn dài L (theo bề ngang phím, kẹp 44…150) — path dựng cho chiều dài chuẩn `unitLength`, layer co giãn
///   NGANG (transform) ⇒ một bộ khung hình (path keyframes) cho mọi phím, render server nội suy (GPU).
/// - Biên độ khung f: A·cos(2π·cycles·t/T)·e^(−t/τ) (t = f/frames·T), khung cuối = 0 (dây đứng yên); dạng dây
///   = sin(πx) (bụng giữa, hai đầu cố định).
/// - Độ dày theo khe (dây dưới dày hơn) = KeyboardDecoration.stringThickness.
enum StringPluck {
    static let duration = 0.3
    static let frames = 18
    static let amplitude = 3.0
    static let cycles = 4.0
    static let decay = 0.09
    static let unitLength = 100.0
    static let points = 16
    static let lengthFactor = 2.2
    static let minLength = 44.0, maxLength = 150.0
    /// Số đoạn dây rung cùng lúc (pool xoay vòng) — gõ nhanh hơn thì đoạn cũ nhất bị bắn lại.
    static let pool = 4
    /// Dọn sau lần gảy cuối: hết animation + chút dư.
    static let sweepSlack = 0.05
    /// Còn bao lâu nữa mới dọn (≤ 0 ⇒ dọn ngay) — thuần, test được.
    static func sweepDelay(sinceLastPluck dt: Double) -> Double { duration + sweepSlack - dt }
    /// Không có khe (một hàng): dây nằm dưới phím cách mép này.
    static let fallbackOffset = 4.0

    static func length(keyWidth w: Double) -> Double { min(max(w * lengthFactor, minLength), maxLength) }

    /// Biên độ (pt) ở khung `f` (0…frames).
    static func amplitude(frame f: Int) -> Double {
        guard f > 0, f < frames else { return f == 0 ? amplitude : 0 }
        let t = Double(f) / Double(frames) * duration
        return amplitude * cos(2 * Double.pi * cycles * t / duration) * exp(-t / decay)
    }

    /// Điểm của dây ở khung `f` (đơn vị pt, chiều dài `unitLength`, tâm tại gốc): x −L/2…L/2, y = a·sin(πu).
    static func shape(frame f: Int) -> [(x: Double, y: Double)] {
        let a = amplitude(frame: f)
        return (0...points).map { i in
            let u = Double(i) / Double(points)
            return (x: (u - 0.5) * unitLength, y: a * sin(Double.pi * u))
        }
    }

    /// Khe chứa dây gần phím nhất: (tâm y, chỉ số khe từ trên xuống). Không có khe ⇒ ngay dưới phím, chỉ số 0.
    static func target(keyTop: Double, keyBottom: Double, gaps: [KeyboardDecoration.Gap]) -> (y: Double, index: Int) {
        let mid = (keyTop + keyBottom) / 2
        var best: (y: Double, index: Int)?
        var bestD = Double.infinity
        for (i, g) in gaps.enumerated() {
            let d = abs(g.center - mid)
            // Hoà (phím giữa hai khe) ⇒ khe DƯỚI (dây trầm hơn).
            if d < bestD - 1e-9 || (abs(d - bestD) <= 1e-9 && g.center > (best?.y ?? -Double.infinity)) {
                bestD = d; best = (g.center, i)
            }
        }
        return best ?? (keyBottom + fallbackOffset, 0)
    }
}

/// Cổng Plus: hiệu ứng đi cùng quyền theme cao cấp (như ảnh nền / tuỳ chỉnh nâng cao).
enum KeyEffectGate {
    static var allows: Bool { PlusGate.isUnlocked(.premiumThemes) }
    static func allows(_ e: KeyEffect) -> Bool { !e.isPlus || allows }
}

/// Kiểu thực chạy — hàm thuần (test): tắt / hết Plus / tiết kiệm pin ⇒ Không.
enum KeyEffectPolicy {
    /// Giảm chuyển động KHÔNG tắt hiệu ứng (Phil 19/10/2026: người bật Giảm chuyển động vẫn muốn
    /// thấy hiệu ứng mình đã chọn) — chỉ hết Plus / nguồn điện thấp.
    static func active(setting: KeyEffect, plus: Bool, lowPower: Bool) -> KeyEffect {
        guard setting != .none, plus, !lowPower else { return .none }
        return setting
    }

    /// Đọc lúc hiện bàn phím (applyAppearance) — không mỗi phím. Cài đặt "Không" ⇒ không hỏi gì thêm.
    static func current(_ d: UserDefaults?) -> KeyEffect {
        let s = KeyEffect.load(d)
        guard s != .none else { return .none }
        return active(setting: s, plus: KeyEffectGate.allows(s),
                      lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }
}

/// Cấp ô pool xoay vòng: đủ `cap` hạt đang bay thì hạt cũ nhất bị thay (gõ nhanh không dồn hạt).
struct KeyEffectPool {
    static let cap = 20
    let capacity: Int
    private(set) var cursor = 0
    init(capacity: Int = KeyEffectPool.cap) { self.capacity = max(1, capacity) }
    mutating func next() -> Int {
        let i = cursor
        cursor = (cursor + 1) % capacity
        return i
    }
}

// MARK: - Hàm thuần dùng chung hai nền tảng (Android: KeyEffect.kt cùng số)

/// LCG 32-bit tất định — Kotlin dùng Int 32-bit tràn số y hệt (cùng chuỗi số).
struct FxRandom {
    private(set) var state: UInt32
    init(seed: Int) { state = UInt32(truncatingIfNeeded: seed) &* 2_654_435_761 &+ 1 }
    /// 0…1.
    mutating func next() -> Double {
        state = state &* 1_103_515_245 &+ 12345
        return Double((state >> 8) & 0xFFFF) / 65535
    }
}

/// "Nháy sáng": MỘT lớp phủ cả bàn phím nháy độ mờ. Dịu mắt (chống nhạy cảm ánh sáng): đỉnh thấp,
/// chỉ tắt dần (không bật–tắt gắt), trần nhịp ≥ 60 ms giữa hai lần nháy; gõ nhanh hơn ⇒ bỏ qua (lần nháy
/// đang chạy tiếp tục, không chồng).
struct FlashPulse {
    static let peak = 0.25
    static let duration = 0.12
    static let minInterval = 0.06
    private(set) var last = -Double.greatestFiniteMagnitude
    private(set) var fired = 0

    /// true ⇒ phát lại xung lúc `t` (giây).
    mutating func trigger(at t: Double) -> Bool {
        guard t - last >= Self.minInterval else { return false }
        last = t
        fired += 1
        return true
    }

    /// Độ mờ sau `dt` giây kể từ lúc nháy: tắt dần (1−x)².
    static func alpha(_ dt: Double) -> Double {
        guard dt >= 0, dt < duration else { return 0 }
        let x = 1 - dt / duration
        return peak * x * x
    }
}

/// "Tia sét": đường gấp khúc tất định từ đỉnh bàn phím xuống tâm phím (gốc toạ độ = tâm phím).
enum LightningBolt {
    static let segments = 7
    static let variants = 6
    static let duration = 0.18

    /// `segments + 1` điểm (x, y) — điểm đầu ở y = −height (đỉnh), điểm cuối (0, 0).
    static func points(height: Double, variant: Int) -> [(x: Double, y: Double)] {
        var r = FxRandom(seed: variant &* 7919 &+ 17)
        let h = max(height, 1)
        let amp = min(14, h * 0.12)
        let sx = (r.next() - 0.5) * min(40, h * 0.4)
        var out: [(x: Double, y: Double)] = [(sx, -h)]
        out.reserveCapacity(segments + 1)
        for i in 1..<segments {
            let f = Double(i) / Double(segments)
            let off = (r.next() - 0.5) * 2 * amp * sin(f * .pi)
            out.append((sx * (1 - f) + off, -h * (1 - f)))
        }
        out.append((0, 0))
        return out
    }
}

/// "Tia sét": phím "vỡ" thành `count` mảnh (quạt từ tâm, theo góc cố định) — CHỈ là lớp phủ trên phím;
/// phím thật không bị đụng tới.
enum LightningShards {
    static let count = 5
    static let flight = 18.0
    static let duration = 0.32
    /// Góc ranh giới mảnh (radian, tăng dần, cách đều + lệch cố định).
    static let angles: [Double] = {
        let jitter = [0, 0.25, -0.2, 0.15, -0.1]
        return (0..<count).map { -Double.pi / 2 + 0.3 + Double($0) * 2 * .pi / Double(count) + jitter[$0] }
    }()

    struct Piece {
        /// Đa giác quanh tâm phím (gốc 0,0).
        var points: [(x: Double, y: Double)]
        var centroid: (x: Double, y: Double)
        var area: Double
    }

    /// Hướng bay của mảnh i (vector đơn vị theo góc giữa) — không phụ thuộc cỡ phím (animation gắn sẵn).
    static func direction(_ i: Int) -> (x: Double, y: Double) {
        let a0 = angles[i], a1 = i + 1 < count ? angles[i + 1] : angles[0] + 2 * .pi
        let m = (a0 + a1) / 2
        return (cos(m), sin(m))
    }
    static func rotation(_ i: Int) -> Double { i % 2 == 0 ? 0.5 : -0.45 }

    static func pieces(width w: Double, height h: Double) -> [Piece] {
        let hw = max(w, 1) / 2, hh = max(h, 1) / 2
        func edge(_ a: Double) -> (x: Double, y: Double) {
            let c = cos(a), s = sin(a)
            let t = min(abs(c) > 1e-9 ? hw / abs(c) : .greatestFiniteMagnitude,
                        abs(s) > 1e-9 ? hh / abs(s) : .greatestFiniteMagnitude)
            return (c * t, s * t)
        }
        let a0 = angles[0]
        // Góc 4 góc phím, đưa về [a0, a0 + 2π).
        let corners: [(a: Double, p: (x: Double, y: Double))] = [(hw, hh), (-hw, hh), (-hw, -hh), (hw, -hh)].map { c in
            var a = atan2(c.1, c.0)
            while a < a0 { a += 2 * .pi }
            while a >= a0 + 2 * .pi { a -= 2 * .pi }
            return (a, (c.0, c.1))
        }.sorted { $0.a < $1.a }
        var out: [Piece] = []
        for i in 0..<count {
            let s = angles[i], e = i + 1 < count ? angles[i + 1] : a0 + 2 * .pi
            var pts: [(x: Double, y: Double)] = [(0, 0), edge(s)]
            for c in corners where c.a > s && c.a < e { pts.append(c.p) }
            pts.append(edge(e))
            // Diện tích + trọng tâm (shoelace).
            var a2 = 0.0, cx = 0.0, cy = 0.0
            for k in 0..<pts.count {
                let p = pts[k], q = pts[(k + 1) % pts.count]
                let cr = p.x * q.y - q.x * p.y
                a2 += cr; cx += (p.x + q.x) * cr; cy += (p.y + q.y) * cr
            }
            let area = a2 / 2
            let cen = abs(area) > 1e-9 ? (cx / (6 * area), cy / (6 * area)) : (0.0, 0.0)
            out.append(Piece(points: pts, centroid: cen, area: abs(area)))
        }
        return out
    }
}

/// "Lửa combo": mức combo theo tốc độ gõ (số phím trong ~2 s gần nhất), nguội sau ~1 s không gõ.
/// Mức 0 = không lửa; 1…3 = số ngọn lửa + cỡ lớn dần. Mảng vòng cấp sẵn (không cấp phát mỗi phím).
struct ComboMeter {
    static let window = 2.0
    static let cooldown = 1.0
    /// Số phím trong `window` để lên mức 1/2/3 (≈ 3 / 5 / 7 phím mỗi giây).
    static let thresholds = [6, 10, 14]
    /// Cỡ ngọn lửa theo mức.
    static let scales: [Double] = [0, 0.8, 1.05, 1.35]
    static let capacity = 16
    private var times = [Double](repeating: -Double.greatestFiniteMagnitude, count: ComboMeter.capacity)
    private var head = 0
    private var last = -Double.greatestFiniteMagnitude

    /// Ghi một phím lúc `t` (giây) — trả mức sau phím đó.
    mutating func press(at t: Double) -> Int {
        if t - last > Self.cooldown { reset() }
        last = t
        times[head] = t
        head = (head + 1) % Self.capacity
        return level(at: t)
    }

    func level(at t: Double) -> Int {
        guard t - last <= Self.cooldown else { return 0 }
        var n = 0
        for x in times where x <= t && t - x <= Self.window { n += 1 }
        var lv = 0
        for th in Self.thresholds where n >= th { lv += 1 }
        return lv
    }

    mutating func reset() {
        for i in 0..<Self.capacity { times[i] = -Double.greatestFiniteMagnitude }
        head = 0
    }
}

/// "Sóng nước": số vòng mỗi lần bấm + nhịp lệch giữa các vòng.
enum WaveRings {
    static let rings = 3
    static let stagger = 0.2
    static let duration = 1.2
    static let radius = 18.0
    static let scaleTo = 5.5
}

/// "Mực loang".
enum InkBloom {
    static let size = 48.0
    static let scaleFrom = 0.25, scaleTo = 3.2
    static let peakAlpha = 0.45
    static let duration = 1.0
}

/// "Matrix": cột chữ xanh rơi — ảnh dải cột dựng MỘT lần, chỉ animate vị trí (GPU).
/// "Sao băng" (theme Vũ trụ): MỘT hạt vector — vệt thon (đuôi dài phía sau, đầu tròn sáng) đặt sẵn theo góc
/// bay, lao chéo từ tâm phím rồi tắt. Không xoay, không ảnh ⇒ dùng chung đường hạt (pool, CA / RenderThread).
/// Android MeteorStreak y hệt (test số chung).
enum MeteorStreak {
    /// Hướng bay (rad, y xuống): lên-phải ≈ −35°.
    static let angle = -0.61
    static let distance = 56.0
    static let duration = 0.5
    static let length = 26.0, headRadius = 2.4, arcSteps = 6
    /// Vàng ấm như sao băng (theme sáng có viền mảnh để thấy trên phím sáng).
    static let color: UInt32 = 0xFFE7A0
    static let edge: UInt32 = 0xB07A1A

    /// Hình giọt (pt, tâm đầu tại gốc): nửa vòng đầu tròn phía trước (arcSteps đoạn) rồi mũi đuôi dài phía sau —
    /// MỘT đa giác (không chồng hình ⇒ tô không thủng).
    static func polygon() -> [(x: Double, y: Double)] {
        var out: [(x: Double, y: Double)] = []
        for k in 0...arcSteps {
            let phi = angle + .pi / 2 - Double(k) * .pi / Double(arcSteps)
            out.append((headRadius * cos(phi), headRadius * sin(phi)))
        }
        out.append((-cos(angle) * length, -sin(angle) * length))
        return out
    }
}

enum MatrixRain {
    static let green: UInt32 = 0x00FF41
    static let head: UInt32 = 0xD8FFE0
    static let glyphs = Array("ABCDEFGHJKLMNPQRSTUVXYZ0123456789ăâđêôơưĂÂĐÊÔƠƯ")
    static let rows = 18
    static let stripCount = 4
    static let glyphSize = 13.0
    static let lineHeight = 15.0
    static let columnWidth = 14.0
    static let spacing = 18.0
    static let idleAfter = 2.5
    static let fadeOut = 0.4
    static var stripHeight: Double { Double(rows) * lineHeight }

    static func columnCount(width: Double) -> Int { min(28, max(1, Int(width / spacing))) }

    /// Thông số cột i (tất định): dải ảnh, thời gian rơi (giây), pha (0…1), lệch ngang (pt).
    static func column(_ i: Int) -> (strip: Int, duration: Double, phase: Double, jitter: Double) {
        var r = FxRandom(seed: i &* 31 &+ 7)
        return (i % stripCount, 1.3 + r.next() * 1.2, r.next(), (r.next() - 0.5) * 4)
    }

    /// Ký tự hàng `row` của dải `strip`.
    static func glyph(strip: Int, row: Int) -> Character {
        var r = FxRandom(seed: strip &* 101 &+ row &* 7 &+ 3)
        return glyphs[Int(r.next() * Double(glyphs.count - 1))]
    }

    /// Độ đậm hàng (0 = trên cùng — đuôi mờ; rows−1 = đầu sáng).
    static func rowAlpha(_ row: Int) -> Double {
        let f = Double(row) / Double(max(rows - 1, 1))
        return 0.08 + 0.92 * pow(f, 1.6)
    }

    /// Độ mờ tối đa — theme sáng dịu hơn.
    static func maxOpacity(dark: Bool) -> Double { dark ? 0.85 : 0.5 }
    /// Mạnh dần theo số phím liên tiếp (bắt đầu 55%).
    static func intensity(presses n: Int) -> Double { min(1, 0.55 + 0.15 * Double(max(n - 1, 0))) }
}

/// Đồng hồ chạy/dừng của Matrix: chạy khi gõ, hết ~2,5 s không gõ ⇒ mờ dần rồi dừng hẳn (0 animation).
struct MatrixClock {
    var idleAfter = MatrixRain.idleAfter
    private(set) var lastInput = -Double.greatestFiniteMagnitude
    private(set) var running = false
    private(set) var presses = 0

    /// Một phím lúc `t` — true nếu vừa khởi động (trước đó đứng yên).
    mutating func poke(at t: Double) -> Bool {
        let started = !running
        running = true
        if t - lastInput > idleAfter { presses = 0 }
        presses += 1
        lastInput = t
        return started
    }
    /// Còn bao lâu nữa thì coi là nghỉ (≤ 0 ⇒ dừng được).
    func idleRemaining(at t: Double) -> Double { idleAfter - (t - lastInput) }
    mutating func stop() { running = false; presses = 0 }
}

/// "Emoji theo chữ": bảng nhỏ dựng sẵn, tra O(1) ở RANH GIỚI TỪ bằng từ vừa chốt (không làm gì mỗi chữ).
/// Không phân biệt dấu (trừ mục `strict` dễ nhầm nghĩa, vd "ngủ" ≠ "ngu"); từ tục / cặp tục ⇒ không emoji.
enum EmojiWords {
    /// (dạng, emoji, strict) — strict: chỉ khớp đúng dấu.
    static let entries: [(String, String, Bool)] = [
        ("haha", "😂", false), ("hihi", "😂", false), ("hehe", "😂", false), ("kkk", "😂", false),
        ("kaka", "😂", false), ("lol", "😂", false), ("lmao", "😂", false), ("hài", "😂", true),
        ("yêu", "❤️", false), ("thương", "❤️", false), ("love", "❤️", false), ("iu", "❤️", false),
        ("chúc mừng", "🎉", false), ("congrats", "🎉", false), ("congratulations", "🎉", false),
        ("hpbd", "🎉", false), ("sinh nhật", "🎉", false), ("party", "🎉", false),
        ("buồn", "😢", false), ("sad", "😢", false), ("khóc", "😢", true), ("huhu", "😢", false), ("hic", "😢", false),
        ("ok", "👌", false), ("oke", "👌", false), ("okay", "👌", false), ("okie", "👌", false), ("okela", "👌", false),
        ("cảm ơn", "🙏", false), ("cám ơn", "🙏", false), ("thanks", "🙏", false), ("thank", "🙏", false),
        ("thx", "🙏", false), ("tks", "🙏", false),
        ("ngủ", "😴", true), ("ngủ ngon", "😴", false), ("buồn ngủ", "😴", false), ("sleep", "😴", false),
        ("tết", "🧧", false), ("năm mới", "🧧", false), ("lì xì", "🧧", false), ("lixi", "🧧", false),
        ("cà phê", "☕", false), ("cafe", "☕", false), ("coffee", "☕", false),
        ("phở", "🍜", true), ("bánh kem", "🎂", false), ("noel", "🎄", false), ("giáng sinh", "🎄", false),
        ("hoa", "🌸", true), ("mưa", "🌧️", true), ("nắng", "☀️", true), ("tuyệt vời", "🤩", false),
        ("xin chào", "👋", false), ("hello", "👋", false), ("bye", "👋", false),
    ]

    /// Chữ thường, bỏ dấu (đ → d).
    static func fold(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: "đ", with: "d")
            .folding(options: .diacriticInsensitive, locale: nil)
    }

    private static let exact: [String: String] = Dictionary(entries.map { ($0.0, $0.1) }, uniquingKeysWith: { a, _ in a })
    private static let folded: [String: String] = Dictionary(entries.filter { !$0.2 }.map { (fold($0.0), $0.1) },
                                                             uniquingKeysWith: { a, _ in a })
    /// Các emoji khác nhau (dựng ảnh trước, ngoài main).
    static var distinctEmojis: [String] { Array(Set(entries.map(\.1))).sorted() }

    private static func clean(_ s: String) -> String {
        s.trimmingCharacters(in: CharacterSet.letters.inverted).lowercased()
    }

    private static func match(_ key: String) -> String? {
        guard !key.isEmpty else { return nil }
        return exact[key] ?? folded[fold(key)]
    }

    /// Emoji cho từ vừa chốt `word` (từ liền trước `prev` — cụm 2 từ ưu tiên). Tục ⇒ nil.
    static func lookup(word: String, prev: String?) -> String? {
        let w = clean(word)
        guard !w.isEmpty, w.count <= 24 else { return nil }
        let p = prev.map(clean)
        if blocked(w, prev: p) { return nil }
        if let p, !p.isEmpty, let e = match(p + " " + w) { return e }
        return match(w)
    }

    /// Lọc từ nhạy cảm (SensitiveWords): từ tục, hoặc cặp tục với từ trước (cả từng từ của cụm).
    static func blocked(_ w: String, prev: String?) -> Bool {
        for part in w.split(separator: " ") where SensitiveWords.set.contains(String(part)) { return true }
        if let prev, SensitiveWords.set.contains(prev) || SensitiveWords.isPair(prev, w) { return true }
        return false
    }
}

// MARK: - Overlay

extension UIView {
    /// Lớp phủ trọn `host` dùng CHUNG hệ toạ độ với host: khung = host.bounds, gốc bounds = gốc bounds
    /// của host. KeyboardView dời gốc bounds lên phần host cấp dư (#151); lớp phủ chỉ đặt frame một lần
    /// (hay dựa autoresizing — không theo gốc) sẽ lệch cả phần dư ⇒ hiệu ứng / ô phóng to vẽ sai chỗ.
    /// Không đổi gì thì không chạm layer.
    func shareCoordinateSpace(with host: UIView) {
        let b = host.bounds
        if frame != b { frame = b }
        if bounds.origin != b.origin { bounds.origin = b.origin }
    }
}

/// Lớp phủ hiệu ứng — một UIView không nhận chạm, phủ trọn KeyboardView.
///
/// Hạt / mực / sóng / emoji: mỗi lần bấm = MỘT "chùm" (CALayer chứa vài layer con). Animation gắn MỘT
/// lần lúc dựng chùm (không bị gỡ, fill cả hai đầu); bấm phím chỉ đặt `position` + `beginTime` của chùm
/// ⇒ cả cây thời gian chạy lại từ đầu trên render server. Tia sét: pool 3 "cú đánh" (path lấy từ cache
/// theo độ cao / cỡ phím). Nháy sáng: MỘT layer. Matrix: các cột ảnh dựng sẵn, animation chỉ gắn khi đang
/// gõ, gỡ sạch sau khi nghỉ.
final class KeyEffectOverlay: UIView {
    private(set) var effect: KeyEffect
    private var color: UIColor
    private var keyFill: UIColor
    private var dark: Bool
    private var bursts: [CALayer] = []
    private var pool = KeyEffectPool(capacity: 1)
    private var paths: [CGPath?] = []
    /// Khung phím chờ vẽ (gõ chồng trong cùng lượt runloop) — giữ tối đa `maxPending` khung mới nhất.
    private var pending: [CGRect] = []
    private static let maxPending = 4
    private var scheduled = false
    /// beginTime cục bộ của animation (> 0: CA không tự gán "bây giờ" lúc thêm).
    private static let animBegin: CFTimeInterval = 1e-3
    /// Cỡ phím mặc định khi chỉ có điểm (emit(at:)).
    static let defaultKeySize = CGSize(width: 34, height: 42)

    // Nháy sáng
    private var flashLayer: CALayer?
    private var flashPulse = FlashPulse()
    // Tia sét
    private var strikes: [Strike] = []
    private var strikePool = KeyEffectPool(capacity: Strike.cap)
    private var strikeSeq = 0
    private var boltCache: [Int: CGPath] = [:]
    private var keyShapeCache: [Int: KeyShapes] = [:]
    // Lửa combo
    private var combo = ComboMeter()
    // Emoji theo chữ
    private var pendingEmoji: String?
    private var emojiImages: [String: CGImage] = [:]
    // Mực loang
    private var blob: CGImage?
    // Đèn lồng / Sương ma — một ảnh mỗi màu cố định
    private var glows: [CGImage] = []
    // Rung dây — pool đoạn dây; animation (khung path + mờ) dựng MỘT lần, gắn mỗi lần gảy và TỰ GỠ khi xong
    // (isRemovedOnCompletion) ⇒ nghỉ gõ = 0 animation trên cây layer.
    /// Khe hàng phím (toạ độ overlay) — KeyboardView đặt lúc layout, chỉ khi kiểu là Rung dây.
    var stringGaps: [KeyboardDecoration.Gap] = []
    private var strings: [CAShapeLayer] = []
    private var stringPool = KeyEffectPool(capacity: StringPluck.pool)
    private var stringAnim: CAAnimationGroup?
    /// Lần gảy cuối (giây máy) + đã hẹn dọn chưa: MỘT asyncAfter cho cả loạt gõ — nghỉ ⇒ gỡ chắc chắn mọi animation
    /// (kể cả khi render server chưa kịp tự gỡ), không timer lặp.
    private var stringLastFire: CFTimeInterval = 0
    private var stringSweepScheduled = false
    // Matrix
    private var matrixRoot: CALayer?
    private var matrixColumns: [CALayer] = []
    private var matrixStrips: [CGImage] = []
    private var matrixClock = MatrixClock()
    private var matrixIdleScheduled = false
    private var matrixFading = false
    private var matrixGen = 0
    private var matrixBuiltFor: CGSize = .zero

    init(effect: KeyEffect, color: UIColor, keyFill: UIColor = .white, dark: Bool = false) {
        self.effect = effect
        self.color = color
        self.keyFill = keyFill
        self.dark = dark
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        backgroundColor = .clear
        isOpaque = false
        pending.reserveCapacity(Self.maxPending)
        applyBand()
        rebuild()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { false }

    /// Gắn / cập nhật / gỡ overlay của `host`. Kiểu "Không" ⇒ gỡ và trả nil (0 chi phí).
    /// `keys`: view chứa phím — dải DƯỚI phím chèn ngay dưới nó (trên nền / ảnh nền).
    static func install(_ effect: KeyEffect, color: UIColor, keyFill: UIColor = .white, dark: Bool = false,
                        in host: UIView, keys: UIView? = nil, existing: KeyEffectOverlay?) -> KeyEffectOverlay? {
        guard effect != .none else {
            existing?.halt()
            existing?.removeFromSuperview()
            return nil
        }
        let o = existing ?? KeyEffectOverlay(effect: effect, color: color, keyFill: keyFill, dark: dark)
        o.configure(effect: effect, color: color, keyFill: keyFill, dark: dark)
        let below = effect.band == .belowKeys
        let placed: Bool = {
            guard o.superview === host else { return false }
            guard let keys, keys.superview === host,
                  let i = host.subviews.firstIndex(of: o), let k = host.subviews.firstIndex(of: keys) else { return true }
            return below ? i < k : i > k
        }()
        if !placed {
            o.removeFromSuperview()
            match(o, to: host)
            if below, let keys, keys.superview === host {
                host.insertSubview(o, belowSubview: keys)
            } else {
                host.addSubview(o)
            }
        }
        return o
    }

    /// Đặt overlay trùng hệ toạ độ của `host` (khung = host.bounds, cùng gốc bounds) ⇒ toạ độ host
    /// dùng thẳng trong overlay dù host dời gốc bounds. Không đổi gì thì không chạm layer.
    static func match(_ o: KeyEffectOverlay, to host: UIView) { o.shareCoordinateSpace(with: host) }

    func configure(effect: KeyEffect, color: UIColor, keyFill: UIColor? = nil, dark: Bool? = nil) {
        let kf = keyFill ?? self.keyFill, dk = dark ?? self.dark
        guard effect != self.effect || !color.isEqual(self.color) || !kf.isEqual(self.keyFill) || dk != self.dark
        else { return }
        if effect != self.effect { halt() }
        self.effect = effect
        self.color = color
        self.keyFill = kf
        self.dark = dk
        applyBand()
        rebuild()
    }

    private func applyBand() {
        // Trên phím (zPosition 0), dưới ô phóng to (BalloonView 10) và popup (11). Dải dưới phím: 0 +
        // thứ tự subview (ngay dưới hàng phím, trên nền / ảnh nền).
        layer.zPosition = effect.band == .belowKeys ? 0 : 5
        clipsToBounds = effect.band == .belowKeys || effect == .flash
    }

    /// "Emoji theo chữ": controller tra bảng ở ranh giới từ (sau khi chốt) rồi xếp emoji — lần vẽ kế
    /// (cùng phím ranh giới) bắn nó.
    func queueEmoji(_ e: String) {
        guard effect == .emojiword else { return }
        pendingEmoji = e
    }

    /// Ghi điểm (toạ độ overlay) — vẽ ở lượt runloop kế, SAU khi phím đã chèn chữ.
    func emit(at p: CGPoint) { emit(key: CGRect(origin: p, size: .zero)) }

    /// Ghi khung phím (toạ độ overlay) — vẽ ở lượt runloop kế, SAU khi phím đã chèn chữ.
    func emit(key r: CGRect) {
        #if DEBUG
        let t0 = CACurrentMediaTime()
        defer { Self.debugCost += CACurrentMediaTime() - t0 }
        #endif
        if effect == .emojiword && pendingEmoji == nil { return }   // không có emoji ⇒ không hẹn gì
        if pending.count >= Self.maxPending { pending.removeFirst() }
        pending.append(r)
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.async { [weak self] in self?.flush() }
    }

    /// Vẽ các khung đang chờ (test gọi thẳng).
    func flush() {
        #if DEBUG
        let t0 = CACurrentMediaTime()
        defer { Self.debugCost += CACurrentMediaTime() - t0 }
        #endif
        scheduled = false
        guard !pending.isEmpty, effect != .none, window != nil || Self.drawsOffscreen else {
            pending.removeAll(keepingCapacity: true)
            pendingEmoji = nil
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let media = CACurrentMediaTime()
        let now = layer.convertTime(media, from: nil)
        if effect == .emojiword {
            if let e = pendingEmoji, let r = pending.last { fireEmoji(e, at: r, now: now) }
            pendingEmoji = nil
        } else {
            for r in pending { fire(r, now: now, media: media) }
        }
        CATransaction.commit()
        pending.removeAll(keepingCapacity: true)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        flashLayer?.frame = bounds
        matrixRoot?.frame = bounds
        CATransaction.commit()
        if effect == .matrix, matrixClock.running, bounds.size != matrixBuiltFor { restartMatrixColumns() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Bàn phím ẩn ⇒ Matrix dừng hẳn (không còn animation nào).
        if window == nil { halt() }
    }

    #if DEBUG
    /// Test: vẽ cả khi chưa gắn vào window (test không có window thật).
    nonisolated(unsafe) static var drawsOffscreen = false
    /// Đo: tổng thời gian main thread trong emit + flush (giây) — bench cộng dồn mỗi phím.
    nonisolated(unsafe) static var debugCost: CFTimeInterval = 0
    /// Số chùm đã dựng / tổng số layer hạt đang có.
    var debugBurstCount: Int { bursts.count }
    var debugParticleCount: Int { bursts.reduce(0) { $0 + ($1.sublayers?.count ?? 0) } }
    var debugPendingCount: Int { pending.count }
    var debugScheduled: Bool { scheduled }
    /// Vị trí các chùm đã bắn (toạ độ overlay).
    var debugBurstPositions: [CGPoint] { bursts.map(\.position) }
    var debugBursts: [CALayer] { bursts }
    var debugFlashLayer: CALayer? { flashLayer }
    var debugFlashFired: Int { flashPulse.fired }
    var debugStrikeCount: Int { strikes.count }
    var debugStrikeRoots: [CALayer] { strikes.map(\.root) }
    var debugMatrixRunning: Bool { matrixClock.running }
    var debugMatrixRoot: CALayer? { matrixRoot }
    var debugMatrixStripsReady: Bool { !matrixStrips.isEmpty }
    /// Số animation còn gắn trên cây Matrix (0 khi nghỉ).
    var debugMatrixAnimationCount: Int {
        guard let r = matrixRoot else { return 0 }
        return (r.animationKeys()?.count ?? 0) + matrixColumns.reduce(0) { $0 + ($1.animationKeys()?.count ?? 0) }
    }
    func debugSetMatrixIdle(_ s: Double) { matrixClock.idleAfter = s }
    var debugEmojiCacheCount: Int { emojiImages.count }
    /// Số ảnh đốm sáng dựng sẵn (Đèn lồng / Sương ma — mỗi màu một ảnh).
    var debugGlowCount: Int { glows.count }
    /// Rung dây: các đoạn dây đã dựng (pool) + số animation đang gắn trên chúng.
    var debugStringLayers: [CAShapeLayer] { strings }
    var debugStringAnimationCount: Int { strings.reduce(0) { $0 + ($1.animationKeys()?.count ?? 0) } }
    var debugStringAnimation: CAAnimationGroup { stringAnimation() }
    #else
    static let drawsOffscreen = false
    #endif

    // MARK: bắn

    private func fire(_ r: CGRect, now: CFTimeInterval, media: CFTimeInterval) {
        let c = CGPoint(x: r.midX, y: r.midY)
        switch effect {
        case .none, .emojiword: return
        case .flash: fireFlash(now: now, media: media)
        case .lightning: fireLightning(r, now: now)
        case .matrix: pokeMatrix(media: media)
        case .string: fireString(r)
        case .combo:
            let lv = combo.press(at: media)
            guard lv > 0 else { return }
            let b = nextBurst()
            let s = CGFloat(ComboMeter.scales[min(lv, 3)])
            b.transform = CATransform3DMakeScale(s, s, 1)
            for (i, l) in (b.sublayers ?? []).enumerated() { l.isHidden = i >= lv }
            launch(b, at: c, now: now)
        default:
            launch(nextBurst(), at: c, now: now)
        }
    }

    private func nextBurst() -> CALayer {
        let slot = pool.next()
        return slot < bursts.count ? bursts[slot] : makeBurst(index: slot)
    }

    private func launch(_ b: CALayer, at p: CGPoint, now: CFTimeInterval) {
        b.position = p
        b.beginTime = now      // chạy lại animation cả chùm từ đầu (thời gian cục bộ = 0)
        b.isHidden = false
    }

    private func fireEmoji(_ e: String, at r: CGRect, now: CFTimeInterval) {
        guard let img = emojiImage(e) else { return }
        let b = nextBurst()
        b.sublayers?.first?.contents = img
        launch(b, at: CGPoint(x: r.midX, y: r.midY), now: now)
    }

    private func fireFlash(now: CFTimeInterval, media: CFTimeInterval) {
        guard flashPulse.trigger(at: media) else { return }     // trần nhịp: không chồng, không nháy gắt
        let l: CALayer
        if let f = flashLayer { l = f } else {
            l = CALayer()
            l.frame = bounds
            l.backgroundColor = color.cgColor
            l.opacity = 0
            let a = CAKeyframeAnimation(keyPath: "opacity")
            let steps = 6
            a.values = (0...steps).map { FlashPulse.alpha(FlashPulse.duration * Double($0) / Double(steps)) }
            a.keyTimes = (0...steps).map { NSNumber(value: Double($0) / Double(steps)) }
            a.duration = FlashPulse.duration
            a.beginTime = Self.animBegin
            a.fillMode = .both
            a.isRemovedOnCompletion = false
            l.add(a, forKey: "fx")
            layer.addSublayer(l)
            flashLayer = l
        }
        l.beginTime = now
    }

    // MARK: Rung dây

    private func fireString(_ r: CGRect) {
        let slot = stringPool.next()
        let l: CAShapeLayer
        if slot < strings.count { l = strings[slot] } else { l = makeStringLayer(); strings.append(l) }
        let size = r.size == .zero ? Self.defaultKeySize : r.size
        let top = r.size == .zero ? r.midY - size.height / 2 : r.minY
        let t = StringPluck.target(keyTop: Double(top), keyBottom: Double(top + size.height), gaps: stringGaps)
        let len = StringPluck.length(keyWidth: Double(size.width))
        l.position = CGPoint(x: r.midX, y: CGFloat(t.y))
        l.transform = CATransform3DMakeScale(CGFloat(len / StringPluck.unitLength), 1, 1)
        l.lineWidth = CGFloat(KeyboardDecoration.stringThickness(t.index) + 0.4)
        l.add(stringAnimation(), forKey: "fx")      // gảy lại cùng đoạn ⇒ thay animation cũ
        stringLastFire = CACurrentMediaTime()
        scheduleStringSweep(after: StringPluck.duration + StringPluck.sweepSlack)
    }

    private func scheduleStringSweep(after s: Double) {
        guard !stringSweepScheduled else { return }
        stringSweepScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + s) { [weak self] in self?.sweepStrings() }
    }

    private func sweepStrings() {
        stringSweepScheduled = false
        let left = StringPluck.sweepDelay(sinceLastPluck: CACurrentMediaTime() - stringLastFire)
        if left > 0 { scheduleStringSweep(after: left); return }
        for l in strings { l.removeAnimation(forKey: "fx") }
    }

    private func makeStringLayer() -> CAShapeLayer {
        let l = CAShapeLayer()
        l.bounds = .zero
        l.path = Self.stringPath(frame: StringPluck.frames)
        l.fillColor = nil
        l.strokeColor = color.cgColor
        l.lineCap = .round
        l.lineJoin = .round
        l.opacity = 0                 // mô hình vô hình: animation xong (tự gỡ) ⇒ không còn gì vẽ
        l.actions = ["position": NSNull(), "transform": NSNull(), "lineWidth": NSNull()]
        layer.addSublayer(l)
        return l
    }

    private static func stringPath(frame f: Int) -> CGPath {
        let p = CGMutablePath()
        for (i, q) in StringPluck.shape(frame: f).enumerated() {
            let pt = CGPoint(x: q.x, y: q.y)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }

    /// Khung path sóng dừng + mờ dần — dựng một lần (CA chép khi gắn). Tự gỡ khi xong.
    private func stringAnimation() -> CAAnimationGroup {
        if let a = stringAnim { return a }
        let wave = CAKeyframeAnimation(keyPath: "path")
        wave.values = (0...StringPluck.frames).map { Self.stringPath(frame: $0) }
        wave.calculationMode = .linear
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 1, 0]; fade.keyTimes = [0, 0.7, 1]
        let g = CAAnimationGroup()
        g.animations = [wave, fade]
        g.duration = StringPluck.duration
        wave.duration = StringPluck.duration; fade.duration = StringPluck.duration
        g.fillMode = .removed
        g.isRemovedOnCompletion = true
        stringAnim = g
        return g
    }

    // MARK: Tia sét

    /// Một cú đánh: tia (quầng + lõi) + ánh chớp trên phím + các mảnh vỡ. Animation gắn một lần.
    private final class Strike {
        static let cap = 3
        let root = CALayer()
        let glowBolt = CAShapeLayer()
        let core = CAShapeLayer()
        let glow = CAShapeLayer()
        var shards: [CAShapeLayer] = []
    }

    private struct KeyShapes {
        var glow: CGPath
        var shards: [(path: CGPath, centroid: CGPoint)]
    }

    private func fireLightning(_ r: CGRect, now: CFTimeInterval) {
        let slot = strikePool.next()
        let s = slot < strikes.count ? strikes[slot] : makeStrike()
        strikeSeq += 1
        let size = r.size == .zero ? Self.defaultKeySize : r.size
        let center = CGPoint(x: r.midX, y: r.midY)
        let bolt = boltPath(height: center.y, variant: strikeSeq % LightningBolt.variants)
        let shapes = keyShapes(size)
        s.glowBolt.path = bolt
        s.core.path = bolt
        s.glow.path = shapes.glow
        for (i, l) in s.shards.enumerated() where i < shapes.shards.count {
            l.path = shapes.shards[i].path
            l.position = shapes.shards[i].centroid
        }
        launch(s.root, at: center, now: now)
    }

    private func boltPath(height: CGFloat, variant: Int) -> CGPath {
        let bucket = Int((height / 4).rounded())
        let k = bucket * 8 + variant
        if let p = boltCache[k] { return p }
        if boltCache.count > 64 { boltCache.removeAll() }
        let p = CGMutablePath()
        for (i, pt) in LightningBolt.points(height: Double(bucket) * 4, variant: variant).enumerated() {
            let q = CGPoint(x: pt.x, y: pt.y)
            if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
        }
        boltCache[k] = p
        return p
    }

    private func keyShapes(_ size: CGSize) -> KeyShapes {
        let k = Int(size.width.rounded()) * 4096 + Int(size.height.rounded())
        if let s = keyShapeCache[k] { return s }
        if keyShapeCache.count > 16 { keyShapeCache.removeAll() }
        let glow = CGPath(roundedRect: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height),
                          cornerWidth: 6, cornerHeight: 6, transform: nil)
        let shards = LightningShards.pieces(width: Double(size.width), height: Double(size.height)).map { pc -> (CGPath, CGPoint) in
            let p = CGMutablePath()
            for (i, q) in pc.points.enumerated() {
                let pt = CGPoint(x: q.x - pc.centroid.x, y: q.y - pc.centroid.y)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
            return (p, CGPoint(x: pc.centroid.x, y: pc.centroid.y))
        }
        let s = KeyShapes(glow: glow, shards: shards.map { (path: $0.0, centroid: $0.1) })
        keyShapeCache[k] = s
        return s
    }

    private func makeStrike() -> Strike {
        let s = Strike()
        s.root.bounds = .zero
        s.root.isHidden = true
        let boltFade: (Double) -> CAAnimationGroup = { _ in
            let draw = CABasicAnimation(keyPath: "strokeEnd")
            draw.fromValue = 0; draw.toValue = 1; draw.duration = 0.05
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [1, 1, 0]; fade.keyTimes = [0, 0.35, 1]; fade.duration = LightningBolt.duration
            return Self.group([draw, fade], duration: LightningBolt.duration, delay: 0)
        }
        for (l, w, c) in [(s.glowBolt, CGFloat(5), color.withAlphaComponent(0.45)), (s.core, CGFloat(1.6), UIColor.white)] {
            l.fillColor = nil
            l.strokeColor = c.cgColor
            l.lineWidth = w
            l.lineJoin = .round
            l.lineCap = .round
            l.opacity = 0
            l.add(boltFade(0), forKey: "fx")
            s.root.addSublayer(l)
        }
        // Ánh chớp trắng / viền nhấn trên phím lúc tia chạm.
        s.glow.fillColor = UIColor.white.withAlphaComponent(0.6).cgColor
        s.glow.strokeColor = color.cgColor
        s.glow.lineWidth = 2
        s.glow.opacity = 0
        let gf = CAKeyframeAnimation(keyPath: "opacity")
        gf.values = [0, 1, 0]; gf.keyTimes = [0, 0.25, 1]; gf.duration = 0.22
        s.glow.add(Self.group([gf], duration: 0.22, delay: 0.04), forKey: "fx")
        s.root.addSublayer(s.glow)
        // Mảnh vỡ: màu phím, bay ra + xoay + mờ. Trước lúc chạm: vô hình (fill lùi = giá trị đầu 0).
        for i in 0..<LightningShards.count {
            let l = CAShapeLayer()
            l.fillColor = keyFill.cgColor
            l.strokeColor = UIColor.white.withAlphaComponent(0.35).cgColor
            l.lineWidth = 0.5
            l.opacity = 0
            let d = LightningShards.direction(i)
            let move = CABasicAnimation(keyPath: "position")
            move.isAdditive = true
            move.fromValue = NSValue(cgPoint: .zero)
            move.toValue = NSValue(cgPoint: CGPoint(x: d.x * LightningShards.flight, y: d.y * LightningShards.flight + 8))
            move.timingFunction = CAMediaTimingFunction(name: .easeOut)
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0; spin.toValue = LightningShards.rotation(i)
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 0.9, 0.9, 0]; fade.keyTimes = [0, 0.01, 0.25, 1]
            l.add(Self.group([move, spin, fade], duration: LightningShards.duration, delay: 0.05), forKey: "fx")
            s.root.addSublayer(l)
            s.shards.append(l)
        }
        layer.addSublayer(s.root)
        strikes.append(s)
        return s
    }

    // MARK: Matrix

    private func pokeMatrix(media: CFTimeInterval) {
        let started = matrixClock.poke(at: media)
        let root = matrixRootLayer()
        if matrixFading {           // gõ lại lúc đang mờ dần ⇒ huỷ dừng, chạy tiếp
            matrixFading = false
            matrixGen += 1
            root.removeAnimation(forKey: "fade")
        }
        root.opacity = Float(MatrixRain.maxOpacity(dark: dark) * MatrixRain.intensity(presses: matrixClock.presses))
        if started {
            root.isHidden = false
            restartMatrixColumns()
        }
        if !matrixIdleScheduled { scheduleMatrixIdle(after: matrixClock.idleAfter) }
    }

    private func matrixRootLayer() -> CALayer {
        if let r = matrixRoot { return r }
        let r = CALayer()
        r.frame = bounds
        r.masksToBounds = true
        r.isHidden = true
        r.opacity = 0
        layer.addSublayer(r)
        matrixRoot = r
        return r
    }

    /// Dựng cột theo bề ngang (một lần mỗi cỡ) + gắn animation rơi (chỉ khi đang chạy).
    private func restartMatrixColumns() {
        guard let root = matrixRoot, bounds.width > 0 else { return }
        let n = MatrixRain.columnCount(width: Double(bounds.width))
        if matrixColumns.count != n {
            for c in matrixColumns { c.removeFromSuperlayer() }
            matrixColumns = (0..<n).map { _ in
                let c = CALayer()
                c.contentsScale = UIScreen.main.scale
                root.addSublayer(c)
                return c
            }
        }
        matrixBuiltFor = bounds.size
        let sh = CGFloat(MatrixRain.stripHeight)
        for (i, c) in matrixColumns.enumerated() {
            let p = MatrixRain.column(i)
            c.removeAllAnimations()
            c.bounds = CGRect(x: 0, y: 0, width: MatrixRain.columnWidth, height: sh)
            c.position = CGPoint(x: (CGFloat(i) + 0.5) * CGFloat(MatrixRain.spacing) + CGFloat(p.jitter), y: -sh / 2)
            if !matrixStrips.isEmpty { c.contents = matrixStrips[p.strip % matrixStrips.count] }
            let a = CABasicAnimation(keyPath: "position.y")
            a.fromValue = -sh / 2
            a.toValue = bounds.height + sh / 2
            a.duration = p.duration
            a.timeOffset = p.phase * p.duration
            a.repeatCount = .infinity
            c.add(a, forKey: "rain")
        }
    }

    private func scheduleMatrixIdle(after s: Double) {
        matrixIdleScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + max(s, 0.01)) { [weak self] in self?.checkMatrixIdle() }
    }

    private func checkMatrixIdle() {
        matrixIdleScheduled = false
        guard matrixClock.running, !matrixFading else { return }
        let rem = matrixClock.idleRemaining(at: CACurrentMediaTime())
        if rem > 0.01 { scheduleMatrixIdle(after: rem); return }
        // Nghỉ: mờ dần rồi gỡ hết animation.
        guard let root = matrixRoot else { return }
        matrixFading = true
        matrixGen += 1
        let gen = matrixGen
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = root.presentation()?.opacity ?? root.opacity
        a.toValue = 0
        a.duration = MatrixRain.fadeOut
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.opacity = 0
        root.add(a, forKey: "fade")
        CATransaction.commit()
        DispatchQueue.main.asyncAfter(deadline: .now() + MatrixRain.fadeOut) { [weak self] in
            guard let self, self.matrixGen == gen, self.matrixFading else { return }
            self.haltMatrix()
        }
    }

    /// Dừng hẳn Matrix: gỡ mọi animation, ẩn — render server không còn việc gì.
    private func haltMatrix() {
        matrixFading = false
        matrixGen += 1
        matrixClock.stop()
        guard let root = matrixRoot else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.removeAllAnimations()
        for c in matrixColumns { c.removeAllAnimations() }
        root.opacity = 0
        root.isHidden = true
        CATransaction.commit()
    }

    /// Dừng mọi thứ chạy liên tục (ẩn bàn phím / đổi kiểu / gỡ).
    func halt() {
        haltMatrix()
        pendingEmoji = nil
        for l in strings { l.removeAllAnimations() }
    }

    // MARK: dựng

    /// Một chùm: các layer con, animation gắn sẵn.
    private func makeBurst(index: Int) -> CALayer {
        let b = CALayer()
        b.bounds = .zero
        b.isHidden = true
        switch effect {
        case .ink:
            let l = CALayer()
            l.bounds = CGRect(x: 0, y: 0, width: InkBloom.size, height: InkBloom.size)
            l.contents = blob
            l.position = .zero
            l.opacity = 0
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = InkBloom.scaleFrom; scale.toValue = InkBloom.scaleTo
            scale.timingFunction = CAMediaTimingFunction(name: .easeOut)
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [InkBloom.peakAlpha, InkBloom.peakAlpha * 0.7, 0]; fade.keyTimes = [0, 0.4, 1]
            l.add(Self.group([scale, fade], duration: InkBloom.duration, delay: 0), forKey: "fx")
            b.addSublayer(l)
        case .wave:
            let ring = CGPath(ellipseIn: CGRect(x: -WaveRings.radius, y: -WaveRings.radius,
                                                width: 2 * WaveRings.radius, height: 2 * WaveRings.radius), transform: nil)
            for k in 0..<WaveRings.rings {
                let l = CAShapeLayer()
                l.path = ring
                l.fillColor = nil
                l.strokeColor = color.withAlphaComponent(0.55).cgColor
                l.lineWidth = 0.9
                l.opacity = 0
                let scale = CABasicAnimation(keyPath: "transform.scale")
                scale.fromValue = 0.15; scale.toValue = WaveRings.scaleTo
                scale.timingFunction = CAMediaTimingFunction(name: .easeOut)
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 0.85; fade.toValue = 0
                l.add(Self.group([scale, fade], duration: WaveRings.duration, delay: Double(k) * WaveRings.stagger), forKey: "fx")
                b.addSublayer(l)
            }
        case .emojiword:
            let l = CALayer()
            l.bounds = CGRect(x: 0, y: 0, width: 30, height: 30)
            l.contentsGravity = .resizeAspect
            l.opacity = 0
            let move = CABasicAnimation(keyPath: "position")
            move.isAdditive = true
            move.fromValue = NSValue(cgPoint: .zero)
            move.toValue = NSValue(cgPoint: CGPoint(x: 0, y: -64))
            move.timingFunction = CAMediaTimingFunction(name: .easeOut)
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.6; scale.toValue = 1.15
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [1, 1, 0]; fade.keyTimes = [0, 0.6, 1]
            l.add(Self.group([move, scale, fade], duration: 1.1, delay: 0), forKey: "fx")
            b.addSublayer(l)
        case _ where effect.usesGlow:
            let g = CGFloat(GlowSprite.size)
            for i in 0..<effect.particlesPerTap {
                let l = CALayer()
                l.bounds = CGRect(x: 0, y: 0, width: g, height: g)
                l.contents = glows.isEmpty ? nil : glows[i % glows.count]
                l.position = .zero
                l.opacity = 0
                l.add(Self.makeAnimation(effect.trajectory(effect.variant(particle: i, seed: index + 1))), forKey: "fx")
                b.addSublayer(l)
            }
        default:
            for i in 0..<effect.particlesPerTap {
                let l = CAShapeLayer()
                style(l, particle: i)
                l.position = .zero
                l.opacity = 0
                l.add(Self.makeAnimation(effect.trajectory(effect.variant(particle: i, seed: index + 1))), forKey: "fx")
                b.addSublayer(l)
            }
        }
        layer.addSublayer(b)
        bursts.append(b)
        return b
    }

    private func style(_ l: CAShapeLayer, particle i: Int) {
        l.path = paths.isEmpty ? nil : paths[i % paths.count]
        l.bounds = .zero
        l.contentsScale = UIScreen.main.scale
        let fixed = effect.fixedColors
        let c = fixed.isEmpty ? color : UIColor(rgb: fixed[i % fixed.count])
        switch effect {
        case .bubble:
            l.fillColor = c.withAlphaComponent(0.18).cgColor
            l.strokeColor = c.cgColor
            l.lineWidth = 1.5
        case .ripple:
            l.fillColor = nil
            l.strokeColor = c.withAlphaComponent(0.8).cgColor
            l.lineWidth = 2
        case .meteor:
            l.fillColor = c.cgColor
            l.strokeColor = dark ? nil : UIColor(rgb: MeteorStreak.edge).cgColor
            l.lineWidth = dark ? 0 : 0.6
        case .snow:
            // Trắng; theme sáng: ánh xanh nhẹ + viền để thấy trên phím sáng.
            l.fillColor = (dark ? UIColor.white : UIColor(rgb: 0xDCEBFF)).cgColor
            l.strokeColor = dark ? nil : UIColor(rgb: 0x8FB3E0).cgColor
            l.lineWidth = dark ? 0 : 0.6
        default:
            l.fillColor = c.cgColor
            l.strokeColor = nil
            l.lineWidth = 0
        }
    }

    /// Đổi kiểu / màu (lúc hiện bàn phím): bỏ các chùm cũ, dựng lại lười ở lần bấm kế.
    private func rebuild() {
        paths = (0..<max(effect.particlesPerTap, 1)).map { KeyEffectShapes.path(effect, particle: $0) }
        pool = KeyEffectPool(capacity: effect.burstSlots)
        strikePool = KeyEffectPool(capacity: Strike.cap)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for b in bursts { b.removeFromSuperlayer() }
        for s in strikes { s.root.removeFromSuperlayer() }
        for l in strings { l.removeFromSuperlayer() }
        flashLayer?.removeFromSuperlayer()
        matrixRoot?.removeFromSuperlayer()
        CATransaction.commit()
        bursts.removeAll()
        strikes.removeAll()
        strings.removeAll()
        stringPool = KeyEffectPool(capacity: StringPluck.pool)
        stringAnim = nil
        flashLayer = nil
        matrixRoot = nil
        matrixColumns.removeAll()
        matrixBuiltFor = .zero
        flashPulse = FlashPulse()
        combo.reset()
        boltCache.removeAll()
        keyShapeCache.removeAll()
        blob = effect == .ink ? Self.renderBlob(color: color, scale: UIScreen.main.scale) : nil
        glows = effect.usesGlow
            ? effect.fixedColors.compactMap { Self.renderGlow(effect, rgb: $0, scale: UIScreen.main.scale) } : []
        if effect != .matrix { matrixStrips = [] }
        if effect != .emojiword { emojiImages = [:] }
        prewarm()
    }

    /// Ảnh dựng sẵn NGOÀI main (dải Matrix, emoji) — một lần mỗi lần đổi kiểu.
    private func prewarm() {
        let scale = UIScreen.main.scale
        switch effect {
        case .matrix where matrixStrips.isEmpty:
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let strips = (0..<MatrixRain.stripCount).compactMap { Self.renderStrip($0, scale: scale) }
                DispatchQueue.main.async {
                    guard let self, self.effect == .matrix else { return }
                    self.matrixStrips = strips
                    for (i, c) in self.matrixColumns.enumerated() where !strips.isEmpty {
                        c.contents = strips[MatrixRain.column(i).strip % strips.count]
                    }
                }
            }
        case .emojiword where emojiImages.isEmpty:
            DispatchQueue.global(qos: .utility).async { [weak self] in
                var imgs: [String: CGImage] = [:]
                for e in EmojiWords.distinctEmojis { imgs[e] = Self.renderEmoji(e, scale: scale) }
                DispatchQueue.main.async {
                    guard let self, self.effect == .emojiword else { return }
                    self.emojiImages.merge(imgs) { a, _ in a }
                }
            }
        default: break
        }
    }

    private func emojiImage(_ e: String) -> CGImage? {
        if let i = emojiImages[e] { return i }
        let i = Self.renderEmoji(e, scale: UIScreen.main.scale)   // hiếm: chưa kịp dựng sẵn
        emojiImages[e] = i
        return i
    }

    static func renderEmoji(_ e: String, scale: CGFloat) -> CGImage? {
        let size: CGFloat = 30
        let f = UIGraphicsImageRendererFormat()
        f.scale = scale
        f.opaque = false
        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 24)]
        let s = e as NSString
        let sz = s.size(withAttributes: attrs)
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: f).image { _ in
            s.draw(at: CGPoint(x: (size - sz.width) / 2, y: (size - sz.height) / 2), withAttributes: attrs)
        }.cgImage
    }

    /// Đốm mực tròn mép mềm (gradient tâm) — một lần mỗi màu.
    static func renderBlob(color: UIColor, scale: CGFloat) -> CGImage? {
        let size = CGFloat(InkBloom.size)
        let f = UIGraphicsImageRendererFormat()
        f.scale = scale
        f.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: f).image { ctx in
            let cs = CGColorSpaceCreateDeviceRGB()
            let cols = [color.cgColor, color.withAlphaComponent(0.6).cgColor, color.withAlphaComponent(0).cgColor] as CFArray
            guard let g = CGGradient(colorsSpace: cs, colors: cols, locations: [0, 0.45, 1]) else { return }
            let c = CGPoint(x: size / 2, y: size / 2)
            ctx.cgContext.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: size / 2, options: [])
        }.cgImage
    }

    /// Đốm sáng mềm (Đèn lồng: lõi ấm + quầng màu; Sương ma: mờ tan mép) — một lần mỗi màu.
    static func renderGlow(_ e: KeyEffect, rgb: UInt32, scale: CGFloat) -> CGImage? {
        let size = CGFloat(GlowSprite.size)
        let f = UIGraphicsImageRendererFormat()
        f.scale = scale
        f.opaque = false
        let base = UIColor(rgb: rgb)
        let stops = GlowSprite.stops(e)
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: f).image { ctx in
            let cols = stops.enumerated().map { i, s -> CGColor in
                let c = (e == .lantern && i == 0) ? UIColor(rgb: GlowSprite.core) : base
                return c.withAlphaComponent(CGFloat(s.alpha)).cgColor
            } as CFArray
            let locs = stops.map { CGFloat($0.pos) }
            guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cols, locations: locs) else { return }
            let c = CGPoint(x: size / 2, y: size / 2)
            ctx.cgContext.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: size / 2, options: [])
        }.cgImage
    }

    /// Dải cột Matrix: chữ đơn cách, đầu sáng dưới cùng, đuôi mờ dần lên trên.
    static func renderStrip(_ strip: Int, scale: CGFloat) -> CGImage? {
        let w = CGFloat(MatrixRain.columnWidth), h = CGFloat(MatrixRain.stripHeight)
        let f = UIGraphicsImageRendererFormat()
        f.scale = scale
        f.opaque = false
        let font = UIFont.monospacedSystemFont(ofSize: CGFloat(MatrixRain.glyphSize), weight: .medium)
        let green = UIColor(rgb: MatrixRain.green), head = UIColor(rgb: MatrixRain.head)
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: f).image { _ in
            for r in 0..<MatrixRain.rows {
                let g = String(MatrixRain.glyph(strip: strip, row: r)) as NSString
                let isHead = r == MatrixRain.rows - 1
                let c = (isHead ? head : green).withAlphaComponent(CGFloat(MatrixRain.rowAlpha(r)))
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: c]
                let sz = g.size(withAttributes: attrs)
                g.draw(at: CGPoint(x: (w - sz.width) / 2, y: CGFloat(r) * CGFloat(MatrixRain.lineHeight)), withAttributes: attrs)
            }
        }.cgImage
    }

    private static func group(_ parts: [CAAnimation], duration: Double, delay: Double) -> CAAnimationGroup {
        for p in parts where p.duration == 0 { p.duration = duration }
        let g = CAAnimationGroup()
        g.animations = parts
        g.duration = duration
        g.beginTime = animBegin + delay
        g.fillMode = .both
        g.isRemovedOnCompletion = false
        return g
    }

    private static func makeAnimation(_ t: KeyEffectTrajectory) -> CAAnimationGroup {
        let move = CABasicAnimation(keyPath: "position")
        move.isAdditive = true
        move.fromValue = NSValue(cgPoint: .zero)
        move.toValue = NSValue(cgPoint: CGPoint(x: t.dx, y: t.dy))
        move.timingFunction = CAMediaTimingFunction(name: .easeOut)
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = t.scaleFrom
        scale.toValue = t.scaleTo
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 1, 0]
        fade.keyTimes = [0, 0.5, 1]
        var parts: [CAAnimation] = [move, scale, fade]
        if t.rotation != 0 {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = t.rotation
            parts.append(spin)
        }
        if t.sway != 0 {
            let sway = CAKeyframeAnimation(keyPath: "position.x")
            sway.isAdditive = true
            sway.values = (0...8).map { t.sway * sin(Double($0) / 8 * 2 * .pi) }
            parts.append(sway)
        }
        // Giữ animation (không gỡ khi xong): chùm chỉ cần đổi beginTime là chạy lại; xong thì đứng ở
        // khung cuối (opacity 0 — vô hình, render server không vẽ gì).
        return group(parts, duration: t.duration, delay: 0)
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

/// Hình vector của từng kiểu (toạ độ quanh gốc 0,0 — layer đặt position là tâm).
enum KeyEffectShapes {
    static func path(_ e: KeyEffect) -> CGPath? { path(e, particle: 0) }

    static func path(_ e: KeyEffect, particle i: Int) -> CGPath? {
        switch e {
        case .heart: return heart(8)
        case .bubble: return CGPath(ellipseIn: CGRect(x: -7, y: -7, width: 14, height: 14), transform: nil)
        case .ripple: return CGPath(ellipseIn: CGRect(x: -20, y: -20, width: 40, height: 40), transform: nil)
        case .petal: return petal(8)
        case .firework: return star(5, inner: 1.6)
        case .blossom: return i % 2 == 0 ? flower(7) : petal(6)
        case .combo: return flame(9)
        case .snow: return snowflake(6)
        case .meteor: return meteor()
        // Đèn lồng / Sương ma vẽ bằng ảnh đốm sáng (GlowSprite); path = khung tròn của đốm (đo / dự phòng).
        case .lantern, .smoke:
            let r = CGFloat(GlowSprite.size / 2)
            return CGPath(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r), transform: nil)
        case .wave: return CGPath(ellipseIn: CGRect(x: -WaveRings.radius, y: -WaveRings.radius,
                                                    width: 2 * WaveRings.radius, height: 2 * WaveRings.radius), transform: nil)
        default: return nil
        }
    }

    static func heart(_ s: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: s * 0.9))
        p.addCurve(to: CGPoint(x: -s, y: -s * 0.2), control1: CGPoint(x: -s * 0.6, y: s * 0.5),
                   control2: CGPoint(x: -s, y: s * 0.15))
        p.addCurve(to: CGPoint(x: 0, y: -s * 0.55), control1: CGPoint(x: -s, y: -s * 0.85),
                   control2: CGPoint(x: -s * 0.2, y: -s * 0.95))
        p.addCurve(to: CGPoint(x: s, y: -s * 0.2), control1: CGPoint(x: s * 0.2, y: -s * 0.95),
                   control2: CGPoint(x: s, y: -s * 0.85))
        p.addCurve(to: CGPoint(x: 0, y: s * 0.9), control1: CGPoint(x: s, y: s * 0.15),
                   control2: CGPoint(x: s * 0.6, y: s * 0.5))
        p.closeSubpath()
        return p
    }

    static func petal(_ s: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: -s))
        p.addQuadCurve(to: CGPoint(x: 0, y: s), control: CGPoint(x: s * 0.9, y: -s * 0.1))
        p.addQuadCurve(to: CGPoint(x: 0, y: -s), control: CGPoint(x: -s * 0.9, y: -s * 0.1))
        p.closeSubpath()
        return p
    }

    static func star(_ r: CGFloat, inner: CGFloat) -> CGPath {
        let p = CGMutablePath()
        for k in 0..<8 {
            let a = CGFloat(k) * .pi / 4 - .pi / 2
            let rr = k % 2 == 0 ? r : inner
            let pt = CGPoint(x: cos(a) * rr, y: sin(a) * rr)
            if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }

    /// Hoa 5 cánh (đào / mai): 5 cánh tròn quanh tâm.
    static func flower(_ r: CGFloat) -> CGPath {
        let p = CGMutablePath()
        let pr = r * 0.48
        for k in 0..<5 {
            let a = CGFloat(k) * 2 * .pi / 5 - .pi / 2
            let c = CGPoint(x: cos(a) * (r - pr), y: sin(a) * (r - pr))
            p.addEllipse(in: CGRect(x: c.x - pr, y: c.y - pr, width: 2 * pr, height: 2 * pr))
        }
        return p
    }

    /// Ngọn lửa (giọt ngược, đỉnh nhọn hướng lên).
    static func flame(_ s: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: -s))
        p.addCurve(to: CGPoint(x: 0, y: s * 0.7), control1: CGPoint(x: s * 0.9, y: -s * 0.1),
                   control2: CGPoint(x: s * 0.75, y: s * 0.7))
        p.addCurve(to: CGPoint(x: 0, y: -s), control1: CGPoint(x: -s * 0.75, y: s * 0.7),
                   control2: CGPoint(x: -s * 0.9, y: -s * 0.1))
        p.closeSubpath()
        return p
    }

    /// Sao băng: giọt thon theo hướng bay — đầu tròn, đuôi dài (MeteorStreak).
    static func meteor() -> CGPath {
        let p = CGMutablePath()
        let pts = MeteorStreak.polygon()
        p.move(to: CGPoint(x: pts[0].x, y: pts[0].y))
        for q in pts.dropFirst() { p.addLine(to: CGPoint(x: q.x, y: q.y)) }
        p.closeSubpath()
        return p
    }

    /// Bông tuyết 6 nhánh (mỗi nhánh một thanh mảnh + 2 ngạnh) — tô kín.
    static func snowflake(_ r: CGFloat) -> CGPath {
        let p = CGMutablePath()
        let w: CGFloat = 0.7
        for k in 0..<6 {
            let t = CGAffineTransform(rotationAngle: CGFloat(k) * .pi / 3)
            p.addRect(CGRect(x: -w / 2, y: -r, width: w, height: r), transform: t)
            for side in [-1.0, 1.0] as [CGFloat] {
                let barb = CGAffineTransform(translationX: 0, y: -r * 0.6).rotated(by: side * .pi / 4).concatenating(t)
                p.addRect(CGRect(x: -w / 2, y: -r * 0.32, width: w, height: r * 0.32), transform: barb)
            }
        }
        return p
    }
}
