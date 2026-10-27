// KeySoundSynth — tổng hợp âm phím (thuần, tất định, test được). Dùng CHUNG app + bàn phím
// (Shared/): bàn phím phát, app nghe thử + nhập âm tự chọn. Thuật toán + công thức Y HỆT
// android/keyboard/.../KeySoundSynth.kt (test chốt cùng checksum hai bên).
//
// Phil 28/09/2026: bản đầu (sine 900–1850 Hz + nhiễu 1–6 kHz, mở 0.4 ms) "chói" ⇒ làm lại:
// thân sine TRẦM-TRUNG (200–700 Hz) có trượt cao độ nhẹ, nhiễu LỌC THẤP (≤ 3.5 kHz), mở mềm
// (raised-cosine 0.8–3 ms), đóng mềm, lọc thấp đầu ra. Test chốt trọng tâm phổ (spectral
// centroid) dưới ngưỡng ⇒ "không chói" đo được.
//
// CÔNG THỨC (mỗi kiểu = danh sách lớp; thời gian giây, tần số Hz):
//   tone: biên độ amp, trễ delay, cao độ f(t) = fEnd + (f0 − fEnd)·e^(−t/glide), tắt dần e^(−t/tau)
//   noise: nhiễu trắng xorshift32 (seed) → high-pass 1 cực hp → low-pass 2 cực lp, tắt dần tau
//   mỗi lớp mở raised-cosine `attack`; tổng → low-pass 1 cực `outLP` → chặn DC 40 Hz → đóng raised-cosine 3 ms
//   → chuẩn hoá đỉnh `peak`.
//   Phím xoá: cao độ ×0.86; phím chức năng (cách/Enter/shift): cao độ ×0.74, tắt chậm ×1.2,
//   dài thêm 6 ms — khác nhẹ như stock.
//
//   Nhẹ nhàng (mặc định): thân 500→360 Hz τ7 ms + bồi 1050→900 Hz τ2.5 ms (0.24) + nhiễu
//     lp 1.9 kHz τ2 ms (0.30); mở 1.6 ms; 32 ms; outLP 2.6 kHz; đỉnh 0.80.
//   Gõ gỗ: 640→590 Hz τ9 ms + mode 2.72× τ2.6 ms (0.28) + nhiễu lp 2.4 kHz τ1.4 ms (0.30); mở 0.9 ms; 42 ms.
//   Bàn phím cơ (thock): 230→180 Hz τ12 ms + 520→450 Hz τ4.5 ms (0.55) + nhiễu lp 1.3 kHz τ3.5 ms (0.55)
//     + chạm đáy trễ 7 ms (300 Hz τ5 ms 0.45 + nhiễu 0.28); mở 1.4 ms; 46 ms.
//   Máy chữ (êm): nhiễu hp 500 Hz lp 2.6 kHz τ2.8 ms (0.95) + 1050→850 Hz τ3 ms (0.35) + thân 260 Hz τ8 ms
//     (0.55) + tiếng "tách" nhỏ trễ 11 ms (nhiễu 0.30 τ1.8 ms); mở 0.8 ms; 44 ms; outLP 3.2 kHz; đỉnh 0.85.
//   Bong bóng: sine trượt LÊN 260→720 Hz (glide 9 ms) τ9 ms + bồi 2× (0.08); mở 3 ms; 36 ms; không nhiễu.
//
// Phil 19/10/2026 — thêm 4 kiểu (cùng cách tổng hợp, không file âm thanh):
//   Đá (rock): gõ đá trầm-cứng-ngắn — 180→150 Hz τ5 ms + mode 2.35× τ2 ms (0.40) + nhiễu hp 150
//     lp 1.6 kHz τ1.2 ms (0.60); mở 0.5 ms; 30 ms; outLP 2.2 kHz; đỉnh 0.85.
//   Pop: "bụp" rơi cao độ 900→380 Hz (glide 4 ms) τ6 ms + nhiễu lp 2 kHz τ0.8 ms (0.15); mở 0.8 ms; 30 ms.
//   Nước (water): giọt nước trượt LÊN 700→1300 Hz (glide 12 ms) τ10 ms + bồi 2× (0.06); mở 2 ms; 42 ms.
//   Cổ điển (vintage): click bọc đệm — nhiễu hp 300 lp 1.5 kHz τ2 ms (0.80) + 380→340 Hz τ6 ms (0.60)
//     + tiếng nhả phím trễ 18 ms (nhiễu 0.25 τ1.5 ms + 330 Hz 0.20); mở 1 ms; 40 ms; outLP 1.8 kHz.
//
//   Pháo (phao, theme Tết): 3 tiếng nổ lách tách nhỏ — nhiễu hp 300 lp 2 kHz τ2.4 ms (1.0) + trễ 13 ms
//     (0.60 τ1.8 ms) + trễ 27 ms (0.40 τ1.4 ms) + thân 210→170 Hz τ4 ms (0.45); mở 0.4 ms; 46 ms;
//     outLP 2.4 kHz; đỉnh 0.55 — NHỎ hơn các kiểu khác (RMS < Gõ gỗ, test chốt). Seed nhiễu khác nhau
//     theo loại phím ⇒ chữ/xoá/chức năng nổ hơi khác nhau (tất định).
//   Chuông (jingle, theme Giáng sinh): cặp sine 880 Hz τ12 ms + 886 Hz τ14 ms (0.55, lệch 6 Hz ⇒ "rung"
//     kim loại) + bồi phi điều hoà 2.76× τ5 ms (0.22); mở 0.8 ms; 54 ms; đỉnh 0.62.
//   Piano: mỗi phím một nốt — xem PianoMap / PianoSynth cuối file.
//   Đàn tranh (dantranh, theme Sen Việt): mỗi phím một nốt dây gảy, ngũ cung điệu Bắc — DanTranhSynth cuối file.
//   Ghi-ta mộc (guitar, theme Ghi-ta): mỗi phím một nốt dây sắt, cách = quạt hợp âm theo vòng — GuitarSynth cuối file.
//
// Bộ đủ món 10/2026 (theme Máy chữ cổ / Vũ trụ):
//   Sci-fi (scifi, theme Vũ trụ): "bíp" synth mềm hai nhịp — 1100→1400 Hz trượt LÊN (glide 5 ms) τ8 ms + bồi 2×
//     (0.16) + nhịp hai 1650 Hz (quãng năm) trễ 11 ms τ5 ms (0.45); không nhiễu; mở 2 ms; 36 ms; outLP 2.8 kHz;
//     đỉnh 0.50 — NHỎ (RMS + đỉnh < Gõ gỗ, test chốt). Không nhiễu ⇒ checksum không phụ thuộc vị trí case.
//   Máy chữ — Enter "ding" (chuông về dòng): tiếng phím chức năng của Máy chữ + chuông 1568 Hz (G6) τ80 ms (0.9)
//     + bồi phi điều hoà 2.76× τ20 ms (0.25) trễ 12 ms; 280 ms; đỉnh 0.60 (RMS ≤ Gõ gỗ). Thuộc KIỂU âm Máy chữ
//     (`returnSamples`), không thuộc theme ⇒ ai chọn Máy chữ cũng nghe "ding"; kiểu khác Enter như cũ.
// Bộ theme đủ món 10/2026 (Trung Thu, Halloween) — NHỎ hơn "Gõ gỗ" (đỉnh + RMS, test chốt):
//   Trống lân (trong): tiếng "thùng" trầm nhẹ — thân 150→100 Hz (glide 6 ms) τ16 ms + mode màng 1.59× τ5 ms
//     (0.30) + nhiễu dùi hp 80 lp 900 Hz τ1.5 ms (0.22); mở 1 ms; 54 ms; outLP 1.4 kHz; đỉnh 0.50.
//   Ma quái (boo): "u~u" vui ngắn — sine trượt LÊN 330→520 Hz (glide 12 ms) τ17 ms + giọng đôi lệch 2 % (0.45)
//     + hoạ âm 3× (0.10) + hơi thở nhiễu lp 1.2 kHz (0.06); mở 4 ms (êm, không "tách"); 54 ms; đỉnh 0.45.
//
// THỨ TỰ case = chỉ số seed nhiễu (KeySoundSynth.seed) ⇒ CHỈ THÊM CUỐI, không chèn giữa (giữ mẫu cũ
// + checksum chung với Android). Thứ tự hiển thị là `menuOrder`.
//
// "system" (Phil 19/10/2026): click hệ thống — iOS UIDevice.playInputClick (theo Cài đặt → Âm thanh →
// Tiếng bấm bàn phím, KHÔNG cần Toàn quyền Truy cập), Android playSoundEffect. Không có công thức,
// không dựng AVAudioEngine/SoundPool (0 chi phí như khi tắt "Âm thanh phím"), miễn phí.
import Foundation

enum KeySoundKind: Int, CaseIterable {
    case letter, delete, modifier
}

/// Kiểu âm phím (setting `keySoundStyle`). rawValue = giá trị lưu/sao lưu.
enum KeySoundStyle: String, CaseIterable {
    // Chỉ thêm CUỐI (chỉ số case = seed nhiễu, chung với Android).
    case subtle, wood, mechanical, typewriter, bubble, custom, system, rock, pop, water, vintage, phao, jingle, piano
    // Theme "Sen Việt" (19/10/2026): mỗi phím một nốt đàn tranh (KeyInstrument.dantranh).
    case dantranh
    // Bộ đủ món 10/2026 (theme Vũ trụ).
    case scifi
    // Bộ theme đủ món 10/2026: Trống lân (Trung Thu), Ma quái (Halloween).
    case trong, boo
    // Theme "Ghi-ta" (10/2026): mỗi phím một nốt ghi-ta mộc dây sắt (KeyInstrument.guitar), cách = quạt hợp âm theo vòng.
    case guitar
    // Theme "Đập chuột" (10/2026): búa gỗ bọc vải gõ nhẹ ("bop").
    case bop

