package com.viettelex.keyboard

import java.text.Normalizer
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

// Theme "Bóng đá" (11/2026, Plus): hiệu ứng "Sút!" (id goal) + cụm cổ vũ (pháo sáng đỏ + cờ đỏ sao vàng) + cảnh sân cỏ
// (motif "pitch" — [ThemeScene]). Hàm thuần song sinh iOS/Keyboard/FootballFx.swift — CÙNG SỐ (test chéo hai nền tảng).

/**
 * Cụm cổ vũ của theme Bóng đá. Chuẩn hoá: NFC, chữ thường, bỏ ký tự đầu/cuối không phải chữ/số/#, chữ lặp ≥ 3 lần (cùng
 * chữ gốc, bỏ dấu) gộp còn một ("vàoooo" ⇒ "vào", "gooool" ⇒ "gol"); "việt nam" ⇒ "vn"; "# 1" / "number one" / "số 1"
 * ⇒ "#1"; "vnvd" ⇒ "vnvđ". Chỉ so NGUYÊN token ("vàobờ" ≠ "vào"); từ Việt phải đúng dấu. iOS CheerWords y hệt.
 */
object CheerWords {
    val PHRASES = listOf("việt nam vô địch", "vô địch", "vnvđ", "vn #1", "vào", "goal", "gol")
    /** Số token gần nhất giữ lại (đủ cho "việt nam number one"). */
    const val MAX_TOKENS = 6
    val TABLE: List<List<String>> by lazy { PHRASES.map { canonical(tokens(it)) } }

    fun tokens(text: String): List<String> = text.split(' ').filter { it.isNotEmpty() }.map { token(it) }.filter { it.isNotEmpty() }

    /** Chữ gốc (bỏ dấu, giữ đ): ký tự đầu của dạng tách NFD. */
    fun base(c: Char): Char = Normalizer.normalize(c.toString(), Normalizer.Form.NFD).firstOrNull() ?: c

    private fun keep(c: Char): Boolean = c.isLetter() || c.isDigit() || c == '#'

    /** Một từ ⇒ token chuẩn hoá (rỗng = bỏ qua). */
    fun token(word: String): String {
        val s = Normalizer.normalize(word, Normalizer.Form.NFC).lowercase()
        var a = 0; var b = s.length
        while (a < b && !keep(s[a])) a++
        while (b > a && !keep(s[b - 1])) b--
        return collapse(s.substring(a, b))
    }

    /** Gộp chuỗi ≥ 3 ký tự cùng chữ gốc: cùng một ký tự ⇒ ký tự đó; lẫn dấu ⇒ chữ gốc không dấu. */
    fun collapse(cs: String): String {
        val out = StringBuilder()
        var i = 0
        while (i < cs.length) {
            val b = base(cs[i])
            var j = i + 1
            while (j < cs.length && base(cs[j]) == b) j++
            if (j - i >= 3) {
                var same = true
                for (k in i until j) if (cs[k] != cs[i]) same = false
                out.append(if (same) cs[i] else b)
            } else out.append(cs, i, j)
            i = j
        }
        return out.toString()
    }

    val NUMBER_WORDS = setOf("#", "number", "số")
    val ONE_WORDS = setOf("1", "one", "một")

    /** Gộp cụm nhiều token thành dạng chuẩn ("việt nam" ⇒ "vn", "số 1" ⇒ "#1", "vnvd" ⇒ "vnvđ"). */
    fun canonical(t: List<String>): List<String> {
        val out = ArrayList<String>(t.size)
        var i = 0
        while (i < t.size) {
            val a = t[i]
            val b = if (i + 1 < t.size) t[i + 1] else null
            if (a == "việt" && b == "nam") { out.add("vn"); i += 2; continue }
            if (a in NUMBER_WORDS && b != null && b in ONE_WORDS) { out.add("#1"); i += 2; continue }
            out.add(if (a == "vnvd") "vnvđ" else a)
            i++
        }
        return out
    }

    /** Dãy token (cũ → mới) có KẾT THÚC bằng một cụm trong bảng không. */
    fun matches(t: List<String>): Boolean {
        val c = canonical(t)
        return TABLE.any { p -> p.size <= c.size && c.subList(c.size - p.size, c.size) == p }
    }

