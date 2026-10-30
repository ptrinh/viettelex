package com.viettelex.keyboard

import java.text.Normalizer
import kotlin.math.exp
import kotlin.math.ln

/*
 * TouchTarget.kt — CHỌN PHÍM THEO NGỮ CẢNH lúc chạm (thử nghiệm, kiểu iOS "dynamic touch
 * targets"). Song sinh iOS/Keyboard/TouchTarget.swift — sửa ở đây thì sửa y hệt bên kia.
 *
 * Router cũ chọn phím GẦN NHẤT. Ở đây, khi điểm chạm rơi vào VÙNG BIÊN giữa 2 phím, chọn
 * argmax P(điểm | phím) · P(phím | các phím Telex đã gõ trong từ) — P ngữ cảnh lấy từ trie
 * chuỗi phím Telex dựng từ vnlexicon (tần suất). Ràng buộc chống cướp phím:
 *  - điểm trong LÕI phím gần nhất ⇒ luôn phím đó (tâm phím luôn thắng);
 *  - chỉ xét phím kề mà điểm chạm nằm sát (≤ [TouchTargetParams.reach] bề rộng phím);
 *  - chỉ đổi khi log-điểm hơn ≥ [TouchTargetParams.margin];
 *  - chuỗi phím đang gõ không có trong trie (tên riêng, viết tắt, từ Anh lạ…) ⇒ không đổi.
 * Chữ đã chèn KHÔNG bao giờ bị thay: quyết định xảy ra đúng một lần lúc touchDown.
 * Tham số chọn bằng mô phỏng gõ chạm (TouchSimTests — câu Tatoeba giữ lại).
 * Android đọc trie dựng SẴN (asset keyprior.bin, [KeyPriorBlob] — RAM-AUDIT #1); iOS vẫn dựng
 * trong RAM từ lexicon — cùng thuật toán, cùng số (KeyPriorBlobTests chốt asset ≡ [TelexKeyPrior.fromLexicon]).
 */

/** Chuỗi phím Telex cho một âm tiết tiếng Việt (để dựng trie ngữ cảnh). */
object TelexSpell {
    private const val VOWELS = "aeiouy"

    /**
     * Các cách gõ Telex phổ biến của [syllable] (chữ thường) kèm tỉ trọng (tổng 1):
     * dấu thanh ở cuối (0.6) hoặc ngay sau nguyên âm trước phụ âm cuối (0.4); "ươ" gõ
     * "uwow" hoặc "uow". null nếu có ký tự ngoài chữ Việt.
     */
    fun variants(syllable: String): List<Pair<String, Float>>? {
        val d = Normalizer.normalize(syllable.lowercase(), Normalizer.Form.NFD)
        val chars = ArrayList<String>()      // phím cho từng chữ
        var tone = 0.toChar()
        for (ch in d) {
            when (ch.code) {
                0x302 -> { val k = chars.lastOrNull() ?: return null; chars[chars.size - 1] = k + k }
                0x306, 0x31B -> {
                    val k = chars.lastOrNull() ?: return null
                    chars[chars.size - 1] = k + "w"
                }
                0x301 -> tone = 's'
                0x300 -> tone = 'f'
                0x309 -> tone = 'r'
                0x303 -> tone = 'x'
                0x323 -> tone = 'j'
                0x111 -> chars.add("dd")
                in 'a'.code..'z'.code -> chars.add(ch.toString())
                else -> return null
            }
        }
        if (chars.isEmpty()) return null
        var lastVowel = -1
        for (i in chars.indices) if (chars[i][0] in VOWELS && !(chars[i] == "dd")) lastVowel = i
        val cores = ArrayList<List<String>>()
        cores.add(chars)
        for (i in 0 until chars.size - 1) {
            if (chars[i] == "uw" && chars[i + 1] == "ow") {
                cores.add(chars.toMutableList().also { it[i] = "u" })
            }
        }
        val out = ArrayList<Pair<String, Float>>()
        val share = 1f / cores.size
        for (c in cores) {
            val all = c.joinToString("")
            if (tone == 0.toChar()) { out.add(all to share); continue }
            val hasCoda = lastVowel >= 0 && lastVowel < c.size - 1
            if (!hasCoda) { out.add(all + tone to share); continue }
            out.add(all + tone to share * 0.6f)
            val head = c.subList(0, lastVowel + 1).joinToString("")
            val coda = c.subList(lastVowel + 1, c.size).joinToString("")
            out.add(head + tone + coda to share * 0.4f)
        }
        return out
    }
}

