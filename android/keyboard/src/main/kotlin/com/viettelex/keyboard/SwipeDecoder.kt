package com.viettelex.keyboard

import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/*
 * SwipeDecoder.kt — LÕI GIẢI MÃ GÕ VUỐT (swipe/glide typing) tiếng Việt, phần THUẦN
 * (không View, không MotionEvent). Song sinh của iOS/Keyboard/SwipeDecoder.swift —
 * sửa thuật toán/hằng số ở đây thì sửa y hệt bên kia (test parity dùng chung fixture
 * iOS/KeyboardTests/Fixtures/swipe-paths.txt so top-1 hai bản).
 *
 * Người dùng vuốt theo chữ KHÔNG DẤU ("viet") → [SwipeDecoder.decode] trả dạng không dấu
 * top-K; [SwipeDecoder.expand] bung thành âm tiết có dấu (việt, viết…) theo tần suất
 * lexicon (+ điểm ngữ cảnh caller cấp).
 *
 * Thuật toán kiểu SHARK2 (Kristensson & Zhai 2004) như FlorisBoard
 * StatisticalGlideTypingClassifier: template = đường nối tâm phím (gộp chữ lặp) theo
 * LAYOUT THẬT; resample N điểm cách đều; shape channel (dời trọng tâm, chia cạnh lớn
 * bbox, sàn 1 phím) + location channel (đơn vị phím, α nặng 2 đầu, đường hầm 0.25 phím);
 * Gaussian log-prob + λ·tần suất; lọc phím đầu/cuối ≤ 1.6 phím (thiếu thì 3.2); kênh độ
 * dài; TẦNG 2 trên top-16: σ location thích nghi (nét cẩu thả ⇒ σ_L tới ×1.5), căn phím
 * đơn điệu vào đường 48 điểm, góc gắt của đường phải gần phím ứng viên. Lệch tay cá nhân
 * [SwipeDecoder.offsetX]/[SwipeDecoder.offsetY] học online bằng [SwipeDecoder.learnOffset].
 * NHỊP (khi có thời gian điểm — SwipePath.ts): đuôi nét chậm ⇒ miễn phần LỐ theo hướng nét cuối
 * (người thật trôi quá phím cuối ~0.45 phím trước khi nhấc tay); tầng 2 phạt phím giữa nằm trên
 * đoạn lướt nhanh và đòi điểm DỪNG gần một phím. Không có thời gian ⇒ y hệt thuật toán cũ.
 * UỐN h (tầng 2, không cần thời gian): cặp ứng viên chỉ khác chữ h của phụ âm ghép (chưa/của) đổi
 * chỗ theo độ uốn của đường về h ([Params.bendWeight]).
 * Mọi phép tính Float32 cùng thứ tự với bản Swift → cùng điểm trên cùng input.
 *
 * Bộ nhớ: lười — không đọc lexicon/dựng template tới lần decode đầu (hoặc [prepare]).
 * Template ≈ 1666 × 24 × 2 Float ≈ 320 KB. Không cấp phát trong vòng chấm điểm.
 * KHÔNG thread-safe: gọi từ một luồng.
 */

/** Tâm phím a…z theo toạ độ thật (cùng hệ với đường vuốt). Đổi layout → setLayout lại. */
class SwipeLayout(
    /** Bước phím ngang (tâm-tới-tâm) — đơn vị chuẩn hoá mọi khoảng cách. */
    val keyWidth: Float,
    centers: Map<Char, Pair<Float, Float>>,
) {
    /** 52 số: (x, y) của 'a'…'z'; +∞ = không có phím. */
    val centers: FloatArray = FloatArray(52) { Float.POSITIVE_INFINITY }

    init {
        require(keyWidth > 0f) { "keyWidth phải > 0" }
        for ((ch, p) in centers) {
            if (ch !in 'a'..'z') continue
            this.centers[(ch - 'a') * 2] = p.first
            this.centers[(ch - 'a') * 2 + 1] = p.second
        }
    }

    fun center(ch: Char): Pair<Float, Float>? {
        if (ch !in 'a'..'z') return null
        val x = centers[(ch - 'a') * 2]
        return if (x.isFinite()) x to centers[(ch - 'a') * 2 + 1] else null
    }

    override fun equals(other: Any?): Boolean =
        other is SwipeLayout && other.keyWidth == keyWidth && other.centers.contentEquals(centers)

    override fun hashCode(): Int = 31 * keyWidth.hashCode() + centers.contentHashCode()

    companion object {
        /** QWERTY chuẩn (hàng 2 lệch 0.5 phím, hàng 3 lệch 1.5 phím). */
        fun qwerty(keyWidth: Float, rowHeight: Float, originX: Float = 0f, originY: Float = 0f): SwipeLayout {
            val m = HashMap<Char, Pair<Float, Float>>()
            val rows = listOf("qwertyuiop" to 0.5f, "asdfghjkl" to 1.0f, "zxcvbnm" to 2.0f)
            for ((r, rowPair) in rows.withIndex()) {
                val (row, x0) = rowPair
                for ((i, ch) in row.withIndex()) {
                    m[ch] = (originX + (x0 + i.toFloat()) * keyWidth) to
                        (originY + (r.toFloat() + 0.5f) * rowHeight)
                }
            }
            return SwipeLayout(keyWidth, m)
        }
    }
}

/**
 * Bộ đệm điểm vuốt cấp sẵn (cùng hành vi bản Swift). Chỉ nhận điểm cách điểm trước
 * ≥ [minDistance] (khuyên 1/6–1/4 phím); điểm nhấc tay thêm bằng `force = true`.
 * Đầy thì điểm mới ghi đè điểm cuối.
 */
class SwipePath(val minDistance: Float, val capacity: Int = 256) {
    init { require(capacity >= 2) }
    val xs = FloatArray(capacity)
    val ys = FloatArray(capacity)
    val ts = DoubleArray(capacity)
    var count = 0; private set
    var length = 0f; private set

    fun reset() { count = 0; length = 0f }

    fun add(x: Float, y: Float, t: Double, force: Boolean = false): Boolean {
        if (count > 0) {
            val dx = x - xs[count - 1]; val dy = y - ys[count - 1]
            val d = sqrt(dx * dx + dy * dy)
            if (!force && d < minDistance) return false
            if (force && d == 0f) { ts[count - 1] = t; return true }
            if (count == capacity) {
                val px = xs[count - 2]; val py = ys[count - 2]
                val ox = xs[count - 1] - px; val oy = ys[count - 1] - py
                val nx = x - px; val ny = y - py
                length += sqrt(nx * nx + ny * ny) - sqrt(ox * ox + oy * oy)
                xs[count - 1] = x; ys[count - 1] = y; ts[count - 1] = t
                return true
            }
            length += d
        }
        xs[count] = x; ys[count] = y; ts[count] = t
        count++
        return true
    }

    /** Thời lượng vuốt (giây). */
    val duration: Double get() = if (count > 1) ts[count - 1] - ts[0] else 0.0
}

/** [folded] = dạng không dấu (VI) hoặc từ tiếng Anh nguyên văn (EN, giai đoạn 3). */
data class SwipeCandidate(val folded: String, val score: Float, val lang: SwipeLang = SwipeLang.VI)
data class SwipeWord(val word: String, val score: Float)

