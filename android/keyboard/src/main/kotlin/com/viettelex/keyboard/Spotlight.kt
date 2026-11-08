package com.viettelex.keyboard

import kotlin.math.cos
import kotlin.math.sin

/*
 * "Neon Night Club" (11/2026, Plus): ĐÈN RỌI trên ảnh nền ("photoFx":"spotlight" — [ThemeSpec]) + quả cầu disco nhỏ.
 * Hàm THUẦN — song sinh iOS/Keyboard/NightClub.swift (CÙNG SỐ, test chung). Vẽ: app/.../ime/SpotlightView.kt.
 */

/** Cổng chạy: theme có "photoFx":"spotlight" + Plus + không tiết kiệm pin. Giảm chuyển động KHÔNG tắt. = iOS SpotlightPolicy. */
object SpotlightPolicy {
    fun active(photoFx: String?, plus: Boolean, lowPower: Boolean): Boolean =
        photoFx == ThemeExtraIds.SPOTLIGHT && plus && !lowPower
}

/** Đèn rọi (giây, dp) — = iOS SpotlightFx. */
object SpotlightFx {
    /** Tối đa số quầng sống cùng lúc (quầng cũ nhất bị thay). */
    const val CAP = 6
    /** Lớp đen phủ ảnh nền (0…1). */
    const val DARKNESS = 0.9
    /** Neon xoay vòng mỗi lần bấm: hồng, tím, lục lam. */
    val COLORS = intArrayOf(0xFF2FD0, 0x9B5CFF, 0x2FE6FF)
    /** Độ đậm quầng tô màu (nhân với độ sáng quầng). */
    const val TINT = 0.32
    const val ATTACK = 0.06
    const val BASE_DURATION = 0.72
    const val DURATION_PER_LEVEL = 0.05
    const val RADIUS_FACTOR = 1.6
    const val RADIUS_PER_LEVEL = 0.15
    const val MIN_RADIUS = 36.0
    const val MAX_RADIUS = 150.0
    const val PEAK_BASE = 0.78
    const val PEAK_PER_LEVEL = 0.07
    const val START_SCALE = 0.8
    const val GROW_SCALE = 0.3

    private fun lv(level: Int): Double = level.coerceIn(0, 3).toDouble()

    /** Thời gian sống của quầng ở mức combo [level] (0…3): 0,72…0,87 s. */
    fun duration(level: Int): Double = BASE_DURATION + DURATION_PER_LEVEL * lv(level)
    /** Bán kính quầng (dp) theo bề rộng phím + mức combo, kẹp [36, 150]. */
    fun radius(keyWidth: Double, level: Int): Double =
        (keyWidth * (RADIUS_FACTOR + RADIUS_PER_LEVEL * lv(level))).coerceIn(MIN_RADIUS, MAX_RADIUS)
    /** Độ sáng đỉnh 0,78…0,99. */
    fun peak(level: Int): Double = minOf(1.0, PEAK_BASE + PEAK_PER_LEVEL * lv(level))
    /** Độ sáng sau [dt] giây: lên tuyến tính trong [ATTACK], rồi tắt (1−u)². */
    fun alpha(dt: Double, level: Int): Double {
        val d = duration(level); val p = peak(level)
        if (dt < 0 || dt >= d) return 0.0
        if (dt < ATTACK) return p * dt / ATTACK
        val u = (dt - ATTACK) / (d - ATTACK)
        return p * (1 - u) * (1 - u)
    }
    /** Hệ số bán kính sau [dt] (0,8 → 1,1, chậm dần). */
    fun scale(dt: Double, level: Int): Double {
        val x = (dt / duration(level)).coerceIn(0.0, 1.0)
        return START_SCALE + GROW_SCALE * (1 - (1 - x) * (1 - x))
    }
    /** Màu neon (RGB) của lần bấm thứ [press]. */
    fun color(press: Int): Int = COLORS[((press % COLORS.size) + COLORS.size) % COLORS.size]
}

/** Vòng quầng sáng (mảng cấp sẵn): lần bấm ⇒ ô kế tiếp (quầng cũ nhất bị thay khi đủ CAP). = iOS SpotlightLights. */
class SpotlightLights {
    val starts = DoubleArray(SpotlightFx.CAP) { Double.NEGATIVE_INFINITY }
    val levels = IntArray(SpotlightFx.CAP)
    var cursor = 0; private set
    var presses = 0; private set

