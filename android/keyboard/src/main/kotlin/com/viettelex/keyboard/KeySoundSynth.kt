package com.viettelex.keyboard

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Kiểu âm phím (setting [Keys.KEY_SOUND_STYLE]); [id] = giá trị lưu/sao lưu (giống iOS).
 * THỨ TỰ entry = ordinal = seed nhiễu ([KeySoundSynth.seed]) ⇒ CHỈ THÊM CUỐI (giữ mẫu cũ + checksum
 * chung với iOS). Thứ tự hiển thị: [MENU_ORDER].
 */
enum class KeySoundStyle(val id: String, val viTitle: String) {
    SUBTLE("subtle", "Nhẹ nhàng"), // l10n-key
    WOOD("wood", "Gõ gỗ"), // l10n-key
    MECHANICAL("mechanical", "Bàn phím cơ"), // l10n-key
    TYPEWRITER("typewriter", "Máy chữ"), // l10n-key
    BUBBLE("bubble", "Bong bóng"), // l10n-key
    CUSTOM("custom", "Âm của bạn"), // l10n-key
    /** Âm thanh khi chạm của hệ thống (playSoundEffect) — không SoundPool, miễn phí. iOS: "iOS". */
    SYSTEM("system", "Hệ thống"), // l10n-key
    ROCK("rock", "Đá"), // l10n-key
    POP("pop", "Pop"), // l10n-key
    WATER("water", "Nước"), // l10n-key
    VINTAGE("vintage", "Cổ điển"), // l10n-key
    PHAO("phao", "Pháo"), // l10n-key
    JINGLE("jingle", "Chuông"), // l10n-key
    /** Mỗi phím một nốt ([PianoMap]/[PianoSynth]) — không dùng đường 3 tiếng. */
    PIANO("piano", "Piano"), // l10n-key
    /** Theme "Sen Việt" (19/10/2026): mỗi phím một nốt đàn tranh ([KeyInstrument.DANTRANH]). */
    DANTRANH("dantranh", "Đàn tranh"), // l10n-key
    /** Bộ đủ món 10/2026 (theme Vũ trụ): "bíp" synth mềm, nhỏ — công thức đầu iOS/Shared/KeySoundSynth.swift. */
    SCIFI("scifi", "Bíp sci-fi"), // l10n-key
    // Bộ theme đủ món 10/2026: Trống lân (Trung Thu), Ma quái (Halloween) — công thức đầu file Swift.
    TRONG("trong", "Trống lân"), // l10n-key
    BOO("boo", "Ma quái"), // l10n-key
    /** Theme "Ghi-ta" (10/2026): mỗi phím một nốt ghi-ta mộc dây sắt ([KeyInstrument.GUITAR]), cách = quạt hợp âm theo vòng. */
    GUITAR("guitar", "Ghi-ta mộc"), // l10n-key
    /** Theme "Đập chuột" (10/2026): búa gỗ bọc vải gõ nhẹ — công thức đầu file Swift. */
    BOP("bop", "Búa gỗ"), // l10n-key
    /** Theme "Pixel 8-bit" (11/2026): "blip" sóng vuông (hoạ âm lẻ) hai nốt nhảy lên — công thức đầu file Swift. */
    CHIP("chip", "Bíp 8-bit"), // l10n-key
    /** Theme "AI" (11/2026): "blip" synth mềm — sine trượt lên D6 → G6 + nốt A6 khẽ chen — công thức đầu file Swift. */
    AI("ai", "Synth AI"), // l10n-key
    /** Theme "Neon Night Club" (11/2026): nhịp club — chữ = hi-hat, xoá = kick, chức năng = kick + hat ([KeySoundSynth.clubRecipe]). */
    CLUB("club", "Nhịp club"), // l10n-key
    /** Theme "Ảo giác" (11/2026): "bloop" mơ màng — hai sine lệch ~1 % trượt lên (phách chậm = lượn cao độ nhẹ). */
    DREAM("dream", "Mơ màng"), // l10n-key
    /** Theme "Lạc trôi" (11/2026): "Lơ lửng" — làn gió khẽ + pad sine mềm ([KeySoundSynth.airyRecipe]). */
    AIRY("airy", "Lơ lửng"), // l10n-key
    /** Theme "Gõ mõ" (11/2026): mõ gỗ "cốc" ấm, rỗng ([KeySoundSynth.MO_RECIPE]). */
    MO("mo", "Mõ gỗ"), // l10n-key
    /** Theme "Kính màu" (11/2026): chuông nhỏ mềm, vài hoạ âm phi điều hoà ([KeySoundSynth.BELL_RECIPE]). */
    BELL("bell", "Chuông nhỏ"), // l10n-key
    /** Theme "Mưa đêm" (11/2026): mưa lách tách trên kính — phím chữ xoay 4 biến thể cao độ ([KeySoundSynth.rainRecipe]). */
    RAIN("rain", "Mưa"), // l10n-key
    /** Theme "Gym" (11/2026): "keng" kim loại khẽ của bánh tạ sắt (hoạ âm không điều hoà) — công thức đầu file Swift. */
    PLATE("plate", "Tạ sắt"), // l10n-key
    /** Theme "Cung hoàng đạo" (11/2026): chuông sao — sine G6 mềm + C7 khẽ chen, không nhiễu. */
    TWINKLE("twinkle", "Chuông sao"), // l10n-key
    /** Theme "Bóng đá" (11/2026): tiếng bóng "bụp" mềm — thân sine trầm trượt xuống + chút da bóng + hơi cỏ (iOS thump). */
    THUMP("thump", "Bóng bụp"), // l10n-key
    /** Theme "Bể cá" (11/2026): bọt "bloop" mềm — sine trượt LÊN 380 → 900 Hz, không nhiễu (iOS bloop). */
    BLOOP("bloop", "Bọt cá"), // l10n-key
    /** Theme "Cà phê sữa đá" (11/2026): đá "lanh canh" — vài hoạ âm thuỷ tinh ngắn, nhỏ, hai viên chạm nhau (iOS clink). */
    CLINK("clink", "Đá lanh canh"); // l10n-key

    /** true ⇒ phát qua SoundPool riêng; [SYSTEM] ⇒ playSoundEffect, không dựng gì. */
    val usesPool: Boolean get() = this != SYSTEM

    companion object {
        /** Bật "Âm thanh phím" lần đầu ⇒ "Nhẹ nhàng" (bật công tắc phải NGHE khác đi; "Hệ thống" = như lúc tắt). */
        val DEFAULT = SUBTLE
        /** Kiểu tổng hợp 3 tiếng (chữ / xoá / chức năng) — có công thức [KeySoundSynth.baseRecipe]. */
        val PRESETS = listOf(SUBTLE, WOOD, MECHANICAL, TYPEWRITER, BUBBLE, ROCK, POP, WATER, VINTAGE, PHAO, JINGLE, SCIFI,
            TRONG, BOO, BOP, CHIP, AI, CLUB, DREAM, AIRY, MO, BELL, RAIN, PLATE, TWINKLE, THUMP, BLOOP, CLINK)
        /** Mọi kiểu dựng sẵn (3 tiếng + nhạc cụ mỗi phím một nốt: Piano, Đàn tranh, Ghi-ta). */
        val ALL_PRESETS = PRESETS + PIANO + DANTRANH + GUITAR
        /**
         * DANH SÁCH DUY NHẤT id hợp lệ cho trường "sound" của theme JSON (chọn theme ⇒ đặt
         * keySoundStyle). Không gồm "system"/"custom". iOS: KeySoundStyle.presetIDs — test chốt trùng.
         */
        val PRESET_IDS: List<String> = ALL_PRESETS.map { it.id }
        /** Thứ tự trong trang "Âm thanh gõ": hệ thống đầu, âm tự chọn cuối (giống iOS menuOrder). */
        val MENU_ORDER = listOf(SYSTEM) + ALL_PRESETS + CUSTOM
        val IDS: Set<String> = entries.map { it.id }.toSet()
        fun of(id: String?): KeySoundStyle? = entries.firstOrNull { it.id == id }

        /** Giá trị lưu → kiểu thật sự phát. Lạ ⇒ mặc định; custom mà file vắng/hỏng ⇒ mặc định. */
        fun resolve(raw: String?, customAvailable: Boolean): KeySoundStyle {
            val s = of(raw) ?: return DEFAULT
            return if (s == CUSTOM && !customAvailable) DEFAULT else s
        }

        /** Kiểu đã lưu có cần SoundPool không. Lạ ⇒ mặc định ⇒ cần; "system" ⇒ không. */
        fun needsPool(raw: String?): Boolean = resolve(raw, true).usesPool
    }
}

/**
 * Âm thanh phím riêng (setting [Keys.KEY_SOUND], mặc định TẮT): 3 tiếng (chữ / xoá / phím
 * chức năng) theo [KeySoundStyle], tổng hợp tất định lúc chạy — không có file âm thanh bên
 * thứ ba. Thuật toán + công thức Y HỆT iOS/Shared/KeySoundSynth.swift (test chốt checksum
 * chung). Công thức từng kiểu + lý do "không chói" ghi ở đầu file Swift.
 */
object KeySoundSynth {
    const val SAMPLE_RATE = 44_100
    /** Đổi khi đổi thuật toán/công thức ⇒ tên file WAV cache đổi theo. */
    const val VERSION = 2

    enum class Kind { LETTER, DELETE, MODIFIER }

    data class Tone(val amp: Double, val delay: Double, val f0: Double, val fEnd: Double, val glide: Double, val tau: Double)
    data class Noise(val amp: Double, val delay: Double, val hp: Double, val lp: Double, val tau: Double)
    data class Recipe(val tones: List<Tone>, val noises: List<Noise>, val attack: Double, val duration: Double,
                      val outLP: Double, val peak: Double)