/** 1666 dạng không dấu rút từ vnlexicon.bin — mỗi dạng là một dải id liên tiếp. */
object SwipeLexicon {
    class Forms(
        val folded: Array<String>,
        val idStart: IntArray,   // dải id dạng f: idStart[f] until idStart[f+1]
        val freq: IntArray,      // 0-255, entry mạnh nhất
        val keys: ByteArray,     // phím đã gộp chữ lặp (0…25)
        val keyStart: IntArray,
    ) { val count: Int get() = folded.size }

    val forms: Forms by lazy { build() }

    private fun build(): Forms {
        val b = VNLexicon2Data.blob
        val n = VNLexicon2Data.count
        val folded = ArrayList<String>(1700)
        val idStart = IntArray(n + 1)
        val freq = IntArray(n)
        val keys = ByteArray(b.offsets[n])
        val keyStart = IntArray(n + 1)
        var fc = 0; var kc = 0
        var prevLo = -1; var prevHi = -1
        for (id in 0 until n) {
            val lo = b.offsets[id]; val hi = b.offsets[id + 1]
            if (prevLo >= 0 && hi - lo == prevHi - prevLo &&
                (0 until hi - lo).all { b.foldedByte(lo + it) == b.foldedByte(prevLo + it) }) continue
            prevLo = lo; prevHi = hi
            val sb = StringBuilder(hi - lo)
            var last = -1
            for (i in lo until hi) {
                val c = b.foldedByte(i)
                sb.append(c.toChar())
                val k = c - 97
                if (k != last) { keys[kc++] = k.toByte(); last = k }
            }
            folded.add(sb.toString())
            idStart[fc] = id
            freq[fc] = b.freq(id)
            fc++
            keyStart[fc] = kc
        }
        idStart[fc] = n
        return Forms(folded.toTypedArray(), idStart.copyOf(fc + 1), freq.copyOf(fc),
            keys.copyOf(kc), keyStart.copyOf(fc + 1))
    }

    /** Chỉ số dạng [folded] (binary search ASCII), -1 nếu không có. */
    fun indexOf(folded: String): Int {
        val a = forms.folded
        var lo = 0; var hi = a.size
        while (lo < hi) {
            val mid = (lo + hi) / 2
            if (a[mid] < folded) lo = mid + 1 else hi = mid
        }
        return if (lo < a.size && a[lo] == folded) lo else -1
    }
}

class SwipeDecoder(val params: Params = Params()) {
    /** Hằng số mô hình — GIỮ Y HỆT bản Swift. */
    data class Params(
        val points: Int = 24,
        val sigmaShape: Float = 0.2f,
        val sigmaLoc: Float = 0.2f,
        val lambdaFreq: Float = 2.5f,
        val tunnel: Float = 0.25f,
        val endWeight: Float = 8f,
        val endSpan: Float = 0.15f,
        val filterRadius: Float = 1.6f,
        val contextPool: Int = 16,
        /** Kênh độ dài: −w·ln²((dài đường+1)/(dài template+1)), đơn vị phím ([lengthPenalty]). */
        val lengthWeight: Float = 2f,
        /** Chấm lại (tầng 2) top-[rescorePool] hình học; 0 = tắt cả tầng 2 + σ thích nghi. */
        val rescorePool: Int = 16,
        /** Điểm resample của tầng 2 (căn phím + góc). */
        val rescorePoints: Int = 48,
        /** Căn phím template vào đường (đơn điệu): −w·trung bình d² (phím, trừ tunnel). */
        val alignWeight: Float = 1f,
        /** Mỗi GÓC gắt trên đường phải gần một phím của ứng viên: −w·Σ d². */
        val cornerWeight: Float = 3f,
        val cornerDegrees: Float = 55f,
        val rescoreTunnel: Float = 0.25f,
        /**
         * σ location thích nghi: nét cẩu thả (location tốt nhất > ngưỡng, phím) ⇒ σ_L nhân
         * tới [adaptMax] — tin tần suất/ngữ cảnh hơn (kiểu SHARK2 nới σ theo tốc độ).
         */
        val adaptThreshold: Float = 0.13f,
        val adaptMax: Float = 1.5f,
        /**
         * NHỊP (cần thời gian điểm vuốt, tầng 2): tốc độ tương đối r = v / v trung bình tại
         * 48 điểm. Mỗi phím GIỮA của ứng viên mà điểm đường gần nó nhất nằm trên đoạn nhanh
         * (lướt qua) bị phạt w·max(0, r − [speedRef]); 0 = tắt. Hằng số nhịp/lố chỉnh trên nét
         * thật + đường giả "tự nhiên" (docs/DATA-SOURCES.md "Nét vuốt thật").
         */
        val speedWeight: Float = 0.3f,
        val speedRef: Float = 1.3f,
        /** Điểm DỪNG (cực tiểu r < [dwellRatio], không sát 2 đầu) phải gần một phím: −w·Σ d². */
        val dwellWeight: Float = 3f,
        val dwellRatio: Float = 0.35f,
        /**
         * CHỮ "h" CỦA PHỤ ÂM GHÉP (tầng 2): hai ứng viên trong pool khác nhau đúng một phím giữa h
         * đứng sau c/n/t/p/k/g (Việt) hoặc t/s/c/w/p/g (Anh) — chưa/của, chú/cụ. Nét thật lướt qua h
         * nhanh như phím thường (không chậm lại) nên nhịp không phân biệt được; thứ phân biệt là đường
         * UỐN về h: uốn = khoảng cách h tới dây cung nối 2 phím kề − khoảng cách h tới đường (phím).
         * Ứng viên có h += w·kẹp(uốn − [bendBias], ±[bendCap]), rồi kẹp trong [min, max] điểm cặp
         * ± 0,01 (chỉ đổi chỗ TRONG cặp, không vượt ứng viên khác). Chỉ khi dây cung cách h trong
         * [[bendMinChord], [bendMaxChord]] phím (h gần thẳng hàng như chọn/con ⇒ hình học không phân
         * biệt được; xa ⇒ kênh location đã đủ). 0 = tắt.
         */
        val bendWeight: Float = 3f,
        val bendBias: Float = 0.05f,
        val bendCap: Float = 0.3f,
        val bendMinChord: Float = 0.3f,
        val bendMaxChord: Float = 1f,
        /**
         * Lố đích ở đầu cuối: thành phần lệch THEO hướng nét cuối của template (đi quá phím
         * cuối trước khi nhấc tay) được miễn tới [overshoot] phím ở điểm cuối (giảm dần về
         * 0 hết đoạn [Params.endSpan]); 0 = tắt.
         */
        val overshoot: Float = 1f,
        /** Cổng miễn lố theo tốc độ tương đối đuôi r: r ≤ [tailSlow] ⇒ đủ, r ≥ [tailFast] ⇒ tắt. */
        val tailSlow: Float = 0.5f,
        val tailFast: Float = 0.8f,
        /** Học lệch tay cá nhân ([learnOffset]): tốc độ EMA, trần mỗi lần (phím). */
        val offsetRate: Float = 0.05f,
        val offsetCap: Float = 0.5f,
    )

    var layout: SwipeLayout? = null; private set

