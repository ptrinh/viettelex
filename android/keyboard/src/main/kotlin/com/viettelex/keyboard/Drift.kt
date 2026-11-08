package com.viettelex.keyboard

import kotlin.math.PI
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/*
 * Theme "Lạc trôi" (11/2026, Plus): hiệu ứng "Đường hầm" ([TunnelFx]) + phím "Lơ lửng" ([FloatFx] / [FloatClock]).
 * Hàm THUẦN — song sinh iOS/Keyboard/Drift.swift (CÙNG SỐ, test chung). Vẽ: app/.../ime/DriftPainters.kt (vòng đường hầm
 * trên KeyEffectView) + KeyboardView (dời HÌNH từng phím lúc vẽ — vùng nhận chạm theo khung phím gốc, không đổi).
 */

/**
 * "Đường hầm": mỗi phím bấm vài vòng mảnh (tím neon dịu / lục lam) hiện ở mép bàn phím rồi co về điểm tụ là phím vừa
 * bấm (không có cỡ phím ⇒ tâm bàn phím), co NHANH DẦN (cỡ 1 − u²) như rơi vào đường hầm vô tận. Vòng = viền bàn phím
 * thu nhỏ quanh điểm tụ V (tâm = V + (C − V)·s). Gõ dồn (mức [ComboMeter]) ⇒ nhiều vòng hơn + rơi nhanh hơn. Trần [POOL].
 * Thời gian giây, đơn vị dp (iOS pt). = iOS TunnelFx.
 */
object TunnelFx {
    const val POOL = 16
    val RINGS_PER_LEVEL = intArrayOf(2, 3, 4, 5)
    val DURATIONS = doubleArrayOf(1.15, 1.05, 0.97, 0.9)
    const val STAGGER = 0.12
    const val LINE_WIDTH = 1.2
    const val GLOW_WIDTH = 4.0
    const val GLOW_ALPHA = 0.22
    const val PEAK_ALPHA = 0.85
    const val FADE_IN = 0.12
    const val FADE_OUT = 0.3
    const val INSET = 2.0
    const val MAX_CORNER = 22.0
    /** Tím neon dịu, lục lam — xen kẽ theo thứ tự vòng. */
    val COLORS = intArrayOf(0xB48CFF, 0x5EEAD4)

    fun level(l: Int): Int = l.coerceIn(0, 3)
    fun rings(level: Int): Int = RINGS_PER_LEVEL[level(level)]
    fun duration(level: Int): Double = DURATIONS[level(level)]
    fun delay(ring: Int): Double = max(ring, 0) * STAGGER
    /** Tỉ lệ cỡ vòng ở tỉ lệ thời gian [u]: 1 − u² — co nhanh dần. */
    fun scale(u: Double): Double { val k = u.coerceIn(0.0, 1.0); return 1 - k * k }
    /** Độ đậm ở [u]: hiện dần [FADE_IN], mờ dần [FADE_OUT] cuối; ngoài [0, 1) ⇒ 0. */
    fun alpha(u: Double): Double = if (u < 0.0 || u >= 1.0) 0.0 else PEAK_ALPHA * minOf(1.0, u / FADE_IN, (1 - u) / FADE_OUT)
    /** Điểm tụ vào [out] (x, y): tâm phím; không có cỡ phím ⇒ tâm bàn phím. */
    fun vanish(kx: Double, ky: Double, kw: Double, kh: Double, bx: Double, by: Double, bw: Double, bh: Double, out: DoubleArray) {
        if (kw > 0 && kh > 0) { out[0] = kx + kw / 2; out[1] = ky + kh / 2 } else { out[0] = bx + bw / 2; out[1] = by + bh / 2 }
    }
    /** Tâm vòng ở [u] vào [out]: V + (C − V)·scale(u). */
    fun center(cx: Double, cy: Double, vx: Double, vy: Double, u: Double, out: DoubleArray) {
        val s = scale(u); out[0] = vx + (cx - vx) * s; out[1] = vy + (cy - vy) * s
    }
    fun corner(w: Double, h: Double): Double = min(MAX_CORNER, min(w, h) * 0.12)
}

/** "Lơ lửng": tham số + đường đi từng phím (giây, dp, radian). = iOS FloatFx. */
object FloatFx {
    const val MAX_OFFSET = 4.0
    const val MAX_ROTATION = 2.0 * PI / 180
    const val IDLE = 2.0
    const val SETTLE = 0.8

    data class Params(val ax: Double, val ay: Double, val rot: Double, val px: Double, val py: Double, val pr: Double)

    private val cache = HashMap<Int, Params>()