    private fun t(amp: Double, f0: Double, fEnd: Double, glide: Double = 0.008, tau: Double, delay: Double = 0.0) =
        Tone(amp, delay, f0, fEnd, glide, tau)
    private fun n(amp: Double, hp: Double = 120.0, lp: Double, tau: Double, delay: Double = 0.0) =
        Noise(amp, delay, hp, lp, tau)

    fun baseRecipe(s: KeySoundStyle): Recipe = when (s) {
        KeySoundStyle.SUBTLE, KeySoundStyle.CUSTOM, KeySoundStyle.SYSTEM, KeySoundStyle.PIANO, KeySoundStyle.DANTRANH,
        KeySoundStyle.GUITAR -> Recipe(
            listOf(t(1.0, 500.0, 360.0, tau = 0.007), t(0.24, 1050.0, 900.0, tau = 0.0025)),
            listOf(n(0.30, lp = 1900.0, tau = 0.002)), 0.0016, 0.032, 2600.0, 0.80)
        KeySoundStyle.WOOD -> Recipe(
            listOf(t(1.0, 640.0, 590.0, tau = 0.009), t(0.28, 640 * 2.72, 590 * 2.72, tau = 0.0026)),
            listOf(n(0.30, lp = 2400.0, tau = 0.0014)), 0.0009, 0.042, 3800.0, 0.80)
        KeySoundStyle.MECHANICAL -> Recipe(
            listOf(t(1.0, 230.0, 180.0, glide = 0.010, tau = 0.012), t(0.55, 520.0, 450.0, tau = 0.0045),
                t(0.45, 300.0, 280.0, tau = 0.005, delay = 0.007)),
            listOf(n(0.55, hp = 90.0, lp = 1300.0, tau = 0.0035), n(0.28, hp = 90.0, lp = 1300.0, tau = 0.002, delay = 0.007)),
            0.0014, 0.046, 2400.0, 0.80)
        KeySoundStyle.TYPEWRITER -> Recipe(
            listOf(t(0.35, 1050.0, 850.0, glide = 0.004, tau = 0.003), t(0.55, 260.0, 240.0, tau = 0.008)),
            listOf(n(0.95, hp = 500.0, lp = 2600.0, tau = 0.0028), n(0.30, hp = 500.0, lp = 2600.0, tau = 0.0018, delay = 0.011)),
            0.0008, 0.044, 3200.0, 0.85)
        KeySoundStyle.BUBBLE -> Recipe(
            listOf(t(1.0, 260.0, 720.0, glide = 0.009, tau = 0.009), t(0.08, 520.0, 1440.0, glide = 0.009, tau = 0.006)),
            emptyList(), 0.003, 0.036, 3000.0, 0.80)
        // Công thức 4 kiểu thêm 19/10/2026: xem đầu iOS/Shared/KeySoundSynth.swift.
        KeySoundStyle.ROCK -> Recipe(
            listOf(t(1.0, 180.0, 150.0, glide = 0.004, tau = 0.005), t(0.40, 180 * 2.35, 150 * 2.35, glide = 0.004, tau = 0.002)),
            listOf(n(0.60, hp = 150.0, lp = 1600.0, tau = 0.0012)), 0.0005, 0.030, 2200.0, 0.85)
        KeySoundStyle.POP -> Recipe(
            listOf(t(1.0, 900.0, 380.0, glide = 0.004, tau = 0.006)),
            listOf(n(0.15, lp = 2000.0, tau = 0.0008)), 0.0008, 0.030, 3000.0, 0.80)
        KeySoundStyle.WATER -> Recipe(
            listOf(t(1.0, 700.0, 1300.0, glide = 0.012, tau = 0.010), t(0.06, 1400.0, 2600.0, glide = 0.012, tau = 0.006)),
            emptyList(), 0.002, 0.042, 3200.0, 0.80)
        KeySoundStyle.VINTAGE -> Recipe(
            listOf(t(0.60, 380.0, 340.0, tau = 0.006), t(0.20, 330.0, 330.0, tau = 0.004, delay = 0.018)),
            listOf(n(0.80, hp = 300.0, lp = 1500.0, tau = 0.002), n(0.25, hp = 300.0, lp = 1500.0, tau = 0.0015, delay = 0.018)),
            0.001, 0.040, 1800.0, 0.80)
        KeySoundStyle.PHAO -> Recipe(
            listOf(t(0.45, 210.0, 170.0, glide = 0.004, tau = 0.004)),
            listOf(n(1.0, hp = 300.0, lp = 2000.0, tau = 0.0024), n(0.60, hp = 300.0, lp = 2000.0, tau = 0.0018, delay = 0.013),
                n(0.40, hp = 300.0, lp = 2000.0, tau = 0.0014, delay = 0.027)),
            0.0004, 0.046, 2400.0, 0.55)
        KeySoundStyle.JINGLE -> Recipe(
            listOf(t(1.0, 880.0, 880.0, tau = 0.012), t(0.55, 886.0, 886.0, tau = 0.014), t(0.22, 880 * 2.76, 880 * 2.76, tau = 0.005)),
            emptyList(), 0.0008, 0.054, 3600.0, 0.62)
        KeySoundStyle.SCIFI -> Recipe(
            listOf(t(1.0, 1100.0, 1400.0, glide = 0.005, tau = 0.008), t(0.16, 2200.0, 2800.0, glide = 0.005, tau = 0.005),
                t(0.45, 1650.0, 1650.0, tau = 0.005, delay = 0.011)),
            emptyList(), 0.002, 0.036, 2800.0, 0.50)
        KeySoundStyle.TRONG -> Recipe(
            listOf(t(1.0, 150.0, 100.0, glide = 0.006, tau = 0.016), t(0.30, 150 * 1.59, 100 * 1.59, glide = 0.006, tau = 0.005)),
            listOf(n(0.22, hp = 80.0, lp = 900.0, tau = 0.0015)), 0.001, 0.054, 1400.0, 0.50)
        KeySoundStyle.BOO -> Recipe(
            listOf(t(1.0, 330.0, 520.0, glide = 0.012, tau = 0.017), t(0.45, 336.6, 530.4, glide = 0.012, tau = 0.017),
                t(0.10, 990.0, 1560.0, glide = 0.012, tau = 0.010)),
            listOf(n(0.06, hp = 200.0, lp = 1200.0, tau = 0.004)), 0.004, 0.054, 2000.0, 0.45)
        KeySoundStyle.BOP -> Recipe(
            listOf(t(1.0, 210.0, 165.0, glide = 0.006, tau = 0.011), t(0.22, 210 * 2.4, 165 * 2.4, glide = 0.006, tau = 0.003)),
            listOf(n(0.18, hp = 90.0, lp = 900.0, tau = 0.0018)), 0.0018, 0.048, 1500.0, 0.50)
        KeySoundStyle.CHIP -> Recipe(
            listOf(t(1.0, 988.0, 988.0, tau = 0.008), t(0.33, 988.0 * 3, 988.0 * 3, tau = 0.008),
                t(0.20, 988.0 * 5, 988.0 * 5, tau = 0.008),
                t(0.85, 1319.0, 1319.0, tau = 0.009, delay = 0.012), t(0.28, 1319.0 * 3, 1319.0 * 3, tau = 0.009, delay = 0.012),
                t(0.17, 1319.0 * 5, 1319.0 * 5, tau = 0.009, delay = 0.012)),
            emptyList(), 0.0008, 0.048, 6000.0, 0.42)
        KeySoundStyle.AI -> Recipe(
            listOf(t(1.0, 1175.0, 1568.0, glide = 0.02, tau = 0.016), t(0.16, 2350.0, 3136.0, glide = 0.02, tau = 0.007),
                t(0.38, 1760.0, 1760.0, tau = 0.012, delay = 0.014)),
            emptyList(), 0.002, 0.05, 5000.0, 0.36)
        KeySoundStyle.CLUB -> clubRecipe(Kind.LETTER)
        // Mơ màng: G5 → C6 trượt 24 ms + bản sao lệch +1,1 % (phách ~9 Hz) + bồi quãng năm khẽ; không nhiễu — y hệt Swift.
        KeySoundStyle.DREAM -> Recipe(
            listOf(t(1.0, 784.0, 1047.0, glide = 0.024, tau = 0.013), t(0.7, 793.0, 1058.0, glide = 0.024, tau = 0.013),
                t(0.12, 1176.0, 1570.0, glide = 0.024, tau = 0.007)),
            emptyList(), 0.003, 0.054, 3200.0, 0.38)
        KeySoundStyle.AIRY -> airyRecipe(Kind.LETTER)
        KeySoundStyle.MO -> MO_RECIPE
        KeySoundStyle.BELL -> BELL_RECIPE
        KeySoundStyle.RAIN -> rainRecipe(Kind.LETTER, 0)
        KeySoundStyle.PLATE -> Recipe(
            listOf(t(1.0, 784.0, 784.0, tau = 0.014), t(0.35, 784 * 1.59, 784 * 1.59, tau = 0.012),
                t(0.55, 784 * 2.76, 784 * 2.76, tau = 0.010), t(0.3, 784 * 5.4, 784 * 5.4, tau = 0.006)),
            listOf(n(0.22, hp = 900.0, lp = 3200.0, tau = 0.0012)), 0.0006, 0.052, 4200.0, 0.42)
        // Chuông sao: G6 (1568 Hz) ngân ngắn + C7 (2093 Hz) chen sau 18 ms + hoạ âm cao rất nhẹ; đỉnh 0.34, ≤ 60 ms. iOS y hệt.
        KeySoundStyle.TWINKLE -> Recipe(
            listOf(t(1.0, 1568.0, 1568.0, tau = 0.016), t(0.55, 2093.0, 2093.0, tau = 0.014, delay = 0.018),
                t(0.10, 3136.0, 3136.0, tau = 0.005)),
            emptyList(), 0.002, 0.058, 4500.0, 0.34)
        // Bóng bụp: sine 120 → 85 Hz (glide 6 ms) τ18 ms + 240 Hz τ6 ms (0.25) + hơi cỏ lp 900 Hz τ3 ms (0.25); 54 ms; đỉnh 0.5.
        KeySoundStyle.THUMP -> Recipe(
            listOf(t(1.0, 120.0, 85.0, glide = 0.006, tau = 0.018), t(0.25, 240.0, 200.0, glide = 0.006, tau = 0.006)),
            listOf(n(0.25, hp = 90.0, lp = 900.0, tau = 0.003)), 0.0015, 0.054, 1400.0, 0.50)
        // Bọt cá: sine 380 → 900 Hz (glide 14 ms) τ14 ms + bồi bát độ khẽ (0.10); mở 3 ms, 45 ms, lọc 2,8 kHz, đỉnh 0.45.
        KeySoundStyle.BLOOP -> Recipe(
            listOf(t(1.0, 380.0, 900.0, glide = 0.014, tau = 0.014), t(0.10, 760.0, 1800.0, glide = 0.014, tau = 0.008)),
            emptyList(), 0.003, 0.045, 2800.0, 0.45)
        // Đá lanh canh: G6 1568 Hz τ10 ms + 2350 Hz (0.35) + 3136 Hz (0.15), viên thứ hai 1661 Hz (0.5) trễ 12 ms; xào nhiễu
        // hp 1,5 kHz lp 4 kHz τ0,8 ms (0.15); 50 ms, lọc 3,2 kHz, đỉnh 0.38.
        KeySoundStyle.CLINK -> Recipe(
            listOf(t(1.0, 1568.0, 1568.0, tau = 0.010), t(0.35, 2350.0, 2350.0, tau = 0.006), t(0.15, 3136.0, 3136.0, tau = 0.004),
                t(0.5, 1661.0, 1661.0, tau = 0.009, delay = 0.012)),
            listOf(n(0.15, hp = 1500.0, lp = 4000.0, tau = 0.0008)), 0.0006, 0.05, 3200.0, 0.38)
    }