/**
 * Trie chuỗi phím a–z, mỗi nút mang tổng trọng số các chuỗi đi qua. Hai cách chứa, CÙNG kết
 * quả: [Builder] (mảng CSR trên heap — test/sweep tham số) và [mapped] (asset keyprior.bin
 * mmap — IME: 0 heap, trang sạch; xem [KeyPriorBlob]).
 */
abstract class KeyTrie {
    abstract val nodeCount: Int

    /** Con của [node] theo phím [key] (0…25), -1 nếu không có. */
    abstract fun child(node: Int, key: Int): Int

    abstract fun weight(node: Int): Float

    /** Nút của chuỗi [raw] (chữ a–z, hoa thường như nhau), -1 nếu không có. */
    fun node(raw: CharSequence): Int {
        var n = 0
        for (ch in raw) {
            val k = ch.lowercaseChar() - 'a'
            if (k !in 0 until 26) return -1
            n = child(n, k)
            if (n < 0) return -1
        }
        return n
    }

    /** CSR trên heap (thứ tự nút = thứ tự chèn). */
    private class Arrays(
        val edgeStart: IntArray,   // [node] → dải cạnh; size = nodes + 1
        val edgeKey: ByteArray,    // 0…25, tăng dần trong dải
        val edgeTo: IntArray,
        val weights: FloatArray,
    ) : KeyTrie() {
        override val nodeCount: Int get() = weights.size
        override fun child(node: Int, key: Int): Int {
            for (e in edgeStart[node] until edgeStart[node + 1]) {
                val k = edgeKey[e].toInt()
                if (k == key) return edgeTo[e]
                if (k > key) return -1
            }
            return -1
        }
        override fun weight(node: Int): Float = weights[node]
    }

    /**
     * Trie trên buffer [KeyPriorBlob] (little-endian, đọc absolute ⇒ thread-safe). Nút đánh số
     * BFS nên con của cạnh e là nút e + 1 — khỏi lưu edgeTo.
     */
    private class Mapped(private val b: java.nio.ByteBuffer, override val nodeCount: Int,
                         private val startOff: Int, private val weightOff: Int, private val keyOff: Int) : KeyTrie() {
        override fun child(node: Int, key: Int): Int {
            val end = b.getInt(startOff + 4 * (node + 1))
            var e = b.getInt(startOff + 4 * node)
            while (e < end) {
                val k = b.get(keyOff + e).toInt()
                if (k == key) return e + 1
                if (k > key) return -1
                e++
            }
            return -1
        }
        override fun weight(node: Int): Float = b.getFloat(weightOff + 4 * node)
    }

    class Builder {
        private val children = HashMap<Long, Int>()
        private val weights = ArrayList<Float>().apply { add(0f) }

        fun add(keys: String, w: Float) {
            if (w <= 0f || keys.isEmpty() || keys.any { it !in 'a'..'z' }) return
            var n = 0
            weights[0] = weights[0] + w
            for (ch in keys) {
                val key = n.toLong() * 32 + (ch - 'a')
                var c = children[key]
                if (c == null) { c = weights.size; weights.add(0f); children[key] = c }
                weights[c] = weights[c] + w
                n = c
            }
        }

        fun build(): KeyTrie {
            val n = weights.size
            val edges = children.entries.map { it.key to it.value }.sortedBy { it.first }
            val start = IntArray(n + 1)
            for ((k, _) in edges) start[(k / 32).toInt() + 1]++
            for (i in 0 until n) start[i + 1] += start[i]
            val key = ByteArray(edges.size); val to = IntArray(edges.size)
            for ((i, e) in edges.withIndex()) { key[i] = (e.first % 32).toByte(); to[i] = e.second }
            return Arrays(start, key, to, FloatArray(n) { weights[it] })
        }
    }

    companion object {
        /** Trie đọc tại chỗ từ blob [KeyPriorBlob] (null = sai magic/phiên bản/cỡ). */
        fun mapped(buf: java.nio.ByteBuffer): KeyTrie? {
            val b = buf.duplicate().order(java.nio.ByteOrder.LITTLE_ENDIAN)
            val h = KeyPriorBlob.header(b) ?: return null
            return Mapped(b, h.nodes, KeyPriorBlob.HEADER, KeyPriorBlob.HEADER + 4 * (h.nodes + 1),
                KeyPriorBlob.HEADER + 8 * h.nodes + 4)
        }
    }
}

