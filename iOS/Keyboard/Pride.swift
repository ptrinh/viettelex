// Theme "Tự hào" (11/2026, Plus): nền tối, viền phím gradient theo màu cờ (borderFx "aurora" với dải màu cờ — tĩnh, vẽ một
// lần), chữ trắng; hiệu ứng "Cầu vồng" (rainbowburst): mỗi phím một vòng cung cầu vồng mềm lan ra từ phím rồi mờ (~0,8 s);
// gõ xong "love is love", "tự hào", "pride", "yêu là yêu" ⇒ lá cờ phấp phới + tim tung (~1,2 s). Người dùng chọn lá cờ ở
// trang Giao diện: Cầu vồng (mặc định), Chuyển giới, Song tính, Toàn tính, Đồng tính nữ, Phi nhị nguyên — đổi bảng màu
// + màu hiệu ứng. CHỈ lưu id cờ (`prideFlag`, App Group + sao lưu). Hàm thuần + bảng màu dùng chung Android (Pride.kt).
import Foundation

enum PrideFlag: String, CaseIterable {
    case rainbow, trans, bi, pan, lesbian, nonbinary

    static let key = "prideFlag"
    static let defaultValue: PrideFlag = .rainbow
    static func parse(_ raw: Any?) -> PrideFlag { (raw as? String).flatMap(PrideFlag.init(rawValue:)) ?? defaultValue }
    static func load(_ d: UserDefaults?) -> PrideFlag { parse(d?.object(forKey: key)) }

    var title: String {
        switch self {
        case .rainbow: return L("Cầu vồng")
        case .trans: return L("Chuyển giới")
        case .bi: return L("Song tính")
        case .pan: return L("Toàn tính")
        case .lesbian: return L("Đồng tính nữ")
        case .nonbinary: return L("Phi nhị nguyên")
        }
    }

    /** Các sọc cờ (RGB, trên → dưới) — ≤ 6 sọc (trần layer hiệu ứng). */
    var stripes: [UInt32] {
        switch self {
        case .rainbow: return [0xE40303, 0xFF8C00, 0xFFED00, 0x008026, 0x004DFF, 0x750787]
        case .trans: return [0x5BCEFA, 0xF5A9B8, 0xFFFFFF, 0xF5A9B8, 0x5BCEFA]
        case .bi: return [0xD60270, 0x9B4F96, 0x0038A8]
        case .pan: return [0xFF218C, 0xFFD800, 0x21B1FF]
        case .lesbian: return [0xD52D00, 0xFF9A56, 0xFFFFFF, 0xD362A4, 0xA30262]
        case .nonbinary: return [0xFCF434, 0xFFFFFF, 0x9C59D1, 0x2C2C2C]
        }
    }

    /// Bảng màu (nền tối, phím tối, chữ trắng; nhấn + chữ chức năng theo cờ). Tương phản ≥ 4,5 (test). Android y hệt.
    var slots: ThemeSlots {
        var s = ThemeSlots()
        s.bg = 0xFF0E_0E14; s.key = 0xFF1E_1E28; s.special = 0xFF2C_2C3A; s.ink = 0xFFFF_FFFF; s.fn = 0xFF16_161F
        switch self {
        case .rainbow: s.accent = 0xFFFF_8C00; s.accentInk = 0xFF1A_0A00; s.fnInk = 0xFFFF_ED00
        case .trans: s.accent = 0xFF5B_CEFA; s.accentInk = 0xFF06_222E; s.fnInk = 0xFFF5_A9B8
        case .bi: s.accent = 0xFFD6_0270; s.accentInk = 0xFFFF_FFFF; s.fnInk = 0xFFF3_8FC4
        case .pan: s.accent = 0xFFFF_D800; s.accentInk = 0xFF1A_1500; s.fnInk = 0xFF21_B1FF
        case .lesbian: s.accent = 0xFFEF_7627; s.accentInk = 0xFF1A_0A00; s.fnInk = 0xFFFF_9A56
        case .nonbinary: s.accent = 0xFFFC_F434; s.accentInk = 0xFF1A_1800; s.fnInk = 0xFFC9_A2EE
        }
        s.borderFx = ThemeSlots.aurora
        s.deco = ThemeDeco(motif: .hearts, color: 0x26FF_FFFF)
        return s
    }
}

/// "Cầu vồng": vòng cung (nửa trên) các sọc cờ lan ra từ phím rồi mờ. Hằng số + hàm thuần — Android RainbowBurst y hệt.
enum RainbowBurst {
    static let life = 0.8
    static let fadeIn = 0.08
    static let peakAlpha = 0.9
    /// Bán kính ngoài khi nở hết (pt / dp) + bề dày mỗi sọc.
    static let outerRadius = 46.0
    static let band = 3.2
    /// Cỡ lúc bắt đầu (tỉ lệ so với nở hết).
    static let startScale = 0.15
    /// Số chùm xoay vòng (× ≤ 6 sọc = ≤ 18 layer).
    static let pool = 3