    /**
     * "Lơ lửng" (theme Lạc trôi) — làn gió + pad, mỗi loại phím một biến thể: chữ = nhiễu hp 500 lp 1.5 kHz τ17 ms + pad
     * 660 → 700 Hz; xoá = gió trầm hp 300 lp 1.1 kHz + pad 520 → 480 Hz; chức năng = hp 350 lp 1.3 kHz τ16 ms + hai nốt
     * 440 / 660 Hz trễ 8 ms. Mở chậm 6 ms, đỉnh 0.40 (< Gõ gỗ). iOS airyRecipe y hệt (công thức + checksum chung).
     */
    fun airyRecipe(k: Kind): Recipe = when (k) {
        Kind.LETTER -> Recipe(listOf(t(0.22, 660.0, 700.0, glide = 0.030, tau = 0.020)),
            listOf(n(1.0, hp = 500.0, lp = 1500.0, tau = 0.017)), 0.006, 0.058, 1800.0, 0.40)
        Kind.DELETE -> Recipe(listOf(t(0.22, 520.0, 480.0, glide = 0.030, tau = 0.020)),
            listOf(n(1.0, hp = 300.0, lp = 1100.0, tau = 0.017)), 0.006, 0.058, 1500.0, 0.40)
        Kind.MODIFIER -> Recipe(listOf(t(0.20, 440.0, 440.0, tau = 0.016), t(0.14, 660.0, 660.0, tau = 0.013, delay = 0.008)),
            listOf(n(1.0, hp = 350.0, lp = 1300.0, tau = 0.016)), 0.006, 0.060, 1600.0, 0.40)
    }

    /** Mõ gỗ (theme Gõ mõ) — công thức + lý do: iOS KeySoundSynth.moRecipe (checksum chung). */
    val MO_RECIPE = Recipe(
        listOf(t(1.0, 860.0, 820.0, glide = 0.004, tau = 0.028), t(0.55, 410.0, 400.0, glide = 0.006, tau = 0.040),
            t(0.12, 860 * 2.3, 820 * 2.3, glide = 0.004, tau = 0.006)),
        listOf(n(0.35, hp = 600.0, lp = 1000.0, tau = 0.0025)), 0.0006, 0.12, 2600.0, 0.50)

    /** Chuông nhỏ (theme Kính màu) — công thức + lý do: iOS KeySoundSynth.bellRecipe (checksum chung). */
    val BELL_RECIPE = Recipe(
        listOf(t(1.0, 1568.0, 1568.0, tau = 0.11), t(0.35, 1572.0, 1572.0, tau = 0.12), t(0.30, 1568 * 2.76, 1568 * 2.76, tau = 0.06),
            t(0.12, 1568 * 5.4, 1568 * 5.4, tau = 0.025), t(0.25, 784.0, 784.0, tau = 0.14)),
        emptyList(), 0.0015, 0.36, 5000.0, 0.40)

    /**
     * Mưa (theme Mưa đêm) — "tích" mưa lách tách, NHỎ nhất (đỉnh 0.34): chữ = giọt "plip" trượt lên 1150 → 1600 Hz + nhiễu
     * lọc + hạt trễ 9 ms, cao độ × [RAIN_PITCH] theo biến thể; xoá trầm hơn; chức năng = giọt to rơi vũng + 3 hạt.
     * Seed cố định ("rain") theo loại phím + biến thể. iOS rainRecipe y hệt (công thức + checksum chung).
     */
    val RAIN_PITCH = doubleArrayOf(1.0, 1.07, 0.94, 1.12)
    val RAIN_VARIANTS: Int get() = RAIN_PITCH.size
    /** Thứ tự biến thể phím chữ (xoay vòng — không bao giờ lặp liền một cao độ). */
    val RAIN_ORDER = intArrayOf(0, 2, 1, 3, 2, 0, 3, 1)
    /** Biến thể của lần bấm phím chữ thứ [n]. */
    fun rainVariant(n: Int): Int = RAIN_ORDER[((n % RAIN_ORDER.size) + RAIN_ORDER.size) % RAIN_ORDER.size]

    fun rainRecipe(k: Kind, variant: Int): Recipe = when (k) {
        Kind.LETTER -> {
            val p = RAIN_PITCH[((variant % RAIN_PITCH.size) + RAIN_PITCH.size) % RAIN_PITCH.size]
            Recipe(listOf(t(0.55, 1150.0 * p, 1600.0 * p, glide = 0.005, tau = 0.006)),
                listOf(n(1.0, hp = 500.0, lp = 1800.0 * p, tau = 0.0032), n(0.45, hp = 500.0, lp = 1800.0 * p, tau = 0.002, delay = 0.009)),
                0.0006, 0.030, 2400.0, 0.34)
        }
        Kind.DELETE -> Recipe(listOf(t(0.5, 1000.0, 1350.0, glide = 0.006, tau = 0.007)),
            listOf(n(1.0, hp = 400.0, lp = 1700.0, tau = 0.0032), n(0.35, hp = 400.0, lp = 1700.0, tau = 0.002, delay = 0.011)),
            0.0006, 0.034, 2400.0, 0.34)
        Kind.MODIFIER -> Recipe(listOf(t(0.45, 820.0, 1100.0, glide = 0.007, tau = 0.009), t(0.3, 1300.0, 1700.0, glide = 0.005, tau = 0.005, delay = 0.013)),
            listOf(n(1.0, hp = 300.0, lp = 1500.0, tau = 0.0045), n(0.5, hp = 400.0, lp = 1900.0, tau = 0.0022, delay = 0.013),
                n(0.3, hp = 400.0, lp = 1900.0, tau = 0.0016, delay = 0.024)),
            0.0006, 0.040, 2200.0, 0.34)
    }

    fun rainSeed(k: Kind, variant: Int): Int =
        0x7261696E xor (0x85EBCA6B.toInt() * (k.ordinal + 1)) xor (0x9E3779B9.toInt() * variant)

    /** Mẫu phím chữ biến thể [v] của kiểu Mưa (biến thể 0 = samples(RAIN, LETTER)). */
    fun rainLetterSamples(v: Int): FloatArray = render(rainRecipe(Kind.LETTER, v), rainSeed(Kind.LETTER, v))

    /**
     * Nhịp club (theme Neon Night Club) — MỖI LOẠI PHÍM một tiếng riêng (không theo luật cao độ ×0.86 / ×0.74): chữ = hi-hat
     * đóng "tss" mềm, xoá = kick điện tử trượt xuống 170 → 55 Hz, chức năng (cách / Enter) = kick trầm + hat nhỏ trễ 9 ms
     * ("bùm-tss"). Đỉnh 0.45 (< Gõ gỗ), trọng tâm phổ < 2.5 kHz. iOS clubRecipe y hệt (công thức + checksum chung).
     */
    fun clubRecipe(k: Kind): Recipe = when (k) {
        Kind.LETTER -> Recipe(listOf(t(0.10, 2200.0, 2200.0, tau = 0.002)),
            listOf(n(1.0, hp = 700.0, lp = 1700.0, tau = 0.010)), 0.0005, 0.034, 1800.0, 0.45)
        Kind.DELETE -> Recipe(listOf(t(1.0, 170.0, 55.0, glide = 0.007, tau = 0.014)),
            listOf(n(0.25, hp = 300.0, lp = 2200.0, tau = 0.0008)), 0.0006, 0.050, 3000.0, 0.45)
        Kind.MODIFIER -> Recipe(listOf(t(1.0, 150.0, 48.0, glide = 0.007, tau = 0.015), t(0.05, 2200.0, 2200.0, tau = 0.002, delay = 0.009)),
            listOf(n(0.25, hp = 300.0, lp = 2200.0, tau = 0.0008), n(0.45, hp = 700.0, lp = 1700.0, tau = 0.004, delay = 0.009)),
            0.0006, 0.056, 2400.0, 0.45)
    }