/**
 * keyprior.bin — trie [TelexKeyPrior] dựng SẴN (sinh bằng `VT_REGEN_KEYPRIOR=1 ./gradlew
 * :keyboard:test --tests '*KeyPriorBlobTests*'`, test parity chặn asset lệch dữ liệu nguồn).
 * Little-endian:
 *   "VTKP" | version u32 | nodes u32 | edges u32 | crc32(vnlexicon ‖ enlexicon ‖ seed) u32 |
 *   lambda f32 | englishShare f32 | 0 u32                                  (32 byte)
 *   edgeStart[nodes + 1] u32 · weight[nodes] f32 · edgeKey[edges] u8
 * Nút đánh số BFS (gốc 0, con theo thứ tự phím) ⇒ cạnh e (xếp theo cha rồi phím) trỏ tới
 * nút e + 1. ~9 byte/nút (63k nút ≈ 570 KB), asset không nén ⇒ mmap.
 */
object KeyPriorBlob {
    const val MAGIC = 0x504B5456 // "VTKP" LE
    const val VERSION = 1
    const val HEADER = 32

    class Header(val nodes: Int, val edges: Int, val inputCrc: Int, val lambda: Float, val englishShare: Float)

    fun header(b: java.nio.ByteBuffer): Header? {
        if (b.capacity() < HEADER || b.getInt(0) != MAGIC || b.getInt(4) != VERSION) return null
        val n = b.getInt(8); val e = b.getInt(12)
        if (n <= 0 || e != n - 1 || b.capacity().toLong() < HEADER + 8L * n + 4 + e) return null
        return Header(n, e, b.getInt(16), b.getFloat(20), b.getFloat(24))
    }

    /** Mã hoá [t] (bất kỳ cách chứa) sang blob — đánh số lại nút theo BFS. */
    fun encode(t: KeyTrie, inputCrc: Int, lambda: Float, englishShare: Float): ByteArray {
        val n = t.nodeCount
        val order = IntArray(n)           // BFS id → nút gốc
        val start = IntArray(n + 1)
        val keys = java.io.ByteArrayOutputStream(n)
        var tail = 1
        for (id in 0 until n) {
            require(id < tail) { "trie không liên thông" }
            val node = order[id]
            start[id] = tail - 1
            for (k in 0 until 26) {
                val c = t.child(node, k)
                if (c >= 0) { order[tail++] = c; keys.write(k) }
            }
        }
        start[n] = tail - 1
        require(tail == n)
        val e = n - 1
        val out = java.nio.ByteBuffer.allocate(HEADER + 8 * n + 4 + e).order(java.nio.ByteOrder.LITTLE_ENDIAN)
        out.putInt(MAGIC).putInt(VERSION).putInt(n).putInt(e).putInt(inputCrc)
            .putFloat(lambda).putFloat(englishShare).putInt(0)
        for (i in 0..n) out.putInt(start[i])
        for (i in 0 until n) out.putFloat(t.weight(order[i]))
        out.put(keys.toByteArray())
        return out.array()
    }

    /** CRC32 các asset nguồn — asset keyprior.bin cũ hơn dữ liệu ⇒ test đỏ, sinh lại. */
    fun inputCrc(): Int {
        val crc = java.util.zip.CRC32()
        for (name in listOf(Keys.ASSET_LEXICON, Keys.ASSET_EN_LEXICON, Keys.ASSET_SEED)) {
            val d = KeyboardData.buffer(name).duplicate(); d.position(0)
            val a = ByteArray(d.remaining()); d.get(a); crc.update(a)
        }
        return crc.value.toInt()
    }
}

/** Tham số chọn phím (GIỮ Y HỆT bản Swift). Đơn vị: bề rộng / cao MẶT phím gần nhất. */
data class TouchTargetParams(
    /** σ Gaussian điểm chạm quanh tâm phím (theo bề rộng / cao phím). */
    val sigmaX: Float,
    val sigmaY: Float,
    /** Lõi phím: điểm cách mép mặt phím > core·bề rộng (cao) ⇒ không bao giờ đổi. */
    val coreX: Float,
    val coreY: Float,
    /** Phím kề chỉ được xét khi điểm cách mặt phím đó ≤ reach·bề rộng. */
    val reach: Float,
    /** Log-điểm phím kề phải hơn phím gần nhất ≥ margin (nat). */
    val margin: Float,
    /** Trộn đều: P = (1-floor)·P_trie + floor/26 — từ lạ không bị ép. */
    val floor: Float,
)

