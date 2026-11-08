// Theme "Cung hoàng đạo" (11/2026, Plus): người dùng chọn cung của mình ở trang Giao diện (app) — bàn phím đổi bảng màu
// theo NGUYÊN TỐ của cung (Lửa / Đất / Khí / Nước) trên nền trời đêm, ký hiệu cung mờ ở góc, hiệu ứng "Chòm sao".
//
// Riêng tư: CHỈ lưu id cung (`zodiacSign`, App Group + sao lưu). "Tính từ ngày sinh" nhận ngày / tháng (không năm), tính
// cung rồi bỏ — không lưu ngày.
//
// Mốc ngày (cung hoàng đạo NHIỆT ĐỚI, bảng phổ biến — ngày bắt đầu mỗi cung, gồm cả ngày đó):
//   Bảo Bình 20/1 · Song Ngư 19/2 · Bạch Dương 21/3 · Kim Ngưu 20/4 · Song Tử 21/5 · Cự Giải 21/6 · Sư Tử 23/7 ·
//   Xử Nữ 23/8 · Thiên Bình 23/9 · Bọ Cạp 23/10 · Nhân Mã 22/11 · Ma Kết 22/12 (tới hết 19/1).
// Ví dụ biên: 20/3 = Song Ngư, 21/3 = Bạch Dương; 19/1 = Ma Kết, 20/1 = Bảo Bình. 29/2 hợp lệ (Song Ngư).
//
// "Chòm sao" (KeyEffect.constellation): MỖI PHÍM thắp thêm MỘT sao của chòm (theo thứ tự trong bảng), nối bằng nét mảnh
// tới các sao đã thắp; đủ sao ⇒ cả chòm loé sáng ngắn rồi mờ; phím kế bắt đầu chòm mới quanh phím đó. Nghỉ quá
// `resetGap` ⇒ chòm dở mờ đi, phím kế bắt đầu lại. Dữ liệu sao (toạ độ trong hộp đơn vị, y xuống) + luật thắp / mờ là
// hàm thuần DÙNG CHUNG Android (Zodiac.kt — test số chung).
import Foundation

/// Nguyên tố — quyết định bảng màu.
enum ZodiacElement: String, CaseIterable {
    case fire, earth, air, water

    var title: String {
        switch self {
        case .fire: return L("Hệ Lửa")
        case .earth: return L("Hệ Đất")
        case .air: return L("Hệ Khí")
        case .water: return L("Hệ Nước")
        }
    }

    /// Bảng màu (nền trời đêm, chữ sáng; "dark":"same"). Tương phản chữ/phím, chữ/phím chức năng, chữ/nhấn ≥ 4,5
    /// (test). Android ZodiacElement.slots y hệt.
    var slots: ThemeSlots {
        var s = ThemeSlots()
        switch self {
        case .fire:   // đỏ cam — vàng kim
            s.bg = 0xFF12_0A1F; s.key = 0xFF2A_1530; s.special = 0xFF3D_1C38; s.ink = 0xFFFF_F4E6
            s.accent = 0xFFFF_7A2F; s.accentInk = 0xFF1A_0A00; s.fn = 0xFF1E_1028; s.fnInk = 0xFFFF_C857
            s.deco = ThemeDeco(motif: .starfield, color: 0x66FF_D9A0)
        case .earth:  // xanh lá — nâu
            s.bg = 0xFF0C_1A12; s.key = 0xFF1C_2E22; s.special = 0xFF2A_3F2E; s.ink = 0xFFF1_EBDD
            s.accent = 0xFF8D_BF5A; s.accentInk = 0xFF0C_1A12; s.fn = 0xFF14_241A; s.fnInk = 0xFFD9_B88C
            s.deco = ThemeDeco(motif: .starfield, color: 0x59E8_E0C8)
        case .air:    // xanh trời — tím
            s.bg = 0xFF0D_1030; s.key = 0xFF1F_2350; s.special = 0xFF2E_3370; s.ink = 0xFFF2_F0FF
            s.accent = 0xFF8E_C5FF; s.accentInk = 0xFF0D_1030; s.fn = 0xFF16_1A40; s.fnInk = 0xFFC9_B5FF
            s.deco = ThemeDeco(motif: .starfield, color: 0x66C9_D6FF)
        case .water:  // xanh biển sâu — lam ngọc
            s.bg = 0xFF05_1A2A; s.key = 0xFF0E_2E44; s.special = 0xFF16_4260; s.ink = 0xFFE6_FAFF
            s.accent = 0xFF2B_C4C4; s.accentInk = 0xFF04_202A; s.fn = 0xFF0A_2438; s.fnInk = 0xFF7F_E3E0
            s.deco = ThemeDeco(motif: .starfield, color: 0x5999_E6FF)
        }
        return s
    }
}

