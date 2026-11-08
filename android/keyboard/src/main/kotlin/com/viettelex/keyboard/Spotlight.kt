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

/** Phông tím đêm khi không có ảnh nền (chỉ lộ dưới đèn, sau bóng cô gái nhảy) — = iOS SpotlightTexture. */
object SpotlightTexture {
    /** Gradient chéo: tím đậm → tím đêm → xanh đêm. */
    val GRADIENT = intArrayOf(0x3A0A5E, 0x16073A, 0x06284A)
}

/**
 * Một tư thế (độ; hướng a ⇒ vector (sin a, cos a), y xuống: 0 = xuống, 90 = phải, 180 = lên, −90 = trái). l / r = bên
 * TRÁI / PHẢI màn hình; ua / fa = cánh tay / cẳng tay; th / sh = đùi / cẳng chân; flare = độ xoè váy 0…100. = iOS DancerPose.
 */
data class DancerPose(val id: String, val torso: Int, val lua: Int, val lfa: Int, val rua: Int, val rfa: Int, val lth: Int,
                      val lsh: Int, val rth: Int, val rsh: Int, val hair: Int, val flare: Int)

/**
 * Bóng đen cô gái nhảy (theme Neon Night Club, KHÔNG có ảnh nền): khối hình bo tròn (đầu, tóc đuôi ngựa, thân thon, váy chữ
 * A, tay chân) từ 8 tư thế themes/dancer-poses.json ([BuiltinThemesData.DANCER_JSON]). Bóng đen kiểu quảng cáo máy nghe
 * nhạc, đầm kín, không chi tiết cơ thể. Mỗi lần đèn nháy ⇒ tư thế kế (bước 3 mod 8: đủ vòng, không lặp liền). Đa giác cùng
 * chiều quay ⇒ tô nonzero = hợp. Hình học thuần — = iOS DancerFigure (checksum chung).
 */
object DancerFigure {
    const val TORSO = 0.27; const val NECK = 0.03; const val HEAD_R = 0.058; const val SHOULDER = 0.068; const val HIP_W = 0.034
    const val UPPER_ARM = 0.14; const val FOREARM = 0.13; const val THIGH = 0.235; const val SHIN = 0.22; const val FOOT = 0.05
    const val HAIR = 0.21
    const val SEG = 6
    const val HEIGHT_FRACTION = 0.86
    const val STEP = 3
    /** Viền đèn rọi (dp) — nửa ngoài lộ ra quanh bóng. */
    const val RIM_WIDTH = 3.0
    val FIELDS = listOf("torso", "lua", "lfa", "rua", "rfa", "lth", "lsh", "rth", "rsh", "hair", "flare")

    /** Đọc CHẶT ([StrictJson]): mục thiếu / sai kiểu / ngoài khoảng ⇒ bỏ mục; hỏng cả ⇒ rỗng. */
    fun parse(text: String): List<DancerPose> {
        val r = StrictJson.parse(text) as? StrictJson.Result.Ok ?: return emptyList()
        val root = r.v as? SJ.Obj ?: return emptyList()
        val items = (root["poses"] as? SJ.Arr)?.a ?: return emptyList()
        val out = ArrayList<DancerPose>()
        for (it in items.take(12)) {
            val m = it as? SJ.Obj ?: continue
            val id = (m["id"] as? SJ.Str)?.s?.takeIf { s -> s.isNotEmpty() } ?: continue
            val v = FIELDS.map { f -> (m[f] as? SJ.Num)?.v?.takeIf { x -> kotlin.math.abs(x) <= 360 } }
            if (v.any { x -> x == null }) continue
            val n = v.map { x -> x!! }
            if (n[10] !in 0..100) continue
            out.add(DancerPose(id, n[0], n[1], n[2], n[3], n[4], n[5], n[6], n[7], n[8], n[9], n[10]))
        }
        return out
    }
    /** Tư thế dựng sẵn — đọc LƯỜI (chỉ khi theme này đang dùng và không có ảnh nền). */
    val POSES: List<DancerPose> by lazy { parse(BuiltinThemesData.DANCER_JSON) }

    /** Tư thế của lần nháy thứ [press]. */
    fun poseIndex(press: Int, count: Int): Int = if (count <= 0) 0 else (((press % count) + count) % count) * STEP % count

