package com.viettelex.keyboard

import kotlin.math.cos
import kotlin.math.sin

/**
 * Hiệu ứng bấm phím "Kính vạn hoa" (id `kaleido`, Plus, 11/2026 — mặc định của theme "Ảo giác") — hình học + thời gian
 * THUẦN, song sinh iOS/Keyboard/Kaleido.swift (KaleidoBloom, cùng số — test chung).
 *
 * Mỗi phím một bông đối xứng 8 nhánh nở từ chỗ chạm: 8 mảnh kính hình diều (dài / ngắn xen kẽ, mỗi mảnh đối xứng qua
 * trục của nó) + 8 viên đá nhỏ giữa hai nhánh, 8 sắc cầu vồng; cả bông xoay chậm 45° trong khi nở rồi tan trong
 * [DURATION]. Tối đa [POOL] bông. Tâm kẹp để CẢ bông nằm trong khung bàn phím.
 */
object KaleidoBloom {
    const val FOLDS = 8
    const val DURATION = 0.9
    /** Góc xoay cả bông trong suốt đời (rad) — 45°, chậm. */
    const val SPIN = Math.PI / 4
    /** Bán kính tới đầu mảnh dài khi nở hết (dp). */
    const val RADIUS = 38.0
    const val SCALE_FROM = 0.25
    const val PEAK = 0.9
    /** Trần số bông cùng lúc. */
    const val POOL = 4
    /** 8 sắc cầu vồng (mảnh k dùng sắc k, đá giữa nhánh k và k+1 dùng sắc k+4). */
    val COLORS = intArrayOf(0xFF5E8A, 0xFFA94D, 0xFFE066, 0x6EE7B7, 0x5EEAD4, 0x60A5FA, 0xA78BFA, 0xF472B6)

    /** Mảnh nhánh [k] dạng đơn vị (trục −y, đầu nhọn hướng lên), đối xứng qua x = 0: chẵn dài mảnh, lẻ ngắn rộng. [x0,y0,x1,y1,…] */
    fun shardUnit(k: Int): DoubleArray = if (k % 2 == 0) doubleArrayOf(0.0, -1.0, 0.17, -0.55, 0.0, -0.16, -0.17, -0.55)
        else doubleArrayOf(0.0, -0.74, 0.24, -0.46, 0.0, -0.2, -0.24, -0.46)
    /** Viên đá nhỏ (hình thoi, đơn vị) trên trục của nó. */
    val GEM_UNIT = doubleArrayOf(0.0, -0.5, 0.07, -0.38, 0.0, -0.26, -0.07, -0.38)

    /** Góc trục nhánh [k]. */
    fun axis(k: Int): Double = k * 2 * Math.PI / FOLDS

    private fun place(unit: DoubleArray, a: Double): DoubleArray {
        val out = DoubleArray(unit.size)
        val c = cos(a); val s = sin(a)
        for (i in unit.indices step 2) {
            val x = unit[i] * RADIUS; val y = unit[i + 1] * RADIUS
            out[i] = x * c - y * s; out[i + 1] = x * s + y * c
        }
        return out
    }
    /** Mảnh nhánh [k] (dp, quanh tâm 0,0) — [x0,y0,x1,y1,…]. */
    fun shard(k: Int): DoubleArray = place(shardUnit(k), axis(k))
    /** Đá giữa nhánh [k] và [k] + 1. */
    fun gem(k: Int): DoubleArray = place(GEM_UNIT, axis(k) + Math.PI / FOLDS)
    fun shardColor(k: Int): Int = k % COLORS.size
    fun gemColor(k: Int): Int = (k + FOLDS / 2) % COLORS.size

    fun progress(t: Double): Double = (t / DURATION).coerceIn(0.0, 1.0)
    /** Cỡ: nở ease-out bậc ba từ [SCALE_FROM] tới 1. */
    fun scale(t: Double): Double {
        val v = 1 - progress(t)
        return SCALE_FROM + (1 - SCALE_FROM) * (1 - v * v * v)
    }
    /** Góc xoay (đều — chậm). */
    fun angle(t: Double): Double = SPIN * progress(t)
    /** Độ mờ: hiện trong 12 % đầu rồi tan (1 − u)²; 0 ở cuối. */
    fun alpha(t: Double): Double {
        if (t < 0 || t >= DURATION) return 0.0
        val u = progress(t)
        return PEAK * minOf(1.0, u / 0.12) * (1 - u) * (1 - u)
    }
    /** Bán kính lớn nhất của cả bông. */
    const val EXTENT = RADIUS

    /** Tâm bông từ điểm chạm, kẹp để CẢ bông nằm trong khung (bx, by, bw, bh) — khung hẹp hơn bông ⇒ giữa khung. */
    fun center(x: Double, y: Double, bx: Double, by: Double, bw: Double, bh: Double): DoubleArray {
        fun clamp(v: Double, lo: Double, len: Double) =
            if (len <= 2 * EXTENT) lo + len / 2 else minOf(maxOf(v, lo + EXTENT), lo + len - EXTENT)
        return doubleArrayOf(clamp(x, bx, bw), clamp(y, by, bh))
    }
}