    /** "Éc" khi đập trúng chuột (theme Đập chuột — [MoleGame]): hai tiếng chíp vút lên, nhỏ + mềm. iOS squeakRecipe y hệt. */
    val SQUEAK_RECIPE = Recipe(
        listOf(t(1.0, 1900.0, 2700.0, glide = 0.018, tau = 0.030), t(0.18, 3800.0, 5400.0, glide = 0.018, tau = 0.012),
            t(0.75, 2200.0, 3100.0, glide = 0.016, tau = 0.026, delay = 0.062), t(0.12, 4400.0, 6200.0, glide = 0.016, tau = 0.010, delay = 0.062)),
        emptyList(), 0.006, 0.130, 4200.0, 0.42)
    const val SQUEAK_SEED = 0x6D6F6C65
    fun squeakSamples(): FloatArray = render(SQUEAK_RECIPE, SQUEAK_SEED)

    // --- Hò reo (theme Bóng đá — Sút!, 11/2026): công thức + lý do ở iOS KeySoundSynth.cheerSamples (checksum chung) ---
    const val CHEER_DURATION = 0.95
    const val CHEER_SWELL = 0.35
    const val CHEER_PEAK = 0.28
    const val CHEER_SEED = 0x63686572   // "cher"
    /** Âm lượng tiếng hò reo (× âm lượng phím của người dùng). */
    const val CHEER_VOLUME = 0.8

    /** Tiếng hò reo đám đông ~0,95 s (22,05 kHz): nhiễu hp 300 Hz → lp 2 cực 1,6 kHz × vỏ dâng 0,35 s, giữ, tắt τ 0,32 s. */
    fun cheerSamples(): FloatArray {
        val sr = SURF_SAMPLE_RATE.toDouble()
        val count = (CHEER_DURATION * sr).roundToInt()
        fun pole(f: Double) = exp(-2 * PI * f / sr)
        val hA = pole(300.0); val lA = pole(1600.0); val oA = pole(2200.0); val dcA = pole(30.0)
        var state = CHEER_SEED
        var hIn = 0.0; var hOut = 0.0; var l1 = 0.0; var l2 = 0.0; var o = 0.0; var dcIn = 0.0; var dcOut = 0.0; var peak = 0.0
        val fout = (0.080 * sr).toInt()
        val out = DoubleArray(count)
        for (i in 0 until count) {
            val t = i / sr
            state = state xor (state shl 13); state = state xor (state ushr 17); state = state xor (state shl 5)
            val white = (state.toLong() and 0xFFFFFFFFL).toDouble() / 4294967295.0 * 2 - 1
            hOut = hA * (hOut + white - hIn); hIn = white
            l1 = (1 - lA) * hOut + lA * l1; l2 = (1 - lA) * l1 + lA * l2
            val env = when {
                t < CHEER_SWELL -> 0.5 - 0.5 * cos(PI * t / CHEER_SWELL)
                t < 0.55 -> 1.0
                else -> exp(-(t - 0.55) / 0.32)
            }
            val am = 1 + 0.15 * (sin(2 * PI * 3.1 * t) + sin(2 * PI * 4.7 * t + 1.3) + sin(2 * PI * 6.3 * t + 2.1)) / 3
            val v = l2 * env * am
            o = (1 - oA) * v + oA * o
            dcOut = dcA * (dcOut + o - dcIn); dcIn = o
            var y = dcOut
            val fromEnd = count - 1 - i
            if (fromEnd < fout) y *= 0.5 - 0.5 * cos(PI * fromEnd / fout)
            out[i] = y
            peak = maxOf(peak, abs(y))
        }
        val norm = if (peak > 0) CHEER_PEAK / peak else 0.0
        return FloatArray(count) { (out[it] * norm).toFloat() }
    }

    // --- Sóng vỗ (theme Biển — [SeaFx], 08/11/2026): công thức + lý do ở iOS KeySoundSynth.surfSamples (checksum chung) ---
    const val SURF_SAMPLE_RATE = 22_050
    const val SURF_DURATION = 1.6
    /** Giây từ lúc phát tới tiếng vỡ — PHẢI = [SeaFx.ROLL] (test chốt). */
    const val SURF_CRASH = 1.15
    const val SURF_PEAK = 0.30
    const val SURF_SEED = 0x73757266   // "surf"

    /** Tiếng "ào" của MỘT con sóng: nhiễu dâng (lp 420 Hz) → vỡ đúng [SURF_CRASH] (hp 160 / lp 1,6 kHz) → rút xì xào (hp 1,1 / lp 3,2 kHz); ra lp 1,8 kHz. */
    fun surfSamples(): FloatArray {
        val sr = SURF_SAMPLE_RATE.toDouble(); val crash = SURF_CRASH
        val count = (SURF_DURATION * sr).roundToInt()
        fun pole(f: Double) = exp(-2 * PI * f / sr)
        val aS = pole(420.0); val hC = pole(160.0); val aC = pole(1600.0); val hH = pole(1100.0); val aH = pole(3200.0)
        val aO = pole(1800.0); val dcA = pole(30.0)
        var state = SURF_SEED
        var s1 = 0.0; var s2 = 0.0; var chIn = 0.0; var chOut = 0.0; var c1 = 0.0; var c2 = 0.0
        var hhIn = 0.0; var hhOut = 0.0; var h1 = 0.0; var h2 = 0.0; var o = 0.0
        var dcIn = 0.0; var dcOut = 0.0; var peak = 0.0
        val fin = (0.030 * sr).toInt(); val fout = (0.080 * sr).toInt()
        val out = DoubleArray(count)
        for (i in 0 until count) {
            val t = i / sr
            state = state xor (state shl 13); state = state xor (state ushr 17); state = state xor (state shl 5)
            val white = (state.toLong() and 0xFFFFFFFFL).toDouble() / 4294967295.0 * 2 - 1
            s1 = (1 - aS) * white + aS * s1; s2 = (1 - aS) * s1 + aS * s2
            chOut = hC * (chOut + white - chIn); chIn = white
            c1 = (1 - aC) * chOut + aC * c1; c2 = (1 - aC) * c1 + aC * c2
            hhOut = hH * (hhOut + white - hhIn); hhIn = white
            h1 = (1 - aH) * hhOut + aH * h1; h2 = (1 - aH) * h1 + aH * h2
            val a = t - crash
            val v = if (a < 0) {
                val u = t / crash
                2.2 * u * u * s2
            } else {
                2.2 * exp(-a / 0.30) * s2 +
                    2.6 * (1 - exp(-a / 0.015)) * exp(-a / 0.28) * c2 +
                    0.9 * (1 - exp(-a / 0.06)) * exp(-a / 0.5) * (0.8 + 0.2 * sin(2 * PI * 6 * a)) * h2
            }
            o = (1 - aO) * v + aO * o
            dcOut = dcA * (dcOut + o - dcIn); dcIn = o
            var y = dcOut
            if (i < fin) y *= 0.5 - 0.5 * cos(PI * i / fin)
            val fromEnd = count - 1 - i
            if (fromEnd < fout) y *= 0.5 - 0.5 * cos(PI * fromEnd / fout)
            out[i] = y
            peak = maxOf(peak, abs(y))
        }
        val norm = if (peak > 0) SURF_PEAK / peak else 0.0
        return FloatArray(count) { (out[it] * norm).toFloat() }
    }

    // --- Âm thanh nét vuốt ([SwipeSoundStyle], 11/2026) — công thức + lý do ghi ở iOS KeySoundSynth.swift ---
    const val SWIPE_SAMPLE_RATE = 22_050
    /** Đoạn nối vòng lặp: trộn công suất đều (sin/cos) đầu vòng với phần chạy tiếp sau cuối vòng ⇒ không "tách". */
    const val SWIPE_CROSSFADE = 0.08
    /** Chạy bộ lọc trước chừng này giây rồi mới lấy mẫu (bỏ quá độ lúc khởi động bộ lọc). */
    const val SWIPE_PREROLL = 0.04
    /** Bản nghe thử trong app: một nét vuốt mẫu (nhanh – chậm ở phím – nhanh) rồi nhấc tay ở [SWIPE_PREVIEW_LIFT]. */
    const val SWIPE_PREVIEW = 1.0
    const val SWIPE_PREVIEW_LIFT = 0.85

    fun swipeLoopSeconds(s: SwipeSoundStyle): Double = when (s) {
        SwipeSoundStyle.NONE -> 0.0
        SwipeSoundStyle.PENCIL, SwipeSoundStyle.CUSTOM -> 1.0
        SwipeSoundStyle.BRUSH -> 1.2
        SwipeSoundStyle.CHALK -> 1.4
        SwipeSoundStyle.MARKER -> 1.0
        SwipeSoundStyle.WHIP -> 1.0
        SwipeSoundStyle.LIGHTNING -> 1.2
        SwipeSoundStyle.PLASMA -> 1.2
        SwipeSoundStyle.WAND -> 1.4
    }

    fun swipePeak(s: SwipeSoundStyle): Double = when (s) {
        SwipeSoundStyle.NONE -> 0.0
        SwipeSoundStyle.PENCIL, SwipeSoundStyle.CUSTOM -> 0.30
        SwipeSoundStyle.BRUSH -> 0.34
        SwipeSoundStyle.CHALK -> 0.30
        SwipeSoundStyle.MARKER -> 0.28
        SwipeSoundStyle.WHIP -> 0.30
        SwipeSoundStyle.LIGHTNING -> 0.30
        SwipeSoundStyle.PLASMA -> 0.28
        SwipeSoundStyle.WAND -> 0.22
    }

