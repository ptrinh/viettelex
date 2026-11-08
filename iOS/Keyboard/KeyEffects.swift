// "Hiệu ứng khi bấm phím" (Plus, Phil 19/10/2026): Trái tim, Bong bóng, Gợn sóng,
// Cánh hoa, Pháo hoa, Nháy sáng, Matrix, Tia sét, Emoji theo chữ, Hoa đào / mai, Lửa combo, Mực loang,
// Sóng nước, Tuyết rơi, Sao băng, Đèn lồng, Sương ma, Rung dây, Plasma, Rung combo, Laser, Glitch, Dấu thanh, Từ khoá,
// Chữ bay, Hạt cát, Biển, Token AI; "Không" = mặc định. Song sinh android/keyboard/.../KeyEffect.kt (cùng khoá
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
    // Đợt 3 (11/2026): tia plasma nối phím, rung combo, laser từ phím cách, glitch, dấu thanh, từ khoá (pháo đỏ / lì xì),
    // chữ bay, hạt cát.
    case plasma, shake, laser, glitch, tone, keyword, letters, sand
    // Theme Biển (11/2026): sóng vỗ bờ + bọt bắn + bong bóng + cá bơi khi combo (SeaFx).
    case sea
    // Theme "AI" (11/2026): chữ vừa ra vỡ thành vài "token" phát sáng bay vào thanh gợi ý (TokenStream).
    case tokens
    // Theme Neon Night Club (11/2026): Sàn nhảy LED — phím vừa bấm + các phím quanh thắp neon thành vòng vuông lan ra.
    case dancefloor
    // Theme "Ảo giác" (11/2026): Kính vạn hoa — bông đối xứng 8 nhánh sắc cầu vồng nở + xoay chậm từ phím (Kaleido.swift).
    case kaleido
    // Theme "Lạc trôi" (11/2026, Drift.swift): Đường hầm — vòng co về phím vừa bấm như rơi vào đường hầm (TunnelFx);
    // Lơ lửng — phím trôi + nhấp nhô chậm khi đang gõ, nghỉ thì về chỗ (FloatFx / KeyFloat, chỉ hình).
    case tunnel, float
    // Theme Gõ mõ / Kính màu (11/2026): Công đức ("+1 công đức" bay lên + đếm trong ngày), Nắng qua kính (ô kính sáng
    // lên + tia nắng chéo, gõ dồn ⇒ ánh nến mép dưới) — MeritGlass.swift.
    case merit, sunlight
    // Theme "Mưa đêm" (11/2026): mưa đêm êm trên ô kính — giọt rơi + loang + lăn ở phím, hạt mưa nền trượt chậm, mưa
    // thưa dần khi gõ và ánh đèn vàng ấm ở góc sáng lên (RainFx).
    case rain
    // Theme Gym (11/2026): Rep — thanh rep lấp mỗi phím, 10 phím = SET ✓, gõ nhanh "+1 rep 💪", từ khoá ⇒ BEAST MODE (RepsFx).
    case reps

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
        case .plasma: return L("Plasma")
        case .shake: return L("Rung combo")
        case .laser: return L("Laser")
        case .glitch: return L("Glitch")
        case .tone: return L("Dấu thanh")
        case .keyword: return L("Từ khoá")
        case .letters: return L("Chữ bay")
        case .sand: return L("Hạt cát")
        case .sea: return L("Biển")
        case .tokens: return L("Token AI")
        case .dancefloor: return L("Sàn nhảy LED")
        case .kaleido: return L("Kính vạn hoa")
        case .tunnel: return L("Đường hầm")
        case .float: return L("Lơ lửng")
        case .merit: return L("Công đức")
        case .sunlight: return L("Nắng qua kính")
        case .rain: return L("Mưa")
        case .reps: return L("Rep")
        }
    }

    /// Mọi kiểu trừ "Không" thuộc Plus.
    var isPlus: Bool { self != .none }

    /// Chỉ bắn khi controller xếp sẵn sự kiện (từ vừa chốt / dấu vừa bỏ / chữ vừa ra): phím thường không hẹn vẽ gì.
    var isQueued: Bool { self == .emojiword || self == .tone || self == .keyword || self == .letters || self == .tokens }
    /// Controller phải so từ đang soạn trước/sau phím — kiểu khác: không đọc gì (0 chi phí).
    var needsComposeDiff: Bool { self == .tone || self == .letters || self == .tokens }
    /// Controller phải tra từ vừa chốt ở ranh giới.
    var needsBoundaryWord: Bool { self == .emojiword || self == .keyword || self == .reps }

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
        case .sea: return SeaFx.tapSlots    // chùm bọt + bong bóng; sóng / cá là layer riêng
        case .rain: return RainFx.tapSlots  // giọt + vòng loang + vệt ướt; mưa nền / đèn là layer riêng
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
        case .sea: return SeaFx.layersPerTap
        case .rain: return RainFx.layersPerTap
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

// MARK: - Đợt 3 (11/2026): Plasma, Rung combo, Laser, Glitch, Dấu thanh, Từ khoá, Chữ bay, Hạt cát
// Hàm thuần song sinh android KeyEffect.kt — CÙNG SỐ (test chéo hai nền tảng).

/// LCG của FxRandom viết thẳng (không tạo struct): trạng thái đầu / kế / giá trị 0…1.
@inline(__always) func fxSeed(_ seed: Int) -> UInt32 { UInt32(truncatingIfNeeded: seed) &* 2_654_435_761 &+ 1 }
@inline(__always) func fxStep(_ st: UInt32) -> UInt32 { st &* 1_103_515_245 &+ 12345 }
@inline(__always) func fxValue(_ st: UInt32) -> Double { Double((st >> 8) & 0xFFFF) / 65535 }

/// "Plasma": tia điện tím nối phím TRƯỚC với phím vừa bấm — gõ nhanh thành chuỗi, mỗi tia tắt nhanh. Hai phím cách
/// nhau quá `chainWindow` (hay cùng phím) ⇒ không nối, chỉ đốm lửa nhỏ tại phím.
enum PlasmaArc {
    static let chainWindow = 0.5
    static let segments = 8
    static let duration = 0.22
    static let maxJitter = 9.0
    /// Ngắn hơn (pt) ⇒ cùng phím: không nối.
    static let minLength = 6.0
    static let pool = 4
    static let variants = 6
    static let color: UInt32 = 0xB44CFF
    static let core: UInt32 = 0xF3E0FF
    static let sparkRadius = 7.0

    /// `segments + 1` điểm từ p0 tới p1: lệch vuông góc tất định theo `variant`, bao sin (hai đầu đúng tâm phím).
    static func points(from p0: (x: Double, y: Double), to p1: (x: Double, y: Double), variant: Int) -> [(x: Double, y: Double)] {
        let dx = p1.x - p0.x, dy = p1.y - p0.y
        let len = hypot(dx, dy)
        let nx = len > 1e-9 ? -dy / len : 0, ny = len > 1e-9 ? dx / len : 0
        let amp = min(maxJitter, len * 0.15)
        var st = fxSeed(variant &* 7919 &+ 29)
        var out: [(x: Double, y: Double)] = [p0]
        out.reserveCapacity(segments + 1)
        for i in 1..<segments {
            let f = Double(i) / Double(segments)
            st = fxStep(st)
            let off = (fxValue(st) - 0.5) * 2 * amp * sin(f * .pi)
            out.append((p0.x + dx * f + nx * off, p0.y + dy * f + ny * off))
        }
        out.append(p1)
        return out
    }

    /// Độ mờ sau `dt` giây: giữ 30 % rồi tắt tuyến tính.
    static func alpha(_ dt: Double) -> Double {
        guard dt >= 0, dt < duration else { return 0 }
        let f = dt / duration
        return f < 0.3 ? 1 : 1 - (f - 0.3) / 0.7
    }
}

/// Chuỗi Plasma: nhớ phím trước (toạ độ + giờ).
struct PlasmaChain {
    private(set) var prev: (x: Double, y: Double) = (0, 0)
    private var lastP: (x: Double, y: Double) = (0, 0)
    private var last = -Double.greatestFiniteMagnitude

    /// Một phím tại `p` lúc `t` (giây): true ⇒ nối tia từ `prev`.
    mutating func press(_ p: (x: Double, y: Double), at t: Double) -> Bool {
        let link = t - last <= PlasmaArc.chainWindow && hypot(p.x - lastP.x, p.y - lastP.y) >= PlasmaArc.minLength
        prev = lastP
        lastP = p
        last = t
        return link
    }
    mutating func reset() { last = -Double.greatestFiniteMagnitude }
}

/// "Rung combo": gõ nhanh ⇒ hàng phím rung kiểu đòn trúng trong game đối kháng, mạnh dần theo mức ShakeMeter
/// (3 / 5 / 7 pt), ~0,25 s, 3–4 nhịp tắt dần, ngang + chút dọc. Chỉ dời HÌNH (animation cộng dồn trên layer — khung
/// nhận chạm của phím không đổi), tự gỡ. Giảm chuyển động KHÔNG tắt (Phil 08/11/2026, như mọi hiệu ứng khác).
/// Bản trước (1,5 pt / 0,18 s, mức ComboMeter cần 6 phím / 2 s, tắt khi Giảm chuyển động) gần như không thấy.
enum ShakeFx {
    static let max = 7.0
    static let amps: [Double] = [0, 3, 5, 7]
    /// 7 đoạn × 35 ms (Android DURATION_MS = 245).
    static let duration = 0.245
    /// Khung hình (tỉ lệ biên độ) — dao động tắt dần, đầu/cuối 0.
    static let xs: [Double] = [0, 1.0, -0.85, 0.65, -0.45, 0.28, -0.12, 0]
    static let ys: [Double] = [0, -0.35, 0.3, -0.22, 0.15, -0.08, 0.03, 0]

    /// Biên độ (pt) cho mức ShakeMeter.
    static func amplitude(level: Int) -> Double {
        Swift.min(max, amps[Swift.min(Swift.max(level, 0), amps.count - 1)])
    }

    private static func sample(_ k: [Double], _ dt: Double, _ amp: Double) -> Double {
        guard dt > 0, dt < duration, amp != 0 else { return 0 }
        let x = dt / duration * Double(k.count - 1)
        let i = Int(x)
        return amp * (k[i] + (k[i + 1] - k[i]) * (x - Double(i)))
    }
    static func offsetX(_ dt: Double, amp: Double) -> Double { sample(xs, dt, amp) }
    static func offsetY(_ dt: Double, amp: Double) -> Double { sample(ys, dt, amp) }
}

/// Mức rung: số phím trong `window` giây gần nhất (kể cả phím này) ≥ 4 / 6 / 8 ⇒ mức 1 / 2 / 3 — gõ nhanh bình thường
/// (≈ 3,5 phím/s) đã lên mức 1. Riêng với ComboMeter (Lửa combo giữ ngưỡng cũ).
struct ShakeMeter {
    static let window = 1.2
    static let thresholds = [4, 6, 8]
    static let capacity = 8
    private var times = [Double](repeating: -Double.greatestFiniteMagnitude, count: ShakeMeter.capacity)
    private var head = 0