/// 12 cung (rawValue = giá trị lưu `zodiacSign`, cùng Android). Thứ tự = thứ tự trong năm bắt đầu từ Bạch Dương.
enum ZodiacSign: String, CaseIterable {
    case aries, taurus, gemini, cancer, leo, virgo, libra, scorpio, sagittarius, capricorn, aquarius, pisces

    static let key = "zodiacSign"
    static let defaultValue: ZodiacSign = .aries

    /// Giá trị lạ / thiếu ⇒ Bạch Dương.
    static func parse(_ raw: Any?) -> ZodiacSign { (raw as? String).flatMap(ZodiacSign.init(rawValue:)) ?? defaultValue }
    static func load(_ d: UserDefaults?) -> ZodiacSign { parse(d?.object(forKey: key)) }

    var title: String {
        switch self {
        case .aries: return L("Bạch Dương")
        case .taurus: return L("Kim Ngưu")
        case .gemini: return L("Song Tử")
        case .cancer: return L("Cự Giải")
        case .leo: return L("Sư Tử")
        case .virgo: return L("Xử Nữ")
        case .libra: return L("Thiên Bình")
        case .scorpio: return L("Bọ Cạp")
        case .sagittarius: return L("Nhân Mã")
        case .capricorn: return L("Ma Kết")
        case .aquarius: return L("Bảo Bình")
        case .pisces: return L("Song Ngư")
        }
    }

    /// Ký hiệu ♈…♓ + U+FE0E (dạng chữ, không emoji màu).
    var glyph: String {
        let base = 0x2648 + (Self.allCases.firstIndex(of: self) ?? 0)
        return String(UnicodeScalar(UInt32(base))!) + "\u{FE0E}"
    }

    var element: ZodiacElement {
        switch self {
        case .aries, .leo, .sagittarius: return .fire
        case .taurus, .virgo, .capricorn: return .earth
        case .gemini, .libra, .aquarius: return .air
        case .cancer, .scorpio, .pisces: return .water
        }
    }

    /// Ngày bắt đầu (tháng, ngày) — theo thứ tự trong năm dương lịch (Bảo Bình đầu).
    static let starts: [(sign: ZodiacSign, month: Int, day: Int)] = [
        (.aquarius, 1, 20), (.pisces, 2, 19), (.aries, 3, 21), (.taurus, 4, 20), (.gemini, 5, 21), (.cancer, 6, 21),
        (.leo, 7, 23), (.virgo, 8, 23), (.libra, 9, 23), (.scorpio, 10, 23), (.sagittarius, 11, 22), (.capricorn, 12, 22),
    ]
    private static let monthDays = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

    /// "Tính từ ngày sinh": ngày / tháng (không năm; 29/2 hợp lệ) ⇒ cung. Ngày không tồn tại ⇒ nil.
    static func from(day: Int, month: Int) -> ZodiacSign? {
        guard (1...12).contains(month), (1...monthDays[month - 1]).contains(day) else { return nil }
        var out: ZodiacSign = .capricorn   // 1/1 … 19/1
        for s in starts where (month, day) >= (s.month, s.day) { out = s.sign }
        return out
    }

    // MARK: Chòm sao (giản lược; toạ độ trong hộp đơn vị 0…1, y xuống — Android y hệt)

    struct Constellation: Equatable {
        var stars: [ZodiacStar]
        /// Cạnh (i, j) — mỗi sao k > 0 có ít nhất một cạnh tới sao trước nó (thắp sao k ⇒ nét nối hiện cùng).
        var edges: [ZodiacEdge]
        /// Cạnh "thuộc" sao k (sao có chỉ số lớn hơn của cạnh) — hiện khi sao k thắp.
        func edges(ownedBy k: Int) -> [ZodiacEdge] { edges.filter { max($0.a, $0.b) == k } }
    }

