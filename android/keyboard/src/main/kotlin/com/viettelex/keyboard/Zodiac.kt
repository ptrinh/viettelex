package com.viettelex.keyboard

// Theme "Cung hoàng đạo" (11/2026, Plus) — song sinh iOS Keyboard/Zodiac.swift (cùng id, cùng bảng màu, cùng mốc ngày,
// cùng bảng chòm sao + luật thắp sao; test số chung ZodiacThemeTests hai bên).
//
// Riêng tư: CHỈ lưu id cung (`zodiacSign`, prefs + sao lưu). "Tính từ ngày sinh" nhận ngày / tháng (không năm), tính
// cung rồi bỏ — không lưu ngày.
//
// Mốc ngày (cung hoàng đạo NHIỆT ĐỚI, ngày bắt đầu mỗi cung, gồm cả ngày đó):
//   Bảo Bình 20/1 · Song Ngư 19/2 · Bạch Dương 21/3 · Kim Ngưu 20/4 · Song Tử 21/5 · Cự Giải 21/6 · Sư Tử 23/7 ·
//   Xử Nữ 23/8 · Thiên Bình 23/9 · Bọ Cạp 23/10 · Nhân Mã 22/11 · Ma Kết 22/12 (tới hết 19/1). 29/2 hợp lệ.
//
// "Chòm sao" ([KeyEffect.CONSTELLATION]): MỖI PHÍM thắp thêm MỘT sao của chòm, nối nét mảnh tới các sao đã thắp; đủ sao ⇒
// cả chòm loé rồi mờ; phím kế mở chòm mới quanh phím đó. Nghỉ quá [ConstellationFx.RESET_GAP] ⇒ chòm dở mờ đi.

/** Nguyên tố — quyết định bảng màu (nền trời đêm, chữ sáng). Tương phản ≥ 4,5 (test). */
enum class ZodiacElement(val id: String, val viTitle: String) {
    FIRE("fire", "Hệ Lửa"), // l10n-key
    EARTH("earth", "Hệ Đất"), // l10n-key
    AIR("air", "Hệ Khí"), // l10n-key
    WATER("water", "Hệ Nước"); // l10n-key

    val title: String get() = tr(viTitle)

    val slots: ThemeSlots get() = when (this) {
        FIRE -> ThemeSlots(bg = 0xFF120A1F.toInt(), key = 0xFF2A1530.toInt(), special = 0xFF3D1C38.toInt(), ink = 0xFFFFF4E6.toInt(),
            accent = 0xFFFF7A2F.toInt(), accentInk = 0xFF1A0A00.toInt(), fn = 0xFF1E1028.toInt(), fnInk = 0xFFFFC857.toInt(),
            deco = ThemeDeco("starfield", 0x66FFD9A0))
        EARTH -> ThemeSlots(bg = 0xFF0C1A12.toInt(), key = 0xFF1C2E22.toInt(), special = 0xFF2A3F2E.toInt(), ink = 0xFFF1EBDD.toInt(),
            accent = 0xFF8DBF5A.toInt(), accentInk = 0xFF0C1A12.toInt(), fn = 0xFF14241A.toInt(), fnInk = 0xFFD9B88C.toInt(),
            deco = ThemeDeco("starfield", 0x59E8E0C8))
        AIR -> ThemeSlots(bg = 0xFF0D1030.toInt(), key = 0xFF1F2350.toInt(), special = 0xFF2E3370.toInt(), ink = 0xFFF2F0FF.toInt(),
            accent = 0xFF8EC5FF.toInt(), accentInk = 0xFF0D1030.toInt(), fn = 0xFF161A40.toInt(), fnInk = 0xFFC9B5FF.toInt(),
            deco = ThemeDeco("starfield", 0x66C9D6FF))
        WATER -> ThemeSlots(bg = 0xFF051A2A.toInt(), key = 0xFF0E2E44.toInt(), special = 0xFF164260.toInt(), ink = 0xFFE6FAFF.toInt(),
            accent = 0xFF2BC4C4.toInt(), accentInk = 0xFF04202A.toInt(), fn = 0xFF0A2438.toInt(), fnInk = 0xFF7FE3E0.toInt(),
            deco = ThemeDeco("starfield", 0x5999E6FF))
    }
}

