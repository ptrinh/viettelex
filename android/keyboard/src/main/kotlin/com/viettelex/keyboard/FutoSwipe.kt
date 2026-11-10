package com.viettelex.keyboard

import java.nio.ByteBuffer
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

/**
 * FutoSwipe.kt — decoder gõ vuốt THỬ NGHIỆM dùng encoder FUTO Swipe ([FutoSwipeModel],
 * "powered by FUTO Swipe"), sau công tắc Keys.SWIPE_FUTO (mặc định TẮT). Bản Swift song
 * sinh: iOS/Keyboard/FutoSwipe.swift.
 *
 * Công tắc TẮT ⇒ lớp này không được tạo, không tải gì, đường gõ vuốt SHARK2 y nguyên.
 * Bật ⇒ [load] (luồng nền) đọc asset fp16 → model; [release] khi ẩn bàn phím / áp lực bộ nhớ;
 * decode lúc model chưa sẵn thì trả null ⇒ caller dùng SHARK2 như cũ.
 *
 * Luồng decode:
 *  1. đường vuốt (toạ độ view) → chuẩn hoá theo khung vùng phím chữ (bbox tâm phím ± nửa
 *     phím; 3 hàng) về 0–1, kẹp; resample theo THỜI GIAN 60 Hz rồi 64 điểm (như FUTO);
 *  2. encoder → log-xác suất phím theo 32 bước (CTC, blank);
 *  3. điểm âm học mỗi từ = CTC Viterbi của chuỗi phím đã gộp chữ lặp (cùng bộ phím với
 *     SwipeLexicon/SwipeEnglish), tìm trên từ vựng xếp theo tiền tố, dùng lại cột CTC của
 *     tiền tố chung + cắt nhánh (cận trên = max_t α tiền tố).
 *  4. kết hợp: [Mode.ENSEMBLE] (mặc định) = điểm SHARK2 (hình học + tần suất + ngữ cảnh +
 *     Việt/Anh) + β·(âm học − âm học tốt nhất) trên pool SHARK2 ∪ top âm học; [Mode.FUTO] =
 *     A·âm học + λ·tần suất (+ bias tiếng Anh) + ngữ cảnh cho top pool — không dùng SHARK2.
 * KHÔNG thread-safe (caller khoá như SwipeDecoder).
 */
class FutoSwipe(private val source: () -> ByteBuffer?) {
    enum class Mode { ENSEMBLE, FUTO }

    data class Params(
        var mode: Mode = Mode.ENSEMBLE,
        /** Mode.FUTO: trọng số âm học (log-prob CTC) so với λ·tần suất/ngữ cảnh. */
        var acousticWeight: Float = 0.5f,
        /** Mode.ENSEMBLE: trọng số âm học cộng vào điểm SHARK2. */
        var ensembleWeight: Float = 0.1f,
        /** Âm học thấp nhất khi từ không chấm được (kẹp phạt). */
        var ensembleFloor: Float = -30f,
        /** Số ứng viên âm học tốt nhất nhập thêm vào pool ensemble. */
        var ensembleExtra: Int = 4,
        /** Pool (theo điểm trước ngữ cảnh) đem cộng ngữ cảnh — như SwipeDecoder.contextPool. */
        var pool: Int = 16,
    )