    private var tpl = FloatArray(0)
    private var tplCX = FloatArray(0)
    private var tplCY = FloatArray(0)
    private var tplScale = FloatArray(0)
    private var tplValid = BooleanArray(0)
    /** Từ vựng (theo công tắc lọc từ nhạy cảm) mà template đang dựng theo — đổi ⇒ dựng lại. */
    private var tplVocab: SwipeVocab.Vocab? = null
    private val alpha: FloatArray
    private val alphaSum: Float
    private val ux: FloatArray
    private val uy: FloatArray
    private val sx: FloatArray
    private val sy: FloatArray
    private var topScore = FloatArray(0)
    private var topIdx = IntArray(0)
    private var topDl = FloatArray(0)
    private var tplLen = FloatArray(0)
    /** Hướng đơn vị nét cuối của template (phím áp chót → phím cuối); 0 nếu 1 phím. */
    private var tplDX = FloatArray(0)
    private var tplDY = FloatArray(0)
    /** Độ sâu miễn lố [0, 1] theo điểm (1 ở điểm cuối), từ [ovFrom]. */
    private val ovDepth: FloatArray
    private val ovFrom: Int
    // tầng 2 + học lệch
    private val mx: FloatArray
    private val my: FloatArray
    private val dp: FloatArray
    private val back: IntArray
    private val corners: IntArray
    private var cornerCount = 0
    // nhịp (tầng 2): thời gian + tốc độ tương đối tại mx/my, điểm dừng, phạt tốc độ
    private val mt: FloatArray
    private val spd: FloatArray
    private val spdPen: FloatArray
    private val dwells: IntArray
    private var dwellCount = 0
    private var speedOn = false
    /** Phạt tốc độ của ứng viên vừa [alignCost]. */
    private var alignSpeed = 0f
    /** Hệ số miễn lố của lần decode này ([tailGate]). */
    private var ovScale = 0f
    private val rkx = FloatArray(32)
    private val rky = FloatArray(32)
    /** Mã phím ứng viên vừa [candidateKeys]; pool tầng 2: mã phím từng ứng viên (32/ô) + số phím. */
    private val rkc = IntArray(32)
    private var poolKeys = ByteArray(0)
    private var poolLen = IntArray(0)
    private var poolHasH = BooleanArray(0)
    private var bx = FloatArray(0)
    private var by = FloatArray(0)
    private val cosCorner: Float

    /**
     * Lệch tay hệ thống của người dùng (đơn vị bề rộng phím; + = phải/xuống), trừ khỏi
     * đường vuốt trước khi chấm. Học bằng [learnOffset]; caller lưu/khôi phục.
     */
    var offsetX = 0f
    var offsetY = 0f
    private var filled = 0
    private val frame = FloatArray(3)
    // template tiếng Anh dựng ngay lúc chấm (không giữ)
    private val ekx = FloatArray(32)
    private val eky = FloatArray(32)
    private val erx: FloatArray
    private val ery: FloatArray
    private val eframe = FloatArray(3)
    private val okFirst = BooleanArray(26)
    private val okLast = BooleanArray(26)

    init {
        val n = params.points
        require(n >= 2)
        alpha = FloatArray(n)
        var s = 0f
        for (i in 0 until n) {
            val edge = min(i, n - 1 - i).toFloat() / (n.toFloat() * params.endSpan)
            alpha[i] = 1f + params.endWeight * max(0f, 1f - edge)
            s += alpha[i]
        }
        alphaSum = s
        ovDepth = FloatArray(n)
        var from = n
        for (i in 0 until n) {
            val dep = 1f - (n - 1 - i).toFloat() / (n.toFloat() * params.endSpan)
            ovDepth[i] = max(0f, dep)
            if (ovDepth[i] > 0f && from == n) from = i
        }
        ovFrom = from
        ux = FloatArray(n); uy = FloatArray(n); sx = FloatArray(n); sy = FloatArray(n)
        erx = FloatArray(n); ery = FloatArray(n)
        val m2 = max(2, params.rescorePoints)
        mx = FloatArray(m2); my = FloatArray(m2); dp = FloatArray(32 * m2); back = IntArray(32 * m2)
        corners = IntArray(m2)
        mt = FloatArray(m2); spd = FloatArray(m2); spdPen = FloatArray(m2); dwells = IntArray(m2)
        cosCorner = kotlin.math.cos(params.cornerDegrees.toDouble() * Math.PI / 180.0).toFloat()
    }

    /** Đặt layout; khác layout cũ thì bỏ template (dựng lại lười). */
    fun setLayout(l: SwipeLayout) {
        if (l == layout) return
        layout = l
        tpl = FloatArray(0); tplCX = tpl; tplCY = tpl; tplScale = tpl; tplLen = tpl; tplDX = tpl; tplDY = tpl
        tplValid = BooleanArray(0)
        tplVocab = null
    }

    /** Dựng template ngay (background khi bàn phím hiện). */
    fun prepare() {
        val l = layout ?: return
        val v = SwipeVocab.current
        if (tpl.isEmpty() || tplVocab !== v) buildTemplates(l, v)
    }

    val templateBytes: Int
        get() = tpl.size * 4 + (tplCX.size + tplCY.size + tplScale.size + tplLen.size + tplDX.size + tplDY.size) * 4 +
            tplValid.size

    private fun buildTemplates(l: SwipeLayout, v: SwipeVocab.Vocab) {
        tplVocab = v
        val forms = v.forms
        val n = params.points; val fc = forms.count
        tpl = FloatArray(fc * n * 2)
        tplCX = FloatArray(fc); tplCY = FloatArray(fc); tplScale = FloatArray(fc); tplLen = FloatArray(fc)
        tplDX = FloatArray(fc); tplDY = FloatArray(fc)
        tplValid = BooleanArray(fc)
        val kx = FloatArray(32); val ky = FloatArray(32)
        val rx = FloatArray(n); val ry = FloatArray(n)
        for (f in 0 until fc) {
            val lo = forms.keyStart[f]; val hi = forms.keyStart[f + 1]
            var ok = hi - lo <= kx.size
            var m = 0
            if (ok) {
                for (j in lo until hi) {
                    val k = forms.keys[j].toInt()
                    if (k !in 0 until 26) { ok = false; break }
                    val x = l.centers[k * 2]; val y = l.centers[k * 2 + 1]
                    if (!x.isFinite()) { ok = false; break }
                    kx[m] = x; ky[m] = y; m++
                }
            }
            if (!ok || m == 0) continue
            resample(kx, ky, m, n, rx, ry)
            val base = f * n * 2
            for (i in 0 until n) { tpl[base + i * 2] = rx[i]; tpl[base + i * 2 + 1] = ry[i] }
            shapeFrame(rx, ry, n, l.keyWidth, frame)
            tplCX[f] = frame[0]; tplCY[f] = frame[1]; tplScale[f] = frame[2]
            tplLen[f] = keyPathLength(kx, ky, m, l.keyWidth)
            endDirection(kx, ky, m, frame)
            tplDX[f] = frame[0]; tplDY[f] = frame[1]
            tplValid[f] = true
        }
    }

    /** Giải mã → top-K dạng không dấu (điểm giảm dần); [context] cộng điểm ngữ cảnh. */
    fun decode(path: SwipePath, topK: Int = 5, context: ((String) -> Float)? = null): List<SwipeCandidate> =
        decodeCore(path.xs, path.ys, path.ts, path.count, topK, context, null, null)