    var constellation: Constellation {
        func c(_ s: [(Double, Double)], _ e: [(Int, Int)]) -> Constellation {
            Constellation(stars: s.map { ZodiacStar(x: $0.0, y: $0.1) }, edges: e.map { ZodiacEdge(a: $0.0, b: $0.1) })
        }
        switch self {
        case .aries:
            return c([(0.08, 0.62), (0.42, 0.38), (0.70, 0.42), (0.90, 0.58)], [(0, 1), (1, 2), (2, 3)])
        case .taurus:
            return c([(0.08, 0.12), (0.38, 0.45), (0.52, 0.60), (0.62, 0.44), (0.92, 0.20), (0.30, 0.85)],
                     [(0, 1), (1, 2), (2, 3), (3, 4), (2, 5)])
        case .gemini:
            return c([(0.20, 0.08), (0.22, 0.48), (0.16, 0.92), (0.52, 0.12), (0.56, 0.50), (0.64, 0.92)],
                     [(0, 1), (1, 2), (0, 3), (3, 4), (4, 5), (1, 4)])
        case .cancer:
            return c([(0.52, 0.08), (0.50, 0.45), (0.62, 0.55), (0.18, 0.90), (0.86, 0.88)],
                     [(0, 1), (1, 2), (1, 3), (2, 4)])
        case .leo:
            return c([(0.36, 0.08), (0.20, 0.16), (0.14, 0.34), (0.26, 0.46), (0.30, 0.70), (0.60, 0.50), (0.92, 0.62),
                      (0.66, 0.78)],
                     [(0, 1), (1, 2), (2, 3), (3, 4), (3, 5), (5, 6), (6, 7), (4, 7)])
        case .virgo:
            return c([(0.10, 0.30), (0.32, 0.38), (0.50, 0.30), (0.70, 0.40), (0.55, 0.62), (0.80, 0.90), (0.30, 0.70)],
                     [(0, 1), (1, 2), (2, 3), (2, 4), (4, 5), (1, 6), (4, 6)])
        case .libra:
            return c([(0.50, 0.10), (0.15, 0.45), (0.85, 0.45), (0.30, 0.90)], [(0, 1), (0, 2), (1, 2), (1, 3)])
        case .scorpio:
            return c([(0.10, 0.15), (0.16, 0.30), (0.10, 0.45), (0.30, 0.40), (0.45, 0.55), (0.55, 0.72), (0.70, 0.85),
                      (0.88, 0.78), (0.92, 0.60)],
                     [(0, 1), (1, 2), (1, 3), (3, 4), (4, 5), (5, 6), (6, 7), (7, 8)])
        case .sagittarius:
            return c([(0.20, 0.35), (0.40, 0.30), (0.55, 0.15), (0.70, 0.30), (0.88, 0.40), (0.70, 0.62), (0.40, 0.68),
                      (0.15, 0.75)],
                     [(0, 1), (1, 2), (2, 3), (1, 3), (3, 4), (4, 5), (5, 6), (1, 6), (6, 7), (0, 7)])
        case .capricorn:
            return c([(0.10, 0.20), (0.30, 0.55), (0.55, 0.85), (0.80, 0.60), (0.92, 0.25), (0.50, 0.30)],
                     [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (0, 5)])
        case .aquarius:
            return c([(0.08, 0.30), (0.25, 0.20), (0.40, 0.35), (0.55, 0.25), (0.70, 0.45), (0.60, 0.70), (0.85, 0.85)],
                     [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (5, 6)])
        case .pisces:
            return c([(0.10, 0.15), (0.22, 0.35), (0.35, 0.58), (0.50, 0.88), (0.65, 0.62), (0.80, 0.45), (0.90, 0.30),
                      (0.78, 0.22)],
                     [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (5, 6), (6, 7), (5, 7)])
        }
    }
}

struct ZodiacStar: Equatable { var x: Double; var y: Double }
struct ZodiacEdge: Equatable { var a: Int; var b: Int }