    /** Seed cố định theo tên ("pncl", "brsh", "chlk", "mrkr", "whip", "ltng", "plsm", "wand") — không theo vị trí enum. */
    fun swipeSeed(s: SwipeSoundStyle): Int = when (s) {
        SwipeSoundStyle.NONE -> 0
        SwipeSoundStyle.PENCIL, SwipeSoundStyle.CUSTOM -> 0x706E636C
        SwipeSoundStyle.BRUSH -> 0x62727368
        SwipeSoundStyle.CHALK -> 0x63686C6B
        SwipeSoundStyle.MARKER -> 0x6D726B72
        SwipeSoundStyle.WHIP -> 0x77686970
        SwipeSoundStyle.LIGHTNING -> 0x6C746E67
        SwipeSoundStyle.PLASMA -> 0x706C736D
        SwipeSoundStyle.WAND -> 0x77616E64
    }

    /** Đỉnh lớp hạt dày của Đũa phép. */
    const val SWIPE_LAYER_PEAK = 0.16

    /** MỘT vòng lặp liền mạch (22,05 kHz mono) của kiểu; Tắt ⇒ rỗng; Âm của bạn ⇒ Bút chì (dự phòng). Tất định — checksum chung iOS. */
    fun swipeLoopSamples(s: SwipeSoundStyle): FloatArray {
        if (s == SwipeSoundStyle.NONE) return FloatArray(0)
        val st = if (s == SwipeSoundStyle.CUSTOM) SwipeSoundStyle.PENCIL else s
        return swipeLoop(st, swipeSeed(st), swipePeak(st), layer = false)
    }

    /** Lớp phát thêm × âm lượng² (dày lên khi vuốt nhanh) — chỉ Đũa phép; kiểu khác rỗng. Cùng độ dài vòng chính. */
    fun swipeLayerSamples(s: SwipeSoundStyle): FloatArray =
        if (s != SwipeSoundStyle.WAND) FloatArray(0) else swipeLoop(s, 0x776E6432, SWIPE_LAYER_PEAK, layer = true)

    private fun swipeLoop(s: SwipeSoundStyle, seed: Int, target: Double, layer: Boolean): FloatArray {
        val sr = SWIPE_SAMPLE_RATE.toDouble()
        val loopSec = swipeLoopSeconds(s)
        val len = (loopSec * sr).roundToInt()
        val f = (SWIPE_CROSSFADE * sr).roundToInt()
        val p = (SWIPE_PREROLL * sr).roundToInt()
        val y = swipeRaw(s, p + len + f, sr, loopSec, seed, layer)
        val out = DoubleArray(len)
        var peak = 0.0
        for (i in 0 until len) {
            val z = y[p + i]
            val v = if (i < f) {
                val w = i.toDouble() / f
                z * sin(PI / 2 * w) + y[p + len + i] * cos(PI / 2 * w)
            } else z
            out[i] = v
            peak = maxOf(peak, abs(v))
        }
        val norm = if (peak > 0) target / peak else 0.0
        return FloatArray(len) { (out[it] * norm).toFloat() }
    }

    /** Hạt chuông của Đũa phép: 6 giọng xoay vòng, hạt cách [gapMin] + [gapRange]·u giây; [bed] > 0 ⇒ thêm nền gió. */
    private fun swipeChimes(n: Int, sr: Double, u: () -> Double, gapMin: Double, gapRange: Double, bed: Double): DoubleArray {
        val notes = doubleArrayOf(1568.0, 1760.0, 2093.0, 2349.0, 2637.0, 3136.0)
        fun pole(f: Double) = exp(-2 * PI * f / sr)
        val ph = DoubleArray(6); val fr = DoubleArray(6); val amp = DoubleArray(6); val dec = DoubleArray(6)
        var voice = 0; var next = 0
        val h = pole(3000.0); val a = pole(7000.0)
        var hi = 0.0; var ho = 0.0; var l1 = 0.0; var l2 = 0.0
        val out = DoubleArray(n)
        for (i in 0 until n) {
            next -= 1
            if (next <= 0) {
                val k = minOf(5, (u() * 6).toInt())
                fr[voice] = notes[k] * (1 + 0.004 * (u() - 0.5))
                amp[voice] = 0.4 + 0.6 * u()
                dec[voice] = exp(-1 / ((0.06 + 0.06 * u()) * sr))
                ph[voice] = 0.0
                voice = (voice + 1) % 6
                next = ((gapMin + gapRange * u()) * sr).toInt()
            }
            var v = 0.0
            for (j in 0 until 6) {
                if (amp[j] <= 1e-4) continue
                ph[j] += 2 * PI * fr[j] / sr
                v += amp[j] * (sin(ph[j]) + 0.15 * sin(2.76 * ph[j]))
                amp[j] *= dec[j]
            }
            if (bed > 0) {
                val x = 2 * u() - 1
                ho = h * (ho + x - hi); hi = x
                l1 = (1 - a) * ho + a * l1; l2 = (1 - a) * l1 + a * l2
                v += bed * l2
            }
            out[i] = v
        }
        return out
    }

    /** Dòng nhiễu đã lọc của kiểu (chưa nối vòng, chưa chuẩn hoá). */
    private fun swipeRaw(s: SwipeSoundStyle, n: Int, sr: Double, loopSec: Double, seed: Int, layer: Boolean): DoubleArray {
        var state = seed
        fun u(): Double {
            state = state xor (state shl 13); state = state xor (state ushr 17); state = state xor (state shl 5)
            return (state.toLong() and 0xFFFFFFFFL).toDouble() / 4294967295.0
        }
        fun pole(f: Double) = exp(-2 * PI * f / sr)
        var out = DoubleArray(n)
        when (s) {
            SwipeSoundStyle.NONE, SwipeSoundStyle.CUSTOM -> Unit
            SwipeSoundStyle.PENCIL -> {
                val h = pole(2000.0); val a = pole(5500.0)
                val gK = 1 - exp(-1 / (0.0015 * sr)); val cD = exp(-1 / (0.0007 * sr))
                var hi1 = 0.0; var ho1 = 0.0; var hi2 = 0.0; var ho2 = 0.0; var l1 = 0.0; var l2 = 0.0
                var grain = 0.6; var gt = 0.6; var left = 0; var crack = 0.0
                for (i in 0 until n) {
                    val t = i / sr
                    val x = 2 * u() - 1
                    if (left <= 0) { gt = 0.35 + 0.65 * u(); left = 40 + (u() * 180).toInt() }
                    left -= 1
                    grain += (gt - grain) * gK
                    if (u() < 0.0009) crack = (if (u() < 0.5) -1.0 else 1.0) * (0.8 + 0.8 * u())
                    val v = x * grain + crack
                    crack *= cD
                    ho1 = h * (ho1 + v - hi1); hi1 = v
                    ho2 = h * (ho2 + ho1 - hi2); hi2 = ho1
                    l1 = (1 - a) * ho2 + a * l1; l2 = (1 - a) * l1 + a * l2
                    out[i] = l2 * (0.85 + 0.15 * sin(2 * PI * 3 / loopSec * t))
                }
            }
            SwipeSoundStyle.BRUSH -> {
                val hb = pole(300.0); val ab = pole(700.0); val ha = pole(900.0); val aa = pole(1600.0)
                var bi = 0.0; var bo = 0.0; var b1 = 0.0; var b2 = 0.0; var ai = 0.0; var ao = 0.0; var a1 = 0.0; var a2 = 0.0
                for (i in 0 until n) {
                    val t = i / sr
                    val x = 2 * u() - 1
                    bo = hb * (bo + x - bi); bi = x
                    b1 = (1 - ab) * bo + ab * b1; b2 = (1 - ab) * b1 + ab * b2
                    ao = ha * (ao + x - ai); ai = x
                    a1 = (1 - aa) * ao + aa * a1; a2 = (1 - aa) * a1 + aa * a2
                    out[i] = (b2 + 0.30 * a2) * (0.8 + 0.2 * sin(2 * PI * 4 / loopSec * t))
                }
            }
            SwipeSoundStyle.CHALK -> {
                val h = pole(900.0); val a = pole(3500.0); val gK = 1 - exp(-1 / (0.001 * sr))
                var hi1 = 0.0; var ho1 = 0.0; var hi2 = 0.0; var ho2 = 0.0; var l1 = 0.0; var l2 = 0.0
                var grain = 0.5; var gt = 0.5; var left = 0
                var next = (0.15 * sr).toInt(); var sqLen = 0; var sqPos = 0; var sqF = 0.0; var ph = 0.0
                for (i in 0 until n) {
                    val x = 2 * u() - 1
                    if (left <= 0) { val g = u(); gt = 0.15 + 0.85 * g * g; left = 30 + (u() * 400).toInt() }
                    left -= 1
                    grain += (gt - grain) * gK
                    val v0 = x * grain
                    ho1 = h * (ho1 + v0 - hi1); hi1 = v0
                    ho2 = h * (ho2 + ho1 - hi2); hi2 = ho1
                    l1 = (1 - a) * ho2 + a * l1; l2 = (1 - a) * l1 + a * l2
                    var v = l2
                    next -= 1
                    if (next <= 0) {
                        sqLen = ((0.03 + 0.04 * u()) * sr).toInt(); sqPos = 0; sqF = 1600 + 800 * u()
                        next = ((0.25 + 0.3 * u()) * sr).toInt()
                    }
                    if (sqPos < sqLen) {
                        val tb = sqPos / sr
                        ph += 2 * PI * sqF * (1 + 0.03 * sin(2 * PI * 9 * tb)) / sr
                        val st = 0.5 + 0.5 * cos(2 * PI * 45 * tb)
                        v += 0.4 * sin(ph) * st * st * sin(PI * sqPos / sqLen)
                        sqPos += 1
                    }
                    out[i] = v
                }
            }
            SwipeSoundStyle.MARKER -> {
                val hn = pole(600.0); val an = pole(2600.0); val r = 0.996
                var ni = 0.0; var no = 0.0; var n1 = 0.0; var n2 = 0.0; var y1 = 0.0; var y2 = 0.0
                for (i in 0 until n) {
                    val t = i / sr
                    val x = 2 * u() - 1
                    no = hn * (no + x - ni); ni = x
                    n1 = (1 - an) * no + an * n1; n2 = (1 - an) * n1 + an * n2
                    val fr = 1250 + 70 * sin(2 * PI / loopSec * t)
                    val y = (1 - r) * x + 2 * r * cos(2 * PI * fr / sr) * y1 - r * r * y2
                    y2 = y1; y1 = y
                    out[i] = (0.7 * n2 + 8 * y) * (0.9 + 0.1 * sin(2 * PI * 3 / loopSec * t))
                }
            }
            SwipeSoundStyle.WHIP -> {
                val h = pole(1500.0); val a = pole(6500.0)
                var hi1 = 0.0; var ho1 = 0.0; var hi2 = 0.0; var ho2 = 0.0; var l1 = 0.0; var l2 = 0.0
                for (i in 0 until n) {
                    val t = i / sr
                    val x = 2 * u() - 1
                    ho1 = h * (ho1 + x - hi1); hi1 = x
                    ho2 = h * (ho2 + ho1 - hi2); hi2 = ho1
                    l1 = (1 - a) * ho2 + a * l1; l2 = (1 - a) * l1 + a * l2
                    out[i] = l2 * (0.7 + 0.3 * sin(2 * PI * 2 / loopSec * t)) * (0.9 + 0.1 * sin(2 * PI * 7 / loopSec * t))
                }
            }
            SwipeSoundStyle.LIGHTNING -> {
                val h = pole(1500.0); val a = pole(5000.0); val cD = exp(-1 / (0.0004 * sr))
                var hi = 0.0; var ho = 0.0; var l1 = 0.0; var l2 = 0.0
                var next = (0.05 * sr).toInt(); var bLeft = 0; var imp = 0.0
                for (i in 0 until n) {
                    val t = i / sr
                    val x = 2 * u() - 1
                    next -= 1
                    if (next <= 0) {
                        bLeft = ((0.008 + 0.032 * u()) * sr).toInt()
                        next = bLeft + ((0.03 + 0.15 * u()) * sr).toInt()
                    }
                    var c = 0.0
                    if (bLeft > 0) {
                        bLeft -= 1
                        if (u() < 0.08) imp = (if (u() < 0.5) -1.0 else 1.0) * (0.5 + 0.5 * u())
                        c = 0.3 * x
                    }
                    val v = c + imp
                    imp *= cD
                    ho = h * (ho + v - hi); hi = v
                    l1 = (1 - a) * ho + a * l1; l2 = (1 - a) * l1 + a * l2
                    val hum = sin(2 * PI * 100 * t) + 0.6 * sin(2 * PI * 200 * t) + 0.4 * sin(2 * PI * 300 * t) +
                        0.25 * sin(2 * PI * 400 * t)
                    out[i] = l2 + 0.1 * hum
                }
            }
            SwipeSoundStyle.PLASMA -> {
                val hn = pole(400.0); val an = pole(1200.0)
                var ni = 0.0; var no = 0.0; var n1 = 0.0; var n2 = 0.0; var ph = 0.0
                for (i in 0 until n) {
                    val t = i / sr
                    val x = 2 * u() - 1
                    no = hn * (no + x - ni); ni = x
                    n1 = (1 - an) * no + an * n1; n2 = (1 - an) * n1 + an * n2
                    val wob = 0.75 + 0.25 * sin(2 * PI * 3 / loopSec * t)
                    ph += 2 * PI * (160 + 6 * sin(2 * PI / loopSec * t)) / sr
                    val tone = sin(ph) + 0.5 * sin(2 * ph + 0.4 * sin(2 * PI * 5 / loopSec * t)) + 0.25 * sin(3 * ph)
                    out[i] = (0.5 * tone + 2.0 * n2) * wob
                }
            }
            SwipeSoundStyle.WAND -> {
                out = if (layer) swipeChimes(n, sr, ::u, 0.015, 0.045, 0.0) else swipeChimes(n, sr, ::u, 0.04, 0.12, 0.25)
            }
        }
        return out
    }