    /** [ts] = thời gian điểm (giây, tuỳ gốc) — null ⇒ không dùng nhịp (điểm như đường đều). */
    fun decode(
        xs: FloatArray, ys: FloatArray, count: Int, topK: Int = 5,
        context: ((String) -> Float)? = null, ts: DoubleArray? = null,
    ): List<SwipeCandidate> = decodeCore(xs, ys, ts, count, topK, context, null, null)

    /**
     * Giai đoạn 3 — [english] != null: thêm từ tiếng Anh vào cùng không gian ứng viên
     * (+bias), [englishContext] = điểm ngữ cảnh riêng của từ tiếng Anh; sau khi xếp áp
     * [arbitrate]. null ⇒ y hệt [decode] thường. (Overload riêng để lambda đuôi
     * `decode(p, k) { … }` vẫn là [context].)
     */
    fun decode(
        path: SwipePath, topK: Int, context: ((String) -> Float)?,
        english: SwipeEnglishPrior?, englishContext: ((String) -> Float)? = null,
    ): List<SwipeCandidate> = decodeCore(path.xs, path.ys, path.ts, path.count, topK, context, english, englishContext)

    fun decode(
        xs: FloatArray, ys: FloatArray, count: Int, topK: Int, context: ((String) -> Float)?,
        english: SwipeEnglishPrior?, englishContext: ((String) -> Float)? = null, ts: DoubleArray? = null,
    ): List<SwipeCandidate> = decodeCore(xs, ys, ts, count, topK, context, english, englishContext)

    private fun decodeCore(
        xs0: FloatArray, ys0: FloatArray, ts: DoubleArray?, count: Int, topK: Int,
        context: ((String) -> Float)?,
        english: SwipeEnglishPrior?,
        englishContext: ((String) -> Float)?,
    ): List<SwipeCandidate> {
        val l = layout
        if (count <= 0 || topK <= 0 || l == null) return emptyList()
        val vocab = SwipeVocab.current
        if (tpl.isEmpty() || tplVocab !== vocab) buildTemplates(l, vocab)
        val forms = vocab.forms
        val en = if (english == null) null else SwipeEnglish.lexicon.swipe
        val fc = forms.count
        val n = params.points; val w = l.keyWidth
        val (xs, ys) = shifted(xs0, ys0, count, w)
        resample(xs, ys, count, n, ux, uy)
        val pathLen = keyPathLength(xs, ys, count, w)
        shapeFrame(ux, uy, n, w, frame)
        val ucx = frame[0]; val ucy = frame[1]; val us = frame[2]
        for (i in 0 until n) { sx[i] = (ux[i] - ucx) * us; sy[i] = (uy[i] - ucy) * us }

        var m = if (context == null && english == null) topK else max(topK, params.contextPool)
        if (params.rescorePool > 0) m = max(m, params.rescorePool)
        if (topScore.size < m) { topScore = FloatArray(m); topIdx = IntArray(m); topDl = FloatArray(m) }
        val tunnelW = params.tunnel * w
        val invS = 1f / (2f * params.sigmaShape * params.sigmaShape)
        val invL = 1f / (2f * params.sigmaLoc * params.sigmaLoc)
        val lam = params.lambdaFreq
        val lw = params.lengthWeight
        val t = tpl; val a = alpha
        ovScale = if (params.overshoot > 0f) tailGate(xs, ys, ts, count) else 0f
        val ov = params.overshoot * w * ovScale
        val ovStart = if (ov > 0f) ovFrom else n   // điểm i ≥ ovStart được miễn lố

        for (pass in 0 until 2) {
            val r = params.filterRadius * w * (if (pass == 0) 1f else 2f)
            val r2 = r * r
            filled = 0
            for (f in 0 until forms.count) {
                if (!tplValid[f]) continue
                val base = f * n * 2
                var dx = ux[0] - t[base]; var dy = uy[0] - t[base + 1]
                if (dx * dx + dy * dy > r2) continue
                dx = ux[n - 1] - t[base + (n - 1) * 2]
                dy = uy[n - 1] - t[base + (n - 1) * 2 + 1]
                if (dx * dx + dy * dy > r2) continue
                val cx = tplCX[f]; val cy = tplCY[f]; val sc = tplScale[f]
                var ds = 0f; var dl = 0f
                for (i in 0 until n) {
                    val tx = t[base + i * 2]; val ty = t[base + i * 2 + 1]
                    val ex = sx[i] - (tx - cx) * sc; val ey = sy[i] - (ty - cy) * sc
                    ds += sqrt(ex * ex + ey * ey)
                    var lx = ux[i] - tx; var ly = uy[i] - ty
                    if (i >= ovStart) {
                        // lố theo hướng nét cuối (tplDX/DY đơn vị) được miễn tới ov·độ sâu
                        val ddx = tplDX[f]; val ddy = tplDY[f]
                        val al = lx * ddx + ly * ddy
                        if (al > 0f) {
                            val cut = min(al, ov * ovDepth[i])
                            lx -= cut * ddx; ly -= cut * ddy
                        }
                    }
                    val d = sqrt(lx * lx + ly * ly) - tunnelW
                    if (d > 0f) dl += a[i] * d
                }
                ds = ds / n.toFloat()
                dl = dl / alphaSum / w
                var score = -(ds * ds) * invS - (dl * dl) * invL + lam * forms.freq[f].toFloat() / 255f
                if (lw > 0f) score -= lw * lengthPenalty(pathLen, tplLen[f])
                insertTop(score, f, dl, m)
            }
            if (en != null && english != null) scoreEnglish(en, english.bias, l, r2, m, fc, pathLen)
            if (filled >= topK) break
        }
        if (params.rescorePool > 0 && filled > 0) rescore(xs, ys, ts, count, l, invL, en, fc)

        val out = ArrayList<SwipeCandidate>(filled)
        for (k in 0 until filled) {
            val f = topIdx[k]
            var s = topScore[k]
            if (f >= fc && en != null) {
                val word = en.word(f - fc)
                if (englishContext != null) s += englishContext(word)
                out.add(SwipeCandidate(word, s, SwipeLang.EN))
                continue
            }
            if (context != null) s += context(forms.folded[f])
            out.add(SwipeCandidate(forms.folded[f], s))
        }
        // sortedByDescending ổn định: bằng điểm giữ thứ tự hình học
        val sorted = if (context != null || englishContext != null) out.sortedByDescending { it.score } else out
        if (english != null) return arbitrate(sorted, topK, english.margin)
        return sorted.take(topK)
    }

