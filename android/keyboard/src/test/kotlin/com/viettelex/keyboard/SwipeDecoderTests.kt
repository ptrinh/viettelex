package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.File
import java.util.Locale
import kotlin.math.PI
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Sinh đường vuốt giả — song sinh SwipeSim trong iOS/KeyboardTests/SwipeDecoderTests.swift.
 * Tâm phím + nhiễu Gaussian σ·phím (điểm điều khiển), lệch đầu/cuối tuỳ chọn, làm mượt
 * Catmull-Rom, mỗi mẫu ~0.35 phím (≈ vuốt 20 phím/s lấy mẫu 60Hz) + rung 0.04 phím,
 * rồi đi qua [SwipePath] (lọc 1/5 phím) như bản tích hợp.
 */
class SwipeSim(seed: Long) {
    private var s = seed.toULong()
    private fun next(): ULong {
        s += 0x9E3779B97F4A7C15uL
        var z = s
        z = (z xor (z shr 30)) * 0xBF58476D1CE4E5B9uL
        z = (z xor (z shr 27)) * 0x94D049BB133111EBuL
        return z xor (z shr 31)
    }
    fun uniform(): Double = (next() shr 11).toDouble() * (1.0 / 9007199254740992.0)
    fun gauss(): Double {
        val u1 = max(uniform(), 1e-12); val u2 = uniform()
        return sqrt(-2 * ln(u1)) * cos(2 * PI * u2)
    }

    fun path(
        word: String, layout: SwipeLayout, sigma: Double = 0.25, endOffset: Double = 0.0,
        jitter: Double = 0.04, step: Double = 0.35,
    ): SwipePath {
        val w = layout.keyWidth.toDouble()
        val keys = collapse(word)
        val cx = DoubleArray(keys.length); val cy = DoubleArray(keys.length)
        for ((i, ch) in keys.withIndex()) {
            val c = layout.center(ch)!!
            cx[i] = c.first + gauss() * sigma * w
            cy[i] = c.second + gauss() * sigma * w
        }
        if (endOffset > 0) {
            var a = uniform() * 2 * PI
            cx[0] += cos(a) * endOffset * w; cy[0] += sin(a) * endOffset * w
            a = uniform() * 2 * PI
            val e = keys.length - 1
            cx[e] += cos(a) * endOffset * w; cy[e] += sin(a) * endOffset * w
        }
        val p = SwipePath(minDistance = layout.keyWidth / 5f)
        if (keys.length == 1) {
            repeat(4) { p.add((cx[0] + gauss() * jitter * w).toFloat(), (cy[0] + gauss() * jitter * w).toFloat(), it / 60.0) }
            return p
        }
        var t = 0.0
        val m = keys.length
        for (sgm in 0 until m - 1) {
            val i0 = max(sgm - 1, 0); val i1 = sgm; val i2 = sgm + 1; val i3 = minOf(sgm + 2, m - 1)
            val n = max(2, ceil(hypot(cx[i2] - cx[i1], cy[i2] - cy[i1]) / (step * w)).toInt())
            for (j in 0 until n) {
                val u = j.toDouble() / n
                val x = catmull(cx[i0], cx[i1], cx[i2], cx[i3], u) + gauss() * jitter * w
                val y = catmull(cy[i0], cy[i1], cy[i2], cy[i3], u) + gauss() * jitter * w
                p.add(x.toFloat(), y.toFloat(), t); t += 1 / 60.0
            }
        }
        p.add(cx[m - 1].toFloat(), cy[m - 1].toFloat(), t, force = true)
        return p
    }

