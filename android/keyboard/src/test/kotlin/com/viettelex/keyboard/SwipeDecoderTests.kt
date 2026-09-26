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
        assertTrue("top1 σ0.25 = $a1", a1 >= 0.85)
        assertTrue("top3 σ0.25 = $a3", a3 >= 0.98)
        assertTrue("top1 σ0.3 = $b1", b1 >= 0.78)
        assertTrue("top3 σ0.3 = $b3", b3 >= 0.95)
        assertTrue("top1 lệch = $c1", c1 >= 0.62)
        assertTrue("top3 lệch = $c3", c3 >= 0.88)
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
        val d = decoder()
        val t0 = System.nanoTime(); d.prepare(); val build = (System.nanoTime() - t0) / 1e6
        val sim = SwipeSim(11)
        val paths = corpus(200).map { sim.path(it, layout) }
        repeat(3) { for (p in paths) d.decode(p, 5) }   // hâm JIT
        val t1 = System.nanoTime()
        for (p in paths) d.decode(p, 5)
        val per = (System.nanoTime() - t1) / 1e6 / paths.size
        println(String.format(Locale.ROOT, "SWIPE benchmark JVM: dựng template %.1f ms, decode %.3f ms/đường, RAM template %d B",
            build, per, d.templateBytes))
        assertTrue("decode $per ms", per < 5.0)
    }

    // ---- Fixture parity Swift ↔ Kotlin ----

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