data class ZodiacStar(val x: Double, val y: Double)
data class ZodiacEdge(val a: Int, val b: Int)
data class Constellation(val stars: List<ZodiacStar>, val edges: List<ZodiacEdge>) {
    /** Cạnh "thuộc" sao k (sao có chỉ số lớn hơn) — hiện khi sao k thắp. */
    fun edgesOwnedBy(k: Int): List<ZodiacEdge> = edges.filter { maxOf(it.a, it.b) == k }
}

/** 12 cung (id = giá trị lưu `zodiacSign`, cùng iOS). */
enum class ZodiacSign(val id: String, val viTitle: String) {
    ARIES("aries", "Bạch Dương"), // l10n-key
    TAURUS("taurus", "Kim Ngưu"), // l10n-key
    GEMINI("gemini", "Song Tử"), // l10n-key
    CANCER("cancer", "Cự Giải"), // l10n-key
    LEO("leo", "Sư Tử"), // l10n-key
    VIRGO("virgo", "Xử Nữ"), // l10n-key
    LIBRA("libra", "Thiên Bình"), // l10n-key
    SCORPIO("scorpio", "Bọ Cạp"), // l10n-key
    SAGITTARIUS("sagittarius", "Nhân Mã"), // l10n-key
    CAPRICORN("capricorn", "Ma Kết"), // l10n-key
    AQUARIUS("aquarius", "Bảo Bình"), // l10n-key
    PISCES("pisces", "Song Ngư"); // l10n-key

    val title: String get() = tr(viTitle)

    /** Ký hiệu ♈…♓ + U+FE0E (dạng chữ, không emoji màu). */
    val glyph: String get() = String(Character.toChars(0x2648 + ordinal)) + "︎"

    val element: ZodiacElement get() = when (this) {
        ARIES, LEO, SAGITTARIUS -> ZodiacElement.FIRE
        TAURUS, VIRGO, CAPRICORN -> ZodiacElement.EARTH
        GEMINI, LIBRA, AQUARIUS -> ZodiacElement.AIR
        CANCER, SCORPIO, PISCES -> ZodiacElement.WATER
    }

    val constellation: Constellation get() = TABLE[ordinal]