    /**
     * Đường vuốt "TỰ NHIÊN" — hiệu chỉnh theo nét thật (45 nét iPhone từ Luyện vuốt, 28/09/2026,
     * docs/DATA-SOURCES.md "Nét vuốt thật"): lấy mẫu 60 Hz, giữ ngón ~50–120 ms ở phím đầu,
     * tốc độ đỉnh ~20–40 phím/s trên đoạn thẳng và CHẬM lại ở phím định đi qua (có khi dừng),
     * điểm đầu hơi lùi sau phím đầu, điểm cuối LỐ quá phím cuối theo hướng nét (trôi chậm
     * trước khi nhấc tay, trung vị ~0.45 phím). Toạ độ cùng hệ layout; t giây.
     */
    fun natural(word: String, layout: SwipeLayout, sigma: Double = 0.2, speed: Double = 1.0,
                overshoot: Double = 0.4): SwipePath {
        val w = layout.keyWidth.toDouble()
        val keys = collapse(word)
        val m = keys.length
        val p = SwipePath(minDistance = layout.keyWidth / 5f)
        val cx = DoubleArray(m); val cy = DoubleArray(m)
        for ((i, ch) in keys.withIndex()) {
            val c = layout.center(ch)!!
            cx[i] = c.first + gauss() * sigma * w
            cy[i] = c.second + gauss() * sigma * w
        }
        if (m == 1) {
            repeat(6) { p.add((cx[0] + gauss() * 0.03 * w).toFloat(), (cy[0] + gauss() * 0.03 * w).toFloat(), it / 60.0) }
            return p
        }
        // điểm đầu: lùi sau phím đầu theo hướng nét + lệch ngang
        var dx = cx[1] - cx[0]; var dy = cy[1] - cy[0]; var dn = max(1e-6, hypot(dx, dy))
        dx /= dn; dy /= dn
        val a0 = (gauss() * 0.22 - 0.15) * w; val b0 = gauss() * 0.25 * w
        val px = ArrayList<Double>(); val py = ArrayList<Double>()
        px.add(cx[0] + dx * a0 - dy * b0); py.add(cy[0] + dy * a0 + dx * b0)
        for (i in 1 until m) { px.add(cx[i]); py.add(cy[i]) }
        // điểm cuối: lố theo hướng nét cuối (trôi chậm) + lệch ngang
        dx = cx[m - 1] - cx[m - 2]; dy = cy[m - 1] - cy[m - 2]; dn = max(1e-6, hypot(dx, dy))
        dx /= dn; dy /= dn
        val o = max(-0.2, overshoot + gauss() * 0.4) * w; val b1 = gauss() * 0.3 * w
        val drift = o > 0.1 * w
        val lift = -0.15 * w   // nhấc tay hơi trượt lên (nét thật: dy cuối trung bình −0.4 phím)
        if (drift) { px.add(cx[m - 1] + dx * o - dy * b1); py.add(cy[m - 1] + dy * o + dx * b1 + lift) }
        else { px[m - 1] = cx[m - 1] + dx * o - dy * b1; py[m - 1] = cy[m - 1] + dy * o + dx * b1 + lift }
        // hình học: Catmull-Rom dày (0.05 phím) → độ dài cung s (phím)
        val gx = ArrayList<Double>(); val gy = ArrayList<Double>(); val gs = ArrayList<Double>()
        val via = DoubleArray(px.size)
        val q = px.size
        gx.add(px[0]); gy.add(py[0]); gs.add(0.0)
        for (sg in 0 until q - 1) {
            val i0 = max(sg - 1, 0); val i1 = sg; val i2 = sg + 1; val i3 = minOf(sg + 2, q - 1)
            val n = max(2, ceil(hypot(px[i2] - px[i1], py[i2] - py[i1]) / (0.05 * w)).toInt())
            for (j in 1..n) {
                val u = j.toDouble() / n
                val x = catmull(px[i0], px[i1], px[i2], px[i3], u); val y = catmull(py[i0], py[i1], py[i2], py[i3], u)
                gs.add(gs.last() + hypot(x - gx.last(), y - gy.last()) / w); gx.add(x); gy.add(y)
            }
            via[sg + 1] = gs.last()
        }
        val total = gs.last()
        // tốc độ (phím/s): đỉnh vPeak, trũng ρ ở phím đi qua (ρ nhỏ = chậm hẳn), đầu/cuối chậm
        val vPeak = 30.0 * speed * kotlin.math.exp(gauss() * 0.2)
        val rho = DoubleArray(q) { 0.05 + uniform() * 0.6 }
        rho[0] = 0.12; rho[m - 1] = 0.15
        val vDrift = 3.0 + uniform() * 5.0
        val ramp = 0.9
        fun v(s: Double): Double {
            var g = 1.0
            for (k in 0 until m) {
                val d = kotlin.math.abs(s - via[k])
                val gk = rho[k] + (1 - rho[k]) * kotlin.math.min(1.0, d / ramp)
                if (gk < g) g = gk
            }
            var vv = vPeak * g
            if (drift && s > via[m - 1]) vv = kotlin.math.min(vv, vDrift)
            return max(1.0, vv)
        }
        // dừng: giữ ngón ở phím đầu; đôi khi dừng ở phím giữa / phím cuối
        val pause = DoubleArray(q)
        pause[0] = 0.02 + uniform() * 0.06
        for (k in 1 until m - 1) if (uniform() < 0.35) pause[k] = 0.02 + uniform() * 0.08
        if (uniform() < 0.5) pause[m - 1] = 0.02 + uniform() * 0.06
        val dt = 1 / 60.0
        var t = 0.0; var s = 0.0; var gi = 0; var nextVia = 0
        val jit = 0.025 * w
        fun at(s: Double): Pair<Double, Double> {
            while (gi < gs.size - 2 && gs[gi + 1] < s) gi++
            val seg = gs[gi + 1] - gs[gi]
            val u = if (seg > 0) ((s - gs[gi]) / seg).coerceIn(0.0, 1.0) else 0.0
            return (gx[gi] + (gx[gi + 1] - gx[gi]) * u) to (gy[gi] + (gy[gi + 1] - gy[gi]) * u)
        }
        p.add(px[0].toFloat(), py[0].toFloat(), 0.0)
        while (s < total) {
            if (nextVia < m && s >= via[nextVia]) {
                var hold = pause[nextVia]
                while (hold > 0) {
                    t += dt; hold -= dt
                    val (x, y) = at(s)
                    p.add((x + gauss() * 0.3 * jit).toFloat(), (y + gauss() * 0.3 * jit).toFloat(), t)
                }
                nextVia++
                continue
            }
            val v1 = v(s); val v2 = v(s + v1 * dt * 0.5)
            s = kotlin.math.min(total, s + v2 * dt); t += dt
            val (x, y) = at(s)
            p.add((x + gauss() * jit).toFloat(), (y + gauss() * jit).toFloat(), t)
        }
        p.add(px[q - 1].toFloat(), py[q - 1].toFloat(), t + dt, force = true)
        return p
    }

