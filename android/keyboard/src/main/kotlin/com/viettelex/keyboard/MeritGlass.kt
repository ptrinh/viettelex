package com.viettelex.keyboard

import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.tan

/*
 * Theme "Gõ mõ" + "Kính màu" (11/2026, Plus): Công đức ([MeritFx], [MeritCounter]), Nắng qua kính ([SunlightFx],
 * [CandleFlicker]), dáng phím ô kính ("keyShape":"glass" — [GlassKeys]). Hàm THUẦN song sinh iOS/Keyboard/MeritGlass.swift
 * (CÙNG SỐ — test chéo hai bên). Vẽ: app/.../ime/MeritSunlightFx.kt (overlay) + KeyboardView (ô kính).
 *
 * Tôn trọng người có đạo: KHÔNG hình tượng Phật / Chúa / Đức Mẹ / thánh / thần linh, không kinh văn — chỉ biểu tượng
 * (mõ gỗ, hoa sen, chuông, ô kính màu, tia nắng, ánh nến).
 */

/** "Công đức": "+1 công đức" vàng dịu bay lên từ phím rồi mờ (~0,9 s), tối đa [CAP] nhãn cùng lúc. = iOS MeritFx. */
object MeritFx {
    const val DURATION = 0.9
    const val RISE = 44.0
    const val CAP = 5
    const val FONT_SIZE = 13.0
    const val COLOR = 0xF2C14E
    const val EDGE = 0x3A2200
    const val FADE_IN = 0.12
    const val FADE_OUT_FROM = 0.5
    const val LABEL_WIDTH = 110.0
    const val LABEL_HEIGHT = 18.0
    const val COUNTER_FONT = 10.0
    const val COUNTER_ALPHA = 0.8

    fun alpha(t: Double): Double {
        if (t < 0 || t >= DURATION) return 0.0
        if (t < FADE_IN) return t / FADE_IN
        if (t < FADE_OUT_FROM) return 1.0
        return 1 - (t - FADE_OUT_FROM) / (DURATION - FADE_OUT_FROM)
    }

    fun lift(t: Double): Double {
        val u = (t / DURATION).coerceIn(0.0, 1.0)
        return RISE * (1 - (1 - u) * (1 - u))
    }

    fun drift(seed: Int): Double = ((((seed % 3) + 3) % 3) - 1) * 6.0

    /** Tâm nhãn lúc xuất phát (dp, toạ độ overlay): mép trên phím, kẹp để cả đường bay nằm trong khung (bx, by, bw, bh). */
    fun origin(keyMidX: Double, keyTop: Double, bx: Double, by: Double, bw: Double, bh: Double): DoubleArray {
        val hw = LABEL_WIDTH / 2 + 8; val hh = LABEL_HEIGHT / 2 + 1
        val x = min(max(keyMidX, bx + hw), max(bx + bw - hw, bx + hw))
        val y = min(max(keyTop, by + RISE + hh), max(by + bh - hh, by + RISE + hh))
        return doubleArrayOf(x, y)
    }

    fun grouped(n: Int, separator: String): String {
        if (n <= 0) return "0"
        val s = n.toString()
        val b = StringBuilder()
        for (i in s.indices) {
            if (i > 0 && (s.length - i) % 3 == 0) b.append(separator)
            b.append(s[i])
        }
        return b.toString()
    }

    fun counterText(n: Int, english: Boolean = L10n.isEnglish): String =
        tr("Công đức hôm nay") + ": " + grouped(n, if (english) "," else ".")

    val floatText: String get() = tr("+1 công đức")
}

/** Bộ đếm công đức trong ngày (giờ địa phương). = iOS MeritCounter. */
class MeritCounter(day: Int = Int.MIN_VALUE, count: Int = 0) {
    var day: Int = day; private set
    var count: Int = max(0, count); private set
    var dirty = false; private set
    private var lastPersist = Double.NEGATIVE_INFINITY

    fun today(d: Int): Int = if (d == day) count else 0

    fun press(d: Int, t: Double): Boolean {
        if (d != day) { day = d; count = 0 }
        count++
        dirty = true
        if (t - lastPersist < PERSIST_INTERVAL) return false
        lastPersist = t
        dirty = false
        return true
    }

    fun takeDirty(): Boolean { val d = dirty; dirty = false; return d }

    companion object {
        const val PERSIST_INTERVAL = 5.0
        /** Khoá prefs ime_state (iOS App Group cùng tên). Chỉ hai số, không sao lưu. */
        const val DAY_KEY = "meritDay"
        const val COUNT_KEY = "meritCount"
        fun dayIndex(epoch: Double, utcOffset: Int): Int = floor((epoch + utcOffset) / 86_400.0).toInt()
    }
}

/** "Nắng qua kính" — ô sáng lên + tia nắng chéo; gõ dồn ⇒ ánh nến mép dưới. = iOS SunlightFx. */
object SunlightFx {
    const val DURATION = 0.7
    const val RISE = 0.08
    const val PEAK = 0.38
    const val NEIGHBOR = 0.16
    const val PITCH_X = 1.12
    const val PITCH_Y = 1.25
    const val LIGHT = 0xFFF1C9
    const val CORNER_FACTOR = 0.18
    const val BEAM_ANGLE = 0.35
    val BEAM_OFFSETS = doubleArrayOf(-0.3, 0.05, 0.35)
    val BEAM_HALF = doubleArrayOf(0.12, 0.18, 0.10)
    const val BEAM_SPREAD = 2.2
    val BEAM_WEIGHTS = doubleArrayOf(0.8, 1.0, 0.6)
    const val BEAM_PEAK = 0.2
    val BEAMS: Int get() = BEAM_OFFSETS.size
    const val POOL = 4