    /// Bật "Âm thanh phím" lần đầu ⇒ "Nhẹ nhàng" (bật công tắc phải NGHE khác đi; "iOS" = như lúc tắt).
    static let defaultStyle: KeySoundStyle = .subtle
    /// Kiểu tổng hợp 3 tiếng (chữ / xoá / chức năng) — có công thức `baseRecipe`.
    static let presets: [KeySoundStyle] = [.subtle, .wood, .mechanical, .typewriter, .bubble, .rock, .pop, .water, .vintage, .phao, .jingle,
                                           .scifi, .trong, .boo, .bop]
    /// Mọi kiểu dựng sẵn (3 tiếng + nhạc cụ mỗi phím một nốt: Piano, Đàn tranh, Ghi-ta).
    static let allPresets: [KeySoundStyle] = presets + [.piano, .dantranh, .guitar]
    /// DANH SÁCH DUY NHẤT id hợp lệ cho trường "sound" của theme JSON (chọn theme ⇒ đặt keySoundStyle).
    /// Không gồm "system"/"custom". Android: KeySoundStyle.PRESET_IDS — test chốt trùng nhau.
    static let presetIDs: [String] = allPresets.map(\.rawValue)
    /// Thứ tự trong trang "Âm thanh gõ": click hệ thống đầu, âm tự chọn cuối.
    static let menuOrder: [KeySoundStyle] = [.system] + allPresets + [.custom]

    /// true ⇒ phát qua engine riêng (cần Full Access). `system` ⇒ click hệ thống, không engine.
    var usesEngine: Bool { self != .system }

    /// Kiểu đã lưu có cần engine riêng không. Lạ ⇒ mặc định (tổng hợp) ⇒ cần; `system` ⇒ không.
    static func needsEngine(_ raw: String?) -> Bool {
        resolve(raw, customAvailable: true).usesEngine
    }

    /// Tên hiển thị (khoá L10n tiếng Việt).
    var viTitle: String {
        switch self {
        case .subtle: return LK("Nhẹ nhàng")
        case .wood: return LK("Gõ gỗ")
        case .mechanical: return LK("Bàn phím cơ")
        case .typewriter: return LK("Máy chữ")
        case .bubble: return LK("Bong bóng")
        case .custom: return LK("Âm của bạn")
        case .system: return LK("iOS")
        case .rock: return LK("Đá")
        case .pop: return LK("Pop")
        case .water: return LK("Nước")
        case .vintage: return LK("Cổ điển")
        case .phao: return LK("Pháo")
        case .jingle: return LK("Chuông")
        case .piano: return LK("Piano")
        case .dantranh: return LK("Đàn tranh")
        case .scifi: return LK("Bíp sci-fi")
        case .trong: return LK("Trống lân")
        case .boo: return LK("Ma quái")
        case .guitar: return LK("Ghi-ta mộc")
        case .bop: return LK("Búa gỗ")
        }
    }

    /// Giá trị lưu → kiểu thật sự phát. Lạ ⇒ mặc định; `custom` mà file vắng/hỏng ⇒ mặc định.
    static func resolve(_ raw: String?, customAvailable: Bool) -> KeySoundStyle {
        guard let s = raw.flatMap(KeySoundStyle.init(rawValue:)) else { return defaultStyle }
        if s == .custom && !customAvailable { return defaultStyle }
        return s
    }
}

enum KeySoundSynth {
    static let sampleRate = 44_100.0
    /// Đổi khi đổi thuật toán/công thức (Android đặt tên file cache theo số này).
    static let version = 2

    struct Tone { var amp: Double; var delay: Double; var f0: Double; var fEnd: Double; var glide: Double; var tau: Double }
    struct Noise { var amp: Double; var delay: Double; var hp: Double; var lp: Double; var tau: Double }
    struct Recipe {
        var tones: [Tone]; var noises: [Noise]
        var attack: Double; var duration: Double; var outLP: Double; var peak: Double
    }

    private static func t(_ amp: Double, _ f0: Double, _ fEnd: Double, glide: Double = 0.008, tau: Double, delay: Double = 0) -> Tone {
        Tone(amp: amp, delay: delay, f0: f0, fEnd: fEnd, glide: glide, tau: tau)
    }
    private static func n(_ amp: Double, hp: Double = 120, lp: Double, tau: Double, delay: Double = 0) -> Noise {
        Noise(amp: amp, delay: delay, hp: hp, lp: lp, tau: tau)
    }

    /// Công thức gốc (phím chữ) của mỗi kiểu có sẵn. `custom` không có công thức.
    static func baseRecipe(_ s: KeySoundStyle) -> Recipe {
        switch s {
        case .subtle, .custom, .system, .piano, .dantranh, .guitar:   // piano/đàn tranh/ghi-ta: nốt riêng (KeyInstrument); công thức này chỉ là dự phòng
            return Recipe(tones: [t(1.0, 500, 360, tau: 0.007), t(0.24, 1050, 900, tau: 0.0025)],
                          noises: [n(0.30, lp: 1900, tau: 0.002)],
                          attack: 0.0016, duration: 0.032, outLP: 2600, peak: 0.80)
        case .wood:
            return Recipe(tones: [t(1.0, 640, 590, tau: 0.009), t(0.28, 640 * 2.72, 590 * 2.72, tau: 0.0026)],
                          noises: [n(0.30, lp: 2400, tau: 0.0014)],
                          attack: 0.0009, duration: 0.042, outLP: 3800, peak: 0.80)
        case .mechanical:
            return Recipe(tones: [t(1.0, 230, 180, glide: 0.010, tau: 0.012), t(0.55, 520, 450, tau: 0.0045),
                                  t(0.45, 300, 280, tau: 0.005, delay: 0.007)],
                          noises: [n(0.55, hp: 90, lp: 1300, tau: 0.0035), n(0.28, hp: 90, lp: 1300, tau: 0.002, delay: 0.007)],
                          attack: 0.0014, duration: 0.046, outLP: 2400, peak: 0.80)
        case .typewriter:
            return Recipe(tones: [t(0.35, 1050, 850, glide: 0.004, tau: 0.003), t(0.55, 260, 240, tau: 0.008)],
                          noises: [n(0.95, hp: 500, lp: 2600, tau: 0.0028), n(0.30, hp: 500, lp: 2600, tau: 0.0018, delay: 0.011)],
                          attack: 0.0008, duration: 0.044, outLP: 3200, peak: 0.85)
        case .bubble:
            return Recipe(tones: [t(1.0, 260, 720, glide: 0.009, tau: 0.009), t(0.08, 520, 1440, glide: 0.009, tau: 0.006)],
                          noises: [],
                          attack: 0.003, duration: 0.036, outLP: 3000, peak: 0.80)
        case .rock:
            return Recipe(tones: [t(1.0, 180, 150, glide: 0.004, tau: 0.005), t(0.40, 180 * 2.35, 150 * 2.35, glide: 0.004, tau: 0.002)],
                          noises: [n(0.60, hp: 150, lp: 1600, tau: 0.0012)],
                          attack: 0.0005, duration: 0.030, outLP: 2200, peak: 0.85)
        case .pop:
            return Recipe(tones: [t(1.0, 900, 380, glide: 0.004, tau: 0.006)],
                          noises: [n(0.15, lp: 2000, tau: 0.0008)],
                          attack: 0.0008, duration: 0.030, outLP: 3000, peak: 0.80)
        case .water:
            return Recipe(tones: [t(1.0, 700, 1300, glide: 0.012, tau: 0.010), t(0.06, 1400, 2600, glide: 0.012, tau: 0.006)],
                          noises: [],
                          attack: 0.002, duration: 0.042, outLP: 3200, peak: 0.80)
        case .vintage:
            return Recipe(tones: [t(0.60, 380, 340, tau: 0.006), t(0.20, 330, 330, tau: 0.004, delay: 0.018)],
                          noises: [n(0.80, hp: 300, lp: 1500, tau: 0.002), n(0.25, hp: 300, lp: 1500, tau: 0.0015, delay: 0.018)],
                          attack: 0.001, duration: 0.040, outLP: 1800, peak: 0.80)
        case .phao:
            return Recipe(tones: [t(0.45, 210, 170, glide: 0.004, tau: 0.004)],
                          noises: [n(1.0, hp: 300, lp: 2000, tau: 0.0024), n(0.60, hp: 300, lp: 2000, tau: 0.0018, delay: 0.013),
                                   n(0.40, hp: 300, lp: 2000, tau: 0.0014, delay: 0.027)],
                          attack: 0.0004, duration: 0.046, outLP: 2400, peak: 0.55)
        case .jingle:
            return Recipe(tones: [t(1.0, 880, 880, tau: 0.012), t(0.55, 886, 886, tau: 0.014),
                                  t(0.22, 880 * 2.76, 880 * 2.76, tau: 0.005)],
                          noises: [],
                          attack: 0.0008, duration: 0.054, outLP: 3600, peak: 0.62)
        case .scifi:
            return Recipe(tones: [t(1.0, 1100, 1400, glide: 0.005, tau: 0.008), t(0.16, 2200, 2800, glide: 0.005, tau: 0.005),
                                  t(0.45, 1650, 1650, tau: 0.005, delay: 0.011)],
                          noises: [],
                          attack: 0.002, duration: 0.036, outLP: 2800, peak: 0.50)
        case .trong:
            return Recipe(tones: [t(1.0, 150, 100, glide: 0.006, tau: 0.016), t(0.30, 150 * 1.59, 100 * 1.59, glide: 0.006, tau: 0.005)],
                          noises: [n(0.22, hp: 80, lp: 900, tau: 0.0015)],
                          attack: 0.001, duration: 0.054, outLP: 1400, peak: 0.50)
        case .boo:
            return Recipe(tones: [t(1.0, 330, 520, glide: 0.012, tau: 0.017), t(0.45, 336.6, 530.4, glide: 0.012, tau: 0.017),
                                  t(0.10, 990, 1560, glide: 0.012, tau: 0.010)],
                          noises: [n(0.06, hp: 200, lp: 1200, tau: 0.004)],
                          attack: 0.004, duration: 0.054, outLP: 2000, peak: 0.45)
        case .bop:
            // Búa gỗ bọc vải: thân trầm ngắn (210 → 165 Hz) + chút gỗ (×2.4) + hơi vải mềm — êm, không "tách".
            return Recipe(tones: [t(1.0, 210, 165, glide: 0.006, tau: 0.011), t(0.22, 210 * 2.4, 165 * 2.4, glide: 0.006, tau: 0.003)],
                          noises: [n(0.18, hp: 90, lp: 900, tau: 0.0018)],
                          attack: 0.0018, duration: 0.048, outLP: 1500, peak: 0.50)
        }
    }