    companion object {
        const val KEY = "zodiacSign"
        val DEFAULT = ARIES
        val IDS: Set<String> = entries.map { it.id }.toSet()
        /** Lạ / thiếu ⇒ Bạch Dương. */
        fun parse(raw: Any?): ZodiacSign = entries.firstOrNull { it.id == raw } ?: DEFAULT

        /** Ngày bắt đầu (cung, tháng, ngày) theo thứ tự năm dương lịch. */
        val STARTS: List<Triple<ZodiacSign, Int, Int>> = listOf(
            Triple(AQUARIUS, 1, 20), Triple(PISCES, 2, 19), Triple(ARIES, 3, 21), Triple(TAURUS, 4, 20),
            Triple(GEMINI, 5, 21), Triple(CANCER, 6, 21), Triple(LEO, 7, 23), Triple(VIRGO, 8, 23),
            Triple(LIBRA, 9, 23), Triple(SCORPIO, 10, 23), Triple(SAGITTARIUS, 11, 22), Triple(CAPRICORN, 12, 22))
        private val MONTH_DAYS = intArrayOf(31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)

        /** "Tính từ ngày sinh": ngày / tháng (không năm; 29/2 hợp lệ) ⇒ cung; ngày không tồn tại ⇒ null. */
        fun from(day: Int, month: Int): ZodiacSign? {
            if (month !in 1..12 || day !in 1..MONTH_DAYS[month - 1]) return null
            var out = CAPRICORN
            for ((s, m, d) in STARTS) if (month > m || (month == m && day >= d)) out = s
            return out
        }

        private fun c(s: List<Pair<Double, Double>>, e: List<Pair<Int, Int>>) =
            Constellation(s.map { ZodiacStar(it.first, it.second) }, e.map { ZodiacEdge(it.first, it.second) })

        /** Chòm sao giản lược (toạ độ trong hộp đơn vị, y xuống) — iOS y hệt. */
        private val TABLE: List<Constellation> = listOf(
            c(listOf(0.08 to 0.62, 0.42 to 0.38, 0.70 to 0.42, 0.90 to 0.58), listOf(0 to 1, 1 to 2, 2 to 3)),
            c(listOf(0.08 to 0.12, 0.38 to 0.45, 0.52 to 0.60, 0.62 to 0.44, 0.92 to 0.20, 0.30 to 0.85),
                listOf(0 to 1, 1 to 2, 2 to 3, 3 to 4, 2 to 5)),
            c(listOf(0.20 to 0.08, 0.22 to 0.48, 0.16 to 0.92, 0.52 to 0.12, 0.56 to 0.50, 0.64 to 0.92),
                listOf(0 to 1, 1 to 2, 0 to 3, 3 to 4, 4 to 5, 1 to 4)),
            c(listOf(0.52 to 0.08, 0.50 to 0.45, 0.62 to 0.55, 0.18 to 0.90, 0.86 to 0.88),
                listOf(0 to 1, 1 to 2, 1 to 3, 2 to 4)),
            c(listOf(0.36 to 0.08, 0.20 to 0.16, 0.14 to 0.34, 0.26 to 0.46, 0.30 to 0.70, 0.60 to 0.50, 0.92 to 0.62,
                0.66 to 0.78),
                listOf(0 to 1, 1 to 2, 2 to 3, 3 to 4, 3 to 5, 5 to 6, 6 to 7, 4 to 7)),
            c(listOf(0.10 to 0.30, 0.32 to 0.38, 0.50 to 0.30, 0.70 to 0.40, 0.55 to 0.62, 0.80 to 0.90, 0.30 to 0.70),
                listOf(0 to 1, 1 to 2, 2 to 3, 2 to 4, 4 to 5, 1 to 6, 4 to 6)),
            c(listOf(0.50 to 0.10, 0.15 to 0.45, 0.85 to 0.45, 0.30 to 0.90), listOf(0 to 1, 0 to 2, 1 to 2, 1 to 3)),
            c(listOf(0.10 to 0.15, 0.16 to 0.30, 0.10 to 0.45, 0.30 to 0.40, 0.45 to 0.55, 0.55 to 0.72, 0.70 to 0.85,
                0.88 to 0.78, 0.92 to 0.60),
                listOf(0 to 1, 1 to 2, 1 to 3, 3 to 4, 4 to 5, 5 to 6, 6 to 7, 7 to 8)),
            c(listOf(0.20 to 0.35, 0.40 to 0.30, 0.55 to 0.15, 0.70 to 0.30, 0.88 to 0.40, 0.70 to 0.62, 0.40 to 0.68,
                0.15 to 0.75),
                listOf(0 to 1, 1 to 2, 2 to 3, 1 to 3, 3 to 4, 4 to 5, 5 to 6, 1 to 6, 6 to 7, 0 to 7)),
            c(listOf(0.10 to 0.20, 0.30 to 0.55, 0.55 to 0.85, 0.80 to 0.60, 0.92 to 0.25, 0.50 to 0.30),
                listOf(0 to 1, 1 to 2, 2 to 3, 3 to 4, 4 to 5, 0 to 5)),
            c(listOf(0.08 to 0.30, 0.25 to 0.20, 0.40 to 0.35, 0.55 to 0.25, 0.70 to 0.45, 0.60 to 0.70, 0.85 to 0.85),
                listOf(0 to 1, 1 to 2, 2 to 3, 3 to 4, 4 to 5, 5 to 6)),
            c(listOf(0.10 to 0.15, 0.22 to 0.35, 0.35 to 0.58, 0.50 to 0.88, 0.65 to 0.62, 0.80 to 0.45, 0.90 to 0.30,
                0.78 to 0.22),
                listOf(0 to 1, 1 to 2, 2 to 3, 3 to 4, 4 to 5, 5 to 6, 6 to 7, 5 to 7)),
        )
        val MAX_STARS: Int get() = TABLE.maxOf { it.stars.size }
    }
}