    /** Chấm từ tiếng Anh lọt lọc phím đầu/cuối (theo cặp phím, thứ tự cố định — parity Swift). */
    private fun scoreEnglish(en: SwipeEnglish.Swipe, bias: Float, l: SwipeLayout, r2: Float, m: Int, fc: Int,
                             pathLen: Float) {
        val n = params.points; val w = l.keyWidth
        val tunnelW = params.tunnel * w
        val invS = 1f / (2f * params.sigmaShape * params.sigmaShape)
        val invL = 1f / (2f * params.sigmaLoc * params.sigmaLoc)
        val lam = params.lambdaFreq
        val a = alpha
        val ov = params.overshoot * w * ovScale
        val ovStart = if (ov > 0f) ovFrom else n
        for (k in 0 until 26) {
            val x = l.centers[k * 2]; val y = l.centers[k * 2 + 1]
            if (!x.isFinite()) { okFirst[k] = false; okLast[k] = false; continue }
            var dx = ux[0] - x; var dy = uy[0] - y
            okFirst[k] = dx * dx + dy * dy <= r2
            dx = ux[n - 1] - x; dy = uy[n - 1] - y
            okLast[k] = dx * dx + dy * dy <= r2
        }
        for (fa in 0 until 26) {
            if (!okFirst[fa]) continue
            for (lb in 0 until 26) {
                if (!okLast[lb]) continue
                val bk = fa * 26 + lb
                for (o in en.bucketStart[bk] until en.bucketStart[bk + 1]) {
                    val i = en.order[o]
                    val lo = en.keyStart[i]; val hi = en.keyStart[i + 1]
                    if (hi - lo > ekx.size) continue
                    var mk = 0; var ok = true
                    for (j in lo until hi) {
                        val k = en.keys[j].toInt()
                        val x = l.centers[k * 2]
                        if (!x.isFinite()) { ok = false; break }
                        ekx[mk] = x; eky[mk] = l.centers[k * 2 + 1]; mk++
                    }
                    if (!ok) continue
                    resample(ekx, eky, mk, n, erx, ery)
                    endDirection(ekx, eky, mk, eframe)
                    val ddx = eframe[0]; val ddy = eframe[1]
                    shapeFrame(erx, ery, n, w, eframe)
                    val cx = eframe[0]; val cy = eframe[1]; val sc = eframe[2]
                    var ds = 0f; var dl = 0f
                    for (p in 0 until n) {
                        val tx = erx[p]; val ty = ery[p]
                        val ex = sx[p] - (tx - cx) * sc; val ey = sy[p] - (ty - cy) * sc
                        ds += sqrt(ex * ex + ey * ey)
                        var lx = ux[p] - tx; var ly = uy[p] - ty
                        if (p >= ovStart) {
                            val al = lx * ddx + ly * ddy
                            if (al > 0f) {
                                val cut = min(al, ov * ovDepth[p])
                                lx -= cut * ddx; ly -= cut * ddy
                            }
                        }
                        val d = sqrt(lx * lx + ly * ly) - tunnelW
                        if (d > 0f) dl += a[p] * d
                    }
                    ds = ds / n.toFloat()
                    dl = dl / alphaSum / w
                    var score = -(ds * ds) * invS - (dl * dl) * invL +
                        lam * en.freq[i].toFloat() / 255f + bias
                    if (params.lengthWeight > 0f)
                        score -= params.lengthWeight * lengthPenalty(pathLen, keyPathLength(ekx, eky, mk, w))
                    insertTop(score, fc + i, dl, m)
                }
            }
        }
    }

    private fun insertTop(s: Float, idx: Int, dl: Float, m: Int) {
        if (filled == m && s <= topScore[m - 1]) return
        var pos = if (filled < m) filled else m - 1
        while (pos > 0 && topScore[pos - 1] < s) {
            topScore[pos] = topScore[pos - 1]; topIdx[pos] = topIdx[pos - 1]; topDl[pos] = topDl[pos - 1]; pos--
        }
        topScore[pos] = s; topIdx[pos] = idx; topDl[pos] = dl
        if (filled < m) filled++
    }

    /** Đường trừ lệch tay ([offsetX]/[offsetY]); không lệch ⇒ chính mảng gốc. */
    private fun shifted(xs: FloatArray, ys: FloatArray, count: Int, w: Float): Pair<FloatArray, FloatArray> {
        if (offsetX == 0f && offsetY == 0f) return xs to ys
        if (bx.size < count) { bx = FloatArray(max(count, 64)); by = FloatArray(max(count, 64)) }
        val ox = offsetX * w; val oy = offsetY * w
        for (i in 0 until count) { bx[i] = xs[i] - ox; by[i] = ys[i] - oy }
        return bx to by
    }

    /** Phím của ứng viên [idx] (< fc: dạng VN; ≥ fc: từ tiếng Anh) → rkx/rky; số phím, ≤ 0 = không dựng được. */
    private fun candidateKeys(idx: Int, l: SwipeLayout, en: SwipeEnglish.Swipe?, fc: Int): Int {
        val keys: ByteArray; val lo: Int; val hi: Int
        if (idx < fc) {
            val forms = (tplVocab ?: SwipeVocab.current).forms
            keys = forms.keys; lo = forms.keyStart[idx]; hi = forms.keyStart[idx + 1]
        } else {
            if (en == null) return -1
            keys = en.keys; lo = en.keyStart[idx - fc]; hi = en.keyStart[idx - fc + 1]
        }
        if (hi - lo > rkx.size) return -1
        var k = 0
        for (j in lo until hi) {
            val c = keys[j].toInt()
            if (c !in 0 until 26) return -1
            val x = l.centers[c * 2]
            if (!x.isFinite()) return -1
            rkc[k] = c
            rkx[k] = x; rky[k] = l.centers[c * 2 + 1]; k++
        }
        return k
    }

    /**
     * Tầng 2 trên top-[filled]: σ location thích nghi (theo location tốt nhất), rồi trừ
     * chi phí căn phím + góc; xếp lại ổn định (bằng điểm giữ thứ tự cũ).
     */
    private fun rescore(xs: FloatArray, ys: FloatArray, ts: DoubleArray?, count: Int, l: SwipeLayout, invL: Float,
                        en: SwipeEnglish.Swipe?, fc: Int) {
        val w = l.keyWidth
        if (params.adaptThreshold > 0f && params.adaptMax > 1f) {
            var best = Float.MAX_VALUE
            for (k in 0 until filled) if (topDl[k] < best) best = topDl[k]
            var kk = best / params.adaptThreshold
            if (kk > params.adaptMax) kk = params.adaptMax
            if (kk > 1f) {
                val gain = invL * (1f - 1f / (kk * kk))
                for (k in 0 until filled) topScore[k] += topDl[k] * topDl[k] * gain
            }
        }
        resample(xs, ys, count, mx.size, mx, my)
        detectCorners(w)
        computeSpeed(xs, ys, ts, count)
        val t = params.rescoreTunnel * w
        val bend = params.bendWeight > 0f
        if (bend && poolLen.size < filled) {
            poolLen = IntArray(filled); poolKeys = ByteArray(filled * 32); poolHasH = BooleanArray(filled)
        }
        for (k in 0 until filled) {
            val km = candidateKeys(topIdx[k], l, en, fc)
            if (bend) {
                // 0 = không có h giữa ⇒ bỏ qua khi ghép cặp (đa số ứng viên)
                var hasH = false
                for (j in 1 until km - 1) if (rkc[j] == H) { hasH = true; break }
                poolLen[k] = if (km > 0) km else 0
                poolHasH[k] = hasH
                for (j in 0 until km) poolKeys[k * 32 + j] = rkc[j].toByte()
            }
            if (km <= 0) continue
            var cost = 0f
            if (params.alignWeight > 0f || speedOn) {
                val a = alignCost(km, t, w)
                if (params.alignWeight > 0f) cost += params.alignWeight * a
                cost += alignSpeed
            }
            if (params.cornerWeight > 0f && cornerCount > 0) {
                var c = 0f
                for (q in 0 until cornerCount) c += nearestKeyCost(mx[corners[q]], my[corners[q]], km, t, w)
                cost += params.cornerWeight * c
            }
            if (dwellCount > 0) {
                var c = 0f
                for (q in 0 until dwellCount) c += nearestKeyCost(mx[dwells[q]], my[dwells[q]], km, t, w)
                cost += params.dwellWeight * c
            }
            topScore[k] -= cost
        }
        if (bend) insertionBend(l, fc)
        // insertion sort ổn định, giảm dần
        for (i in 1 until filled) {
            val s = topScore[i]; val id = topIdx[i]; val d = topDl[i]
            var j = i
            while (j > 0 && topScore[j - 1] < s) {
                topScore[j] = topScore[j - 1]; topIdx[j] = topIdx[j - 1]; topDl[j] = topDl[j - 1]; j--
            }
            topScore[j] = s; topIdx[j] = id; topDl[j] = d
        }
    }