    /// "Éc" khi đập trúng chuột (theme Đập chuột — MoleGame): hai tiếng chíp ngắn vút lên, nhỏ + mềm (đỉnh ≤ Gõ gỗ).
    /// Seed cố định ⇒ tất định, checksum chung Android (KeySoundSynth.squeakSamples).
    static let squeakRecipe = Recipe(
        tones: [t(1.0, 1900, 2700, glide: 0.018, tau: 0.030), t(0.18, 3800, 5400, glide: 0.018, tau: 0.012),
                t(0.75, 2200, 3100, glide: 0.016, tau: 0.026, delay: 0.062), t(0.12, 4400, 6200, glide: 0.016, tau: 0.010, delay: 0.062)],
        noises: [],
        attack: 0.006, duration: 0.130, outLP: 4200, peak: 0.42)
    static let squeakSeed: UInt32 = 0x6D6F_6C65
    static func squeakSamples() -> [Float] { render(squeakRecipe, seed: squeakSeed) }

    /// Tiếng Enter RIÊNG của kiểu (nil = như phím chức năng). Máy chữ: tiếng phím chức năng + "ding" chuông về
    /// dòng. Seed cố định theo (typewriter, modifier) ⇒ không đổi khi thêm kiểu mới. Android y hệt.
    static func returnRecipe(_ s: KeySoundStyle) -> Recipe? {
        guard s == .typewriter else { return nil }
        var r = recipe(.typewriter, .modifier)
        r.tones += [t(0.9, 1568, 1568, tau: 0.08, delay: 0.012), t(0.25, 1568 * 2.76, 1568 * 2.76, tau: 0.02, delay: 0.012)]
        r.duration = 0.28
        r.peak = 0.60
        return r
    }

    /// Mẫu Enter riêng của kiểu (nil = dùng tiếng phím chức năng).
    static func returnSamples(_ s: KeySoundStyle) -> [Float]? {
        returnRecipe(s).map { render($0, seed: seed(s, .modifier)) }
    }

    /// Công thức theo loại phím: xoá trầm hơn chút; phím chức năng trầm + dài hơn.
    static func recipe(_ s: KeySoundStyle, _ k: KeySoundKind) -> Recipe {
        var r = baseRecipe(s)
        let (pitch, decay, extra): (Double, Double, Double)
        switch k {
        case .letter: return r
        case .delete: (pitch, decay, extra) = (0.86, 1.0, 0)
        case .modifier: (pitch, decay, extra) = (0.74, 1.2, 0.006)
        }
        r.tones = r.tones.map { var x = $0; x.f0 *= pitch; x.fEnd *= pitch; x.tau *= decay; return x }
        r.noises = r.noises.map { var x = $0; x.lp *= pitch; x.tau *= decay; return x }
        r.duration += extra
        return r
    }

    static func seed(_ s: KeySoundStyle, _ k: KeySoundKind) -> UInt32 {
        let si = UInt32(KeySoundStyle.allCases.firstIndex(of: s) ?? 0)
        return 0x9E37_79B9 &* (si &+ 1) ^ (0x85EB_CA6B &* UInt32(k.rawValue + 1))
    }

    /// Mẫu mono Float −1…1 của một kiểu có sẵn (`custom` ⇒ dùng công thức mặc định).
    static func samples(_ s: KeySoundStyle, _ k: KeySoundKind) -> [Float] {
        render(recipe(s, k), seed: seed(s, k))
    }

    /// Tương thích: kiểu mặc định.
    static func samples(_ k: KeySoundKind) -> [Float] { samples(.defaultStyle, k) }

    /// 3 mẫu (chữ / xoá / chức năng) cho kiểu đã lưu. `custom` vắng/hỏng ⇒ kiểu mặc định.
    static func bank(_ raw: String?, custom: [Float]?) -> (style: KeySoundStyle, samples: [[Float]]) {
        let st = KeySoundStyle.resolve(raw, customAvailable: custom != nil)
        if st == .custom, let c = custom {
            return (st, KeySoundKind.allCases.map { KeySoundCustom.variant(c, $0) })
        }
        return (st, KeySoundKind.allCases.map { samples(st, $0) })
    }

    /// Bản nghe thử khi chọn kiểu: chữ → xoá → phím chức năng, cách nhau `gap` giây lặng.
    /// Ghép thành MỘT mẫu ⇒ app phát một lần (một AVAudioPlayer/AudioTrack). Giống Kotlin.
    static func previewSequence(_ bank: [[Float]], gap: Double = 0.16) -> [Float] {
        let silence = [Float](repeating: 0, count: Int((gap * sampleRate).rounded()))
        var out: [Float] = []
        for (i, s) in bank.enumerated() {
            if i > 0 { out += silence }
            out += s
        }
        return out
    }

    static func render(_ r: Recipe, seed: UInt32) -> [Float] {
        let sr = sampleRate
        let count = Int((r.duration * sr).rounded())
        var out = [Double](repeating: 0, count: count)
        // Tone
        for tn in r.tones {
            var phase = 0.0
            let start = Int((tn.delay * sr).rounded())
            if start >= count { continue }
            for i in start..<count {
                let tt = Double(i - start) / sr
                let f = tn.fEnd + (tn.f0 - tn.fEnd) * exp(-tt / tn.glide)
                phase += 2 * Double.pi * f / sr
                out[i] += tn.amp * sin(phase) * exp(-tt / tn.tau) * ramp(tt, r.attack)
            }
        }
        // Noise (mỗi lớp dòng xorshift riêng, lệch seed theo chỉ số lớp)
        for (li, nz) in r.noises.enumerated() {
            var state = seed ^ (0x2545_F491 &* UInt32(li + 1))
            if state == 0 { state = 0x1234_5678 }
            let hpA = exp(-2 * Double.pi * nz.hp / sr)
            let lpA = exp(-2 * Double.pi * nz.lp / sr)
            var hpIn = 0.0, hpOut = 0.0, lp1 = 0.0, lp2 = 0.0
            let start = Int((nz.delay * sr).rounded())
            if start >= count { continue }
            for i in start..<count {
                let tt = Double(i - start) / sr
                state ^= state << 13; state ^= state >> 17; state ^= state << 5
                let white = Double(state) / Double(UInt32.max) * 2 - 1
                let hp = hpA * (hpOut + white - hpIn)
                hpIn = white; hpOut = hp
                lp1 = (1 - lpA) * hp + lpA * lp1
                lp2 = (1 - lpA) * lp1 + lpA * lp2
                out[i] += nz.amp * 2.5 * lp2 * exp(-tt / nz.tau) * ramp(tt, r.attack)
            }
        }
        // Lọc thấp đầu ra + đóng mềm 3 ms.
        let oA = exp(-2 * Double.pi * r.outLP / sr)
        let dcA = exp(-2 * Double.pi * 40 / sr)   // chặn DC 40 Hz (loa nhỏ không phí công)
        var y = 0.0, dcIn = 0.0, dcOut = 0.0
        let rel = min(count, Int(0.003 * sr))
        var peak = 0.0
        for i in 0..<count {
            y = (1 - oA) * out[i] + oA * y
            dcOut = dcA * (dcOut + y - dcIn); dcIn = y
            var v = dcOut
            let fromEnd = count - 1 - i
            if fromEnd < rel { v *= 0.5 - 0.5 * cos(Double.pi * Double(fromEnd) / Double(rel)) }
            out[i] = v
            peak = max(peak, abs(v))
        }
        let norm = peak > 0 ? r.peak / peak : 0
        return out.map { Float($0 * norm) }
    }

    /// Mở raised-cosine 0→1 trong `a` giây (0 ⇒ luôn 1).
    private static func ramp(_ t: Double, _ a: Double) -> Double {
        if a <= 0 || t >= a { return 1 }
        return 0.5 - 0.5 * cos(Double.pi * t / a)
    }

    /// 0…100 % → biên độ; bình phương cho cảm giác to/nhỏ đều tay hơn tuyến tính.
    static func gain(forPercent p: Int) -> Float {
        let x = Float(max(0, min(100, p))) / 100
        return x * x
    }

    // MARK: đo đạc (test + ghi chú)

    /// Trọng tâm phổ (Hz) — trung bình tần số có trọng số biên độ DFT. Cao ⇒ chói.
    static func spectralCentroid(_ x: [Float], sampleRate sr: Double = sampleRate) -> Double {
        let n = x.count
        guard n > 1 else { return 0 }
        var num = 0.0, den = 0.0
        for k in 1...(n / 2) {
            var re = 0.0, im = 0.0
            let w = 2 * Double.pi * Double(k) / Double(n)
            for (i, v) in x.enumerated() { re += Double(v) * cos(w * Double(i)); im -= Double(v) * sin(w * Double(i)) }
            let mag = (re * re + im * im).squareRoot()
            num += mag * Double(k) * sr / Double(n); den += mag
        }
        return den > 0 ? num / den : 0
    }

    static func rms(_ x: [Float]) -> Double {
        guard !x.isEmpty else { return 0 }
        return (x.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(x.count)).squareRoot()
    }

    // MARK: WAV (16-bit PCM mono) — file âm tự chọn + bản nghe thử