    companion object {
        fun collapse(s: String): String {
            val b = StringBuilder()
            for (c in s) if (b.isEmpty() || b.last() != c) b.append(c)
            return b.toString()
        }
        private fun catmull(p0: Double, p1: Double, p2: Double, p3: Double, t: Double): Double {
            val t2 = t * t; val t3 = t2 * t
            return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
                (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
        }
    }
}

class SwipeDecoderTests {
    @Before fun setUp() = TestAssets.install()

    private val layout = SwipeLayout.qwerty(keyWidth = 40f, rowHeight = 54f)
    private fun decoder() = SwipeDecoder().also { it.setLayout(layout) }

    /** 500 dạng không dấu phổ biến nhất (≥ 2 phím sau gộp lặp) — cùng thứ tự bản Swift. */
    private fun corpus(n: Int = 500): List<String> {
        val f = SwipeLexicon.forms
        return (0 until f.count)
            .filter { SwipeSim.collapse(f.folded[it]).length >= 2 }
            .sortedWith(compareBy({ -f.freq[it] }, { f.folded[it] }))
            .take(n).map { f.folded[it] }
    }

    private fun accuracy(d: SwipeDecoder, words: List<String>, seed: Long, sigma: Double = 0.25,
                         endOffset: Double = 0.0): Pair<Double, Double> {
        val sim = SwipeSim(seed)
        var t1 = 0; var t3 = 0
        for (w in words) {
            val r = d.decode(sim.path(w, layout, sigma, endOffset), 3).map { it.folded }
            if (r.firstOrNull() == w) t1++
            if (w in r) t3++
        }
        return t1.toDouble() / words.size to t3.toDouble() / words.size
    }

    @Test fun lexiconForms() {
        val f = SwipeLexicon.forms
        assertEquals(1666, f.count)
        assertTrue(SwipeLexicon.indexOf("viet") >= 0)
        assertEquals(-1, SwipeLexicon.indexOf("zzz"))
        val i = SwipeLexicon.indexOf("boong")
        assertEquals("bong", (f.keyStart[i] until f.keyStart[i + 1]).map { ('a' + f.keys[it].toInt()) }.joinToString(""))
    }

    @Test fun accuracyTop500() {
        val d = decoder(); val words = corpus()
        val (a1, a3) = accuracy(d, words, 42)
        val (b1, b3) = accuracy(d, words, 7, sigma = 0.3)
        val (c1, c3) = accuracy(d, words, 42, endOffset = 0.5)
        println(String.format(Locale.ROOT,
            "SWIPE accuracy σ0.25: top1 %.3f top3 %.3f | σ0.3: %.3f/%.3f | lệch đầu/cuối 0.5: %.3f/%.3f",
            a1, a3, b1, b3, c1, c3))
        // đo 27/09/2026 (tầng 2 + kênh độ dài): 0.902/0.994 | 0.836/0.984 | 0.724/0.952
        // (trước: 0.900/0.996 | 0.824/0.978 | 0.684/0.914)
        assertTrue("top1 σ0.25 = $a1", a1 >= 0.85)
        assertTrue("top3 σ0.25 = $a3", a3 >= 0.98)
        assertTrue("top1 σ0.3 = $b1", b1 >= 0.80)
        assertTrue("top3 σ0.3 = $b3", b3 >= 0.96)
        assertTrue("top1 lệch = $c1", c1 >= 0.69)
        assertTrue("top3 lệch = $c3", c3 >= 0.93)
    }

    /** Tầng 2 (σ thích nghi + căn phím + góc) + kênh độ dài phải hơn SHARK2 trần ở ca khó. */
    @Test fun rescoreBeatsPlainShark2() {
        val plain = SwipeDecoder(SwipeDecoder.Params(rescorePool = 0, lengthWeight = 0f)).also { it.setLayout(layout) }
        val d = decoder(); val words = corpus()
        val (p1, _) = accuracy(plain, words, 42, endOffset = 0.5)
        val (n1, _) = accuracy(d, words, 42, endOffset = 0.5)
        val (q1, _) = accuracy(plain, words, 7, sigma = 0.3)
        val (m1, _) = accuracy(d, words, 7, sigma = 0.3)
        println(String.format(Locale.ROOT, "SWIPE tầng 2: lệch 0.5 %.3f → %.3f | σ0.3 %.3f → %.3f", p1, n1, q1, m1))
        assertTrue("lệch: $p1 → $n1", n1 >= p1 + 0.02)
        assertTrue("σ0.3: $q1 → $m1", m1 >= q1)
    }

