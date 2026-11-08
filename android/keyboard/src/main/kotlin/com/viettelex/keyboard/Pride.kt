package com.viettelex.keyboard

// Theme "Tự hào" (11/2026, Plus) — song sinh iOS Keyboard/Pride.swift (cùng id, bảng màu, sọc cờ, hình học vòng cung /
// cờ / tim, từ khoá; test số chung PrideThemeTests hai bên). CHỈ lưu id cờ (`prideFlag`, prefs + sao lưu).

enum class PrideFlag(val id: String, val viTitle: String, val stripes: IntArray) {
    RAINBOW("rainbow", "Cầu vồng", intArrayOf(0xE40303, 0xFF8C00, 0xFFED00, 0x008026, 0x004DFF, 0x750787)), // l10n-key
    TRANS("trans", "Chuyển giới", intArrayOf(0x5BCEFA, 0xF5A9B8, 0xFFFFFF, 0xF5A9B8, 0x5BCEFA)), // l10n-key
    BI("bi", "Song tính", intArrayOf(0xD60270, 0x9B4F96, 0x0038A8)), // l10n-key
    PAN("pan", "Toàn tính", intArrayOf(0xFF218C, 0xFFD800, 0x21B1FF)), // l10n-key
    LESBIAN("lesbian", "Đồng tính nữ", intArrayOf(0xD52D00, 0xFF9A56, 0xFFFFFF, 0xD362A4, 0xA30262)), // l10n-key
    NONBINARY("nonbinary", "Phi nhị nguyên", intArrayOf(0xFCF434, 0xFFFFFF, 0x9C59D1, 0x2C2C2C)); // l10n-key

    val title: String get() = tr(viTitle)

    /** Bảng màu (nền tối, chữ trắng; nhấn + chữ chức năng theo cờ; viền aurora; tim mờ). Tương phản ≥ 4,5. iOS y hệt. */
    val slots: ThemeSlots get() {
        val (accent, accentInk, fnInk) = when (this) {
            RAINBOW -> Triple(0xFFFF8C00, 0xFF1A0A00, 0xFFFFED00)
            TRANS -> Triple(0xFF5BCEFA, 0xFF06222E, 0xFFF5A9B8)
            BI -> Triple(0xFFD60270, 0xFFFFFFFF, 0xFFF38FC4)
            PAN -> Triple(0xFFFFD800, 0xFF1A1500, 0xFF21B1FF)
            LESBIAN -> Triple(0xFFEF7627, 0xFF1A0A00, 0xFFFF9A56)
            NONBINARY -> Triple(0xFFFCF434, 0xFF1A1800, 0xFFC9A2EE)
        }
        return ThemeSlots(bg = 0xFF0E0E14.toInt(), key = 0xFF1E1E28.toInt(), special = 0xFF2C2C3A.toInt(), ink = 0xFFFFFFFF.toInt(),
            accent = accent.toInt(), accentInk = accentInk.toInt(), fn = 0xFF16161F.toInt(), fnInk = fnInk.toInt(),
            borderFx = ThemeSlots.AURORA, deco = ThemeDeco("hearts", 0x26FFFFFF))
    }

    companion object {
        const val KEY = "prideFlag"
        val DEFAULT = RAINBOW
        val IDS: Set<String> = entries.map { it.id }.toSet()
        fun parse(raw: Any?): PrideFlag = entries.firstOrNull { it.id == raw } ?: DEFAULT
    }
}

/** "Cầu vồng": vòng cung (nửa trên) các sọc cờ lan ra từ phím rồi mờ — iOS RainbowBurst y hệt. Giây / dp. */
object RainbowBurst {
    const val LIFE = 0.8
    const val FADE_IN = 0.08
    const val PEAK_ALPHA = 0.9
    const val OUTER_RADIUS = 46.0
    const val BAND = 3.2
    const val START_SCALE = 0.15
    const val POOL = 3

