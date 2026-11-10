package com.viettelex.keyboard

import org.junit.Before
import org.junit.Test
import java.io.File
import java.util.Locale

/**
 * ĐO FUTO Swipe (thử nghiệm) vs SHARK2 vs ensemble — bộ chậm (VT_SLOW_TESTS=1). In bảng số;
 * docs/DATA-SOURCES.md mục FUTO Swipe ghi lại kết quả. Hai kiểu đường giả:
 *  - "đều": SwipeSim hiện có (tốc độ không đổi — KHÔNG có nhịp chậm ở phím);
 *  - "nhịp": FutoSim (minimum-jerk, chậm dần tới phím như tay thật).
 * Model FUTO học từ vuốt THẬT tiếng Anh; cả hai kiểu đều là giả nên số có thể lệch thật.
 */
class FutoSwipeEvalTests {
    @Before fun setUp() = TestAssets.install()

    private val layout = FutoSwipeTests.layout

    private fun heldout(): List<List<String>> {
        val f = listOf("../../iOS", "../iOS", "iOS").map { File(it, "KeyboardTests/Fixtures/bigram-heldout.txt") }
            .firstOrNull { it.exists() } ?: error("không thấy bigram-heldout.txt")
        return f.readLines().filter { it.isNotBlank() && !it.startsWith("#") }.map { it.split(' ') }
    }

    data class Acc(var n: Int = 0, var f1: Int = 0, var t1: Int = 0, var t3: Int = 0, var ms: Double = 0.0) {
        fun fmt() = String.format(Locale.ROOT, "không dấu top1 %.3f | có dấu top1 %.3f top3 %.3f (n=%d, %.2f ms)",
            f1.toDouble() / n, t1.toDouble() / n, t3.toDouble() / n, n, ms / maxOf(1, n))
        val top1: Double get() = t1.toDouble() / n
    }

    private fun path(realistic: Boolean, sim: SwipeSim, fsim: FutoSim, w: String): SwipePath =
        if (realistic) fsim.path(w, layout) else sim.path(w, layout)

    /** Cấu hình decoder: null mode = SHARK2. */
    data class Cfg(val name: String, val mode: FutoSwipe.Mode?, val a: Float = 0.5f, val beta: Float = 0.25f)

    /**
     * Câu giữ lại (chuỗi [chains]) — y như SyllableLMTests.measure (LM trigram); mọi cấu hình
     * chấm trên CÙNG đường vuốt (encoder chạy 1 lần/đường).
     */
    private fun sentences(chains: List<List<String>>, cfgs: List<Cfg>, realistic: Boolean, fs: FutoSwipe,
                          english: Boolean = false, seed: Long = 2027): List<Acc> {
        val d = SwipeDecoder().also { it.setLayout(layout) }
        val sim = SwipeSim(seed); val fsim = FutoSim(seed)
        val accs = cfgs.map { Acc() }
        for (chain in chains) for (i in 1 until chain.size) {
            val w = chain[i]
            val p = path(realistic, sim, fsim, SwipeSuggest.fold(w))
            val prior = if (english) SwipeLangContext.prior(SwipeLangContext.classify(chain[i - 1]),
                SwipeLangContext.classify(chain.getOrNull(i - 2))) else null
            val ctx = SwipeSuggest.context(null, chain[i - 1], chain.getOrNull(i - 2), prior)
            var first = true
            for ((k, cfg) in cfgs.withIndex()) {
                val acc = accs[k]
                val t0 = System.nanoTime()
                val cands = if (cfg.mode == null) {
                    d.decode(p, SwipeSuggest.TOP_K, ctx.folded, ctx.english, ctx.englishWord)
                } else {
                    fs.params.mode = cfg.mode; fs.params.acousticWeight = cfg.a; fs.params.ensembleWeight = cfg.beta
                    val r = fs.decode(p, SwipeSuggest.TOP_K, ctx.folded, ctx.english, ctx.englishWord, d,
                        reuseEmissions = !first)!!
                    first = false
                    r
                }
                acc.ms += (System.nanoTime() - t0) / 1e6
                val c = SwipeSuggest.choose(cands, ctx.word, lambdaFreq = ctx.lambdaFreq) ?: continue
                acc.n++
                if (cands.firstOrNull()?.folded == SwipeSuggest.fold(w)) acc.f1++
                if (c.word == w) acc.t1++
                if (c.word == w || w in c.alternatives.take(2)) acc.t3++
            }
        }
        return accs
    }

    private fun futo(mode: FutoSwipe.Mode, beta: Float = FutoSwipe.Params().ensembleWeight, a: Float = 0.5f) =
        FutoSwipe { KeyboardData.buffer(Keys.ASSET_FUTO) }.also {
            it.setLayout(layout); it.load()
            it.params.mode = mode; it.params.ensembleWeight = beta; it.params.acousticWeight = a
        }