    /**
     * Cặp ứng viên B = A + một phím giữa K (cùng ngôn ngữ): B += w·kẹp(uốn − bias, ±cap), uốn =
     * d(K, dây cung phím trước–phím sau) − d(K, đường 48 điểm) (phím). Mỗi B lấy cặp A đầu tiên.
     */
    private fun insertionBend(l: SwipeLayout, fc: Int) {
        val w = l.keyWidth
        val c = l.centers
        for (b in 0 until filled) {
            val nb = poolLen[b]
            if (nb < 3 || !poolHasH[b]) continue
            val bEn = topIdx[b] >= fc
            for (a in 0 until filled) {
                if (poolLen[a] != nb - 1 || (topIdx[a] >= fc) != bEn) continue
                var j = 0
                while (j < nb - 1 && poolKeys[b * 32 + j] == poolKeys[a * 32 + j]) j++
                if (j == 0 || j >= nb - 1) continue
                var same = true
                for (q in j until nb - 1) if (poolKeys[b * 32 + q + 1] != poolKeys[a * 32 + q]) { same = false; break }
                if (!same) continue
                val kp = poolKeys[b * 32 + j - 1].toInt(); val kk = poolKeys[b * 32 + j].toInt()
                val kn = poolKeys[b * 32 + j + 1].toInt()
                if (kk != H || !(if (bEn) H_AFTER_EN else H_AFTER_VI)[kp]) continue
                val px = c[kp * 2]; val py = c[kp * 2 + 1]; val kx = c[kk * 2]; val ky = c[kk * 2 + 1]
                val nx = c[kn * 2]; val ny = c[kn * 2 + 1]
                val dx = nx - px; val dy = ny - py
                val len2 = dx * dx + dy * dy
                var u = if (len2 > 0f) ((kx - px) * dx + (ky - py) * dy) / len2 else 0f
                if (u < 0f) u = 0f else if (u > 1f) u = 1f
                val cx = kx - (px + u * dx); val cy = ky - (py + u * dy)
                val chord = sqrt(cx * cx + cy * cy) / w
                if (chord < params.bendMinChord || chord > params.bendMaxChord) break
                var best = Float.MAX_VALUE
                for (i in 0 until mx.size) {
                    val ex = mx[i] - kx; val ey = my[i] - ky
                    val q = ex * ex + ey * ey
                    if (q < best) best = q
                }
                var g = chord - sqrt(best) / w - params.bendBias
                if (g > params.bendCap) g = params.bendCap else if (g < -params.bendCap) g = -params.bendCap
                // chỉ đổi thứ tự TRONG cặp: B mới kẹp trong [min(A, B) − ε, max(A, B) + ε]
                val sa = topScore[a]; val sb = topScore[b]
                var v = sb + params.bendWeight * g
                val hi = (if (sa > sb) sa else sb) + BEND_EPS; val lo = (if (sa < sb) sa else sb) - BEND_EPS
                if (v > hi) v = hi else if (v < lo) v = lo
                topScore[b] = v
                break
            }
        }
    }

    /**
     * Nhịp tầng 2: thời gian tại mx/my (nội suy theo độ dài như [resample]) → tốc độ tương đối
     * spd[i] = v_i / v trung bình (sai phân trung tâm, kẹp ≤ 4), phạt tốc độ cho phím giữa
     * (spdPen) và điểm dừng (dwells). Không có ts / thời lượng ≈ 0 ⇒ tắt ([speedOn] = false).
     */
    private fun computeSpeed(xs: FloatArray, ys: FloatArray, ts: DoubleArray?, count: Int) {
        speedOn = false; dwellCount = 0
        if (ts == null || count < 2 || (params.speedWeight <= 0f && params.dwellWeight <= 0f)) return
        val m2 = mx.size
        resampleTime(xs, ys, ts, count, m2, mt)
        val total = mt[m2 - 1] - mt[0]
        if (!(total > 1e-3f)) return
        val unit = total / (m2 - 1).toFloat()
        for (i in 0 until m2) {
            val lo = if (i > 0) i - 1 else 0
            val hi = if (i < m2 - 1) i + 1 else m2 - 1
            val dt = mt[hi] - mt[lo]
            val need = (hi - lo).toFloat() * unit
            spd[i] = if (dt * 4f <= need) 4f else need / dt
        }
        speedOn = params.speedWeight > 0f
        for (i in 0 until m2) {
            val e = spd[i] - params.speedRef
            spdPen[i] = if (e > 0f) params.speedWeight * e else 0f
        }
        if (params.dwellWeight <= 0f) return
        val g = 2
        for (i in g until m2 - g) {
            val v = spd[i]
            if (v >= params.dwellRatio || v > spd[i - 1] || v > spd[i + 1]) continue
            if (dwellCount > 0 && i - dwells[dwellCount - 1] <= g) {
                if (v < spd[dwells[dwellCount - 1]]) dwells[dwellCount - 1] = i
            } else {
                dwells[dwellCount++] = i
            }
        }
    }

    /**
     * Đuôi nét CHẬM (trôi trước khi nhấc tay) ⇒ bật miễn lố: r = tốc độ tương đối trên
     * [Params.endSpan] độ dài cuối; r ≤ [Params.tailSlow] ⇒ 1, r ≥ [Params.tailFast] ⇒ 0, tuyến
     * tính giữa. Không có ts ⇒ 0.
     */
    private fun tailGate(xs: FloatArray, ys: FloatArray, ts: DoubleArray?, count: Int): Float {
        if (ts == null || count < 2) return 0f
        var total = 0f
        for (j in 0 until count - 1) total += segmentLength(xs, ys, j)
        val dur = (ts[count - 1] - ts[0]).toFloat()
        if (!(total > 1e-4f) || !(dur > 1e-3f)) return 0f
        val want = total * params.endSpan
        var acc = 0f
        var tail = 0f
        for (q in 0 until count - 1) {
            val j = count - 2 - q   // đoạn j: điểm j → j+1, từ cuối ngược lại
            val seg = segmentLength(xs, ys, j)
            val dt = (ts[j + 1] - ts[j]).toFloat()
            if (acc + seg >= want) {
                val u = if (seg > 0f) (want - acc) / seg else 0f
                tail += dt * u
                break
            }
            acc += seg; tail += dt
        }
        if (!(tail > 0f)) return 1f
        val r = params.endSpan * dur / tail
        val g = (params.tailFast - r) / (params.tailFast - params.tailSlow)
        return if (g <= 0f) 0f else if (g >= 1f) 1f else g
    }

