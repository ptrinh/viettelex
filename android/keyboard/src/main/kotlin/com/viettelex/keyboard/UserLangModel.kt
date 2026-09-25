package com.viettelex.keyboard

import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import kotlin.math.pow

/**
 * Datastore cá nhân hoá cho thanh gợi ý (port 1:1 iOS UserLangModel): uni / bi
 * (prev → next → count) / tri ("p2␁p1" → next → count), shrinkage, learning-vs-
 * suggesting (từ lạ cần count ≥3), decay ×0.7/tuần, cap halve-when-full.
 *
 * THREADING: mọi đọc/ghi bảng trên MAIN thread (như iOS). Decode/encode/IO trên [io];
 * kết quả load trả về qua [main]. Persist binary `filesDir/userlm.bin`, ghi atomic
 * (file tạm + rename), coalesce 5 s sau record cuối.
 *
 * PRIVACY: chỉ đếm tần suất.
 */
class UserLangModel(
    /** null = in-memory (tests): sẵn sàng ngay, không IO. Có file ⇒ load nền ngay. */
    private val file: File? = null,
    private val main: MainThread = ImmediateMainThread(),
    ioExecutor: Executor? = null,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    private val io: Executor by lazy {
        ioExecutor ?: Executors.newSingleThreadExecutor { r ->
            Thread(r, "vt-userlm-io").apply { isDaemon = true; priority = Thread.MIN_PRIORITY }
        }
    }

    private var uni = HashMap<String, Int>()
    private var bi = HashMap<String, HashMap<String, Int>>()
    private var tri = HashMap<String, HashMap<String, Int>>()
    private var lastDecay = clock()
    private var biPairs = 0
    private var triPairs = 0
    private var uniTotal = 0

    /** Lexicon tĩnh (VNSuggest.contains). Mặc định false để test kiểm soát. */
    var isKnownWord: (String) -> Boolean = { false }
        set(v) { field = v; knownCache.clear(); topCache = null }

    /** Gọi trên main khi bảng trên đĩa swap-in xong (IME refresh bar). */
    var onReady: (() -> Unit)? = null

    private var saveWork: Cancellable? = null
    private var isLoaded = false
    private var loadGeneration = 0
    private class PendingRecord(val word: String, val prev1: String?, val prev2: String?, val weight: Int)
    private val pendingRecords = ArrayList<PendingRecord>()
    private var pendingSeed: (() -> SeedData.Seed)? = null
    /** Nguồn seed gần nhất — để [reloadAfterExternalErase] seed lại. */
    private var seedSource: (() -> SeedData.Seed)? = null

    private val knownCache = HashMap<String, Boolean>()
    private var topCacheK = 0
    private var topCache: List<String>? = null

    companion object {
        const val UNI_CAP = 3000
        const val BI_CAP = 6000
        const val TRI_CAP = 3000
        const val UNKNOWN_SUGGEST_THRESHOLD = 3
        const val PENDING_RECORD_CAP = 128
        const val SEP = "\u0001"
        private const val MAGIC = 0x56544C4D // "VTLM"
        private const val VERSION = 1
        private const val WEEK_MS = 7L * 86_400_000L

        /** Từ "học được": chữ cái thuần, ≤12, không chuỗi lặp ≥3 ("heeeyyy"). */
        fun learnable(w: String): Boolean {
            if (w.isEmpty()) return false
            var n = 0; var run = 1; var prev = -1
            var i = 0
            while (i < w.length) {
                val c = w.codePointAt(i)
                if (!Character.isLetter(c)) return false
                run = if (c == prev) run + 1 else 1
                if (run >= 3) return false
                prev = c; n++
                i += Character.charCount(c)
            }
            return n <= 12
        }
    }

    init {
        if (file != null) loadAsync(file) else isLoaded = true
    }

    private fun loadAsync(f: File) {
        val gen = loadGeneration
        io.execute {
            val t = readTables(f)
            main.post { if (loadGeneration == gen) finishLoad(t) }
        }
    }

    private class Tables(val uni: HashMap<String, Int>, val bi: HashMap<String, HashMap<String, Int>>,
                         val tri: HashMap<String, HashMap<String, Int>>, val lastDecay: Long)

    private fun finishLoad(t: Tables?) {
        if (t != null) {
            uni = t.uni; bi = t.bi; tri = t.tri; lastDecay = t.lastDecay
            recount()
        }
        isLoaded = true
        topCache = null
        val seed = pendingSeed
        if (uni.isEmpty() && seed != null) applySeed(seed())
        pendingSeed = null
        val queued = pendingRecords.toList()
        pendingRecords.clear()
        for (r in queued) record(r.word, r.prev1, r.prev2, r.weight)
        decayIfDue()
        onReady?.invoke()
    }

    private fun recount() {
        biPairs = bi.values.sumOf { it.size }
        triPairs = tri.values.sumOf { it.size }
        uniTotal = uni.values.sum()
    }

    // MARK: học

    /** Một từ vừa chốt; weight 1 gõ thường, 2 khi bấm nhận gợi ý. */
    fun record(word: String, after: String?, prev2: String? = null, weight: Int = 1) {
        if (!isLoaded) {
            if (pendingRecords.size < PENDING_RECORD_CAP) pendingRecords.add(PendingRecord(word, after, prev2, weight))
            return
        }
        if (!learnable(word)) return
        val w = word.lowercase()
        uni[w] = (uni[w] ?: 0) + weight
        uniTotal += weight
        topCache = null
        val p1 = after?.lowercase()
        if (p1 != null && learnable(p1)) {
            val b = bi.getOrPut(p1) { HashMap() }
            if (b[w] == null) biPairs++
            b[w] = (b[w] ?: 0) + weight
            val p2 = prev2?.lowercase()
            if (p2 != null && learnable(p2) && (bi[p2]?.get(p1) ?: 0) >= 2) {
                val t = tri.getOrPut(p2 + SEP + p1) { HashMap() }
                if (t[w] == null) triPairs++
                t[w] = (t[w] ?: 0) + weight
            }
        }
        pruneIfNeeded()
        scheduleSave()
    }

    private fun cachedKnown(w: String): Boolean {
        knownCache[w]?.let { return it }
        if (knownCache.size > 4096) knownCache.clear()
        val v = isKnownWord(w)
        knownCache[w] = v
        return v
    }

    private fun suggestable(w: String) = cachedKnown(w) || (uni[w] ?: 0) >= UNKNOWN_SUGGEST_THRESHOLD

    // MARK: gợi ý

    /** Top từ hay dùng (ô trống). Cache tới khi uni đổi. */
    fun topWords(limit: Int): List<String> {
        topCache?.let { if (topCacheK >= limit) return it.take(limit) }
        val sorted = uni.entries.sortedWith(compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key })
        val out = ArrayList<String>(limit)
        for ((w, _) in sorted) {
            if (!suggestable(w)) continue
            out.add(w)
            if (out.size >= limit) break
        }
        topCache = out; topCacheK = limit
        return out
    }

    /** Từ kế tiếp sau (prev2, prev1): tri ⊕ bi ⊕ uni ⊕ seed với shrinkage. */
    fun nextWords(after: String, prev2: String? = null, limit: Int): List<String> {
        val p1 = after.lowercase()
        val biBucket: Map<String, Int> = bi[p1] ?: emptyMap()
        val triBucket: Map<String, Int> = prev2?.let { tri[it.lowercase() + SEP + p1] } ?: emptyMap()
        val seeds = seedNext[p1] ?: emptyList()
        val biTotal = biBucket.values.sum()
        val triTotal = triBucket.values.sum()
        val uniT = maxOf(uniTotal, 1)
        val lamTri = triTotal.toDouble() / (triTotal + 2.0)
        val lamBi = biTotal.toDouble() / (biTotal + 4.0)
        val cands = LinkedHashSet<String>()
        cands.addAll(biBucket.keys); cands.addAll(triBucket.keys); cands.addAll(seeds)
        fun score(w: String): Double {
            val pTri = if (triTotal > 0) (triBucket[w] ?: 0).toDouble() / triTotal else 0.0
            val pBi = if (biTotal > 0) (biBucket[w] ?: 0).toDouble() / biTotal else 0.0
            val pUni = (uni[w] ?: 0).toDouble() / uniT
            val i = seeds.indexOf(w)
            val pSeed = if (i >= 0) 0.5.pow(i) else 0.0
            return lamTri * pTri + lamBi * pBi + 0.1 * pUni + (1 - lamBi) * 0.9 * pSeed
        }
        return cands.filter { suggestable(it) || it in seeds }
            .map { it to score(it) }
            .sortedWith(compareByDescending<Pair<String, Double>> { it.second }.thenBy { it.first })
            .take(limit).map { it.first }
    }

    /** Điểm cá nhân của một từ. */
    fun count(of: String): Int = uni[of] ?: uni[of.lowercase()] ?: 0

    /**
     * Seed khi store trống. [seed] chỉ được gọi khi thật sự seed; đang chờ load thì
     * giữ lại quyết sau swap-in.
     */
    fun seedIfEmpty(seed: () -> SeedData.Seed = SeedData::load) {
        seedSource = seed
        if (!isLoaded) { pendingSeed = seed; return }
        if (uni.isNotEmpty()) return
        applySeed(seed())
    }

    /** Tiện cho test: seed từ map/list trực tiếp. */
    fun seedIfEmpty(unigrams: Map<String, Int>, bigrams: List<Triple<String, String, Int>>) =
        seedIfEmpty { SeedData.Seed(unigrams, bigrams) }

    private fun applySeed(s: SeedData.Seed) {
        uni = HashMap(s.unigrams)
        uniTotal = uni.values.sum()
        for ((a, b, c) in s.bigrams) {
            val m = bi.getOrPut(a) { HashMap() }
            if (m[b] == null) biPairs++
            m[b] = c
        }
        topCache = null
        save()
    }

    // MARK: persistence

    private fun readTables(f: File): Tables? {
        if (!f.exists()) return null
        return try {
            DataInputStream(BufferedInputStream(FileInputStream(f), 32 * 1024)).use { d ->
                if (d.readInt() != MAGIC) return null
                if (d.readInt() != VERSION) return null
                val lastDecay = d.readLong()
                val nu = d.readInt()
                val uni = HashMap<String, Int>(nu * 2)
                repeat(nu) { uni[d.readUTF()] = d.readInt() }
                fun nested(): HashMap<String, HashMap<String, Int>> {
                    val n = d.readInt()
                    val m = HashMap<String, HashMap<String, Int>>(n * 2)
                    repeat(n) {
                        val k = d.readUTF(); val c = d.readInt()
                        val inner = HashMap<String, Int>(c * 2)
                        repeat(c) { inner[d.readUTF()] = d.readInt() }
                        m[k] = inner
                    }
                    return m
                }
                val bi = nested(); val tri = nested()
                Tables(uni, bi, tri, lastDecay)
            }
        } catch (e: Exception) { null }
    }

    private class Snapshot(val uni: Map<String, Int>, val bi: Map<String, Map<String, Int>>,
                           val tri: Map<String, Map<String, Int>>, val lastDecay: Long)

    private fun snapshot(): Snapshot {
        // copy nông trên main (rẻ so với encode + IO) — nền encode bản copy
        return Snapshot(HashMap(uni), bi.mapValuesTo(HashMap()) { HashMap(it.value) },
            tri.mapValuesTo(HashMap()) { HashMap(it.value) }, lastDecay)
    }

    private fun write(s: Snapshot, f: File, gen: Int) {
        if (gen != loadGenerationSnapshot()) return   // đã bị erase/reload: không ghi đè
        val tmp = File(f.parentFile, f.name + ".tmp")
        try {
            DataOutputStream(BufferedOutputStream(FileOutputStream(tmp), 32 * 1024)).use { d ->
                d.writeInt(MAGIC); d.writeInt(VERSION); d.writeLong(s.lastDecay)
                d.writeInt(s.uni.size)
                for ((k, v) in s.uni) { d.writeUTF(k); d.writeInt(v) }
                for (m in listOf(s.bi, s.tri)) {
                    d.writeInt(m.size)
                    for ((k, inner) in m) {
                        d.writeUTF(k); d.writeInt(inner.size)
                        for ((w, c) in inner) { d.writeUTF(w); d.writeInt(c) }
                    }
                }
            }
            if (!tmp.renameTo(f)) { f.delete(); tmp.renameTo(f) }
        } catch (_: Exception) { tmp.delete() }
    }

    @Volatile private var volatileGen = 0
    private fun loadGenerationSnapshot() = volatileGen

    /** Encode + ghi atomic trên io. */
    fun save() {
        saveWork?.cancel(); saveWork = null
        val f = file
        if (!isLoaded || f == null) return
        val snap = snapshot()
        val gen = volatileGen
        io.execute { write(snap, f, gen) }
    }

    /** Flush khi bàn phím ẩn: chỉ ghi nếu có thay đổi chờ; giữ FIFO với save(). */
    fun saveNow() {
        if (saveWork == null) return
        save()
    }

    private fun scheduleSave() {
        saveWork?.cancel()
        saveWork = main.postDelayed(TypingTimings.USERLM_SAVE_COALESCE_MS, Runnable { saveWork = null; save() })
    }

    /** Có thay đổi đang chờ ghi (test/IME). */
    val hasPendingSave: Boolean get() = saveWork != null

    fun eraseAll() {
        dropInMemory()
        isLoaded = true
        val f = file
        if (f != null) io.execute { f.delete() }
    }

    private fun dropInMemory() {
        loadGeneration++
        volatileGen++
        saveWork?.cancel(); saveWork = null
        uni = HashMap(); bi = HashMap(); tri = HashMap()
        biPairs = 0; triPairs = 0; uniTotal = 0
        pendingRecords.clear(); pendingSeed = null
        topCache = null
        knownCache.clear()
    }

    /**
     * App đã xoá userlm.bin ("Xóa từ đã học", pref userlmResetAt đổi): bỏ bảng trong RAM,
     * huỷ ghi chờ (không bao giờ ghi lại dữ liệu cũ), load lại file (vắng ⇒ seed lại).
     */
    fun reloadAfterExternalErase() {
        dropInMemory()
        val f = file
        if (f == null) {
            isLoaded = true
            seedSource?.let { applySeed(it()) }
            return
        }
        isLoaded = false
        pendingSeed = seedSource
        loadAsync(f)
    }

    // MARK: decay / prune

    /** Mỗi ≥7 ngày: count ×0.7^tuần (một timestamp toàn cục). */
    internal fun decayIfDue(now: Long = clock()) {
        val weeks = ((now - lastDecay) / WEEK_MS).toInt()
        if (weeks < 1) return
        val f = 0.7.pow(weeks)
        fun decayMap(m: Map<String, Int>): HashMap<String, Int> {
            val out = HashMap<String, Int>()
            for ((k, c) in m) { val v = (c * f).toInt(); if (v > 0) out[k] = v }
            return out
        }
        uni = decayMap(uni)
        bi = nestedMap(bi) { decayMap(it) }
        tri = nestedMap(tri) { decayMap(it) }
        recount()
        lastDecay = now
        topCache = null
        save()
    }

    /** Test: giả lập lần decay cuối. */
    internal fun setLastDecayForTest(t: Long) { lastDecay = t }

    private fun nestedMap(m: Map<String, HashMap<String, Int>>,
                          f: (Map<String, Int>) -> HashMap<String, Int>): HashMap<String, HashMap<String, Int>> {
        val out = HashMap<String, HashMap<String, Int>>()
        for ((k, v) in m) { val d = f(v); if (d.isNotEmpty()) out[k] = d }
        return out
    }

    private fun halve(m: Map<String, Int>): HashMap<String, Int> {
        val out = HashMap<String, Int>()
        for ((k, c) in m) if (c / 2 != 0) out[k] = c / 2
        return out
    }

    private fun pruneIfNeeded() {
        if (uni.size > UNI_CAP) { uni = halve(uni); uniTotal = uni.values.sum(); topCache = null }
        if (biPairs > BI_CAP) {
            bi = nestedMap(bi) { halve(it) }
            biPairs = bi.values.sumOf { it.size }
        }
        if (triPairs > TRI_CAP) {
            tri = nestedMap(tri) { halve(it) }
            triPairs = tri.values.sumOf { it.size }
        }
    }

    internal val uniSize: Int get() = uni.size

    // seed bigrams tĩnh
    val seedNext: Map<String, List<String>> get() = SEED_NEXT
}