/// Hằng số + hàm thuần của hiệu ứng "Chòm sao" (Android ConstellationFx y hệt — test số chung).
enum ConstellationFx {
    /// Sao thắp: mờ → rõ + nở 0,3 → 1 (giây).
    static let starFadeIn = 0.18
    /// Nghỉ quá chừng này (giây) ⇒ chòm dở mờ đi; phím kế bắt đầu chòm mới.
    static let resetGap = 2.4
    static let fadeOut = 0.5
    /// Đủ sao: loé sáng (quầng quanh mọi sao) rồi mờ cả chòm.
    static let glowTime = 0.4
    static let glowFade = 0.6
    /// Số chòm xoay vòng (chòm vừa xong còn đang mờ khi chòm mới bắt đầu).
    static let pool = 2
    /// Hộp chòm sao: rộng = min(rộng bàn phím × widthFactor, maxWidth); cao = rộng × aspect, ≤ cao × maxHeightFactor.
    static let widthFactor = 0.6, maxWidth = 240.0, aspect = 0.6, maxHeightFactor = 0.7, margin = 6.0
    /// Cỡ vẽ (pt / dp): bán kính sao (hình sao 4 cánh), quầng loé, nét nối.
    static let starRadius = 3.2, starInner = 1.1, haloRadius = 7.0, lineWidth = 1.0, lineAlpha = 0.65
    /// Màu sao (trắng ấm) — nét nối + quầng theo màu nhấn của theme.
    static let starColor: UInt32 = 0xFFF6D8

    /// Hộp (x, y, w, h) quanh phím (cx, cy) — luôn nằm trong `bounds` (kể cả khi gốc bounds bị dời — #151).
    static func box(cx: Double, cy: Double, bounds b: (x: Double, y: Double, w: Double, h: Double))
        -> (x: Double, y: Double, w: Double, h: Double) {
        let availW = max(b.w - 2 * margin, 1), availH = max(b.h - 2 * margin, 1)
        var w = min(b.w * widthFactor, maxWidth, availW)
        var h = w * aspect
        let maxH = min(b.h * maxHeightFactor, availH)
        if h > maxH { h = maxH; w = min(h / aspect, availW) }
        let x = min(max(cx - w / 2, b.x + margin), b.x + b.w - margin - w)
        let y = min(max(cy - h * 0.75, b.y + margin), b.y + b.h - margin - h)
        return (x, y, w, h)
    }

    /// Toạ độ sao trong hộp.
    static func point(_ s: ZodiacStar, box: (x: Double, y: Double, w: Double, h: Double)) -> (x: Double, y: Double) {
        (box.x + s.x * box.w, box.y + s.y * box.h)
    }

    /// Độ rõ của sao `dt` giây sau khi thắp.
    static func starAlpha(_ dt: Double) -> Double { dt < 0 ? 0 : min(1, dt / starFadeIn) }
    /// Độ rõ cả chòm: chưa xong ⇒ `dt` tính từ phím cuối (giữ `resetGap` rồi mờ `fadeOut`); xong ⇒ `dt` tính từ lúc
    /// đủ sao (giữ `glowTime` rồi mờ `glowFade`).
    static func cycleAlpha(_ dt: Double, completed: Bool) -> Double {
        let hold = completed ? glowTime : resetGap, fade = completed ? glowFade : fadeOut
        if dt < 0 { return 1 }
        if dt < hold { return 1 }
        return max(0, 1 - (dt - hold) / fade)
    }
    /// Quầng loé khi đủ sao (`dt` từ lúc đủ): lên nhanh 0 → 0,85 (0,15 s), xuống tới 0 ở glowTime + glowFade.
    static func glowAlpha(_ dt: Double) -> Double {
        let up = 0.15, peak = 0.85, end = glowTime + glowFade
        if dt < 0 || dt >= end { return 0 }
        if dt < up { return peak * dt / up }
        return peak * (1 - (dt - up) / (end - up))
    }
    /// Đời tối đa của một chòm sau phím cuối (giây).
    static func lifetime(completed: Bool) -> Double { completed ? glowTime + glowFade : resetGap + fadeOut }
}

/// Luật thắp sao theo phím (thuần — test được; Android ConstellationTrace y hệt).
struct ConstellationTrace {
    struct Step: Equatable {
        /// Chỉ số sao vừa thắp.
        var star: Int
        /// Phím này mở chòm mới (chòm cũ xong / nghỉ quá lâu / lần đầu).
        var newCycle: Bool
        /// Phím này thắp sao cuối ⇒ loé + mờ.
        var completes: Bool
    }
    let count: Int
    private(set) var lit = 0
    private(set) var cycle = 0
    private(set) var last = -Double.greatestFiniteMagnitude
    init(count: Int) { self.count = max(1, count) }

    mutating func press(at t: Double) -> Step {
        let fresh = lit == 0 || lit >= count || t - last > ConstellationFx.resetGap
        if fresh { lit = 0; cycle += 1 }
        let star = lit
        lit += 1
        last = t
        return Step(star: star, newCycle: fresh, completes: lit >= count)
    }
}