    /**
     * Bộ so khớp chạy theo phím: IME đưa từ vừa chốt + ký hiệu vừa gõ; "#" và chữ số dồn thành một token ("#1").
     * Chỉ so ở ranh giới (cách / Enter / dấu câu); khớp ⇒ xoá bộ nhớ (một cụm bắn một lần). iOS CheerWords.Matcher y hệt.
     */
    class Matcher {
        private val buf = ArrayList<String>(MAX_TOKENS + 1)
        private var glue = ""
        val tokens: List<String> get() = buf

        private fun push(t: String) {
            if (t.isEmpty()) return
            buf.add(t)
            while (buf.size > MAX_TOKENS) buf.removeAt(0)
        }
        private fun closeGlue() { if (glue.isNotEmpty()) { push(glue); glue = "" } }

        /** [word]: từ vừa chốt (rỗng = không có); [symbol]: ký hiệu / chữ số vừa gõ; [end]: ranh giới. True = vừa xong cụm. */
        fun feed(word: String, symbol: String? = null, end: Boolean = false): Boolean {
            if (word.isNotEmpty()) { closeGlue(); push(token(word)) }
            if (symbol != null) {
                if (isGlue(symbol)) { glue += symbol; if (glue.length > 8) glue = glue.takeLast(8); return false }
                closeGlue()
                return evaluate()
            }
            if (!end) return false
            closeGlue()
            return evaluate()
        }

        private fun evaluate(): Boolean {
            if (buf.isEmpty() || !matches(buf)) return false
            buf.clear()
            return true
        }

        fun reset() { buf.clear(); glue = "" }

        companion object {
            fun isGlue(s: String): Boolean = s.isNotEmpty() && s.all { it == '#' || it in '0'..'9' }
        }
    }
}

/** Cú sút: khung thành nhỏ canh giữa mép trên, bóng bay cung Bézier bậc 2 từ tâm phím Enter vào giữa lưới (dp). */
object GoalFx {
    const val NET_WIDTH = 56.0; const val NET_HEIGHT = 24.0; const val NET_TOP = 4.0; const val MESH = 6.0; const val POST_WIDTH = 2.0
    const val BALL_RADIUS = 7.0
    const val FLIGHT = 0.6; const val HOLD = 0.35; const val FADE = 0.4
    const val LIFE = FLIGHT + HOLD + FADE + 0.15
    const val LIFT = 34.0; const val LIFT_PER_DX = 0.3
    const val POOL = 2
    const val TEXT = "VÀOOO!"
    const val TEXT_SIZE = 16.0; const val TEXT_GAP = 12.0; const val TEXT_WIDTH = 96.0; const val TEXT_HEIGHT = 22.0
    const val BALL_SCALE_END = 0.72
    const val SPIN_TURNS = 2.0

    data class Rect(val x: Double, val y: Double, val w: Double, val h: Double) {
        val midX: Double get() = x + w / 2
        val maxY: Double get() = y + h
    }
    data class Pt(val x: Double, val y: Double)