    /** Tiếng ngắn lúc nhấc tay (22,05 kHz mono, đã chuẩn hoá đỉnh); kiểu không có ⇒ rỗng. Tất định — checksum chung iOS. */
    fun swipeLiftSamples(s: SwipeSoundStyle): FloatArray {
        val (dur, target, seed) = when (s) {
            SwipeSoundStyle.WHIP -> Triple(0.16, 0.55, 0x7763726B)
            SwipeSoundStyle.LIGHTNING -> Triple(0.22, 0.50, 0x6C747A70)
            SwipeSoundStyle.PLASMA -> Triple(0.18, 0.40, 0x706C7A77)
            SwipeSoundStyle.WAND -> Triple(0.34, 0.40, 0x77676C73)
            else -> return FloatArray(0)
        }
        val sr = SWIPE_SAMPLE_RATE.toDouble()
        var state = seed
        fun u(): Double {
            state = state xor (state shl 13); state = state xor (state ushr 17); state = state xor (state shl 5)
            return (state.toLong() and 0xFFFFFFFFL).toDouble() / 4294967295.0
        }
        fun pole(f: Double) = exp(-2 * PI * f / sr)
        val n = (dur * sr).roundToInt()
        val out = DoubleArray(n)
        when (s) {
            SwipeSoundStyle.WHIP -> {
                val h = pole(1200.0); val a = pole(7000.0)
                var hi = 0.0; var ho = 0.0; var l1 = 0.0; var l2 = 0.0
                for (i in 0 until n) {
                    val t = i / sr
                    val x = 2 * u() - 1
                    val env = (if (t < 0.0006) t / 0.0006 else 1.0) * (0.9 * exp(-t / 0.003) + 0.35 * exp(-t / 0.035))
                    val v = x * env
                    ho = h * (ho + v - hi); hi = v
                    l1 = (1 - a) * ho + a * l1; l2 = (1 - a) * l1 + a * l2
                    out[i] = l2 + 0.25 * exp(-t / 0.0015) * sin(2 * PI * 2600 * t)
                }
            }
            SwipeSoundStyle.LIGHTNING -> {
                val h = pole(1500.0); val a = pole(6000.0); val b = pole(180.0); val cD = exp(-1 / (0.0003 * sr))
                var hi = 0.0; var ho = 0.0; var l1 = 0.0; var l2 = 0.0; var r1 = 0.0; var r2 = 0.0; var imp = 0.0
                for (i in 0 until n) {
                    val t = i / sr
                    val x = 2 * u() - 1
                    val pr = if (t < 0.03) 0.25 else 0.02 * exp(-(t - 0.03) / 0.05)
                    if (u() < pr) imp = (if (u() < 0.5) -1.0 else 1.0) * (0.5 + 0.5 * u())
                    val v = imp + 0.2 * x * exp(-t / 0.04)
                    imp *= cD
                    ho = h * (ho + v - hi); hi = v
                    l1 = (1 - a) * ho + a * l1; l2 = (1 - a) * l1 + a * l2
                    r1 = (1 - b) * x + b * r1; r2 = (1 - b) * r1 + b * r2
                    out[i] = l2 + 12 * r2 * (1 - exp(-t / 0.01)) * exp(-t / 0.07)
                }
            }
            SwipeSoundStyle.PLASMA -> {
                var ph = 0.0
                for (i in 0 until n) {
                    val t = i / sr
                    ph += 2 * PI * (300 * (1400.0 / 300).pow(t / dur)) / sr
                    val e = sin(PI * t / dur)
                    out[i] = e * e * (sin(ph) + 0.3 * sin(2 * ph)) + 0.03 * (2 * u() - 1) * e
                }
            }
            SwipeSoundStyle.WAND -> {
                val notes = doubleArrayOf(2093.0, 2349.0, 2637.0, 3136.0, 3520.0)
                val det = DoubleArray(5) { 1 + 0.003 * (u() - 0.5) }
                for (i in 0 until n) {
                    val t = i / sr
                    var v = 0.0
                    for (k in 0 until 5) {
                        val a0 = t - 0.04 * k
                        if (a0 >= 0) {
                            val ph = 2 * PI * notes[k] * det[k] * a0
                            v += (0.6 + 0.1 * k) * exp(-a0 / 0.08) * (sin(ph) + 0.1 * sin(2.76 * ph))
                        }
                    }
                    out[i] = v
                }
            }
            else -> Unit
        }
        val fo = (0.012 * sr).roundToInt()
        var peak = 0.0
        for (i in 0 until n) {
            val fe = n - 1 - i
            if (fe < fo) out[i] *= 0.5 - 0.5 * cos(PI * fe / fo)
            peak = maxOf(peak, abs(out[i]))
        }
        val norm = if (peak > 0) target / peak else 0.0
        return FloatArray(n) { (out[it] * norm).toFloat() }
    }

    /** Tốc độ (pt/s) của nét vuốt mẫu ở giây [t]: lên nhanh, chậm lại ở 3 "phím", nhấc tay ở [SWIPE_PREVIEW_LIFT]. */
    fun swipeDemoSpeed(t: Double): Double =
        if (t < 0 || t >= SWIPE_PREVIEW_LIFT) 0.0
        else SwipeSoundFx.SPEED_FULL * sin(PI * t / SWIPE_PREVIEW_LIFT) * (0.45 + 0.55 * abs(cos(3 * PI * t / SWIPE_PREVIEW_LIFT)))

    /**
     * Bản nghe thử: vòng lặp × vỏ âm lượng y như lúc vuốt thật (cùng đường cong tốc độ + [SwipeSoundEnvelope]), lớp hạt dày
     * × âm lượng², tiếng nhấc tay ở [SWIPE_PREVIEW_LIFT] với độ to cố định [SwipeSoundFx.PREVIEW_LIFT_GAIN].
     */
    fun swipePreviewSamples(s: SwipeSoundStyle): FloatArray =
        swipePreview(swipeLoopSamples(s), swipeLayerSamples(s), swipeLiftSamples(s))