    private fun vec(a: Int): DoubleArray { val r = a * Math.PI / 180; return doubleArrayOf(sin(r), cos(r)) }
    private fun add(p: DoubleArray, v: DoubleArray, k: Double) = doubleArrayOf(p[0] + v[0] * k, p[1] + v[1] * k)
    private fun oriented(pts: List<DoubleArray>): DoubleArray {
        var a = 0.0
        for (i in pts.indices) { val p = pts[i]; val q = pts[(i + 1) % pts.size]; a += p[0] * q[1] - q[0] * p[1] }
        val o = if (a >= 0) pts else pts.reversed()
        val out = DoubleArray(o.size * 2)
        for ((i, p) in o.withIndex()) { out[2 * i] = p[0]; out[2 * i + 1] = p[1] }
        return out
    }
    private fun capsule(p0: DoubleArray, p1: DoubleArray, r0: Double, r1: Double): DoubleArray {
        val dx = p1[0] - p0[0]; val dy = p1[1] - p0[1]
        val a = if (kotlin.math.hypot(dx, dy) > 1e-9) kotlin.math.atan2(dy, dx) else 0.0
        val pts = ArrayList<DoubleArray>()
        for (k in 0..SEG) { val t = a - Math.PI / 2 + Math.PI * k / SEG; pts.add(doubleArrayOf(p1[0] + r1 * cos(t), p1[1] + r1 * sin(t))) }
        for (k in 0..SEG) { val t = a + Math.PI / 2 + Math.PI * k / SEG; pts.add(doubleArrayOf(p0[0] + r0 * cos(t), p0[1] + r0 * sin(t))) }
        return oriented(pts)
    }
    private fun circle(c: DoubleArray, r: Double): DoubleArray = oriented((0 until 2 * SEG).map { k ->
        val t = 2 * Math.PI * k / (2 * SEG); doubleArrayOf(c[0] + r * cos(t), c[1] + r * sin(t))
    })

    /** Đa giác (mảng phẳng x0, y0 …) toạ độ đơn vị (hông = gốc) — 17 đa giác, thứ tự = iOS. */
    fun polygons(p: DancerPose): List<DoubleArray> {
        val hip = doubleArrayOf(0.0, 0.0); val t = vec(p.torso); val perp = doubleArrayOf(-t[1], t[0])
        val neckP = add(hip, t, TORSO); val head = add(neckP, t, NECK + HEAD_R)
        fun side(k: Double, w: Double) = add(add(hip, t, k), perp, w)
        val out = ArrayList<DoubleArray>()
        out.add(oriented(listOf(side(0.0, -0.05), side(0.12, -0.04), side(0.20, -0.052), side(TORSO, -0.072),
            side(TORSO, 0.072), side(0.20, 0.052), side(0.12, 0.04), side(0.0, 0.05))))
        out.add(capsule(neckP, add(neckP, t, NECK + 0.01), 0.02, 0.02))
        out.add(circle(head, HEAD_R))
        out.add(capsule(add(head, t, -0.01), add(head, vec(p.hair), HAIR), HEAD_R, 0.03))
        val fl = p.flare / 100.0; val down = doubleArrayOf(-t[0], -t[1])
        val w0 = add(hip, t, 0.12); val hem = add(hip, down, 0.11); val hw = 0.10 + 0.05 * fl
        out.add(oriented(listOf(add(w0, perp, -0.045), add(hem, perp, -hw), add(hem, perp, hw), add(w0, perp, 0.045))))
        for ((s, ua, fa) in listOf(Triple(-1.0, p.lua, p.lfa), Triple(1.0, p.rua, p.rfa))) {
            val sh = add(add(hip, t, TORSO - 0.015), perp, s * SHOULDER)
            val el = add(sh, vec(ua), UPPER_ARM); val hd = add(el, vec(fa), FOREARM)
            out.add(capsule(sh, el, 0.027, 0.021))
            out.add(capsule(el, hd, 0.021, 0.016))
            out.add(circle(hd, 0.019))
        }
        for ((s, th, sn) in listOf(Triple(-1, p.lth, p.lsh), Triple(1, p.rth, p.rsh))) {
            val root = add(hip, perp, s * HIP_W)
            val kn = add(root, vec(th), THIGH); val an = add(kn, vec(sn), SHIN)
            out.add(capsule(root, kn, 0.04, 0.027))
            out.add(capsule(kn, an, 0.026, 0.015))
            out.add(capsule(an, add(an, vec(sn + s * 80), FOOT), 0.015, 0.011))
        }
        return out
    }

    /** Đặt vào khung w × h: cao HEIGHT_FRACTION·h theo khung bao tư thế, giữa ngang, đáy cách 7 %. = iOS fitted. */
    fun fitted(p: DancerPose, w: Double, h: Double): List<DoubleArray> {
        val polys = polygons(p)
        var minX = Double.POSITIVE_INFINITY; var maxX = Double.NEGATIVE_INFINITY
        var minY = Double.POSITIVE_INFINITY; var maxY = Double.NEGATIVE_INFINITY
        for (q in polys) for (i in q.indices step 2) {
            minX = minOf(minX, q[i]); maxX = maxOf(maxX, q[i]); minY = minOf(minY, q[i + 1]); maxY = maxOf(maxY, q[i + 1])
        }
        if (maxY <= minY || h <= 0) return emptyList()
        val k = h * HEIGHT_FRACTION / (maxY - minY); val cx = (minX + maxX) / 2
        val bottom = h * (1 - (1 - HEIGHT_FRACTION) / 2)
        return polys.map { q ->
            val o = q.copyOf()
            for (i in q.indices step 2) { o[i] = w / 2 + (q[i] - cx) * k; o[i + 1] = bottom - (maxY - q[i + 1]) * k }
            o
        }
    }

    /** Tổng toạ độ (test chéo nền tảng). */
    fun checksum(polys: List<DoubleArray>): Double = polys.sumOf { it.sum() }
}