    fun net(minX: Double, width: Double, top: Double) = Rect(minX + (width - NET_WIDTH) / 2, top + NET_TOP, NET_WIDTH, NET_HEIGHT)
    /** Đích: giữa lưới, hơi thấp. */
    fun target(n: Rect) = Pt(n.midX, n.y + n.h * 0.55)
    /** Điểm điều khiển: giữa hai đầu theo ngang, cao hơn điểm cao hơn; kẹp ≥ top + bán kính bóng + 1. */
    fun control(start: Pt, end: Pt, top: Double): Pt {
        val cy = min(start.y, end.y) - LIFT - LIFT_PER_DX * abs(start.x - end.x)
        return Pt((start.x + end.x) / 2, max(cy, top + BALL_RADIUS + 1))
    }
    fun ball(u: Double, start: Pt, control: Pt, end: Pt): Pt {
        val k = u.coerceIn(0.0, 1.0); val m = 1 - k
        return Pt(m * m * start.x + 2 * m * k * control.x + k * k * end.x, m * m * start.y + 2 * m * k * control.y + k * k * end.y)
    }
    fun ballScale(u: Double) = 1 - (1 - BALL_SCALE_END) * u.coerceIn(0.0, 1.0)
    fun ballSpin(u: Double) = 2 * Math.PI * SPIN_TURNS * u.coerceIn(0.0, 1.0)
    /** Gợn lưới (tỉ lệ phồng) [t] giây sau khi bóng chạm lưới — dao động tắt dần, hết sau 0,6 s. */
    fun netRipple(t: Double): Double {
        if (t <= 0 || t >= 0.6) return 0.0
        return 0.16 * sin(2 * Math.PI * 2.6 * t) * exp(-t / 0.2)
    }
    fun netAlpha(t: Double): Double = when {
        t <= 0 || t >= LIFE -> 0.0
        t < 0.12 -> t / 0.12
        t > LIFE - 0.3 -> (LIFE - t) / 0.3
        else -> 1.0
    }
    fun textScale(t: Double): Double = when {
        t <= 0 -> 0.4
        t < 0.12 -> 0.4 + 0.8 * t / 0.12
        t < 0.22 -> 1.2 - 0.2 * (t - 0.12) / 0.1
        else -> 1.0
    }
    fun textAlpha(t: Double): Double {
        if (t <= 0) return 0.0
        val end = HOLD + FADE + 0.15
        if (t > end - 0.25) return max(0.0, (end - t) / 0.25)
        return 1.0
    }
    fun textCenter(n: Rect) = Pt(n.midX, n.maxY + TEXT_GAP)
    /** Vạch lưới dọc + ngang (toạ độ trong khung lưới) — bước [MESH]. */
    fun meshLines(n: Rect): Pair<List<Double>, List<Double>> {
        val xs = ArrayList<Double>(); val ys = ArrayList<Double>()
        var x = MESH; while (x < n.w - 0.5) { xs.add(x); x += MESH }
        var y = MESH; while (y < n.h - 0.5) { ys.add(y); y += MESH }
        return xs to ys
    }
}

/** Túm cỏ nhú ở mép dưới phím (phím không phải Enter): 3 lá (lệch ngang, cao, nghiêng ngọn) — dp. */
object GrassTuft {
    val BLADES = arrayOf(doubleArrayOf(-4.0, 7.0, -2.0), doubleArrayOf(0.0, 9.0, 0.5), doubleArrayOf(4.0, 6.5, 2.0))
    const val BLADE_WIDTH = 1.6
    const val GROW = 0.12; const val DURATION = 0.32
    const val POOL = 6
    const val INSET = 2.0
    const val COLOR = 0x8BD36A
    fun origin(keyMidX: Double, keyMaxY: Double) = GoalFx.Pt(keyMidX, keyMaxY - INSET)
    fun scaleY(t: Double): Double = if (t <= 0) 0.0 else if (t < GROW) t / GROW else 1.0
    fun alpha(t: Double): Double {
        if (t <= 0 || t >= DURATION) return 0.0
        return if (t < GROW) 0.9 else 0.9 * (DURATION - t) / (DURATION - GROW)
    }
}

/** Cụm cổ vũ: pháo sáng đỏ hai góc dưới + cờ đỏ sao vàng rơi (dp). */
object CheerBurst {
    const val DURATION = 1.2
    const val FLAG_COUNT = 14
    const val FLAG_W = 11.0; const val FLAG_H = 7.5; const val STAR_R = 2.6
    /** Tỉ lệ bán kính trong của sao 5 cánh (ngôi sao cờ: r trong ≈ 0,382 r ngoài). */
    const val STAR_INNER = 0.382

    /** Sao vàng 5 cánh (10 đỉnh xen ngoài / trong, đỉnh đầu chĩa lên) quanh gốc — iOS CheerBurst.star y hệt. */
    fun star(r: Double = STAR_R): List<Pair<Double, Double>> = (0 until 10).map { k ->
        val a = k * Math.PI / 5 - Math.PI / 2
        val rr = if (k % 2 == 0) r else r * STAR_INNER
        Pair(rr * Math.cos(a), rr * Math.sin(a))
    }
    const val RED = 0xDA251D; const val YELLOW = 0xFFFF00
    const val FLARE_RED = 0xFF3B30
    const val FLARE_RADIUS = 5.0
    const val SPARKS_PER_FLARE = 5
    const val SPARK_DURATION = 0.8
    const val MARGIN = 8.0

    data class Flag(val x0: Double, val y0: Double, val dx: Double, val dy: Double, val rot: Double, val delay: Double, val dur: Double)

