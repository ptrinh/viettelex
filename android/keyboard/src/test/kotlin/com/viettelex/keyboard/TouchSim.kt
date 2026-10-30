package com.viettelex.keyboard

import com.viettelex.telexcore.TelexEngine
import java.io.File
import java.util.Random
import kotlin.math.sqrt

/**
 * MÔ PHỎNG GÕ CHẠM cho đo chọn phím (TouchSimTests). Câu Tatoeba giữ lại
 * (iOS/KeyboardTests/Fixtures/bigram-heldout.txt) → chuỗi phím Telex (TelexSpell, kiểm
 * bằng engine thật) → điểm chạm Gaussian 2D quanh tâm phím + lệch hệ thống (Henze 2012:
 * chạm thấp hơn tâm; Azenkot & Zhai 2012: σ ≈ 1 mm ≈ 0.15–0.3 phím) → router → engine.
 */
object TouchSim {
    /** Đơn vị σ/lệch của người gõ (pt) — cố định theo ngón tay, không theo cỡ phím. */
    const val UNIT = 40f

    /** Hình học QWERTY (pt). Mặc định iPhone dọc: bước phím 40, mặt 34; hàng 54, mặt 42. */
    class Geo(val pitchX: Float = 40f, val faceW: Float = 34f, val pitchY: Float = 54f, val faceH: Float = 42f, val name: String = "iPhone dọc") {
        val rects = ArrayList<KRect>()
        val keys: CharArray
        val index = IntArray(26) { -1 }
        val rowOf = IntArray(26)
        init {
            val rows = listOf("qwertyuiop" to 0f, "asdfghjkl" to 0.5f, "zxcvbnm" to 1.5f)
            val ks = StringBuilder()
            for ((r, row) in rows.withIndex()) for ((i, c) in row.first.withIndex()) {
                val cx = (row.second + i + 0.5f) * pitchX
                val cy = (r + 0.5f) * pitchY
                index[c - 'a'] = rects.size
                rowOf[rects.size] = r
                rects.add(KRect(cx - faceW / 2, cy - faceH / 2, cx + faceW / 2, cy + faceH / 2))
                ks.append(c)
            }
            keys = ks.toString().toCharArray()
        }
        fun center(i: Int) = KPoint((rects[i].left + rects[i].right) / 2, (rects[i].top + rects[i].bottom) / 2)
        val width get() = 10 * pitchX
    }

    /**
     * Người gõ: σ theo bước phím ngang (pitchX); bias (pt đơn vị bước phím) cộng vào mọi chạm;
     * [pull]: lệch ngang theo vị trí — phím mép bị kéo về giữa (âm) / ra ngoài (dương).
     */
    data class Profile(val name: String, val sx: Float, val sy: Float, val bx: Float = 0f, val by: Float = 0f, val pull: Float = 0f)

    val PROFILES = listOf(
        Profile("cẩn thận  σ.15", 0.15f, 0.15f, by = 0.10f),
        Profile("vừa       σ.22", 0.22f, 0.27f, by = 0.12f),
        Profile("nhanh     σ.30", 0.30f, 0.36f, by = 0.15f),
        Profile("lệch phải σ.22", 0.22f, 0.27f, bx = 0.20f, by = 0.25f),
        Profile("lệch giữa σ.22", 0.22f, 0.27f, by = 0.20f, pull = -0.20f),
    )

    fun tap(g: Geo, key: Int, pr: Profile, rng: Random): KPoint {
        val c = g.center(key)
        val rel = (c.x - g.width / 2) / (g.width / 2)
        val x = c.x + UNIT * (pr.bx + pr.pull * rel + pr.sx * rng.nextGaussian().toFloat())
        val y = c.y + UNIT * (pr.by + pr.sy * rng.nextGaussian().toFloat())
        return KPoint(x, y)
    }

    fun engine() = TelexEngine().apply {
        freeMarking = true; simpleTelex = true; liveSpellCheck = true
        quickTelex = false; modernTone = false; teencode = false
    }

    fun compose(raw: String): String {
        val e = engine()
        for (ch in raw) e.feed(ch)
        return SyllableLM.normalize(e.composed)
    }

    fun heldout(): List<List<String>> {
        val f = listOf("../../iOS", "../iOS", "iOS").map { File(it, "KeyboardTests/Fixtures/bigram-heldout.txt") }
            .firstOrNull { it.exists() } ?: error("không thấy bigram-heldout.txt")
        return f.readLines().filter { it.isNotBlank() && !it.startsWith("#") }.map { it.trim().split(" ") }
    }