    /// Ghi một phím lúc `t` (giây) — trả mức sau phím đó.
    mutating func press(at t: Double) -> Int {
        times[head] = t
        head = (head + 1) % Self.capacity
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

/// "Laser": tia mảnh sáng từ phím cách bắn lên phím vừa bấm, tắt nhanh.
enum LaserBeam {
    static let duration = 0.16
    /// Thời gian đầu tia chạy từ phím cách tới phím.
    static let travel = 0.04
    static let color: UInt32 = 0xFF2D55
    static let glowWidth = 4.0, coreWidth = 1.2
    static let pool = 3
    /// Không biết phím cách: gốc giữa đáy, cách đáy chừng này (pt).
    static let fallbackInset = 4.0

    /// Phím vừa bấm nằm trong phím cách ⇒ không bắn (tia dài 0).
    static func fires(space: CGRect, key p: CGPoint) -> Bool { !space.contains(p) }
    static func reach(_ dt: Double) -> Double { Swift.min(Swift.max(dt / travel, 0), 1) }
    static func alpha(_ dt: Double) -> Double {
        guard dt >= 0, dt < duration else { return 0 }
        let f = dt / duration
        return f < 0.25 ? 1 : 1 - (f - 0.25) / 0.75
    }
}

/// "Glitch": phím vừa bấm nhiễu hình ~120 ms — lệch kênh màu (lục lam / hồng) + vài lát ngang lệch trái/phải, đổi
/// mỗi `stepTime`. Chỉ lớp phủ (lát = màu phím), phím thật không bị đụng.
enum GlitchFx {
    static let duration = 0.12
    static let stepTime = 0.03
    static let steps = 4
    static let slices = 3
    static let maxShift = 4.0
    static let split = 2.0
    static let cyan: UInt32 = 0x00E5FF
    static let magenta: UInt32 = 0xFF2BD6
    static let pool = 2
    static let variants = 8

    /// Lát ở bước `step` (lần bấm `variant`): (đỉnh 0…1, cao 0…1, lệch −1…1).
    static func slices(step: Int, variant: Int) -> [(y: Double, h: Double, dx: Double)] {
        var st = fxSeed(variant &* 131 &+ step &* 17 &+ 5)
        return (0..<slices).map { _ in
            st = fxStep(st); let h = 0.08 + fxValue(st) * 0.14
            st = fxStep(st); let y = fxValue(st) * (1 - h)
            st = fxStep(st); let dx = fxValue(st) * 2 - 1
            return (y, h, dx)
        }
    }
    /// Bước sau `dt` giây; ≥ steps ⇒ hết.
    static func step(_ dt: Double) -> Int { dt < 0 ? steps : Int((dt * 1000).rounded(.down)) / Int(stepTime * 1000) }
    /// Lệch kênh màu bước `step`: bước lẻ một nửa.
    static func split(step: Int) -> Double { step % 2 == 0 ? split : split / 2 }
}

/// Kiểu hình "Dấu thanh": 5 dấu thanh + mũ (â ê ô ă) / râu (ơ ư) / gạch đ. Thứ tự = Android ToneFx.
enum ToneFx: Int, CaseIterable {
    case sac, huyen, hoi, nga, nang, hat, horn, stroke
}

/// "Dấu thanh": so từ đang soạn TRƯỚC/SAU phím ⇒ dấu vừa bỏ. Bảng ký tự dựng một lần (tra không cấp phát); nhận cả
/// dấu rời (U+0300…). Chỉ chạy khi chọn kiểu này.
enum ToneMarks {
    /// Mỗi hàng 6 ký tự: không dấu, sắc, huyền, hỏi, ngã, nặng.
    private static let table = Array("aáàảãạăắằẳẵặâấầẩẫậeéèẻẽẹêếềểễệiíìỉĩịoóòỏõọôốồổỗộơớờởỡợuúùủũụưứừửữựyýỳỷỹỵ".unicodeScalars)
    private static let bases = Array("aăâeêioôơuưy")
    /// Mã: 3 bit thấp = dấu thanh (0…5), bit 3+ = 1 mũ / 2 râu / 3 gạch — cả chữ hoa.
    private static let codes: [UInt32: UInt8] = {
        var m: [UInt32: UInt8] = [0x301: 1, 0x300: 2, 0x309: 3, 0x303: 4, 0x323: 5, 0x302: 1 << 3, 0x306: 1 << 3, 0x31B: 2 << 3]
        for (i, u) in table.enumerated() {
            let mod: UInt8
            switch bases[i / 6] {
            case "ă", "â", "ê", "ô": mod = 1
            case "ơ", "ư": mod = 2
            default: mod = 0
            }
            let c = UInt8(i % 6) | (mod << 3)
            m[u.value] = c
            for up in String(u).uppercased().unicodeScalars { m[up.value] = c }
        }
        m[0x111] = 3 << 3; m[0x110] = 3 << 3        // đ Đ
        return m
    }()

    static func code(_ u: Unicode.Scalar) -> Int { Int(codes[u.value] ?? 0) }

    /// (dấu thanh 0…5, số mũ, số râu, số gạch).
    static func summary(_ w: String) -> (tone: Int, hats: Int, horns: Int, strokes: Int) {
        var tone = 0, hats = 0, horns = 0, strokes = 0
        for u in w.unicodeScalars {
            let c = code(u)
            if c & 7 != 0 { tone = c & 7 }
            switch c >> 3 { case 1: hats += 1; case 2: horns += 1; case 3: strokes += 1; default: break }
        }
        return (tone, hats, horns, strokes)
    }

    /// Dấu vừa bỏ khi từ đổi `before` → `after`; nil = không (gỡ dấu, chữ thường, ranh giới…).
    static func detect(before: String, after: String) -> ToneFx? {
        guard !after.isEmpty else { return nil }
        let b = summary(before), a = summary(after)
        if a.tone != 0 && a.tone != b.tone { return ToneFx(rawValue: a.tone - 1) }
        if a.strokes > b.strokes { return .stroke }
        if a.horns > b.horns { return .horn }
        if a.hats > b.hats { return .hat }
        return nil
    }
}

/// Màu + quỹ đạo của "Dấu thanh" (pt, giây).
enum ToneBurst {
    static let sparks = 4
    static let pool = 2      // mỗi kiểu dấu (dựng lười)
    static func color(_ k: ToneFx) -> UInt32 {
        switch k {
        case .sac: return 0xFFC83D
        case .huyen: return 0x4FC3F7
        case .hoi: return 0xB388FF
        case .nga: return 0x26C6DA
        case .nang: return 0xFF7043
        default: return 0xFFE082
        }
    }
    static func count(_ k: ToneFx) -> Int { k == .sac || k == .huyen ? sparks : 1 }
    static func stretchesX(_ k: ToneFx) -> Bool { k == .nga }
    static func easeIn(_ k: ToneFx) -> Bool { k == .nang }
    /// Hình vẽ bằng nét (móc hỏi, sóng ngã, mũ, râu, gạch); còn lại tô.
    static func stroked(_ k: ToneFx) -> Bool { !(k == .sac || k == .huyen || k == .nang) }

    /// Sắc: tia lửa lên-phải; huyền: xuống-trái; hỏi: móc xoáy; ngã: sóng giãn ngang; nặng: giọt rơi; mũ…: lấp lánh.
    static func trajectory(_ k: ToneFx, _ i: Int) -> KeyEffectTrajectory {
        switch k {
        case .sac, .huyen:
            let base = k == .sac ? -Double.pi / 4 : 3 * Double.pi / 4
            let a = base + (Double(i) - 1.5) * 0.28
            let d = 26.0 + Double(i % 2) * 8
            return KeyEffectTrajectory(dx: cos(a) * d, dy: sin(a) * d, scaleFrom: 1, scaleTo: 0.4, rotation: 0, duration: 0.42)
        case .hoi: return KeyEffectTrajectory(dx: 0, dy: -18, scaleFrom: 0.6, scaleTo: 1.3, rotation: -1.2, duration: 0.5)
        case .nga: return KeyEffectTrajectory(dx: 0, dy: -10, scaleFrom: 0.6, scaleTo: 2.0, rotation: 0, duration: 0.5)
        case .nang: return KeyEffectTrajectory(dx: 0, dy: 28, scaleFrom: 1, scaleTo: 0.8, rotation: 0, duration: 0.55)
        default: return KeyEffectTrajectory(dx: 0, dy: -14, scaleFrom: 0.4, scaleTo: 1.4, rotation: 0, duration: 0.4)
        }
    }

    /// Hình (pt quanh gốc) — y hệt Android buildFx3Paths.
    static func path(_ k: ToneFx) -> CGPath {
        let p = CGMutablePath()
        switch k {
        case .sac, .huyen: return KeyEffectShapes.star4(3.5, inner: 1)
        case .hoi:
            p.move(to: CGPoint(x: -3.5, y: -2.5))
            p.addQuadCurve(to: CGPoint(x: 1, y: -6), control: CGPoint(x: -3, y: -6.5))
            p.addQuadCurve(to: CGPoint(x: 3, y: -2), control: CGPoint(x: 4.5, y: -5))
            p.addQuadCurve(to: CGPoint(x: 0, y: 1), control: CGPoint(x: 1.5, y: 0.5))
            p.addLine(to: CGPoint(x: 0, y: 4))
        case .nga:
            p.move(to: CGPoint(x: -8, y: 1))
            p.addQuadCurve(to: CGPoint(x: 0, y: 0), control: CGPoint(x: -4, y: -5))
            p.addQuadCurve(to: CGPoint(x: 8, y: -1), control: CGPoint(x: 4, y: 5))
        case .nang:
            p.move(to: CGPoint(x: 0, y: -6))
            p.addQuadCurve(to: CGPoint(x: 3.5, y: 2.5), control: CGPoint(x: 5, y: 0))
            p.addQuadCurve(to: CGPoint(x: -3.5, y: 2.5), control: CGPoint(x: 0, y: 6.5))
            p.addQuadCurve(to: CGPoint(x: 0, y: -6), control: CGPoint(x: -5, y: 0))
            p.closeSubpath()
        case .hat:
            p.move(to: CGPoint(x: -5, y: 2.5)); p.addLine(to: CGPoint(x: 0, y: -2.5)); p.addLine(to: CGPoint(x: 5, y: 2.5))
        case .horn:
            p.move(to: CGPoint(x: -1, y: 3))
            p.addQuadCurve(to: CGPoint(x: 3, y: -3), control: CGPoint(x: 4, y: 2))
            p.addLine(to: CGPoint(x: 5, y: -4))
        case .stroke:
            p.move(to: CGPoint(x: -5, y: 0)); p.addLine(to: CGPoint(x: 5, y: 0))
        }
        return p
    }
}

enum KeywordKind: Int, CaseIterable { case laugh, love, angry, tet }

/// "Từ khoá": từ vừa chốt khớp bảng nhỏ ⇒ chùm hình theo nghĩa: cười (mặt cười), yêu (tim), giận (khói bốc), Tết
/// (pháo đỏ nổ + xác pháo rơi + lì xì bay lên). Tra O(1) ở RANH GIỚI TỪ. Từ Việt khớp ĐÚNG dấu (không phân biệt hoa
/// thường): "tết" ≠ "tet", "thương" ≠ "thường"; tiếng cười lặp ("hahaha", "kkkk") khớp theo đơn vị lặp. Lọc từ tục như
/// Emoji theo chữ. Bảng y hệt Android KeywordBursts.
enum KeywordBursts {
    static let entries: [(form: String, kind: KeywordKind)] = [
        ("haha", .laugh), ("hihi", .laugh), ("hehe", .laugh), ("kkk", .laugh),
        ("yêu", .love), ("thương", .love), ("love", .love),
        ("giận", .angry), ("bực", .angry),
        ("tết", .tet), ("năm mới", .tet), ("lì xì", .tet), ("lixi", .tet),
    ]
    /// Tiếng cười lặp: (đơn vị, số lần tối thiểu).
    static let laughUnits: [(unit: String, min: Int)] = [("ha", 2), ("hi", 2), ("he", 2), ("k", 3)]
    private static let table: [String: KeywordKind] = Dictionary(entries.map { ($0.form, $0.kind) }, uniquingKeysWith: { a, _ in a })

    private static func clean(_ s: String) -> String { s.trimmingCharacters(in: CharacterSet.letters.inverted).lowercased() }

    static func isLaugh(_ w: String) -> Bool {
        let cs = Array(w)
        return laughUnits.contains { u in
            let us = Array(u.unit)
            guard cs.count >= us.count * u.min, cs.count % us.count == 0 else { return false }
            return cs.indices.allSatisfy { cs[$0] == us[$0 % us.count] }
        }
    }

    /// Kiểu chùm cho từ vừa chốt (từ liền trước `prev` — cụm 2 từ ưu tiên: "chúc mừng năm mới" ⇒ "năm mới").
    static func lookup(word: String, prev: String?) -> KeywordKind? {
        let w = clean(word)
        guard !w.isEmpty, w.count <= 24 else { return nil }
        let p = prev.map(clean)
        if EmojiWords.blocked(w, prev: p) { return nil }
        if let p, !p.isEmpty, let k = table[p + " " + w] { return k }
        return table[w] ?? (isLaugh(w) ? .laugh : nil)
    }

    enum Shape { case emoji, heart, puff, cracker, spark, paper, envelope }

    /// Một hạt: hình, màu (emoji: chỉ số trong `emojis`), điểm xuất phát lệch khỏi phím (pt), quỹ đạo, trễ (giây).
    struct Particle {
        var shape: Shape
        var color: UInt32
        var x0: Double, y0: Double
        var traj: KeyEffectTrajectory
        var delay: Double
        var easeIn = false
    }

    static func emojis(_ k: KeywordKind) -> [String] {
        switch k {
        case .laugh: return ["😂", "🤣", "😆"]
        case .angry: return ["😤"]
        default: return []
        }
    }
    static var allEmojis: [String] {
        var seen = Set<String>(); return KeywordKind.allCases.flatMap(emojis).filter { seen.insert($0).inserted }
    }

    static let red: UInt32 = 0xE53935
    static let gold: UInt32 = 0xFFC83D
    static let crackerRise = 0.35
    /// Số chùm xoay vòng mỗi kiểu (dựng lười).
    static let pool = 2

    private static let built: [[Particle]] = KeywordKind.allCases.map(build)
    /// Các hạt của chùm — tất định, ≤ KeyEffectPool.cap; dựng một lần.
    static func particles(_ k: KeywordKind) -> [Particle] { built[k.rawValue] }
    static func lifetime(_ k: KeywordKind) -> Double { particles(k).map { $0.delay + $0.traj.duration }.max() ?? 0 }

    private static func build(_ k: KeywordKind) -> [Particle] {
        switch k {
        case .laugh:
            return (0..<3).map { i in
                let t = Double(i) - 1
                return Particle(shape: .emoji, color: UInt32(i), x0: 0, y0: 0,
                                traj: KeyEffectTrajectory(dx: t * 24, dy: -(52 + (1 - abs(t)) * 12), scaleFrom: 0.6, scaleTo: 1.1,
                                                          rotation: t * 0.3, duration: 1.0), delay: Double(i) * 0.06)
            }
        case .love:
            let cols: [UInt32] = [0xFF3B6B, 0xFF7AA2, 0xE91E63]
            return (0..<5).map { i in
                let t = Double(i - 2) / 2
                return Particle(shape: .heart, color: cols[i % 3], x0: 0, y0: 0,
                                traj: KeyEffectTrajectory(dx: t * 30, dy: -(44 + Double(i % 3) * 8), scaleFrom: 0.5, scaleTo: 1.1,
                                                          rotation: t * 0.3, duration: 0.95, sway: 5), delay: Double(i) * 0.04)
            }
        case .angry:
            return [Particle(shape: .emoji, color: 0, x0: 0, y0: 0,
                             traj: KeyEffectTrajectory(dx: 0, dy: -22, scaleFrom: 0.6, scaleTo: 1.2, rotation: 0, duration: 0.8), delay: 0)]
                + (0..<4).map { i in
                    let side: Double = i % 2 == 0 ? -1 : 1
                    return Particle(shape: .puff, color: 0xB0B0B0, x0: side * 10, y0: -6,
                                    traj: KeyEffectTrajectory(dx: side * (10 + Double(i) * 3), dy: -(30 + Double(i) * 4), scaleFrom: 0.5,
                                                              scaleTo: 1.8, rotation: 0, duration: 0.8, sway: 3),
                                    delay: 0.08 + Double(i) * 0.06)
                }
        case .tet:
            var out: [Particle] = []
            for c in 0..<2 {
                let side: Double = c == 0 ? -1 : 1
                let rise = 56.0 + Double(c) * 10
                let start = Double(c) * 0.12
                out.append(Particle(shape: .cracker, color: red, x0: side * 6, y0: 0,
                                    traj: KeyEffectTrajectory(dx: side * 14, dy: -rise, scaleFrom: 1, scaleTo: 0.9, rotation: side * 0.4,
                                                              duration: crackerRise), delay: start))
                let px = side * 20, py = -rise
                for s in 0..<5 {     // nổ: tia vàng / đỏ toả tròn ở đỉnh
                    let a = Double(s) * 2 * .pi / 5 + Double(c) * 0.6
                    out.append(Particle(shape: .spark, color: s % 2 == 0 ? gold : red, x0: px, y0: py,
                                        traj: KeyEffectTrajectory(dx: cos(a) * 22, dy: sin(a) * 22, scaleFrom: 1, scaleTo: 0.4,
                                                                  rotation: 0, duration: 0.45), delay: start + crackerRise))
                }
                for b in 0..<3 {     // xác pháo đỏ rơi, lắc, xoay
                    let t = Double(b) - 1
                    out.append(Particle(shape: .paper, color: red, x0: px, y0: py,
                                        traj: KeyEffectTrajectory(dx: t * 18 + side * 6, dy: 44 + Double(b) * 12, scaleFrom: 1, scaleTo: 0.9,
                                                                  rotation: t * 3 + side, duration: 1.0, sway: 6),
                                        delay: start + crackerRise + 0.03, easeIn: true))
                }
            }
            for e in 0..<2 {         // lì xì bay lên
                let side: Double = e == 0 ? -1 : 1
                out.append(Particle(shape: .envelope, color: red, x0: side * 4, y0: 0,
                                    traj: KeyEffectTrajectory(dx: side * (20 + Double(e) * 8), dy: -(70 + Double(e) * 10), scaleFrom: 0.7,
                                                              scaleTo: 1, rotation: side * 0.25, duration: 1.3, sway: 6),
                                    delay: 0.1 + Double(e) * 0.15))
            }
            return out
        }
    }
}

/// "Chữ bay": ĐÚNG chữ vừa ra (kể cả dấu — lấy từ engine, không phải nhãn phím) bay lên từ phím, hơi xoay/lệch rồi mờ.
enum FlyingLetters {
    static let pool = 6
    static let duration = 0.7
    static let rise = 46.0
    static let size = 22.0

    /// Chữ vừa ra khi từ đang soạn đổi `before` → `after`: dài ra ⇒ ký tự cuối; cùng độ dài ⇒ ký tự cuối cùng KHÁC
    /// ("hoan"+"s" ⇒ "á", "tuong"+"w" ⇒ "ơ"). Từ rỗng (ký hiệu) ⇒ `typed` nếu đúng một ký tự in được.
    static func glyph(before: String, after: String, typed: String?) -> String? {
        if !after.isEmpty {
            guard after != before else { return nil }
            let a = Array(after), b = Array(before)
            var i = a.count - 1
            if a.count == b.count { while i > 0 && a[i] == b[i] { i -= 1 } }
            return String(a[i])
        }
        guard let t = typed, t.count == 1, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return t
    }

    static func drift(_ seed: Int) -> Double { (fxValue(fxStep(fxSeed(seed &* 37 &+ 11))) - 0.5) * 24 }
    static func spin(_ seed: Int) -> Double { (fxValue(fxStep(fxStep(fxSeed(seed &* 37 &+ 11)))) - 0.5) * 0.6 }
}

/// "Hạt cát": chạm phím ⇒ vài hạt rơi xuống đáy bàn phím rồi TÍCH LẠI thành đống thấp (mảng chiều cao theo cột — không
/// mô phỏng hạt đã đáp). Trần `maxHeight`; ngừng gõ `idleAfter` ⇒ lún dần trong `sinkTime` rồi sạch; ẩn bàn phím ⇒ xoá.
struct SandPile {
    static let column = 3.0
    static let grain = 0.6
    static let maxHeight = 5.0
    static let slope = 0.9
    static let grainsPerTap = 3
    static let grainSize = 1.8
    static let gravity = 1800.0
    static let idleAfter = 1.2
    static let sinkTime = 1.5
    static let color: UInt32 = 0xD9B26A
    static let flying = 12

    static func columns(for w: Double) -> Int { Swift.max(1, Int((Swift.max(w, 1) / column).rounded(.up))) }
    static func fallTime(_ d: Double) -> Double { sqrt(2 * Swift.max(d, 0) / gravity) }
    /// Hệ số còn lại sau `idle` giây không gõ: 1 tới idleAfter rồi giảm tuyến tính về 0 trong sinkTime.
    static func sinkFactor(idle: Double) -> Double {
        if idle <= idleAfter { return 1 }
        if idle >= idleAfter + sinkTime { return 0 }
        return 1 - (idle - idleAfter) / sinkTime
    }
    static func spread(_ i: Int, seed: Int) -> Double { (fxValue(fxStep(fxSeed(seed &* 53 &+ i &* 7 &+ 3))) - 0.5) * 16 }

    let columns: Int
    private(set) var heights: [Double]
    init(width: Double) {
        columns = Self.columns(for: width)
        heights = [Double](repeating: 0, count: columns)
    }

    func column(_ x: Double) -> Int { Swift.min(Swift.max(Int(x / Self.column), 0), columns - 1) }
    func surface(_ x: Double) -> Double { heights[column(x)] }
    var isEmpty: Bool { heights.allSatisfy { $0 <= 1e-6 } }
    var maxHeightNow: Double { heights.max() ?? 0 }

    /// Một hạt đáp tại x: cột cao thêm `grain` (trần — đầy thì lăn sang cột thấp hơn), rồi sạt cho dốc ≤ slope.
    mutating func deposit(_ x: Double) {
        var c = column(x)
        var guardN = 0
        while heights[c] + Self.grain > Self.maxHeight {
            let l = c > 0 ? heights[c - 1] : .greatestFiniteMagnitude
            let r = c < columns - 1 ? heights[c + 1] : .greatestFiniteMagnitude
            guardN += 1
            if Swift.min(l, r) >= heights[c] || guardN > columns + 1 { return }
            c = l <= r ? c - 1 : c + 1
        }
        heights[c] += Self.grain
        relax(c)
    }

    private mutating func relax(_ start: Int) {
        var c = start
        for _ in 0..<columns {
            let l = c > 0 ? heights[c] - heights[c - 1] : 0
            let r = c < columns - 1 ? heights[c] - heights[c + 1] : 0
            if l <= Self.slope && r <= Self.slope { return }
            let n = l >= r ? c - 1 : c + 1
            let move = (heights[c] - heights[n]) / 2
            heights[c] -= move; heights[n] += move
            c = n
        }
    }

    mutating func scale(_ f: Double) { let k = Swift.min(Swift.max(f, 0), 1); for i in heights.indices { heights[i] *= k } }
    mutating func clear() { for i in heights.indices { heights[i] = 0 } }
}

/// "Biển" (theme Biển, 11/2026): SÓNG VỖ BỜ là phần chính — gõ ⇒ một con sóng cuộn từ đỉnh bàn phím xuống đáy (đáy = bờ
/// cát): mặt sóng cong, mép bọt trắng; chạm bờ thì vỡ bọt tràn dọc đáy rồi rút, để lại vệt ướt mờ dần. Gõ liên tiếp ⇒ sóng
/// nối nhau (cách nhau ≥ `launchGap`, tối đa `maxWaves` — sóng mới không bao giờ cướp sóng đang chạy); gõ nhanh (mức
/// ComboMeter) ⇒ sóng to hơn. Phụ: vài giọt bọt bắn ở phím + 2 bong bóng lắc lên rồi vỡ thành vòng; combo lên `fishLevel` ⇒
/// một chú cá bơi ngang một lần. Nghỉ gõ = không còn gì chạy. Hàm thuần — Android SeaFx y hệt (test số chung).
/// Phil 08/11/2026: sóng chạy nhanh quá ⇒ chậm ~1,9× như sóng lừng ngoài biển (cuộn 1,15 s êm — chậm lúc đầu, đều, chỉ
/// nhanh dần chút trước khi chạm bờ; vỡ 0,55 s; rút 1,3 s) + mỗi con sóng mới một tiếng "ào" (KeySoundSynth.surfSamples,
/// tiếng vỡ trùng lúc sóng chạm bờ) khi Âm thanh phím bật.
enum SeaFx {
    // Sóng vỗ bờ
    static let maxWaves = 3
    static let launchGap = 1.0
    /// Cuộn từ đỉnh xuống bờ / vỡ bọt tràn lên / rút (giây).
    static let roll = 1.15, breakTime = 0.55, recede = 1.3
    static var life: Double { roll + breakTime + recede }
    /// Thân sóng (pt, phía sau mép sóng) — nhân cỡ sóng.
    static let bodyHeight = 26.0
    static let bodyAlpha = 0.22
    static let foamAlpha = 0.85
    static let foamWidth = 2.5
    static let crestAmp = 3.5
    static let wavelength = 110.0
    /// Mép sóng trôi ngang khi cuộn (pt).
    static let drift = 16.0
    /// Bọt tràn lên bờ cao nhất (pt, nhân cỡ sóng).
    static let washMax = 14.0
    static let wetPeak = 0.3
    /// Bước lấy mẫu mép sóng (pt) / số khung keyframe iOS trên cả đời sóng.
    static let step = 8.0
    static let frames = 64
    /// Cỡ sóng theo mức combo 0…3.
    static let sizes: [Double] = [1.0, 1.2, 1.4, 1.65]

    static func size(level: Int) -> Double { sizes[Swift.min(Swift.max(level, 0), sizes.count - 1)] }
    /// Sóng mới chỉ khi sóng trước đã đi được `launchGap` (gõ dồn ⇒ chỉ bọt + bong bóng).
    static func shouldLaunch(sinceLast dt: Double) -> Bool { dt >= launchGap }
    /// Tỉ lệ quãng đỉnh → bờ của mép sóng: sóng lừng — khởi chậm (tốc độ 0,3), đều giữa chừng, nhanh dần CHÚT trước khi
    /// chạm bờ (tốc độ cuối 1,5; u² cũ = 0 → 2 như rơi). f(u) = 0,3u + 0,9u² − 0,2u³: f′ > 0, f″ > 0 trên [0, 1].
    static func travel(_ t: Double) -> Double {
        guard t > 0 else { return 0 }
        guard t < roll else { return 1 }
        let u = t / roll
        return u * (0.3 + u * (0.9 - 0.2 * u))
    }
    static func driftX(_ t: Double) -> Double { drift * Swift.min(Swift.max(t / roll, 0), 1) }
    /// Pha mép sóng của ô sóng `slot` (mỗi con sóng một dáng).
    static func phase(_ slot: Int) -> Double { Double(abs(slot) % 7) * 0.9 }
    /// Mép sóng (lệch y, pt) tại x — hai điều hoà lệch pha ⇒ đỉnh nhọn lệch như sóng sắp cuộn.
    static func crestOffset(_ x: Double, phase: Double) -> Double {
        let th = 2 * Double.pi * x / wavelength + phase
        return crestAmp * (sin(th) + 0.3 * sin(2 * th + 0.6))
    }
    /// Mép trên thân sóng (gốc = mép sóng).
    static func bodyTop(_ x: Double, phase: Double) -> Double { -bodyHeight + 0.5 * crestOffset(x + wavelength / 3, phase: phase) }
    /// Mép trên bọt tràn / vệt ướt (gốc = đáy, cao washMax).
    static func washTop(_ x: Double, phase: Double) -> Double { -washMax + 0.4 * crestOffset(x, phase: phase + 1) }
    /// Độ đậm thân + mép sóng: đủ khi cuộn, tan trong lúc vỡ.
    static func waveAlpha(_ t: Double) -> Double {
        if t < 0 || t >= roll + breakTime { return 0 }
        if t < roll { return 1 }
        return 1 - (t - roll) / breakTime
    }
    /// Chiều cao bọt tràn ở bờ (pt): dâng nhanh khi vỡ, rút tuyến tính.
    static func washHeight(_ t: Double, size s: Double) -> Double {
        let a = t - roll
        if a <= 0 || t >= life { return 0 }
        if a < breakTime { let u = a / breakTime; return washMax * s * (1 - (1 - u) * (1 - u)) }
        return washMax * s * (1 - (a - breakTime) / recede)
    }
    /// Vệt ướt trên cát lúc nước rút: đậm nhất khi bọt bắt đầu rút, mờ về 0.
    static func wetAlpha(_ t: Double) -> Double {
        let a = t - roll - breakTime
        if a < 0 || t >= life { return 0 }
        return wetPeak * (1 - a / recede)
    }

    // Bọt bắn + bong bóng ở phím (mỗi lần bấm MỘT chùm, pool tapSlots chùm)
    static let dropletsPerTap = 3, bubblesPerTap = 2, tapSlots = 4
    static var layersPerTap: Int { dropletsPerTap + bubblesPerTap }
    static let dropletDx: [Double] = [-14, 3, 15]
    static let dropletPeak: [Double] = [16, 22, 13]
    static let dropletSink = 12.0, dropletDuration = 0.45, dropletRadius = 1.8
    /// Giọt `i` ở tỉ lệ thời gian f: vòng cung lên rồi rơi (gốc = phím).
    static func droplet(_ i: Int, _ f: Double) -> (x: Double, y: Double) {
        let k = Swift.min(Swift.max(f, 0), 1), j = i % dropletsPerTap
        return (dropletDx[j] * k, -dropletPeak[j] * 4 * k * (1 - k) + dropletSink * k * k)
    }
    static let bubbleDx: [Double] = [-5, 6]
    static let bubbleRise: [Double] = [44, 56]
    static let bubbleDuration = 0.9, bubbleRadius = 3.5, bubbleSway = 3.5
    /// Bong bóng vỡ: từ popAt phồng tới popScale + tan (vòng "póc").
    static let popAt = 0.85, popScale = 1.8
    static func bubble(_ i: Int, _ f: Double) -> (x: Double, y: Double, scale: Double, alpha: Double) {
        let k = Swift.min(Swift.max(f, 0), 1), j = i % bubblesPerTap
        let e = 1 - (1 - k) * (1 - k)
        let x = bubbleDx[j] + bubbleSway * sin(2 * Double.pi * 1.5 * k + Double(j) * Double.pi)
        let y = -bubbleRise[j] * e
        if k < popAt { return (x, y, 0.6 + 0.4 * k / popAt, 1) }
        let p = (k - popAt) / (1 - popAt)
        return (x, y, 1 + (popScale - 1) * p, 1 - p)
    }

    // Cá bơi khi gõ combo
    static let fishLevel = 2
    static let fishCooldown = 4.0, fishDuration = 2.8, fishSize = 24.0, fishMargin = 14.0, fishBob = 3.0
    static let fishGlyphs = ["🐟", "🐠"]
    /// Cá bơi khi mức combo VỪA lên tới fishLevel và đã nghỉ cá ≥ fishCooldown.
    static func fishShouldSwim(level: Int, previous: Int, sinceLastFish: Double) -> Bool {
        level >= fishLevel && previous < fishLevel && sinceLastFish >= fishCooldown
    }
    static func fishRightToLeft(_ seq: Int) -> Bool { seq % 2 == 0 }
    static func fishY(_ seq: Int, height: Double) -> Double { height * (0.25 + 0.35 * fxValue(fxStep(fxSeed(seq &* 29 &+ 5)))) }
    static func fishX(_ f: Double, width: Double, rightToLeft: Bool) -> Double {
        let k = Swift.min(Swift.max(f, 0), 1), a = fishMargin, b = Swift.max(width - fishMargin, fishMargin)
        return rightToLeft ? b + (a - b) * k : a + (b - a) * k
    }
    static func fishBobY(_ f: Double) -> Double { fishBob * sin(2 * Double.pi * 3 * f) }
    static func fishAlpha(_ f: Double) -> Double {
        guard f >= 0, f < 1 else { return 0 }
        return Swift.min(1, f / 0.1, (1 - f) / 0.1)
    }

    // Tiếng sóng vỗ (KeySoundSynth.surfSamples): MỖI CON SÓNG MỚI một tiếng (không mỗi phím), chỉ khi Âm thanh phím bật.
    /// Tối đa bấy nhiêu tiếng sóng chồng nhau (tiếng 1,6 s, sóng cách ≥ launchGap ⇒ ≤ 2) — tiếng thứ 3 thay tiếng cũ nhất.
    static let surfVoices = 2
    static func shouldSurf(customSound: Bool) -> Bool { customSound }
    /// Âm lượng tiếng sóng theo cỡ sóng: cỡ thường 0,7 → cỡ combo lớn nhất 1,0 (nhân âm lượng phím của user).
    static func surfVolume(size s: Double) -> Double {
        0.7 + 0.3 * Swift.min(Swift.max((s - 1) / (sizes[sizes.count - 1] - 1), 0), 1)
    }
}

// MARK: - Theme "Mưa đêm" (11/2026): Mưa

/// "Mưa" (theme Mưa đêm): mưa đêm êm trên ô kính — chậm, dịu, ấm dần.
///  • Mưa nền: khi đang gõ, vài hạt mưa có vệt trượt xuống "ô kính" (cả bàn phím, rất mờ), trượt — dừng — trượt tiếp
///    (`profiles`), tối đa `maxDrops`; hạt mới chỉ sinh lúc bấm phím, cách nhau ≥ `spawnGap(intensity:)` ⇒ ngừng gõ thì
///    các hạt đang trượt chạy nốt (`dropLife` = `idleAfter`) rồi thôi — nghỉ = 0 animation / 0 khung hình.
///  • Bấm phím: một giọt rơi xuống đúng phím, loang một vòng nhỏ, rồi lăn xuống để lại vệt ướt ngắn mờ dần.
///  • Mưa tạnh dần: mỗi lần bàn phím hiện mưa đậm (1.0); cứ `stepKeys` phím mưa thưa đi `stepDrop` (sàn
///    `floorIntensity`), ánh đèn vàng ấm ở góc dưới phải sáng dần 0 → `glowMax`. Ẩn bàn phím ⇒ về đầu.
/// Hàm thuần song sinh android RainFx.kt — CÙNG SỐ (test chéo hai nền tảng). Thời gian giây, đơn vị pt (Android dp).
enum RainFx {
    // Mưa tạnh dần
    static let stepKeys = 40
    static let stepDrop = 0.1
    static let floorIntensity = 0.2
    /// Độ đậm của mưa sau `keys` phím kể từ lúc bàn phím hiện: 1.0 → giảm `stepDrop` mỗi `stepKeys` phím, sàn 0.2.
    static func intensity(keys: Int) -> Double {
        let steps = Swift.max(keys, 0) / stepKeys
        return Swift.max(floorIntensity, 1 - stepDrop * Double(steps))
    }
    /// Ánh đèn ấm: 0 khi mưa đậm nhất → `glowMax` khi mưa thưa tới sàn (tuyến tính theo độ thưa).
    static let glowMax = 0.6
    static func glow(keys: Int) -> Double { glowMax * (1 - intensity(keys: keys)) / (1 - floorIntensity) }
    /// Chuyển độ sáng đèn khi mưa thưa một nấc: êm (smoothstep) trong `glowFade` giây — không bao giờ nháy.
    static let glowFade = 1.5
    static func glowAt(from a: Double, to b: Double, t: Double) -> Double {
        let u = Swift.min(Swift.max(t / glowFade, 0), 1)
        return a + (b - a) * u * u * (3 - 2 * u)
    }
    /// Đèn: màu vàng hổ phách, tâm gần góc dưới phải, bán kính theo cỡ bàn phím; độ đậm theo bán kính (0…1).
    static let glowColor: UInt32 = 0xFFB25C
    static let glowStops: [(location: Double, alpha: Double)] = [(0, 0.42), (0.45, 0.17), (1, 0)]
    static func glowCenter(width w: Double, height h: Double) -> (x: Double, y: Double) { (w * 0.9, h * 0.94) }
    static func glowRadius(width w: Double, height h: Double) -> Double { Swift.min(0.55 * w, 0.9 * h) }

    // Mưa nền
    static let maxDrops = 12
    /// Đời một hạt mưa nền (trượt từ trên xuống hết ô kính) = ngưỡng nghỉ: ngừng gõ `idleAfter` giây là hết hạt.
    static let dropLife = 3.0
    static let idleAfter = 3.0
    static let baseGap = 0.25
    /// Khoảng cách tối thiểu giữa hai hạt mưa nền: mưa thưa ⇒ hạt thưa (0,25 s → 1,25 s).
    static func spawnGap(intensity i: Double) -> Double { baseGap / Swift.max(i, floorIntensity) }
    static func shouldSpawn(sinceLast dt: Double, intensity i: Double) -> Bool { dt >= spawnGap(intensity: i) - 1e-9 }
    /// Số hạt cùng lúc nhiều nhất ở độ đậm `i` (≤ `maxDrops`).
    static func maxInFlight(intensity i: Double) -> Int {
        Swift.min(maxDrops, Int((dropLife / spawnGap(intensity: i) - 1e-9).rounded(.up)))
    }
    static func isIdle(sinceLastKey dt: Double) -> Bool { dt >= idleAfter }
    /// Ba kiểu trượt (tỉ lệ thời gian, tỉ lệ quãng): trượt — đọng lại (bò rất chậm) — trượt — đọng — trượt hết kính.
    static let profiles: [[(t: Double, y: Double)]] = [
        [(0, 0), (0.18, 0.22), (0.40, 0.25), (0.58, 0.55), (0.74, 0.57), (1, 1)],
        [(0, 0), (0.25, 0.34), (0.50, 0.37), (0.66, 0.66), (0.80, 0.68), (1, 1)],
        [(0, 0), (0.12, 0.14), (0.34, 0.16), (0.55, 0.48), (0.72, 0.50), (1, 1)],
    ]
    static func profile(slot: Int) -> Int { ((slot % profiles.count) + profiles.count) % profiles.count }
    /// Tỉ lệ quãng đã trượt ở tỉ lệ thời gian `f` (nội suy tuyến tính giữa các mốc).
    static func travel(_ f: Double, profile p: Int) -> Double {
        let k = profiles[((p % profiles.count) + profiles.count) % profiles.count]
        if f <= 0 { return 0 }
        if f >= 1 { return 1 }
        for i in 1..<k.count where f <= k[i].t {
            let a = k[i - 1], b = k[i]
            return a.y + (b.y - a.y) * (f - a.t) / (b.t - a.t)
        }
        return 1
    }
    /// Hạt mưa nền xuất phát trên mép trên `startAbove` pt và trượt quá mép dưới `overshoot` pt (vệt ra hết khỏi kính).
    static let startAbove = 4.0
    static let overshoot = 18.0
    static func travelDistance(height h: Double) -> Double { h + startAbove + overshoot }
    static let dropPeakAlpha = 0.45
    static func dropAlpha(_ f: Double) -> Double {
        guard f >= 0, f < 1 else { return 0 }
        return dropPeakAlpha * Swift.min(1, f / 0.06, (1 - f) / 0.1)
    }
    static let dropMargin = 10.0
    /// Hoành độ hạt mưa nền thứ `seq` (từ mép trái bàn phím).
    static func dropX(seq: Int, width w: Double) -> Double {
        let span = Swift.max(w - 2 * dropMargin, 0)
        return dropMargin + span * fxValue(fxStep(fxSeed(seq &* 37 &+ 11)))
    }
    /// Hạt mưa nền: đầu giọt elip (bán kính ngang, dọc) + vệt nước phía trên (dài, rộng, độ đậm tương đối).
    static let headRX = 1.5, headRY = 2.1
    static let streakLength = 16.0, streakWidth = 1.0, streakAlpha = 0.55

    // Giọt ở phím
    static let tapSlots = 6
    /// Giọt + vòng loang + vệt ướt.
    static let layersPerTap = 3
    static let fallTime = 0.12
    static let fallFrom = 16.0
    static let rollStart = 0.2
    static let rollTime = 1.1
    static let rollDistance = 30.0
    static let rollWiggle = 2.5
    static let trailFade = 0.8
    static var tapLife: Double { rollStart + rollTime + trailFade }
    static let tapDropRadius = 2.2
    static let tapDropAlpha = 0.9
    /// Giọt ở phím (gốc = tâm phím, y xuống): rơi nhanh dần từ trên xuống, đọng ở tâm, rồi lăn xuống (nhanh dần, lắc nhẹ).
    static func drop(_ t: Double) -> (x: Double, y: Double, alpha: Double) {
        if t < 0 { return (0, -fallFrom, 0) }
        if t < fallTime { let u = t / fallTime; return (0, -fallFrom * (1 - u * u), tapDropAlpha) }
        if t < rollStart { return (0, 0, tapDropAlpha) }
        if t < rollStart + rollTime {
            let u = (t - rollStart) / rollTime
            return (rollX(u), rollDistance * u * u, tapDropAlpha * (u < 0.7 ? 1 : (1 - u) / 0.3))
        }
        return (rollX(1), rollDistance, 0)
    }
    static func rollX(_ u: Double) -> Double { rollWiggle * sin(Double.pi * u) }
    static let ringFrom = 1.5, ringTo = 11.0, ringTime = 0.4, ringAlpha = 0.7, ringWidth = 1.0
    /// Vòng loang khi giọt chạm phím: nở nhanh rồi chậm, mờ dần.
    static func ring(_ t: Double) -> (radius: Double, alpha: Double) {
        let a = t - fallTime
        guard a >= 0, a < ringTime else { return (0, 0) }
        let u = a / ringTime, e = 1 - (1 - u) * (1 - u)
        return (ringFrom + (ringTo - ringFrom) * e, ringAlpha * (1 - u))
    }
    static let trailAlpha = 0.35, trailWidth = 1.6
    /// Vệt ướt sau giọt lăn: phần đã lăn (tỉ lệ quãng, = y giọt / rollDistance) + độ đậm (mờ dần sau khi giọt lăn hết).
    static func trail(_ t: Double) -> (end: Double, alpha: Double) {
        let a = t - rollStart
        guard a >= 0 else { return (0, 0) }
        let u = Swift.min(a / rollTime, 1)
        if a < rollTime { return (u * u, trailAlpha) }
        let fade = (a - rollTime) / trailFade
        return fade < 1 ? (1, trailAlpha * (1 - fade)) : (1, 0)
    }
}

// MARK: - Theme "AI" (11/2026): Token AI

/// "Token AI": ĐÚNG chữ engine vừa ra (như Chữ bay — FlyingLetters.glyph) loé ở mép trên phím rồi VỠ thành 3…6 "token"
/// (chip bo tròn nhỏ, gradient phát sáng tím / lam / hồng) bay theo đường cong VÀO thanh gợi ý (tâm dải gợi ý, hoặc
/// Mắt AI nếu đang bật). Thanh gợi ý đổi gợi ý thật ⇒ một vệt sáng quét ngang MỘT lần (~0,3 s) — ShimmerGate.
/// Hàm thuần song sinh android KeyEffect.kt TokenStream — CÙNG SỐ (test chéo hai nền tảng).
enum TokenStream {
    /// Số chùm bay cùng lúc (xoay vòng — gõ nhanh hơn thì chùm cũ nhất bị bắn lại).
    static let pool = 4
    static let minChips = 3, maxChips = 6
    /// Trần chip đang có (mọi chùm) — không bao giờ quá.
    static var cap: Int { pool * maxChips }
    /// Chip (pt / dp): rộng × cao, bo.
    static let chipW = 7.0, chipH = 4.0, chipRadius = 2.0
    /// Màu chip (theo thứ tự chip): tím, lam ngọc, hồng — gradient chip i: màu i → màu i+1.
    static let colors: [UInt32] = [0xA855F7, 0x22D3EE, 0xF472B6]
    /// Chữ loé tại phím trước khi vỡ (giây) + cỡ chữ.
    static let glyphTime = 0.16
    static let glyphSize = 20.0
    /// Thời gian bay mỗi chip + trễ giữa hai chip liền nhau (chip đầu rời phím sau glyphTime / 2).
    static let flight = 0.55
    static let stagger = 0.035
    /// Chip toả ở điểm xuất phát (khoảng cách ngang giữa hai chip liền nhau).
    static let spread = 6.0
    /// Độ cong: điểm điều khiển lệch khỏi trung điểm ≤ `bend` (và ≤ 35 % quãng bay).
    static let bend = 42.0
    /// Điểm điều khiển / đích cách mép bàn phím ≥ `inset` ⇒ cả đường cong (bao lồi) nằm TRONG bàn phím (#151).
    static let inset = 2.0
    /// Co lại khi tới đích.
    static let endScale = 0.45

    /// Số chip cho chữ vừa ra: 3 + số dấu (NFD, tối đa 2) + chẵn/lẻ mã chữ gốc ⇒ 3…6. "b" 3, "a" 4, "đ" 4, "á" 5, "ế" 6.
    static func chipCount(_ glyph: String) -> Int {
        let scalars = Array(glyph.decomposedStringWithCanonicalMapping.unicodeScalars)
        guard let base = scalars.first else { return minChips }
        return Swift.min(maxChips, minChips + Swift.min(scalars.count - 1, 2) + Int(base.value % 2))
    }

    /// Hệ số toả của chip `i` trong `n` chip: −1…1 (giữa = 0).
    static func fan(_ i: Int, of n: Int) -> Double { n > 1 ? (Double(i) - Double(n - 1) / 2) / (Double(n - 1) / 2) : 0 }

    /// Điểm xuất phát chip `i`/`n` quanh mép trên phím `key`, kẹp trong khung `w`×`h`.
    static func start(key: (x: Double, y: Double), chip i: Int, of n: Int, width w: Double, height h: Double)
        -> (x: Double, y: Double) {
        clamp((key.x + (Double(i) - Double(n - 1) / 2) * spread, key.y), width: w, height: h)
    }

    /// Điểm điều khiển (Bézier bậc 2) — lệch VUÔNG GÓC khỏi trung điểm, cùng phía cho cả chùm (vòng cung vồng LÊN),
    /// chip ngoài cong hơn (toả quạt); kẹp trong khung ⇒ đường cong không bao giờ ra ngoài bàn phím.
    static func control(from p0: (x: Double, y: Double), to p1: (x: Double, y: Double), chip i: Int, of n: Int,
                        width w: Double, height h: Double) -> (x: Double, y: Double) {
        let dx = p1.x - p0.x, dy = p1.y - p0.y
        let len = hypot(dx, dy)
        guard len > 1e-9 else { return clamp(p0, width: w, height: h) }
        var nx = -dy / len, ny = dx / len
        if ny > 0 || (ny == 0 && nx < 0) { nx = -nx; ny = -ny }   // vồng lên (y nhỏ hơn); bay thẳng đứng ⇒ sang phải
        let k = Swift.min(bend, len * 0.35) * (0.55 + 0.45 * fan(i, of: n))
        return clamp(((p0.x + p1.x) / 2 + nx * k, (p0.y + p1.y) / 2 + ny * k), width: w, height: h)
    }

    /// Điểm trên đường bay tại tiến độ `t` (0…1, đã qua `ease`).
    static func point(_ p0: (x: Double, y: Double), _ c: (x: Double, y: Double), _ p1: (x: Double, y: Double), t: Double)
        -> (x: Double, y: Double) {
        let u = 1 - t
        return (u * u * p0.x + 2 * u * t * c.x + t * t * p1.x, u * u * p0.y + 2 * u * t * c.y + t * t * p1.y)
    }

    /// Kẹp điểm vào [inset, w − inset] × [inset, h − inset].
    static func clamp(_ p: (x: Double, y: Double), width w: Double, height h: Double) -> (x: Double, y: Double) {
        (Swift.min(Swift.max(p.x, inset), Swift.max(inset, w - inset)), Swift.min(Swift.max(p.y, inset), Swift.max(inset, h - inset)))
    }

    /// Trễ (giây, tính từ lúc bấm) của chip `i`.
    static func delay(_ i: Int) -> Double { glyphTime / 2 + Double(i) * stagger }
    /// Toàn bộ chùm xong sau (giây).
    static var lifetime: Double { delay(maxChips - 1) + flight }

    /// Tăng tốc dần vào đích (hút vào): t².
    static func ease(_ f: Double) -> Double { let x = Swift.min(Swift.max(f, 0), 1); return x * x }
    /// Độ đậm theo tiến độ bay `f`: hiện nhanh (12 %), giữ, tắt dần 75 % → 100 %.
    static func alpha(_ f: Double) -> Double {
        guard f >= 0, f <= 1 else { return 0 }
        if f < 0.12 { return f / 0.12 }
        return f < 0.75 ? 1 : (1 - f) / 0.25
    }
    static func scale(_ f: Double) -> Double { 1 - (1 - endScale) * Swift.min(Swift.max(f, 0), 1) }
}

/// Vệt sáng quét thanh gợi ý khi gợi ý ĐỔI THẬT (Token AI): cùng danh sách từ ⇒ không; rỗng ⇒ không; đổi quá dồn
/// (< `minGap` từ lần quét trước) ⇒ bỏ (không quét chồng). Chỉ overlay kiểu Token AI giữ — kiểu khác không có gì.
struct ShimmerGate {
    static let duration = 0.3
    static let minGap = 0.35
    /// Bề ngang vệt (tỉ lệ bề ngang dải gợi ý).
    static let band = 0.35
    static let peakAlpha = 0.35
    private(set) var words: [String] = []
    private var last = -Double.greatestFiniteMagnitude

    /// Gợi ý đang hiện là `w` lúc `t` (giây) ⇒ true = quét một lần.
    mutating func update(_ w: [String], at t: Double) -> Bool {
        guard w != words else { return false }
        words = w
        guard !w.isEmpty, t - last >= Self.minGap else { return false }
        last = t
        return true
    }
    mutating func reset() { words = []; last = -.greatestFiniteMagnitude }

    /// Mép trái vệt (theo bề ngang dải `w`) ở tiến độ `f` 0…1: từ ngoài trái (−band·w) tới ngoài phải (w).
    static func left(_ f: Double, width w: Double) -> Double {
        let b = band * w
        return -b + Swift.min(Swift.max(f, 0), 1) * (w + b)
    }
}

/// "Sàn nhảy LED" (theme Neon Night Club, 11/2026): phím vừa bấm + các ô quanh nó thắp neon hồng / tím / lục lam như
/// sàn nhảy LED — vòng 0 (chính phím) rồi vòng vuông 1, 2 lan ra cách nhau `ringDelay`, mỗi ô tắt trong `tileLife`. Ô
/// hàng xóm theo lưới bước = cỡ phím × (pitchX, pitchY) (≈ khe phím thật); phím rộng (cách / Enter) ⇒ ô hàng xóm rộng
/// tối đa 0,85 × cao, dời ra ngoài mép phím. Gõ dồn (ComboMeter mức 3) ⇒ cả bàn phím nháy một nhịp (trần 1,2 s, ≤ 120
/// ô). Chỉ vector. Hàm thuần — Android DanceFloor cùng số.
enum DanceFloor {
    static let rings = 3
    static let ringDelay = 0.06
    static let tileLife = 0.26
    static let peak = 0.55
    static let pitchX = 1.18
    static let pitchY = 1.28
    static let unitAspect = 0.85
    static let cornerFactor = 0.18
    /// Hồng, tím, lục lam (= SpotlightFx.colors).
    static let colors: [UInt32] = [0xFF2FD0, 0x9B5CFF, 0x2FE6FF]
    static let pool = 3
    static let flickerLevel = 3
    static let flickerCooldown = 1.2
    static let flickerDuration = 0.2
    static let flickerPeak = 0.22
    /// Trần số ô của lưới nháy cả bàn phím.
    static let maxGrid = 120

    struct Tile: Equatable { var ring: Int; var color: Int; var x: Double; var y: Double; var w: Double; var h: Double }

    static func ring(_ i: Int, _ j: Int) -> Int { Swift.max(abs(i), abs(j)) }
    static func colorIndex(_ i: Int, _ j: Int, seed: Int) -> Int { (((i - j + seed) % 3) + 3) % 3 }
    /// Độ sáng ô vòng `ring` sau `dt` giây kể từ lúc bấm: bật ngay khi tới lượt vòng, tắt (1−u)².
    static func alpha(_ dt: Double, ring: Int) -> Double {
        let t = dt - Double(ring) * ringDelay
        guard t >= 0, t < tileLife else { return 0 }
        let u = t / tileLife
        return peak * (1 - u) * (1 - u)
    }
    /// Toàn bộ chùm tắt hẳn sau (giây).
    static var lifetime: Double { Double(rings - 1) * ringDelay + tileLife }
    /// Nháy cả bàn phím: sáng 0–60 ms, tắt 60–100 ms, sáng lại rồi tắt dần tới 200 ms.
    static func flickerAlpha(_ dt: Double) -> Double {
        guard dt >= 0, dt < flickerDuration else { return 0 }
        if dt < 0.06 { return flickerPeak }
        if dt < 0.10 { return 0 }
        return flickerPeak * (1 - (dt - 0.10) / 0.10)
    }
    /// Cổng nháy cả bàn phím: chỉ ở mức combo ≥ `flickerLevel`, cách nhau ≥ `flickerCooldown`.
    struct FlickerGate {
        private(set) var last = -Double.greatestFiniteMagnitude
        private(set) var fired = 0
        mutating func trigger(level: Int, at t: Double) -> Bool {
            guard level >= DanceFloor.flickerLevel, t - last >= DanceFloor.flickerCooldown else { return false }
            last = t; fired += 1
            return true
        }
    }

    /// Bề rộng ô hàng xóm.
    static func unit(w: Double, h: Double) -> Double { Swift.min(w, h * unitAspect) }
    /// Tâm ô (i, j) quanh phím tâm (cx, cy) cỡ w × h.
    static func center(_ i: Int, _ j: Int, cx: Double, cy: Double, w: Double, h: Double) -> (x: Double, y: Double) {
        let u = unit(w: w, h: h)
        let sx = i == 0 ? 0 : (i > 0 ? 1.0 : -1.0)
        return (cx + sx * ((w - u) / 2 + Double(abs(i)) * u * pitchX), cy + Double(j) * h * pitchY)
    }

    /// Các ô vòng 0…rings−1 (vòng 0 = đúng khung phím), thứ tự hàng j rồi cột i (−2…2).
    static func tiles(cx: Double, cy: Double, w: Double, h: Double, seed: Int) -> [Tile] {
        var out: [Tile] = []
        let n = rings - 1, u = unit(w: w, h: h)
        for j in -n...n {
            for i in -n...n {
                let c = center(i, j, cx: cx, cy: cy, w: w, h: h)
                out.append(Tile(ring: ring(i, j), color: colorIndex(i, j, seed: seed), x: c.x, y: c.y,
                                w: i == 0 && j == 0 ? w : u, h: h))
            }
        }
        return out
    }

    /// Lưới phủ cả bàn phím (nháy combo) theo bước của phím vừa bấm — tâm ô nằm trong khung, trần `maxGrid` ô.
    static func grid(bounds b: (x: Double, y: Double, w: Double, h: Double), cx: Double, cy: Double, w: Double, h: Double,
                     seed: Int) -> [Tile] {
        let u = unit(w: w, h: h), px = u * pitchX, py = h * pitchY
        guard px > 1, py > 1, b.w > 0, b.h > 0 else { return [] }
        let i0 = Int(((b.x - cx) / px).rounded(.down)), i1 = Int(((b.x + b.w - cx) / px).rounded(.up))
        let j0 = Int(((b.y - cy) / py).rounded(.down)), j1 = Int(((b.y + b.h - cy) / py).rounded(.up))
        var out: [Tile] = []
        for j in j0...j1 {
            for i in i0...i1 {
                let x = cx + Double(i) * px, y = cy + Double(j) * py
                guard x >= b.x, x <= b.x + b.w, y >= b.y, y <= b.y + b.h, out.count < maxGrid else { continue }
                out.append(Tile(ring: 0, color: colorIndex(i, j, seed: seed), x: x, y: y, w: u, h: h))
            }
        }
        return out
    }
}

/// "Sàn nhảy LED" — cú FLASH stroboscope: bấm PHÍM CÁCH (hết một từ — trùng nhịp kick của âm Nhịp club) ⇒ lớp phủ
/// TOÀN bàn phím, SAU phím (nền / ảnh / nhân vật loé sáng, chữ phím vẫn đọc được), trắng ngả màu neon của nhịp, lên
/// `rise` rồi tắt (1−u)² trong `fall`. Phím chữ không flash. AN TOÀN cảm quang (WCAG 2.3.1): tối đa `maxPerSecond`
/// lần mỗi giây — cổng `Gate` dùng CHUNG với nhịp nháy cả bàn phím của DanceFloor; quá thì bỏ qua (sàn LED vẫn chạy).
/// Không phụ thuộc Giảm chuyển động. = Android BeatFlash.
enum BeatFlash {
    static let rise = 0.02
    static let fall = 0.11
    static var duration: Double { rise + fall }
    static let peak = 0.6
    static let maxPerSecond = 3
    static let window = 1.0
    /// Phần màu neon trộn vào trắng.
    static let tintMix = 0.35

    /// Độ đục sau `dt` giây kể từ cú flash.
    static func alpha(_ dt: Double) -> Double {
        guard dt >= 0, dt < duration else { return 0 }
        if dt < rise { return peak * dt / rise }
        let u = (dt - rise) / fall
        return peak * (1 - u) * (1 - u)
    }

    /// Màu nhịp thứ `i`: trắng trộn `tintMix` màu DanceFloor.colors[i % 3] (0xRRGGBB).
    static func tint(_ i: Int) -> UInt32 {
        let c = DanceFloor.colors[((i % DanceFloor.colors.count) + DanceFloor.colors.count) % DanceFloor.colors.count]
        func ch(_ sh: UInt32) -> UInt32 {
            let v = Double((c >> sh) & 0xFF)
            return UInt32((255 * (1 - tintMix) + v * tintMix).rounded()) << sh
        }
        return ch(16) | ch(8) | ch(0)
    }

    /// Cổng an toàn: ≤ `maxPerSecond` lần trong mọi khoảng `window` giây. Lớp tham chiếu — flash phím cách và nhịp
    /// nháy cả bàn phím (DanceFloor) dùng chung một cổng.
    final class Gate {
        private var times = [Double](repeating: -Double.greatestFiniteMagnitude, count: BeatFlash.maxPerSecond)
        private var head = 0
        private(set) var fired = 0
        func trigger(at t: Double) -> Bool {
            guard t - times[head] >= BeatFlash.window else { return false }
            times[head] = t
            head = (head + 1) % times.count
            fired += 1
            return true
        }
        func reset() {
            for i in times.indices { times[i] = -Double.greatestFiniteMagnitude }
            head = 0
        }
    }
}

/// Lớp flash của Sàn nhảy LED: MỘT view (layer = màu nền) tái dùng, KeyboardView chèn ngay DƯỚI hàng phím, khung =
/// bounds KeyboardView (chung hệ toạ độ #151). Animation opacity dựng MỘT lần, mỗi nhịp chỉ đổi màu + gắn lại.
/// Không nhận chạm, ẩn với VoiceOver. Kiểu khác ⇒ KeyboardView không giữ view này (0 chi phí).
final class BeatFlashView: UIView {
    let gate = BeatFlash.Gate()
    private var beat = 0
    private let anim: CAKeyframeAnimation = {
        let a = CAKeyframeAnimation(keyPath: "opacity")
        let steps = 13
        a.values = (0...steps).map { BeatFlash.alpha(BeatFlash.duration * Double($0) / Double(steps) * 0.9999) }
        a.keyTimes = (0...steps).map { NSNumber(value: Double($0) / Double(steps)) }
        a.duration = BeatFlash.duration
        a.isRemovedOnCompletion = true
        return a
    }()
    static let animKey = "fx.beat"

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        layer.opacity = 0
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { false }

    /// Nhịp phím cách: qua cổng an toàn ⇒ flash (true). Quá 3 lần / giây ⇒ bỏ qua (false).
    @discardableResult
    func kick(at t: CFTimeInterval = CACurrentMediaTime()) -> Bool {
        guard gate.trigger(at: t) else { return false }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.backgroundColor = UIColor(rgb: BeatFlash.tint(beat)).cgColor
        layer.add(anim, forKey: Self.animKey)
        CATransaction.commit()
        beat += 1
        return true
    }

    func halt() {
        layer.removeAnimation(forKey: Self.animKey)
        gate.reset()
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
/// "Rep" (theme Gym, 11/2026): thanh rep mảnh dọc mép trên bàn phím lấp MỘT nấc mỗi phím; đủ `perSet` phím = một hiệp ⇒ huy
/// hiệu "SET n ✓" đấm phồng rồi mờ, thanh rút về 0. Gõ nhanh (ComboMeter ≥ 1) ⇒ nhãn "+1 rep 💪" bay lên từ phím (pool
/// `labelCap`, dùng lại). Từ khoá ("gym", "tập", "beast mode"…) ⇒ chữ BEAST MODE đập xuống giữa bàn phím + một vòng sóng
/// xung kích (~1 s). Đếm hiệp về 0 khi ẩn bàn phím hoặc nghỉ `idleReset` giây. Mọi thứ nằm TRONG khung bàn phím (#151).
/// Đường cong là hàm thuần (keyframe tuyến tính) — iOS lấy mẫu làm CAKeyframeAnimation, Android vẽ Canvas: cùng số.
/// Android RepsFx y hệt.
enum RepsFx {
    static let perSet = 10
    static let idleReset = 60.0
    static let labelCap = 5
    static let labelText = "+1 rep 💪"
    static let slamText = "BEAST MODE"
    static func badgeText(set: Int) -> String { "SET \(set) ✓" }
    /// Thanh rep: cao (pt / dp), cách mép trên + lề hai bên.
    static let barHeight = 3.0
    static let barInset = 2.0
    /// Một nấc trượt; hết hiệp: đầy thêm `setHold` rồi rút về 0 trong `setDrain`.
    static let barStep = 0.12
    static let setHold = 0.45
    static let setDrain = 0.2
    static var setLife: Double { barStep + setHold + setDrain }
    /// Huy hiệu SET: tâm cách mép trên `badgeY`, cỡ chữ, thời lượng, mốc phồng / mờ.
    static let badgeY = 18.0
    static let badgeFont = 13.0
    static let badgeDuration = 0.9
    static let badgeTimes: [Double] = [0, 0.12, 0.22, 0.3, 0.7, 0.9]
    static let badgeScales: [Double] = [0.4, 1.25, 0.95, 1.0, 1.0, 1.0]
    static let badgeAlphas: [Double] = [0, 1, 1, 1, 1, 0]
    /// Nhãn "+1 rep 💪".
    static let labelDuration = 0.8
    static let labelRise = 38.0
    static let labelFont = 14.0
    static let labelHeight = 20.0
    static let labelHalfWidth = 40.0
    /// BEAST MODE: chữ đập (phồng 2.4 → 0.9 → 1.08 → 1) + vòng xung kích trễ `ringDelay`.
    static let slamDuration = 1.0
    static let slamTimes: [Double] = [0, 0.1, 0.18, 0.26, 0.8, 1.0]
    static let slamScales: [Double] = [2.4, 0.9, 1.08, 1.0, 1.0, 1.0]
    static let slamAlphas: [Double] = [0, 1, 1, 1, 1, 0]
    static let slamMaxFont = 30.0
    static let ringDelay = 0.1
    static let ringDuration = 0.5
    static let ringRadius = 44.0
    static let ringGrow = 1.6
    static let ringWidth = 3.0

    /// Bộ đếm rep / hiệp — hàm thuần (thời gian truyền vào, giây).
    struct Counter: Equatable {
        struct Event: Equatable { var fill: Int; var completedSet: Int? }
        private(set) var reps = 0
        private(set) var sets = 0
        private(set) var last = -Double.greatestFiniteMagnitude
        /// Một phím lúc `t`: nấc thanh sau phím (1…perSet) + số hiệp vừa xong (nil nếu chưa).
        mutating func press(at t: Double) -> Event {
            if isIdle(at: t) { reset() }
            last = t
            reps += 1
            if reps >= RepsFx.perSet { reps = 0; sets += 1; return Event(fill: RepsFx.perSet, completedSet: sets) }
            return Event(fill: reps, completedSet: nil)
        }
        func isIdle(at t: Double) -> Bool { t - last > RepsFx.idleReset }
        /// Ẩn bàn phím / nghỉ lâu ⇒ hiệp về 0.
        mutating func reset() { reps = 0; sets = 0; last = -Double.greatestFiniteMagnitude }
    }

    /// Nội suy tuyến tính theo mốc (kẹp hai đầu).
    static func keyframe(_ t: Double, _ ts: [Double], _ vs: [Double]) -> Double {
        guard let f = ts.first, t > f else { return vs[0] }
        for i in 1..<ts.count where t <= ts[i] {
            let u = (t - ts[i - 1]) / max(ts[i] - ts[i - 1], 1e-9)
            return vs[i - 1] + (vs[i] - vs[i - 1]) * u
        }
        return vs[vs.count - 1]
    }

    /// Phần thanh (0…1) sau `dt` giây kể từ phím: nấc `from` → `to`; hết hiệp (`to` = perSet) ⇒ đầy, giữ, rút về 0.
    static func barFill(from: Int, to: Int, dt: Double) -> Double {
        let a = Double(from) / Double(perSet), b = Double(to) / Double(perSet)
        if dt <= 0 { return a }
        if dt < barStep { return a + (b - a) * dt / barStep }
        guard to >= perSet else { return b }
        let u = dt - barStep - setHold
        if u < 0 { return 1 }
        return u < setDrain ? 1 - u / setDrain : 0
    }

    static func badgeScale(_ dt: Double) -> Double { keyframe(dt, badgeTimes, badgeScales) }
    static func badgeAlpha(_ dt: Double) -> Double { dt < 0 || dt >= badgeDuration ? 0 : keyframe(dt, badgeTimes, badgeAlphas) }
    static func slamScale(_ dt: Double) -> Double { keyframe(dt, slamTimes, slamScales) }
    static func slamAlpha(_ dt: Double) -> Double { dt < 0 || dt >= slamDuration ? 0 : keyframe(dt, slamTimes, slamAlphas) }

    /// Nhãn: độ lên (âm = lên), mờ, cỡ sau `dt` giây.
    static func labelDy(_ dt: Double) -> Double {
        let u = min(max(dt / labelDuration, 0), 1)
        return -labelRise * (1 - (1 - u) * (1 - u))
    }
    static func labelAlpha(_ dt: Double) -> Double {
        guard dt >= 0, dt < labelDuration else { return 0 }
        let u = dt / labelDuration
        return u < 0.15 ? u / 0.15 : (u > 0.6 ? (1 - u) / 0.4 : 1)
    }
    static func labelScale(_ dt: Double) -> Double { 0.8 + 0.25 * min(max(dt / labelDuration, 0) / 0.2, 1) }
    /// Lệch ngang nhẹ theo lần bắn (−8…8) — tất định.
    static func labelDrift(_ seed: Int) -> Double { Double(((seed % 5) + 5) % 5 - 2) * 4 }

    /// Vòng xung kích: hệ số bán kính + độ mờ sau `dt` giây kể từ cú đập.
    static func ringScale(_ dt: Double) -> Double {
        let u = min(max((dt - ringDelay) / ringDuration, 0), 1)
        return 0.3 + (ringGrow - 0.3) * (1 - (1 - u) * (1 - u))
    }
    static func ringAlpha(_ dt: Double) -> Double {
        let t = dt - ringDelay
        guard t >= 0, t < ringDuration else { return 0 }
        return 0.85 * (1 - t / ringDuration)
    }

    /// Bán kính vòng vừa khung (lớn nhất × ringGrow + nét vẫn trong bàn phím).
    static func ringRadius(width w: Double, height h: Double) -> Double { max(0, min(ringRadius, (min(w, h) / 2 - ringWidth) / ringGrow)) }
    /// Cỡ chữ BEAST MODE vừa bề ngang (10 ký tự đậm, chừa lề — phồng 1.08 vẫn trong khung).
    static func slamFont(width w: Double) -> Double { max(8, min(slamMaxFont, w / 8.5)) }

    /// Tâm xuất phát của nhãn (mép trên phím) — kẹp sao cho CẢ đường bay (lệch ngang, lên `labelRise`) nằm trong khung.
    static func labelOrigin(keyMidX: Double, keyTop: Double, seed: Int,
                            bounds b: (x: Double, y: Double, w: Double, h: Double)) -> (x: Double, y: Double) {
        let hw = labelHalfWidth, hh = labelHeight / 2
        let x = min(max(keyMidX + labelDrift(seed), b.x + hw), max(b.x + b.w - hw, b.x + hw))
        let y = min(max(keyTop, b.y + labelRise + hh), max(b.y + b.h - hh, b.y + labelRise + hh))
        return (x, y)
    }

    /// Từ khoá BEAST MODE. Cụm > 3 từ khớp theo 3 từ cuối ("no pain no gain" ⇒ "pain no gain").
    static let keywords = ["gym", "tập", "fit", "no pain no gain", "beast mode", "lên tạ"]
    private static let forms: Set<String> = Set(keywords.map { $0.split(separator: " ").suffix(3).joined(separator: " ") })
    private static func clean(_ s: String) -> String { s.trimmingCharacters(in: CharacterSet.letters.inverted).lowercased() }

    /// Từ vừa chốt `word` (+ hai từ liền trước) có kích BEAST MODE không — tra O(1) ở RANH GIỚI TỪ; đúng dấu ("tap" ≠ "tập").
    static func isKeyword(word: String, prev: String?, prev2: String?) -> Bool {
        let w = clean(word)
        guard !w.isEmpty, w.count <= 24 else { return false }
        if forms.contains(w) { return true }
        guard let p = prev.map(clean), !p.isEmpty else { return false }
        if forms.contains(p + " " + w) { return true }
        guard let p2 = prev2.map(clean), !p2.isEmpty else { return false }
        return forms.contains(p2 + " " + p + " " + w)
    }
}

final class KeyEffectOverlay: UIView {
    private(set) var effect: KeyEffect
    /// Kính vạn hoa: dựng lười ở phím đầu; kiểu khác ⇒ nil.
    private var kaleido: KaleidoFx?
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
    // Đợt 3
    private var arcs: [Arc] = []
    private var arcPool = KeyEffectPool(capacity: PlasmaArc.pool)
    private var plasma = PlasmaChain()
    private var plasmaSeq = 0
    /// Rung combo: layer hàng phím bị rung (install đặt = `keys`). Giảm chuyển động vẫn rung (như mọi hiệu ứng).
    weak var shakeTarget: UIView?
    private var shakeMeter = ShakeMeter()
    /// Laser: khung phím cách (toạ độ overlay) — nil ⇒ gốc giữa đáy.
    var laserOrigin: (() -> CGRect?)?
    private var beams: [Beam] = []
    private var beamPool = KeyEffectPool(capacity: LaserBeam.pool)
    private var glitches: [Glitch] = []
    private var glitchPool = KeyEffectPool(capacity: GlitchFx.pool)
    private var glitchSeq = 0
    private var pendingTone: ToneFx?
    private var toneRoots: [ToneFx: [CALayer]] = [:]
    private var toneCursor: [ToneFx: Int] = [:]
    private var pendingKeyword: KeywordKind?
    private var keywordRoots: [KeywordKind: [CALayer]] = [:]
    private var keywordCursor: [KeywordKind: Int] = [:]
    private var pendingLetter: String?
    private var letters: [CATextLayer] = []
    private var letterPool = KeyEffectPool(capacity: FlyingLetters.pool)
    private var sand: SandPile?
    private var sandPile: CAShapeLayer?
    private var grains: [CALayer] = []
    private var grainPool = KeyEffectPool(capacity: SandPile.flying)
    private var sandSeq = 0
    private var sandLast: CFTimeInterval = -.greatestFiniteMagnitude
    private var pendingLandings: [Double] = []
    private var sandSweepScheduled = false
    // Biển — sóng: pool maxWaves gốc dựng lười theo cỡ bàn phím (path + animation gắn MỘT lần), bấm chỉ đặt cỡ + beginTime.
    private var seaWaves: [SeaWave] = []
    private var seaBuiltFor: CGSize = .zero
    private var seaCursor = 0
    private var seaLastWave: CFTimeInterval = -.greatestFiniteMagnitude
    private var seaLevel = 0
    private var seaFish: CALayer?
    private var seaLastFish: CFTimeInterval = -.greatestFiniteMagnitude
    private var seaFishSeq = 0
    /// Biển: mỗi con sóng MỚI (không mỗi phím) — cỡ sóng. KeyboardView đặt khi kiểu là Biển ⇒ tiếng sóng vỗ (KeySound.playSurf).
    var onSeaWave: ((Double) -> Void)?
    // Token AI — pool chùm dựng lười (chữ + 6 chip mỗi chùm), vệt sáng dải gợi ý dựng lười ở lần gợi ý đổi đầu tiên.
    /// Đích bay (toạ độ overlay): tâm Mắt AI nếu đang bật, không thì tâm dải gợi ý — KeyboardView đặt khi kiểu là Token AI.
    var tokenTarget: (() -> CGPoint?)?
    private var pendingToken: String?
    private var tokenBursts: [TokenBurst] = []
    private var tokenPool = KeyEffectPool(capacity: TokenStream.pool)
    private var shimmerGate = ShimmerGate()
    private var shimmerClip: CALayer?
    private var shimmerBand: CAGradientLayer?
    // Sàn nhảy LED
    private var dances: [Dance] = []
    private var dancePool = KeyEffectPool(capacity: DanceFloor.pool)
    private var danceSeq = 0
    private var floorFlicker: Dance?
    private var flickerGate = DanceFloor.FlickerGate()
    /// Sàn nhảy LED: cổng an toàn chung với lớp flash phím cách (BeatFlashView.gate). nil ⇒ chỉ FlickerGate.
    var flashGate: BeatFlash.Gate?
    // Lạc trôi — Đường hầm (Drift.swift): dựng lười ở lần bắn đầu; kiểu khác ⇒ nil.
    private var tunnel: TunnelRings?
    // Công đức / Nắng qua kính (MeritGlass.swift) — dựng lười ở lần bấm đầu; kiểu khác ⇒ nil (0 chi phí).
    private var merit: MeritLayers?
    private var sunlight: SunlightLayers?
    /// Công đức: bộ đếm trong ngày (RAM) — giữ qua rebuild (đổi màu), chỉ nạp từ `meritStore` khi gắn kho.
    private var meritCounter = MeritCounter()
    /// Lệch múi giờ (giây) đọc MỘT lần lúc gắn kho / hiện bàn phím — mỗi phím chỉ cộng trừ số.
    private var meritOffset = TimeZone.current.secondsFromGMT()
    /// Công đức: nơi lưu bộ đếm (App Group) — KeyboardView đặt khi kiểu là Công đức; nil ⇒ chỉ đếm trong RAM (xem thử).
    var meritStore: MeritStore? {
        didSet {
            guard let st = meritStore, effect == .merit else { return }
            let v = st.load()
            meritCounter = MeritCounter(day: v.day, count: v.count)
            meritOffset = TimeZone.current.secondsFromGMT()
            refreshMeritCounter()
        }
    }
    #if DEBUG
    /// Test: giờ "bây giờ" (epoch giây) cho bộ đếm công đức — nil = Date().
    var debugMeritEpoch: (() -> Double)?
    #endif
    // Mưa — mưa nền: pool maxDrops hạt dựng lười theo cỡ bàn phím (animation gắn MỘT lần), bấm chỉ đặt x + beginTime;
    // đèn ấm: MỘT lớp gradient tròn, chỉ đổi độ đậm khi mưa thưa một nấc (một animation ngắn tự gỡ).
    private var rainDrops: [CALayer] = []
    private var rainBuiltFor: CGSize = .zero
    private var rainCursor = 0
    private var rainSeq = 0
    private var rainKeys = 0
    private var rainLastDrop: CFTimeInterval = -.greatestFiniteMagnitude
    private var rainLastKey: CFTimeInterval = -.greatestFiniteMagnitude
    private var rainGlow: CAGradientLayer?
    private var rainGlowLevel = 0.0
    private var rainSweepScheduled = false
    // Rep (theme Gym) — dựng lười lần bắn đầu; kiểu khác ⇒ không layer nào.
    private var repCounter = RepsFx.Counter()
    private var repFill = 0
    private var repLastMedia: CFTimeInterval = 0
    private var repSweepScheduled = false
    private var repBarTrack: CALayer?
    private var repBar: CALayer?
    private var repBadge: CALayer?
    private var repBadgeText: CATextLayer?
    private var repLabels: [CALayer] = []
    private var repLabelPool = KeyEffectPool(capacity: RepsFx.labelCap)
    private var repLabelImage: CGImage?
    private var repSeq = 0
    private var pendingSlam = false
    private var repSlam: CALayer?
    private var repSlamText: CATextLayer?
    private var repRing: CAShapeLayer?

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
        o.shakeTarget = effect == .shake ? keys : nil
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

    static let clipped: Set<KeyEffect> = [.plasma, .laser, .glitch, .tone, .keyword, .letters, .sand, .sea, .tokens, .dancefloor,
                                          .kaleido, .tunnel, .merit, .sunlight, .rain, .reps]

    private func applyBand() {
        // Trên phím (zPosition 0), dưới ô phóng to (BalloonView 10) và popup (11). Dải dưới phím: 0 +
        // thứ tự subview (ngay dưới hàng phím, trên nền / ảnh nền).
        layer.zPosition = effect.band == .belowKeys ? 0 : 5
        // Đợt 3: cắt theo bàn phím — tia / pháo / chữ không bao giờ vẽ ra ngoài (#151).
        clipsToBounds = effect.band == .belowKeys || effect == .flash || Self.clipped.contains(effect)
    }

    /// "Emoji theo chữ": controller tra bảng ở ranh giới từ (sau khi chốt) rồi xếp emoji — lần vẽ kế
    /// (cùng phím ranh giới) bắn nó.
    func queueEmoji(_ e: String) {
        guard effect == .emojiword else { return }
        pendingEmoji = e
    }

    /// "Dấu thanh": controller so từ trước/sau phím (ToneMarks.detect) — lần vẽ kế bắn tại phím đó.
    func queueTone(_ t: ToneFx) { if effect == .tone { pendingTone = t } }
    /// "Từ khoá": controller tra bảng ở ranh giới từ — lần vẽ kế (phím ranh giới) bắn chùm.
    func queueKeyword(_ k: KeywordKind) { if effect == .keyword { pendingKeyword = k } }
    /// "Chữ bay": chữ vừa ra (FlyingLetters.glyph) — lần vẽ kế thả từ phím vừa bấm.
    func queueLetter(_ g: String) { if effect == .letters { pendingLetter = g } }
    /// "Rep": từ vừa chốt là từ khoá gym (RepsFx.isKeyword) — lần vẽ kế đập chữ BEAST MODE + vòng xung kích.
    func queueBeastMode() { if effect == .reps { pendingSlam = true } }
    /// "Token AI": chữ vừa ra — lần vẽ kế loé tại phím rồi vỡ thành token bay vào thanh gợi ý.
    func queueToken(_ g: String) { if effect == .tokens { pendingToken = g } }

    /// "Token AI": thanh gợi ý vừa hiện `words` trong khung `bar` (toạ độ overlay). Chỉ đổi THẬT (ShimmerGate) mới quét
    /// một vệt sáng ~0,3 s; kiểu khác ⇒ return ngay (0 chi phí).
    func suggestionsChanged(_ words: [String], bar: CGRect) {
        guard effect == .tokens else { return }
        guard shimmerGate.update(words, at: CACurrentMediaTime()), bar.width > 0, bar.height > 0,
              window != nil || Self.drawsOffscreen else { return }
        fireShimmer(in: bar)
    }

    private var hasQueued: Bool {
        switch effect {
        case .emojiword: return pendingEmoji != nil
        case .tone: return pendingTone != nil
        case .keyword: return pendingKeyword != nil
        case .letters: return pendingLetter != nil
        case .tokens: return pendingToken != nil
        default: return true
        }
    }

    /// Ghi điểm (toạ độ overlay) — vẽ ở lượt runloop kế, SAU khi phím đã chèn chữ.
    func emit(at p: CGPoint) { emit(key: CGRect(origin: p, size: .zero)) }

    /// Ghi khung phím (toạ độ overlay) — vẽ ở lượt runloop kế, SAU khi phím đã chèn chữ.
    func emit(key r: CGRect) {
        #if DEBUG
        let t0 = CACurrentMediaTime()
        defer { Self.debugCost += CACurrentMediaTime() - t0 }
        #endif
        if effect.isQueued && !hasQueued { return }   // Emoji / Dấu thanh / Từ khoá / Chữ bay: không có sự kiện ⇒ không hẹn gì
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
            pendingEmoji = nil; pendingTone = nil; pendingKeyword = nil; pendingLetter = nil; pendingToken = nil
            pendingSlam = false
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let media = CACurrentMediaTime()
        let now = layer.convertTime(media, from: nil)
        if effect == .emojiword {
            if let e = pendingEmoji, let r = pending.last { fireEmoji(e, at: r, now: now) }
            pendingEmoji = nil
        } else if effect == .tone {
            if let t = pendingTone, let r = pending.last { fireTone(t, at: r, now: now) }
            pendingTone = nil
        } else if effect == .keyword {
            if let k = pendingKeyword, let r = pending.last { fireKeyword(k, at: r, now: now) }
            pendingKeyword = nil
        } else if effect == .letters {
            if let g = pendingLetter, let r = pending.last { fireLetter(g, at: r, now: now) }
            pendingLetter = nil
        } else if effect == .tokens {
            if let g = pendingToken, let r = pending.last { fireToken(g, at: r, now: now) }
            pendingToken = nil
        } else {
            for r in pending { fire(r, now: now, media: media) }
            if pendingSlam { pendingSlam = false; fireSlam(now: now) }
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
        if repBarTrack != nil { layoutRepBar() }
        if let l = sandPile {
            let f = CGRect(x: bounds.minX, y: bounds.maxY - CGFloat(SandPile.maxHeight) - 1,
                           width: bounds.width, height: CGFloat(SandPile.maxHeight) + 1)
            if l.frame != f, l.animation(forKey: "sink") == nil { l.frame = f }
        }
        CATransaction.commit()
        if effect == .matrix, matrixClock.running, bounds.size != matrixBuiltFor { restartMatrixColumns() }
        if effect == .merit { refreshMeritCounter() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Bàn phím ẩn ⇒ Matrix dừng hẳn (không còn animation nào).
        if window == nil { halt() } else if effect == .merit {
            DispatchQueue.main.async { [weak self] in self?.refreshMeritCounter() }   // phím cách đã layout
        }
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
    /// Đợt 3: mọi layer gốc đã dựng (để kiểm trần + trong khung bàn phím) + trạng thái.
    var debugFx3Roots: [CALayer] {
        arcs.map(\.root) + beams.map(\.root) + glitches.map(\.root) + Array(toneRoots.values.joined())
            + Array(keywordRoots.values.joined()) + letters + grains + (sandPile.map { [$0] } ?? [])
    }
    var debugSand: SandPile? { sand }
    var debugSandLayer: CAShapeLayer? { sandPile }
    func debugLandSand() { landSand() }
    var debugLetters: [CATextLayer] { letters }
    /// Kính vạn hoa: gốc các bông đã dựng (pool).
    var debugKaleidoRoots: [CALayer] { kaleido?.roots ?? [] }
    /// Biển: gốc các con sóng đã dựng + cỡ (scale dọc) từng con + cá (nil nếu chưa bơi lần nào).
    var debugSeaWaveRoots: [CALayer] { seaWaves.map(\.root) }
    var debugSeaWaveSizes: [CGFloat] { seaWaves.map { $0.wave.transform.m22 } }
    var debugSeaFish: CALayer? { seaFish }
    /// Token AI: gốc các chùm đã dựng (pool) + số chip đang hiện của từng chùm + đường bay (điểm đầu / điều khiển / đích).
    var debugTokenRoots: [CALayer] { tokenBursts.map(\.root) }
    var debugTokenChipCounts: [Int] { tokenBursts.map { $0.chips.filter { !$0.isHidden }.count } }
    var debugTokenLayerCount: Int { tokenBursts.reduce(0) { $0 + 1 + $1.chips.count * 2 + 1 } }
    var debugTokenPaths: [CGPath] { tokenBursts.flatMap { b in b.chips.compactMap { ($0.animation(forKey: "fx") as? CAAnimationGroup)?.animations?.compactMap { ($0 as? CAKeyframeAnimation)?.path }.first } } }
    var debugShimmerLayer: CAGradientLayer? { shimmerBand }
    var debugShimmerFrame: CGRect? { shimmerClip?.frame }
    /// Sàn nhảy LED: gốc các chùm ô đã dựng (pool) + lớp nháy cả bàn phím (nil = chưa nháy lần nào).
    var debugDanceRoots: [CALayer] { dances.map(\.root) }
    /// Mưa: hạt mưa nền đã dựng (pool) + số đang hiện, số phím đã gõ, độ đậm mưa, độ sáng đèn (đích) + lớp đèn.
    var debugRainDrops: [CALayer] { rainDrops }
    var debugRainVisibleDrops: Int { rainDrops.filter { !$0.isHidden }.count }
    var debugRainKeys: Int { rainKeys }
    var debugRainIntensity: Double { RainFx.intensity(keys: rainKeys) }
    var debugRainGlowLevel: Double { rainGlowLevel }
    var debugRainGlow: CAGradientLayer? { rainGlow }
    func debugRainSweep() { sweepRain(force: true) }
    var debugFloorFlicker: CALayer? { floorFlicker?.root }
    /// Đường hầm: pool vòng (nil = chưa bắn lần nào).
    var debugTunnel: TunnelRings? { tunnel }
    /// Công đức / Nắng qua kính: lớp đã dựng (nil = chưa bấm lần nào / kiểu khác) + bộ đếm.
    var debugMerit: MeritLayers? { merit }
    var debugMeritCounter: MeritCounter { meritCounter }
    var debugSunlight: SunlightLayers? { sunlight }
    /// Rep: bộ đếm, nấc thanh đang hiện, các layer đã dựng (thanh, huy hiệu, chữ đập, nhãn), chữ huy hiệu.
    var debugRepCounter: RepsFx.Counter { repCounter }
    var debugRepFill: Int { repFill }
    var debugRepBarTrack: CALayer? { repBarTrack }
    var debugRepBar: CALayer? { repBar }
    var debugRepBadge: CALayer? { repBadge }
    var debugRepBadgeText: String? { repBadgeText?.string as? String }
    var debugRepLabels: [CALayer] { repLabels }
    var debugRepSlam: CALayer? { repSlam }
    var debugRepSlamText: CATextLayer? { repSlamText }
    var debugRepRing: CAShapeLayer? { repRing }
    func debugSweepReps(idleFor s: Double) { repLastMedia = CACurrentMediaTime() - s; repSweepScheduled = false; sweepReps() }
    #else
    static let drawsOffscreen = false
    #endif

    // MARK: bắn

    private func fire(_ r: CGRect, now: CFTimeInterval, media: CFTimeInterval) {
        let c = CGPoint(x: r.midX, y: r.midY)
        switch effect {
        case .none, .emojiword, .tone, .keyword, .letters, .tokens: return
        case .float: return     // Lơ lửng: KeyboardView.keyFloat lo (không vẽ gì trên overlay)
        case .tunnel:
            let t = tunnel ?? TunnelRings(host: layer)
            tunnel = t
            t.fire(key: r, bounds: bounds, level: combo.press(at: media), media: media)
        case .plasma: firePlasma(c, now: now, media: media)
        case .shake: fireShake(media: media)
        case .laser: fireLaser(c, now: now)
        case .kaleido:
            let k = kaleido ?? KaleidoFx(host: layer)
            kaleido = k
            k.fire(at: c, bounds: bounds, now: now)
        case .glitch: fireGlitch(r, now: now)
        case .sand: fireSand(c, now: now, media: media)
        case .sea: fireSea(c, now: now, media: media)
        case .dancefloor: fireDance(r, now: now, media: media)
        case .merit: fireMerit(r, now: now, media: media)
        case .sunlight:
            let s = sunlight ?? SunlightLayers(host: layer)
            sunlight = s
            s.fire(key: r, bounds: bounds, now: now, media: media)
        case .rain: fireRain(c, now: now, media: media)
        case .reps: fireRep(r, now: now, media: media)
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
        kaleido?.halt()
        haltMatrix()
        pendingEmoji = nil; pendingTone = nil; pendingKeyword = nil; pendingLetter = nil; pendingToken = nil
        for l in strings { l.removeAllAnimations() }
        for b in tokenBursts { b.root.isHidden = true }   // Token AI: ẩn bàn phím ⇒ không còn chip / vệt nào
        shimmerBand?.removeAllAnimations()
        shimmerGate.reset()
        shakeTarget?.layer.removeAnimation(forKey: Self.shakeKey)
        plasma.reset()
        clearSand()                       // ẩn bàn phím ⇒ đống cát về 0
        haltSea()
        tunnel?.halt()
        sunlight?.halt()
        persistMerit(force: true)         // ẩn bàn phím ⇒ ghi nốt công đức chưa lưu
        haltRain()                        // ẩn bàn phím ⇒ mưa về đậm, đèn tắt, không còn hạt nào
        resetReps()                       // ẩn bàn phím ⇒ hiệp về 0
    }

    // MARK: Công đức

    private var meritEpoch: Double {
        #if DEBUG
        if let f = debugMeritEpoch { return f() }
        #endif
        return Date().timeIntervalSince1970
    }

    private func fireMerit(_ r: CGRect, now: CFTimeInterval, media: CFTimeInterval) {
        let m = merit ?? MeritLayers(host: layer)
        merit = m
        m.fire(key: r, bounds: bounds, now: now)
        let day = MeritCounter.dayIndex(epoch: meritEpoch, utcOffset: meritOffset)
        if meritCounter.press(day: day, at: media) { meritStore?.save(meritCounter.day, meritCounter.count) }
        m.showCounter(meritCounter.count, anchor: laserOrigin?())
    }

    private func persistMerit(force: Bool) {
        guard effect == .merit, let st = meritStore, meritCounter.takeDirty() || !force else { return }
        st.save(meritCounter.day, meritCounter.count)
    }

    /// Nhãn đếm trên phím cách theo khung hiện tại (hiện / đổi bố cục) — kiểu khác ⇒ 0 việc.
    private func refreshMeritCounter() {
        guard effect == .merit, meritStore != nil else { return }
        let m = merit ?? MeritLayers(host: layer)
        merit = m
        let day = MeritCounter.dayIndex(epoch: meritEpoch, utcOffset: meritOffset)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        m.showCounter(meritCounter.today(day), anchor: laserOrigin?())
        CATransaction.commit()
    }

    // MARK: Đợt 3 — Plasma, Rung combo, Laser, Glitch, Dấu thanh, Từ khoá, Chữ bay, Hạt cát
    // Cùng kiểu: layer dựng lười theo pool, animation gắn MỘT lần, bấm chỉ đặt hình/vị trí + beginTime.

    private final class Arc {
        let root = CALayer()
        let glow = CAShapeLayer()
        let core = CAShapeLayer()
        let spark = CAShapeLayer()
    }

    private func firePlasma(_ c: CGPoint, now: CFTimeInterval, media: CFTimeInterval) {
        let slot = arcPool.next()
        let a: Arc
        if slot < arcs.count { a = arcs[slot] } else { a = makeArc(); arcs.append(a) }
        let link = plasma.press((Double(c.x), Double(c.y)), at: media)
        if link {
            plasmaSeq += 1
            let p = CGMutablePath()
            for (i, q) in PlasmaArc.points(from: plasma.prev, to: (Double(c.x), Double(c.y)),
                                           variant: plasmaSeq % PlasmaArc.variants).enumerated() {
                if i == 0 { p.move(to: CGPoint(x: q.x, y: q.y)) } else { p.addLine(to: CGPoint(x: q.x, y: q.y)) }
            }
            a.glow.path = p; a.core.path = p
        } else {
            a.glow.path = nil; a.core.path = nil
        }
        a.spark.position = c
        a.root.beginTime = now
        a.root.isHidden = false
    }

    private func makeArc() -> Arc {
        let a = Arc()
        a.root.bounds = .zero
        a.root.position = .zero
        a.root.isHidden = true
        a.root.opacity = 0
        for (l, w, c) in [(a.glow, CGFloat(5), UIColor(rgb: PlasmaArc.color).withAlphaComponent(0.5)),
                          (a.core, CGFloat(1.5), UIColor(rgb: PlasmaArc.core))] {
            l.fillColor = nil; l.strokeColor = c.cgColor; l.lineWidth = w
            l.lineJoin = .round; l.lineCap = .round
            a.root.addSublayer(l)
        }
        let r = CGFloat(PlasmaArc.sparkRadius)
        a.spark.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r), transform: nil)
        a.spark.fillColor = UIColor(rgb: PlasmaArc.color).withAlphaComponent(0.45).cgColor
        a.root.addSublayer(a.spark)
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 1, 0]; fade.keyTimes = [0, 0.3, 1]
        a.root.add(Self.group([fade], duration: PlasmaArc.duration, delay: 0), forKey: "fx")
        layer.addSublayer(a.root)
        return a
    }

    /// Rung combo: animation CỘNG DỒN trên layer hàng phím (model — khung nhận chạm — không đổi), tự gỡ khi xong.
    private func fireShake(media: CFTimeInterval) {
        let amp = ShakeFx.amplitude(level: shakeMeter.press(at: media))
        guard amp > 0, let target = shakeTarget else { return }
        let a = CAKeyframeAnimation(keyPath: "position")
        a.isAdditive = true
        a.values = zip(ShakeFx.xs, ShakeFx.ys).map { NSValue(cgPoint: CGPoint(x: $0 * amp, y: $1 * amp)) }
        a.duration = ShakeFx.duration
        a.isRemovedOnCompletion = true
        target.layer.add(a, forKey: Self.shakeKey)
    }
    static let shakeKey = "fx.shake"

    private final class Beam {
        let root = CALayer()
        let glow = CAShapeLayer()
        let core = CAShapeLayer()
        let flare = CAShapeLayer()
    }

    private func fireLaser(_ c: CGPoint, now: CFTimeInterval) {
        let origin: CGPoint
        if let s = laserOrigin?() {
            guard LaserBeam.fires(space: s, key: c) else { return }
            origin = CGPoint(x: s.midX, y: s.minY)
        } else {
            origin = CGPoint(x: bounds.midX, y: bounds.maxY - CGFloat(LaserBeam.fallbackInset))
        }
        let slot = beamPool.next()
        let b: Beam
        if slot < beams.count { b = beams[slot] } else { b = makeBeam(); beams.append(b) }
        let p = CGMutablePath()
        p.move(to: origin); p.addLine(to: c)
        b.glow.path = p; b.core.path = p
        b.flare.position = c
        b.root.beginTime = now
        b.root.isHidden = false
    }

    private func makeBeam() -> Beam {
        let b = Beam()
        b.root.bounds = .zero
        b.root.position = .zero
        b.root.isHidden = true
        b.root.opacity = 0
        let travel = LaserBeam.travel / LaserBeam.duration
        for (l, w, c) in [(b.glow, CGFloat(LaserBeam.glowWidth), UIColor(rgb: LaserBeam.color).withAlphaComponent(0.55)),
                          (b.core, CGFloat(LaserBeam.coreWidth), UIColor.white)] {
            l.fillColor = nil; l.strokeColor = c.cgColor; l.lineWidth = w; l.lineCap = .round
            let draw = CAKeyframeAnimation(keyPath: "strokeEnd")
            draw.values = [0, 1, 1]; draw.keyTimes = [0, NSNumber(value: travel), 1]
            l.add(Self.group([draw], duration: LaserBeam.duration, delay: 0), forKey: "fx")
            b.root.addSublayer(l)
        }
        b.flare.path = CGPath(ellipseIn: CGRect(x: -6, y: -6, width: 12, height: 12), transform: nil)
        b.flare.fillColor = UIColor(rgb: LaserBeam.color).withAlphaComponent(0.5).cgColor
        b.flare.opacity = 0
        let pop = CAKeyframeAnimation(keyPath: "opacity")
        pop.values = [0, 0, 1, 0]; pop.keyTimes = [0, NSNumber(value: travel), NSNumber(value: travel + 0.01), 1]
        b.flare.add(Self.group([pop], duration: LaserBeam.duration, delay: 0), forKey: "fx")
        b.root.addSublayer(b.flare)
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 1, 0]; fade.keyTimes = [0, 0.25, 1]
        b.root.add(Self.group([fade], duration: LaserBeam.duration, delay: 0), forKey: "fx")
        layer.addSublayer(b.root)
        return b
    }

    /// Glitch: mỗi bước một nhóm (2 kênh màu + 3 lát) chỉ hiện trong 30 ms của nó — hình đặt mỗi lần bấm, animation gắn sẵn.
    private final class Glitch {
        let root = CALayer()
        var steps: [(group: CALayer, cyan: CALayer, magenta: CALayer, slices: [CALayer])] = []
    }

    private func fireGlitch(_ r: CGRect, now: CFTimeInterval) {
        let slot = glitchPool.next()
        let g: Glitch
        if slot < glitches.count { g = glitches[slot] } else { g = makeGlitch(); glitches.append(g) }
        glitchSeq += 1
        let size = r.size == .zero ? Self.defaultKeySize : r.size
        let box = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
        for (k, st) in g.steps.enumerated() {
            let sp = CGFloat(GlitchFx.split(step: k))
            st.cyan.frame = box.offsetBy(dx: -sp, dy: 0)
            st.magenta.frame = box.offsetBy(dx: sp, dy: 0)
            for (i, s) in GlitchFx.slices(step: k, variant: glitchSeq % GlitchFx.variants).enumerated() where i < st.slices.count {
                st.slices[i].frame = CGRect(x: box.minX + CGFloat(s.dx * GlitchFx.maxShift), y: box.minY + size.height * CGFloat(s.y),
                                            width: size.width, height: size.height * CGFloat(s.h))
            }
        }
        g.root.position = CGPoint(x: r.midX, y: r.midY)
        g.root.beginTime = now
        g.root.isHidden = false
    }

    private func makeGlitch() -> Glitch {
        let g = Glitch()
        g.root.bounds = .zero
        g.root.isHidden = true
        for k in 0..<GlitchFx.steps {
            let grp = CALayer()
            grp.opacity = 0                      // chỉ hiện trong khoảng của bước (animation không lấp hai đầu)
            let cyan = CALayer(), magenta = CALayer()
            for (l, c) in [(cyan, GlitchFx.cyan), (magenta, GlitchFx.magenta)] {
                l.backgroundColor = UIColor(rgb: c).withAlphaComponent(0.32).cgColor
                l.cornerRadius = 5
                grp.addSublayer(l)
            }
            var slices: [CALayer] = []
            for i in 0..<GlitchFx.slices {
                let s = CALayer()
                s.backgroundColor = keyFill.withAlphaComponent(0.95).cgColor
                let line = CALayer()
                line.backgroundColor = UIColor(rgb: i % 2 == 0 ? GlitchFx.cyan : GlitchFx.magenta).withAlphaComponent(0.8).cgColor
                line.frame = CGRect(x: 0, y: 0, width: 400, height: 1)
                s.masksToBounds = true
                s.addSublayer(line)
                grp.addSublayer(s)
                slices.append(s)
            }
            let on = CABasicAnimation(keyPath: "opacity")
            on.fromValue = 1; on.toValue = 1
            on.duration = GlitchFx.stepTime
            on.beginTime = Self.animBegin + Double(k) * GlitchFx.stepTime
            on.fillMode = .removed
            on.isRemovedOnCompletion = false
            grp.add(on, forKey: "fx")
            g.root.addSublayer(grp)
            g.steps.append((grp, cyan, magenta, slices))
        }
        layer.addSublayer(g.root)
        return g
    }

    // MARK: Sàn nhảy LED

    /// Một chùm ô: mỗi vòng × mỗi màu một CAShapeLayer (path = các ô bo góc) — animation mờ dựng MỘT lần (trễ theo vòng).
    private final class Dance {
        let root = CALayer()
        var layers: [[CAShapeLayer]] = []      // [vòng][màu]
    }

    private func fireDance(_ r: CGRect, now: CFTimeInterval, media: CFTimeInterval) {
        let level = combo.press(at: media)
        let slot = dancePool.next()
        let d: Dance
        if slot < dances.count { d = dances[slot] } else { d = makeDance(rings: DanceFloor.rings, flicker: false); dances.append(d) }
        danceSeq += 1
        let key = r.size == .zero ? CGRect(x: r.minX - Self.defaultKeySize.width / 2, y: r.minY - Self.defaultKeySize.height / 2,
                                           width: Self.defaultKeySize.width, height: Self.defaultKeySize.height) : r
        fill(d, tiles: DanceFloor.tiles(cx: Double(key.midX), cy: Double(key.midY), w: Double(key.width), h: Double(key.height),
                                        seed: danceSeq), rings: DanceFloor.rings)
        d.root.beginTime = now
        d.root.isHidden = false
        // Gõ dồn (mức combo cao nhất): cả bàn phím nháy một nhịp — trần nhịp `flickerCooldown`.
        // Cổng an toàn chung với flash phím cách (≤ 3 lần / giây) — KeyboardView đặt `flashGate`.
        if flickerGate.trigger(level: level, at: media), flashGate?.trigger(at: media) ?? true {
            let f: Dance
            if let x = floorFlicker { f = x } else { f = makeDance(rings: 1, flicker: true); floorFlicker = f }
            fill(f, tiles: DanceFloor.grid(bounds: (Double(bounds.minX), Double(bounds.minY), Double(bounds.width), Double(bounds.height)),
                                           cx: Double(key.midX), cy: Double(key.midY), w: Double(key.width), h: Double(key.height),
                                           seed: danceSeq), rings: 1)
            f.root.beginTime = now
            f.root.isHidden = false
        }
    }

    private func fill(_ d: Dance, tiles: [DanceFloor.Tile], rings: Int) {
        let paths = (0..<rings).map { _ in (0..<DanceFloor.colors.count).map { _ in CGMutablePath() } }
        for t in tiles where t.ring < rings {
            let rect = CGRect(x: t.x - t.w / 2, y: t.y - t.h / 2, width: t.w, height: t.h)
            let rad = CGFloat(DanceFloor.cornerFactor) * min(rect.width, rect.height)
            paths[t.ring][t.color].addRoundedRect(in: rect, cornerWidth: rad, cornerHeight: rad)
        }
        for (i, row) in d.layers.enumerated() where i < rings {
            for (k, l) in row.enumerated() { l.path = paths[i][k] }
        }
    }

    private func makeDance(rings: Int, flicker: Bool) -> Dance {
        let d = Dance()
        d.root.bounds = .zero
        d.root.position = .zero
        d.root.anchorPoint = .zero
        d.root.isHidden = true
        for ring in 0..<rings {
            var row: [CAShapeLayer] = []
            for c in DanceFloor.colors {
                let l = CAShapeLayer()
                l.fillColor = UIColor(rgb: c).cgColor
                l.strokeColor = UIColor(rgb: c).withAlphaComponent(0.9).cgColor
                l.lineWidth = 1.5
                l.opacity = 0
                let a = CAKeyframeAnimation(keyPath: "opacity")
                let steps = 10
                let life = flicker ? DanceFloor.flickerDuration : DanceFloor.tileLife
                let start = flicker ? 0 : DanceFloor.ringDelay * Double(ring)
                a.values = (0...steps).map { k -> Double in
                    let t = life * Double(k) / Double(steps) * 0.9999
                    return flicker ? DanceFloor.flickerAlpha(t) : DanceFloor.alpha(t + start, ring: ring)
                }
                a.keyTimes = (0...steps).map { NSNumber(value: Double($0) / Double(steps)) }
                a.duration = life
                a.beginTime = Self.animBegin + start
                a.fillMode = .removed
                a.isRemovedOnCompletion = false
                l.add(a, forKey: "fx")
                d.root.addSublayer(l)
                row.append(l)
            }
            d.layers.append(row)
        }
        layer.addSublayer(d.root)
        return d
    }

    /// Dấu thanh: mỗi kiểu dấu một pool nhỏ (dựng lười — chỉ kiểu đã gặp mới có layer).
    private func fireTone(_ t: ToneFx, at r: CGRect, now: CFTimeInterval) {
        var list = toneRoots[t] ?? []
        let cur = toneCursor[t, default: 0]
        toneCursor[t] = (cur + 1) % ToneBurst.pool
        let root: CALayer
        if cur < list.count { root = list[cur] } else { root = makeToneRoot(t); list.append(root); toneRoots[t] = list }
        launch(root, at: Self.keyTop(r), now: now)
    }

    /// Điểm phát: mép trên phím (không vượt đỉnh overlay).
    private static func keyTop(_ r: CGRect) -> CGPoint {
        let h = r.size == .zero ? defaultKeySize.height : r.height
        return CGPoint(x: r.midX, y: max(r.midY - h / 2 + 4, 0))
    }

    private func makeToneRoot(_ t: ToneFx) -> CALayer {
        let b = CALayer()
        b.bounds = .zero
        b.isHidden = true
        let path = ToneBurst.path(t)
        let c = UIColor(rgb: ToneBurst.color(t))
        for i in 0..<ToneBurst.count(t) {
            let l = CAShapeLayer()
            l.path = path
            l.bounds = .zero
            l.contentsScale = UIScreen.main.scale
            if ToneBurst.stroked(t) {
                l.fillColor = nil; l.strokeColor = c.cgColor; l.lineWidth = 2; l.lineCap = .round; l.lineJoin = .round
            } else {
                l.fillColor = c.cgColor
            }
            l.opacity = 0
            l.add(Self.makeAnimation(ToneBurst.trajectory(t, i), easeIn: ToneBurst.easeIn(t),
                                     scaleXOnly: ToneBurst.stretchesX(t)), forKey: "fx")
            b.addSublayer(l)
        }
        layer.addSublayer(b)
        return b
    }

    private func fireKeyword(_ k: KeywordKind, at r: CGRect, now: CFTimeInterval) {
        var list = keywordRoots[k] ?? []
        let cur = keywordCursor[k, default: 0]
        keywordCursor[k] = (cur + 1) % KeywordBursts.pool
        let root: CALayer
        if cur < list.count { root = list[cur] } else { root = makeKeywordRoot(k); list.append(root); keywordRoots[k] = list }
        launch(root, at: Self.keyTop(r), now: now)
    }

    private func makeKeywordRoot(_ k: KeywordKind) -> CALayer {
        let b = CALayer()
        b.bounds = .zero
        b.isHidden = true
        let ems = KeywordBursts.emojis(k)
        for p in KeywordBursts.particles(k) {
            let l: CALayer
            switch p.shape {
            case .emoji:
                l = CALayer()
                l.bounds = CGRect(x: 0, y: 0, width: 30, height: 30)
                l.contentsGravity = .resizeAspect
                if Int(p.color) < ems.count { l.contents = emojiImage(ems[Int(p.color)]) }
            default:
                let s = CAShapeLayer()
                s.bounds = .zero
                s.contentsScale = UIScreen.main.scale
                s.fillColor = UIColor(rgb: p.color).cgColor
                switch p.shape {
                case .heart: s.path = KeyEffectShapes.heart(8)
                case .spark: s.path = KeyEffectShapes.star4(3.5, inner: 1.1)
                case .puff:
                    s.path = CGPath(ellipseIn: CGRect(x: -6, y: -6, width: 12, height: 12), transform: nil)
                    s.fillColor = UIColor(rgb: p.color).withAlphaComponent(0.7).cgColor
                case .paper: s.path = CGPath(rect: CGRect(x: -1.5, y: -2.5, width: 3, height: 5), transform: nil)
                case .cracker:
                    s.path = CGPath(roundedRect: CGRect(x: -2.5, y: -5.5, width: 5, height: 11), cornerWidth: 1, cornerHeight: 1, transform: nil)
                    let band = CAShapeLayer()
                    band.path = CGPath(rect: CGRect(x: -2.5, y: -1, width: 5, height: 2), transform: nil)
                    band.fillColor = UIColor(rgb: KeywordBursts.gold).cgColor
                    s.addSublayer(band)
                case .envelope:
                    s.path = CGPath(roundedRect: CGRect(x: -6, y: -8, width: 12, height: 16), cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)
                    let seal = CAShapeLayer()
                    seal.path = CGPath(ellipseIn: CGRect(x: -2.6, y: -3.6, width: 5.2, height: 5.2), transform: nil)
                    seal.fillColor = UIColor(rgb: KeywordBursts.gold).cgColor
                    s.addSublayer(seal)
                case .emoji: break
                }
                l = s
            }
            l.position = CGPoint(x: p.x0, y: p.y0)
            l.opacity = 0
            l.add(Self.makeAnimation(p.traj, easeIn: p.easeIn, delay: p.delay, hiddenBefore: true), forKey: "fx")
            b.addSublayer(l)
        }
        layer.addSublayer(b)
        return b
    }

    private func fireLetter(_ g: String, at r: CGRect, now: CFTimeInterval) {
        let slot = letterPool.next()
        let l: CATextLayer
        if slot < letters.count { l = letters[slot] } else { l = makeLetter(slot); letters.append(l) }
        l.string = g
        let p = Self.keyTop(r)
        l.position = CGPoint(x: p.x, y: p.y)
        l.beginTime = now
        l.isHidden = false
    }

    private func makeLetter(_ seed: Int) -> CATextLayer {
        let l = CATextLayer()
        let s = CGFloat(FlyingLetters.size)
        l.bounds = CGRect(x: 0, y: 0, width: s * 2, height: s * 1.3)
        l.font = UIFont.boldSystemFont(ofSize: s)
        l.fontSize = s
        l.alignmentMode = .center
        l.contentsScale = UIScreen.main.scale
        l.foregroundColor = color.cgColor
        l.isHidden = true
        l.opacity = 0
        let t = KeyEffectTrajectory(dx: FlyingLetters.drift(seed), dy: -FlyingLetters.rise, scaleFrom: 0.8, scaleTo: 1.2,
                                    rotation: FlyingLetters.spin(seed), duration: FlyingLetters.duration)
        l.add(Self.makeAnimation(t, fadeAt: 0.4), forKey: "fx")
        layer.addSublayer(l)
        return l
    }

    // Token AI

    /// Một chùm: chữ loé + `maxChips` chip (vỏ có bóng sáng theo shadowPath — không vẽ ngoài màn — + lõi gradient bo).
    private final class TokenBurst {
        let root = CALayer()
        let glyph = CATextLayer()
        var chips: [CALayer] = []
    }

    private func fireToken(_ g: String, at r: CGRect, now: CFTimeInterval) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let slot = tokenPool.next()
        let b: TokenBurst
        if slot < tokenBursts.count { b = tokenBursts[slot] } else { b = makeTokenBurst(); tokenBursts.append(b) }
        // Toạ độ tính trong khung overlay gốc 0 (pure clamp theo w × h) rồi cộng gốc bounds (#151).
        let o = bounds.origin, w = Double(bounds.width), h = Double(bounds.height)
        let k = Self.keyTop(r)
        let key = (x: Double(k.x - o.x), y: Double(k.y - o.y))
        let t = tokenTarget?() ?? CGPoint(x: bounds.midX, y: bounds.minY + 14)
        let p1 = TokenStream.clamp((Double(t.x - o.x), Double(t.y - o.y)), width: w, height: h)
        let n = TokenStream.chipCount(g)
        b.root.isHidden = false
        b.glyph.string = g
        b.glyph.position = CGPoint(x: k.x, y: max(k.y, bounds.minY + CGFloat(TokenStream.glyphSize) / 2))
        b.glyph.beginTime = now
        for (i, c) in b.chips.enumerated() {
            guard i < n else { c.isHidden = true; continue }
            let p0 = TokenStream.start(key: key, chip: i, of: n, width: w, height: h)
            let cp = TokenStream.control(from: p0, to: p1, chip: i, of: n, width: w, height: h)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: p0.x + o.x, y: p0.y + o.y))
            path.addQuadCurve(to: CGPoint(x: p1.x + o.x, y: p1.y + o.y), control: CGPoint(x: cp.x + o.x, y: cp.y + o.y))
            c.isHidden = false
            c.position = CGPoint(x: p1.x + o.x, y: p1.y + o.y)
            c.removeAnimation(forKey: "fx")
            c.add(Self.tokenAnimation(path: path, delay: TokenStream.delay(i), now: now), forKey: "fx")
        }
    }

    private func makeTokenBurst() -> TokenBurst {
        let b = TokenBurst()
        b.root.bounds = .zero
        b.root.position = .zero
        let s = CGFloat(TokenStream.glyphSize)
        b.glyph.bounds = CGRect(x: 0, y: 0, width: s * 2, height: s * 1.3)
        b.glyph.font = UIFont.boldSystemFont(ofSize: s)
        b.glyph.fontSize = s
        b.glyph.alignmentMode = .center
        b.glyph.contentsScale = UIScreen.main.scale
        b.glyph.foregroundColor = UIColor.white.cgColor
        b.glyph.shadowColor = UIColor(rgb: TokenStream.colors[0]).cgColor
        b.glyph.shadowRadius = 4
        b.glyph.shadowOpacity = 0.9
        b.glyph.shadowOffset = .zero
        b.glyph.opacity = 0
        let pop = CABasicAnimation(keyPath: "transform.scale")
        pop.fromValue = 0.9; pop.toValue = 1.25
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 1, 0]; fade.keyTimes = [0, 0.45, 1]
        b.glyph.add(Self.group([pop, fade], duration: TokenStream.glyphTime, delay: 0), forKey: "fx")
        b.root.addSublayer(b.glyph)
        let cw = CGFloat(TokenStream.chipW), ch = CGFloat(TokenStream.chipH), cr = CGFloat(TokenStream.chipRadius)
        let cols = TokenStream.colors
        for i in 0..<TokenStream.maxChips {
            let shell = CALayer()
            shell.bounds = CGRect(x: 0, y: 0, width: cw, height: ch)
            shell.opacity = 0
            shell.isHidden = true
            let glowColor = UIColor(rgb: cols[i % cols.count])
            shell.shadowColor = glowColor.cgColor
            shell.shadowOpacity = 1
            shell.shadowRadius = 3
            shell.shadowOffset = .zero
            shell.shadowPath = CGPath(roundedRect: shell.bounds, cornerWidth: cr, cornerHeight: cr, transform: nil)
            let core = CAGradientLayer()
            core.frame = shell.bounds
            core.colors = [glowColor.cgColor, UIColor(rgb: cols[(i + 1) % cols.count]).cgColor]
            core.startPoint = CGPoint(x: 0, y: 0.5)
            core.endPoint = CGPoint(x: 1, y: 0.5)
            core.cornerRadius = cr
            core.masksToBounds = true
            shell.addSublayer(core)
            b.root.addSublayer(shell)
            b.chips.append(shell)
        }
        layer.addSublayer(b.root)
        return b
    }