    val params = Params()
    @Volatile private var model: FutoSwipeModel? = null
    @Volatile private var loadFailed = false
    /** Khoá RIÊNG cho việc tải (không dùng khoá decode của IME ⇒ vuốt không chờ tải weights). */
    private val loadLock = Any()
    /** Tăng ở [release]: lượt tải đang dở lúc nhả thì bỏ kết quả (không hồi sinh model đã nhả). */
    @Volatile private var loadGen = 0
    private var layout: SwipeLayout? = null
    private val keyXY = FloatArray(52)
    /** chữ a…z → cột trong đầu ra model (−1 = layout không có phím). */
    private val classOf = IntArray(26) { -1 }
    private var nk = 0
    private var frameX = 0f; private var frameW = 1f; private var frameY = 0f; private var frameH = 1f
    // scratch
    private val feats = FloatArray(2 * FutoSwipeModel.T)
    private var em = FloatArray(FutoSwipeModel.T2 * 27)
    private var px = FloatArray(0); private var py = FloatArray(0); private var pt = FloatArray(0)
    private var gx = FloatArray(0); private var gy = FloatArray(0)
    private val nb = FloatArray(MAX_DEPTH * FutoSwipeModel.T2)
    private val bl = FloatArray(MAX_DEPTH * FutoSwipeModel.T2)
    private val bl0 = FloatArray(FutoSwipeModel.T2)
    private val stack = IntArray(MAX_DEPTH)
    private val topScore = FloatArray(64); private val topAc = FloatArray(64); private val topIdx = IntArray(64)
    private var topFilled = 0
    /** Có emissions hợp lệ cho đường vuốt cuối cùng. */
    var hasEmissions = false; private set
    /** Thời gian encoder lần cuối (ms) — đo/TouchLog. */
    var lastModelMs = 0.0; private set

    val isLoaded: Boolean get() = model != null

    /**
     * Tải model (gọi ở luồng nền). An toàn gọi lại; hỏng thì không thử lại tới [release].
     * Thread-safe với [decode] mà KHÔNG cần khoá decode: decode thấy model null ⇒ trả null
     * (caller dùng SHARK2) thay vì chờ tải xong.
     */
    fun load(): Boolean {
        if (model != null) return true
        synchronized(loadLock) {
            if (model != null) return true
            if (loadFailed) return false
            val gen = loadGen
            val m = try { source()?.let { FutoSwipeModel.load(it) } } catch (e: Exception) { null }
            if (m == null) { loadFailed = true; return false }
            if (gen != loadGen) return false          // đã nhả trong lúc tải
            model = m
            return true
        }
    }

    /** Nhả model (ẩn bàn phím / áp lực bộ nhớ / tắt công tắc). Không chờ lượt tải đang chạy. */
    fun release() {
        loadGen++
        model = null
        loadFailed = false
        hasEmissions = false
    }