    /** Bấm lúc [t] ở mức combo [level] ⇒ chỉ số ô dùng. */
    fun press(t: Double, level: Int): Int {
        val i = cursor
        starts[i] = t; levels[i] = level
        cursor = (cursor + 1) % SpotlightFx.CAP
        presses++
        return i
    }
    /** Số quầng còn sáng lúc [t]. */
    fun live(t: Double): Int {
        var n = 0
        for (i in 0 until SpotlightFx.CAP) if (t >= starts[i] && t - starts[i] < SpotlightFx.duration(levels[i])) n++
        return n
    }
    /** Thời điểm quầng cuối tắt hẳn (−∞ khi chưa bấm). */
    val lastEnd: Double get() {
        var e = Double.NEGATIVE_INFINITY
        for (i in 0 until SpotlightFx.CAP) if (starts[i] > Double.NEGATIVE_INFINITY) e = maxOf(e, starts[i] + SpotlightFx.duration(levels[i]))
        return e
    }
    fun reset() { starts.fill(Double.NEGATIVE_INFINITY); levels.fill(0); cursor = 0 }
}

/** Quả cầu disco nhỏ ở góc trên phải (dp) — = iOS DiscoBall. */
object DiscoBall {
    const val DIAMETER = 16.0
    const val INSET = 6.0
    /** Dây treo (từ mép trên xuống đỉnh quả cầu). */
    const val CORD = 5.0
    /** Mỗi lần bấm xoay thêm (rad) trong [SPIN_DURATION]. */
    const val SPIN = 0.35
    const val SPIN_DURATION = 0.25
    const val DOTS_PER_PRESS = 3
    const val DOT_POOL = 6
    const val DOT_RADIUS = 2.0
    const val DOT_DISTANCE = 30.0
    const val DOT_DURATION = 0.45
    const val MIN_INTERVAL = 0.12

    /** Tâm quả cầu (x, y) trong khung (minX, minY, width) — góc trên phải. */
    fun center(minX: Double, minY: Double, width: Double): DoubleArray =
        doubleArrayOf(minX + width - INSET - DIAMETER / 2, minY + CORD + DIAMETER / 2)
    /** Hướng bay chấm [i] của lần bấm [press] (đơn vị, y xuống): toả xuống-trái 0,55π…1,03π. */
    fun direction(press: Int, i: Int): DoubleArray {
        val a = Math.PI * (0.55 + 0.16 * i + 0.04 * (((press % 3) + 3) % 3))
        return doubleArrayOf(cos(a), sin(a))
    }
    /** Độ mờ chấm sau [dt]: (1−u)². */
    fun dotAlpha(dt: Double): Double {
        if (dt < 0 || dt >= DOT_DURATION) return 0.0
        val u = dt / DOT_DURATION
        return (1 - u) * (1 - u)
    }
    /** Quãng đã bay sau [dt] (chậm dần). */
    fun dotTravel(dt: Double): Double {
        val u = (dt / DOT_DURATION).coerceIn(0.0, 1.0)
        return DOT_DISTANCE * (1 - (1 - u) * (1 - u))
    }
}

/** Phông tím đêm khi không có ảnh nền (chỉ lộ dưới đèn, quanh người nhảy) — = iOS SpotlightTexture. */
object SpotlightTexture {
    /** Gradient chéo: tím đậm → tím đêm → xanh đêm. */
    val GRADIENT = intArrayOf(0x3A0A5E, 0x16073A, 0x06284A)
}

/**
 * Người nhảy (KHÔNG có ảnh nền): nhân vật HOẠT HÌNH của Bạn đồng hành (atlas 4 × 2 buddy-<id>-v2.png — khung 0 đứng,
 * 1 nhảy, 2 xoay ¾, 3 nghiêng phải, 4 sau lưng, 5 nghiêng trái, 6 xoay về; 7 ngủ không dùng) cỡ lớn phía sau phím, chìm
 * trong tối (~12 % sáng); chỉ vùng đèn rọi thấy màu thật + viền neon theo màu đèn. Mỗi lần đèn nháy ⇒ biến thể kế: 7 khung
 * × {thường, lật ngang} = 14 biến thể. Hàm THUẦN — = iOS NightDancer (cùng số, test chung).
 */
object NightDancer {
    /** Chuỗi nhảy nhanh (khung atlas) — trọng số chọn khung; bỏ khung 7 (ngủ). */
    val SEQUENCE = intArrayOf(0, 1, 0, 1, 2, 3, 4, 5, 6)
    const val FRAMES = 7
    const val VARIANTS = FRAMES * 2
    /** Xác suất theo đúng chuỗi nhảy (còn lại: khung ngẫu nhiên 0…6). */
    const val FOLLOW = 0.7
    /** Lật ngang: sau biến thể thường / sau biến thể đã lật (thấp hơn ⇒ ít khi lật hai lần liền — xoay qua lại tự nhiên). */
    const val MIRROR = 0.5
    const val MIRROR_AGAIN = 0.25
    /** Cao nhân vật = tỉ lệ cao bàn phím (cả dải gợi ý), đứng sát đáy, giữa ngang. */
    const val HEIGHT_FRACTION = 0.85
    /** Độ sáng phần ngoài đèn (nhân RGB, giữ alpha). */
    const val SHADE = 0.12
    /** Viền neon quanh nhân vật dưới đèn (dp / pt). */
    const val RIM = 2.5
    const val COLUMNS = 4
    const val ROWS = 2
    /** Trần cạnh dài atlas khi giải (px) — ≤ 2048 × 1365 × 4 B ≈ 11 MB; atlas hiện 1536 × 1024 ⇒ 6,3 MB. */
    const val MAX_LONG_EDGE = 2048