    /// Chip bay theo `path` (Bézier bậc 2 trong bàn phím), nhanh dần vào đích (t² ≈ easeIn), co lại, hiện nhanh rồi tắt.
    private static func tokenAnimation(path: CGPath, delay: Double, now: CFTimeInterval) -> CAAnimationGroup {
        let move = CAKeyframeAnimation(keyPath: "position")
        move.path = path
        move.calculationMode = .linear
        move.timingFunction = CAMediaTimingFunction(name: .easeIn)
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1
        scale.toValue = TokenStream.endScale
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0]
        fade.keyTimes = [0, 0.12, 0.75, 1]
        let g = CAAnimationGroup()
        g.animations = [move, scale, fade]
        for a in g.animations ?? [] { a.duration = TokenStream.flight }
        g.duration = TokenStream.flight
        g.beginTime = now + delay
        g.fillMode = .both
        g.isRemovedOnCompletion = false
        return g
    }

    /// Vệt sáng quét dải gợi ý MỘT lần: lớp cắt theo khung dải + dải gradient trắng mờ trượt trái → phải, gỡ khi xong.
    private func fireShimmer(in bar: CGRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let clip: CALayer
        if let c = shimmerClip { clip = c } else {
            clip = CALayer()
            clip.masksToBounds = true
            let band = CAGradientLayer()
            let white = UIColor.white
            band.colors = [white.withAlphaComponent(0).cgColor, white.withAlphaComponent(CGFloat(ShimmerGate.peakAlpha)).cgColor,
                           white.withAlphaComponent(0).cgColor]
            band.startPoint = CGPoint(x: 0, y: 0.5)
            band.endPoint = CGPoint(x: 1, y: 0.5)
            band.anchorPoint = .zero
            clip.addSublayer(band)
            layer.addSublayer(clip)
            shimmerClip = clip; shimmerBand = band
        }
        if clip.frame != bar { clip.frame = bar }
        let w = Double(bar.width)
        if let band = shimmerBand {
            band.bounds = CGRect(x: 0, y: 0, width: CGFloat(ShimmerGate.band * w), height: bar.height)
            band.position = CGPoint(x: CGFloat(ShimmerGate.left(1, width: w)), y: 0)   // nghỉ: ngoài mép phải (bị cắt)
            let a = CABasicAnimation(keyPath: "position.x")
            a.fromValue = ShimmerGate.left(0, width: w)
            a.toValue = ShimmerGate.left(1, width: w)
            a.duration = ShimmerGate.duration
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            band.removeAnimation(forKey: "shimmer")
            band.add(a, forKey: "shimmer")   // tự gỡ khi xong (isRemovedOnCompletion mặc định) ⇒ nghỉ = 0 animation
        }
        CATransaction.commit()
    }

    // Hạt cát

    private func fireSand(_ c: CGPoint, now: CFTimeInterval, media: CFTimeInterval) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        if sand?.columns != SandPile.columns(for: Double(bounds.width)) { sand = SandPile(width: Double(bounds.width)) }
        let pileLayer = sandLayer()
        // Đang lún dở ⇒ chốt mức lún hiện tại vào đống rồi gõ tiếp từ đó.
        let k = SandPile.sinkFactor(idle: media - sandLast)
        if k < 1 {
            if k <= 0 { sand?.clear() } else { sand?.scale(k) }
            updateSandPath()
        }
        sandLast = media
        sandSeq += 1
        var maxFall = 0.0
        var landing: [Double] = []
        for i in 0..<SandPile.grainsPerTap {
            let slot = grainPool.next()
            let g: CALayer
            if slot < grains.count { g = grains[slot] } else { g = makeGrain(); grains.append(g) }
            let x = min(max(Double(c.x) + SandPile.spread(i, seed: sandSeq), 0), Double(bounds.width) - 1)
            let floorY = Double(bounds.maxY) - (sand?.surface(x) ?? 0)
            let fall = SandPile.fallTime(floorY - Double(c.y))
            maxFall = max(maxFall, fall)
            let drop = CABasicAnimation(keyPath: "position.y")
            drop.fromValue = c.y; drop.toValue = floorY
            drop.timingFunction = CAMediaTimingFunction(name: .easeIn)
            let show = CABasicAnimation(keyPath: "opacity")
            show.fromValue = 1; show.toValue = 1
            let grp = CAAnimationGroup()
            grp.animations = [drop, show]
            grp.duration = max(fall, 0.01); drop.duration = grp.duration; show.duration = grp.duration
            grp.isRemovedOnCompletion = true
            g.position = CGPoint(x: x, y: floorY)
            g.add(grp, forKey: "fx")
            landing.append(x)
        }
        pendingLandings += landing
        // MỘT hẹn giờ cho cả lượt hạt: đáp ⇒ ghi vào mảng chiều cao + vẽ lại đống (một path).
        DispatchQueue.main.asyncAfter(deadline: .now() + maxFall) { [weak self] in self?.landSand() }
        // Lún: animation co dọc đống bắt đầu sau idleAfter (đặt lại mỗi lần gõ), một lần dọn khi hết.
        let sink = CABasicAnimation(keyPath: "transform.scale.y")
        sink.fromValue = 1; sink.toValue = 0
        sink.beginTime = pileLayer.convertTime(media, from: nil) + SandPile.idleAfter
        sink.duration = SandPile.sinkTime
        sink.fillMode = .both
        sink.isRemovedOnCompletion = false
        pileLayer.add(sink, forKey: "sink")
        scheduleSandSweep(after: SandPile.idleAfter + SandPile.sinkTime + 0.05)
        _ = now
    }

    private func landSand() {
        guard !pendingLandings.isEmpty, sand != nil else { pendingLandings.removeAll(); return }
        for x in pendingLandings { sand?.deposit(x) }
        pendingLandings.removeAll(keepingCapacity: true)
        updateSandPath()
    }

    private func scheduleSandSweep(after s: Double) {
        guard !sandSweepScheduled else { return }
        sandSweepScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + s) { [weak self] in self?.sweepSand() }
    }

    private func sweepSand() {
        sandSweepScheduled = false
        let left = SandPile.idleAfter + SandPile.sinkTime + 0.05 - (CACurrentMediaTime() - sandLast)
        if left > 0 { scheduleSandSweep(after: left); return }
        clearSand()
    }

    private func clearSand() {
        sand?.clear()
        pendingLandings.removeAll()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sandPile?.removeAllAnimations()
        sandPile?.path = nil
        for g in grains { g.removeAllAnimations() }
        CATransaction.commit()
    }

    private func sandLayer() -> CAShapeLayer {
        if let l = sandPile { return l }
        let l = CAShapeLayer()
        l.fillColor = UIColor(rgb: SandPile.color).withAlphaComponent(0.92).cgColor
        l.anchorPoint = CGPoint(x: 0.5, y: 1)
        l.frame = CGRect(x: bounds.minX, y: bounds.maxY - CGFloat(SandPile.maxHeight) - 1,
                         width: bounds.width, height: CGFloat(SandPile.maxHeight) + 1)
        l.actions = ["path": NSNull(), "position": NSNull(), "bounds": NSNull()]
        layer.addSublayer(l)
        sandPile = l
        return l
    }

    /// Path đống cát (toạ độ layer đống: đáy = bounds.maxY) — dựng lại chỉ khi đống đổi.
    private func updateSandPath() {
        guard let l = sandPile, let s = sand else { return }
        if s.isEmpty { l.path = nil; return }
        let h = l.bounds.height
        let w = CGFloat(SandPile.column)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: h))
        for (c, v) in s.heights.enumerated() {
            let y = h - CGFloat(v)
            p.addLine(to: CGPoint(x: CGFloat(c) * w, y: y))
            p.addLine(to: CGPoint(x: CGFloat(c + 1) * w, y: y))
        }
        p.addLine(to: CGPoint(x: CGFloat(s.columns) * w, y: h))
        p.closeSubpath()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        l.path = p
        CATransaction.commit()
    }

    private func makeGrain() -> CALayer {
        let g = CALayer()
        let d = CGFloat(SandPile.grainSize)
        g.bounds = CGRect(x: 0, y: 0, width: d, height: d)
        g.cornerRadius = d / 2
        g.backgroundColor = UIColor(rgb: SandPile.color).cgColor
        g.opacity = 0                 // chỉ hiện khi đang rơi (animation tự gỡ)
        layer.addSublayer(g)
        return g
    }

    // MARK: Biển

    /// Một con sóng: gốc (góc trên-trái bàn phím) chứa `wave` (thân + mép bọt, cuộn xuống) và `shore` (vệt ướt + bọt
    /// tràn ở đáy). Cỡ sóng = scale dọc của `wave` / `shore`, đặt lúc bắn.
    private final class SeaWave {
        let root = CALayer(), wave = CALayer(), shore = CALayer()
    }

    private func fireSea(_ c: CGPoint, now: CFTimeInterval, media: CFTimeInterval) {
        let prev = seaLevel
        let lv = combo.press(at: media)
        seaLevel = lv
        launch(nextBurst(), at: c, now: now)            // bọt bắn + bong bóng ở phím
        guard bounds.width > 0, bounds.height > 0 else { return }
        if SeaFx.shouldLaunch(sinceLast: media - seaLastWave) {
            seaLastWave = media
            let size = SeaFx.size(level: lv)
            launchWave(size: size, now: now)
            onSeaWave?(size)
        }
        if SeaFx.fishShouldSwim(level: lv, previous: prev, sinceLastFish: media - seaLastFish) {
            seaLastFish = media
            swimFish()
        }
    }

    private func launchWave(size: Double, now: CFTimeInterval) {
        if seaBuiltFor != bounds.size {       // cỡ bàn phím đổi ⇒ dựng lại path + animation theo cỡ mới
            for w in seaWaves { w.root.removeFromSuperlayer() }
            seaWaves.removeAll(); seaCursor = 0
            seaBuiltFor = bounds.size
        }
        let slot = seaCursor
        seaCursor = (slot + 1) % SeaFx.maxWaves
        let w: SeaWave
        if slot < seaWaves.count { w = seaWaves[slot] } else { w = makeSeaWave(slot); seaWaves.append(w) }
        let s = CGFloat(size)
        w.wave.transform = CATransform3DMakeScale(1, s, 1)
        w.shore.transform = CATransform3DMakeScale(1, s, 1)
        w.root.position = bounds.origin
        w.root.beginTime = now
        w.root.isHidden = false
    }

    private static func polyline(_ xs: [Double], _ y: (Double) -> Double) -> CGMutablePath {
        let p = CGMutablePath()
        for (i, x) in xs.enumerated() {
            let pt = CGPoint(x: x, y: y(x))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }

    private func makeSeaWave(_ slot: Int) -> SeaWave {
        let w = SeaWave()
        let W = Double(bounds.width), H = Double(bounds.height)
        let ph = SeaFx.phase(slot)
        let lam = SeaFx.wavelength
        let xs = Array(stride(from: -lam, through: W + lam, by: SeaFx.step))
        let foam = UIColor.white
        // Thân sóng (gốc = mép sóng): mép dưới = crestOffset, mép trên = bodyTop.
        let body = Self.polyline(xs) { SeaFx.crestOffset($0, phase: ph) }
        for x in xs.reversed() { body.addLine(to: CGPoint(x: x, y: SeaFx.bodyTop(x, phase: ph))) }
        body.closeSubpath()
        let crest = Self.polyline(xs) { SeaFx.crestOffset($0, phase: ph) }
        let edge = Self.polyline(xs) { SeaFx.crestOffset($0, phase: ph) + 1.8 }
        func shape(_ path: CGPath, fill: UIColor?, stroke: UIColor?, width: CGFloat = 0) -> CAShapeLayer {
            let l = CAShapeLayer()
            l.path = path; l.bounds = .zero; l.position = .zero
            l.fillColor = fill?.cgColor; l.strokeColor = stroke?.cgColor; l.lineWidth = width
            l.lineJoin = .round; l.lineCap = .round
            l.contentsScale = UIScreen.main.scale
            return l
        }
        w.wave.bounds = .zero
        w.wave.addSublayer(shape(body, fill: color.withAlphaComponent(CGFloat(SeaFx.bodyAlpha)), stroke: nil))
        // Mép màu nhấn ngay dưới bọt — thấy được cả trên phím sáng.
        w.wave.addSublayer(shape(edge, fill: nil, stroke: color.withAlphaComponent(0.6), width: 1))
        w.wave.addSublayer(shape(crest, fill: nil, stroke: foam.withAlphaComponent(CGFloat(SeaFx.foamAlpha)),
                                 width: CGFloat(SeaFx.foamWidth)))
        // Bờ (gốc = đáy bàn phím): vệt ướt + bọt tràn, cao washMax, mép trên gợn.
        let band = CGMutablePath()
        band.move(to: CGPoint(x: xs[0], y: 0))
        for x in xs { band.addLine(to: CGPoint(x: x, y: SeaFx.washTop(x, phase: ph))) }
        band.addLine(to: CGPoint(x: xs[xs.count - 1], y: 0))
        band.closeSubpath()
        let top = Self.polyline(xs) { SeaFx.washTop($0, phase: ph) }
        w.shore.bounds = .zero
        w.shore.position = CGPoint(x: 0, y: H)
        let wet = shape(band, fill: color, stroke: nil)
        wet.opacity = 0
        let wash = CALayer()
        wash.bounds = .zero
        wash.addSublayer(shape(band, fill: foam.withAlphaComponent(dark ? 0.6 : 0.75), stroke: nil))
        wash.addSublayer(shape(top, fill: nil, stroke: color.withAlphaComponent(0.7), width: 1))
        wash.transform = CATransform3DMakeScale(1, 0, 1)
        w.shore.addSublayer(wet)
        w.shore.addSublayer(wash)

        // Animation gắn MỘT lần, lấy mẫu từ hàm thuần (Android vẽ từng khung bằng đúng các hàm đó).
        let n = SeaFx.frames, life = SeaFx.life
        let ts = (0...n).map { life * Double($0) / Double(n) }
        let keyTimes = (0...n).map { NSNumber(value: Double($0) / Double(n)) }
        func kf(_ path: String, _ values: [Any]) -> CAKeyframeAnimation {
            let a = CAKeyframeAnimation(keyPath: path)
            a.values = values; a.keyTimes = keyTimes; a.calculationMode = .linear
            return a
        }
        w.wave.opacity = 0
        w.wave.add(Self.group([kf("position", ts.map { NSValue(cgPoint: CGPoint(x: SeaFx.driftX($0), y: SeaFx.travel($0) * H)) }),
                               kf("opacity", ts.map { SeaFx.waveAlpha($0) })], duration: life, delay: 0), forKey: "fx")
        wet.add(Self.group([kf("opacity", ts.map { SeaFx.wetAlpha($0) })], duration: life, delay: 0), forKey: "fx")
        wash.add(Self.group([kf("transform.scale.y", ts.map { SeaFx.washHeight($0, size: 1) / SeaFx.washMax })],
                            duration: life, delay: 0), forKey: "fx")
        w.root.bounds = .zero
        w.root.anchorPoint = .zero
        w.root.isHidden = true
        w.root.addSublayer(w.wave)
        w.root.addSublayer(w.shore)
        layer.insertSublayer(w.root, at: 0)        // sóng nằm dưới bọt bắn / bong bóng
        return w
    }

    /// Cá: MỘT layer ảnh emoji (dựng sẵn ngoài main); hiếm (≥ fishCooldown) nên animation tạo mỗi lần bơi, tự gỡ khi xong.
    private func swimFish() {
        let seq = seaFishSeq
        seaFishSeq += 1
        let l: CALayer
        if let f = seaFish { l = f } else {
            l = CALayer()
            let s = CGFloat(SeaFx.fishSize)
            l.bounds = CGRect(x: 0, y: 0, width: s, height: s)
            l.contentsGravity = .resizeAspect
            l.opacity = 0
            layer.addSublayer(l)
            seaFish = l
        }
        let rtl = SeaFx.fishRightToLeft(seq)
        l.contents = emojiImage(SeaFx.fishGlyphs[seq % SeaFx.fishGlyphs.count])
        // Emoji cá quay mặt sang trái: bơi sang phải ⇒ lật ngang.
        l.transform = rtl ? CATransform3DIdentity : CATransform3DMakeScale(-1, 1, 1)
        let W = Double(bounds.width), x0 = Double(bounds.minX)
        let y0 = Double(bounds.minY) + SeaFx.fishY(seq, height: Double(bounds.height))
        let n = 24
        let fs = (0...n).map { Double($0) / Double(n) }
        let move = CAKeyframeAnimation(keyPath: "position")
        move.values = fs.map { NSValue(cgPoint: CGPoint(x: x0 + SeaFx.fishX($0, width: W, rightToLeft: rtl), y: y0 + SeaFx.fishBobY($0))) }
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = fs.map { SeaFx.fishAlpha(min($0, 0.999)) }
        let g = CAAnimationGroup()
        g.animations = [move, fade]
        g.duration = SeaFx.fishDuration; move.duration = g.duration; fade.duration = g.duration
        g.isRemovedOnCompletion = true
        g.fillMode = .removed
        l.position = CGPoint(x: x0 + SeaFx.fishX(1, width: W, rightToLeft: rtl), y: y0)
        l.add(g, forKey: "fx")
    }

    /// Chùm bọt bắn (giọt trắng) + bong bóng (vòng) của một lần bấm — animation gắn một lần.
    private func makeSeaSplash(into b: CALayer) {
        let r = CGFloat(SeaFx.dropletRadius)
        let dropPath = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r), transform: nil)
        let n = 10
        let fs = (0...n).map { Double($0) / Double(n) }
        for i in 0..<SeaFx.dropletsPerTap {
            let l = CAShapeLayer()
            l.path = dropPath; l.bounds = .zero; l.position = .zero
            l.contentsScale = UIScreen.main.scale
            l.fillColor = UIColor.white.cgColor
            l.strokeColor = dark ? nil : color.withAlphaComponent(0.8).cgColor   // theme sáng: viền để thấy trên phím sáng
            l.lineWidth = dark ? 0 : 0.6
            l.opacity = 0
            let move = CAKeyframeAnimation(keyPath: "position")
            move.isAdditive = true
            move.values = fs.map { let p = SeaFx.droplet(i, $0); return NSValue(cgPoint: CGPoint(x: p.x, y: p.y)) }
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [1, 1, 0]; fade.keyTimes = [0, 0.6, 1]
            l.add(Self.group([move, fade], duration: SeaFx.dropletDuration, delay: 0), forKey: "fx")
            b.addSublayer(l)
        }
        let br = CGFloat(SeaFx.bubbleRadius)
        let ring = CGPath(ellipseIn: CGRect(x: -br, y: -br, width: 2 * br, height: 2 * br), transform: nil)
        for i in 0..<SeaFx.bubblesPerTap {
            let l = CAShapeLayer()
            l.path = ring; l.bounds = .zero; l.position = .zero
            l.contentsScale = UIScreen.main.scale
            l.fillColor = color.withAlphaComponent(0.15).cgColor
            l.strokeColor = (dark ? UIColor.white.withAlphaComponent(0.85) : color).cgColor
            l.lineWidth = 1.2
            l.opacity = 0
            let samples = fs.map { SeaFx.bubble(i, $0) }
            let move = CAKeyframeAnimation(keyPath: "position")
            move.isAdditive = true
            move.values = samples.map { NSValue(cgPoint: CGPoint(x: $0.x, y: $0.y)) }
            let scale = CAKeyframeAnimation(keyPath: "transform.scale")
            scale.values = samples.map(\.scale)
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = samples.map(\.alpha)
            l.add(Self.group([move, scale, fade], duration: SeaFx.bubbleDuration, delay: 0), forKey: "fx")
            b.addSublayer(l)
        }
    }

    private func haltSea() {
        seaLastWave = -.greatestFiniteMagnitude
        seaLevel = 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for w in seaWaves { w.root.isHidden = true }
        seaFish?.removeAllAnimations()
        CATransaction.commit()
    }

    // MARK: Mưa

    /// Màu nước: trắng trên theme tối, màu nhấn trên theme sáng (trắng không thấy trên phím sáng).
    private var rainInk: UIColor { dark ? .white : color }

    private func fireRain(_ c: CGPoint, now: CFTimeInterval, media: CFTimeInterval) {
        rainKeys += 1
        rainLastKey = media
        launch(nextBurst(), at: c, now: now)            // giọt rơi + loang + lăn ở phím
        guard bounds.width > 0, bounds.height > 0 else { return }
        if rainBuiltFor != bounds.size {                // cỡ bàn phím đổi ⇒ dựng lại hạt mưa nền theo cỡ mới
            CATransaction.begin(); CATransaction.setDisableActions(true)
            for d in rainDrops { d.removeFromSuperlayer() }
            CATransaction.commit()
            rainDrops.removeAll(); rainCursor = 0
            rainBuiltFor = bounds.size
        }
        layoutRainGlow()
        let i = RainFx.intensity(keys: rainKeys)
        if RainFx.shouldSpawn(sinceLast: media - rainLastDrop, intensity: i) {
            rainLastDrop = media
            launchRainDrop(now: now)
        }
        let g = RainFx.glow(keys: rainKeys)
        if g != rainGlowLevel { setRainGlow(g) }
        scheduleRainSweep(after: Swift.max(RainFx.dropLife, RainFx.tapLife) + 0.05)
    }

    private func launchRainDrop(now: CFTimeInterval) {
        let slot = rainCursor
        rainCursor = (slot + 1) % RainFx.maxDrops
        let d = slot < rainDrops.count ? rainDrops[slot] : makeRainDrop(slot)
        if slot >= rainDrops.count { rainDrops.append(d) }
        d.position = CGPoint(x: Double(bounds.minX) + RainFx.dropX(seq: rainSeq, width: Double(bounds.width)),
                             y: Double(bounds.minY) - RainFx.startAbove)
        rainSeq += 1
        d.beginTime = now
        d.isHidden = false
    }

    /// Hạt mưa nền: gốc = đầu giọt; vệt nước (gradient trong → trắng mờ) phía trên; trượt theo `RainFx.profiles`.
    private func makeRainDrop(_ slot: Int) -> CALayer {
        let root = CALayer()
        root.bounds = .zero
        root.isHidden = true
        let ink = rainInk
        let streak = CAGradientLayer()
        let sw = CGFloat(RainFx.streakWidth), sl = CGFloat(RainFx.streakLength), ry = CGFloat(RainFx.headRY)
        streak.frame = CGRect(x: -sw / 2, y: -sl - ry * 0.6, width: sw, height: sl)
        streak.colors = [ink.withAlphaComponent(0).cgColor, ink.withAlphaComponent(CGFloat(RainFx.streakAlpha)).cgColor]
        streak.cornerRadius = sw / 2
        let head = CAShapeLayer()
        let rx = CGFloat(RainFx.headRX)
        head.path = CGPath(ellipseIn: CGRect(x: -rx, y: -ry, width: 2 * rx, height: 2 * ry), transform: nil)
        head.fillColor = ink.cgColor
        head.contentsScale = UIScreen.main.scale
        root.addSublayer(streak)
        root.addSublayer(head)
        let n = 60, life = RainFx.dropLife, p = RainFx.profile(slot: slot)
        let dist = RainFx.travelDistance(height: Double(bounds.height))
        let fs = (0...n).map { Double($0) / Double(n) }
        let move = CAKeyframeAnimation(keyPath: "position")
        move.isAdditive = true
        move.values = fs.map { NSValue(cgPoint: CGPoint(x: 0, y: RainFx.travel($0, profile: p) * dist)) }
        move.calculationMode = .linear
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = fs.map { RainFx.dropAlpha(Swift.min($0, 0.9999)) }
        root.opacity = 0
        root.add(Self.group([move, fade], duration: life, delay: 0), forKey: "fx")
        layer.insertSublayer(root, at: rainGlow == nil ? 0 : 1)   // dưới giọt ở phím, trên đèn
        return root
    }

    /// Một lần bấm: vệt ướt + vòng loang + giọt — animation gắn MỘT lần (lấy mẫu RainFx), bấm chỉ dời + beginTime.
    private func makeRainTap(into b: CALayer) {
        let ink = rainInk
        let n = 42, life = RainFx.tapLife
        let ts = (0...n).map { life * Double($0) / Double(n) }
        func kf(_ path: String, _ values: [Any], additive: Bool = false) -> CAKeyframeAnimation {
            let a = CAKeyframeAnimation(keyPath: path)
            a.values = values; a.calculationMode = .linear; a.isAdditive = additive
            return a
        }
        func shape() -> CAShapeLayer {
            let l = CAShapeLayer()
            l.bounds = .zero; l.position = .zero
            l.contentsScale = UIScreen.main.scale
            l.opacity = 0
            return l
        }
        // Vệt ướt: đường lăn của giọt (u = 0…1), vẽ dần theo strokeEnd = tỉ lệ quãng đã lăn.
        let trail = shape()
        let tp = CGMutablePath()
        for k in 0...24 {
            let u = Double(k) / 24
            let pt = CGPoint(x: RainFx.rollX(u), y: RainFx.rollDistance * u * u)
            if k == 0 { tp.move(to: pt) } else { tp.addLine(to: pt) }
        }
        trail.path = tp
        trail.fillColor = nil
        trail.strokeColor = ink.cgColor
        trail.lineWidth = CGFloat(RainFx.trailWidth)
        trail.lineCap = .round; trail.lineJoin = .round
        trail.strokeEnd = 0
        let tr = ts.map { RainFx.trail($0) }
        trail.add(Self.group([kf("strokeEnd", tr.map(\.end)), kf("opacity", tr.map(\.alpha))], duration: life, delay: 0),
                  forKey: "fx")
        // Vòng loang: path vòng tròn theo bán kính lấy mẫu (cùng số phần tử ⇒ CA nội suy được).
        let ring = shape()
        ring.fillColor = nil
        ring.strokeColor = ink.cgColor
        ring.lineWidth = CGFloat(RainFx.ringWidth)
        let rg = ts.map { RainFx.ring($0) }
        let circles: [CGPath] = rg.map {
            let r = CGFloat(Swift.max($0.radius, RainFx.ringFrom))
            return CGPath(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r), transform: nil)
        }
        ring.path = circles[0]
        ring.add(Self.group([kf("path", circles), kf("opacity", rg.map(\.alpha))], duration: life, delay: 0), forKey: "fx")
        // Giọt: rơi xuống phím, đọng, lăn xuống.
        let drop = shape()
        let r = CGFloat(RainFx.tapDropRadius)
        drop.path = CGPath(ellipseIn: CGRect(x: -r, y: -r * 1.25, width: 2 * r, height: 2.5 * r), transform: nil)
        drop.fillColor = ink.cgColor
        let dp = ts.map { RainFx.drop($0) }
        drop.add(Self.group([kf("position", dp.map { NSValue(cgPoint: CGPoint(x: $0.x, y: $0.y)) }, additive: true),
                             kf("opacity", dp.map(\.alpha))], duration: life, delay: 0), forKey: "fx")
        b.addSublayer(trail)
        b.addSublayer(ring)
        b.addSublayer(drop)
    }

    /// Đèn ấm góc dưới phải: lớp gradient tròn dựng lười lần đầu cần, khung theo cỡ bàn phím (gốc bounds — #151).
    private func layoutRainGlow() {
        guard let g = rainGlow else { return }
        let w = Double(bounds.width), h = Double(bounds.height)
        let c = RainFx.glowCenter(width: w, height: h), rad = RainFx.glowRadius(width: w, height: h)
        let f = CGRect(x: Double(bounds.minX) + c.x - rad, y: Double(bounds.minY) + c.y - rad, width: 2 * rad, height: 2 * rad)
        guard g.frame != f else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        g.frame = f
        CATransaction.commit()
    }

    private func setRainGlow(_ level: Double) {
        let g: CAGradientLayer
        if let x = rainGlow { g = x } else {
            g = CAGradientLayer()
            g.type = .radial
            g.startPoint = CGPoint(x: 0.5, y: 0.5)
            g.endPoint = CGPoint(x: 1, y: 1)
            let c = UIColor(rgb: RainFx.glowColor)
            g.colors = RainFx.glowStops.map { c.withAlphaComponent(CGFloat($0.alpha)).cgColor }
            g.locations = RainFx.glowStops.map { NSNumber(value: $0.location) }
            g.opacity = 0
            layer.insertSublayer(g, at: 0)                // dưới hạt mưa / giọt
            rainGlow = g
            layoutRainGlow()
        }
        let from = (g.presentation()?.opacity ?? g.opacity)
        rainGlowLevel = level
        g.opacity = Float(level)
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = from; a.toValue = Float(level)
        a.duration = RainFx.glowFade
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)   // ≈ smoothstep (Android glowAt)
        a.isRemovedOnCompletion = true
        g.add(a, forKey: "glow")
    }

    /// MỘT asyncAfter cho cả loạt gõ: nghỉ đủ đời hạt ⇒ ẩn mọi hạt / giọt (không còn layer nào chạy), không timer lặp.
    private func scheduleRainSweep(after s: Double) {
        guard !rainSweepScheduled else { return }
        rainSweepScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + s) { [weak self] in
            guard let self else { return }
            self.rainSweepScheduled = false
            self.sweepRain(force: false)
        }
    }

    private func sweepRain(force: Bool) {
        guard effect == .rain else { return }
        let idle = CACurrentMediaTime() - rainLastKey
        let need = Swift.max(RainFx.dropLife, RainFx.tapLife)
        if !force && idle < need {
            scheduleRainSweep(after: need - idle + 0.05)
            return
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for d in rainDrops { d.isHidden = true }
        for b in bursts { b.isHidden = true }
        CATransaction.commit()
    }

    /// Ô xem thử (app): như đã gõ `keys` phím từ lúc bàn phím hiện — mưa thưa + đèn ấm theo đúng đường cong RainFx.
    func previewRain(keys: Int) {
        guard effect == .rain else { return }
        rainKeys = Swift.max(keys - 1, 0)
    }

    private func haltRain() {
        rainKeys = 0
        rainLastDrop = -.greatestFiniteMagnitude
        rainLastKey = -.greatestFiniteMagnitude
        rainGlowLevel = 0
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for d in rainDrops { d.isHidden = true }
        if effect == .rain { for b in bursts { b.isHidden = true } }
        rainGlow?.removeAllAnimations()
        rainGlow?.opacity = 0
        CATransaction.commit()
    }

    // MARK: Rep (theme Gym — RepsFx)
    // Thanh rep + huy hiệu + nhãn + chữ đập: layer dựng lười MỘT lần, animation keyframe lấy mẫu từ hàm thuần (RepsFx).
    // Nhãn / huy hiệu / chữ đập gắn animation một lần, bấm chỉ đổi vị trí + beginTime; thanh rep: animation tự gỡ khi xong
    // ⇒ nghỉ = 0 animation. Một asyncAfter (gộp) đưa hiệp về 0 sau `idleReset` giây nghỉ; ẩn bàn phím (halt) cũng vậy.

    /// Keyframe lấy mẫu `n` + 1 điểm đều trên [0, duration) từ hàm thuần `f`.
    private static func sampled(_ keyPath: String, duration: Double, steps n: Int, _ f: (Double) -> Double) -> CAKeyframeAnimation {
        let a = CAKeyframeAnimation(keyPath: keyPath)
        a.values = (0...n).map { f(duration * Double($0) / Double(n) * 0.9999) }
        a.keyTimes = (0...n).map { NSNumber(value: Double($0) / Double(n)) }
        a.duration = duration
        return a
    }

    /// Chữ trên nền màu nhấn: đen hay trắng tuỳ độ sáng.
    private static func inkOn(_ c: UIColor) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.299 * r + 0.587 * g + 0.114 * b > 0.55 ? UIColor(white: 0.07, alpha: 1) : .white
    }

    private var repBoundsTuple: (x: Double, y: Double, w: Double, h: Double) {
        (Double(bounds.minX), Double(bounds.minY), Double(bounds.width), Double(bounds.height))
    }

    private func fireRep(_ r: CGRect, now: CFTimeInterval, media: CFTimeInterval) {
        let ev = repCounter.press(at: media)
        let from = repFill
        repFill = ev.fill >= RepsFx.perSet ? 0 : ev.fill
        repLastMedia = media
        layoutRepBar()
        if let bar = repBar {
            bar.transform = CATransform3DMakeScale(CGFloat(max(Double(repFill) / Double(RepsFx.perSet), 1e-4)), 1, 1)
            let set = ev.completedSet != nil
            let a = Self.sampled("transform.scale.x", duration: set ? RepsFx.setLife : RepsFx.barStep, steps: set ? 24 : 2) {
                max(RepsFx.barFill(from: from, to: ev.fill, dt: $0), 1e-4)
            }
            bar.add(a, forKey: "fx")   // tự gỡ khi xong (isRemovedOnCompletion mặc định) ⇒ nghỉ = 0 animation
        }
        if let s = ev.completedSet { fireRepBadge(set: s, now: now) }
        if combo.press(at: media) >= 1 { fireRepLabel(r, now: now) }
        scheduleRepSweep(after: RepsFx.idleReset + 0.5)
    }

    private func layoutRepBar() {
        let track: CALayer
        if let t = repBarTrack { track = t } else {
            track = CALayer()
            track.backgroundColor = color.withAlphaComponent(0.22).cgColor
            track.cornerRadius = CGFloat(RepsFx.barHeight / 2)
            let b = CALayer()
            b.backgroundColor = color.cgColor
            b.cornerRadius = CGFloat(RepsFx.barHeight / 2)
            b.anchorPoint = CGPoint(x: 0, y: 0.5)
            b.transform = CATransform3DMakeScale(1e-4, 1, 1)
            track.addSublayer(b)
            layer.addSublayer(track)
            repBarTrack = track; repBar = b
        }
        let ins = CGFloat(RepsFx.barInset), h = CGFloat(RepsFx.barHeight)
        let f = CGRect(x: bounds.minX + ins, y: bounds.minY + ins, width: max(bounds.width - 2 * ins, 0), height: h)
        guard track.frame != f else { return }
        track.frame = f
        repBar?.bounds = CGRect(x: 0, y: 0, width: f.width, height: h)
        repBar?.position = CGPoint(x: 0, y: h / 2)
    }

    private func fireRepBadge(set: Int, now: CFTimeInterval) {
        let root: CALayer, text: CATextLayer
        if let r = repBadge, let t = repBadgeText { root = r; text = t } else {
            root = CALayer()
            root.backgroundColor = color.cgColor
            root.opacity = 0
            root.isHidden = true
            text = CATextLayer()
            let fs = CGFloat(RepsFx.badgeFont)
            text.font = UIFont.systemFont(ofSize: fs, weight: .heavy)
            text.fontSize = fs
            text.alignmentMode = .center
            text.contentsScale = UIScreen.main.scale
            text.foregroundColor = Self.inkOn(color).cgColor
            root.addSublayer(text)
            let times = RepsFx.badgeTimes.map { NSNumber(value: $0 / RepsFx.badgeDuration) }
            let scale = CAKeyframeAnimation(keyPath: "transform.scale")
            scale.values = RepsFx.badgeScales; scale.keyTimes = times
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = RepsFx.badgeAlphas; fade.keyTimes = times
            root.add(Self.group([scale, fade], duration: RepsFx.badgeDuration, delay: 0), forKey: "fx")
            layer.addSublayer(root)
            repBadge = root; repBadgeText = text
        }
        text.string = RepsFx.badgeText(set: set)
        let pref = text.preferredFrameSize()
        let maxScale = CGFloat(RepsFx.badgeScales.max() ?? 1)
        let h = CGFloat(RepsFx.badgeFont) + 9
        let w = min(pref.width + 18, max((bounds.width - 4) / maxScale, 1))
        root.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        root.cornerRadius = h / 2
        text.frame = CGRect(x: 0, y: (h - pref.height) / 2, width: w, height: pref.height)
        root.position = CGPoint(x: bounds.midX, y: bounds.minY + CGFloat(RepsFx.badgeY))
        root.beginTime = now
        root.isHidden = false
    }

    private func fireRepLabel(_ r: CGRect, now: CFTimeInterval) {
        if repLabelImage == nil { repLabelImage = Self.renderRepLabel(color: color, scale: UIScreen.main.scale) }
        let slot = repLabelPool.next()
        let l: CALayer
        if slot < repLabels.count { l = repLabels[slot] } else {
            l = CALayer()
            l.bounds = CGRect(x: 0, y: 0, width: RepsFx.labelHalfWidth * 2, height: RepsFx.labelHeight)
            l.contentsGravity = .resizeAspect
            l.contentsScale = UIScreen.main.scale
            l.opacity = 0
            l.isHidden = true
            let d = RepsFx.labelDuration
            let rise = Self.sampled("position.y", duration: d, steps: 8) { RepsFx.labelDy($0) }
            rise.isAdditive = true
            let fade = Self.sampled("opacity", duration: d, steps: 8) { RepsFx.labelAlpha($0) }
            let grow = Self.sampled("transform.scale", duration: d, steps: 8) { RepsFx.labelScale($0) }
            l.add(Self.group([rise, fade, grow], duration: d, delay: 0), forKey: "fx")
            layer.addSublayer(l)
            repLabels.append(l)
        }
        l.contents = repLabelImage
        repSeq &+= 1
        let size = r.size == .zero ? Self.defaultKeySize : r.size
        let top = r.size == .zero ? r.midY - size.height / 2 : r.minY
        let o = RepsFx.labelOrigin(keyMidX: Double(r.midX), keyTop: Double(top), seed: repSeq, bounds: repBoundsTuple)
        l.position = CGPoint(x: o.x, y: o.y)
        l.beginTime = now
        l.isHidden = false
    }

    /// "+1 rep 💪" vẽ MỘT lần mỗi màu (CATextLayer không vẽ emoji màu).
    static func renderRepLabel(color: UIColor, scale: CGFloat) -> CGImage? {
        let size = CGSize(width: RepsFx.labelHalfWidth * 2, height: RepsFx.labelHeight)
        let f = UIGraphicsImageRendererFormat()
        f.scale = scale
        f.opaque = false
        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: CGFloat(RepsFx.labelFont), weight: .heavy),
                                                    .foregroundColor: color]
        let s = RepsFx.labelText as NSString
        let sz = s.size(withAttributes: attrs)
        return UIGraphicsImageRenderer(size: size, format: f).image { _ in
            s.draw(at: CGPoint(x: (size.width - sz.width) / 2, y: (size.height - sz.height) / 2), withAttributes: attrs)
        }.cgImage
    }

    private func fireSlam(now: CFTimeInterval) {
        let root: CALayer, text: CATextLayer, ring: CAShapeLayer
        if let r = repSlam, let t = repSlamText, let g = repRing { root = r; text = t; ring = g } else {
            root = CALayer()
            root.bounds = .zero
            root.isHidden = true
            ring = CAShapeLayer()
            ring.fillColor = nil
            ring.strokeColor = color.cgColor
            ring.lineWidth = CGFloat(RepsFx.ringWidth)
            ring.opacity = 0
            let d = RepsFx.slamDuration
            ring.add(Self.group([Self.sampled("transform.scale", duration: d, steps: 16) { RepsFx.ringScale($0) },
                                 Self.sampled("opacity", duration: d, steps: 16) { RepsFx.ringAlpha($0) }],
                                duration: d, delay: 0), forKey: "fx")
            text = CATextLayer()
            text.alignmentMode = .center
            text.contentsScale = UIScreen.main.scale
            text.foregroundColor = color.cgColor
            text.opacity = 0
            let times = RepsFx.slamTimes.map { NSNumber(value: $0 / d) }
            let scale = CAKeyframeAnimation(keyPath: "transform.scale")
            scale.values = RepsFx.slamScales; scale.keyTimes = times
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = RepsFx.slamAlphas; fade.keyTimes = times
            text.add(Self.group([scale, fade], duration: d, delay: 0), forKey: "fx")
            root.addSublayer(ring)
            root.addSublayer(text)
            layer.addSublayer(root)
            repSlam = root; repSlamText = text; repRing = ring
        }
        let w = Double(bounds.width), h = Double(bounds.height)
        let rad = CGFloat(RepsFx.ringRadius(width: w, height: h))
        ring.path = CGPath(ellipseIn: CGRect(x: -rad, y: -rad, width: 2 * rad, height: 2 * rad), transform: nil)
        let fs = CGFloat(RepsFx.slamFont(width: w))
        if text.fontSize != fs {
            text.font = UIFont.systemFont(ofSize: fs, weight: .black)
            text.fontSize = fs
        }
        text.string = RepsFx.slamText
        text.bounds = CGRect(x: 0, y: 0, width: bounds.width, height: fs * 1.3)
        text.position = .zero
        root.position = CGPoint(x: bounds.midX, y: bounds.midY)
        root.beginTime = now
        root.isHidden = false
    }

    private func scheduleRepSweep(after s: Double) {
        guard !repSweepScheduled else { return }
        repSweepScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + s) { [weak self] in self?.sweepReps() }
    }

    /// Nghỉ đủ `idleReset` ⇒ hiệp về 0 (thanh rỗng); chưa đủ ⇒ hẹn lại phần còn lại. Một lần hẹn cho cả loạt gõ.
    private func sweepReps() {
        repSweepScheduled = false
        guard effect == .reps else { return }
        let idle = CACurrentMediaTime() - repLastMedia
        if idle <= RepsFx.idleReset { scheduleRepSweep(after: RepsFx.idleReset - idle + 0.5); return }
        resetReps()
    }

    /// Hiệp về 0 + ẩn mọi thứ đang bay (ẩn bàn phím / nghỉ lâu / đổi kiểu).
    private func resetReps() {
        repCounter.reset(); repFill = 0; pendingSlam = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        repBar?.removeAllAnimations()
        repBar?.transform = CATransform3DMakeScale(1e-4, 1, 1)
        repBadge?.isHidden = true
        repSlam?.isHidden = true
        for l in repLabels { l.isHidden = true }
        CATransaction.commit()
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
        case .sea:
            makeSeaSplash(into: b)
        case .rain:
            makeRainTap(into: b)
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
        kaleido?.remove(); kaleido = nil
        paths = (0..<max(effect.particlesPerTap, 1)).map { KeyEffectShapes.path(effect, particle: $0) }
        pool = KeyEffectPool(capacity: effect.burstSlots)
        strikePool = KeyEffectPool(capacity: Strike.cap)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for b in bursts { b.removeFromSuperlayer() }
        for s in strikes { s.root.removeFromSuperlayer() }
        for l in strings { l.removeFromSuperlayer() }
        for a in arcs { a.root.removeFromSuperlayer() }
        for b in beams { b.root.removeFromSuperlayer() }
        for g in glitches { g.root.removeFromSuperlayer() }
        for l in toneRoots.values.joined() { l.removeFromSuperlayer() }
        for l in keywordRoots.values.joined() { l.removeFromSuperlayer() }
        for l in letters { l.removeFromSuperlayer() }
        for b in tokenBursts { b.root.removeFromSuperlayer() }
        shimmerClip?.removeFromSuperlayer()
        for g in grains { g.removeFromSuperlayer() }
        for d in dances { d.root.removeFromSuperlayer() }
        floorFlicker?.root.removeFromSuperlayer()
        merit?.remove(); merit = nil
        sunlight?.remove(); sunlight = nil
        repBarTrack?.removeFromSuperlayer(); repBadge?.removeFromSuperlayer(); repSlam?.removeFromSuperlayer()
        for l in repLabels { l.removeFromSuperlayer() }
        sandPile?.removeFromSuperlayer()
        for w in seaWaves { w.root.removeFromSuperlayer() }
        seaFish?.removeFromSuperlayer()
        for d in rainDrops { d.removeFromSuperlayer() }
        rainGlow?.removeFromSuperlayer()
        flashLayer?.removeFromSuperlayer()
        matrixRoot?.removeFromSuperlayer()
        CATransaction.commit()
        bursts.removeAll()
        strikes.removeAll()
        strings.removeAll()
        stringPool = KeyEffectPool(capacity: StringPluck.pool)
        arcs.removeAll(); arcPool = KeyEffectPool(capacity: PlasmaArc.pool); plasma.reset()
        beams.removeAll(); beamPool = KeyEffectPool(capacity: LaserBeam.pool)
        glitches.removeAll(); glitchPool = KeyEffectPool(capacity: GlitchFx.pool)
        toneRoots.removeAll(); toneCursor.removeAll()
        keywordRoots.removeAll(); keywordCursor.removeAll()
        letters.removeAll(); letterPool = KeyEffectPool(capacity: FlyingLetters.pool)
        tokenBursts.removeAll(); tokenPool = KeyEffectPool(capacity: TokenStream.pool)
        shimmerClip = nil; shimmerBand = nil; shimmerGate.reset()
        grains.removeAll(); grainPool = KeyEffectPool(capacity: SandPile.flying)
        sandPile = nil; sand = nil; pendingLandings.removeAll()
        seaWaves.removeAll(); seaBuiltFor = .zero; seaCursor = 0; seaFish = nil; seaFishSeq = 0
        seaLastWave = -.greatestFiniteMagnitude; seaLastFish = -.greatestFiniteMagnitude; seaLevel = 0
        dances.removeAll(); dancePool = KeyEffectPool(capacity: DanceFloor.pool); danceSeq = 0
        rainDrops.removeAll(); rainBuiltFor = .zero; rainCursor = 0; rainSeq = 0; rainGlow = nil
        rainKeys = 0; rainGlowLevel = 0; rainLastDrop = -.greatestFiniteMagnitude; rainLastKey = -.greatestFiniteMagnitude
        floorFlicker = nil; flickerGate = DanceFloor.FlickerGate()
        tunnel?.remove(); tunnel = nil
        repBarTrack = nil; repBar = nil; repBadge = nil; repBadgeText = nil; repSlam = nil; repSlamText = nil; repRing = nil
        repLabels.removeAll(); repLabelPool = KeyEffectPool(capacity: RepsFx.labelCap); repLabelImage = nil
        repCounter.reset(); repFill = 0; pendingSlam = false
        if effect != .shake { shakeTarget?.layer.removeAnimation(forKey: Self.shakeKey) }
        shakeMeter.reset()
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
        if effect != .emojiword && effect != .keyword && effect != .sea { emojiImages = [:] }
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
        case .emojiword where emojiImages.isEmpty, .keyword where emojiImages.isEmpty, .sea where emojiImages.isEmpty:
            let want = effect
            let list = effect == .keyword ? KeywordBursts.allEmojis : effect == .sea ? SeaFx.fishGlyphs : EmojiWords.distinctEmojis
            DispatchQueue.global(qos: .utility).async { [weak self] in
                var imgs: [String: CGImage] = [:]
                for e in list { imgs[e] = Self.renderEmoji(e, scale: scale) }
                DispatchQueue.main.async {
                    guard let self, self.effect == want else { return }
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

    /// `easeIn`: rơi nhanh dần (giọt nặng, xác pháo); `scaleXOnly`: giãn ngang (sóng ngã); `delay`: trễ trong chùm;
    /// `hiddenBefore`: vô hình tới lúc bắt đầu (hạt trễ); `fadeAt`: bắt đầu mờ (tỉ lệ thời gian).
    private static func makeAnimation(_ t: KeyEffectTrajectory, easeIn: Bool = false, scaleXOnly: Bool = false,
                                      delay: Double = 0, hiddenBefore: Bool = false, fadeAt: Double = 0.5) -> CAAnimationGroup {
        let move = CABasicAnimation(keyPath: "position")
        move.isAdditive = true
        move.fromValue = NSValue(cgPoint: .zero)
        move.toValue = NSValue(cgPoint: CGPoint(x: t.dx, y: t.dy))
        move.timingFunction = CAMediaTimingFunction(name: easeIn ? .easeIn : .easeOut)
        let scale = CABasicAnimation(keyPath: scaleXOnly ? "transform.scale.x" : "transform.scale")
        scale.fromValue = t.scaleFrom
        scale.toValue = t.scaleTo
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        if hiddenBefore {
            fade.values = [0, 1, 1, 0]
            fade.keyTimes = [0, 0.01, NSNumber(value: fadeAt), 1]
        } else {
            fade.values = [1, 1, 0]
            fade.keyTimes = [0, NSNumber(value: fadeAt), 1]
        }
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
        return group(parts, duration: t.duration, delay: delay)
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

    /// Sao 4 cánh (tia lửa Dấu thanh / pháo Từ khoá) — = Android star4.
    static func star4(_ r: CGFloat, inner: CGFloat) -> CGPath {
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