    /** Đường của [words] dời cả nét (dx, dy) phím — người dùng có lệch tay hệ thống. */
    private fun biasedPaths(words: List<String>, seed: Long, dx: Float, dy: Float): List<SwipePath> {
        val sim = SwipeSim(seed)
        return words.map { w ->
            val p = sim.path(w, layout)
            val q = SwipePath(p.minDistance)
            for (i in 0 until p.count) q.add(p.xs[i] + dx * layout.keyWidth, p.ys[i] + dy * layout.keyWidth, p.ts[i], force = true)
            q
        }
    }

    private fun top1(d: SwipeDecoder, paths: List<SwipePath>, words: List<String>): Double =
        paths.indices.count { d.decode(paths[it], 1).firstOrNull()?.folded == words[it] }.toDouble() / words.size

    @Test fun learnOffsetConvergesAndHelps() {
        val d = decoder(); val words = corpus()
        val train = words.filterIndexed { i, _ -> i % 2 == 0 }; val test = words.filterIndexed { i, _ -> i % 2 == 1 }
        val trainPaths = biasedPaths(train, 5, 0.3f, 0.25f)
        val testPaths = biasedPaths(test, 6, 0.3f, 0.25f)
        val before = top1(d, testPaths, test)
        for ((i, p) in trainPaths.take(120).withIndex()) assertTrue(d.learnOffset(p, train[i]))
        val after = top1(d, testPaths, test)
        println(String.format(Locale.ROOT, "SWIPE học lệch (0.30, 0.25): học được (%.3f, %.3f), top1 %.3f → %.3f",
            d.offsetX, d.offsetY, before, after))
        assertEquals(0.3f, d.offsetX, 0.08f)
        assertEquals(0.25f, d.offsetY, 0.08f)
        assertTrue("$before → $after", after >= before + 0.05)
        // không lệch ⇒ học quanh 0 và không hại
        val u = decoder()
        val sim = SwipeSim(8)
        for (w in train.take(120)) u.learnOffset(sim.path(w, layout), w)
        assertTrue("lệch ảo (${u.offsetX}, ${u.offsetY})", kotlin.math.abs(u.offsetX) < 0.06f && kotlin.math.abs(u.offsetY) < 0.06f)
        // dạng lạ / đường 1 điểm ⇒ không học
        val p1 = SwipePath(1f); p1.add(10f, 10f, 0.0)
        assertTrue(!u.learnOffset(sim.path("viet", layout), "zzz"))
        assertTrue(!u.learnOffset(p1, "viet"))
    }

    /** Tỉ lệ (trên [n] đường nhiễu) mà [word] nằm trong top-[k]. */
    private fun hitRate(d: SwipeDecoder, word: String, k: Int, n: Int = 20, sigma: Double = 0.2,
                        endOffset: Double = 0.0): Double {
        val sim = SwipeSim(word.hashCode().toLong() and 0xFFFF)
        var hit = 0
        repeat(n) { if (word in d.decode(sim.path(word, layout, sigma, endOffset), k).map { it.folded }) hit++ }
        return hit.toDouble() / n
    }

    @Test fun vietExpandsToAccented() {
        val d = decoder()
        assertTrue(hitRate(d, "viet", 3) >= 0.9)
        val words = SwipeDecoder.expand("viet").map { it.word }
        assertTrue(words.take(3).containsAll(listOf("việt", "viết")))
        // bung "d" gồm cả đ
        assertTrue("đi" in SwipeDecoder.expand("di").map { it.word })
    }

    @Test fun hardPairsInTop3() {
        val d = decoder()
        for (w in listOf("cho", "co", "nay", "ngay", "trong", "truong", "bua", "nua")) {
            val r = hitRate(d, w, 3)
            assertTrue("$w top-3 rate $r", r >= 0.85)
        }
    }

    @Test fun repeatedLetters() {
        val d = decoder()
        assertTrue(hitRate(d, "luu", 3) >= 0.9)
        assertTrue(hitRate(d, "boong", 3) >= 0.85)
        assertEquals("lưu", SwipeDecoder.expand("luu").first().word)
    }

    @Test fun twoLetterWords() {
        val d = decoder()
        for (w in listOf("an", "em", "di", "la", "ta", "va", "de", "no")) {
            assertTrue("$w top-1 (đường sạch)", cleanTop(d, w, 1))
            assertTrue("$w top-3 nhiễu", hitRate(d, w, 3) >= 0.9)
        }
    }

    private fun cleanTop(d: SwipeDecoder, w: String, k: Int): Boolean {
        val p = SwipeSim(1).path(w, layout, sigma = 0.0, jitter = 0.0)
        return w in d.decode(p, k).map { it.folded }
    }