    fun setLayout(l: SwipeLayout) {
        if (l == layout) return
        layout = l
        var minX = Float.POSITIVE_INFINITY; var maxX = Float.NEGATIVE_INFINITY
        var minY = Float.POSITIVE_INFINITY; var maxY = Float.NEGATIVE_INFINITY
        for (k in 0 until 26) {
            val x = l.centers[2 * k]; val y = l.centers[2 * k + 1]
            if (!x.isFinite()) continue
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
        val kw = l.keyWidth
        frameX = minX - kw / 2; frameW = max(maxX - minX + kw, 1e-3f)
        val rh = max((maxY - minY) / 2, 1e-3f)
        frameY = minY - rh / 2; frameH = 3 * rh
        nk = 0
        for (k in 0 until 26) {
            val x = l.centers[2 * k]
            if (!x.isFinite()) { classOf[k] = -1; continue }
            classOf[k] = nk
            keyXY[2 * nk] = (x - frameX) / frameW
            keyXY[2 * nk + 1] = (l.centers[2 * k + 1] - frameY) / frameH
            nk++
        }
        hasEmissions = false
    }

    /** Toạ độ chuẩn hoá của phím (test). */
    fun normalizedKeys(): FloatArray = keyXY.copyOf(2 * nk)

    /**
     * Bước 1: đường vuốt → 128 đặc trưng (x hàng rồi y hàng). [ts] giây. Thuần; cùng thuật
     * toán với Scripts/futo-swipe/gen_fixture.py (làm tròn floor(x+0.5)).
     */
    fun features(xs: FloatArray, ys: FloatArray, ts: DoubleArray, count: Int, out: FloatArray = feats): FloatArray {
        if (px.size < count) { px = FloatArray(count); py = FloatArray(count); pt = FloatArray(count) }
        for (i in 0 until count) {
            px[i] = min(max((xs[i] - frameX) / frameW, 0f), 1f)
            py[i] = min(max((ys[i] - frameY) / frameH, 0f), 1f)
            pt[i] = ((ts[i] - ts[0]) * 1000.0).toFloat()
        }
        resampleTime(px, py, pt, count, out)
        return out
    }

    private fun resampleTime(x: FloatArray, y: FloatArray, t: FloatArray, count: Int, out: FloatArray) {
        val tn = FutoSwipeModel.T
        var sx = x; var sy = y; var n = count
        val tEnd = t[count - 1]
        if (count > 1 && tEnd > 1e-3f) {
            val n60 = max(2, floor(tEnd / (1000f / 60f) + 0.5f).toInt() + 1)
            if (gx.size < n60) { gx = FloatArray(n60); gy = FloatArray(n60) }
            var j = 0
            for (i in 0 until n60) {
                val tt = tEnd * i / (n60 - 1)
                while (j < count - 2 && t[j + 1] < tt) j++
                val t0 = t[j]; val t1 = t[j + 1]
                val a = if (t1 > t0) min(max((tt - t0) / (t1 - t0), 0f), 1f) else 0f
                gx[i] = x[j] + a * (x[j + 1] - x[j])
                gy[i] = y[j] + a * (y[j + 1] - y[j])
            }
            sx = gx; sy = gy; n = n60
        }
        for (i in 0 until tn) {
            val pos = if (n == 1) 0f else (n - 1).toFloat() * i / (tn - 1)
            val j = min(pos.toInt(), max(n - 2, 0))
            if (n == 1) { out[i] = sx[0]; out[tn + i] = sy[0]; continue }
            val a = pos - j
            out[i] = sx[j] + a * (sx[j + 1] - sx[j])
            out[tn + i] = sy[j] + a * (sy[j + 1] - sy[j])
        }
    }

    /** Bước 2: encoder trên đường vuốt → emissions nội bộ. false nếu chưa có model/layout. */
    fun computeEmissions(xs: FloatArray, ys: FloatArray, ts: DoubleArray, count: Int): Boolean {
        hasEmissions = false
        val m = model ?: return false
        if (layout == null || nk == 0 || count < 1) return false
        features(xs, ys, ts, count)
        if (em.size < FutoSwipeModel.T2 * (nk + 1)) em = FloatArray(FutoSwipeModel.T2 * (nk + 1))
        val t0 = System.nanoTime()
        m.run(feats, keyXY, nk, em)
        lastModelMs = (System.nanoTime() - t0) / 1e6
        hasEmissions = true
        return true
    }

    fun emissions(): FloatArray = em.copyOf(FutoSwipeModel.T2 * (nk + 1))

    /** Bước 3: CTC Viterbi (log) của một chuỗi phím đã gộp chữ lặp, trên emissions hiện có. */
    fun score(keys: ByteArray, lo: Int, hi: Int): Float {
        if (!hasEmissions || hi <= lo || hi - lo > MAX_DEPTH) return Float.NEGATIVE_INFINITY
        initBlank()
        for (d in 0 until hi - lo) {
            val c = classOf[keys[lo + d].toInt()]
            if (c < 0) return Float.NEGATIVE_INFINITY
            extend(d, c)
        }
        val base = (hi - lo - 1) * T2 + T2 - 1
        return max(nb[base], bl[base])
    }

    fun score(word: String): Float {
        val b = ByteArray(word.length); var n = 0; var last = -1
        for (ch in word) {
            val k = ch.code - 97
            if (k !in 0..25) return Float.NEGATIVE_INFINITY
            if (k != last) { b[n++] = k.toByte(); last = k }
        }
        return score(b, 0, n)
    }

    private fun initBlank() {
        val stride = nk + 1
        var acc = 0f
        for (t in 0 until T2) { acc += em[t * stride + nk]; bl0[t] = acc }
    }

    /** Cột CTC cho tiền tố độ sâu d (kết thúc bằng phím c), từ độ sâu d−1 (hoặc rỗng). */
    private fun extend(d: Int, c: Int) {
        val stride = nk + 1
        val o = d * T2; val q = (d - 1) * T2
        val neg = Float.NEGATIVE_INFINITY
        for (t in 0 until T2) {
            val e = em[t * stride + c]
            val from: Float = if (t == 0) {
                if (d == 0) 0f else neg
            } else {
                val a = nb[o + t - 1]
                val b = if (d == 0) bl0[t - 1] else max(bl[q + t - 1], nb[q + t - 1])
                max(a, b)
            }
            nb[o + t] = e + from
            bl[o + t] = if (t == 0) neg else em[t * stride + nk] + max(bl[o + t - 1], nb[o + t - 1])
        }
    }

    private fun bound(d: Int): Float {
        var m = Float.NEGATIVE_INFINITY
        val o = d * T2
        for (t in 0 until T2) if (nb[o + t] > m) m = nb[o + t]
        return m
    }

    /**
     * Tìm trên từ vựng theo tiền tố: giữ top-[m] theo điểm prior = [w]·âm học + λ·tần suất/255
     * (+ [enBias] cho từ tiếng Anh). Chỉ số: < fc = dạng Việt; ≥ fc = từ tiếng Anh.
     */
    fun search(m: Int, w: Float, lambdaFreq: Float, en: SwipeEnglish.Swipe?, enBias: Float) {
        topFilled = 0
        if (!hasEmissions) return
        initBlank()
        val forms = SwipeLexicon.forms
        val fc = forms.count
        val maxPrior = lambdaFreq + (if (en != null) max(0f, enBias) else 0f)
        searchList(forms.keys, forms.keyStart, fc, 0, forms.freq, m, w, lambdaFreq, 0f, maxPrior)
        if (en != null) searchList(en.keys, en.keyStart, en.count, fc, en.freq, m, w, lambdaFreq, enBias, maxPrior)
    }

    private fun searchList(keys: ByteArray, keyStart: IntArray, n: Int, idxBase: Int, freq: IntArray,
                           m: Int, w: Float, lam: Float, bias: Float, maxPrior: Float) {
        var depth = 0        // số tầng cột CTC hợp lệ trong stack
        var prunedLen = -1   // tiền tố bị cắt (stack[0..prunedLen)) — bỏ mọi từ có cùng tiền tố
        for (i in 0 until n) {
            val lo = keyStart[i]; val len = keyStart[i + 1] - lo
            if (len <= 0 || len > MAX_DEPTH) continue
            if (prunedLen > 0 && len >= prunedLen) {
                var same = true
                for (d in 0 until prunedLen) if (stack[d] != keys[lo + d].toInt()) { same = false; break }
                if (same) continue
            }
            prunedLen = -1
            // dùng lại tiền tố chung
            var l = 0
            val lim = min(depth, len)
            while (l < lim && stack[l] == keys[lo + l].toInt()) l++
            depth = l
            var ok = true
            val thr = if (topFilled == m) topScore[m - 1] else Float.NEGATIVE_INFINITY
            while (depth < len) {
                val k = keys[lo + depth].toInt()
                val c = classOf[k]
                if (c < 0) { ok = false; break }
                stack[depth] = k
                extend(depth, c)
                depth++
                if (depth < len && thr > Float.NEGATIVE_INFINITY && w * bound(depth - 1) + maxPrior < thr) {
                    prunedLen = depth; ok = false; break
                }
            }
            if (!ok) continue
            val base = (len - 1) * T2 + T2 - 1
            val ac = max(nb[base], bl[base])
            if (ac == Float.NEGATIVE_INFINITY) continue
            insertTop(w * ac + lam * freq[i] / 255f + bias, ac, idxBase + i, m)
        }
    }

    /** Kết quả [search]: (chỉ số, âm học) theo điểm giảm dần. */
    fun top(): List<Pair<Int, Float>> = (0 until topFilled).map { topIdx[it] to topAc[it] }

    private fun insertTop(s: Float, ac: Float, idx: Int, m: Int) {
        if (topFilled == m && s <= topScore[m - 1]) return
        var pos = if (topFilled < m) topFilled else m - 1
        while (pos > 0 && topScore[pos - 1] < s) {
            topScore[pos] = topScore[pos - 1]; topAc[pos] = topAc[pos - 1]; topIdx[pos] = topIdx[pos - 1]; pos--
        }
        topScore[pos] = s; topAc[pos] = ac; topIdx[pos] = idx
        if (topFilled < m) topFilled++
    }

    /**
     * Giải mã một cú vuốt. null ⇒ model chưa sẵn (caller dùng SHARK2). [shark] cần cho
     * Mode.ENSEMBLE (đã setLayout). Tham số khác y như SwipeDecoder.decode.
     */
    fun decode(path: SwipePath, topK: Int, context: ((String) -> Float)?, english: SwipeEnglishPrior?,
               englishContext: ((String) -> Float)?, shark: SwipeDecoder?,
               /** true = dùng emissions đã tính cho CHÍNH đường này (đo/tune nhiều cấu hình). */
               reuseEmissions: Boolean = false): List<SwipeCandidate>? {
        if (!(reuseEmissions && hasEmissions) && !computeEmissions(path.xs, path.ys, path.ts, path.count)) return null
        val lam = SwipeDecoder.Params().lambdaFreq
        val en = if (english != null) SwipeEnglish.lexicon.swipe else null
        val forms = SwipeLexicon.forms
        val fc = forms.count
        val out = ArrayList<SwipeCandidate>()
        if (params.mode == Mode.ENSEMBLE && shark != null) {
            val pool = shark.decode(path, max(topK, params.pool), context, english, englishContext)
            search(params.ensembleExtra.coerceAtLeast(1), 1f, 0f, en, 0f)
            val acs = FloatArray(pool.size) { score(pool[it].folded) }
            var best = Float.NEGATIVE_INFINITY
            for (a in acs) if (a > best) best = a
            for (k in 0 until topFilled) if (topAc[k] > best) best = topAc[k]
            val floor = best + params.ensembleFloor
            val seen = HashSet<String>()
            var minShark = Float.POSITIVE_INFINITY
            for ((i, c) in pool.withIndex()) {
                seen.add(c.folded)
                if (c.score < minShark) minShark = c.score
                out.add(c.copy(score = c.score + params.ensembleWeight * (max(acs[i], floor) - best)))
            }
            // ứng viên âm học mạnh mà SHARK2 bỏ sót: điểm gốc = SHARK2 kém nhất của pool
            if (pool.isNotEmpty()) for (k in 0 until topFilled) {
                val idx = topIdx[k]
                val isEn = idx >= fc
                val word = if (isEn) en!!.word(idx - fc) else forms.folded[idx]
                if (!seen.add(word)) continue
                var s = minShark + params.ensembleWeight * (topAc[k] - best)
                if (!isEn && context != null) s += context(word)
                if (isEn) { s += english!!.bias; englishContext?.let { s += it(word) } }
                out.add(SwipeCandidate(word, s, if (isEn) SwipeLang.EN else SwipeLang.VI))
            }
        } else {
            search(max(topK, params.pool), params.acousticWeight, lam, en, english?.bias ?: 0f)
            for (k in 0 until topFilled) {
                val idx = topIdx[k]
                var s = topScore[k]
                if (idx >= fc) {
                    val word = en!!.word(idx - fc)
                    englishContext?.let { s += it(word) }
                    out.add(SwipeCandidate(word, s, SwipeLang.EN))
                } else {
                    val word = forms.folded[idx]
                    context?.let { s += it(word) }
                    out.add(SwipeCandidate(word, s))
                }
            }
        }
        val sorted = out.withIndex().sortedWith(compareBy({ -it.value.score }, { it.index })).map { it.value }
        return if (english != null) SwipeDecoder.arbitrate(sorted, topK, english.margin) else sorted.take(topK)
    }

    companion object {
        private const val T2 = FutoSwipeModel.T2
        private const val MAX_DEPTH = 32
    }
}