    /** Bản nghe thử từ vòng lặp cho sẵn ("Âm của bạn": vòng từ file). [loop] rỗng ⇒ rỗng. */
    fun swipePreview(loop: FloatArray, layer: FloatArray = FloatArray(0), shot: FloatArray = FloatArray(0)): FloatArray {
        if (loop.isEmpty()) return loop
        val sr = SWIPE_SAMPLE_RATE.toDouble()
        val lift = (SWIPE_PREVIEW_LIFT * sr).roundToInt()
        val n = maxOf((SWIPE_PREVIEW * sr).roundToInt(), lift + shot.size)
        val lg = SwipeSoundFx.PREVIEW_LIFT_GAIN
        val env = SwipeSoundEnvelope(1 / sr)
        return FloatArray(n) { i ->
            if (i == lift) env.release()
            val g = env.next(SwipeSoundFx.speedGain(swipeDemoSpeed(i / sr)))
            var v = loop[i % loop.size].toDouble() * g
            if (layer.isNotEmpty()) v += layer[i % layer.size].toDouble() * g * g
            if (i >= lift && i - lift < shot.size) v += shot[i - lift].toDouble() * lg
            v.toFloat()
        }
    }

    /**
     * Tiếng Enter RIÊNG của kiểu (null = như phím chức năng). Máy chữ: tiếng phím chức năng + "ding" chuông về dòng
     * (1568 Hz τ80 ms + bồi 2.76× τ20 ms, trễ 12 ms; 280 ms; đỉnh 0.60). Thuộc KIỂU âm (ai chọn Máy chữ cũng nghe),
     * seed cố định (typewriter, modifier). iOS returnRecipe y hệt.
     */
    fun returnRecipe(s: KeySoundStyle): Recipe? {
        if (s != KeySoundStyle.TYPEWRITER) return null
        val r = recipe(KeySoundStyle.TYPEWRITER, Kind.MODIFIER)
        return r.copy(tones = r.tones + listOf(t(0.9, 1568.0, 1568.0, tau = 0.08, delay = 0.012),
            t(0.25, 1568 * 2.76, 1568 * 2.76, tau = 0.02, delay = 0.012)), duration = 0.28, peak = 0.60)
    }

    /** Mẫu Enter riêng của kiểu (null = dùng tiếng phím chức năng). */
    fun returnSamples(s: KeySoundStyle): FloatArray? = returnRecipe(s)?.let { render(it, seed(s, Kind.MODIFIER)) }

    /** Xoá trầm hơn chút; phím chức năng trầm + dài hơn (như iOS). */
    fun recipe(s: KeySoundStyle, k: Kind): Recipe {
        if (s == KeySoundStyle.CLUB) return clubRecipe(k)   // mỗi loại phím một tiếng (hat / kick / kick + hat)
        if (s == KeySoundStyle.AIRY) return airyRecipe(k)   // gió + pad theo loại phím
        if (s == KeySoundStyle.RAIN) return rainRecipe(k, 0)
        val r = baseRecipe(s)
        val (pitch, decay, extra) = when (k) {
            Kind.LETTER -> return r
            Kind.DELETE -> Triple(0.86, 1.0, 0.0)
            Kind.MODIFIER -> Triple(0.74, 1.2, 0.006)
        }
        return r.copy(
            tones = r.tones.map { it.copy(f0 = it.f0 * pitch, fEnd = it.fEnd * pitch, tau = it.tau * decay) },
            noises = r.noises.map { it.copy(lp = it.lp * pitch, tau = it.tau * decay) },
            duration = r.duration + extra)
    }

    fun seed(s: KeySoundStyle, k: Kind): Int =
        // Nhịp club: seed CỐ ĐỊNH ("club"), không theo vị trí — checksum không đổi khi nhánh khác thêm kiểu trước nó.
        if (s == KeySoundStyle.CLUB) 0x636C7562 xor (0x85EBCA6B.toInt() * (k.ordinal + 1))
        // Lơ lửng: seed CỐ ĐỊNH ("airy").
        else if (s == KeySoundStyle.AIRY) 0x61697279 xor (0x85EBCA6B.toInt() * (k.ordinal + 1))
        // Mõ gỗ / Chuông nhỏ: seed cố định ("momo" / "bell") — cùng lý do.
        else if (s == KeySoundStyle.MO) 0x6D6F6D6F xor (0x85EBCA6B.toInt() * (k.ordinal + 1))
        else if (s == KeySoundStyle.BELL) 0x62656C6C xor (0x85EBCA6B.toInt() * (k.ordinal + 1))
        else if (s == KeySoundStyle.RAIN) rainSeed(k, 0)
        // Tạ sắt: seed CỐ ĐỊNH ("plat") — như club.
        else if (s == KeySoundStyle.PLATE) 0x706C6174 xor (0x85EBCA6B.toInt() * (k.ordinal + 1))
        // Chuông sao: seed cố định ("twnk") như Nhịp club.
        else if (s == KeySoundStyle.TWINKLE) 0x74776E6B xor (0x85EBCA6B.toInt() * (k.ordinal + 1))
        // Kiểu theme 11/2026 trở đi: seed CỐ ĐỊNH theo tên (iOS fixedSeeds y hệt).
        else FIXED_SEEDS[s]?.let { it xor (0x85EBCA6B.toInt() * (k.ordinal + 1)) }
            ?: ((0x9E3779B9.toInt() * (s.ordinal + 1)) xor (0x85EBCA6B.toInt() * (k.ordinal + 1)))

    /** Seed cố định theo tên kiểu ("thum"…) — iOS KeySoundSynth.fixedSeeds y hệt. */
    val FIXED_SEEDS: Map<KeySoundStyle, Int> = mapOf(KeySoundStyle.THUMP to 0x7468756D, KeySoundStyle.BLOOP to 0x626C6F6F, KeySoundStyle.CLINK to 0x636C696E)

    fun samples(s: KeySoundStyle, k: Kind): FloatArray = render(recipe(s, k), seed(s, k))

    /** Tương thích: kiểu mặc định. */
    fun samples(k: Kind): FloatArray = samples(KeySoundStyle.DEFAULT, k)

    /** 3 mẫu (chữ / xoá / chức năng) cho kiểu đã lưu. custom vắng/hỏng ⇒ mặc định. */
    fun bank(raw: String?, custom: FloatArray?): Pair<KeySoundStyle, List<FloatArray>> {
        val st = KeySoundStyle.resolve(raw, custom != null)
        return if (st == KeySoundStyle.CUSTOM && custom != null) st to Kind.entries.map { KeySoundCustom.variant(custom, it) }
        else st to Kind.entries.map { samples(st, it) }
    }

    /** Bản nghe thử khi chọn kiểu: chữ → xoá → phím chức năng, cách nhau [gap] giây lặng (giống iOS). */
    fun previewSequence(bank: List<FloatArray>, gap: Double = 0.16): FloatArray {
        val silence = (gap * SAMPLE_RATE).roundToInt()
        val out = FloatArray(bank.sumOf { it.size } + silence * (bank.size - 1).coerceAtLeast(0))
        var o = 0
        bank.forEachIndexed { i, s ->
            if (i > 0) o += silence
            s.copyInto(out, o); o += s.size
        }
        return out
    }

    private fun ramp(t: Double, a: Double): Double = if (a <= 0 || t >= a) 1.0 else 0.5 - 0.5 * cos(PI * t / a)

    fun render(r: Recipe, seed: Int): FloatArray {
        val sr = SAMPLE_RATE.toDouble()
        val count = (r.duration * sr).roundToInt()
        val out = DoubleArray(count)
        for (tn in r.tones) {
            var phase = 0.0
            val start = (tn.delay * sr).roundToInt()
            for (i in start until count) {
                val tt = (i - start) / sr
                val f = tn.fEnd + (tn.f0 - tn.fEnd) * exp(-tt / tn.glide)
                phase += 2 * PI * f / sr
                out[i] += tn.amp * sin(phase) * exp(-tt / tn.tau) * ramp(tt, r.attack)
            }
        }
        r.noises.forEachIndexed { li, nz ->
            var state = seed xor (0x2545F491 * (li + 1))
            if (state == 0) state = 0x12345678
            val hpA = exp(-2 * PI * nz.hp / sr)
            val lpA = exp(-2 * PI * nz.lp / sr)
            var hpIn = 0.0; var hpOut = 0.0; var lp1 = 0.0; var lp2 = 0.0
            val start = (nz.delay * sr).roundToInt()
            for (i in start until count) {
                val tt = (i - start) / sr
                state = state xor (state shl 13); state = state xor (state ushr 17); state = state xor (state shl 5)
                val white = (state.toLong() and 0xFFFFFFFFL).toDouble() / 4294967295.0 * 2 - 1
                val hp = hpA * (hpOut + white - hpIn)
                hpIn = white; hpOut = hp
                lp1 = (1 - lpA) * hp + lpA * lp1
                lp2 = (1 - lpA) * lp1 + lpA * lp2
                out[i] += nz.amp * 2.5 * lp2 * exp(-tt / nz.tau) * ramp(tt, r.attack)
            }
        }
        val oA = exp(-2 * PI * r.outLP / sr)
        val dcA = exp(-2 * PI * 40 / sr)
        var y = 0.0; var dcIn = 0.0; var dcOut = 0.0
        val rel = minOf(count, (0.003 * sr).toInt())
        var peak = 0.0
        for (i in 0 until count) {
            y = (1 - oA) * out[i] + oA * y
            dcOut = dcA * (dcOut + y - dcIn); dcIn = y
            var v = dcOut
            val fromEnd = count - 1 - i
            if (fromEnd < rel) v *= 0.5 - 0.5 * cos(PI * fromEnd / rel)
            out[i] = v
            peak = maxOf(peak, abs(v))
        }
        val norm = if (peak > 0) r.peak / peak else 0.0
        return FloatArray(count) { (out[it] * norm).toFloat() }
    }