    /** Góc gắt trên đường resample tầng 2 (cos góc rẽ < cos[Params.cornerDegrees]). */
    private fun detectCorners(w: Float) {
        cornerCount = 0
        if (params.cornerWeight <= 0f) return
        val m2 = mx.size; val g = 2; val minLen = 0.15f * w
        for (i in g until m2 - g) {
            val c = turnCos(i, g, minLen)
            if (c >= cosCorner) continue
            if (cornerCount > 0 && i - corners[cornerCount - 1] <= g) {
                if (c < turnCos(corners[cornerCount - 1], g, minLen)) corners[cornerCount - 1] = i
            } else {
                corners[cornerCount++] = i
            }
        }
    }

    /** cos góc rẽ tại điểm i (cạnh ±g điểm); cạnh < minLen ⇒ 1 (không tính là góc). */
    private fun turnCos(i: Int, g: Int, minLen: Float): Float {
        val ax = mx[i] - mx[i - g]; val ay = my[i] - my[i - g]
        val bx = mx[i + g] - mx[i]; val by = my[i + g] - my[i]
        val la = sqrt(ax * ax + ay * ay); val lb = sqrt(bx * bx + by * by)
        if (la < minLen || lb < minLen) return 1f
        return (ax * bx + ay * by) / (la * lb)
    }

    /** (khoảng cách tới phím gần nhất của ứng viên − tunnel)², đơn vị phím. */
    private fun nearestKeyCost(x: Float, y: Float, km: Int, t: Float, w: Float): Float {
        var best = Float.MAX_VALUE
        for (j in 0 until km) {
            val dx = x - rkx[j]; val dy = y - rky[j]
            var d = (sqrt(dx * dx + dy * dy) - t) / w
            if (d < 0f) d = 0f
            if (d < best) best = d
        }
        return best * best
    }

    /**
     * Căn đơn điệu km phím (rkx/rky) vào mx/my: trung bình (d − tunnel)² nhỏ nhất (phím). Cùng
     * vòng: [alignSpeed] = Σ spdPen tại điểm đường GẦN NHẤT mỗi phím giữa (phím nằm trên đoạn lướt
     * nhanh ⇒ không phải phím định đi); lấy điểm gần nhất, không theo căn DP, để DP không "giấu"
     * phím thừa vào chỗ dừng.
     */
    private fun alignCost(km: Int, t: Float, w: Float): Float {
        val m2 = mx.size
        val sp = speedOn
        alignSpeed = 0f
        for (j in 0 until km) {
            var run = Float.MAX_VALUE
            val mid = sp && j > 0 && j < km - 1
            var bq = Float.MAX_VALUE; var bi = 0
            for (i in 0 until m2) {
                val dx = mx[i] - rkx[j]; val dy = my[i] - rky[j]
                val q = dx * dx + dy * dy
                if (mid && q < bq) { bq = q; bi = i }
                var d = (sqrt(q) - t) / w
                if (d < 0f) d = 0f
                var prev = 0f
                if (j > 0) { val v = dp[(j - 1) * m2 + i]; if (v < run) run = v; prev = run }
                dp[j * m2 + i] = d * d + prev
            }
            if (mid) alignSpeed += spdPen[bi]
        }
        var best = Float.MAX_VALUE
        for (i in 0 until m2) { val v = dp[(km - 1) * m2 + i]; if (v < best) best = v }
        return best / km.toFloat()
    }

    /**
     * Học lệch tay từ một lượt vuốt người dùng ĐÃ CHẤP NHẬN là dạng [folded] (không dấu,
     * có trong lexicon): căn phím vào đường (đã trừ lệch hiện tại), lệch trung bình (kẹp
     * ±[Params.offsetCap] phím) → EMA [Params.offsetRate] vào [offsetX]/[offsetY].
     * false = không học (chưa có layout / dạng lạ / đường < 2 điểm).
     */
    fun learnOffset(xs0: FloatArray, ys0: FloatArray, count: Int, folded: String): Boolean {
        val l = layout ?: return false
        if (count < 2 || params.offsetRate <= 0f) return false
        val v = tplVocab ?: SwipeVocab.current
        val f = v.indexOf(folded)
        if (f < 0) return false
        val km = candidateKeys(f, l, null, v.forms.count)
        if (km <= 0) return false
        val w = l.keyWidth
        val (xs, ys) = shifted(xs0, ys0, count, w)
        val m2 = mx.size
        resample(xs, ys, count, m2, mx, my)
        for (j in 0 until km) {
            var run = Float.MAX_VALUE; var runI = 0
            for (i in 0 until m2) {
                val dx = mx[i] - rkx[j]; val dy = my[i] - rky[j]
                val d = sqrt(dx * dx + dy * dy) / w
                var prev = 0f
                if (j > 0) {
                    val v = dp[(j - 1) * m2 + i]
                    if (v < run) { run = v; runI = i }
                    prev = run; back[j * m2 + i] = runI
                }
                dp[j * m2 + i] = d * d + prev
            }
        }
        var bi = 0
        for (i in 1 until m2) if (dp[(km - 1) * m2 + i] < dp[(km - 1) * m2 + bi]) bi = i
        var sx = 0f; var sy = 0f
        var pos = bi
        for (j in km - 1 downTo 0) {
            sx += mx[pos] - rkx[j]; sy += my[pos] - rky[j]
            if (j > 0) pos = back[j * m2 + pos]
        }
        val cap = params.offsetCap
        val dx = (sx / km.toFloat() / w).coerceIn(-cap, cap)
        val dy = (sy / km.toFloat() / w).coerceIn(-cap, cap)
        offsetX += params.offsetRate * dx
        offsetY += params.offsetRate * dy
        return true
    }

    fun learnOffset(path: SwipePath, folded: String): Boolean = learnOffset(path.xs, path.ys, path.count, folded)