/** Hằng số + hàm thuần của hiệu ứng "Chòm sao" — iOS ConstellationFx y hệt. Đơn vị: giây; cỡ: dp. */
object ConstellationFx {
    const val STAR_FADE_IN = 0.18
    const val RESET_GAP = 2.4
    const val FADE_OUT = 0.5
    const val GLOW_TIME = 0.4
    const val GLOW_FADE = 0.6
    const val POOL = 2
    const val WIDTH_FACTOR = 0.6
    const val MAX_WIDTH = 240.0
    const val ASPECT = 0.6
    const val MAX_HEIGHT_FACTOR = 0.7
    const val MARGIN = 6.0
    const val STAR_RADIUS = 3.2
    const val STAR_INNER = 1.1
    const val HALO_RADIUS = 7.0
    const val LINE_WIDTH = 1.0
    const val LINE_ALPHA = 0.65
    const val STAR_COLOR = 0xFFF6D8

    data class Box(val x: Double, val y: Double, val w: Double, val h: Double)

    /** Hộp quanh phím (cx, cy) — luôn trong khung [bx, by, bw, bh]. */
    fun box(cx: Double, cy: Double, bx: Double, by: Double, bw: Double, bh: Double): Box {
        val availW = maxOf(bw - 2 * MARGIN, 1.0); val availH = maxOf(bh - 2 * MARGIN, 1.0)
        var w = minOf(bw * WIDTH_FACTOR, MAX_WIDTH, availW)
        var h = w * ASPECT
        val maxH = minOf(bh * MAX_HEIGHT_FACTOR, availH)
        if (h > maxH) { h = maxH; w = minOf(h / ASPECT, availW) }
        val x = minOf(maxOf(cx - w / 2, bx + MARGIN), bx + bw - MARGIN - w)
        val y = minOf(maxOf(cy - h * 0.75, by + MARGIN), by + bh - MARGIN - h)
        return Box(x, y, w, h)
    }

    fun pointX(s: ZodiacStar, b: Box): Double = b.x + s.x * b.w
    fun pointY(s: ZodiacStar, b: Box): Double = b.y + s.y * b.h

    fun starAlpha(dt: Double): Double = if (dt < 0) 0.0 else minOf(1.0, dt / STAR_FADE_IN)
    fun cycleAlpha(dt: Double, completed: Boolean): Double {
        val hold = if (completed) GLOW_TIME else RESET_GAP
        val fade = if (completed) GLOW_FADE else FADE_OUT
        if (dt < hold) return 1.0
        return maxOf(0.0, 1 - (dt - hold) / fade)
    }
    fun glowAlpha(dt: Double): Double {
        val up = 0.15; val peak = 0.85; val end = GLOW_TIME + GLOW_FADE
        if (dt < 0 || dt >= end) return 0.0
        if (dt < up) return peak * dt / up
        return peak * (1 - (dt - up) / (end - up))
    }
    fun lifetime(completed: Boolean): Double = if (completed) GLOW_TIME + GLOW_FADE else RESET_GAP + FADE_OUT
}

/** Luật thắp sao theo phím (thuần) — iOS ConstellationTrace y hệt. */
class ConstellationTrace(count: Int) {
    data class Step(val star: Int, val newCycle: Boolean, val completes: Boolean)
    val count = maxOf(1, count)
    var lit = 0; private set
    var cycle = 0; private set
    private var last = -Double.MAX_VALUE

    fun press(t: Double): Step {
        val fresh = lit == 0 || lit >= count || t - last > ConstellationFx.RESET_GAP
        if (fresh) { lit = 0; cycle++ }
        val star = lit
        lit++
        last = t
        return Step(star, fresh, lit >= count)
    }
}