    private val validCache = HashMap<String, List<Pair<String, Float>>>()
    /** Biến thể gõ Telex HỢP LỆ (engine ra đúng âm tiết). */
    fun validVariants(s: String): List<Pair<String, Float>> = validCache.getOrPut(s) {
        val want = SyllableLM.normalize(s)
        TelexSpell.variants(s).orEmpty().filter { compose(it.first) == want }
    }

    fun pickVariant(s: String, rng: Random): String? {
        val v = validVariants(s)
        if (v.isEmpty()) return null
        val tot = v.sumOf { it.second.toDouble() }
        var r = rng.nextDouble() * tot
        for ((k, w) in v) { r -= w; if (r <= 0) return k }
        return v.last().first
    }

    /** Người gõ "lạ": dấu thanh chèn ở vị trí ngẫu nhiên sau nguyên âm đầu (free marking). */
    fun pickFreeVariant(s: String, rng: Random): String? {
        val base = pickVariant(s, rng) ?: return null
        val t = base.last()
        if (t !in "sfrxj" || base.length < 3) return base
        val core = base.dropLast(1)
        val fv = core.indexOfFirst { it in "aeiouy" }
        if (fv < 0) return base
        val pos = fv + 1 + rng.nextInt(core.length - fv)
        val alt = core.substring(0, pos) + t + core.substring(pos)
        return if (compose(alt) == compose(base)) alt else base
    }

    /** Từ tiếng Anh theo tần suất enlexicon (thang vnlexicon) — gõ xen câu Việt. */
    fun englishWords(n: Int, rng: Random): List<List<String>> {
        val lx = SwipeEnglish.lexicon
        val w = DoubleArray(lx.count) { Math.exp(0.06 * (lx.freq[it] - 255)) }
        val tot = w.sum()
        return List(n) {
            var r = rng.nextDouble() * tot
            var i = 0
            while (i < w.size - 1 && r > w[i]) { r -= w[i]; i++ }
            listOf(lx.words[i])
        }
    }

    /** Từ chat/viết tắt trong seed (không phải âm tiết Việt), theo trọng số seed. */
    fun chatWords(n: Int, rng: Random): List<List<String>> {
        // ≥ 2 chữ: chữ đơn của seed ("z" gen z, "x" chụp x quang — 18/10/2026) không phải từ chat, chạm lệch một
        // phím thì không gì sửa được ⇒ chỉ thêm nhiễu cho mẫu
        val items = SeedData.unigrams.filter { (w, _) -> w.length >= 2 && w.all { it in 'a'..'z' } && !VNSuggest.contains(w) }.toList()
        val w = items.map { Math.exp(0.06 * (it.second * 5.1 - 255)) }
        val tot = w.sum()
        return List(n) {
            var r = rng.nextDouble() * tot
            var i = 0
            while (i < w.size - 1 && r > w[i]) { r -= w[i]; i++ }
            listOf(items[i].first)
        }
    }

    /** Viết tắt / tên riêng KHÔNG có trong bất kỳ bảng nào (rủi ro "từ lạ"), mỗi từ × [times]. */
    fun oovWords(times: Int): List<List<String>> {
        val cand = listOf("khum", "mng", "nma", "nhma", "tks", "thx", "pls", "plz", "omg", "hcm", "tphcm", "sg", "hn",
            "kpop", "hic", "hix", "bh", "ms", "nt", "lm", "ntn", "bn", "mk", "mik", "trc", "ns", "bt", "bik", "thik",
            "wa", "zui", "iu", "nx", "cx", "ck", "vk", "ny", "ah", "uh", "kk", "kkk", "hjhj", "vcd", "dz", "ce", "nv",
            "ae", "ad", "sp", "tl", "hqua", "hnay", "nguoi", "ngta", "vch", "cty", "sdt", "cmnd", "gplx", "atm")
        val seed = SeedData.unigrams.keys
        val keep = cand.filter { it !in seed && !SwipeEnglish.contains(it) && !VNSuggest.contains(it) }
        return List(times) { keep.map { listOf(it) } }.flatten()
    }