private val SEED_NEXT: Map<String, List<String>> = hashMapOf(
    "anh" to listOf("ơi", "đang", "có", "yêu"),
    "em" to listOf("ơi", "yêu", "đang", "nhé"),
    "chị" to listOf("ơi", "đang", "có"),
    "mẹ" to listOf("ơi", "đang", "có"),
    "bạn" to listOf("ơi", "có", "đang"),
    "mình" to listOf("đang", "có", "sẽ", "nghĩ"),
    "tôi" to listOf("đang", "có", "sẽ", "nghĩ"),
    "cảm" to listOf("ơn"),
    "xin" to listOf("chào", "lỗi", "phép"),
    "chúc" to listOf("mừng", "ngủ", "sức"),
    "không" to listOf("có", "phải", "biết", "sao"),
    "rất" to listOf("vui", "đẹp", "ngon", "tốt"),
    "hôm" to listOf("nay", "qua"),
    "ngày" to listOf("mai", "mới", "nào"),
    "buổi" to listOf("sáng", "trưa", "chiều", "tối"),
    "đi" to listOf("làm", "học", "chơi", "ăn"),
    "ăn" to listOf("cơm", "sáng", "trưa", "tối"),
    "đang" to listOf("làm", "ăn", "đi", "ở"),
    "có" to listOf("khỏe", "thể", "gì", "ai"),
    "làm" to listOf("gì", "việc", "sao"),
    "yêu" to listOf("em", "anh", "quá"),
    "ngủ" to listOf("ngon", "sớm", "dậy"),
    "tạm" to listOf("biệt"),
    "hẹn" to listOf("gặp"),
    "gặp" to listOf("lại", "nhau"),
    "vui" to listOf("quá", "lắm", "vẻ"),
    "được" to listOf("không", "rồi", "chưa"),
    "nhớ" to listOf("em", "anh", "nhé"),
)