    static func wav(_ s: [Float], sampleRate sr: Int = Int(sampleRate)) -> Data {
        var d = Data(capacity: 44 + s.count * 2)
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let data = UInt32(s.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + data); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(UInt32(sr)); u32(UInt32(sr * 2)); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(data)
        for x in s {
            let v = Int16(max(-1, min(1, x)) * 32767)
            u16(UInt16(bitPattern: v))
        }
        return d
    }

    /// Đọc WAV PCM 16-bit (mono/stereo → mono). nil nếu không phải định dạng đó.
    static func parseWav(_ d: Data) -> (samples: [Float], sampleRate: Double)? {
        let b = [UInt8](d)
        guard b.count >= 44, String(bytes: b[0..<4], encoding: .ascii) == "RIFF",
              String(bytes: b[8..<12], encoding: .ascii) == "WAVE" else { return nil }
        func u16(_ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        var o = 12
        var channels = 0, rate = 0, bits = 0, fmtTag = 0
        while o + 8 <= b.count {
            let id = String(bytes: b[o..<o + 4], encoding: .ascii) ?? ""
            let size = u32(o + 4)
            let body = o + 8
            if id == "fmt ", body + 16 <= b.count {
                fmtTag = u16(body); channels = u16(body + 2); rate = u32(body + 4); bits = u16(body + 14)
            } else if id == "data" {
                guard fmtTag == 1, bits == 16, channels >= 1, rate > 0 else { return nil }
                let end = min(b.count, body + size)
                let frames = (end - body) / (2 * channels)
                var out = [Float](repeating: 0, count: frames)
                for f in 0..<frames {
                    var acc = 0.0
                    for c in 0..<channels {
                        let p = body + (f * channels + c) * 2
                        acc += Double(Int16(bitPattern: UInt16(u16(p))))
                    }
                    out[f] = Float(acc / Double(channels) / 32768)
                }
                return (out, Double(rate))
            }
            o = body + size + (size & 1)
        }
        return nil
    }
}

/// Âm tự chọn: xử lý thuần sau khi giải mã (app iOS: AVAudioFile; Android: MediaCodec).
/// Giống hệt Kotlin KeySoundCustom.
enum KeySoundCustom {
    static let maxDuration = 0.300       // ≤ 300 ms
    static let targetPeak: Float = 0.80  // đỉnh an toàn
    static let maxRMS = 0.22             // âm "đặc" (ù dài) bị hạ tiếp cho khỏi to
    static let fileName = "keysound-custom.wav"