    /**
     * Học lệch cá nhân online theo hàng (phương án c): EMA của (điểm chọn − tâm phím) trên các
     * chạm thuộc TỪ ra đúng (người dùng không sửa). [dead]: phần lệch ≤ dead (pt) bỏ qua.
     */
    class OffsetLearner(
        val rate: Float = 0.05f, val minSamples: Int = 20, val dead: Float = 0f,
        val clampX: Float = 0.3f, val clampY: Float = 0.35f,
    ) {
        val ox = FloatArray(3); val oy = FloatArray(3); val n = IntArray(3)
        private fun shrink(v: Float) = if (v > dead) v - dead else if (v < -dead) v + dead else 0f
        fun correct(p: KPoint, g: Geo): KPoint {
            val row = (p.y / g.pitchY).toInt().coerceIn(0, 2)
            if (n[row] < minSamples) return p
            return KPoint(p.x - shrink(ox[row]), p.y - shrink(oy[row]))
        }
        fun learn(p: KPoint, key: Int, row: Int, g: Geo) {
            val c = g.center(key)
            val dx = (p.x - c.x).coerceIn(-clampX * g.pitchX, clampX * g.pitchX)
            val dy = (p.y - TouchGeometry.yOffset - c.y).coerceIn(-clampY * g.pitchY, clampY * g.pitchY)
            val a = if (n[row] < minSamples) 1f / (n[row] + 1) else rate
            ox[row] += a * (dx - ox[row]); oy[row] += a * (dy - oy[row]); n[row]++
        }
    }

    class Stats {
        var taps = 0; var tapErr = 0; var words = 0; var wordErr = 0
        var badOverride = 0; var goodOverride = 0; var markErr = 0
        var lost = 0
        /** Chạm ra phím ở HÀNG KHÁC phím định gõ (lỗi dọc). */
        var crossRow = 0
        // (d) gợi ý sửa trên thanh: từ sai có bản sửa ĐÚNG ở slot 1 / sai gợi ý sai / từ đúng bị gợi ý
        var wrongVn = 0; var sugHit = 0; var sugWrong = 0; var sugFalse = 0
        fun pct(a: Int, b: Int) = if (b == 0) "-" else "%.2f".format(100.0 * a / b)
        override fun toString() = "tap ${pct(tapErr, taps)}% | từ ${pct(wordErr, words)}% | đổi-nhầm ${pct(badOverride, taps)}% | cứu ${pct(goodOverride, taps)}% | dấu-hỏng ${pct(markErr, words)}%"
        fun sugString() = "từ sai ${wordErr} (ra từ Việt hợp lệ ${wrongVn}) | slot1 đúng ${pct(sugHit, wordErr)}% | gợi ý sai ${pct(sugWrong, wordErr)}% | từ đúng bị gợi ý ${pct(sugFalse, words - wordErr)}%"
        fun add(x: Stats) {
            taps += x.taps; tapErr += x.tapErr; words += x.words; wordErr += x.wordErr
            badOverride += x.badOverride; goodOverride += x.goodOverride; markErr += x.markErr; lost += x.lost
            crossRow += x.crossRow
            wrongVn += x.wrongVn; sugHit += x.sugHit; sugWrong += x.sugWrong; sugFalse += x.sugFalse
        }
    }

    /** (d): gợi ý sửa cho từ vừa gõ — (raw đã gõ, điểm chạm từng phím, âm tiết trước) → từ gợi ý hoặc null. */
    fun interface Suggester { fun suggest(typed: String, pts: List<KPoint>, prev: String?): String? }

    /**
     * Chạy [sentences] cho một người gõ. Đếm đổi nhầm/cứu so với router gần-nhất; [learner]
     * học lệch từ TỪ ra đúng; [suggester] đo gợi ý sửa (d).
     */
    fun run(
        sentences: List<List<String>>, g: Geo, pr: Profile, seed: Long,
        method: (KPoint, String) -> Int, learner: OffsetLearner? = null,
        english: Boolean = false, free: Boolean = false, suggester: Suggester? = null,
    ): Stats {
        val st = Stats()
        val rng = Random(seed)
        val base = baseline(g)
        for (sent in sentences) {
            var prev: String? = null
            for (syl in sent) {
                val intended = (if (english) syl else if (free) pickFreeVariant(syl, rng) else pickVariant(syl, rng)) ?: continue
                val typed = StringBuilder()
                val pts = ArrayList<Pair<KPoint, Int>>(); val rawPts = ArrayList<KPoint>()
                var markBad = false
                for (ch in intended) {
                    val k = g.index[ch - 'a']
                    val raw = tap(g, k, pr, rng)
                    val adj = learner?.correct(raw, g) ?: raw
                    val b0 = base(raw, typed.toString())
                    val m = method(adj, typed.toString())
                    st.taps++
                    if (m != k) st.tapErr++
                    if (m < 0) st.lost++
                    if (m >= 0 && m != k && g.rowOf[m] != g.rowOf[k]) st.crossRow++
                    if (b0 == k && m != k) st.badOverride++
                    if (b0 != k && m == k) st.goodOverride++
                    if (m != k && (ch in "sfrxjw" || (m >= 0 && g.keys[m] in "sfrxjw"))) markBad = true
                    if (m >= 0) { typed.append(g.keys[m]); pts.add(TouchGeometry.keySelectionPoint(adj) to m); rawPts.add(raw) }
                }
                st.words++
                val got = compose(typed.toString())
                val want = compose(intended)
                val ok = if (english) typed.toString() == intended else got == want
                if (!ok) {
                    st.wordErr++; if (markBad) st.markErr++
                    if (VNSuggest.contains(got)) st.wrongVn++
                }
                if (suggester != null && !english) {
                    val s = suggester.suggest(typed.toString(), pts.map { it.first }, prev)
                    if (s != null) {
                        if (ok) st.sugFalse++ else if (s == want) st.sugHit++ else st.sugWrong++
                    }
                }
                if (ok && learner != null) for ((i, pm) in pts.withIndex()) learner.learn(rawPts[i], pm.second, g.rowOf[pm.second], g)
                prev = got
            }
        }
        return st
    }

