package com.viettelex.keyboard

import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.sin

// Theme "Cà phê sữa đá" (11/2026, Plus): hiệu ứng "Đá lanh canh" (id ice) + cảnh ly cà phê (motif "cafe" — [ThemeScene]).
// Hàm thuần song sinh iOS/Keyboard/CafeFx.swift — CÙNG SỐ (test chéo hai nền tảng). Toạ độ dp.
//  • Bấm phím ⇒ "viên đá" (khung kính sáng ôm phím) lắc lư tắt dần + một giọt nước đọng trượt xuống từ góc dưới phím.
//  • Phin nhỏ (vector) ở góc trái thanh gợi ý: mỗi 4 phím nhỏ một giọt cà phê xuống ly. Phin tĩnh (0 hoạt ảnh khi nghỉ).
//  • Gõ nhanh (ComboMeter lên mức 2) ⇒ một vòng sữa xoáy vào cà phê ở đáy (hồi 2,5 s).
object CafeFx {
    // Viên đá lắc
    const val JIGGLE_AMP = 0.09
    const val JIGGLE_TAU = 0.12
    const val JIGGLE_FREQ = 7.0
    const val JIGGLE_DURATION = 0.4
    const val CUBE_INSET = 1.0
    const val CUBE_CORNER = 6.0
    const val POOL = 6

    /** Góc lắc (radian) [t] giây sau khi bấm: dao động tắt dần, 0 sau [JIGGLE_DURATION]. */
    fun jiggle(t: Double): Double {
        if (t <= 0 || t >= JIGGLE_DURATION) return 0.0
        return JIGGLE_AMP * exp(-t / JIGGLE_TAU) * sin(2 * Math.PI * JIGGLE_FREQ * t)
    }
    fun cubeAlpha(t: Double): Double = if (t <= 0 || t >= JIGGLE_DURATION) 0.0 else 0.9 * (1 - t / JIGGLE_DURATION)

    // Giọt nước đọng
    const val DROPLET_RADIUS = 2.2
    const val DROPLET_SLIDE = 12.0
    const val DROPLET_DURATION = 0.6
    fun dropletOrigin(keyMaxX: Double, keyMaxY: Double): Pair<Double, Double> = Pair(keyMaxX - 6, keyMaxY - 3)
    /** (lệch y, độ đậm) — trượt nhanh dần, mờ dần. */
    fun droplet(t: Double): Pair<Double, Double> {
        val u = (t / DROPLET_DURATION).coerceIn(0.0, 1.0)
        return Pair(DROPLET_SLIDE * u * u, if (t <= 0 || t >= DROPLET_DURATION) 0.0 else 0.9 * (1 - u))
    }

    // Phin + giọt cà phê
    const val DRIP_EVERY = 4
    const val PHIN_WIDTH = 16.0
    const val PHIN_HEIGHT = 10.0
    const val CUP_WIDTH = 14.0
    const val CUP_HEIGHT = 10.0
    const val CUP_GAP = 9.0
    const val DROP_FALL = 8.0
    const val DROP_DURATION = 0.3
    const val DROP_RADIUS = 1.6
    const val COFFEE = 0x3B2416
    /** Góc phin (trên-trái của phin) — góc trái thanh gợi ý. */
    fun phinOrigin(minX: Double, top: Double): Pair<Double, Double> = Pair(minX + 8, top + 3)
    /** Toàn khung phin + ly: x, y, w, h. */
    fun phinBox(minX: Double, top: Double): DoubleArray {
        val o = phinOrigin(minX, top)
        return doubleArrayOf(o.first, o.second, PHIN_WIDTH, PHIN_HEIGHT + CUP_GAP + CUP_HEIGHT)
    }
    /** Giọt rơi [t] giây: lệch y (rơi nhanh dần) — 0…[DROP_FALL]. */
    fun dropY(t: Double): Double {
        val u = (t / DROP_DURATION).coerceIn(0.0, 1.0)
        return DROP_FALL * u * u
    }

    class DripCounter {
        var n = 0
            private set
        /** Một phím — true khi tới lượt nhỏ giọt (mỗi [DRIP_EVERY] phím). */
        fun press(): Boolean {
            n++
            if (n >= DRIP_EVERY) { n = 0; return true }
            return false
        }
        fun reset() { n = 0 }
    }

    // Sữa xoáy
    const val SWIRL_LEVEL = 2
    const val SWIRL_COOLDOWN = 2.5
    const val SWIRL_DURATION = 1.2
    const val SWIRL_DRAW = 0.6
    const val SWIRL_RADIUS = 22.0
    const val SWIRL_TURNS = 1.75
    const val SWIRL_POINTS = 40
    const val SWIRL_LIFT = 28.0
    const val SWIRL_WIDTH = 2.5
    const val MILK = 0xF3E5CC

    class SwirlGate {
        var last = -Double.MAX_VALUE
            private set
        /** Mức combo VỪA lên tới [SWIRL_LEVEL] và đã hồi ≥ [SWIRL_COOLDOWN] (giây). */
        fun shouldSwirl(level: Int, previous: Int, now: Double): Boolean {
            if (level < SWIRL_LEVEL || previous >= SWIRL_LEVEL || now - last < SWIRL_COOLDOWN) return false
            last = now
            return true
        }
    }
    fun swirlCenter(midX: Double, bottom: Double): Pair<Double, Double> = Pair(midX, bottom - SWIRL_LIFT)
    /** Xoắn ốc Archimedes r = a·θ quanh gốc, θ 0 … turns·2π, bán kính cuối = [SWIRL_RADIUS]. */
    fun spiral(): List<Pair<Double, Double>> {
        val tMax = SWIRL_TURNS * 2 * Math.PI; val a = SWIRL_RADIUS / tMax
        return (0..SWIRL_POINTS).map { i ->
            val th = tMax * (i.toDouble() / SWIRL_POINTS)
            Pair(a * th * cos(th), a * th * sin(th))
        }
    }
    fun swirlAlpha(t: Double): Double {
        if (t <= 0 || t >= SWIRL_DURATION) return 0.0
        if (t > SWIRL_DURATION - 0.4) return 0.85 * (SWIRL_DURATION - t) / 0.4
        return 0.85
    }
}

/** Cảnh ly cà phê (motif "cafe"): giọt nước đọng li ti (màu deco) trên gradient [ThemeScene.gradient]. iOS CafeScene y hệt. */
object CafeScene {
    const val DOT_COUNT = 24
    /** (x, y, bán kính) mỗi giọt. */
    fun dots(w: Double, h: Double): List<DoubleArray> = (0 until DOT_COUNT).map { i ->
        val a = fxStep(fxSeed(i * 211 + 3)); val b = fxStep(a); val c = fxStep(b)
        doubleArrayOf(4 + (w - 8) * fxValue(a), 4 + (h - 8) * fxValue(b), 1 + 1.2 * fxValue(c))
    }
}