    /** Tune trên dev (chuỗi %12==0), báo trên test (%12==6) — tập giữ lại, không dựng LM. */
    @Test fun heldoutSentences() {
        SlowTests.assume()
        val all = heldout()
        val dev = all.filterIndexed { i, _ -> i % 12 == 0 }
        val test = all.filterIndexed { i, _ -> i % 12 == 6 }
        val grid = listOf(Cfg("SHARK2", null)) +
            listOf(0.25f, 0.5f, 1f, 2f).map { Cfg("FUTO A=$it", FutoSwipe.Mode.FUTO, a = it) } +
            listOf(0.1f, 0.25f, 0.5f, 1f).map { Cfg("ENSEMBLE β=$it", FutoSwipe.Mode.ENSEMBLE, beta = it) }
        val fs = futo(FutoSwipe.Mode.FUTO)
        for (realistic in listOf(true, false)) {
            val tag = if (realistic) "nhịp" else "đều"
            val r = sentences(dev, grid, realistic, fs)
            for ((k, c) in grid.withIndex()) println("[$tag] DEV ${c.name.padEnd(14)} ${r[k].fmt()}")
            val bestF = grid.indices.filter { grid[it].mode == FutoSwipe.Mode.FUTO }.maxBy { r[it].top1 }
            val bestE = grid.indices.filter { grid[it].mode == FutoSwipe.Mode.ENSEMBLE }.maxBy { r[it].top1 }
            val pick = listOf(grid[0], grid[bestF], grid[bestE])
            val rt = sentences(test, pick, realistic, fs)
            for ((k, c) in pick.withIndex()) println("[$tag] TEST ${c.name.padEnd(14)} ${rt[k].fmt()}")
            // ngưỡng hồi quy: ensemble với β mặc định không tụt quá 1 điểm so với SHARK2 (cả hai kiểu đường)
            val def = sentences(test, listOf(Cfg("ENSEMBLE mặc định", FutoSwipe.Mode.ENSEMBLE,
                beta = FutoSwipe.Params().ensembleWeight)), realistic, fs)[0]
            println("[$tag] TEST ENSEMBLE mặc định ${def.fmt()}")
            org.junit.Assert.assertTrue("[$tag] ensemble ${def.fmt()} vs SHARK2 ${rt[0].fmt()}", def.top1 >= rt[0].top1 - 0.01)
            val re = sentences(test.filterIndexed { i, _ -> i % 2 == 0 }, pick, realistic, fs, english = true)
            for ((k, c) in pick.withIndex()) println("[$tag] TEST+EN ${c.name.padEnd(14)} ${re[k].fmt()}")
        }
    }