object TouchTarget {
    // σ dò lại 30/10/2026 (TouchSimTests.sigmaSweep, TOUCHSIM_SIGMA=1|test): σy < σx làm tăng lỗi khác hàng
    // (σ theo cao phím đã gồm phím cao hơn rộng); σx 0.33–0.35 bớt lỗi Việt nhưng tăng đổi nhầm + lỗi chat ⇒ giữ 0.30/0.30.
    val DEFAULT = TouchTargetParams(
        sigmaX = 0.30f, sigmaY = 0.30f, coreX = 0.25f, coreY = 0.25f,
        reach = 0.45f, margin = 1.0f, floor = 0.20f,
    )

    /**
     * Chọn phím chữ cho điểm [p] (đã qua [TouchGeometry.keySelectionPoint]) khi router
     * gần-nhất ra [nearest]. [keys] = ký tự từng phím (cùng thứ tự [rects]), [prior] trả
     * P(phím | ngữ cảnh) hoặc null nếu không biết. Trả index phím (== nearest nếu không đổi).
     */
    fun choose(
        p: KPoint, rects: List<KRect>, keys: CharArray, nearest: Int,
        prior: (Char) -> Float?, params: TouchTargetParams = DEFAULT,
    ): Int {
        if (nearest < 0 || nearest >= rects.size) return nearest
        val r = rects[nearest]
        val w = r.right - r.left; val h = r.bottom - r.top
        if (w <= 0f || h <= 0f || nearest >= keys.size || !isLetter(keys[nearest]) || inCore(p, r, params)) return nearest
        val p0 = prior(keys[nearest]) ?: return nearest
        val s0 = score(p, r, w, h, p0, params)
        var best = nearest; var bestS = s0 + params.margin
        val lim = params.reach * w
        for (i in rects.indices) {
            if (i == nearest || i >= keys.size || !isLetter(keys[i])) continue
            val f = rects[i]
            val dx = maxOf(f.left - p.x, 0f, p.x - f.right)
            val dy = maxOf(f.top - p.y, 0f, p.y - f.bottom)
            if (dx > lim || dy > lim) continue
            if (dx * dx + dy * dy > lim * lim) continue
            val pi = prior(keys[i]) ?: continue
            val s = score(p, f, w, h, pi, params)
            if (s > bestS) { best = i; bestS = s }
        }
        return best
    }

    /** Chỉ phím chữ a–z tham gia: "." "," "'"… KHÔNG bao giờ bị đổi sang chữ (hay ngược lại) dù prior nói gì. */
    private fun isLetter(c: Char) = c in 'a'..'z' || c in 'A'..'Z'

    /** [p] trong LÕI mặt phím [r] (cách mọi mép > core) ⇒ phím đó thắng, khỏi tính gì thêm. */
    fun inCore(p: KPoint, r: KRect, params: TouchTargetParams = DEFAULT): Boolean {
        val inX = minOf(p.x - r.left, r.right - p.x)
        val inY = minOf(p.y - r.top, r.bottom - p.y)
        return inX > params.coreX * (r.right - r.left) && inY > params.coreY * (r.bottom - r.top)
    }

    private fun score(p: KPoint, f: KRect, w: Float, h: Float, prior: Float, q: TouchTargetParams): Float {
        val ux = (p.x - (f.left + f.right) / 2) / (q.sigmaX * w)
        val uy = (p.y - (f.top + f.bottom) / 2) / (q.sigmaY * h)
        val pr = (1 - q.floor) * prior + q.floor / 26f
        return -0.5f * (ux * ux + uy * uy) + ln(pr)
    }
}

/** P(phím kế | chuỗi phím Telex đã gõ trong từ) từ trie tần suất vnlexicon. */
class TelexKeyPrior(val trie: KeyTrie) {
    /**
     * Prior theo kiểu gõ: trie dựng theo chuỗi phím TELEX (ee/aw/dd, s f r x j) — VNI (số là
     * phím dấu) không khớp ⇒ null, router gần-nhất như cũ. iOS: forTyping(_:vniMode:).
     */
    fun forTyping(raw: CharSequence, vniMode: Boolean): ((Char) -> Float?)? = if (vniMode) null else forRaw(raw)

    /** Hàm prior cho router: null nếu [raw] ngoài trie (không biết ⇒ không đổi phím). */
    fun forRaw(raw: CharSequence): ((Char) -> Float?)? {
        if (raw.length > MAX_RAW) return null
        val n = trie.node(raw)
        if (n < 0) return null
        val total = trie.weight(n)
        if (total <= 0f) return null
        return { ch ->
            val k = ch.lowercaseChar() - 'a'
            if (k !in 0 until 26) null else {
                val c = trie.child(n, k)
                if (c < 0) 0f else trie.weight(c) / total
            }
        }
    }