    /// File âm tự chọn trong App Group (app ghi, bàn phím đọc — cần Full Access mới đọc được).
    /// KHÔNG nằm trong file sao lưu VietTelex (chỉ key `keySoundStyle` đi theo).
    static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppFlavor.appGroup)?
            .appendingPathComponent(fileName)
    }

    /// Khoá bộ mẫu: kiểu + (nếu tự chọn) ngày sửa + cỡ file ⇒ app thay file là nạp lại.
    static func bankKey(style raw: String, customURL: URL?) -> String {
        guard raw == KeySoundStyle.custom.rawValue, let u = customURL,
              let a = try? FileManager.default.attributesOfItem(atPath: u.path) else { return raw }
        let m = (a[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(raw)@\(m)#\((a[.size] as? NSNumber)?.intValue ?? 0)"
    }

    /// Đọc file âm tự chọn đã xử lý (WAV 44.1 kHz mono). nil ⇒ vắng/hỏng ⇒ dùng mặc định.
    static func load(_ url: URL?) -> [Float]? {
        guard let url, let d = try? Data(contentsOf: url), let w = KeySoundSynth.parseWav(d),
              !w.samples.isEmpty, w.samples.count <= Int(maxDuration * KeySoundSynth.sampleRate) + 16
        else { return nil }
        return resample(w.samples, from: w.sampleRate, to: KeySoundSynth.sampleRate)
    }

    enum Failure: Error, Equatable { case empty, silent }
    struct Result: Equatable {
        let samples: [Float]
        /// true ⇒ âm gốc dài hơn 300 ms, đã cắt (báo người dùng).
        let truncated: Bool
    }

    /// mono ở `rate` → 44.1 kHz, bỏ lặng đầu/cuối, cắt ≤ 300 ms, mở/đóng mềm, chuẩn hoá đỉnh.
    static func process(_ mono: [Float], sampleRate rate: Double) throws -> Result {
        guard !mono.isEmpty, rate > 0 else { throw Failure.empty }
        let x = resample(mono, from: rate, to: KeySoundSynth.sampleRate)
        let peak = x.reduce(Float(0)) { max($0, abs($1)) }
        guard peak >= 0.001 else { throw Failure.silent }
        let thr = max(peak * 0.05, 0.001)
        let sr = KeySoundSynth.sampleRate
        let first = x.firstIndex { abs($0) >= thr } ?? 0
        let last = x.lastIndex { abs($0) >= thr } ?? (x.count - 1)
        let start = max(0, first - Int(0.002 * sr))           // giữ 2 ms trước đỉnh mở
        let endAll = min(x.count, last + 1 + Int(0.010 * sr))  // giữ 10 ms đuôi
        let cap = Int(maxDuration * sr)
        let truncated = endAll - start > cap
        let end = min(endAll, start + cap)
        var y = Array(x[start..<end])
        // Mở 1 ms (bỏ "bụp" do cắt), đóng 5 ms (15 ms nếu bị cắt giữa chừng).
        let fin = min(y.count, Int(0.001 * sr))
        for i in 0..<fin { y[i] *= Float(0.5 - 0.5 * cos(Double.pi * Double(i) / Double(fin))) }
        let fout = min(y.count, Int((truncated ? 0.015 : 0.005) * sr))
        for j in 0..<fout {
            let i = y.count - 1 - j
            y[i] *= Float(0.5 - 0.5 * cos(Double.pi * Double(j) / Double(fout)))
        }
        let p2 = y.reduce(Float(0)) { max($0, abs($1)) }
        guard p2 > 0 else { throw Failure.silent }
        var g = targetPeak / p2
        let r = KeySoundSynth.rms(y) * Double(g)
        if r > maxRMS { g *= Float(maxRMS / r) }
        return Result(samples: y.map { $0 * g }, truncated: truncated)
    }

    /// Nội suy tuyến tính (đủ cho click ngắn).
    static func resample(_ x: [Float], from: Double, to: Double) -> [Float] {
        if abs(from - to) < 0.5 || x.count < 2 { return x }
        let n = max(1, Int((Double(x.count) * to / from).rounded()))
        var out = [Float](repeating: 0, count: n)
        let step = from / to
        for i in 0..<n {
            let p = Double(i) * step
            let j = Int(p)
            if j >= x.count - 1 { out[i] = x[x.count - 1]; continue }
            let f = Float(p - Double(j))
            out[i] = x[j] * (1 - f) + x[j + 1] * f
        }
        return out
    }

    /// Mẫu phát cho từng loại phím từ âm tự chọn: chữ nguyên bản, xoá/chức năng nhỏ hơn chút.
    static func variant(_ s: [Float], _ k: KeySoundKind) -> [Float] {
        switch k {
        case .letter: return s
        case .delete: return s.map { $0 * 0.9 }
        case .modifier: return s.map { $0 * 0.82 }
        }
    }
}

/// Giới hạn tần suất nghe thử khi kéo thanh trượt: tối đa 1 lần / `interval` trong lúc kéo,
/// và luôn phát lúc thả (trừ khi vừa phát đúng giá trị đó rất gần). Thuần — test được.
struct PreviewThrottle {
    var interval: TimeInterval = 0.12
    private(set) var lastFire: TimeInterval = -.infinity
    private(set) var lastValue: Int?

    init(interval: TimeInterval = 0.12) { self.interval = interval }

    /// true ⇒ phát ngay bây giờ.
    mutating func shouldFire(value: Int, now: TimeInterval, final: Bool) -> Bool {
        let elapsed = now - lastFire
        let fire: Bool
        if final { fire = value != lastValue || elapsed >= interval }
        else { fire = elapsed >= interval && value != lastValue }
        if fire { lastFire = now; lastValue = value }
        return fire
    }
}

// MARK: - Piano (Phil 19/10/2026): mỗi phím một nốt, ngũ cung trưởng C D E G A — gõ lung tung vẫn
// thành nhạc, không nghịch tai. Thuật toán + bảng Y HỆT Kotlin PianoMap/PianoSynth (test chốt chung).

/// Phím → nốt (MIDI), hàm thuần theo VỊ TRÍ phím trên QWERTY — chung mọi nhạc cụ "mỗi phím một nốt"
/// (Piano, Đàn tranh), chỉ khác thang 5 bậc + hợp âm. Kotlin NoteMap y hệt.
/// - Trái → phải trong một hàng: đi lên thang ngũ cung (5 bậc/quãng tám).
/// - Hàng chữ dưới (z…m) bắt đầu C3, hàng giữa (a…l) C4, hàng trên (q…p) C5 ⇒ ~3 quãng tám qua 3 hàng
///   (C3 … A6); hàng số cao thêm một quãng tám (C6 … A7).
/// - Ký tự khác (dấu câu, ký hiệu, chữ có dấu…): bậc = mã ký tự % 10 trên nền C4 — tất định.
struct NoteMap: Equatable {
    static let rows: [String] = ["1234567890", "qwertyuiop", "asdfghjkl", "zxcvbnm"]
    static let rowBase: [Int] = [84, 72, 60, 48]   // C6, C5, C4, C3
    static let fallbackBase = 60

    let scale: [Int]
    let spaceChord: [Int]
    let returnChord: [Int]
    let deleteNote: Int
    let modifierNote: Int
    /// Vòng hợp âm của phím cách (ChordProgression) — mỗi phần tử một hợp âm (MIDI, trầm → cao = thứ tự quạt dây).
    /// Rỗng = phím cách phát `spaceChord` cố định (Đàn tranh). Nốt hợp âm KHÔNG vào `notes` (hợp âm dựng nguyên khối).
    let progression: [[Int]]
    /// Bảng ASCII dựng sẵn (−1 = không có trong 4 hàng) ⇒ tra mỗi phím không cấp phát.
    private let ascii: [Int]
    /// Mọi nốt bàn phím có thể phát (dựng sẵn mỗi nốt một buffer), tăng dần.
    let notes: [Int]

    init(scale: [Int], spaceChord: [Int], returnChord: [Int], deleteNote: Int, modifierNote: Int, progression: [[Int]] = []) {
        self.scale = scale; self.spaceChord = spaceChord; self.returnChord = returnChord
        self.deleteNote = deleteNote; self.modifierNote = modifierNote; self.progression = progression
        func m(_ base: Int, _ step: Int) -> Int { base + 12 * (step / 5) + scale[step % 5] }
        var t = [Int](repeating: -1, count: 128)
        var s = Set<Int>()
        for (r, row) in Self.rows.enumerated() {
            for (c, ch) in row.unicodeScalars.enumerated() { t[Int(ch.value)] = m(Self.rowBase[r], c); s.insert(m(Self.rowBase[r], c)) }
        }
        for st in 0..<10 { s.insert(m(Self.fallbackBase, st)) }
        for x in spaceChord + returnChord + [modifierNote] { s.insert(x) }
        ascii = t
        notes = s.sorted()
    }

    func midi(base: Int, step: Int) -> Int { base + 12 * (step / 5) + scale[step % 5] }
    func midi(row: Int, col: Int) -> Int { midi(base: Self.rowBase[row], step: col) }

    /// Nốt cho một ký tự (mã Unicode). Hoa ⇒ như thường.
    func midi(scalar v: UInt32) -> Int {
        var x = v
        if x >= 65 && x <= 90 { x += 32 }   // A–Z → a–z
        if x < 128, ascii[Int(x)] >= 0 { return ascii[Int(x)] }
        return midi(base: Self.fallbackBase, step: Int(x % 10))
    }

    /// Nốt cho nhãn phím ("a", "Q", "7", "," …). Rỗng ⇒ C4.
    func midi(forKey key: String?) -> Int {
        guard let v = key?.unicodeScalars.first?.value else { return Self.fallbackBase }
        return midi(scalar: v)
    }

    /// Piano: ngũ cung trưởng C D E G A. Cách: vòng hợp âm đệm C → Am → F → G (ba nốt, xếp trầm gọn: C3 G3 E4 /
    /// A2 E3 C4 / F2 C3 A3 / G2 D3 B3 — hợp nốt ngũ cung trên tay phải); Enter: hợp âm "kết" C4+G4+C5 (chủ + năm);
    /// ⌫: nốt trầm tắt tiếng A2; phím chức năng khác (123, 🌐…): C3 nhẹ. `spaceChord` C3+G3+C4 = hợp âm cách cũ
    /// (giữ API / bảng nốt; bàn phím phát vòng hợp âm).
    static let piano = NoteMap(scale: [0, 2, 4, 7, 9], spaceChord: [48, 55, 60], returnChord: [60, 67, 72],
                               deleteNote: 45, modifierNote: 48,
                               progression: [[48, 55, 64], [45, 52, 60], [41, 48, 57], [43, 50, 59]])
    /// Đàn tranh: ngũ cung "điệu Bắc" Hò Xự Xang Xê Cống ≈ C D F G A. Cách: dây buông C3+G3+C4 rải nhẹ;
    /// Enter: Hò–Xang–Hò C4+F4+C5 rải; ⌫: dây A2 bị chặn tiếng; phím chức năng khác: C3.
    static let dantranh = NoteMap(scale: [0, 2, 5, 7, 9], spaceChord: [48, 55, 60], returnChord: [60, 65, 72],
                                  deleteNote: 45, modifierNote: 48)
    /// Ghi-ta mộc: ngũ cung trưởng C D E G A như Piano (cùng vị trí phím). Cách: quạt xuống 6 dây theo vòng
    /// Am → F → C → G (thế bấm mở: Am/E 0-0-2-2-1-0, F chặn 1-3-3-2-1-1, C/G 3-3-2-0-1-0, G 3-2-0-0-0-3 —
    /// quen tai "pop", nốt ngũ cung C D E G A nghe hợp cả bốn); Enter: quạt "kết" về chủ C trưởng (x-3-2-0-1-3:
    /// C3 E3 G3 C4 E4 G4); ⌫: tiếng "chặn dây" (mute) quanh E2; phím chức năng khác: C3.
    static let guitar = NoteMap(scale: [0, 2, 4, 7, 9], spaceChord: [], returnChord: [48, 52, 55, 60, 64, 67],
                                deleteNote: 40, modifierNote: 48,
                                progression: [[40, 45, 52, 57, 60, 64], [41, 48, 53, 57, 60, 65],
                                              [43, 48, 52, 55, 60, 64], [43, 47, 50, 55, 59, 67]])
}

/// Vòng hợp âm phím cách (Piano / Ghi-ta) — máy trạng thái THUẦN (Kotlin ChordProgression y hệt, test chung).
/// Trạng thái = chỉ số hợp âm kế tiếp + thời điểm gõ gần nhất (giây).
/// - Mỗi lần cách: phát hợp âm `index` rồi tiến một bước (vòng lặp lại sau hợp âm cuối).
/// - Nghỉ gõ > `idleReset` (3 s) ⇒ lần cách kế bắt đầu lại hợp âm đầu (đoạn nhạc mới).
/// - Kết câu (gõ . ! ?) ⇒ về hợp âm đầu. Enter ⇒ phát hợp âm chủ (`returnChord`) rồi về đầu.
/// - Gõ chữ / ⌫ chỉ cập nhật thời điểm (đang gõ ⇒ vòng không bị reset giữa câu dài).
struct ChordProgression: Equatable {
    static let idleReset = 3.0
    let count: Int
    private(set) var index = 0
    private(set) var lastTime = -Double.infinity

    init(count: Int) { self.count = max(0, count) }

    /// Phím cách lúc `now`: trả chỉ số hợp âm cần phát (0…count−1) rồi tiến một bước.
    mutating func space(now: Double) -> Int {
        guard count > 0 else { lastTime = now; return 0 }
        if now - lastTime > Self.idleReset { index = 0 }
        let i = index % count
        index = (i + 1) % count
        lastTime = now
        return i
    }

    /// Gõ phím khác (chữ, ký hiệu, ⌫). `sentenceEnd` (. ! ?) ⇒ về hợp âm đầu.
    mutating func typed(now: Double, sentenceEnd: Bool) {
        if sentenceEnd || now - lastTime > Self.idleReset { index = 0 }
        lastTime = now
    }

    /// Enter: hợp âm chủ (bàn phím phát `returnChord`), rồi vòng về đầu.
    mutating func returnKey(now: Double) {
        index = 0
        lastTime = now
    }

    mutating func reset() { index = 0; lastTime = -Double.infinity }

    /// Nhãn phím kết câu: . ! ?
    static func isSentenceEnd(_ key: String?) -> Bool {
        guard let k = key, k.unicodeScalars.count == 1, let v = k.unicodeScalars.first?.value else { return false }
        return v == 46 || v == 33 || v == 63
    }
}

/// Bảng Piano (giữ API cũ — test/nơi gọi cũ). Mọi thứ uỷ cho NoteMap.piano.
enum PianoMap {
    static var rows: [String] { NoteMap.rows }
    static var rowBase: [Int] { NoteMap.rowBase }
    static var scale: [Int] { NoteMap.piano.scale }
    static var fallbackBase: Int { NoteMap.fallbackBase }
    static var spaceChord: [Int] { NoteMap.piano.spaceChord }
    static var returnChord: [Int] { NoteMap.piano.returnChord }
    static var deleteNote: Int { NoteMap.piano.deleteNote }
    static var modifierNote: Int { NoteMap.piano.modifierNote }
    static func midi(base: Int, step: Int) -> Int { NoteMap.piano.midi(base: base, step: step) }
    static func midi(row: Int, col: Int) -> Int { NoteMap.piano.midi(row: row, col: col) }
    static func midi(scalar v: UInt32) -> Int { NoteMap.piano.midi(scalar: v) }
    static func midi(forKey key: String?) -> Int { NoteMap.piano.midi(forKey: key) }
    /// Ngũ cung C3 … A7 = 25 nốt.
    static var notes: [Int] { NoteMap.piano.notes }
}

/// Sự kiện âm Piano (chỉ kiểu piano đi đường này; kiểu khác giữ đường 3 tiếng).
enum PianoEvent: Equatable {
    case note(Int), space, returnKey, delete, pedal
    /// Hợp âm thứ i của vòng phím cách (NoteMap.progression) — Piano / Ghi-ta.
    case chord(Int)
}

/// Tổng hợp nốt kiểu piano: cộng hoạ âm 1–5 (biên độ giảm dần, hơi phi điều hoà B = 0.00035),
/// mở nhanh 2.5 ms, tắt dần hai tầng (âm "đầu" nhanh + "dư âm" chậm như dây đàn thật), hoạ âm cao
/// tắt nhanh hơn, nốt trầm ngân lâu hơn. Mono, chuẩn hoá đỉnh mỗi nốt (to đều mọi cao độ).
/// - Thường: 22.05 kHz, 0.8 s (dư âm τ ≈ 0.42 s ⇒ nghe ~0.6–0.9 s).
/// - Ngân (pedal Shift/Caps): 11.025 kHz, 2.5 s (τ ≈ 1 s) — chỉ dựng khi pedal được dùng lần đầu.
enum PianoSynth {
    static let sampleRate = 22_050.0
    static let sustainSampleRate = 11_025.0
    static let noteDuration = 0.8
    static let sustainDuration = 2.5
    static let mutedDuration = 0.15
    static let pedalDuration = 0.6
    static let notePeak = 0.34
    static let chordPeak = 0.30
    static let pedalPeak = 0.30
    static let inharmonicity = 0.00035
    static let partialAmps: [Double] = [1.0, 0.45, 0.28, 0.16, 0.09]
    /// Số giọng (polyphony) mỗi pool: bấm nhiều phím cùng lúc ⇒ hợp âm.
    static let voices = 8

    enum Kind { case normal, sustain, muted }

    static func freq(_ m: Int) -> Double { 440 * pow(2, Double(m - 69) / 12) }

    static func samples(_ midis: [Int], kind: Kind, peak: Double) -> [Float] {
        let sr = kind == .sustain ? sustainSampleRate : sampleRate
        let dur = kind == .sustain ? sustainDuration : (kind == .muted ? mutedDuration : noteDuration)
        let n = Int((dur * sr).rounded())
        var out = [Double](repeating: 0, count: n)
        for m in midis {
            let f = freq(m)
            let s = min(1.6, max(0.5, pow(262 / f, 0.3)))
            let t1: Double, t2: Double
            switch kind {
            case .normal: t1 = 0.10 * s; t2 = 0.42 * s
            case .sustain: t1 = 0.22 * s; t2 = 1.0 * s
            case .muted: t1 = 0.025; t2 = 0.05
            }
            for k in 1...partialAmps.count {
                let kd = Double(k)
                let fk = kd * f * (1 + inharmonicity * kd * kd).squareRoot()
                if fk >= 0.45 * sr { break }
                let a = partialAmps[k - 1] * exp(-(kd - 1) * f / 4000)
                let d1 = exp(-1 / (sr * t1 / kd.squareRoot()))
                let d2 = exp(-1 / (sr * t2 / kd.squareRoot()))
                let w = 2 * Double.pi * fk / sr
                var e1 = 0.65, e2 = 0.35
                for i in 0..<n {
                    out[i] += a * (e1 + e2) * sin(w * Double(i))
                    e1 *= d1; e2 *= d2
                }
            }
        }
        return finish(out, sampleRate: sr, attack: 0.0025, release: kind == .sustain ? 0.2 : 0.06, peak: peak)
    }

    /// Mở/đóng raised-cosine + chuẩn hoá đỉnh.
    static func finish(_ x: [Double], sampleRate sr: Double, attack: Double, release: Double, peak: Double) -> [Float] {
        var out = x
        let n = out.count
        let ai = Int(attack * sr), rel = min(n, Int(release * sr))
        var pk = 0.0
        for i in 0..<n {
            var v = out[i]
            if i < ai { v *= 0.5 - 0.5 * cos(Double.pi * Double(i) / Double(ai)) }
            let fe = n - 1 - i
            if fe < rel { v *= 0.5 - 0.5 * cos(Double.pi * Double(fe) / Double(rel)) }
            out[i] = v
            pk = max(pk, abs(v))
        }
        let g = pk > 0 ? peak / pk : 0
        return out.map { Float($0 * g) }
    }

    static func note(_ m: Int, sustain: Bool = false) -> [Float] { samples([m], kind: sustain ? .sustain : .normal, peak: notePeak) }
    static func space() -> [Float] { samples(PianoMap.spaceChord, kind: .normal, peak: chordPeak) }
    /// Hợp âm thứ i của vòng phím cách (C → Am → F → G).
    static func chord(_ i: Int) -> [Float] { samples(NoteMap.piano.progression[i], kind: .normal, peak: chordPeak) }
    static func returnChord() -> [Float] { samples(PianoMap.returnChord, kind: .normal, peak: chordPeak) }
    static func delete() -> [Float] { samples([PianoMap.deleteNote], kind: .muted, peak: notePeak) }

    /// Tiếng "đạp pedal" (bấm Shift/Caps): tiếng thịch trầm tắt nhanh (55→75 Hz trượt xuống) + ánh
    /// cộng hưởng mờ của dây C4 G4 C5 G5 dâng lên chậm rồi tắt — không nhiễu chói.
    static func pedal() -> [Float] {
        let sr = sampleRate
        let n = Int((pedalDuration * sr).rounded())
        var out = [Double](repeating: 0, count: n)
        var phase = 0.0
        for i in 0..<n {
            let t = Double(i) / sr
            phase += 2 * Double.pi * (55 + 20 * exp(-t / 0.02)) / sr
            out[i] += sin(phase) * exp(-t / 0.045)
        }
        for m in [60, 67, 72, 79] {
            let w = 2 * Double.pi * freq(m) / sr
            for i in 0..<n {
                let t = Double(i) / sr
                out[i] += 0.06 * sin(w * Double(i)) * (1 - exp(-t / 0.12)) * exp(-t / 0.35)
            }
        }
        return finish(out, sampleRate: sr, attack: 0.003, release: 0.06, peak: pedalPeak)
    }

    /// Nghe thử trong app: C4 E4 G4 C5 nối nhau (cách 0.16 s, ngân chồng) — 22.05 kHz.
    static func previewMelody() -> [Float] {
        let step = Int((0.16 * sampleRate).rounded())
        let notes = [60, 64, 67, 72].map { note($0) }
        var out = [Float](repeating: 0, count: step * (notes.count - 1) + notes[0].count)
        for (i, x) in notes.enumerated() {
            for (j, v) in x.enumerated() { out[i * step + j] += v * 0.8 }
        }
        return out
    }

    /// Bộ nhớ (byte, Float32) của bộ nốt dựng sẵn lúc hiện bàn phím (25 nốt + 4 hợp âm vòng cách + Enter + ⌫ + pedal).
    static var normalBankBytes: Int {
        let note = Int((noteDuration * sampleRate).rounded())
        let muted = Int((mutedDuration * sampleRate).rounded())
        let ped = Int((pedalDuration * sampleRate).rounded())
        return 4 * (PianoMap.notes.count * note + (NoteMap.piano.progression.count + 1) * note + muted + ped)
    }

    /// Bộ nhớ bộ nốt ngân (dựng lười khi pedal dùng lần đầu).
    static var sustainBankBytes: Int {
        4 * PianoMap.notes.count * Int((sustainDuration * sustainSampleRate).rounded())
    }
}

/// Đàn tranh (Phil 19/10/2026, theme "Sen Việt"): dây gảy tổng hợp cộng hoạ âm — tất định, Kotlin
/// DanTranhSynth Y HỆT (test chốt checksum chung). Dùng chung hạ tầng Piano: 22.05 kHz (nốt ngân 11.025 kHz
/// 2.5 s), pool giọng, pedal, finish().
/// - Phổ dây gảy: hoạ âm k = 1…8, biên độ |sin(π·k·p)|/k (gảy ở p = 0.2 chiều dài dây, gần ngựa đàn ⇒ sáng)
///   × e^(−(k−1)·f/6000) (nốt cao không chói); hoạ âm cao tắt nhanh hơn (τ / (1 + 0.6(k−1))) ⇒ gảy sáng rồi dịu.
///   sin(k·φ) tính bằng truy hồi Chebyshev (một sin + một cos mỗi mẫu).
/// - Mở rất nhanh 1.2 ms ("tưng"), tắt hai tầng: phần gảy τ1 = 0.09 s (60 %) + dư âm τ2 = 0.42 s (40 %), × theo
///   cao độ (nốt trầm ngân lâu hơn) ⇒ nghe ~1 s, cắt mềm 80 ms cuối của 1.0 s.
/// - "Nhấn nhá" nhẹ: dây vừa gảy căng hơn chút (+7 cent, về trong ~30 ms); từ 0.16 s rung 5.2 Hz sâu dần tới
///   ±12 cent — nghe ra đàn tranh mà hợp âm không phô.
/// - Cách / Enter: hợp âm rải (18 / 26 ms giữa các dây). Pedal: tiếng vuốt dây (6 dây cao rải 22 ms, tắt
///   nhanh, nhỏ). ⌫: dây bị chặn tiếng (không rung).
/// - Nhỏ hơn Piano: đỉnh nốt 0.30 (Piano 0.34), hợp âm 0.26 (0.30), pedal 0.18 (0.30) — test chốt.
enum DanTranhSynth {
    static let noteDuration = 1.0
    static let notePeak = 0.30
    static let chordPeak = 0.26
    static let pedalPeak = 0.18
    static let pluckPosition = 0.2
    static let partials = 8
    static let vibratoRate = 5.2
    static let vibratoDepth = 0.007
    static let vibratoDelay = 0.16
    static let vibratoRise = 0.3
    static let pluckBend = 0.004
    static let pluckBendTau = 0.03
    static let attack = 0.0012
    static let spaceStrum = 0.018
    static let returnStrum = 0.026
    static let brushStrum = 0.022
    static let brushNotes: [Int] = [69, 72, 74, 77, 79, 81]

    enum Kind { case normal, sustain, muted, brush }

    static func samples(_ midis: [Int], kind: Kind, peak: Double, strum: Double = 0) -> [Float] {
        let sr = kind == .sustain ? PianoSynth.sustainSampleRate : PianoSynth.sampleRate
        let dur: Double
        switch kind {
        case .normal: dur = noteDuration
        case .sustain: dur = PianoSynth.sustainDuration
        case .muted: dur = PianoSynth.mutedDuration
        case .brush: dur = PianoSynth.pedalDuration
        }
        let n = Int((dur * sr).rounded())
        var out = [Double](repeating: 0, count: n)
        var amps = [Double](repeating: 0, count: partials)
        var e1 = amps, e2 = amps, d1 = amps, d2 = amps
        let vib = kind == .normal || kind == .sustain
        for (j, m) in midis.enumerated() {
            let f = PianoSynth.freq(m)
            let s = min(1.5, max(0.6, pow(262 / f, 0.25)))
            let t1: Double, t2: Double
            switch kind {
            case .normal: t1 = 0.09 * s; t2 = 0.42 * s
            case .sustain: t1 = 0.2 * s; t2 = 1.0 * s
            case .muted: t1 = 0.018; t2 = 0.04
            case .brush: t1 = 0.03; t2 = 0.11
            }
            var kmax = 0
            for k in 0..<partials {
                let kd = Double(k + 1)
                if kd * f >= 0.45 * sr { break }
                amps[k] = abs(sin(Double.pi * kd * pluckPosition)) / kd * exp(-(kd - 1) * f / 6000)
                let damp = 1 + 0.6 * (kd - 1)
                d1[k] = exp(-damp / (sr * t1)); d2[k] = exp(-damp / (sr * t2))
                e1[k] = 0.6; e2[k] = 0.4
                kmax = k + 1
            }
            let start = Int((Double(j) * strum * sr).rounded())
            if start >= n || kmax == 0 { continue }
            var phase = 0.0
            for i in start..<n {
                let tt = Double(i - start) / sr
                var ratio = 1 + pluckBend * exp(-tt / pluckBendTau)
                if vib && tt > vibratoDelay {
                    let u = tt - vibratoDelay
                    ratio += vibratoDepth * (1 - exp(-u / vibratoRise)) * sin(2 * Double.pi * vibratoRate * u)
                }
                phase += 2 * Double.pi * f * ratio / sr
                let c2 = 2 * cos(phase)
                var prev = 0.0, cur = sin(phase), acc = 0.0
                for k in 0..<kmax {
                    if k > 0 { let nx = c2 * cur - prev; prev = cur; cur = nx }
                    acc += amps[k] * (e1[k] + e2[k]) * cur
                    e1[k] *= d1[k]; e2[k] *= d2[k]
                }
                if tt < attack { acc *= 0.5 - 0.5 * cos(Double.pi * tt / attack) }
                out[i] += acc
            }
        }
        let release: Double
        switch kind {
        case .normal: release = 0.08
        case .sustain: release = 0.2
        case .muted: release = 0.03
        case .brush: release = 0.06
        }
        return PianoSynth.finish(out, sampleRate: sr, attack: attack, release: release, peak: peak)
    }

    static func note(_ m: Int, sustain: Bool = false) -> [Float] { samples([m], kind: sustain ? .sustain : .normal, peak: notePeak) }
    static func space() -> [Float] { samples(NoteMap.dantranh.spaceChord, kind: .normal, peak: chordPeak, strum: spaceStrum) }
    static func returnChord() -> [Float] { samples(NoteMap.dantranh.returnChord, kind: .normal, peak: chordPeak, strum: returnStrum) }
    static func delete() -> [Float] { samples([NoteMap.dantranh.deleteNote], kind: .muted, peak: notePeak) }
    /// Pedal (Shift/Caps): vuốt nhẹ 6 dây cao A4 C5 D5 F5 G5 A5.
    static func pedal() -> [Float] { samples(brushNotes, kind: .brush, peak: pedalPeak, strum: brushStrum) }

    /// Nghe thử trong app: G4 A4 C5 A4 G4 (điệu Bắc), cách 0.17 s, ngân chồng — 22.05 kHz.
    static func previewMelody() -> [Float] {
        let step = Int((0.17 * PianoSynth.sampleRate).rounded())
        let notes = [67, 69, 72, 69, 67].map { note($0) }
        var out = [Float](repeating: 0, count: step * (notes.count - 1) + notes[0].count)
        for (i, x) in notes.enumerated() {
            for (j, v) in x.enumerated() { out[i * step + j] += v * 0.8 }
        }
        return out
    }

    /// Bộ nhớ (byte, Float32) bộ nốt dựng sẵn lúc hiện (25 nốt + cách + Enter + ⌫ + pedal).
    static var normalBankBytes: Int {
        let note = Int((noteDuration * PianoSynth.sampleRate).rounded())
        let muted = Int((PianoSynth.mutedDuration * PianoSynth.sampleRate).rounded())
        let ped = Int((PianoSynth.pedalDuration * PianoSynth.sampleRate).rounded())
        return 4 * (NoteMap.dantranh.notes.count * note + 2 * note + muted + ped)
    }

    /// Bộ nhớ bộ nốt ngân (dựng lười khi pedal dùng lần đầu) — cùng cỡ Piano.
    static var sustainBankBytes: Int {
        4 * NoteMap.dantranh.notes.count * Int((PianoSynth.sustainDuration * PianoSynth.sustainSampleRate).rounded())
    }
}

/// Ghi-ta mộc dây sắt (theme "Ghi-ta", 10/2026): dây gảy tổng hợp cộng hoạ âm CÙNG HỌ DanTranhSynth — tất định,
/// Kotlin GuitarSynth Y HỆT (test chốt checksum chung). Khác đàn tranh:
/// - Sáng hơn: gảy gần ngựa đàn (p = 0.13), 10 hoạ âm, giảm theo cao độ chậm hơn (f/9000), mở 0.8 ms.
/// - Thân đàn: hoạ âm quanh ~200 Hz được nâng nhẹ (chuông log2 rộng 0.9 quãng tám, đỉnh +50 %) — ấm vùng trầm-trung.
/// - Tắt hai tầng: phần gảy τ1 = 0.12 s (55 %) + dư âm τ2 = 0.55 s (45 %) × theo cao độ; hoạ âm cao tắt nhanh hơn
///   (1 + 0.9(k−1)) ⇒ nghe ~1.2 s. KHÔNG rung (vibrato) — chỉ căng dây rất nhẹ lúc gảy (+4 cent, về trong 20 ms).
/// - Cách: quạt xuống 6 dây cách nhau 25 ms theo vòng Am → F → C → G (NoteMap.guitar.progression); Enter: quạt "kết"
///   về chủ C chậm hơn (35 ms). Mỗi hợp âm dựng MỘT lần (4 + chủ).
/// - ⌫: "chặn dây" — 4 dây trầm bị tay chặn (tắt ~20 ms) quạt 6 ms + tiếng gõ thân đàn 90 Hz.
/// - Pedal (Shift/Caps): vuốt nhẹ 3 dây cao G3 B3 E4.
/// - Không to hơn Piano: đỉnh nốt 0.32 (Piano 0.34), hợp âm 0.24 (0.30; 6 dây ⇒ RMS ≤ hợp âm Piano), ⌫ 0.26, pedal 0.16 (0.30) — test chốt.
enum GuitarSynth {
    static let noteDuration = 1.2
    static let notePeak = 0.32
    static let chordPeak = 0.24
    static let deletePeak = 0.26
    static let pedalPeak = 0.16
    static let pluckPosition = 0.13
    static let partials = 10
    static let pluckBend = 0.0023
    static let pluckBendTau = 0.02
    static let attack = 0.0008
    static let bodyFreq = 200.0
    static let bodyBoost = 0.5
    static let bodyWidth = 0.9
    static let strum = 0.025
    static let tonicStrum = 0.035
    static let chuckNotes: [Int] = [40, 45, 50, 55]
    static let chuckStrum = 0.006
    static let thumpFreq = 90.0
    static let brushNotes: [Int] = [55, 59, 64]
    static let brushStrum = 0.03

    enum Kind { case normal, sustain, muted, brush }

    /// Mẫu bắt đầu của dây thứ j khi quạt (`strum` giây giữa hai dây).
    static func onset(_ j: Int, strum: Double, sampleRate sr: Double) -> Int { Int((Double(j) * strum * sr).rounded()) }

    /// Cộng hưởng thân đàn: hệ số biên độ theo tần số hoạ âm (1 … 1 + bodyBoost, đỉnh ở bodyFreq).
    static func body(_ f: Double) -> Double {
        let o = log2(f / bodyFreq) / bodyWidth
        return 1 + bodyBoost * exp(-0.5 * o * o)
    }

    static func samples(_ midis: [Int], kind: Kind, peak: Double, strum: Double = 0) -> [Float] {
        let sr = kind == .sustain ? PianoSynth.sustainSampleRate : PianoSynth.sampleRate
        let dur: Double
        switch kind {
        case .normal: dur = noteDuration
        case .sustain: dur = PianoSynth.sustainDuration
        case .muted: dur = PianoSynth.mutedDuration
        case .brush: dur = PianoSynth.pedalDuration
        }
        let n = Int((dur * sr).rounded())
        var out = [Double](repeating: 0, count: n)
        var amps = [Double](repeating: 0, count: partials)
        var e1 = amps, e2 = amps, d1 = amps, d2 = amps
        for (j, m) in midis.enumerated() {
            let f = PianoSynth.freq(m)
            let s = min(1.4, max(0.6, pow(262 / f, 0.25)))
            let t1: Double, t2: Double
            switch kind {
            case .normal: t1 = 0.12 * s; t2 = 0.55 * s
            case .sustain: t1 = 0.25 * s; t2 = 1.1 * s
            case .muted: t1 = 0.012; t2 = 0.03
            case .brush: t1 = 0.04; t2 = 0.15
            }
            var kmax = 0
            for k in 0..<partials {
                let kd = Double(k + 1)
                if kd * f >= 0.45 * sr { break }
                amps[k] = abs(sin(Double.pi * kd * pluckPosition)) / kd * exp(-(kd - 1) * f / 9000) * body(kd * f)
                let damp = 1 + 0.9 * (kd - 1)
                d1[k] = exp(-damp / (sr * t1)); d2[k] = exp(-damp / (sr * t2))
                e1[k] = 0.55; e2[k] = 0.45
                kmax = k + 1
            }
            let start = onset(j, strum: strum, sampleRate: sr)
            if start >= n || kmax == 0 { continue }
            var phase = 0.0
            for i in start..<n {
                let tt = Double(i - start) / sr
                let ratio = 1 + pluckBend * exp(-tt / pluckBendTau)
                phase += 2 * Double.pi * f * ratio / sr
                let c2 = 2 * cos(phase)
                var prev = 0.0, cur = sin(phase), acc = 0.0
                for k in 0..<kmax {
                    if k > 0 { let nx = c2 * cur - prev; prev = cur; cur = nx }
                    acc += amps[k] * (e1[k] + e2[k]) * cur
                    e1[k] *= d1[k]; e2[k] *= d2[k]
                }
                if tt < attack { acc *= 0.5 - 0.5 * cos(Double.pi * tt / attack) }
                out[i] += acc
            }
        }
        if kind == .muted {
            // Tiếng gõ thân đàn khi bàn tay chặn dây.
            let w = 2 * Double.pi * thumpFreq / sr
            for i in 0..<n { out[i] += 0.35 * sin(w * Double(i)) * exp(-Double(i) / (sr * 0.015)) }
        }
        let release: Double
        switch kind {
        case .normal: release = 0.08
        case .sustain: release = 0.2
        case .muted: release = 0.03
        case .brush: release = 0.06
        }
        return PianoSynth.finish(out, sampleRate: sr, attack: attack, release: release, peak: peak)
    }

    static func note(_ m: Int, sustain: Bool = false) -> [Float] { samples([m], kind: sustain ? .sustain : .normal, peak: notePeak) }
    /// Hợp âm thứ i của vòng phím cách: quạt xuống 6 dây, 25 ms giữa hai dây.
    static func chord(_ i: Int) -> [Float] { samples(NoteMap.guitar.progression[i], kind: .normal, peak: chordPeak, strum: strum) }
    /// Cách (không theo vòng) = hợp âm đầu vòng.
    static func space() -> [Float] { chord(0) }
    static func returnChord() -> [Float] { samples(NoteMap.guitar.returnChord, kind: .normal, peak: chordPeak, strum: tonicStrum) }
    static func delete() -> [Float] { samples(chuckNotes, kind: .muted, peak: deletePeak, strum: chuckStrum) }
    static func pedal() -> [Float] { samples(brushNotes, kind: .brush, peak: pedalPeak, strum: brushStrum) }

    /// Nghe thử trong app: quạt Am rồi A3 C4 E4 G4 A4 nối nhau (cách 0.16 s, ngân chồng) — 22.05 kHz.
    static func previewMelody() -> [Float] {
        let step = Int((0.16 * PianoSynth.sampleRate).rounded())
        let lead = chord(0)
        let notes = [57, 60, 64, 67, 69].map { note($0) }
        let off = 3 * step
        var out = [Float](repeating: 0, count: max(lead.count, off + step * (notes.count - 1) + notes[0].count))
        for (j, v) in lead.enumerated() { out[j] += v * 0.8 }
        for (i, x) in notes.enumerated() {
            for (j, v) in x.enumerated() { out[off + i * step + j] += v * 0.8 }
        }
        return out
    }

    /// Bộ nhớ (byte, Float32) bộ nốt dựng sẵn lúc hiện: 25 nốt 1.2 s + 4 hợp âm vòng + chủ (Enter) + ⌫ + pedal.
    static var normalBankBytes: Int {
        let note = Int((noteDuration * PianoSynth.sampleRate).rounded())
        let muted = Int((PianoSynth.mutedDuration * PianoSynth.sampleRate).rounded())
        let ped = Int((PianoSynth.pedalDuration * PianoSynth.sampleRate).rounded())
        return 4 * (NoteMap.guitar.notes.count * note + (NoteMap.guitar.progression.count + 1) * note + muted + ped)
    }

    /// Bộ nhớ bộ nốt ngân (dựng lười khi pedal dùng lần đầu) — cùng cỡ Piano.
    static var sustainBankBytes: Int {
        4 * NoteMap.guitar.notes.count * Int((PianoSynth.sustainDuration * PianoSynth.sustainSampleRate).rounded())
    }
}

/// Nhạc cụ "mỗi phím một nốt" — chọn bảng nốt + bộ tổng hợp; KeySound / KeyboardView dùng CHUNG pool giọng,
/// pedal, buffer theo MIDI cho mọi nhạc cụ (không nhân bản đường Piano). Kotlin KeyInstrument y hệt.
/// Nhạc cụ có vòng hợp âm (`hasProgression`: Piano, Ghi-ta) ⇒ phím cách phát `.chord(i)` theo ChordProgression;
/// Đàn tranh (ngũ cung, không theo hoà âm phương Tây) giữ hợp âm dây buông cố định (`.space`).
enum KeyInstrument: String, CaseIterable {
    case piano, dantranh, guitar

    init?(style: KeySoundStyle) {
        switch style {
        case .piano: self = .piano
        case .dantranh: self = .dantranh
        case .guitar: self = .guitar
        default: return nil
        }
    }

    /// Kiểu đã lưu → nhạc cụ (nil = đường 3 tiếng).
    static func of(_ raw: String?) -> KeyInstrument? { KeyInstrument(style: KeySoundStyle.resolve(raw, customAvailable: true)) }

    var style: KeySoundStyle {
        switch self {
        case .piano: return .piano
        case .dantranh: return .dantranh
        case .guitar: return .guitar
        }
    }
    var map: NoteMap {
        switch self {
        case .piano: return .piano
        case .dantranh: return .dantranh
        case .guitar: return .guitar
        }
    }
    /// Phím cách đi theo vòng hợp âm (ChordProgression).
    var hasProgression: Bool { !map.progression.isEmpty }

    func note(_ m: Int, sustain: Bool = false) -> [Float] {
        switch self {
        case .piano: return PianoSynth.note(m, sustain: sustain)
        case .dantranh: return DanTranhSynth.note(m, sustain: sustain)
        case .guitar: return GuitarSynth.note(m, sustain: sustain)
        }
    }
    func space() -> [Float] {
        switch self {
        case .piano: return PianoSynth.space()
        case .dantranh: return DanTranhSynth.space()
        case .guitar: return GuitarSynth.space()
        }
    }
    /// Hợp âm thứ i của vòng phím cách (nhạc cụ không có vòng ⇒ hợp âm cách cố định).
    func chord(_ i: Int) -> [Float] {
        switch self {
        case .piano: return PianoSynth.chord(i)
        case .dantranh: return DanTranhSynth.space()
        case .guitar: return GuitarSynth.chord(i)
        }
    }
    func returnChord() -> [Float] {
        switch self {
        case .piano: return PianoSynth.returnChord()
        case .dantranh: return DanTranhSynth.returnChord()
        case .guitar: return GuitarSynth.returnChord()
        }
    }
    func delete() -> [Float] {
        switch self {
        case .piano: return PianoSynth.delete()
        case .dantranh: return DanTranhSynth.delete()
        case .guitar: return GuitarSynth.delete()
        }
    }
    func pedal() -> [Float] {
        switch self {
        case .piano: return PianoSynth.pedal()
        case .dantranh: return DanTranhSynth.pedal()
        case .guitar: return GuitarSynth.pedal()
        }
    }
    func previewMelody() -> [Float] {
        switch self {
        case .piano: return PianoSynth.previewMelody()
        case .dantranh: return DanTranhSynth.previewMelody()
        case .guitar: return GuitarSynth.previewMelody()
        }
    }
    var normalBankBytes: Int {
        switch self {
        case .piano: return PianoSynth.normalBankBytes
        case .dantranh: return DanTranhSynth.normalBankBytes
        case .guitar: return GuitarSynth.normalBankBytes
        }
    }
    var sustainBankBytes: Int {
        switch self {
        case .piano: return PianoSynth.sustainBankBytes
        case .dantranh: return DanTranhSynth.sustainBankBytes
        case .guitar: return GuitarSynth.sustainBankBytes
        }
    }
}

/// Pedal ngân (Shift / Caps Lock) — máy trạng thái thuần.
/// - Bấm Shift ra một-lần ⇒ pedal xuống (tiếng pedal), nốt KẾ TIẾP ngân rồi nhả.
/// - Caps Lock ⇒ pedal giữ; tắt Caps (bấm hoặc tự tắt) ⇒ "giảm âm" (damper) các nốt đang ngân.
/// - Shift TỰ bật đầu câu KHÔNG phải pedal (chỉ phím Shift người dùng bấm mới tính).
struct PianoPedal {
    enum State: Equatable { case off, once, caps }
    enum Shift: Equatable { case off, on, caps }
    enum Action: Equatable { case none, pedalDown, damper }
    private(set) var state: State = .off

    var isDown: Bool { state != .off }

    /// Người dùng bấm phím Shift; `result` = trạng thái Shift SAU khi bấm.
    mutating func shiftPressed(_ result: Shift) -> Action {
        switch result {
        case .on: state = .once; return .pedalDown
        case .caps: state = .caps; return .pedalDown
        case .off:
            let was = state
            state = .off
            return was == .caps ? .damper : .none
        }
    }

    /// Gõ một nốt: true ⇒ nốt này ngân. Pedal một-lần nhả sau nốt.
    mutating func noteTyped() -> Bool {
        let s = state != .off
        if state == .once { state = .off }
        return s
    }

    /// Shift đổi KHÔNG do bấm (rời plane, đổi ô…): Caps tắt ⇒ damper.
    mutating func shiftChanged(_ now: Shift) -> Action {
        if state == .caps && now != .caps { state = .off; return .damper }
        return .none
    }
}

/// Pool giọng xoay vòng (round-robin) — mỗi lần bấm lấy giọng kế tiếp, không cấp phát. Các giọng bắt
/// đầu trong cùng `window` (bấm nhiều phím cùng lúc) được hạ âm lượng 1/√n để hợp âm không vỡ tiếng.
struct VoicePool {
    let size: Int
    private(set) var next = 0
    private var starts: [Double]
    static let chordWindow = 0.06

    init(size: Int) {
        self.size = size
        starts = [Double](repeating: -Double.infinity, count: size)
    }

    mutating func allocate(now: Double) -> Int {
        let v = next
        next = (next + 1) % size
        starts[v] = now
        return v
    }

    func isRecent(_ v: Int, now: Double) -> Bool { now - starts[v] <= Self.chordWindow }

    /// Số giọng vừa bắt đầu trong cửa sổ hợp âm.
    func simultaneous(now: Double) -> Int {
        var c = 0
        for v in 0..<size where isRecent(v, now: now) { c += 1 }
        return c
    }

    static func chordScale(_ n: Int) -> Float { 1 / Float(max(1, n)).squareRoot() }
}