    /** Tham số phím thứ [i] — |(ax, ay)| ≤ √(2.2² + 2.8²) ≈ 3.56 dp (ngang nhỏ hơn dọc: khe phím kề hẹp hơn khe hàng), |rot| ≤ 1.6°. Cache theo chỉ số (≤ vài chục phím, dựng một lần). */
    fun params(i: Int): Params = cache.getOrPut(i) {
        var st = mix(i * 131 + 17)
        val v = DoubleArray(7) { st = fxStep(st); fxValue(st) }
        val g = v[6]
        val sx = if (g < 0.5) -1.0 else 1.0
        val sy = if ((g * 1000).toInt() % 2 == 0) 1.0 else -1.0
        val sr = if ((g * 1000).toInt() / 2 % 2 == 0) -1.0 else 1.0
        Params(sx * (1.4 + 0.8 * v[0]), sy * (1.8 + 1.0 * v[1]), sr * (0.8 + 0.8 * v[2]) * PI / 180,
            3.2 + 1.6 * v[3], 3.0 + 1.6 * v[4], 3.6 + 1.4 * v[5])
    }

    /** Trộn chỉ số phím (murmur3 finalizer) — phím kề nhau ra nhịp khác hẳn nhau. = iOS FloatFx.mix. */
    fun mix(i: Int): Int {
        var h = i * 0x9E3779B9.toInt()
        h = h xor (h ushr 16); h *= 0x85EBCA6B.toInt(); h = h xor (h ushr 13); h *= 0xC2B2AE35.toInt(); h = h xor (h ushr 16)
        return h
    }

    /** Độ lệch phím [i] sau [t] giây trôi vào [out] (x, y, xoay). */
    fun bob(i: Int, t: Double, out: DoubleArray) {
        val p = params(i); val w = 2 * PI
        out[0] = p.ax * sin(w * t / p.px); out[1] = p.ay * sin(w * t / p.py); out[2] = p.rot * sin(w * t / p.pr)
    }
    fun smooth(f: Double): Double { val k = f.coerceIn(0.0, 1.0); return k * k * (3 - 2 * k) }
    /** Hệ số còn lại khi về chỗ, [dt] giây sau khi bắt đầu về: 1 → 0. */
    fun settleFactor(dt: Double): Double = 1 - smooth(dt / SETTLE)
}

/**
 * Đồng hồ "Lơ lửng": gõ ⇒ trôi; nghỉ [FloatFx.IDLE] ⇒ về chỗ [FloatFx.SETTLE] rồi dừng. Gõ lại lúc đang về chỗ ⇒ nhịp trôi
 * mới từ 0 CỘNG phần về chỗ còn lại (liền mạch). = iOS FloatClock (iOS: animation cộng dồn cùng công thức).
 */
class FloatClock {
    var start = Double.NaN
        private set
    var last = Double.NEGATIVE_INFINITY
        private set
    var settleStart = Double.NaN
        private set
    var frozen = 0.0
        private set
    private val tmp = DoubleArray(3)

    val bobbing: Boolean get() = !start.isNaN()
    val active: Boolean get() = !start.isNaN() || !settleStart.isNaN()

    /** Một phím lúc [t] — true khi nhịp trôi VỪA bắt đầu. */
    fun poke(t: Double): Boolean {
        last = t
        if (!start.isNaN()) return false
        start = t
        return true
    }
    /** Cập nhật lúc [t] — true khi VỪA chuyển sang về chỗ. */
    fun update(t: Double): Boolean {
        var began = false
        if (!start.isNaN() && t - last >= FloatFx.IDLE) { settleStart = t; frozen = t - start; start = Double.NaN; began = true }
        if (!settleStart.isNaN() && t - settleStart >= FloatFx.SETTLE) settleStart = Double.NaN
        return began
    }
    /** Độ lệch phím [i] lúc [t] vào [out] (x, y dp; xoay radian). Không cấp phát. */
    fun offset(i: Int, t: Double, out: DoubleArray) {
        out[0] = 0.0; out[1] = 0.0; out[2] = 0.0
        if (!start.isNaN()) FloatFx.bob(i, t - start, out)
        if (!settleStart.isNaN()) {
            val k = FloatFx.settleFactor(t - settleStart)
            FloatFx.bob(i, frozen, tmp)
            out[0] += tmp[0] * k; out[1] += tmp[1] * k; out[2] += tmp[2] * k
        }
    }
    fun stop() { start = Double.NaN; settleStart = Double.NaN }
}

/**
 * Cổng "Lơ lửng": hiệu ứng thực dùng là FLOAT HOẶC theme có "keyMotion":"float"; cần Plus, không tiết kiệm pin. Giảm
 * chuyển động / tỉ lệ hoạt ảnh 0 KHÔNG tắt (Phil 11/2026). = iOS FloatPolicy.
 */
object FloatPolicy {
    fun active(effect: KeyEffect, keyMotion: String?, plus: Boolean, lowPower: Boolean): Boolean =
        plus && !lowPower && (effect == KeyEffect.FLOAT || keyMotion == ThemeExtraIds.FLOAT_MOTION)
}