    /** Cờ rơi: trải đều bề ngang (lệch nhẹ), xuất phát gần mép trên, rơi tối đa tới cách đáy [MARGIN]. Thứ tự rút số = iOS. */
    fun flags(minX: Double, top: Double, width: Double, height: Double): List<Flag> = (0 until FLAG_COUNT).map { i ->
        var st = fxSeed(i * 131 + 7)
        fun next(): Double { st = fxStep(st); return fxValue(st) }
        val slot = (i + 0.5) / FLAG_COUNT
        val x0 = minX + MARGIN + (width - 2 * MARGIN) * slot + (next() - 0.5) * 6
        val y0 = top + 6 + 10 * next()
        val fall = (height - 20) * (0.45 + 0.4 * next())
        val dy = max(0.0, min(fall, top + height - MARGIN - y0))
        val dx = (next() - 0.5) * 24
        val rot = (next() - 0.5) * 6
        val delay = 0.25 * next()
        Flag(x0, y0, dx, dy, rot, delay, DURATION - delay)
    }
    fun flares(minX: Double, top: Double, width: Double, height: Double): List<GoalFx.Pt> {
        val y = top + height - 10
        return listOf(GoalFx.Pt(minX + width * 0.1, y), GoalFx.Pt(minX + width * 0.9, y))
    }
    /** Độ sáng pháo: mở 0,1 s, bập bùng NHẸ (0,75…1, 3 Hz — không chớp), tắt 0,3 s cuối. */
    fun flareAlpha(t: Double): Double = when {
        t <= 0 || t >= DURATION -> 0.0
        t < 0.1 -> t / 0.1
        t > DURATION - 0.3 -> (DURATION - t) / 0.3 * 0.875
        else -> 0.875 + 0.125 * sin(2 * Math.PI * 3 * t)
    }
    /** Tia lửa thứ [k] của pháo: (dx, dy, trễ). */
    fun spark(k: Int): DoubleArray = doubleArrayOf((k - 2) * 7.0, -(26 + 6.0 * (k % 3)), k * 0.07)
}

/**
 * Sân cỏ: sọc cắt cỏ dọc (sọc lẻ sáng hơn) + vạch vôi mờ: đường biên, vạch giữa, vòng tròn giữa + chấm, vòng cấm + khu cầu
 * môn hai bên. Toạ độ trong khung w×h (gốc trên-trái, dp). iOS PitchScene y hệt.
 */
object PitchScene {
    const val INSET = 5.0; const val LINE_WIDTH = 1.2; const val SPOT = 1.6
    const val STRIPE_ALPHA = 0.07
    fun stripeWidth(w: Double) = max(28.0, w / 10)
    /** Sọc sáng [x, bề rộng] — sọc lẻ. */
    fun stripes(w: Double, h: Double): List<DoubleArray> {
        val sw = stripeWidth(w)
        val out = ArrayList<DoubleArray>()
        var x = sw
        while (x < w) { out.add(doubleArrayOf(x, min(sw, w - x))); x += 2 * sw }
        return out
    }
    sealed class Prim {
        data class Rect(val x: Double, val y: Double, val w: Double, val h: Double) : Prim()
        data class Circle(val cx: Double, val cy: Double, val r: Double) : Prim()
        data class Line(val x0: Double, val y0: Double, val x1: Double, val y1: Double) : Prim()
    }
    fun lines(w: Double, h: Double): List<Prim> {
        if (w <= 4 * INSET || h <= 4 * INSET) return emptyList()
        val r = min(h * 0.22, 40.0)
        val bw = w * 0.12; val bh = h * 0.5; val gw = w * 0.05; val gh = h * 0.26
        return listOf(
            Prim.Rect(INSET, INSET, w - 2 * INSET, h - 2 * INSET),
            Prim.Line(w / 2, INSET, w / 2, h - INSET),
            Prim.Circle(w / 2, h / 2, r),
            Prim.Rect(INSET, (h - bh) / 2, bw, bh),
            Prim.Rect(w - INSET - bw, (h - bh) / 2, bw, bh),
            Prim.Rect(INSET, (h - gh) / 2, gw, gh),
            Prim.Rect(w - INSET - gw, (h - gh) / 2, gw, gh),
        )
    }
}