    @Test fun endpointsOffsetHalfKey() {
        val d = decoder()
        for (w in listOf("khong", "nguoi", "duoc", "viet", "chung")) {
            val r = hitRate(d, w, 3, sigma = 0.15, endOffset = 0.5)
            assertTrue("$w lệch nửa phím: $r", r >= 0.8)
        }
    }

    // ---- NHỊP (thời gian điểm vuốt) — lỗi nét thật 28/09/2026 ----

    private val legacy = SwipeDecoder.Params(speedWeight = 0f, dwellWeight = 0f, overshoot = 0f)

    /** Điểm dừng của [glide]: toạ độ (đơn vị phím, gốc = tâm [at]), tốc độ đi tới (phím/s), giữ (s). */
    private data class Stop(val at: Char, val dx: Float = 0f, val dy: Float = 0f, val speed: Float = 25f,
                            val hold: Double = 0.0)

    /** Đường vuốt tuyến tính qua [stops], lấy mẫu 60 Hz (như SwiftUI/MotionEvent), qua SwipePath. */
    private fun glide(vararg stops: Stop): SwipePath {
        val w = layout.keyWidth
        val p = SwipePath(minDistance = w / 5f)
        var t = 0.0
        fun xy(s: Stop): Pair<Float, Float> { val c = layout.center(s.at)!!; return (c.first + s.dx * w) to (c.second + s.dy * w) }
        var (x, y) = xy(stops[0])
        p.add(x, y, t)
        for ((k, s) in stops.withIndex()) {
            if (k > 0) {
                val (tx, ty) = xy(s)
                val d = hypot((tx - x).toDouble(), (ty - y).toDouble()) / w
                val n = max(1, ceil(d / s.speed * 60).toInt())
                for (j in 1..n) {
                    t += 1 / 60.0
                    p.add(x + (tx - x) * j / n, y + (ty - y) * j / n, t)
                }
                x = tx; y = ty
            }
            t += s.hold
        }
        p.add(x, y, t, force = true)
        return p
    }

    /** "đấy" ×3 trên iPhone ra "đâu": tới y rồi TRÔI chậm sang u trước khi nhấc tay. */
    @Test fun slowDriftPastLastKeyIsOvershoot() {
        val p = glide(Stop('d', hold = 0.08), Stop('a', hold = 0.1), Stop('y', dy = 0.1f, speed = 22f),
            Stop('y', dx = 0.65f, dy = -0.15f, speed = 3f))
        assertEquals("day", decoder().decode(p, 3).first().folded)
        // cùng đường nhưng không có thời gian (đường đều) ⇒ hành vi cũ
        assertEquals(SwipeDecoder(legacy).also { it.setLayout(layout) }.decode(p, 3),
            decoder().decode(p.xs, p.ys, p.count, 3))
    }

    /**
     * "cũng" ra "chung": lướt NHANH qua h trên đường thẳng c→u rồi dừng ở u — h không phải phím
     * định đi (nét thật: tốc độ tại phím lướt qua ≈ 2× trung bình, phím định đi ≈ 0.8×).
     */
    @Test fun fastPassThroughKeyIsNotInserted() {
        // gần như thẳng c→u: lướt nhanh sượt h 0.4 phím (nét thật "cũng": uốn về h ≈ 0)
        val p = glide(Stop('c', hold = 0.08), Stop('h', dx = -0.3f, dy = -0.28f, speed = 38f), Stop('u', speed = 30f, hold = 0.1),
            Stop('n', speed = 20f, hold = 0.06), Stop('g', speed = 15f, hold = 0.1))
        assertEquals("cung", decoder().decode(p, 3).first().folded)
        // dừng ở h ⇒ chung (phím có chủ đích)
        val q = glide(Stop('c', hold = 0.08), Stop('h', speed = 20f, hold = 0.1), Stop('u', speed = 20f, hold = 0.1),
            Stop('n', speed = 20f, hold = 0.06), Stop('g', speed = 15f, hold = 0.1))
        assertEquals("chung", decoder().decode(q, 3).first().folded)
    }