    companion object {
        private const val BEND_EPS = 0.01f
        private const val H = 'h' - 'a'
        /** Phím đứng trước h thành phụ âm ghép: Việt ch nh th ph kh gh; Anh th sh ch wh ph gh. */
        private val H_AFTER_VI = keySet("cntpkg")
        private val H_AFTER_EN = keySet("tscwpg")

        private fun keySet(s: String): BooleanArray = BooleanArray(26).also { m -> for (c in s) m[c - 'a'] = true }

        /**
         * Phân xử ngôn ngữ trên danh sách đã xếp (port Swift `arbitrate`): top-1 tiếng Anh
         * mà có ứng viên Việt kém < [margin] ⇒ ứng viên Việt đó lên đầu; top-K thiếu ngôn
         * ngữ kia mà pool có ⇒ NỐI THÊM ứng viên tốt nhất của ngôn ngữ kia (kết quả có thể
         * dài topK+1 — không chiếm chỗ ứng viên cùng ngôn ngữ).
         */
        fun arbitrate(sorted: List<SwipeCandidate>, topK: Int, margin: Float): List<SwipeCandidate> {
            val out = sorted.toMutableList()
            val first = out.firstOrNull()
            if (first != null && first.lang == SwipeLang.EN && margin > 0f) {
                val j = out.indexOfFirst { it.lang == SwipeLang.VI && it.score > first.score - margin }
                if (j >= 0) out.add(0, out.removeAt(j))
            }
            val top = out.take(topK).toMutableList()
            val lead = top.firstOrNull()?.lang
            if (topK >= 2 && lead != null && top.none { it.lang != lead }) {
                val other = out.firstOrNull { it.lang != lead }
                if (other != null) top.add(other)
            }
            return top
        }

        /**
         * Bung dạng không dấu → âm tiết có dấu, điểm = λ·tần suất/255 (+context), giảm dần.
         * Theo [SwipeVocab.current]: lọc bật ⇒ bỏ từ nhạy cảm; thêm từ chat/viết tắt (+ tục khi tắt lọc).
         */
        fun expand(
            folded: String, limit: Int = 8, lambdaFreq: Float = Params().lambdaFreq,
            context: ((String) -> Float)? = null,
        ): List<SwipeWord> {
            if (limit <= 0) return emptyList()
            val vocab = SwipeVocab.current
            val f = SwipeLexicon.indexOf(folded)
            val extra = vocab.words[folded]
            if (f < 0 && extra == null) return emptyList()
            val out = ArrayList<SwipeWord>()
            if (f >= 0) {
                val forms = SwipeLexicon.forms
                val b = VNLexicon2Data.blob
                for (id in forms.idStart[f] until forms.idStart[f + 1]) {
                    val w = VNSuggest.display(id)
                    if (vocab.filter && SwipeVocab.isSensitive(w)) continue
                    if (extra != null && extra.any { it.word == w }) continue   // bảng thay tần suất
                    var s = lambdaFreq * b.freq(id).toFloat() / 255f
                    if (context != null) s += context(w)
                    out.add(SwipeWord(w, s))
                }
            }
            if (extra != null) for (e in extra) {
                var s = lambdaFreq * e.score / 255f
                if (context != null) s += context(e.word)
                out.add(SwipeWord(e.word, s))
            }
            // ổn định: bằng điểm giữ thứ tự lexicon (id tăng)
            return out.sortedByDescending { it.score }.take(limit)
        }

        /** out[0..1] = hướng đơn vị phím áp chót → phím cuối (0, 0 nếu < 2 phím / trùng). */
        fun endDirection(kx: FloatArray, ky: FloatArray, m: Int, out: FloatArray) {
            out[0] = 0f; out[1] = 0f
            if (m < 2) return
            val dx = kx[m - 1] - kx[m - 2]; val dy = ky[m - 1] - ky[m - 2]
            val d = sqrt(dx * dx + dy * dy)
            if (d > 0f) { out[0] = dx / d; out[1] = dy / d }
        }

        /** Độ dài polyline (count điểm) theo đơn vị phím. */
        fun keyPathLength(xs: FloatArray, ys: FloatArray, count: Int, keyWidth: Float): Float {
            var s = 0f
            for (j in 0 until count - 1) {
                val dx = xs[j + 1] - xs[j]; val dy = ys[j + 1] - ys[j]
                s += sqrt(dx * dx + dy * dy)
            }
            return s / keyWidth
        }

        /**
         * ≈ ln²((a+1)/(b+1)) bằng 2(a−b)/(a+b+2) (xấp xỉ Padé của ln, bão hoà ở ±2 khi
         * lệch lớn) — thuần + − × ÷ nên Swift/Kotlin ra cùng bit.
         */
        fun lengthPenalty(a: Float, b: Float): Float {
            val r = 2f * (a - b) / (a + b + 2f)
            return r * r
        }

        /** Resample polyline (count điểm) thành n điểm cách đều theo độ dài. */
        fun resample(xs: FloatArray, ys: FloatArray, count: Int, n: Int, ox: FloatArray, oy: FloatArray) {
            var total = 0f
            if (count > 1) {
                for (j in 0 until count - 1) {
                    val dx = xs[j + 1] - xs[j]; val dy = ys[j + 1] - ys[j]
                    total += sqrt(dx * dx + dy * dy)
                }
            }
            if (count == 1 || total <= 1e-4f) {
                for (k in 0 until n) { ox[k] = xs[0]; oy[k] = ys[0] }
                return
            }
            val step = total / (n - 1).toFloat()
            ox[0] = xs[0]; oy[0] = ys[0]
            var j = 0; var acc = 0f
            var segLen = segmentLength(xs, ys, 0)
            for (k in 1 until n - 1) {
                val target = k.toFloat() * step
                while (j < count - 2 && acc + segLen < target) {
                    acc += segLen; j++
                    segLen = segmentLength(xs, ys, j)
                }
                var tt = if (segLen > 0f) (target - acc) / segLen else 0f
                if (tt < 0f) tt = 0f else if (tt > 1f) tt = 1f
                ox[k] = xs[j] + (xs[j + 1] - xs[j]) * tt
                oy[k] = ys[j] + (ys[j + 1] - ys[j]) * tt
            }
            ox[n - 1] = xs[count - 1]; oy[n - 1] = ys[count - 1]
        }

        /**
         * Thời gian (giây, gốc = ts[0], Float) tại n điểm resample của [resample] — cùng vòng
         * duyệt, nội suy tuyến tính trong đoạn.
         */
        fun resampleTime(xs: FloatArray, ys: FloatArray, ts: DoubleArray, count: Int, n: Int, ot: FloatArray) {
            var total = 0f
            if (count > 1) {
                for (j in 0 until count - 1) {
                    val dx = xs[j + 1] - xs[j]; val dy = ys[j + 1] - ys[j]
                    total += sqrt(dx * dx + dy * dy)
                }
            }
            val t0 = ts[0]
            if (count == 1 || total <= 1e-4f) {
                for (k in 0 until n) ot[k] = 0f
                return
            }
            val step = total / (n - 1).toFloat()
            ot[0] = 0f
            var j = 0; var acc = 0f
            var segLen = segmentLength(xs, ys, 0)
            for (k in 1 until n - 1) {
                val target = k.toFloat() * step
                while (j < count - 2 && acc + segLen < target) {
                    acc += segLen; j++
                    segLen = segmentLength(xs, ys, j)
                }
                var tt = if (segLen > 0f) (target - acc) / segLen else 0f
                if (tt < 0f) tt = 0f else if (tt > 1f) tt = 1f
                val a = (ts[j] - t0).toFloat(); val b = (ts[j + 1] - t0).toFloat()
                ot[k] = a + (b - a) * tt
            }
            ot[n - 1] = (ts[count - 1] - t0).toFloat()
        }

        private fun segmentLength(xs: FloatArray, ys: FloatArray, j: Int): Float {
            val dx = xs[j + 1] - xs[j]; val dy = ys[j + 1] - ys[j]
            return sqrt(dx * dx + dy * dy)
        }

        /** out = (trọng tâm x, y, 1 / max(cạnh bbox, 1 phím)). */
        fun shapeFrame(xs: FloatArray, ys: FloatArray, n: Int, keyWidth: Float, out: FloatArray) {
            var minX = xs[0]; var maxX = xs[0]; var minY = ys[0]; var maxY = ys[0]
            var sx = 0f; var sy = 0f
            for (i in 0 until n) {
                val x = xs[i]; val y = ys[i]
                if (x < minX) minX = x; if (x > maxX) maxX = x
                if (y < minY) minY = y; if (y > maxY) maxY = y
                sx += x; sy += y
            }
            val side = max(max(maxX - minX, maxY - minY), keyWidth)
            out[0] = sx / n.toFloat(); out[1] = sy / n.toFloat(); out[2] = 1f / side
        }
    }
}
