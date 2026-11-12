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

/// Tiếng sự kiện của hiệu ứng (không phải tiếng phím): phát trên đường riêng 22,05 kHz, 2 giọng, chỉ khi Âm thanh phím bật.
enum FxEventSound: Equatable {
    /// Sóng vỗ (Biển) / hò reo (Sút! — Bóng đá).
    case surf, cheer
    func samples() -> [Float] {
        switch self {
        case .surf: return KeySoundSynth.surfSamples()
        case .cheer: return KeySoundSynth.cheerSamples()
        }
    }
}

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
    // Theme "Pixel 8-bit" (11/2026): tiếng "blip" máy chơi game cầm tay — sóng vuông (hoạ âm lẻ) hai nốt nhảy lên.
    case chip
    // Theme "AI" (11/2026): "blip" synth mềm — sine trượt lên (D6 → G6) + bồi nhẹ quãng năm, không nhiễu.
    case ai
    // Theme "Neon Night Club" (11/2026): nhịp club điện tử — phím chữ = hi-hat "tss" ngắn, xoá = kick điện tử, cách /
    // Enter (chức năng) = kick + hat ⇒ gõ chữ rồi cách thành nhịp "tss tss tss BÙM" xen kẽ tự nhiên.
    case club
    // Theme "Ảo giác" (11/2026): "bloop" mơ màng — hai sine lệch nhau ~1 % trượt lên (phách chậm = lượn cao độ nhẹ).
    case dream
    // Theme "Lạc trôi" (11/2026): "Lơ lửng" — làn gió khẽ (nhiễu dải giữa mở chậm) + nốt pad sine mềm, không gắt.
    case airy
    // Theme "Gõ mõ" (11/2026): tiếng mõ gỗ "cốc" ấm, rỗng — moRecipe. Theme "Kính màu": chuông nhỏ mềm — bellRecipe.
    case mo, bell
    // Theme "Mưa đêm" (11/2026): mưa lách tách trên kính — tiếng "tích" nhiễu lọc rất nhỏ + giọt nước "plip" trượt lên,
    // phím chữ đổi cao độ nhẹ theo bộ biến thể cố định (KeySoundSynth.rainVariant) ⇒ nghe như mưa rơi lộp độp.
    case rain
    // Theme "Gym" (11/2026): "keng" kim loại khẽ của bánh tạ sắt — hoạ âm KHÔNG điều hoà (×1, ×1.59, ×2.76, ×5.4 như đĩa
    // kim loại) tắt nhanh + tiếng chạm nhiễu rất ngắn. Seed cố định ("plat").
    case plate
    // Theme "Cung hoàng đạo" (11/2026): chuông sao "twinkle" — sine G6 mềm + E7 khẽ chen, không nhiễu.
    case twinkle
    // Theme "Bóng đá" (11/2026): tiếng bóng "bụp" mềm — thân sine trầm trượt xuống + chút da bóng + hơi cỏ.
    case thump
    // Theme "Bể cá" (11/2026): bọt "bloop" mềm — sine trượt LÊN 380 → 900 Hz, không nhiễu.
    case bloop
    // Theme "Cà phê sữa đá" (11/2026): đá "lanh canh" — vài hoạ âm thuỷ tinh ngắn, nhỏ, hai viên chạm nhau.
    case clink

    /// Bật "Âm thanh phím" lần đầu ⇒ "Nhẹ nhàng" (bật công tắc phải NGHE khác đi; "iOS" = như lúc tắt).
    static let defaultStyle: KeySoundStyle = .subtle
    /// Kiểu tổng hợp 3 tiếng (chữ / xoá / chức năng) — có công thức `baseRecipe`.
    static let presets: [KeySoundStyle] = [.subtle, .wood, .mechanical, .typewriter, .bubble, .rock, .pop, .water, .vintage, .phao, .jingle,
                                           .scifi, .trong, .boo, .bop, .chip, .ai, .club, .dream, .airy, .mo, .bell, .rain, .plate, .twinkle, .thump, .bloop, .clink]
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
        case .chip: return LK("Bíp 8-bit")
        case .ai: return LK("Synth AI")
        case .club: return LK("Nhịp club")
        case .dream: return LK("Mơ màng")
        case .airy: return LK("Lơ lửng")
        case .mo: return LK("Mõ gỗ")
        case .bell: return LK("Chuông nhỏ")
        case .rain: return LK("Mưa")
        case .plate: return LK("Tạ sắt")
        case .twinkle: return LK("Chuông sao")
        case .thump: return LK("Bóng bụp")
        case .bloop: return LK("Bọt cá")
        case .clink: return LK("Đá lanh canh")
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
        case .chip:
            // Bíp 8-bit: sóng VUÔNG dựng bằng hoạ âm lẻ (1, 1/3, 1/5 — không đổi bộ tổng hợp) — nốt B5 (988 Hz) ngắn rồi
            // nhảy lên E6 (1319 Hz) sau 12 ms kiểu "nhặt xu". Đỉnh 0.42 (< Gõ gỗ), ≤ 50 ms, năng lượng dồn đầu mẫu.
            return Recipe(tones: [t(1.0, 988, 988, tau: 0.008), t(0.33, 988 * 3, 988 * 3, tau: 0.008),
                                  t(0.20, 988 * 5, 988 * 5, tau: 0.008),
                                  t(0.85, 1319, 1319, tau: 0.009, delay: 0.012), t(0.28, 1319 * 3, 1319 * 3, tau: 0.009, delay: 0.012),
                                  t(0.17, 1319 * 5, 1319 * 5, tau: 0.009, delay: 0.012)],
                          noises: [],
                          attack: 0.0008, duration: 0.048, outLP: 6000, peak: 0.42)
        case .ai:
            // Synth AI: sine mềm trượt lên D6 (1175 Hz) → G6 (1568 Hz) trong 20 ms + bồi bát độ rất nhẹ, nốt A6 (1760 Hz)
            // khẽ chen sau 14 ms như tiếng "xác nhận". Không nhiễu, đỉnh 0.36 (< Gõ gỗ), ≤ 50 ms, lọc mềm 5 kHz.
            return Recipe(tones: [t(1.0, 1175, 1568, glide: 0.02, tau: 0.016), t(0.16, 2350, 3136, glide: 0.02, tau: 0.007),
                                  t(0.38, 1760, 1760, tau: 0.012, delay: 0.014)],
                          noises: [],
                          attack: 0.002, duration: 0.05, outLP: 5000, peak: 0.36)
        case .club:
            return clubRecipe(.letter)
        case .dream:
            // Mơ màng: "bloop" mềm — sine G5 (784 Hz) trượt lên C6 (1047 Hz) trong 24 ms + bản sao lệch +1,1 % (phách ~9 Hz
            // ⇒ cao độ lượn nhẹ như chorus) + bồi quãng năm rất khẽ. Không nhiễu (checksum không phụ thuộc seed), đỉnh 0.38
            // (< Gõ gỗ), ≤ 56 ms, lọc mềm 3,2 kHz.
            return Recipe(tones: [t(1.0, 784, 1047, glide: 0.024, tau: 0.013), t(0.7, 793, 1058, glide: 0.024, tau: 0.013),
                                  t(0.12, 1176, 1570, glide: 0.024, tau: 0.007)],
                          noises: [],
                          attack: 0.003, duration: 0.054, outLP: 3200, peak: 0.38)
        case .airy:
            return airyRecipe(.letter)
        case .mo:
            return moRecipe
        case .bell:
            return bellRecipe
        case .rain:
            return rainRecipe(.letter, variant: 0)
        case .plate:
            // Tạ sắt: G5 (784 Hz) τ14 ms + các hoạ âm lệch kiểu đĩa kim loại 1.59× / 2.76× / 5.4× tắt nhanh dần, chạm nhiễu
            // hp 900 Hz lp 3.2 kHz τ1.2 ms. Đỉnh 0.42 (< Gõ gỗ), ≤ 52 ms, lọc 4.2 kHz ⇒ "keng" khẽ, không chói.
            return Recipe(tones: [t(1.0, 784, 784, tau: 0.014), t(0.35, 784 * 1.59, 784 * 1.59, tau: 0.012),
                                  t(0.55, 784 * 2.76, 784 * 2.76, tau: 0.010), t(0.3, 784 * 5.4, 784 * 5.4, tau: 0.006)],
                          noises: [n(0.22, hp: 900, lp: 3200, tau: 0.0012)],
                          attack: 0.0006, duration: 0.052, outLP: 4200, peak: 0.42)
        case .twinkle:
            // Chuông sao: sine G6 (1568 Hz) ngân ngắn + C7 (2093 Hz) khẽ chen sau 18 ms như sao lấp lánh + chút hoạ âm
            // cao rất nhẹ. Không nhiễu, đỉnh 0.34 (< Gõ gỗ), ≤ 60 ms, lọc mềm 4,5 kHz.
            return Recipe(tones: [t(1.0, 1568, 1568, tau: 0.016), t(0.55, 2093, 2093, tau: 0.014, delay: 0.018),
                                  t(0.10, 3136, 3136, tau: 0.005)],
                          noises: [],
                          attack: 0.002, duration: 0.058, outLP: 4500, peak: 0.34)
        case .thump:
            // Bóng bụp: sine 120 → 85 Hz (glide 6 ms) τ18 ms (thân bóng) + 240 Hz τ6 ms (0.25, da bóng) + hơi cỏ nhiễu lp 900 Hz
            // τ3 ms (0.25); mở 1,5 ms (êm), 54 ms, lọc 1,4 kHz, đỉnh 0.5 (< Gõ gỗ).
            return Recipe(tones: [t(1.0, 120, 85, glide: 0.006, tau: 0.018), t(0.25, 240, 200, glide: 0.006, tau: 0.006)],
                          noises: [n(0.25, hp: 90, lp: 900, tau: 0.003)],
                          attack: 0.0015, duration: 0.054, outLP: 1400, peak: 0.50)
        case .bloop:
            // Bọt cá: sine trượt LÊN 380 → 900 Hz (glide 14 ms) τ14 ms + bồi bát độ khẽ (0.10); mở 3 ms, 45 ms, lọc 2,8 kHz,
            // đỉnh 0.45 — tròn, ướt, không "tách".
            return Recipe(tones: [t(1.0, 380, 900, glide: 0.014, tau: 0.014), t(0.10, 760, 1800, glide: 0.014, tau: 0.008)],
                          noises: [],
                          attack: 0.003, duration: 0.045, outLP: 2800, peak: 0.45)
        case .clink:
            // Đá lanh canh: G6 1568 Hz τ10 ms + 2350 Hz (0.35) τ6 ms + 3136 Hz (0.15) τ4 ms, viên thứ hai 1661 Hz (0.5) trễ
            // 12 ms; chút xào nhiễu hp 1,5 kHz lp 4 kHz τ0,8 ms (0.15); 50 ms, lọc 3,2 kHz, đỉnh 0.38 — sáng nhưng không chói.
            return Recipe(tones: [t(1.0, 1568, 1568, tau: 0.010), t(0.35, 2350, 2350, tau: 0.006), t(0.15, 3136, 3136, tau: 0.004),
                                  t(0.5, 1661, 1661, tau: 0.009, delay: 0.012)],
                          noises: [n(0.15, hp: 1500, lp: 4000, tau: 0.0008)],
                          attack: 0.0006, duration: 0.05, outLP: 3200, peak: 0.38)
        }
    }

    /// "Lơ lửng" (theme Lạc trôi) — làn gió + pad, MỖI LOẠI PHÍM một biến thể (không theo luật cao độ ×0.86 / ×0.74):
    ///   chữ: nhiễu hp 500 Hz lp 1.5 kHz τ17 ms (1.0) + pad sine 660 → 700 Hz trượt 30 ms τ20 ms (0.22); mở 6 ms; 58 ms.
    ///   xoá: gió trầm hơn — nhiễu hp 300 lp 1.1 kHz τ17 ms + pad 520 → 480 Hz (0.22); 58 ms.
    ///   chức năng (cách / Enter): nhiễu hp 350 lp 1.3 kHz τ16 ms + hai nốt pad 440 Hz + 660 Hz trễ 8 ms ("hà-a"); 60 ms.
    /// Đỉnh chung 0.40 (< Gõ gỗ), mở chậm (không "tách"), trọng tâm phổ thấp. Android KeySoundSynth.airyRecipe y hệt.
    static func airyRecipe(_ k: KeySoundKind) -> Recipe {
        switch k {
        case .letter:
            return Recipe(tones: [t(0.22, 660, 700, glide: 0.030, tau: 0.020)],
                          noises: [n(1.0, hp: 500, lp: 1500, tau: 0.017)],
                          attack: 0.006, duration: 0.058, outLP: 1800, peak: 0.40)
        case .delete:
            return Recipe(tones: [t(0.22, 520, 480, glide: 0.030, tau: 0.020)],
                          noises: [n(1.0, hp: 300, lp: 1100, tau: 0.017)],
                          attack: 0.006, duration: 0.058, outLP: 1500, peak: 0.40)
        case .modifier:
            return Recipe(tones: [t(0.20, 440, 440, tau: 0.016), t(0.14, 660, 660, tau: 0.013, delay: 0.008)],
                          noises: [n(1.0, hp: 350, lp: 1300, tau: 0.016)],
                          attack: 0.006, duration: 0.060, outLP: 1600, peak: 0.40)
        }
    }

    /// Mõ gỗ (theme Gõ mõ): tiếng "cốc" ấm, rỗng — hốc cộng hưởng 860 → 820 Hz τ28 ms (1.0) + thân gỗ 410 → 400 Hz τ40 ms
    /// (0.55) + vệt gõ 2.3× τ6 ms (0.12) + tiếng dùi nhiễu thông dải hp 600 / lp 1 kHz τ2.5 ms (0.35); mở 0.6 ms; 120 ms;
    /// outLP 2.6 kHz; đỉnh 0.50 (RMS + đỉnh < Gõ gỗ, test chốt). Seed CỐ ĐỊNH ("momo"). Android moRecipe y hệt.
    static let moRecipe = Recipe(
        tones: [t(1.0, 860, 820, glide: 0.004, tau: 0.028), t(0.55, 410, 400, glide: 0.006, tau: 0.040),
                t(0.12, 860 * 2.3, 820 * 2.3, glide: 0.004, tau: 0.006)],
        noises: [n(0.35, hp: 600, lp: 1000, tau: 0.0025)],
        attack: 0.0006, duration: 0.12, outLP: 2600, peak: 0.50)

    /// Chuông nhỏ (theme Kính màu): G6 1568 Hz τ110 ms (1.0) + cặp lệch 4 Hz τ120 ms (0.35 — ngân nhẹ) + hoạ âm phi điều
    /// hoà 2.76× τ60 ms (0.30) và 5.4× τ25 ms (0.12) + "hum" quãng tám dưới 784 Hz τ140 ms (0.25). Không nhiễu, mở 1.5 ms,
    /// 360 ms, outLP 5 kHz, đỉnh 0.40 (êm, RMS < Gõ gỗ). Seed CỐ ĐỊNH ("bell"). Android bellRecipe y hệt.
    static let bellRecipe = Recipe(
        tones: [t(1.0, 1568, 1568, tau: 0.11), t(0.35, 1572, 1572, tau: 0.12), t(0.30, 1568 * 2.76, 1568 * 2.76, tau: 0.06),
                t(0.12, 1568 * 5.4, 1568 * 5.4, tau: 0.025), t(0.25, 784, 784, tau: 0.14)],
        noises: [],
        attack: 0.0015, duration: 0.36, outLP: 5000, peak: 0.40)

    /// Mưa (theme Mưa đêm) — "tích" mưa lách tách, NHỎ nhất trong các kiểu (đỉnh 0.34):
    ///   chữ: giọt "plip" sine trượt LÊN 1150 → 1600 Hz (glide 5 ms) τ6 ms (0.55) + nhiễu hp 500 lp 1.8 kHz τ3.2 ms (1.0)
    ///        + hạt thứ hai trễ 9 ms (0.45 τ2 ms); 30 ms; outLP 2.4 kHz. Cao độ (tone + lp nhiễu) × rainPitch[biến thể].
    ///   xoá: trầm hơn — 1000 → 1350 Hz τ7 ms (0.5) + nhiễu lp 1.7 kHz τ3.2 ms + hạt trễ 11 ms (0.35); 34 ms.
    ///   chức năng (cách / Enter): giọt to hơn rơi xuống vũng — 820 → 1100 Hz τ9 ms + giọt nhỏ trễ 13 ms + 3 hạt nhiễu; 40 ms.
    /// Seed cố định ("rain") theo loại phím + biến thể — không theo vị trí case. Android KeySoundSynth.rainRecipe y hệt.
    static let rainPitch: [Double] = [1.0, 1.07, 0.94, 1.12]
    static var rainVariants: Int { rainPitch.count }
    /// Thứ tự biến thể phím chữ (xoay vòng — không bao giờ lặp liền một cao độ) ⇒ "mưa" không đều như máy.
    static let rainOrder: [Int] = [0, 2, 1, 3, 2, 0, 3, 1]
    /// Biến thể của lần bấm phím chữ thứ `n` (0, 1, 2…).
    static func rainVariant(_ n: Int) -> Int { rainOrder[((n % rainOrder.count) + rainOrder.count) % rainOrder.count] }

    static func rainRecipe(_ k: KeySoundKind, variant v: Int) -> Recipe {
        switch k {
        case .letter:
            let p = rainPitch[((v % rainPitch.count) + rainPitch.count) % rainPitch.count]
            return Recipe(tones: [t(0.55, 1150 * p, 1600 * p, glide: 0.005, tau: 0.006)],
                          noises: [n(1.0, hp: 500, lp: 1800 * p, tau: 0.0032), n(0.45, hp: 500, lp: 1800 * p, tau: 0.002, delay: 0.009)],
                          attack: 0.0006, duration: 0.030, outLP: 2400, peak: 0.34)
        case .delete:
            return Recipe(tones: [t(0.5, 1000, 1350, glide: 0.006, tau: 0.007)],
                          noises: [n(1.0, hp: 400, lp: 1700, tau: 0.0032), n(0.35, hp: 400, lp: 1700, tau: 0.002, delay: 0.011)],
                          attack: 0.0006, duration: 0.034, outLP: 2400, peak: 0.34)
        case .modifier:
            return Recipe(tones: [t(0.45, 820, 1100, glide: 0.007, tau: 0.009), t(0.3, 1300, 1700, glide: 0.005, tau: 0.005, delay: 0.013)],
                          noises: [n(1.0, hp: 300, lp: 1500, tau: 0.0045), n(0.5, hp: 400, lp: 1900, tau: 0.0022, delay: 0.013),
                                   n(0.3, hp: 400, lp: 1900, tau: 0.0016, delay: 0.024)],
                          attack: 0.0006, duration: 0.040, outLP: 2200, peak: 0.34)
        }
    }

    static func rainSeed(_ k: KeySoundKind, variant v: Int) -> UInt32 {
        0x7261_696E ^ (0x85EB_CA6B &* UInt32(k.rawValue + 1)) ^ (0x9E37_79B9 &* UInt32(truncatingIfNeeded: v))
    }

    /// Mẫu phím chữ biến thể `v` của kiểu Mưa (biến thể 0 = samples(.rain, .letter)).
    static func rainLetterSamples(_ v: Int) -> [Float] { render(rainRecipe(.letter, variant: v), seed: rainSeed(.letter, variant: v)) }

    /// Nhịp club (theme Neon Night Club) — MỖI LOẠI PHÍM một tiếng riêng (không theo luật cao độ ×0.86 / ×0.74):
    ///   chữ: hi-hat đóng "tss" mềm — nhiễu hp 700 Hz lp 1.7 kHz τ10 ms (1.0) + vệt kim loại 2.2 kHz τ2 ms (0.10); 34 ms.
    ///   xoá: kick điện tử — sine trượt XUỐNG 170 → 55 Hz (glide 7 ms) τ14 ms + "click" nhiễu lp 2.2 kHz τ0.8 ms (0.25); 50 ms.
    ///   chức năng (cách / Enter): kick trầm hơn 150 → 48 Hz + hat nhỏ trễ 9 ms (0.45) ⇒ "bùm-tss"; 56 ms.
    /// Đỉnh chung 0.45 (< Gõ gỗ, test chốt), không chói (trọng tâm phổ < 2.5 kHz). Android KeySoundSynth.clubRecipe y hệt.
    static func clubRecipe(_ k: KeySoundKind) -> Recipe {
        switch k {
        case .letter:
            return Recipe(tones: [t(0.10, 2200, 2200, tau: 0.002)],
                          noises: [n(1.0, hp: 700, lp: 1700, tau: 0.010)],
                          attack: 0.0005, duration: 0.034, outLP: 1800, peak: 0.45)
        case .delete:
            return Recipe(tones: [t(1.0, 170, 55, glide: 0.007, tau: 0.014)],
                          noises: [n(0.25, hp: 300, lp: 2200, tau: 0.0008)],
                          attack: 0.0006, duration: 0.050, outLP: 3000, peak: 0.45)
        case .modifier:
            return Recipe(tones: [t(1.0, 150, 48, glide: 0.007, tau: 0.015), t(0.05, 2200, 2200, tau: 0.002, delay: 0.009)],
                          noises: [n(0.25, hp: 300, lp: 2200, tau: 0.0008), n(0.45, hp: 700, lp: 1700, tau: 0.004, delay: 0.009)],
                          attack: 0.0006, duration: 0.056, outLP: 2400, peak: 0.45)
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

    /// Seed cố định theo tên kiểu ("thum"…) — Android FIXED_SEEDS y hệt.
    static let fixedSeeds: [KeySoundStyle: UInt32] = [.thump: 0x7468_756D, .bloop: 0x626C_6F6F, .clink: 0x636C_696E]

    // MARK: Hò reo (theme Bóng đá — Sút!, 11/2026)
    // Mỗi cú sút một tiếng hò reo đám đông ~0,95 s, từ MỘT dòng nhiễu xorshift32: high-pass 1 cực 300 Hz → low-pass 2 cực
    // 1,6 kHz ("aaa" của đám đông) × vỏ dâng (mở raised-cosine 0,35 s — đỉnh đúng lúc bóng vào lưới) rồi tắt τ 0,32 s sau
    // 0,55 s; điều biên chậm 3 sóng sine (3,1 / 4,7 / 6,3 Hz, ±15 %) như nhiều giọng chồng; lọc ra 1 cực 2,2 kHz → chặn DC
    // 30 Hz → đóng 80 ms → đỉnh 0,28 (mềm hơn mọi tiếng phím). 22,05 kHz như tiếng sóng. Android cheerSamples y hệt.
    static let cheerDuration = 0.95
    static let cheerSwell = 0.35
    static let cheerPeak = 0.28
    static let cheerSeed: UInt32 = 0x6368_6572   // "cher"
    /// Âm lượng tiếng hò reo (× âm lượng phím của người dùng).
    static let cheerVolume = 0.8

    static func cheerSamples() -> [Float] {
        let sr = surfSampleRate
        let count = Int((cheerDuration * sr).rounded())
        func pole(_ f: Double) -> Double { exp(-2 * Double.pi * f / sr) }
        let hA = pole(300), lA = pole(1600), oA = pole(2200), dcA = pole(30)
        var state = cheerSeed
        var hIn = 0.0, hOut = 0.0, l1 = 0.0, l2 = 0.0, o = 0.0, dcIn = 0.0, dcOut = 0.0, peak = 0.0
        let fout = Int(0.080 * sr)
        var out = [Double](repeating: 0, count: count)
        for i in 0..<count {
            let t = Double(i) / sr
            state ^= state << 13; state ^= state >> 17; state ^= state << 5
            let white = Double(state) / Double(UInt32.max) * 2 - 1
            hOut = hA * (hOut + white - hIn); hIn = white
            l1 = (1 - lA) * hOut + lA * l1; l2 = (1 - lA) * l1 + lA * l2
            let env: Double
            if t < cheerSwell { env = 0.5 - 0.5 * cos(Double.pi * t / cheerSwell) }
            else if t < 0.55 { env = 1 }
            else { env = exp(-(t - 0.55) / 0.32) }
            let am = 1 + 0.15 * (sin(2 * Double.pi * 3.1 * t) + sin(2 * Double.pi * 4.7 * t + 1.3) + sin(2 * Double.pi * 6.3 * t + 2.1)) / 3
            let v = l2 * env * am
            o = (1 - oA) * v + oA * o
            dcOut = dcA * (dcOut + o - dcIn); dcIn = o
            var y = dcOut
            let fromEnd = count - 1 - i
            if fromEnd < fout { y *= 0.5 - 0.5 * cos(Double.pi * Double(fromEnd) / Double(fout)) }
            out[i] = y
            peak = max(peak, abs(y))
        }
        let norm = peak > 0 ? cheerPeak / peak : 0
        return out.map { Float($0 * norm) }
    }

    // MARK: Sóng vỗ (theme Biển — SeaFx, 08/11/2026)
    // Mỗi con sóng mới một tiếng "ào" 1,6 s, tổng hợp từ MỘT dòng nhiễu xorshift32 qua 3 nhánh song song:
    //   dâng: low-pass 2 cực 420 Hz, vỏ (t/crash)² — rì rầm lớn dần khi sóng cuộn tới;
    //   vỡ:   high-pass 160 Hz → low-pass 2 cực 1,6 kHz (×2,6), mở 15 ms đúng lúc `surfCrash` (= SeaFx.roll: sóng chạm bờ), tắt τ 280 ms;
    //   rút:  high-pass 1,1 kHz → low-pass 2 cực 3,2 kHz, mở 60 ms, tắt τ 500 ms, xì xào lắc 6 Hz ±20 %.
    // Tổng → low-pass 1 cực 1,8 kHz (trọng tâm phổ < 2,5 kHz như tiếng phím) → chặn DC 30 Hz → mở 30 ms / đóng 80 ms raised-cosine → chuẩn hoá đỉnh 0,30 (mềm hơn mọi tiếng phím).
    // 22,05 kHz (đủ cho nhiễu ≤ 3,2 kHz, nửa bộ nhớ: ~141 KB Float32). Android KeySoundSynth.surfSamples y hệt (checksum chung).
    static let surfSampleRate = 22_050.0
    static let surfDuration = 1.6
    /// Giây từ lúc phát tới tiếng vỡ — PHẢI = SeaFx.roll (test chốt).
    static let surfCrash = 1.15
    static let surfPeak = 0.30
    static let surfSeed: UInt32 = 0x7375_7266   // "surf"

    static func surfSamples() -> [Float] {
        let sr = surfSampleRate, crash = surfCrash
        let count = Int((surfDuration * sr).rounded())
        func pole(_ f: Double) -> Double { exp(-2 * Double.pi * f / sr) }
        let aS = pole(420), hC = pole(160), aC = pole(1600), hH = pole(1100), aH = pole(3200), aO = pole(1800), dcA = pole(30)
        var state = surfSeed
        var s1 = 0.0, s2 = 0.0, chIn = 0.0, chOut = 0.0, c1 = 0.0, c2 = 0.0, hhIn = 0.0, hhOut = 0.0, h1 = 0.0, h2 = 0.0, o = 0.0
        var dcIn = 0.0, dcOut = 0.0, peak = 0.0
        let fin = Int(0.030 * sr), fout = Int(0.080 * sr)
        var out = [Double](repeating: 0, count: count)
        for i in 0..<count {
            let t = Double(i) / sr
            state ^= state << 13; state ^= state >> 17; state ^= state << 5
            let white = Double(state) / Double(UInt32.max) * 2 - 1
            s1 = (1 - aS) * white + aS * s1; s2 = (1 - aS) * s1 + aS * s2
            chOut = hC * (chOut + white - chIn); chIn = white
            c1 = (1 - aC) * chOut + aC * c1; c2 = (1 - aC) * c1 + aC * c2
            hhOut = hH * (hhOut + white - hhIn); hhIn = white
            h1 = (1 - aH) * hhOut + aH * h1; h2 = (1 - aH) * h1 + aH * h2
            let a = t - crash
            let v: Double
            if a < 0 {
                let u = t / crash
                v = 2.2 * u * u * s2
            } else {
                v = 2.2 * exp(-a / 0.30) * s2
                    + 2.6 * (1 - exp(-a / 0.015)) * exp(-a / 0.28) * c2
                    + 0.9 * (1 - exp(-a / 0.06)) * exp(-a / 0.5) * (0.8 + 0.2 * sin(2 * Double.pi * 6 * a)) * h2
            }
            o = (1 - aO) * v + aO * o
            dcOut = dcA * (dcOut + o - dcIn); dcIn = o
            var y = dcOut
            if i < fin { y *= 0.5 - 0.5 * cos(Double.pi * Double(i) / Double(fin)) }
            let fromEnd = count - 1 - i
            if fromEnd < fout { y *= 0.5 - 0.5 * cos(Double.pi * Double(fromEnd) / Double(fout)) }
            out[i] = y
            peak = max(peak, abs(y))
        }
        let norm = peak > 0 ? surfPeak / peak : 0
        return out.map { Float($0 * norm) }
    }

    // MARK: Âm thanh nét vuốt (SwipeSoundStyle, 11/2026)
    // Mỗi kiểu MỘT vòng lặp liền mạch 22,05 kHz mono, tổng hợp từ nhiễu xorshift32 (seed cố định theo tên):
    //   Bút chì (1,0 s): than chì sạn trên giấy — nhiễu × "hạt" (đích biên độ 0,35–1 đổi mỗi 40–220 mẫu, mượt τ1,5 ms)
    //     + lách tách thưa (xác suất 0,09 %/mẫu, xung ±0,8–1,6 tắt τ0,7 ms) → high-pass 2 kHz ×2 → low-pass 2 cực 5,5 kHz;
    //     lực tay 0,85 + 0,15·sin (3 chu kỳ/vòng). Đỉnh 0,30 (sáng nhất, trọng tâm phổ ~5,8 kHz).
    //   Chổi lông (1,2 s): "xoạt" mềm, không hạt — thân hp 300 Hz → lp 2 cực 700 Hz + hơi gió 0,30 × (hp 900 → lp 1,6 kHz);
    //     phồng 0,8 + 0,2·sin (4 chu kỳ/vòng). Đỉnh 0,34 (trầm nhất).
    //   Phấn bảng (1,4 s): nhám, không đều — hạt 0,15–1 (bình phương ⇒ hay nhỏ, thỉnh thoảng gắt) đổi mỗi 30–430 mẫu
    //     τ1 ms → hp 900 Hz ×2 → lp 3,5 kHz; thỉnh thoảng (mỗi 0,25–0,55 s) một tiếng "kít" nhỏ 30–70 ms: sine 1,6–2,4 kHz
    //     rung 3 %/9 Hz, giật 45 Hz (dính-trượt), vỏ nửa sin, biên độ 0,4 — không chói (≤ 2,4 kHz). Đỉnh 0,30.
    //   Bút dạ (1,0 s): đầu phớt lướt, hơi có cao độ — nhiễu hp 600 → lp 2,6 kHz (0,7) + bộ cộng hưởng 2 cực r 0,996 quanh
    //     1250 ± 70 Hz (1 chu kỳ/vòng) × 8; lắc 0,9 + 0,1·sin (3 chu kỳ/vòng). Đỉnh 0,28.
    // Nối vòng: chạy lọc 40 ms bỏ đi, lấy L mẫu + 80 ms chạy tiếp; 80 ms đầu = trộn công suất đều (sin/cos) giữa đầu vòng và
    // phần chạy tiếp ⇒ mẫu cuối nối thẳng vào mẫu đầu (không "tách"). Mọi điều biến tuần hoàn có số chu kỳ nguyên mỗi vòng.
    // Android KeySoundSynth.swipeLoopSamples y hệt (checksum chung).
    static let swipeSampleRate = 22_050.0
    static let swipeCrossfade = 0.08
    static let swipePreroll = 0.04
    /// Bản nghe thử trong app: một nét vuốt mẫu (nhanh – chậm ở phím – nhanh) rồi nhấc tay ở `swipePreviewLift`.
    static let swipePreview = 1.0
    static let swipePreviewLift = 0.85

    //   Roi vụt (1,0 s): "vút" gió sáng hơn Chổi lông — nhiễu hp 1,5 kHz ×2 → lp 2 cực 6,5 kHz; phồng 0,7 + 0,3·sin (2 chu
    //     kỳ/vòng) × 0,9 + 0,1·sin (7). Đỉnh 0,30.
    //   Tia sét (1,2 s): ù điện 100 Hz + bồi 200/300/400 (0,6/0,4/0,25) × 0,1 + từng chùm lách tách 8–40 ms cách 30–180 ms
    //     (xung ±0,5–1 xác suất 8 %/mẫu tắt τ0,4 ms + nhiễu 0,3) → hp 1,5 kHz → lp 2 cực 5 kHz. Đỉnh 0,30.
    //   Plasma (1,2 s): ù năng lượng mượt — sine 160 ± 6 Hz (1 chu kỳ/vòng) + bồi 2× (pha lắc 0,4·sin 5) 0,5 + 3× 0,25, × 0,5,
    //     + nhiễu hp 400 → lp 2 cực 1,2 kHz × 2 ("vù"); lắc chậm 0,75 + 0,25·sin (3 chu kỳ/vòng = 2,5 Hz). Đỉnh 0,28.
    //   Đũa phép (1,4 s): hạt chuông nhỏ lấp lánh — 6 giọng xoay vòng, mỗi hạt một nốt ngũ cung G6…G7 (lệch ±0,2 %), biên độ
    //     0,4–1, tắt τ60–120 ms, bồi 2,76× 0,15; hạt cách 40–160 ms + nền gió hp 3 kHz → lp 2 cực 7 kHz × 0,25. Đỉnh 0,22.
    //     Lớp hạt dày (swipeLayerSamples, seed "wnd2"): hạt cách 15–60 ms, không nền, đỉnh 0,16 — phát × âm lượng² ⇒ vuốt
    //     nhanh hạt dày hơn hẳn, vuốt chậm gần như chỉ còn lớp thưa.
    // Tiếng nhấc tay (swipeLiftSamples, một lần, KHÔNG khi huỷ; độ to = SwipeSoundFx.liftGain(tốc độ 80 ms cuối)):
    //   Roi vụt "chát" 160 ms: nhiễu × (mở 0,6 ms; 0,9·e^(−t/3 ms) + 0,35·e^(−t/35 ms)) → hp 1,2 kHz → lp 2 cực 7 kHz + "tắc"
    //     sine 2,6 kHz τ1,5 ms. Đỉnh 0,55.
    //   Tia sét "xẹt" 220 ms: xung dày 30 ms đầu (25 %/mẫu) rồi thưa dần + nhiễu τ40 ms → hp 1,5 kHz → lp 6 kHz; + "ầm" nhiễu
    //     lp 2 cực 180 Hz × 12, mở τ10 ms tắt τ70 ms. Đỉnh 0,50.
    //   Plasma "víu" 180 ms: sine quét mũ 300 → 1400 Hz (+ 2× 0,3), vỏ sin², chút nhiễu. Đỉnh 0,40.
    //   Đũa phép 340 ms: 5 nốt đi lên C7 D7 E7 G7 A7 cách 40 ms, τ80 ms. Đỉnh 0,40.
    //   Đóng 12 ms cuối (nửa cos). Seed riêng ("wcrk", "ltzp", "plzw", "wgls").
    // Đợt 2 (11/2026):
    //   Sáo trúc (1,2 s): tiếng sáo ở D5 (587,5 Hz = 705 chu kỳ/vòng) + bồi 2× 0,18, 3× 0,06, rung 5 Hz ±0,5 %, lắc 0,94 +
    //     0,06·sin (3) + hơi thở nhiễu hp 1,5 kHz → lp 2 cực 5 kHz × 0,5 (× 0,7 + 0,3·sin pha). Đỉnh 0,20. Bàn phím đọc vòng
    //     này nhanh/chậm theo vị trí ngón (SwipeSoundFx.fluteRate) ⇒ cao độ trượt theo ngón.
    //   Sóng biển (1,4 s): thân "ào" hp 100 → lp 2 cực 650 Hz × (0,55 + 0,45·sin²(πt/L)) + bọt hp 1,2 → lp 2 cực 3,5 kHz × 0,5 ×
    //     (0,3 + 0,7·sin²(πt/L + 0,5)). Đỉnh 0,30.
    //   Mèo kêu (1,2 s): tiếng "rừ" khẽ — nhiễu hp 120 → lp 2 cực 600 Hz × nhịp 25 Hz (0,25 + 0,75·p³) × thở 0,65 + 0,35·sin².
    //     Đỉnh 0,20.
    //   Chim hót (1,4 s): nền lá xào xạc (hp 2,5 → lp 2 cực 6,5 kHz × 0,12) + các câu hót thưa (birdChirps "chrp", câu cách
    //     0,18–0,48 s); lớp hót dày (birdChirps "chr2", câu cách 0,04–0,14 s, không nền, đỉnh 0,16) phát × âm lượng².
    //   Tiếng nhấc tay: Sóng biển = con sóng theme Biển (surfSamples) từ ngay trước lúc vỡ, ~0,52 s, đỉnh 0,40; Mèo kêu "meo"
    //     480 ms (formant), đỉnh 0,40; Chim hót "láy" 300 ms, đỉnh 0,36.
    //   Nốt nhạc theo phím: không vòng lặp — swipeNoteSamples (nốt nhạc cụ âm phím cắt 0,6 s).
    // "Âm của bạn" (custom) không có công thức: hàm ở đây trả Bút chì (vòng dự phòng); file thật — SwipeSoundCustom.

    static func swipeLoopSeconds(_ s: SwipeSoundStyle) -> Double {
        switch s {
        case .none: return 0
        case .pencil, .custom: return 1.0
        case .brush: return 1.2
        case .chalk: return 1.4
        case .marker: return 1.0
        case .whip: return 1.0
        case .lightning: return 1.2
        case .plasma: return 1.2
        case .wand: return 1.4
        case .notes: return 0
        case .flute: return 1.2
        case .waves: return 1.4
        case .cat: return 1.2
        case .birds: return 1.4
        }
    }

    static func swipePeak(_ s: SwipeSoundStyle) -> Double {
        switch s {
        case .none: return 0
        case .pencil, .custom: return 0.30
        case .brush: return 0.34
        case .chalk: return 0.30
        case .marker: return 0.28
        case .whip: return 0.30
        case .lightning: return 0.30
        case .plasma: return 0.28
        case .wand: return 0.22
        case .notes: return 0
        case .flute: return 0.20
        case .waves: return 0.30
        case .cat: return 0.20
        case .birds: return 0.22
        }
    }

    /// Seed cố định theo tên ("pncl", "brsh", "chlk", "mrkr", "whip", "ltng", "plsm", "wand", "flut", "wave", "purr",
    /// "brds") — không theo vị trí case.
    static func swipeSeed(_ s: SwipeSoundStyle) -> UInt32 {
        switch s {
        case .none: return 0
        case .pencil, .custom: return 0x706E_636C
        case .brush: return 0x6272_7368
        case .chalk: return 0x6368_6C6B
        case .marker: return 0x6D72_6B72
        case .whip: return 0x7768_6970
        case .lightning: return 0x6C74_6E67
        case .plasma: return 0x706C_736D
        case .wand: return 0x7761_6E64
        case .notes: return 0
        case .flute: return 0x666C_7574
        case .waves: return 0x7761_7665
        case .cat: return 0x7075_7272
        case .birds: return 0x6272_6473
        }
    }

    /// Đỉnh lớp hạt dày của Đũa phép / lớp tiếng hót dày của Chim hót.
    static let swipeLayerPeak = 0.16

    /// MỘT vòng lặp liền mạch (22,05 kHz mono) của kiểu; Tắt ⇒ rỗng; Âm của bạn ⇒ Bút chì (dự phòng). Tất định —
    /// checksum chung Android.
    static func swipeLoopSamples(_ s: SwipeSoundStyle) -> [Float] {
        guard s != .none else { return [] }
        let st: SwipeSoundStyle = s == .custom ? .pencil : s
        return swipeLoop(st, seed: swipeSeed(st), peak: swipePeak(st), layer: false)
    }

    /// Lớp phát thêm × âm lượng² (dày lên khi vuốt nhanh) — Đũa phép (hạt chuông, seed "wnd2"), Chim hót (tiếng hót dày,
    /// lịch "chr2"); kiểu khác rỗng. Cùng độ dài vòng chính.
    static func swipeLayerSamples(_ s: SwipeSoundStyle) -> [Float] {
        switch s {
        case .wand: return swipeLoop(s, seed: 0x776E_6432, peak: swipeLayerPeak, layer: true)
        case .birds: return swipeLoop(s, seed: swipeSeed(s), peak: swipeLayerPeak, layer: true)
        default: return []
        }
    }

    private static func swipeLoop(_ s: SwipeSoundStyle, seed: UInt32, peak target: Double, layer: Bool) -> [Float] {
        let sr = swipeSampleRate
        let loopSec = swipeLoopSeconds(s)
        let len = Int((loopSec * sr).rounded())
        let f = Int((swipeCrossfade * sr).rounded())
        let p = Int((swipePreroll * sr).rounded())
        let y = swipeRaw(s, p + len + f, sr: sr, loopSec: loopSec, seed: seed, layer: layer)
        var out = [Double](repeating: 0, count: len)
        var peak = 0.0
        for i in 0..<len {
            let z = y[p + i]
            let v: Double
            if i < f {
                let w = Double(i) / Double(f)
                v = z * sin(Double.pi / 2 * w) + y[p + len + i] * cos(Double.pi / 2 * w)
            } else {
                v = z
            }
            out[i] = v
            peak = max(peak, abs(v))
        }
        let norm = peak > 0 ? target / peak : 0
        return out.map { Float($0 * norm) }
    }

    /// Hạt chuông của Đũa phép: 6 giọng xoay vòng, hạt cách `gapMin` + `gapRange`·u giây; `bed` > 0 ⇒ thêm nền gió.
    private static func swipeChimes(_ n: Int, sr: Double, u: () -> Double, gapMin: Double, gapRange: Double,
                                    bed: Double) -> [Double] {
        let notes: [Double] = [1568, 1760, 2093, 2349, 2637, 3136]
        func pole(_ f: Double) -> Double { exp(-2 * Double.pi * f / sr) }
        var ph = [Double](repeating: 0, count: 6), fr = ph, amp = ph, dec = ph
        var voice = 0, next = 0
        let h = pole(3000), a = pole(7000)
        var hi = 0.0, ho = 0.0, l1 = 0.0, l2 = 0.0
        var out = [Double](repeating: 0, count: n)
        for i in 0..<n {
            next -= 1
            if next <= 0 {
                let k = min(5, Int(u() * 6))
                fr[voice] = notes[k] * (1 + 0.004 * (u() - 0.5))
                amp[voice] = 0.4 + 0.6 * u()
                dec[voice] = exp(-1 / ((0.06 + 0.06 * u()) * sr))
                ph[voice] = 0
                voice = (voice + 1) % 6
                next = Int((gapMin + gapRange * u()) * sr)
            }
            var v = 0.0
            for j in 0..<6 where amp[j] > 1e-4 {
                ph[j] += 2 * Double.pi * fr[j] / sr
                v += amp[j] * (sin(ph[j]) + 0.15 * sin(2.76 * ph[j]))
                amp[j] *= dec[j]
            }
            if bed > 0 {
                let x = 2 * u() - 1
                ho = h * (ho + x - hi); hi = x
                l1 = (1 - a) * ho + a * l1; l2 = (1 - a) * l1 + a * l2
                v += bed * l2
            }
            out[i] = v
        }
        return out
    }

    /// Dòng nhiễu đã lọc của kiểu (chưa nối vòng, chưa chuẩn hoá).
    private static func swipeRaw(_ s: SwipeSoundStyle, _ n: Int, sr: Double, loopSec: Double, seed: UInt32,
                                 layer: Bool) -> [Double] {
        var state = seed
        func u() -> Double {
            state ^= state << 13; state ^= state >> 17; state ^= state << 5
            return Double(state) / Double(UInt32.max)
        }
        func pole(_ f: Double) -> Double { exp(-2 * Double.pi * f / sr) }
        let pi = Double.pi
        var out = [Double](repeating: 0, count: n)
        switch s {
        case .none, .custom, .notes: break
        case .pencil:
            let h = pole(2000), a = pole(5500)
            let gK = 1 - exp(-1 / (0.0015 * sr)), cD = exp(-1 / (0.0007 * sr))
            var hi1 = 0.0, ho1 = 0.0, hi2 = 0.0, ho2 = 0.0, l1 = 0.0, l2 = 0.0
            var grain = 0.6, gt = 0.6, left = 0, crack = 0.0
            for i in 0..<n {
                let t = Double(i) / sr
                let x = 2 * u() - 1
                if left <= 0 { gt = 0.35 + 0.65 * u(); left = 40 + Int(u() * 180) }
                left -= 1
                grain += (gt - grain) * gK
                if u() < 0.0009 { crack = (u() < 0.5 ? -1.0 : 1.0) * (0.8 + 0.8 * u()) }
                let v = x * grain + crack
                crack *= cD
                ho1 = h * (ho1 + v - hi1); hi1 = v
                ho2 = h * (ho2 + ho1 - hi2); hi2 = ho1
                l1 = (1 - a) * ho2 + a * l1; l2 = (1 - a) * l1 + a * l2
                out[i] = l2 * (0.85 + 0.15 * sin(2 * pi * 3 / loopSec * t))
            }
        case .brush:
            let hb = pole(300), ab = pole(700), ha = pole(900), aa = pole(1600)
            var bi = 0.0, bo = 0.0, b1 = 0.0, b2 = 0.0, ai = 0.0, ao = 0.0, a1 = 0.0, a2 = 0.0
            for i in 0..<n {
                let t = Double(i) / sr
                let x = 2 * u() - 1
                bo = hb * (bo + x - bi); bi = x
                b1 = (1 - ab) * bo + ab * b1; b2 = (1 - ab) * b1 + ab * b2
                ao = ha * (ao + x - ai); ai = x
                a1 = (1 - aa) * ao + aa * a1; a2 = (1 - aa) * a1 + aa * a2
                out[i] = (b2 + 0.30 * a2) * (0.8 + 0.2 * sin(2 * pi * 4 / loopSec * t))
            }
        case .chalk:
            let h = pole(900), a = pole(3500), gK = 1 - exp(-1 / (0.001 * sr))
            var hi1 = 0.0, ho1 = 0.0, hi2 = 0.0, ho2 = 0.0, l1 = 0.0, l2 = 0.0
            var grain = 0.5, gt = 0.5, left = 0
            var next = Int(0.15 * sr), sqLen = 0, sqPos = 0, sqF = 0.0, ph = 0.0
            for i in 0..<n {
                let x = 2 * u() - 1
                if left <= 0 { let g = u(); gt = 0.15 + 0.85 * g * g; left = 30 + Int(u() * 400) }
                left -= 1
                grain += (gt - grain) * gK
                let v0 = x * grain
                ho1 = h * (ho1 + v0 - hi1); hi1 = v0
                ho2 = h * (ho2 + ho1 - hi2); hi2 = ho1
                l1 = (1 - a) * ho2 + a * l1; l2 = (1 - a) * l1 + a * l2
                var v = l2
                next -= 1
                if next <= 0 {
                    sqLen = Int((0.03 + 0.04 * u()) * sr); sqPos = 0; sqF = 1600 + 800 * u()
                    next = Int((0.25 + 0.3 * u()) * sr)
                }
                if sqPos < sqLen {
                    let tb = Double(sqPos) / sr
                    ph += 2 * pi * sqF * (1 + 0.03 * sin(2 * pi * 9 * tb)) / sr
                    let st = 0.5 + 0.5 * cos(2 * pi * 45 * tb)
                    v += 0.4 * sin(ph) * st * st * sin(pi * Double(sqPos) / Double(sqLen))
                    sqPos += 1
                }
                out[i] = v
            }
        case .marker:
            let hn = pole(600), an = pole(2600), r = 0.996
            var ni = 0.0, no = 0.0, n1 = 0.0, n2 = 0.0, y1 = 0.0, y2 = 0.0
            for i in 0..<n {
                let t = Double(i) / sr
                let x = 2 * u() - 1
                no = hn * (no + x - ni); ni = x
                n1 = (1 - an) * no + an * n1; n2 = (1 - an) * n1 + an * n2
                let fr = 1250 + 70 * sin(2 * pi / loopSec * t)
                let y = (1 - r) * x + 2 * r * cos(2 * pi * fr / sr) * y1 - r * r * y2
                y2 = y1; y1 = y
                out[i] = (0.7 * n2 + 8 * y) * (0.9 + 0.1 * sin(2 * pi * 3 / loopSec * t))
            }
        case .whip:
            let h = pole(1500), a = pole(6500)
            var hi1 = 0.0, ho1 = 0.0, hi2 = 0.0, ho2 = 0.0, l1 = 0.0, l2 = 0.0
            for i in 0..<n {
                let t = Double(i) / sr
                let x = 2 * u() - 1
                ho1 = h * (ho1 + x - hi1); hi1 = x
                ho2 = h * (ho2 + ho1 - hi2); hi2 = ho1
                l1 = (1 - a) * ho2 + a * l1; l2 = (1 - a) * l1 + a * l2
                out[i] = l2 * (0.7 + 0.3 * sin(2 * pi * 2 / loopSec * t)) * (0.9 + 0.1 * sin(2 * pi * 7 / loopSec * t))
            }
        case .lightning:
            let h = pole(1500), a = pole(5000), cD = exp(-1 / (0.0004 * sr))
            var hi = 0.0, ho = 0.0, l1 = 0.0, l2 = 0.0
            var next = Int(0.05 * sr), bLeft = 0, imp = 0.0
            for i in 0..<n {
                let t = Double(i) / sr
                let x = 2 * u() - 1
                next -= 1
                if next <= 0 {
                    bLeft = Int((0.008 + 0.032 * u()) * sr)
                    next = bLeft + Int((0.03 + 0.15 * u()) * sr)
                }
                var c = 0.0
                if bLeft > 0 {
                    bLeft -= 1
                    if u() < 0.08 { imp = (u() < 0.5 ? -1.0 : 1.0) * (0.5 + 0.5 * u()) }
                    c = 0.3 * x
                }
                let v = c + imp
                imp *= cD
                ho = h * (ho + v - hi); hi = v
                l1 = (1 - a) * ho + a * l1; l2 = (1 - a) * l1 + a * l2
                let hum = sin(2 * pi * 100 * t) + 0.6 * sin(2 * pi * 200 * t) + 0.4 * sin(2 * pi * 300 * t)
                    + 0.25 * sin(2 * pi * 400 * t)
                out[i] = l2 + 0.1 * hum
            }
        case .plasma:
            let hn = pole(400), an = pole(1200)
            var ni = 0.0, no = 0.0, n1 = 0.0, n2 = 0.0, ph = 0.0
            for i in 0..<n {
                let t = Double(i) / sr
                let x = 2 * u() - 1
                no = hn * (no + x - ni); ni = x
                n1 = (1 - an) * no + an * n1; n2 = (1 - an) * n1 + an * n2
                let wob = 0.75 + 0.25 * sin(2 * pi * 3 / loopSec * t)
                ph += 2 * pi * (160 + 6 * sin(2 * pi / loopSec * t)) / sr
                let tone = sin(ph) + 0.5 * sin(2 * ph + 0.4 * sin(2 * pi * 5 / loopSec * t)) + 0.25 * sin(3 * ph)
                out[i] = (0.5 * tone + 2.0 * n2) * wob
            }
        case .wand:
            out = layer ? swipeChimes(n, sr: sr, u: u, gapMin: 0.015, gapRange: 0.045, bed: 0)
                        : swipeChimes(n, sr: sr, u: u, gapMin: 0.04, gapRange: 0.12, bed: 0.25)
        case .flute:
            // Tần số gốc làm tròn để vòng có số chu kỳ NGUYÊN (705 chu kỳ / 1,2 s = 587,5 Hz) + rung 6 chu kỳ/vòng ⇒ pha
            // tuần hoàn đúng một vòng: đoạn trộn nối vòng là hai bản cùng pha (không hụt tiếng).
            let f0 = (587.33 * loopSec).rounded() / loopSec
            let hb = pole(1500), ab = pole(5000)
            var bi = 0.0, bo = 0.0, b1 = 0.0, b2 = 0.0, ph = 0.0
            for i in 0..<n {
                let t = Double(i) / sr
                let x = 2 * u() - 1
                bo = hb * (bo + x - bi); bi = x
                b1 = (1 - ab) * bo + ab * b1; b2 = (1 - ab) * b1 + ab * b2
                ph += 2 * pi * f0 * (1 + 0.005 * sin(2 * pi * 6 / loopSec * t)) / sr
                let tone = sin(ph) + 0.18 * sin(2 * ph) + 0.06 * sin(3 * ph)
                out[i] = tone * (0.94 + 0.06 * sin(2 * pi * 3 / loopSec * t)) + 0.5 * b2 * (0.7 + 0.3 * sin(ph))
            }
        case .waves:
            let h1 = pole(100), a1 = pole(650), h2 = pole(1200), a2 = pole(3500)
            var bi = 0.0, bo = 0.0, b1 = 0.0, b2 = 0.0, fi = 0.0, fo = 0.0, q1 = 0.0, q2 = 0.0
            for i in 0..<n {
                let t = Double(i) / sr
                let x = 2 * u() - 1
                bo = h1 * (bo + x - bi); bi = x
                b1 = (1 - a1) * bo + a1 * b1; b2 = (1 - a1) * b1 + a1 * b2
                fo = h2 * (fo + x - fi); fi = x
                q1 = (1 - a2) * fo + a2 * q1; q2 = (1 - a2) * q1 + a2 * q2
                let sw = sin(pi * t / loopSec), sf = sin(pi * t / loopSec + 0.5)
                out[i] = b2 * (0.55 + 0.45 * sw * sw) + 0.5 * q2 * (0.3 + 0.7 * sf * sf)
            }
        case .cat:
            let h = pole(120), a = pole(600)
            var bi = 0.0, bo = 0.0, b1 = 0.0, b2 = 0.0
            for i in 0..<n {
                let t = Double(i) / sr
                let x = 2 * u() - 1
                bo = h * (bo + x - bi); bi = x
                b1 = (1 - a) * bo + a * b1; b2 = (1 - a) * b1 + a * b2
                let pl = 0.5 - 0.5 * cos(2 * pi * 25 * t)
                let sb = sin(pi * t / loopSec)
                out[i] = b2 * (0.25 + 0.75 * pl * pl * pl) * (0.65 + 0.35 * sb * sb)
            }
        case .birds:
            if !layer {
                let h = pole(2500), a = pole(6500)
                var bi = 0.0, bo = 0.0, b1 = 0.0, b2 = 0.0
                for i in 0..<n {
                    let t = Double(i) / sr
                    let x = 2 * u() - 1
                    bo = h * (bo + x - bi); bi = x
                    b1 = (1 - a) * bo + a * b1; b2 = (1 - a) * b1 + a * b2
                    out[i] = 0.12 * b2 * (0.8 + 0.2 * sin(2 * pi * 2 / loopSec * t))
                }
            }
            // Tiếng hót đặt theo giờ TRONG vòng (tính từ sau đoạn chạy trước) ⇒ không tiếng nào rơi vào chỗ nối.
            let p = Int((swipePreroll * sr).rounded())
            let chirps = layer ? birdChirps(seed: birdLayerSeed, loopSec: loopSec, gapMin: 0.04, gapRange: 0.10)
                               : birdChirps(seed: birdSeed, loopSec: loopSec, gapMin: 0.18, gapRange: 0.30)
            for c in chirps {
                let s0 = p + Int(c.start * sr), m = Int(c.duration * sr)
                var ph = 0.0
                for j in 0..<m {
                    if s0 + j >= n { break }
                    let tau = Double(j) / sr
                    ph += 2 * pi * c.f0 * pow(c.f1 / c.f0, tau / c.duration) / sr
                    let e = sin(pi * tau / c.duration)
                    out[s0 + j] += c.amp * e * e * (sin(ph) + 0.12 * sin(2 * ph))
                }
            }
        }
        return out
    }

    /// Một tiếng hót ngắn của Chim hót: quét tần số mũ f0 → f1 trong `duration` giây, vỏ sin², biên độ `amp`.
    struct BirdChirp: Equatable {
        let start: Double, duration: Double, f0: Double, f1: Double, amp: Double
    }
    static let birdSeed: UInt32 = 0x6368_7270        // "chrp"
    static let birdLayerSeed: UInt32 = 0x6368_7232   // "chr2"
    /// Không tiếng hót nào trong chừng này giây đầu/cuối vòng (chỗ nối chỉ còn nền lá xào xạc).
    static let birdMargin = 0.1

    /// Lịch tiếng hót trong MỘT vòng (thuần, tất định, = Android): từng câu 2–4 tiếng (35–70 ms, cách 25–55 ms) cùng
    /// hướng quét (lên ×1,5 / xuống ×0,65, gốc 2,6–4,2 kHz, mỗi tiếng sau cao hơn 5 %), câu cách `gapMin` + `gapRange`·u;
    /// mọi tiếng nằm trong [birdMargin, loopSec − birdMargin].
    static func birdChirps(seed: UInt32, loopSec: Double, gapMin: Double, gapRange: Double) -> [BirdChirp] {
        var state = seed
        func u() -> Double {
            state ^= state << 13; state ^= state >> 17; state ^= state << 5
            return Double(state) / Double(UInt32.max)
        }
        var t = birdMargin + 0.5 * gapRange * u()
        var out = [BirdChirp]()
        while true {
            let count = 2 + min(2, Int(u() * 3))
            let base = 2600 + 1600 * u()
            let up = u() < 0.5
            let dur = 0.035 + 0.035 * u()
            let gap = 0.025 + 0.03 * u()
            let len = Double(count) * dur + Double(count - 1) * gap
            if t + len > loopSec - birdMargin { break }
            for c in 0..<count {
                let amp = 0.6 + 0.4 * u()
                let f0 = base * (1 + 0.05 * Double(c))
                out.append(BirdChirp(start: t, duration: dur, f0: f0, f1: f0 * (up ? 1.5 : 0.65), amp: amp))
                t += dur + gap
            }
            t += gapMin + gapRange * u()
        }
        return out
    }

    /// Tiếng ngắn lúc nhấc tay (22,05 kHz mono, đã chuẩn hoá đỉnh); kiểu không có ⇒ rỗng. Tất định — checksum chung Android.
    static func swipeLiftSamples(_ s: SwipeSoundStyle) -> [Float] {
        let cfg: (dur: Double, target: Double, seed: UInt32)
        switch s {
        case .whip: cfg = (0.16, 0.55, 0x7763_726B)
        case .lightning: cfg = (0.22, 0.50, 0x6C74_7A70)
        case .plasma: cfg = (0.18, 0.40, 0x706C_7A77)
        case .wand: cfg = (0.34, 0.40, 0x7767_6C73)
        case .waves: return swipeSettleWave()
        case .cat: cfg = (0.48, 0.34, 0x6D65_6F77)
        case .birds: cfg = (0.30, 0.36, 0x7472_6C6C)
        default: return []
        }
        let dur = cfg.dur, target = cfg.target
        let sr = swipeSampleRate, pi = Double.pi
        var state = cfg.seed
        func u() -> Double {
            state ^= state << 13; state ^= state >> 17; state ^= state << 5
            return Double(state) / Double(UInt32.max)
        }
        func pole(_ f: Double) -> Double { exp(-2 * pi * f / sr) }
        let n = Int((dur * sr).rounded())
        var out = [Double](repeating: 0, count: n)
        switch s {
        case .whip:
            let h = pole(1200), a = pole(7000)
            var hi = 0.0, ho = 0.0, l1 = 0.0, l2 = 0.0
            for i in 0..<n {
                let t = Double(i) / sr
                let x = 2 * u() - 1
                let env = (t < 0.0006 ? t / 0.0006 : 1) * (0.9 * exp(-t / 0.003) + 0.35 * exp(-t / 0.035))
                let v = x * env
                ho = h * (ho + v - hi); hi = v
                l1 = (1 - a) * ho + a * l1; l2 = (1 - a) * l1 + a * l2
                out[i] = l2 + 0.25 * exp(-t / 0.0015) * sin(2 * pi * 2600 * t)
            }
        case .lightning:
            let h = pole(1500), a = pole(6000), b = pole(180), cD = exp(-1 / (0.0003 * sr))
            var hi = 0.0, ho = 0.0, l1 = 0.0, l2 = 0.0, r1 = 0.0, r2 = 0.0, imp = 0.0
            for i in 0..<n {
                let t = Double(i) / sr
                let x = 2 * u() - 1
                let pr = t < 0.03 ? 0.25 : 0.02 * exp(-(t - 0.03) / 0.05)
                if u() < pr { imp = (u() < 0.5 ? -1.0 : 1.0) * (0.5 + 0.5 * u()) }
                let v = imp + 0.2 * x * exp(-t / 0.04)
                imp *= cD
                ho = h * (ho + v - hi); hi = v
                l1 = (1 - a) * ho + a * l1; l2 = (1 - a) * l1 + a * l2
                r1 = (1 - b) * x + b * r1; r2 = (1 - b) * r1 + b * r2
                out[i] = l2 + 12 * r2 * (1 - exp(-t / 0.01)) * exp(-t / 0.07)
            }
        case .plasma:
            var ph = 0.0
            for i in 0..<n {
                let t = Double(i) / sr
                ph += 2 * pi * (300 * pow(1400.0 / 300, t / dur)) / sr
                let e = sin(pi * t / dur)
                out[i] = e * e * (sin(ph) + 0.3 * sin(2 * ph)) + 0.03 * (2 * u() - 1) * e
            }
        case .wand:
            let notes: [Double] = [2093, 2349, 2637, 3136, 3520]
            let det = notes.map { _ in 1 + 0.003 * (u() - 0.5) }
            for i in 0..<n {
                let t = Double(i) / sr
                var v = 0.0
                for k in 0..<5 {
                    let a0 = t - 0.04 * Double(k)
                    if a0 >= 0 {
                        let ph = 2 * pi * notes[k] * det[k] * a0
                        v += (0.6 + 0.1 * Double(k)) * exp(-a0 / 0.08) * (sin(ph) + 0.1 * sin(2.76 * ph))
                    }
                }
                out[i] = v
            }
        case .cat:
            // "Meo" hoạt hình: nguồn hoạ âm (Chebyshev, ≤ 12 bậc dưới 5 kHz, nghiêng 1/k^0,6) qua 3 formant trượt i → a → u
            // (F1 350 → 850 → 350, F2 2300 → 900, F3 3200); f0 520 → ~740 → 440 Hz + rung 6 Hz lớn dần; mở 40 ms, đóng 30 % cuối.
            var ph = 0.0
            for i in 0..<n {
                let t = Double(i) / sr, uu = t / dur
                let f0 = (520 + 260 * sin(pi * uu) - 80 * uu) * (1 + 0.015 * sin(2 * pi * 6 * t) * uu)
                ph += 2 * pi * f0 / sr
                let f1 = 350 + 500 * sin(pi * uu), f2 = 2300 - 1400 * uu
                var env = t < 0.04 ? 0.5 - 0.5 * cos(pi * t / 0.04) : 1
                if uu > 0.7 { env *= 0.5 + 0.5 * cos(pi * (uu - 0.7) / 0.3) }
                let c2 = 2 * cos(ph)
                var prev = 0.0, cur = sin(ph), acc = 0.0
                for k in 1...12 {
                    let fk = Double(k) * f0
                    if fk >= 5000 { break }
                    if k > 1 { let nx = c2 * cur - prev; prev = cur; cur = nx }
                    let d1 = (fk - f1) / 130, d2 = (fk - f2) / 200, d3 = (fk - 3200) / 300
                    acc += (1 / (1 + d1 * d1) + 0.7 / (1 + d2 * d2) + 0.25 / (1 + d3 * d3)) / pow(Double(k), 0.6) * cur
                }
                out[i] = env * acc
            }
        case .birds:
            // Láy: tần số trượt 3,9 → 3,0 kHz, rung ±12 % 24 Hz, biên độ đập 24 Hz, mở 10 ms tắt τ150 ms.
            var ph = 0.0
            for i in 0..<n {
                let t = Double(i) / sr
                let f = (3900 - 900 * (t / dur)) * (1 + 0.12 * sin(2 * pi * 24 * t))
                ph += 2 * pi * f / sr
                let am = 0.5 - 0.5 * cos(2 * pi * 24 * t)
                out[i] = am * min(1, t / 0.01) * exp(-t / 0.15) * (sin(ph) + 0.1 * sin(2 * ph))
            }
        default: break
        }
        return swipeLiftFinish(out, target: target)
    }

    /// Đóng 12 ms cuối (nửa cos) + chuẩn hoá đỉnh — chung mọi tiếng nhấc tay.
    private static func swipeLiftFinish(_ x: [Double], target: Double) -> [Float] {
        var out = x
        let n = out.count, pi = Double.pi
        let fo = Int((0.012 * swipeSampleRate).rounded())
        var peak = 0.0
        for i in 0..<n {
            let fe = n - 1 - i
            if fe < fo { out[i] *= 0.5 - 0.5 * cos(pi * Double(fe) / Double(fo)) }
            peak = max(peak, abs(out[i]))
        }
        let norm = peak > 0 ? target / peak : 0
        return out.map { Float($0 * norm) }
    }

    /// Sóng biển — tiếng nhấc tay: DÙNG LẠI con sóng của theme Biển (surfSamples, cùng 22,05 kHz) từ ngay trước lúc vỡ
    /// (`swipeSettleFrom` 1,08 s) tới hết: sóng vỡ rồi rút xì xào ~0,52 s; mở 25 ms nửa cos. Đỉnh 0,40.
    static let swipeSettleFrom = 1.08
    private static func swipeSettleWave() -> [Float] {
        let x = surfSamples()
        let i0 = Int((swipeSettleFrom * swipeSampleRate).rounded()), fi = Int((0.025 * swipeSampleRate).rounded())
        var out = [Double](repeating: 0, count: x.count - i0)
        for i in 0..<out.count {
            var v = Double(x[i0 + i])
            if i < fi { v *= 0.5 - 0.5 * cos(Double.pi * Double(i) / Double(fi)) }
            out[i] = v
        }
        return swipeLiftFinish(out, target: 0.40)
    }

    // MARK: Nốt nhạc theo phím + Sáo trúc (bản nghe thử)
    // Nốt: nốt thường của nhạc cụ (KeyInstrument.note — Piano / Đàn tranh / Ghi-ta, CÙNG bộ tổng hợp âm phím) cắt còn
    // `swipeNoteDuration` (0,6 s), đóng 150 ms cuối nửa cos, chuẩn hoá đỉnh `swipeNotePeak` 0,26 (nhỏ hơn nốt âm phím; nhiều
    // nốt chồng nhau khi vuốt nhanh). 14 bậc (SwipeNoteMap) ⇒ ~0,74 MB Float32 mỗi nhạc cụ, dựng lười ở cú vuốt đầu.
    static let swipeNoteDuration = 0.6
    static let swipeNoteFade = 0.15
    static let swipeNotePeak = 0.26
    static var swipeNoteLength: Int { Int((swipeNoteDuration * swipeSampleRate).rounded()) }

    /// Nốt bậc `step` (0…13) của nhạc cụ, đã cắt/đóng/chuẩn hoá. Tất định — checksum chung Android.
    static func swipeNoteSamples(_ inst: KeyInstrument, step: Int) -> [Float] {
        let x = inst.note(SwipeNoteMap.midi(step: step, scale: inst.map.scale))
        let n = swipeNoteLength, f = Int((swipeNoteFade * swipeSampleRate).rounded())
        var out = [Double](repeating: 0, count: n)
        var pk = 0.0
        for i in 0..<min(n, x.count) {
            var v = Double(x[i])
            let fe = n - 1 - i
            if fe < f { v *= 0.5 - 0.5 * cos(Double.pi * Double(fe) / Double(f)) }
            out[i] = v
            pk = max(pk, abs(v))
        }
        let g = pk > 0 ? swipeNotePeak / pk : 0
        return out.map { Float($0 * g) }
    }

    /// Cả 14 nốt (chỉ số = bậc).
    static func swipeNoteBank(_ inst: KeyInstrument) -> [[Float]] { (0..<SwipeNoteMap.steps).map { swipeNoteSamples(inst, step: $0) } }

    /// Nét vuốt mẫu của bản nghe thử: chữ "viet" trên QWERTY chuẩn (phím 36 × hàng 54), đi đều 120 điểm/giây trong
    /// `swipePreviewLift` giây. Trả tâm phím + các điểm (x, y, giây).
    static let swipeDemoWord = "viet"
    static func swipeDemoPath() -> (centers: [Float], keyWidth: Float, points: [(x: Double, y: Double, t: Double)]) {
        let kw: Float = 36, c = SwipeKeyTracker.qwertyCenters(keyWidth: kw, rowHeight: 54)
        let wp = swipeDemoWord.unicodeScalars.map { ch -> (Double, Double) in
            let k = Int(ch.value) - 97
            return (Double(c[2 * k]), Double(c[2 * k + 1]))
        }
        let seg = (0..<(wp.count - 1)).map { hypot(wp[$0 + 1].0 - wp[$0].0, wp[$0 + 1].1 - wp[$0].1) }
        let total = seg.reduce(0, +)
        let steps = Int(swipePreviewLift * 120)
        var pts = [(x: Double, y: Double, t: Double)]()
        for k in 0...steps {
            var s = total * Double(k) / Double(steps)
            var j = 0
            while j < seg.count - 1 && s > seg[j] { s -= seg[j]; j += 1 }
            let a = seg[j] > 0 ? min(1, s / seg[j]) : 0
            pts.append((wp[j].0 + (wp[j + 1].0 - wp[j].0) * a, wp[j].1 + (wp[j + 1].1 - wp[j].1) * a, Double(k) / 120))
        }
        return (c, kw, pts)
    }

    /// Bản nghe thử Nốt nhạc theo phím: nét "viet" qua SwipeKeyTracker (cùng bộ dò phím với bàn phím) ⇒ v h i u y t r e r t,
    /// mỗi nốt × `SwipeSoundFx.previewNoteGain`, ngân hết. Tất định — checksum chung Android.
    static func swipeNotesPreview(_ inst: KeyInstrument) -> [Float] {
        let d = swipeDemoPath()
        guard var tr = SwipeKeyTracker(centers: d.centers, keyWidth: d.keyWidth) else { return [] }
        var events = [(at: Int, step: Int)]()
        for p in d.points {
            let k = tr.feed(x: p.x, y: p.y)
            if k >= 0 { events.append((Int((p.t * swipeSampleRate).rounded()), SwipeNoteMap.step(letter: k))) }
        }
        guard let lastAt = events.last?.at else { return [] }
        let len = swipeNoteLength, g = SwipeSoundFx.previewNoteGain
        var bank = [Int: [Float]]()
        var out = [Double](repeating: 0, count: lastAt + len)
        for e in events {
            let x = bank[e.step] ?? swipeNoteSamples(inst, step: e.step)
            bank[e.step] = x
            for j in 0..<len { out[e.at + j] += Double(x[j]) * g }
        }
        return out.map { Float($0) }
    }

    /// Bản nghe thử Sáo trúc: vòng lặp đọc với tốc độ theo vị trí ngang của nét "viet" (SwipeSoundFx.fluteRate, trượt
    /// τ glideTau, nội suy tuyến tính — y như render bàn phím), âm lượng theo đường cong tốc độ mẫu, tắt dần fluteRelease.
    static func swipeFlutePreview() -> [Float] {
        let loop = swipeLoopSamples(.flute), n0 = loop.count
        let d = swipeDemoPath()
        guard n0 > 0, let tr = SwipeKeyTracker(centers: d.centers, keyWidth: d.keyWidth) else { return [] }
        let sr = swipeSampleRate
        let lift = Int((swipePreviewLift * sr).rounded())
        let n = max(Int((swipePreview * sr).rounded()), lift + Int((SwipeSoundFx.fluteRelease * sr).rounded()) + 2)
        let kg = 1 - exp(-1 / (sr * SwipeSoundFx.glideTau))
        var env = SwipeSoundEnvelope(step: 1 / sr, fade: SwipeSoundFx.fluteRelease)
        var rate = SwipeSoundFx.fluteRate(tr.unitX(d.points[0].x)), pos = 0.0
        let last = d.points.count - 1
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            if i == lift { env.release() }
            let g = env.next(SwipeSoundFx.speedGain(swipeDemoSpeed(Double(i) / sr)))
            let j = min(last, Int(Double(i) / sr * 120))
            rate += (SwipeSoundFx.fluteRate(tr.unitX(d.points[j].x)) - rate) * kg
            let i0 = Int(pos), fr = pos - Double(i0)
            out[i] = Float((Double(loop[i0]) * (1 - fr) + Double(loop[(i0 + 1) % n0]) * fr) * g)
            pos += rate
            if pos >= Double(n0) { pos -= Double(n0) }
        }
        return out
    }

    /// Tốc độ (pt/s) của nét vuốt mẫu ở giây `t`: lên nhanh, chậm lại ở 3 "phím", nhấc tay ở `swipePreviewLift`.
    static func swipeDemoSpeed(_ t: Double) -> Double {
        guard t >= 0, t < swipePreviewLift else { return 0 }
        return SwipeSoundFx.speedFull * sin(Double.pi * t / swipePreviewLift)
            * (0.45 + 0.55 * abs(cos(3 * Double.pi * t / swipePreviewLift)))
    }

    /// Bản nghe thử: vòng lặp × vỏ âm lượng y như lúc vuốt thật (cùng đường cong tốc độ + SwipeSoundEnvelope), lớp hạt dày
    /// × âm lượng², tiếng nhấc tay ở `swipePreviewLift` với độ to cố định `SwipeSoundFx.previewLiftGain`.
    /// Nốt nhạc theo phím: nét "viet" bằng nhạc cụ `instrument` (Âm thanh phím; không phải nhạc cụ ⇒ Đàn tranh).
    /// Sáo trúc: cao độ theo nét "viet".
    static func swipePreviewSamples(_ s: SwipeSoundStyle, instrument: KeyInstrument = .dantranh) -> [Float] {
        switch s {
        case .notes: return swipeNotesPreview(instrument)
        case .flute: return swipeFlutePreview()
        default: return swipePreview(loop: swipeLoopSamples(s), layer: swipeLayerSamples(s), lift: swipeLiftSamples(s))
        }
    }

    /// Bản nghe thử từ vòng lặp cho sẵn ("Âm của bạn": vòng từ file). `loop` rỗng ⇒ rỗng.
    static func swipePreview(loop: [Float], layer: [Float] = [], lift shot: [Float] = []) -> [Float] {
        guard !loop.isEmpty else { return [] }
        let sr = swipeSampleRate
        let lift = Int((swipePreviewLift * sr).rounded())
        let n = max(Int((swipePreview * sr).rounded()), lift + shot.count)
        let lg = SwipeSoundFx.previewLiftGain
        var env = SwipeSoundEnvelope(step: 1 / sr)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            if i == lift { env.release() }
            let g = env.next(SwipeSoundFx.speedGain(swipeDemoSpeed(Double(i) / sr)))
            var v = Double(loop[i % loop.count]) * g
            if !layer.isEmpty { v += Double(layer[i % layer.count]) * g * g }
            if i >= lift && i - lift < shot.count { v += Double(shot[i - lift]) * lg }
            out[i] = Float(v)
        }
        return out
    }

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
        if s == .club { return clubRecipe(k) }   // mỗi loại phím một tiếng (hat / kick / kick + hat)
        if s == .airy { return airyRecipe(k) }   // gió + pad theo loại phím
        if s == .rain { return rainRecipe(k, variant: 0) }
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
        // Nhịp club: seed CỐ ĐỊNH ("club"), không theo vị trí case ⇒ checksum không đổi khi nhánh khác thêm kiểu trước nó.
        if s == .club { return 0x636C_7562 ^ (0x85EB_CA6B &* UInt32(k.rawValue + 1)) }
        // Lơ lửng: seed CỐ ĐỊNH ("airy") — checksum không đổi khi nhánh khác thêm kiểu trước nó.
        if s == .airy { return 0x6169_7279 ^ (0x85EB_CA6B &* UInt32(k.rawValue + 1)) }
        // Mõ gỗ / Chuông nhỏ: seed cố định ("momo" / "bell") — cùng lý do.
        if s == .mo { return 0x6D6F_6D6F ^ (0x85EB_CA6B &* UInt32(k.rawValue + 1)) }
        if s == .bell { return 0x6265_6C6C ^ (0x85EB_CA6B &* UInt32(k.rawValue + 1)) }
        if s == .rain { return rainSeed(k, variant: 0) }
        // Tạ sắt: seed CỐ ĐỊNH ("plat") — như club.
        if s == .plate { return 0x706C_6174 ^ (0x85EB_CA6B &* UInt32(k.rawValue + 1)) }
        // Chuông sao: seed cố định ("twnk") như Nhịp club.
        if s == .twinkle { return 0x7477_6E6B ^ (0x85EB_CA6B &* UInt32(k.rawValue + 1)) }
        // Kiểu theme 11/2026 trở đi: seed CỐ ĐỊNH theo tên (không theo vị trí case — nhánh khác thêm kiểu không đổi checksum).
        if let tag = fixedSeeds[s] { return tag ^ (0x85EB_CA6B &* UInt32(k.rawValue + 1)) }
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