    /**
     * chưa/của (500 nét thật: chua→cua ×19/28): h của "ch" bị lướt NHANH như phím thường, không
     * chậm lại — thứ phân biệt là đường UỐN về h so với dây cung c→u ([SwipeDecoder.Params.bendWeight]).
     */
    @Test fun digraphHBendSeparatesChuaFromCua() {
        fun path(f: Float, last: Char = 'a') = glide(Stop('c', hold = 0.08),
            Stop('h', dx = -0.4f * f, dy = -0.37f * f, speed = 38f), Stop('u', speed = 30f, hold = 0.1),
            Stop(last, speed = 20f, hold = 0.1))
        assertEquals("chua", decoder().decode(path(0.25f), 3).first().folded)   // uốn về h, lướt nhanh
        assertEquals("cua", decoder().decode(path(1f), 3).first().folded)       // thẳng c→u
        // không uốn thì như cũ: tắt kênh uốn, đường qua h vẫn ra "cua" (tiền nghiệm của > chưa)
        val off = SwipeDecoder(SwipeDecoder.Params(bendWeight = 0f)).also { it.setLayout(layout) }
        assertEquals("cua", off.decode(path(0.25f), 3).first().folded)
        // chỉ đổi chỗ TRONG cặp: ứng viên thứ ba giữ nguyên vị trí tương đối
        val on = decoder().decode(path(0.25f), 5).map { it.folded }
        assertEquals(off.decode(path(0.25f), 5).map { it.folded }.filter { it != "chua" && it != "cua" },
            on.filter { it != "chua" && it != "cua" })
    }

    /** Đường "tự nhiên" (nhịp + lố như nét thật): nhịp phải tăng rõ top-1, đường đều không tụt. */
    @Test fun timingHelpsNaturalPaths() {
        val words = corpus(300)
        val d = decoder(); val old = SwipeDecoder(legacy).also { it.setLayout(layout) }
        fun acc(dec: SwipeDecoder, natural: Boolean): Double {
            val sim = SwipeSim(404)
            return words.count { w ->
                val p = if (natural) sim.natural(w, layout) else sim.path(w, layout)
                dec.decode(p, 3).firstOrNull()?.folded == w
            }.toDouble() / words.size
        }
        val (n0, n1) = acc(old, true) to acc(d, true)
        val (o0, o1) = acc(old, false) to acc(d, false)
        println(String.format(Locale.ROOT, "SWIPE nhịp: đường tự nhiên top1 %.3f → %.3f | đường đều %.3f → %.3f", n0, n1, o0, o1))
        assertTrue("tự nhiên $n0 → $n1", n1 >= n0 + 0.04)
        assertTrue("đều $o0 → $o1", o1 >= o0 - 0.01)
    }

    @Test fun contextReranks() {
        val d = decoder()
        val p = SwipeSim(3).path("cho", layout, sigma = 0.0, jitter = 0.0)
        val plain = d.decode(p, 3).map { it.folded }
        assertEquals("co", plain.first())   // c-h-o thẳng hàng: hình học không phân biệt được
        val ctx = d.decode(p, 3) { if (it == "cho") 3f else 0f }
        assertEquals("cho", ctx.first().folded)
        val e = SwipeDecoder.expand("cho") { if (it == "chó") 5f else 0f }
        assertEquals("chó", e.first().word)
    }

    @Test fun layoutChangeRebuildsAndOtherLayoutWorks() {
        val d = decoder()
        d.decode(SwipeSim(5).path("khong", layout), 1)
        assertTrue("RAM template ${d.templateBytes}", d.templateBytes in 1..1_000_000)
        // Android-ish: phím hẹp, hàng cao, gốc lệch
        val l2 = SwipeLayout.qwerty(keyWidth = 36f, rowHeight = 58f, originX = 3f, originY = 10f)
        d.setLayout(l2)
        assertEquals(0, d.templateBytes)
        val sim = SwipeSim(9); var ok = 0
        val words = corpus(100)
        for (w in words) if (d.decode(sim.path(w, l2), 3).any { it.folded == w }) ok++
        assertTrue("top3 layout 2 = $ok/100", ok >= 95)
    }

    @Test fun swipePathFiltersAndCaps() {
        val p = SwipePath(minDistance = 8f, capacity = 4)
        assertTrue(p.add(0f, 0f, 0.0))
        assertTrue(!p.add(3f, 4f, 0.01))          // 5 < 8
        assertTrue(p.add(6f, 8f, 0.02))           // 10
        assertEquals(2, p.count); assertEquals(10f, p.length, 1e-4f)
        assertTrue(p.add(7f, 8f, 0.03, force = true))
        assertEquals(3, p.count)
        p.add(20f, 8f, 0.04); assertEquals(4, p.count)
        p.add(40f, 8f, 0.05)                        // đầy → ghi đè điểm cuối
        assertEquals(4, p.count); assertEquals(40f, p.xs[3]); assertEquals(44f, p.length, 1e-3f)  // 10+1+33
        assertEquals(0.05, p.duration, 1e-9)
        p.reset(); assertEquals(0, p.count)
        assertTrue(SwipeDecoder().decode(p).isEmpty())
    }