    /** Từ rời (không ngữ cảnh): theo độ dài; tiếng Anh; lỗi greedy (thiên lệch tiền nghiệm Anh?). */
    @Test fun isolatedWordsAndBias() {
        SlowTests.assume()
        val forms = SwipeLexicon.forms
        val vn = (0 until forms.count).filter { SwipeSim.collapse(forms.folded[it]).length >= 2 }
            .sortedWith(compareBy({ -forms.freq[it] }, { forms.folded[it] })).take(500).map { forms.folded[it] }
        val e = SwipeEnglish.lexicon
        val en = (0 until e.count).filter { SwipeSim.collapse(e.word(it)).length >= 2 }
            .sortedWith(compareBy({ -e.freq(it) }, { e.word(it) })).take(500).map { e.word(it) }
        val shark = SwipeDecoder().also { it.setLayout(layout) }
        for (realistic in listOf(true, false)) {
            val tag = if (realistic) "nhịp" else "đều"
            for ((name, mode) in listOf("SHARK2" to null, "FUTO" to FutoSwipe.Mode.FUTO, "ENSEMBLE" to FutoSwipe.Mode.ENSEMBLE)) {
                val fs = mode?.let { futo(it) }
                // Việt theo độ dài dạng gộp
                val byLen = HashMap<Int, IntArray>()
                val sim = SwipeSim(42); val fsim = FutoSim(42)
                for (w in vn) {
                    val p = path(realistic, sim, fsim, w)
                    val r = fs?.decode(p, 3, null, null, null, shark) ?: shark.decode(p, 3)
                    val b = byLen.getOrPut(minOf(SwipeSim.collapse(w).length, 5)) { IntArray(3) }
                    b[0]++
                    if (r.firstOrNull()?.folded == w) b[1]++
                    if (r.any { it.folded == w }) b[2]++
                }
                val vnS = byLen.toSortedMap().entries.joinToString(" ") { (l, b) ->
                    String.format(Locale.ROOT, "len%s:%.2f/%.2f", if (l == 5) "5+" else "$l", b[1].toDouble() / b[0], b[2].toDouble() / b[0])
                }
                // tiếng Anh (prior ENGLISH — đang gõ tiếng Anh)
                var t1 = 0; var t3 = 0
                val sim2 = SwipeSim(43); val fsim2 = FutoSim(43)
                for (w in en) {
                    val p = path(realistic, sim2, fsim2, w)
                    val r = fs?.decode(p, 3, null, SwipeLangContext.ENGLISH, null, shark)
                        ?: shark.decode(p, 3, null, SwipeLangContext.ENGLISH)
                    if (r.firstOrNull()?.let { it.lang == SwipeLang.EN && it.folded == w } == true) t1++
                    if (r.any { it.lang == SwipeLang.EN && it.folded == w }) t3++
                }
                println(String.format(Locale.ROOT, "[%s] %-8s VN top1/top3 %s | EN top1 %.3f top3 %.3f", tag, name, vnS,
                    t1.toDouble() / en.size, t3.toDouble() / en.size))
            }
            // thiên lệch tiền nghiệm: greedy CTC (không từ điển) — tỉ lệ lỗi ký tự Việt vs Anh cùng độ dài
            val fs = futo(FutoSwipe.Mode.FUTO)
            for ((name, words) in listOf("VN" to vn, "EN" to en)) {
                val sim = SwipeSim(44); val fsim = FutoSim(44)
                val errs = HashMap<Int, DoubleArray>()
                val dropped = HashMap<String, Int>()
                for (w in words) {
                    val p = path(realistic, sim, fsim, w)
                    fs.computeEmissions(p.xs, p.ys, p.ts, p.count)
                    val g = FutoSwipeTests.greedy(fs.emissions(), 26)
                    val ref = SwipeSim.collapse(w)
                    val a = errs.getOrPut(minOf(ref.length, 6)) { DoubleArray(2) }
                    a[0] += editDistance(g, ref).toDouble(); a[1] += ref.length.toDouble()
                    for (k in 0 until ref.length - 1) {
                        val bg = ref.substring(k, k + 2)
                        if (!SwipeSim.collapse(g).contains(bg)) dropped[bg] = (dropped[bg] ?: 0) + 1
                    }
                }
                println("[$tag] greedy CER $name: " + errs.toSortedMap().entries.joinToString(" ") { (l, a) ->
                    String.format(Locale.ROOT, "len%d:%.3f", l, a[0] / a[1]) } +
                    " | cặp chữ hay mất: " + dropped.entries.sortedByDescending { it.value }.take(8).joinToString(" ") { "${it.key}×${it.value}" })
            }
        }
    }

    @Test fun latency() {
        SlowTests.assume()
        val fs = futo(FutoSwipe.Mode.ENSEMBLE)
        val shark = SwipeDecoder().also { it.setLayout(layout); it.prepare() }
        val fsim = FutoSim(5)
        val words = listOf("khong", "nguoi", "duoc", "thuong", "viet", "anh", "chung", "nghieng")
        val paths = words.map { fsim.path(it, layout) }
        repeat(30) { for (p in paths) fs.decode(p, 5, null, null, null, shark) } // JIT
        var model = 0.0; var total = 0.0; var sharkMs = 0.0; var n = 0
        repeat(20) {
            for (p in paths) {
                val t0 = System.nanoTime(); shark.decode(p, 16); sharkMs += (System.nanoTime() - t0) / 1e6
                val t1 = System.nanoTime(); fs.decode(p, 5, null, null, null, shark); total += (System.nanoTime() - t1) / 1e6
                model += fs.lastModelMs; n++
            }
        }
        fs.params.mode = FutoSwipe.Mode.FUTO
        var alone = 0.0
        val en = SwipeEnglish.lexicon
        repeat(20) { for (p in paths) { val t = System.nanoTime(); fs.decode(p, 5, null, SwipeLangContext.DEFAULT, null, shark); alone += (System.nanoTime() - t) / 1e6 } }
        println(String.format(Locale.ROOT, "FUTO JVM: encoder %.2f ms | ensemble tổng %.2f ms (SHARK2 riêng %.2f ms) | FUTO+EN 20k tìm kiếm %.2f ms (en=%d)",
            model / n, total / n, sharkMs / n, alone / n, en.count))
    }

    private fun editDistance(a: String, b: String): Int {
        val d = IntArray(b.length + 1) { it }
        for (i in 1..a.length) {
            var prev = d[0]; d[0] = i
            for (j in 1..b.length) {
                val tmp = d[j]
                d[j] = minOf(d[j] + 1, d[j - 1] + 1, prev + if (a[i - 1] == b[j - 1]) 0 else 1)
                prev = tmp
            }
        }
        return d[b.length]
    }
}