    fun radius(i: Int): Double = OUTER_RADIUS - (i + 0.5) * BAND
    fun alpha(t: Double): Double = when {
        t < 0 || t >= LIFE -> 0.0
        t < FADE_IN -> PEAK_ALPHA * t / FADE_IN
        else -> PEAK_ALPHA * (1 - (t - FADE_IN) / (LIFE - FADE_IN))
    }
    fun scale(t: Double): Double {
        val f = (t / LIFE).coerceIn(0.0, 1.0)
        return START_SCALE + (1 - START_SCALE) * (1 - (1 - f) * (1 - f))
    }
}

/** Cờ phấp phới + tim tung khi gõ từ khoá — iOS PrideFlagWave y hệt (dp, gốc = giữa mép trên phím). */
object PrideFlagWave {
    const val LIFE = 1.2
    const val WIDTH = 56.0
    const val HEIGHT = 36.0
    const val GAP = 10.0
    const val AMPLITUDE = 3.5
    const val COLUMNS = 8
    const val WAVES = 2.0
    const val RISE = 8.0
    const val POLE_WIDTH = 2.0
    const val FRAMES = 12
    const val HEARTS = 8

    fun phase(t: Double): Double = 2 * Math.PI * WAVES * (t / LIFE).coerceIn(0.0, 1.0)
    fun offset(x: Double, phase: Double): Double = AMPLITUDE * (x / WIDTH) * Math.sin(2 * Math.PI * x / WIDTH - phase)

    /** Đa giác sọc [i]/[n] vào [out] (x0, y0, x1, y1, …): mép trên trái → phải rồi mép dưới phải → trái. Trả số điểm. */
    fun stripe(i: Int, n: Int, phase: Double, out: DoubleArray): Int {
        val x0 = -WIDTH / 2; val top = -GAP - HEIGHT
        val y0 = top + HEIGHT * i / n; val y1 = top + HEIGHT * (i + 1) / n
        var k = 0
        for (c in 0..COLUMNS) {
            val x = WIDTH * c / COLUMNS
            out[2 * k] = x0 + x; out[2 * k + 1] = y0 + offset(x, phase); k++
        }
        for (c in COLUMNS downTo 0) {
            val x = WIDTH * c / COLUMNS
            out[2 * k] = x0 + x; out[2 * k + 1] = y1 + offset(x, phase); k++
        }
        return k
    }
    const val STRIPE_POINTS = 2 * (COLUMNS + 1)

    fun alpha(t: Double): Double = when {
        t < 0 || t >= LIFE -> 0.0
        t < 0.15 -> t / 0.15
        t < 0.85 -> 1.0
        else -> maxOf(0.0, 1 - (t - 0.85) / (LIFE - 0.85))
    }
    fun riseY(t: Double): Double = -RISE * (t / LIFE).coerceIn(0.0, 1.0)

    fun heart(k: Int): KeyEffectTrajectory {
        val t = k - 3.5
        return KeyEffectTrajectory(t * 12, -(40 + (k % 3) * 10.0), 0.5, 1.0, t * 0.15, 1.1, 5.0)
    }
    fun heartDelay(k: Int): Double = k * 0.03
}

/** Từ khoá Tự hào ở RANH GIỚI TỪ (từ vừa chốt + tối đa hai từ trước); tiếng Việt khớp ĐÚNG dấu. iOS PrideKeywords y hệt. */
object PrideKeywords {
    val PHRASES: List<List<String>> = listOf(listOf("love", "is", "love"), listOf("tự", "hào"), listOf("pride"),
        listOf("yêu", "là", "yêu"))
    private fun clean(s: String): String = s.trim { !it.isLetter() }.lowercase()

    fun matches(word: String, prev: String?, prev2: String?): Boolean {
        val w = clean(word)
        if (w.isEmpty()) return false
        val tail = listOf(prev2?.let(::clean) ?: "", prev?.let(::clean) ?: "", w)
        return PHRASES.any { p -> tail.takeLast(p.size) == p }
    }
}