    @Test fun benchmark() {
        SlowTests.assume()
        val d = decoder()
        val t0 = System.nanoTime(); d.prepare(); val build = (System.nanoTime() - t0) / 1e6
        val sim = SwipeSim(11)
        val paths = corpus(200).map { sim.path(it, layout) }
        val plain = SwipeDecoder(SwipeDecoder.Params(rescorePool = 0, lengthWeight = 0f)).also { it.setLayout(layout); it.prepare() }
        repeat(5) { for (p in paths) { d.decode(p, 5); plain.decode(p, 5) } }   // hâm JIT
        val t1 = System.nanoTime()
        repeat(5) { for (p in paths) d.decode(p, 5) }
        val per = (System.nanoTime() - t1) / 1e6 / paths.size / 5
        val t2 = System.nanoTime()
        repeat(5) { for (p in paths) plain.decode(p, 5) }
        val perPlain = (System.nanoTime() - t2) / 1e6 / paths.size / 5
        println(String.format(Locale.ROOT, "SWIPE benchmark JVM: dựng template %.1f ms, decode %.3f ms/đường " +
            "(SHARK2 trần %.3f), RAM template %d B", build, per, perPlain, d.templateBytes))
        assertTrue("decode $per ms", per < 5.0)
        // nhịp (28/09/2026): đường tự nhiên CÓ thời gian, so với cùng decoder tắt nhịp — xen kẽ
        // nhiều vòng, lấy trung vị (máy dev dao động)
        val old = SwipeDecoder(legacy).also { it.setLayout(layout); it.prepare() }
        val nsim = SwipeSim(12)
        val nat = corpus(200).map { nsim.natural(it, layout) }
        repeat(5) { for (p in nat) { d.decode(p, 5); old.decode(p, 5) } }
        val tn = ArrayList<Double>(); val to = ArrayList<Double>()
        repeat(9) {
            var t = System.nanoTime(); for (p in nat) d.decode(p, 5); tn.add((System.nanoTime() - t) / 1e6 / nat.size)
            t = System.nanoTime(); for (p in nat) old.decode(p, 5); to.add((System.nanoTime() - t) / 1e6 / nat.size)
        }
        val mn = tn.sorted()[4]; val mo = to.sorted()[4]
        println(String.format(Locale.ROOT, "SWIPE benchmark nhịp: %.4f ms/đường (tắt nhịp %.4f, %+.1f%%)", mn, mo, (mn / mo - 1) * 100))
        assertTrue("nhịp chậm quá: $mn vs $mo ms", mn <= mo * 1.2 + 0.01)
        // uốn h của phụ âm ghép (28/09/2026, 500 nét thật): bật vs tắt, trần +10 %
        val nob = SwipeDecoder(SwipeDecoder.Params(bendWeight = 0f)).also { it.setLayout(layout); it.prepare() }
        repeat(5) { for (p in nat) nob.decode(p, 5) }
        val tb = ArrayList<Double>(); val tnb = ArrayList<Double>()
        repeat(9) {
            var t = System.nanoTime(); for (p in nat) d.decode(p, 5); tb.add((System.nanoTime() - t) / 1e6 / nat.size)
            t = System.nanoTime(); for (p in nat) nob.decode(p, 5); tnb.add((System.nanoTime() - t) / 1e6 / nat.size)
        }
        val mb = tb.sorted()[4]; val mnb = tnb.sorted()[4]
        println(String.format(Locale.ROOT, "SWIPE benchmark uốn h: %.4f ms/đường (tắt %.4f, %+.1f%%)", mb, mnb, (mb / mnb - 1) * 100))
        assertTrue("uốn h chậm quá: $mb vs $mnb ms", mb <= mnb * 1.1 + 0.005)
    }

    // ---- Fixture parity Swift ↔ Kotlin ----

    private fun timedFixtureFile(): File =
        listOf("../../iOS", "../iOS", "iOS").map { File(it, "KeyboardTests/Fixtures/swipe-paths-timed.txt") }
            .firstOrNull { it.parentFile.exists() } ?: error("không thấy iOS/KeyboardTests/Fixtures")

    private fun timedPrior(tag: String): SwipeEnglishPrior? = when (tag) {
        "vi" -> SwipeLangContext.DEFAULT
        "en" -> SwipeLangContext.ENGLISH
        else -> null
    }