    const val CANDLE_LEVEL = 2
    const val CANDLE_MIN_INTERVAL = 0.34
    val CANDLE_LEVELS = doubleArrayOf(0.34, 0.24, 0.40, 0.28)
    const val CANDLE_RAMP = 0.3
    const val CANDLE_HOLD = 1.0
    const val CANDLE_FADE = 0.5
    const val CANDLE_BAND = 22.0
    const val CANDLE_COLOR = 0xFFB347

    data class Pane(val x: Double, val y: Double, val w: Double, val h: Double, val level: Double)

    fun envelope(dt: Double): Double {
        if (dt < 0 || dt >= DURATION) return 0.0
        if (dt < RISE) return dt / RISE
        val u = (dt - RISE) / (DURATION - RISE)
        return (1 - u) * (1 - u)
    }

    fun panes(cx: Double, cy: Double, w: Double, h: Double): List<Pane> = listOf(
        Pane(cx, cy, w, h, PEAK),
        Pane(cx - w * PITCH_X, cy, w, h, NEIGHBOR), Pane(cx + w * PITCH_X, cy, w, h, NEIGHBOR),
        Pane(cx, cy - h * PITCH_Y, w, h, NEIGHBOR), Pane(cx, cy + h * PITCH_Y, w, h, NEIGHBOR))

    /** Tia [i]: [x0,y0, x1,y1, x2,y2, x3,y3] — ghi vào [out] (≥ 8) để không cấp phát. */
    fun beam(i: Int, cx: Double, keyTop: Double, w: Double, top: Double, out: DoubleArray = DoubleArray(8)): DoubleArray {
        val xk = cx + BEAM_OFFSETS[i] * w; val hk = BEAM_HALF[i] * w; val ht = hk * BEAM_SPREAD
        val xt = xk - tan(BEAM_ANGLE) * max(keyTop - top, 0.0)
        out[0] = xt - ht; out[1] = top; out[2] = xt + ht; out[3] = top
        out[4] = xk + hk; out[5] = keyTop; out[6] = xk - hk; out[7] = keyTop
        return out
    }
}

/** Ánh nến bập bùng chậm (≤ 3 lần đổi độ sáng / giây, đổi mượt). = iOS CandleFlicker. */
class CandleFlicker {
    var last = Double.NEGATIVE_INFINITY; private set
    var from = 0.0; private set
    var target = 0.0; private set
    var changes = 0; private set

    fun value(t: Double): Double = if (last == Double.NEGATIVE_INFINITY) 0.0 else envelope(t - last, from, target)

    /** Một phím lúc [t] (giây) ở mức combo [level]: được đổi ⇒ độ sáng đích mới; không ⇒ null. */
    fun press(t: Double, level: Int): Double? {
        if (level < SunlightFx.CANDLE_LEVEL || t - last < SunlightFx.CANDLE_MIN_INTERVAL) return null
        from = value(t)
        target = SunlightFx.CANDLE_LEVELS[changes % SunlightFx.CANDLE_LEVELS.size]
        last = t
        changes++
        return target
    }

    fun reset() { last = Double.NEGATIVE_INFINITY; from = 0.0; target = 0.0; changes = 0 }

    companion object {
        fun envelope(dt: Double, from: Double, to: Double): Double {
            if (dt < 0) return from
            if (dt < SunlightFx.CANDLE_RAMP) {
                val u = dt / SunlightFx.CANDLE_RAMP
                return from + (to - from) * u * u * (3 - 2 * u)
            }
            if (dt < SunlightFx.CANDLE_HOLD) return to
            if (dt < SunlightFx.CANDLE_HOLD + SunlightFx.CANDLE_FADE)
                return to * (1 - (dt - SunlightFx.CANDLE_HOLD) / SunlightFx.CANDLE_FADE)
            return 0.0
        }
    }
}

/** "keyShape":"glass" — ô kính màu theo chữ, viền chì, gradient trong. = iOS GlassKeys. */
object GlassKeys {
    const val SHAPE = "glass"
    val PANES = intArrayOf(0x8E1B2E, 0x1E4596, 0x0F5C40, 0x7A4A00)
    val ROWS = listOf("qwertyuiop", "asdfghjkl", "zxcvbnm")
    const val LEAD = 0x0B0A0C
    const val HIGHLIGHT = 0.10
    const val SHADE = 0.14
    const val PRESSED_LIFT = 0.22
    const val LEAD_FACTOR = 0.06
    const val MIN_LEAD = 2.0

    fun paneIndex(label: String): Int {
        val s = label.lowercase()
        if (s.isEmpty()) return 0
        val cp = s.codePointAt(0)
        ROWS.forEachIndexed { r, row ->
            val c = row.indexOf(cp.toChar())
            if (cp < 0x10000 && c >= 0) return (c + 2 * r) % PANES.size
        }
        return ((cp.toLong() and 0xFFFFFFFFL) % PANES.size).toInt()
    }

    fun paneColor(label: String): Int = PANES[paneIndex(label)]

    fun mix(c: Int, d: Int, t: Double): Int {
        fun ch(sh: Int): Int {
            val a = ((c shr sh) and 0xFF).toDouble(); val b = ((d shr sh) and 0xFF).toDouble()
            return Math.round(a + (b - a) * t).toInt() shl sh
        }
        return ch(16) or ch(8) or ch(0)
    }

    fun top(c: Int): Int = mix(c, 0xFFFFFF, HIGHLIGHT)
    fun pressed(c: Int): Int = mix(c, 0xFFFFFF, PRESSED_LIFT)
    fun leadWidth(keyHeight: Double): Double = max(MIN_LEAD, keyHeight * LEAD_FACTOR)
}