    /// Bán kính tâm sọc `i` (0 = ngoài cùng) khi nở hết.
    static func radius(_ i: Int) -> Double { outerRadius - (Double(i) + 0.5) * band }
    static func alpha(_ t: Double) -> Double {
        if t < 0 || t >= life { return 0 }
        if t < fadeIn { return peakAlpha * t / fadeIn }
        return peakAlpha * (1 - (t - fadeIn) / (life - fadeIn))
    }
    /// Tỉ lệ nở (ease-out bậc hai).
    static func scale(_ t: Double) -> Double {
        let f = min(max(t / life, 0), 1)
        return startScale + (1 - startScale) * (1 - (1 - f) * (1 - f))
    }
}

/// Lá cờ phấp phới + tim tung khi gõ từ khoá. Hình học thuần (pt / dp, gốc = điểm giữa mép trên phím). Android y hệt.
enum PrideFlagWave {
    static let life = 1.2
    static let width = 56.0, height = 36.0
    /// Mép dưới cờ cách mép trên phím; biên độ sóng lớn nhất (đầu tự do bên phải); số cột lấy mẫu.
    static let gap = 10.0, amplitude = 3.5, columns = 8
    /// Số vòng sóng chạy qua cờ trong một đời; cờ bay lên chừng này (pt / dp).
    static let waves = 2.0, rise = 8.0
    static let poleWidth = 2.0
    /// Số khung lấy mẫu cho animation đường viền (iOS).
    static let frames = 12

    static func phase(_ t: Double) -> Double { 2 * Double.pi * waves * min(max(t / life, 0), 1) }
    /// Độ dời dọc của điểm có hoành độ `x` (0…width) trên cột cờ ở pha `phase` — cán cờ (x = 0) đứng yên.
    static func offset(_ x: Double, phase: Double) -> Double {
        amplitude * (x / width) * sin(2 * Double.pi * x / width - phase)
    }
    /// Đa giác sọc `i`/`n` ở pha `phase`: mép trên (trái → phải) rồi mép dưới (phải → trái), toạ độ quanh gốc.
    static func stripe(_ i: Int, of n: Int, phase: Double) -> [(x: Double, y: Double)] {
        let x0 = -width / 2, top = -gap - height
        let y0 = top + height * Double(i) / Double(n), y1 = top + height * Double(i + 1) / Double(n)
        var out: [(x: Double, y: Double)] = []
        for c in 0...columns {
            let x = width * Double(c) / Double(columns)
            out.append((x0 + x, y0 + offset(x, phase: phase)))
        }
        for c in stride(from: columns, through: 0, by: -1) {
            let x = width * Double(c) / Double(columns)
            out.append((x0 + x, y1 + offset(x, phase: phase)))
        }
        return out
    }
    static func alpha(_ t: Double) -> Double {
        if t < 0 || t >= life { return 0 }
        if t < 0.15 { return t / 0.15 }
        if t < 0.85 { return 1 }
        return max(0, 1 - (t - 0.85) / (life - 0.85))
    }
    static func riseY(_ t: Double) -> Double { -rise * min(max(t / life, 0), 1) }

    /// Tim tung: 8 tim màu sọc cờ (tim k dùng sọc k % số sọc), quỹ đạo quạt lên.
    static let hearts = 8
    static func heart(_ k: Int) -> KeyEffectTrajectory {
        let t = Double(k) - 3.5
        return KeyEffectTrajectory(dx: t * 12, dy: -(40 + Double(k % 3) * 10), scaleFrom: 0.5, scaleTo: 1.0,
                                   rotation: t * 0.15, duration: 1.1, sway: 5)
    }
    static func heartDelay(_ k: Int) -> Double { Double(k) * 0.03 }
}

/// Từ khoá của theme Tự hào — khớp ở RANH GIỚI TỪ (từ vừa chốt + tối đa hai từ trước), không phân biệt hoa thường; tiếng
/// Việt khớp ĐÚNG dấu ("tự hào" ≠ "tu hao"). Android PrideKeywords y hệt.
enum PrideKeywords {
    static let phrases: [[String]] = [["love", "is", "love"], ["tự", "hào"], ["pride"], ["yêu", "là", "yêu"]]
    private static func clean(_ s: String) -> String { s.trimmingCharacters(in: CharacterSet.letters.inverted).lowercased() }

    static func matches(word: String, prev: String?, prev2: String?) -> Bool {
        let w = clean(word)
        guard !w.isEmpty else { return false }
        let tail = [prev2.map(clean) ?? "", prev.map(clean) ?? "", w]
        return phrases.contains { p in Array(tail.suffix(p.count)) == p }
    }
}