    fun baseline(g: Geo): (KPoint, String) -> Int = { p, _ ->
        KeyRouter.nearestLetter(TouchGeometry.keySelectionPoint(p), g.rects, rowsTop = 0f) ?: -1
    }

    fun bayes(g: Geo, prior: TelexKeyPrior, params: TouchTargetParams): (KPoint, String) -> Int = { p, typed ->
        val q = TouchGeometry.keySelectionPoint(p)
        val n = KeyRouter.nearestLetter(q, g.rects, rowsTop = 0f) ?: -1
        if (n < 0) -1 else {
            val f = prior.forRaw(typed)
            if (f == null) n else TouchTarget.choose(q, g.rects, g.keys, n, f, params)
        }
    }

    /**
     * (d) nguyên mẫu: thay MỘT phím bằng phím kề (theo điểm chạm thật) → âm tiết hợp lệ;
     * điểm = λ·tần suất + PMI bigram(âm tiết trước) + log-likelihood chạm. Gợi ý khi hơn từ
     * hiện tại ≥ [tau]. [onlyValid]: chỉ khi từ hiện tại LÀ tiếng Việt (phần AdjacentKeyFixer chưa lo).
     */
    fun vnFixer(g: Geo, tau: Float, onlyValid: Boolean, sigma: Float = 0.3f, lambda: Float = 0.06f): Suggester =
        Suggester { typed, pts, prev ->
            val cur = compose(typed)
            val curF = VNSuggest.frequency(cur)
            if (onlyValid && curF == null) return@Suggester null
            val big = SyllableLM.shared
            val prevId = prev?.let { SyllableLM.idOf(it) } ?: -1
            fun lm(w: String, f: Int): Float {
                val id = if (prevId >= 0 && big != null) SyllableLM.idOf(w) else -1
                val pmi = if (id >= 0) big!!.bigram(prevId).explicit(id).coerceAtLeast(0f) else 0f
                return lambda * f + pmi
            }
            fun ll(p: KPoint, k: Int): Float {
                val r = g.rects[k]; val w = r.right - r.left; val h = r.bottom - r.top
                val ux = (p.x - (r.left + r.right) / 2) / (sigma * w)
                val uy = (p.y - (r.top + r.bottom) / 2) / (sigma * h)
                return -0.5f * (ux * ux + uy * uy)
            }
            val s0 = if (curF != null) lm(cur, curF) else -1e9f
            var best: String? = null; var bestS = s0 + tau
            val arr = typed.toCharArray()
            for (i in arr.indices) {
                val p = pts.getOrNull(i) ?: continue
                val k0 = g.index[arr[i] - 'a']
                for (k in g.rects.indices) {
                    if (k == k0) continue
                    val f = g.rects[k]; val w = f.right - f.left
                    val dx = maxOf(f.left - p.x, 0f, p.x - f.right)
                    val dy = maxOf(f.top - p.y, 0f, p.y - f.bottom)
                    if (dx * dx + dy * dy > (0.6f * w) * (0.6f * w)) continue
                    val c = arr.copyOf(); c[i] = g.keys[k]
                    val wv = compose(String(c))
                    if (wv == cur) continue
                    val fq = VNSuggest.frequency(wv) ?: continue
                    val s = lm(wv, fq) + ll(p, k) - ll(p, k0)
                    if (s > bestS) { best = wv; bestS = s }
                }
            }
            best
        }
}