    /**
     * Parity phần NHỊP (thời gian điểm): đường "tự nhiên" x,y,t(ms). Ghi lại:
     * SWIPE_WRITE_FIXTURE=1 ./gradlew :keyboard:test --tests '*SwipeDecoderTests.timedFixtureParity'.
     */
    @Test fun timedFixtureParity() {
        val d = decoder()
        val file = timedFixtureFile()
        if (System.getenv("SWIPE_WRITE_FIXTURE") == "1") {
            val sim = SwipeSim(2028)
            val sb = StringBuilder("# swipe-paths-timed v1 — layout qwerty(keyWidth 40, rowHeight 54), SwipeSim.natural. " +
                "Sinh bởi SwipeDecoderTests.kt (SWIPE_WRITE_FIXTURE=1). word<TAB>prior none|vi|en<TAB>top1 lang:word<TAB>x,y,ms;…\n")
            val en = SwipeEnglish.lexicon.let { e -> (0 until e.count).sortedByDescending { e.freq(it) }.map { e.word(it) } }
                .filter { it.length >= 3 }.take(30)
            val cases = corpus(120).map { it to "none" } + corpus(160).drop(120).map { it to "vi" } +
                listOf("day", "lay", "thay", "vi", "cung", "hoi", "trai", "the", "nay", "du", "nhu").map { it to "vi" } +
                en.map { it to "en" }
            for ((w, tag) in cases) {
                val p = sim.natural(w, layout)
                val xs = FloatArray(p.count) { String.format(Locale.ROOT, "%.2f", p.xs[it]).toFloat() }
                val ys = FloatArray(p.count) { String.format(Locale.ROOT, "%.2f", p.ys[it]).toFloat() }
                val ms = (0 until p.count).map { String.format(Locale.ROOT, "%.1f", (p.ts[it] - p.ts[0]) * 1000) }
                val ts = DoubleArray(p.count) { ms[it].toDouble() / 1000.0 }
                val top = d.decode(xs, ys, p.count, 3, null, timedPrior(tag), null, ts).first()
                sb.append(w).append('\t').append(tag).append('\t')
                    .append(if (top.lang == SwipeLang.EN) "en:" else "vi:").append(top.folded).append('\t')
                for (i in 0 until p.count) {
                    if (i > 0) sb.append(';')
                    sb.append(String.format(Locale.ROOT, "%.2f,%.2f,", xs[i], ys[i])).append(ms[i])
                }
                sb.append('\n')
            }
            file.writeText(sb.toString())
        }
        var n = 0; var same = 0; var right = 0
        for (line in file.readLines()) {
            if (line.startsWith("#") || line.isBlank()) continue
            val (w, tag, top, pts) = line.split('\t')
            val pp = pts.split(';').map { it.split(',') }
            val xs = FloatArray(pp.size) { pp[it][0].toFloat() }
            val ys = FloatArray(pp.size) { pp[it][1].toFloat() }
            val ts = DoubleArray(pp.size) { pp[it][2].toDouble() / 1000.0 }
            n++
            val r = d.decode(xs, ys, xs.size, 3, null, timedPrior(tag), null, ts).first()
            if ((if (r.lang == SwipeLang.EN) "en:" else "vi:") + r.folded == top) same++
            if (r.folded == w) right++
        }
        assertTrue(n >= 190)
        assertEquals("top-1 khớp fixture", n, same)
        assertTrue("đúng $right/$n", right >= n * 0.8)
    }

    private fun fixtureFile(): File =
        listOf("../../iOS", "../iOS", "iOS").map { File(it, "KeyboardTests/Fixtures/swipe-paths.txt") }
            .firstOrNull { it.parentFile.exists() } ?: error("không thấy iOS/KeyboardTests/Fixtures")

    /** Ghi lại fixture: SWIPE_WRITE_FIXTURE=1 ./gradlew :keyboard:test --tests '*SwipeDecoderTests*'. */
    @Test fun fixtureParity() {
        val d = decoder()
        val file = fixtureFile()
        if (System.getenv("SWIPE_WRITE_FIXTURE") == "1") {
            val sim = SwipeSim(2026)
            val sb = StringBuilder("# swipe-paths v1 — layout qwerty(keyWidth 40, rowHeight 54). " +
                "Sinh bởi SwipeDecoderTests.kt (SWIPE_WRITE_FIXTURE=1). word<TAB>top1 Kotlin<TAB>x,y;x,y…\n")
            val words = corpus(150).map { it to 0.0 } +
                listOf("viet", "cho", "co", "nay", "ngay", "trong", "truong", "bua", "nua", "luu", "boong",
                    "khong", "nguoi", "duoc").map { it to 0.5 }
            for ((w, off) in words) {
                val p = sim.path(w, layout, 0.25, off)
                // làm tròn 2 số lẻ TRƯỚC khi decode — y như bên đọc fixture
                val xs = FloatArray(p.count) { String.format(Locale.ROOT, "%.2f", p.xs[it]).toFloat() }
                val ys = FloatArray(p.count) { String.format(Locale.ROOT, "%.2f", p.ys[it]).toFloat() }
                val top = d.decode(xs, ys, p.count, 1).first().folded
                sb.append(w).append('\t').append(top).append('\t')
                for (i in 0 until p.count) {
                    if (i > 0) sb.append(';')
                    sb.append(String.format(Locale.ROOT, "%.2f,%.2f", xs[i], ys[i]))
                }
                sb.append('\n')
            }
            file.writeText(sb.toString())
        }
        var n = 0; var same = 0
        for (line in file.readLines()) {
            if (line.startsWith("#") || line.isBlank()) continue
            val (_, top, pts) = line.split('\t')
            val pp = pts.split(';').map { it.split(',') }
            val xs = FloatArray(pp.size) { pp[it][0].toFloat() }
            val ys = FloatArray(pp.size) { pp[it][1].toFloat() }
            n++
            if (d.decode(xs, ys, xs.size, 1).first().folded == top) same++
        }
        assertTrue(n >= 150)
        assertEquals("top-1 khớp fixture", n, same)
    }
}