    /** 0…100 % → biên độ SoundPool; bình phương cho cảm giác to/nhỏ đều tay. */
    fun gain(percent: Int): Float {
        val x = percent.coerceIn(0, 100) / 100f
        return x * x
    }

    // --- đo đạc (test) ---

    /** Trọng tâm phổ (Hz), trọng số biên độ DFT. Cao ⇒ chói. */
    fun spectralCentroid(x: FloatArray, sr: Double = SAMPLE_RATE.toDouble()): Double {
        val n = x.size
        if (n < 2) return 0.0
        var num = 0.0; var den = 0.0
        for (k in 1..n / 2) {
            var re = 0.0; var im = 0.0
            val w = 2 * PI * k / n
            for (i in 0 until n) { re += x[i] * cos(w * i); im -= x[i] * sin(w * i) }
            val mag = sqrt(re * re + im * im)
            num += mag * k * sr / n; den += mag
        }
        return if (den > 0) num / den else 0.0
    }

    fun rms(x: FloatArray): Double = if (x.isEmpty()) 0.0 else sqrt(x.sumOf { it.toDouble() * it } / x.size)

    // --- WAV PCM 16-bit mono (SoundPool chỉ nạp từ file/fd) ---

    fun wav(k: Kind): ByteArray = wav(samples(k))
    fun wav(style: KeySoundStyle, k: Kind): ByteArray = wav(samples(style, k))

    fun wav(s: FloatArray, sampleRate: Int = SAMPLE_RATE): ByteArray {
        val data = s.size * 2
        val b = java.nio.ByteBuffer.allocate(44 + data).order(java.nio.ByteOrder.LITTLE_ENDIAN)
        b.put("RIFF".toByteArray()).putInt(36 + data).put("WAVE".toByteArray())
        b.put("fmt ".toByteArray()).putInt(16).putShort(1).putShort(1)
            .putInt(sampleRate).putInt(sampleRate * 2).putShort(2).putShort(16)
        b.put("data".toByteArray()).putInt(data)
        for (x in s) b.putShort((x.coerceIn(-1f, 1f) * 32767f).toInt().toShort())
        return b.array()
    }

    /** Đọc WAV PCM 16-bit (mono/stereo → mono). null nếu không phải định dạng đó. */
    fun parseWav(d: ByteArray): Pair<FloatArray, Double>? {
        if (d.size < 44 || String(d, 0, 4) != "RIFF" || String(d, 8, 4) != "WAVE") return null
        fun u16(o: Int) = (d[o].toInt() and 0xFF) or ((d[o + 1].toInt() and 0xFF) shl 8)
        fun u32(o: Int) = u16(o) or (u16(o + 2) shl 16)
        var o = 12
        var channels = 0; var rate = 0; var bits = 0; var tag = 0
        while (o + 8 <= d.size) {
            val id = String(d, o, 4)
            val size = u32(o + 4)
            val body = o + 8
            if (id == "fmt " && body + 16 <= d.size) {
                tag = u16(body); channels = u16(body + 2); rate = u32(body + 4); bits = u16(body + 14)
            } else if (id == "data") {
                if (tag != 1 || bits != 16 || channels < 1 || rate <= 0) return null
                val end = minOf(d.size.toLong(), body.toLong() + (size.toLong() and 0xFFFFFFFFL)).toInt()
                val frames = (end - body) / (2 * channels)
                val out = FloatArray(frames) { f ->
                    var acc = 0.0
                    for (c in 0 until channels) acc += u16(body + (f * channels + c) * 2).toShort().toDouble()
                    (acc / channels / 32768).toFloat()
                }
                return out to rate.toDouble()
            }
            if (size < 0) return null
            o = body + size + (size and 1)
        }
        return null
    }

    enum class Route { SYSTEM, CUSTOM, SILENT }

    /**
     * Đường âm cho một lần bấm. TẮT ⇒ [Route.SYSTEM] (AudioManager.playSoundEffect như cũ —
     * theo "Âm thanh khi chạm" của máy). BẬT ⇒ tiếng riêng, KHÔNG kèm tiếng hệ thống; im khi
     * máy ở chế độ Rung/Im lặng (như Gboard/AOSP LatinIME) hoặc âm lượng 0.
     */
    fun route(enabled: Boolean, volumePercent: Int, ringerNormal: Boolean, style: String? = null): Route = when {
        !enabled -> Route.SYSTEM
        !KeySoundStyle.needsPool(style) -> Route.SYSTEM   // kiểu "Hệ thống": như lúc tắt
        !ringerNormal || volumePercent <= 0 -> Route.SILENT
        else -> Route.CUSTOM
    }
}

/**
 * Âm tự chọn: xử lý thuần sau khi giải mã (Android: MediaCodec; iOS: AVAudioFile) — giống
 * hệt Swift KeySoundCustom. 44.1 kHz mono, bỏ lặng đầu/cuối, cắt ≤ 300 ms, mở/đóng mềm,
 * chuẩn hoá đỉnh 0.8 + trần RMS 0.22.
 */
object KeySoundCustom {
    const val MAX_DURATION = 0.300
    const val TARGET_PEAK = 0.80f
    const val MAX_RMS = 0.22
    /** Trong noBackupFilesDir của app (IME cùng process đọc được) — không vào sao lưu. */
    const val FILE_NAME = "keysound-custom.wav"

    class Failure(val silent: Boolean) : Exception(if (silent) "silent" else "empty")
    data class Result(val samples: FloatArray, val truncated: Boolean)

    fun process(mono: FloatArray, sampleRate: Double): Result {
        if (mono.isEmpty() || sampleRate <= 0) throw Failure(silent = false)
        val sr = KeySoundSynth.SAMPLE_RATE.toDouble()
        val x = resample(mono, sampleRate, sr)
        val peak = x.maxOf { abs(it) }
        if (peak < 0.001f) throw Failure(silent = true)
        val thr = maxOf(peak * 0.05f, 0.001f)
        val first = x.indexOfFirst { abs(it) >= thr }.coerceAtLeast(0)
        val last = x.indexOfLast { abs(it) >= thr }.let { if (it < 0) x.size - 1 else it }
        val start = maxOf(0, first - (0.002 * sr).toInt())
        val endAll = minOf(x.size, last + 1 + (0.010 * sr).toInt())
        val cap = (MAX_DURATION * sr).toInt()
        val truncated = endAll - start > cap
        val end = minOf(endAll, start + cap)
        val y = x.copyOfRange(start, end)
        val fin = minOf(y.size, (0.001 * sr).toInt())
        for (i in 0 until fin) y[i] *= (0.5 - 0.5 * cos(PI * i / fin)).toFloat()
        val fout = minOf(y.size, ((if (truncated) 0.015 else 0.005) * sr).toInt())
        for (j in 0 until fout) { val i = y.size - 1 - j; y[i] *= (0.5 - 0.5 * cos(PI * j / fout)).toFloat() }
        val p2 = y.maxOf { abs(it) }
        if (p2 <= 0f) throw Failure(silent = true)
        var g = TARGET_PEAK / p2
        val r = KeySoundSynth.rms(y) * g
        if (r > MAX_RMS) g *= (MAX_RMS / r).toFloat()
        return Result(FloatArray(y.size) { y[it] * g }, truncated)
    }

    fun resample(x: FloatArray, from: Double, to: Double): FloatArray {
        if (abs(from - to) < 0.5 || x.size < 2) return x
        val n = maxOf(1, (x.size * to / from).roundToInt())
        val step = from / to
        return FloatArray(n) { i ->
            val p = i * step
            val j = p.toInt()
            if (j >= x.size - 1) x[x.size - 1]
            else { val f = (p - j).toFloat(); x[j] * (1 - f) + x[j + 1] * f }
        }
    }

    /** Mẫu cho từng loại phím: chữ nguyên bản, xoá/chức năng nhỏ hơn chút. */
    fun variant(s: FloatArray, k: KeySoundSynth.Kind): FloatArray = when (k) {
        KeySoundSynth.Kind.LETTER -> s
        KeySoundSynth.Kind.DELETE -> FloatArray(s.size) { s[it] * 0.9f }
        KeySoundSynth.Kind.MODIFIER -> FloatArray(s.size) { s[it] * 0.82f }
    }

    /** Đọc file âm tự chọn đã xử lý. null ⇒ vắng/hỏng ⇒ dùng mặc định. */
    fun load(f: java.io.File?): FloatArray? {
        if (f == null || !f.isFile) return null
        val (s, rate) = runCatching { KeySoundSynth.parseWav(f.readBytes()) }.getOrNull() ?: return null
        if (s.isEmpty() || s.size > (MAX_DURATION * KeySoundSynth.SAMPLE_RATE).toInt() + 16) return null
        return resample(s, rate, KeySoundSynth.SAMPLE_RATE.toDouble())
    }

    /** Khoá bộ mẫu: kiểu + (nếu tự chọn) ngày sửa + cỡ file ⇒ app thay file là nạp lại. */
    fun bankKey(style: String, file: java.io.File?): String =
        if (style != KeySoundStyle.CUSTOM.id || file == null || !file.isFile) style
        else "$style@${file.lastModified()}#${file.length()}"
}

/**
 * Giới hạn tần suất nghe/rung thử khi kéo thanh trượt: ≤ 1 lần / [intervalMs] khi kéo, luôn
 * phát lúc thả (trừ khi vừa phát đúng giá trị đó rất gần). Thuần — test được. Giống iOS.
 */
class PreviewThrottle(private val intervalMs: Long = 120) {
    private var lastFire = Long.MIN_VALUE / 2
    private var lastValue: Int? = null

    fun shouldFire(value: Int, nowMs: Long, final: Boolean): Boolean {
        val elapsed = nowMs - lastFire
        val fire = if (final) value != lastValue || elapsed >= intervalMs
                   else elapsed >= intervalMs && value != lastValue
        if (fire) { lastFire = nowMs; lastValue = value }
        return fire
    }
}