    companion object {
        const val MAX_RAW = 12
        /** Thang tần suất vnlexicon: byte f ≈ 255·ln(count)/ln(max) ⇒ trọng số exp(λ·f). */
        const val LAMBDA = 0.06f

        /** Tỉ trọng từ tiếng Anh (enlexicon, cùng thang tần suất) so với âm tiết Việt. */
        const val ENGLISH = 0.1f

        /**
         * [syllables]: âm tiết Việt + tần suất vnlexicon (0–255); [english]: từ Anh (cùng thang)
         * nhân [englishShare]; [chat]: từ chat/viết tắt gõ nguyên phím (ko, dc, ok…, cùng thang).
         */
        fun build(
            syllables: Sequence<Pair<String, Int>>, english: Sequence<Pair<String, Int>> = emptySequence(),
            chat: Sequence<Pair<String, Int>> = emptySequence(),
            lambda: Float = LAMBDA, englishShare: Float = ENGLISH,
        ): TelexKeyPrior {
            val b = KeyTrie.Builder()
            for ((s, f) in syllables) {
                val w = exp(lambda * (f - 255)).toFloat()
                for ((keys, share) in TelexSpell.variants(s) ?: continue) b.add(keys, w * share)
            }
            if (englishShare > 0f) for ((word, f) in english) b.add(word, englishShare * exp(lambda * (f - 255)).toFloat())
            for ((word, f) in chat) b.add(word, exp(lambda * (f - 255)).toFloat())
            return TelexKeyPrior(b.build())
        }

        /** Seed chat (log, max 50) → thang vnlexicon. Chỉ từ gõ nguyên phím a–z (ko, dc, ok, haha…). */
        fun chatWords(seed: Map<String, Int>): Sequence<Pair<String, Int>> =
            seed.asSequence().filter { (w, _) -> w.isNotEmpty() && w.all { it in 'a'..'z' } }
                .map { (w, c) -> w to (c * 51 / 10).coerceIn(0, 255) }

        /** Dựng từ vnlexicon + enlexicon + seed chat — vài chục ms, gọi ngoài main thread. */
        fun fromLexicon(lambda: Float = LAMBDA, englishShare: Float = ENGLISH): TelexKeyPrior {
            // Parse riêng (không giữ SwipeEnglish.lexicon ~20k String trong RAM khi tắt gõ vuốt).
            val en = try { SwipeEnglish.parse(KeyboardData.buffer(Keys.ASSET_EN_LEXICON)) } catch (e: Exception) { null }
                ?: SwipeEnglish.Lexicon(emptyArray(), IntArray(0), ByteArray(0), IntArray(1), IntArray(0), IntArray(677))
            val seed = try { SeedData.unigrams } catch (e: Exception) { emptyMap() }
            return build(
                (0 until VNLexicon2Data.count).asSequence().map { VNSuggest.display(it) to VNSuggest.freq(it) },
                (0 until en.count).asSequence().map { en.words[it] to en.freq[it] },
                chatWords(seed).filter { !VNSuggest.contains(it.first) }, lambda, englishShare,
            )
        }

        /**
         * Trie dựng sẵn trong asset [Keys.ASSET_KEY_PRIOR] (mmap: 0 heap, không rác) — null nếu
         * thiếu/hỏng hoặc sinh với tham số khác mặc định (khi đó [warmUp] dựng như cũ).
         */
        fun fromAsset(): TelexKeyPrior? = try {
            val b = KeyboardData.buffer(Keys.ASSET_KEY_PRIOR)
            val h = KeyPriorBlob.header(b)
            if (h == null || h.lambda != LAMBDA || h.englishShare != ENGLISH) null
            else KeyTrie.mapped(b)?.let { TelexKeyPrior(it) }
        } catch (e: Exception) { null }

        @Volatile private var cached: TelexKeyPrior? = null
        /** Bảng dùng chung; null tới khi [warmUp] xong (router coi như tắt). */
        val sharedIfReady: TelexKeyPrior? get() = cached
        /** Asset mmap (vài µs); asset thiếu ⇒ dựng từ lexicon (~31 MB rác, gọi ngoài main). */
        fun warmUp(): TelexKeyPrior = cached ?: synchronized(this) {
            cached ?: (fromAsset() ?: fromLexicon()).also { cached = it }
        }
        /** Tắt tính năng: bỏ tham chiếu (trang mmap sạch, kernel tự thu); [warmUp] mở lại khi cần. */
        fun release() { cached = null }
    }
}