    fun frame(variant: Int): Int = Math.floorMod(variant, VARIANTS) % FRAMES
    fun mirrored(variant: Int): Boolean = Math.floorMod(variant, VARIANTS) >= FRAMES

    /** Nhân vật nhảy: chàng trai nếu Bạn đồng hành đang chọn là chàng trai; còn lại (tắt, cô gái, mèo, gà, AI…) ⇒ cô gái. */
    fun character(buddy: BuddyCharacter): BuddyCharacter = if (buddy == BuddyCharacter.BOY) BuddyCharacter.BOY else BuddyCharacter.GIRL

    /**
     * Biến thể của lần nháy thứ [flash] (1, 2, …) sau biến thể [prev] (−1 = chưa có): theo chuỗi nhảy với xác suất
     * [FOLLOW], không thì khung ngẫu nhiên; lật ngang [MIRROR] / [MIRROR_AGAIN]; KHÔNG BAO GIỜ trùng [prev]. Tất định
     * theo [flash] (fxSeed) ⇒ cùng số hai nền tảng.
     */
    fun next(prev: Int, flash: Int): Int {
        var st = fxStep(fxSeed(flash * 7919 + 17))   // bỏ một bước: số đầu của seed liền nhau tương quan
        st = fxStep(st); val a = fxValue(st)
        st = fxStep(st); val b = fxValue(st)
        st = fxStep(st); val c = fxValue(st)
        var f = if (a < FOLLOW) SEQUENCE[Math.floorMod(flash, SEQUENCE.size)] else minOf(FRAMES - 1, (b * FRAMES).toInt())
        val m = c < (if (prev >= 0 && mirrored(prev)) MIRROR_AGAIN else MIRROR)
        var v = f + if (m) FRAMES else 0
        if (v == prev) { f = (f + 1) % FRAMES; v = f + if (m) FRAMES else 0 }
        return v
    }

    /** Ô [frame] trong atlas: (x, y, w, h) theo tỉ lệ 0…1 (contentsRect iOS / src rect Android). */
    fun cell(frame: Int): DoubleArray {
        val i = Math.floorMod(frame, COLUMNS * ROWS)
        return doubleArrayOf((i % COLUMNS).toDouble() / COLUMNS, (i / COLUMNS).toDouble() / ROWS, 1.0 / COLUMNS, 1.0 / ROWS)
    }

    /** Khung vẽ (x, y, w, h) trong bàn phím [w] × [h] với ô tỉ lệ rộng/cao [cellAspect]: cao 85 %, đứng đáy, giữa ngang. */
    fun rect(w: Double, h: Double, cellAspect: Double): DoubleArray {
        val fh = h * HEIGHT_FRACTION
        val fw = fh * cellAspect
        return doubleArrayOf((w - fw) / 2, h - fh, fw, fh)
    }

    /**
     * Cạnh dài (px) cần giải atlas [atlasW] × [atlasH] để ô cao đúng [displayHeight] (pt / dp) × [scale] (px mỗi pt) —
     * không quá ảnh gốc, không quá [MAX_LONG_EDGE]. Giải MỘT lần (không giải lại mỗi khung).
     */
    fun decodeLongEdge(displayHeight: Double, scale: Double, atlasW: Int, atlasH: Int): Int {
        if (atlasW <= 0 || atlasH <= 0) return 0
        val native = maxOf(atlasW, atlasH)
        val needH = displayHeight * scale * ROWS
        val need = Math.ceil(needH * native / atlasH).toInt()
        return minOf(need, native, MAX_LONG_EDGE)
    }

    /** Android inSampleSize: lũy thừa 2 lớn nhất mà cạnh dài sau giải vẫn ≥ [target] (không bao giờ mờ hơn cỡ cần). */
    fun sampleSize(nativeLongEdge: Int, target: Int): Int {
        var s = 1
        if (target <= 0) return s
        while (nativeLongEdge / (s * 2) >= target) s *= 2
        return s
    }

    /** RAM ảnh đã giải (byte, RGBA 8-bit) khi cạnh dài = [longEdge]. */
    fun decodedBytes(longEdge: Int, atlasW: Int, atlasH: Int): Long {
        if (atlasW <= 0 || atlasH <= 0 || longEdge <= 0) return 0
        val native = maxOf(atlasW, atlasH).toDouble()
        val w = Math.round(atlasW * longEdge / native); val h = Math.round(atlasH * longEdge / native)
        return w * h * 4
    }
}
