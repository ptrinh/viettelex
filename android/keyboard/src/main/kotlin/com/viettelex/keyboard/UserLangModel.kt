package com.viettelex.keyboard

import java.io.ByteArrayInputStream
import java.io.DataInputStream
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import java.util.zip.CRC32
import kotlin.math.pow

/**
 * Datastore cá nhân hoá cho thanh gợi ý (port 1:1 iOS UserLangModel): uni / bi
 * (prev → next → count) / tri ("p2␁p1" → next → count), shrinkage, learning-vs-
 * suggesting (từ lạ cần count ≥3), decay ×0.7/tuần, cap halve-when-full.
 *
 * BẢNG GỌN (09/2026, android/docs/RAM-AUDIT.md — trước đây HashMap lồng, boxed, ~1 KB/mục): từ
 * intern thành id Int ([UserLMTables]), uni là IntArray theo id, bi là "prev id → LongArray sắp
 * (next id shl 32 | count)", tri là bảng băm mở (p2 shl 32 | p1) → slot → mảng như bi. Ngữ nghĩa
 * (cap, decay, prune, retract, thứ tự gợi ý) y hệt bản cũ (property test so với LegacyUserLangModel).
 *
 * THREADING: mọi đọc/ghi bảng trên MAIN thread (như iOS). Decode/encode/IO trên [io];
 * kết quả load trả về qua [main]. Persist `filesDir/userlm.bin` định dạng VTL2 (chung iOS —
 * [UserLMCodec]), ghi atomic (file tạm + rename), coalesce 5 s sau record cuối. File v1 cũ
 * (DataOutputStream "VTLM") được đọc và ghi lại thành VTL2 một lần (rename chỉ sau khi bản mới
 * ghi xong và đọc lại khớp — hỏng giữa chừng thì bản cũ còn nguyên).
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
    private val ioLazy = lazy {
        ioExecutor ?: Executors.newSingleThreadExecutor { r ->
            Thread(r, "vt-userlm-io").apply { isDaemon = true; priority = Thread.MIN_PRIORITY }
        }
    }
    private val io: Executor by ioLazy
    private val ownsIo = ioExecutor == null
    private var closed = false

    private var t = UserLMTables()
    /** Hoa/thường đã học ([CaseTable]): dạng người dùng nhất quán viết giữa câu. */
    private var cases = CaseTable()
    private var lastDecay = clock()
    /** Từ user tự thêm (màn Từ điển cá nhân): key lowercase → dạng hiển thị ("VietTelex"). */
    private var manual = LinkedHashMap<String, String>()

    /** Lexicon tĩnh (VNSuggest.contains). Mặc định false để test kiểm soát. */
    var isKnownWord: (String) -> Boolean = { false }
        set(v) { field = v; knownCache.clear(); topCache = null }

    /** Gọi trên main khi bảng trên đĩa swap-in xong (IME refresh bar). */
    var onReady: (() -> Unit)? = null

    private var saveWork: Cancellable? = null
    private var isLoaded = false
    private var loadGeneration = 0
    internal class PendingRecord(val word: String, val prev1: String?, val prev2: String?, val weight: Int,
                                 val caseEvidence: Boolean = false) {
        /** Biên nhận khi đã phát lại sau lúc nạp xong (để [retract] vẫn rút được). */
        var replayed: Learned? = null
    }

    /**
     * Biên nhận một lần [record]: đúng những gì đã cộng (uni / bi / tri) để [retract] trừ
     * lại chính xác — dùng khi ⌫ mở lại từ vừa chốt.
     */
    class Learned internal constructor(
        internal val word: String?, internal val prev1: String?, internal val triKey: String?,
        internal val weight: Int, internal val pending: PendingRecord?,
    )
    private val pendingRecords = ArrayList<PendingRecord>()
    private var pendingSeed: (() -> SeedData.Seed)? = null
    /** Nguồn seed gần nhất — để [reloadAfterExternalErase] seed lại. */
    private var seedSource: (() -> SeedData.Seed)? = null

    private val knownCache = HashMap<String, Boolean>()
    private var topCacheK = 0
    private var topCache: List<String>? = null
    /** Khoá (chữ thường) của [topCache], cùng thứ tự — để [bumpTop] cập nhật tăng dần. */
    private var topKeys: ArrayList<String>? = null

    companion object {
        const val UNI_CAP = 3000
        const val BI_CAP = 6000
        const val TRI_CAP = 3000
        const val UNKNOWN_SUGGEST_THRESHOLD = 3
        const val PENDING_RECORD_CAP = 128
        const val SEP = "\u0001"
        /** File v1 (trước 09/2026): DataOutputStream big-endian "VTLM". */
        private const val LEGACY_MAGIC = 0x56544C4D // "VTLM"
        private const val LEGACY_VERSION = 1
        private const val WEEK_MS = 7L * 86_400_000L
        /** Đuôi tuỳ chọn sau bảng tri của file v1: danh sách từ thêm tay. */
        private const val LEGACY_MANUAL_MAGIC = 0x4D414E55 // "MANU"
        /** Count khởi điểm của từ thêm tay: ≥ ngưỡng gợi ý, xếp trên từ học 1-2 lần. */
        const val MANUAL_COUNT = 5
        const val MANUAL_MAX_LEN = 24

        /**
         * Chuẩn hoá từ user gõ vào màn Từ điển cá nhân: bỏ khoảng trắng đầu/cuối, chỉ chữ
         * cái (tên riêng, thuật ngữ — một "từ" không dấu cách), 1..24 ký tự. null = không hợp lệ.
         */
        fun normalizeManual(raw: String): String? {
            val w = java.text.Normalizer.normalize(raw.trim(), java.text.Normalizer.Form.NFC)
            if (w.isEmpty()) return null
            var n = 0; var i = 0
            while (i < w.length) {
                val c = w.codePointAt(i)
                if (!Character.isLetter(c)) return null
                n++; i += Character.charCount(c)
            }
            return if (n <= MANUAL_MAX_LEN) w else null
        }

        /** Bỏ dấu + lowercase + đ→d — so tiền tố "kube"/"phuc" với từ thêm tay. */
        fun fold(s: String): String {
            val d = java.text.Normalizer.normalize(s.lowercase(), java.text.Normalizer.Form.NFD)
            val sb = StringBuilder(d.length)
            for (ch in d) {
                if (Character.getType(ch) == Character.NON_SPACING_MARK.toInt()) continue
                sb.append(if (ch == 'đ') 'd' else ch)
            }
            return sb.toString()
        }

        /** File v1 cũ → bảng dict; null nếu không phải v1 / hỏng. */
        internal fun readLegacyV1(bytes: ByteArray): Plain? = try {
            DataInputStream(ByteArrayInputStream(bytes)).use { d ->
                if (d.readInt() != LEGACY_MAGIC) return null
                if (d.readInt() != LEGACY_VERSION) return null
                val lastDecay = d.readLong()
                val nu = d.readInt()
                val uni = HashMap<String, Int>(nu * 2)
                repeat(nu) { uni[d.readUTF()] = d.readInt() }
                fun nested(): HashMap<String, Map<String, Int>> {
                    val n = d.readInt()
                    val m = HashMap<String, Map<String, Int>>(n * 2)
                    repeat(n) {
                        val k = d.readUTF(); val c = d.readInt()
                        val inner = HashMap<String, Int>(c * 2)
                        repeat(c) { inner[d.readUTF()] = d.readInt() }
                        m[k] = inner
                    }
                    return m
                }
                val bi = nested(); val tri = nested()
                // Đuôi tuỳ chọn: từ thêm tay (file cũ không có ⇒ EOF ⇒ rỗng).
                val manual = ArrayList<String>()
                try {
                    if (d.readInt() == LEGACY_MANUAL_MAGIC) repeat(d.readInt()) { manual.add(d.readUTF()) }
                } catch (_: java.io.EOFException) { }
                Plain(LearnedWords(uni, bi, tri, manual), lastDecay)
            }
        } catch (e: Exception) { null }

        /**
         * Đọc store: VTL2, hoặc v1 cũ (khi đó [migrate] = ghi lại thành VTL2 — file cũ chỉ bị thay
         * sau khi bản mới ghi xong và đọc lại khớp). null nếu vắng / hỏng.
         */
        private fun readTablesFile(f: File, migrate: Boolean): Loaded? {
            if (!f.exists()) return null
            val bytes = try { f.readBytes() } catch (_: Exception) { return null }
            UserLMCodec.decode(bytes)?.let { return it }
            val old = readLegacyV1(bytes) ?: return null
            val tables = UserLMTables.fromMaps(old.learned.uni, old.learned.bi, old.learned.tri)
            if (migrate) writeVerified(UserLMCodec.encode(tables, old.lastDecay, old.learned.manual), f)
            return Loaded(tables, old.lastDecay, old.learned.manual)
        }

        /** Ghi atomic: file tạm → (tuỳ chọn) đọc lại so từng byte → rename. false = file cũ nguyên vẹn. */
        private fun writeVerified(bytes: ByteArray, f: File, verify: Boolean = true): Boolean {
            val tmp = File(f.parentFile, f.name + ".tmp")
            return try {
                FileOutputStream(tmp).use { it.write(bytes); if (verify) it.fd.sync() }
                if (verify && !tmp.readBytes().contentEquals(bytes)) { tmp.delete(); return false }
                if (!tmp.renameTo(f)) { f.delete(); if (!tmp.renameTo(f)) { tmp.delete(); return false } }
                true
            } catch (_: Exception) { tmp.delete(); false }
        }

        /** Sao lưu: đọc userlm.bin thành [LearnedWords]; null nếu vắng/hỏng. Không ghi gì. */
        fun readLearned(f: File): LearnedWords? =
            readTablesFile(f, migrate = false)?.let { LearnedWords(it.t.uniMap(), it.t.biMap(), it.t.triMap(), it.manual) }

        /**
         * Nhập sao lưu: gộp [lw] vào file (count lớn hơn, giữ lastDecay). Gọi TRƯỚC khi
         * báo IME nạp lại ([reloadAfterExternalErase] qua pref userlmResetAt).
         */
        fun mergeLearnedIntoFile(lw: LearnedWords, f: File, now: Long = System.currentTimeMillis()) {
            val cur = readTablesFile(f, migrate = false)
            val merged = (cur?.let { LearnedWords(it.t.uniMap(), it.t.biMap(), it.t.triMap(), it.manual) }
                ?: LearnedWords()).merged(lw)
            // Từ thêm tay luôn có mặt trong uni (như keepManual của model).
            val uni = HashMap(merged.uni).apply { for (m in merged.manual) merge(m.lowercase(), 1) { a, _ -> a } }
            val tables = UserLMTables.fromMaps(uni, merged.bi, merged.tri)
            writeVerified(UserLMCodec.encode(tables, cur?.lastDecay ?: now, merged.manual), f)
        }

        /** Test/công cụ: ghi thẳng một store từ dict (VTL2). */
        internal fun writePlain(p: Plain, f: File): Boolean {
            val tables = UserLMTables.fromMaps(p.learned.uni, p.learned.bi, p.learned.tri)
            return writeVerified(UserLMCodec.encode(tables, p.lastDecay, p.learned.manual), f)
        }

        /** Test/công cụ: đọc store thành dict (không ghi gì). */
        internal fun readPlain(f: File): Plain? = readTablesFile(f, migrate = false)?.let {
            Plain(LearnedWords(it.t.uniMap(), it.t.biMap(), it.t.triMap(), it.manual), it.lastDecay)
        }

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

    /** Dạng dict của store (ranh giới sao lưu / test). */
    internal data class Plain(val learned: LearnedWords, val lastDecay: Long)

    internal class Loaded(val t: UserLMTables, val lastDecay: Long, val manual: List<String>,
                          val cases: CaseTable = CaseTable())

    init {
        if (file != null) loadAsync(file) else isLoaded = true
    }

    private fun loadAsync(f: File) {
        if (closed) return
        val gen = loadGeneration
        io.execute {
            val t = readTablesFile(f, migrate = true)
            main.post { if (loadGeneration == gen) finishLoad(t) }
        }
    }

    private fun finishLoad(l: Loaded?) {
        if (l != null) {
            t = l.t; lastDecay = l.lastDecay; cases = l.cases
            manual = LinkedHashMap<String, String>().apply { for (d in l.manual) this[d.lowercase()] = d }
            keepManual()
        }
        isLoaded = true
        topCache = null
        val seed = pendingSeed
        pendingSeed = null
        if (seed != null) seedIfEmpty(seed)
        val queued = pendingRecords.toList()
        pendingRecords.clear()
        for (r in queued) r.replayed = record(r.word, r.prev1, r.prev2, r.weight, r.caseEvidence)
        decayIfDue()
        onReady?.invoke()
    }

    // MARK: học

    /**
     * Một từ vừa chốt; weight 1 gõ thường, 2 khi bấm nhận gợi ý. [caseEvidence]: hoa/thường của
     * [word] (đúng như đã gõ) là bằng chứng GIỮA CÂU — caller tính bằng [DisplayCase.casingEvidence]
     * (+ ô không tự hoa mỗi từ). false ⇒ không đụng bảng hoa/thường. = iOS record(caseEvidence:).
     */
    fun record(word: String, after: String?, prev2: String? = null, weight: Int = 1,
               caseEvidence: Boolean = false): Learned? {
        if (!isLoaded) {
            if (pendingRecords.size >= PENDING_RECORD_CAP) return null
            val pr = PendingRecord(word, after, prev2, weight, caseEvidence)
            pendingRecords.add(pr)
            return Learned(null, null, null, weight, pr)
        }
        if (weight <= 0 || !learnable(word)) return null
        val w = word.lowercase()
        val wid = t.intern(w)
        if (caseEvidence) {
            cases.observe(java.text.Normalizer.normalize(word, java.text.Normalizer.Form.NFC), w, t.uni(wid))
        }
        t.setUni(wid, t.uni(wid) + weight)
        bumpTop(w)
        var biKey: String? = null
        var triKey: String? = null
        val p1 = after?.lowercase()
        if (p1 != null && learnable(p1)) {
            val pid = t.intern(p1)
            t.addBi(pid, wid, weight)
            biKey = p1
            val p2 = prev2?.lowercase()
            if (p2 != null && learnable(p2)) {
                val p2id = t.id(p2)
                if (p2id >= 0 && t.biCount(p2id, pid) >= 2) {
                    t.addTri(UserLMTables.ctx(p2id, pid), wid, weight)
                    triKey = p2 + SEP + p1
                }
            }
        }
        pruneIfNeeded()
        scheduleSave()
        return Learned(w, biKey, triKey, weight, null)
    }

    /** Rút lại một lần [record] (từ vừa chốt được mở lại để sửa). Không âm, bỏ mục về 0. */
    fun retract(l: Learned) {
        l.pending?.let { p ->
            if (!pendingRecords.remove(p)) p.replayed?.let { retract(it) }
            return
        }
        val w = l.word ?: return
        val wid = t.id(w)
        if (wid < 0) return
        val had = t.uni(wid)
        if (had <= 0) return
        t.setUni(wid, if (had <= l.weight) 0 else had - l.weight)
        topCache = null
        l.prev1?.let { k -> val pid = t.id(k); if (pid >= 0) t.decBi(pid, wid, l.weight) }
        l.triKey?.let { k ->
            val parts = k.split(SEP)
            if (parts.size == 2) {
                val a = t.id(parts[0]); val b = t.id(parts[1])
                if (a >= 0 && b >= 0) t.decTri(UserLMTables.ctx(a, b), wid, l.weight)
            }
        }
        scheduleSave()
    }

    /** Dạng hoa/thường người dùng hay viết ([key] chữ thường) — null nếu chưa đủ nhất quán. O(1). */
    fun learnedCase(key: String): String? = if (cases.isEmpty) null else cases.preferred(key)

    internal val caseCount: Int get() = cases.count
    internal fun caseStat(key: String): CaseStat? = cases.stats[key]

    private fun cachedKnown(w: String): Boolean {
        knownCache[w]?.let { return it }
        if (knownCache.size > 4096) knownCache.clear()
        val v = isKnownWord(w)
        knownCache[w] = v
        return v
    }

    private fun suggestable(w: String) =
        cachedKnown(w) || w in manual || t.uni(w) >= UNKNOWN_SUGGEST_THRESHOLD

    // MARK: từ điển cá nhân (màn quản lý trong app)

    /** Một dòng của màn Từ điển cá nhân. */
    data class Entry(val word: String, val count: Int, val manual: Boolean)

    /**
     * Mọi từ đã học + từ thêm tay, tần suất giảm dần (hoà: theo chữ cái). [query] ≠ rỗng:
     * chỉ từ CHỨA chuỗi tìm (bỏ dấu, không phân biệt hoa/thường — "viet" khớp "việt").
     */
    fun entries(query: String = ""): List<Entry> {
        val q = fold(query.trim())
        val out = ArrayList<Entry>()
        for (i in 0 until t.nWords) {
            val c = t.uniC[i]
            if (c <= 0) continue
            val k = t.word(i)
            if (q.isNotEmpty() && !fold(k).contains(q)) continue
            out.add(Entry(manual[k] ?: cases.preferred(k) ?: k, c, k in manual))
        }
        return out.sortedWith(compareByDescending<Entry> { it.count }.thenBy { it.word.lowercase() })
    }

    val isManualEmpty: Boolean get() = manual.isEmpty()

    /**
     * Xoá hẳn một từ: unigram, mọi bigram/trigram có từ đó (ở vị trí trước hay sau), và
     * dấu "thêm tay". true nếu có gì bị xoá.
     */
    fun removeWord(word: String): Boolean {
        val w = word.lowercase()
        var changed = manual.remove(w) != null
        if (cases.stats.containsKey(w)) { cases.remove(w); changed = true }
        val id = t.id(w)
        if (id >= 0 && t.removeWord(id)) changed = true
        if (!changed) return false
        t.compact()
        topCache = null
        knownCache.remove(w)
        scheduleSave()
        return true
    }

    /**
     * Thêm tay một từ (tên riêng, thuật ngữ) — được gợi ý ngay (không cần đạt ngưỡng
     * từ lạ), hiện ở hoàn thiện từ khi gõ tiền tố, không bị decay/prune xoá. false nếu
     * không hợp lệ ([normalizeManual]).
     */
    fun addWord(raw: String): Boolean {
        val display = normalizeManual(raw) ?: return false
        val w = display.lowercase()
        manual[w] = display
        val id = t.intern(w)
        if (t.uni(id) < MANUAL_COUNT) t.setUni(id, MANUAL_COUNT)
        topCache = null
        scheduleSave()
        return true
    }

    /**
     * Từ thêm tay khớp tiền tố đang gõ (bỏ dấu, không phân biệt hoa/thường), dạng hiển
     * thị. Bỏ từ trùng hệt chuỗi đang gõ.
     */
    fun manualCompletions(prefix: String, limit: Int = 2): List<String> {
        if (manual.isEmpty() || prefix.isEmpty()) return emptyList()
        val f = fold(prefix)
        return manual.entries.asSequence()
            .filter { (k, d) -> d != prefix && fold(k).startsWith(f) }
            .sortedByDescending { t.uni(it.key) }
            .map { it.value }.take(limit).toList()
    }

    /** Từ thêm tay luôn còn trong uni (decay/prune không được xoá). */
    private fun keepManual() {
        for (k in manual.keys) if (t.uni(k) < 1) t.setUni(t.intern(k), 1)
    }

    // MARK: gợi ý

    /** Top từ hay dùng (ô trống). Cache tới khi uni đổi. */
    fun topWords(limit: Int): List<String> {
        topCache?.let { if (topCacheK >= limit) return it.take(limit) }
        // (count << 32 | id) — sắp giảm theo count, hoà theo khoá tăng dần
        val ids = ArrayList<Int>(t.uniN)
        for (i in 0 until t.nWords) if (t.uniC[i] > 0) ids.add(i)
        val sorted = ids.sortedWith { a, b ->
            val ca = t.uniC[a]; val cb = t.uniC[b]
            if (ca != cb) cb.compareTo(ca) else t.word(a).compareTo(t.word(b))
        }
        val out = ArrayList<String>(limit)
        val keys = ArrayList<String>(limit + 1)
        for (i in sorted) {
            val w = t.word(i)
            if (!suggestable(w)) continue
            out.add(manual[w] ?: w); keys.add(w)
            if (out.size >= limit) break
        }
        topCache = out; topCacheK = limit; topKeys = keys
        return out
    }

    /**
     * [record] vừa TĂNG uni[w]: cập nhật top-K tại chỗ thay vì bỏ cache (trước đây mỗi dấu cách
     * sắp xếp lại cả ≤3000 mục trên main thread ở lượt gợi ý kế). Đếm chỉ tăng ⇒ tập top-K chỉ
     * có thể thêm đúng [w]; thứ tự như [topWords] (đếm giảm dần, rồi khoá tăng dần).
     */
    private fun bumpTop(w: String) {
        val keys = topKeys ?: run { topCache = null; return }
        if (topCache == null) return
        val had = keys.remove(w)
        if (!suggestable(w)) { if (had) topCache = null; return }
        val c = t.uni(w)
        var i = 0
        while (i < keys.size) {
            val o = keys[i]; val oc = t.uni(o)
            if (oc < c || (oc == c && o > w)) break
            i++
        }
        if (i >= topCacheK) { if (had) topCache = null; return }   // (không xảy ra khi đếm chỉ tăng)
        keys.add(i, w)
        while (keys.size > topCacheK) keys.removeAt(keys.size - 1)
        topCache = keys.map { manual[it] ?: it }
    }

    /** Từ kế tiếp sau (prev2, prev1): tri ⊕ bi ⊕ uni ⊕ seed với shrinkage. */
    fun nextWords(after: String, prev2: String? = null, limit: Int): List<String> {
        val p1 = after.lowercase()
        val pid = t.id(p1)
        var biB: LongArray? = null; var biN = 0
        if (pid >= 0) { biB = t.biB[pid]; biN = t.biL[pid] }
        var triB: LongArray? = null; var triN = 0
        if (pid >= 0 && prev2 != null) {
            val p2id = t.id(prev2.lowercase())
            if (p2id >= 0) {
                val s = t.triSlotOf(UserLMTables.ctx(p2id, pid))
                if (s >= 0) { triB = t.triB[s]; triN = t.triL[s] }
            }
        }
        val seeds = seedNext[p1] ?: emptyList()
        var biTotal = 0; var triTotal = 0
        for (i in 0 until biN) biTotal += UserLMTables.cnt(biB!![i])
        for (i in 0 until triN) triTotal += UserLMTables.cnt(triB!![i])
        val uniT = maxOf(t.uniTotal, 1)
        val lamTri = triTotal.toDouble() / (triTotal + 2.0)
        val lamBi = biTotal.toDouble() / (biTotal + 4.0)
        // Ứng viên = bi ∪ tri (trộn hai mảng sắp theo id) ∪ seed; count lấy luôn khi trộn.
        val cw = ArrayList<String>(biN + triN + seeds.size)
        val cb = IntArray(biN + triN + seeds.size); val ct = IntArray(biN + triN + seeds.size)
        var i = 0; var j = 0
        while (i < biN || j < triN) {
            val bn = if (i < biN) UserLMTables.nid(biB!![i]) else Int.MAX_VALUE
            val tn = if (j < triN) UserLMTables.nid(triB!![j]) else Int.MAX_VALUE
            val id = minOf(bn, tn)
            val k = cw.size
            if (bn == id) { cb[k] = UserLMTables.cnt(biB!![i]); i++ }
            if (tn == id) { ct[k] = UserLMTables.cnt(triB!![j]); j++ }
            cw.add(t.word(id))
        }
        for (s in seeds) if (s !in cw) cw.add(s)
        fun score(k: Int): Double {
            val w = cw[k]
            val pTri = if (triTotal > 0) ct[k].toDouble() / triTotal else 0.0
            val pBi = if (biTotal > 0) cb[k].toDouble() / biTotal else 0.0
            val pUni = t.uni(w).toDouble() / uniT
            val si = seeds.indexOf(w)
            val pSeed = if (si >= 0) 0.5.pow(si) else 0.0
            return lamTri * pTri + lamBi * pBi + 0.1 * pUni + (1 - lamBi) * 0.9 * pSeed
        }
        return cw.indices.filter { suggestable(cw[it]) || cw[it] in seeds }
            .map { cw[it] to score(it) }
            .sortedWith(compareByDescending<Pair<String, Double>> { it.second }.thenBy { it.first })
            .take(limit).map { manual[it.first] ?: it.first }
    }

    /** Điểm cá nhân của một từ. */
    fun count(of: String): Int {
        val c = t.uni(of)
        return if (c > 0) c else t.uni(of.lowercase())
    }

    /** Từ của người dùng: thêm tay, hoặc đã gõ đủ nhiều để được gợi ý — tự sửa không đụng. */
    fun isUserWord(w: String): Boolean {
        val k = w.lowercase()
        return k in manual || t.uni(k) >= UNKNOWN_SUGGEST_THRESHOLD
    }

    /** Số lần cặp (prev → word) đã gặp (bigram cá nhân + seed) — AddTones chấm lưới âm tiết. */
    fun bigramCount(prev: String, word: String): Int {
        val p = t.id(prev.lowercase()); if (p < 0) return 0
        val w = t.id(word); if (w < 0) return 0
        return t.biCount(p, w)
    }

    /** Số lần bộ ba (prev2, prev → word) người dùng đã gõ (không có seed) — thanh gợi ý ưu tiên. */
    fun trigramCount(prev2: String, prev: String, word: String): Int {
        val a = t.id(prev2.lowercase()); if (a < 0) return 0
        val b = t.id(prev.lowercase()); if (b < 0) return 0
        val s = t.triSlotOf(UserLMTables.ctx(a, b)); if (s < 0 || t.triL[s] == 0) return 0
        val raw = t.id(word)
        if (raw >= 0) { val c = t.triCount(s, raw); if (c > 0) return c }
        val low = t.id(word.lowercase())
        return if (low >= 0) t.triCount(s, low) else 0
    }

    /**
     * Seed khi store trống. [seed] chỉ được gọi khi thật sự seed; đang chờ load thì
     * giữ lại quyết sau swap-in.
     */
    fun seedIfEmpty(seed: () -> SeedData.Seed = SeedData::load) {
        seedSource = seed
        if (!isLoaded) { pendingSeed = seed; return }
        if (t.uniN != 0 || seeding) return
        if (file == null) { applySeed(seed()); return }   // in-memory (test): đồng bộ như cũ
        // Có file (IME thật, người dùng mới / vừa xoá dữ liệu học): parse seed.tsv (~vài nghìn dòng) trên
        // io, áp trên main SAU — không chặn onStartInputView / khung đầu. Từ gõ chen giữa giữ nguyên.
        seeding = true
        val gen = loadGeneration
        io.execute {
            val s = try { seed() } catch (_: Exception) { null }
            main.post {
                if (loadGeneration != gen) return@post   // đã xoá / nạp lại: lượt mới tự seed
                seeding = false
                if (s != null && !closed) applySeed(s)
            }
        }
    }
    /** Đang parse seed trên io (áp lên main khi xong). */
    private var seeding = false

    /** Tiện cho test: seed từ map/list trực tiếp. */
    fun seedIfEmpty(unigrams: Map<String, Int>, bigrams: List<Triple<String, String, Int>>) =
        seedIfEmpty { SeedData.Seed(unigrams, bigrams) }

    private fun applySeed(s: SeedData.Seed) {
        // uni rỗng ⇒ như `uni = HashMap(s.unigrams)` bản cũ (đè). Seed nền áp muộn mà người dùng đã gõ
        // vài từ trong lúc chờ ⇒ gộp: giữ số lớn hơn (không hạ đếm từ vừa gõ).
        val merge = t.uniN != 0
        for ((w, c) in s.unigrams) if (c > 0) {
            val id = t.intern(w)
            if (!merge || t.uni(id) < c) t.setUni(id, c)
        }
        for ((a, b, c) in s.bigrams) if (c > 0) {
            val ia = t.intern(a); val ib = t.intern(b)
            if (!merge || t.biCount(ia, ib) < c) t.setBi(ia, ib, c)
        }
        topCache = null
        save()
    }

    // MARK: persistence

    private class Snapshot(val t: UserLMTables, val lastDecay: Long, val manual: List<String>, val cases: CaseTable)

    /** Bản sao sâu trên main (vài chục µs — chỉ copy mảng nguyên thuỷ), nền encode bản sao. */
    private fun snapshot() = Snapshot(t.copy(), lastDecay, manual.values.toList(), cases.copy())

    private fun write(s: Snapshot, f: File, gen: Int) {
        if (gen != loadGenerationSnapshot()) return   // đã bị erase/reload: không ghi đè
        writeVerified(UserLMCodec.encode(s.t, s.lastDecay, s.manual, s.cases), f, verify = false)
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

    /**
     * Service IME bị huỷ (đổi bàn phím): ghi thay đổi đang chờ, bỏ bảng trong RAM (vỏ service
     * cũ có thể bị framework giữ lâu — đừng kéo theo bảng), dừng luồng IO sau khi
     * ghi xong. Sau đó model không ghi/nạp nữa (không bao giờ ghi bảng rỗng đè file).
     */
    fun close() {
        if (closed) return
        saveNow()
        closed = true
        isLoaded = false
        loadGeneration++
        saveWork?.cancel(); saveWork = null
        t = UserLMTables(); manual = LinkedHashMap(); cases = CaseTable()
        pendingRecords.clear(); pendingSeed = null; seedSource = null
        topCache = null; topKeys = null
        knownCache.clear()
        onReady = null
        if (ownsIo && ioLazy.isInitialized()) (ioLazy.value as? java.util.concurrent.ExecutorService)?.shutdown()
    }

    fun eraseAll() {
        dropInMemory()
        isLoaded = true
        val f = file
        if (f != null) { if (closed) f.delete() else io.execute { f.delete() } }
    }

    private fun dropInMemory() {
        loadGeneration++
        volatileGen++
        saveWork?.cancel(); saveWork = null
        t = UserLMTables(); manual = LinkedHashMap(); cases = CaseTable()
        pendingRecords.clear(); pendingSeed = null; seeding = false
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
        t.mapCounts(uni = true, bi = true, tri = true) { (it * f).toInt() }
        keepManual()
        t.compact()
        dropOrphanCases()
        lastDecay = now
        topCache = null
        save()
    }

    /** Test: giả lập lần decay cuối. */
    internal fun setLastDecayForTest(t: Long) { lastDecay = t }

    private fun pruneIfNeeded() {
        val u = t.uniN > UNI_CAP; val b = t.biN > BI_CAP; val r = t.triN > TRI_CAP
        if (!u && !b && !r) return
        t.mapCounts(uni = u, bi = b, tri = r) { it / 2 }
        if (u) { keepManual(); topCache = null }
        t.compact()
        if (u) dropOrphanCases()
    }

    /** Từ rơi khỏi unigram (decay/prune) ⇒ bỏ luôn hoa/thường của nó. */
    private fun dropOrphanCases() {
        val tt = t
        cases.retain { tt.uni(it) > 0 }
    }

    internal val uniSize: Int get() = t.uniN
    internal val biPairCount: Int get() = t.biN
    internal val triPairCount: Int get() = t.triN
    internal val vocabSize: Int get() = t.nWords
    /** Test/công cụ: bảng dạng dict (dựng lại mỗi lần gọi — không dùng trên đường gõ). */
    internal fun uniMap(): Map<String, Int> = t.uniMap()
    internal fun biMap(): Map<String, Map<String, Int>> = t.biMap()
    internal fun triMap(): Map<String, Map<String, Int>> = t.triMap()
    internal fun manualMap(): Map<String, String> = manual

    // seed bigrams tĩnh
    val seedNext: Map<String, List<String>> get() = SEED_NEXT
}

/**
 * Bảng n-gram gọn: từ intern thành id Int (bảng băm mở [slots] → id + 1), count Int ≥ 1.
 * - uni: [uniC][id] (0 = không có mục).
 * - bi: [biB][prev id] = LongArray (next id shl 32 | count) sắp tăng theo next id, dài [biL].
 * - tri: băm mở (p2 shl 32 | p1) → slot; [triB]/[triL] như bi. Slot rỗng giữ tới lần compact.
 * Chỉ nguyên thuỷ — không boxing, không Node HashMap mỗi mục.
 */
internal class UserLMTables {
    var words: Array<String?> = arrayOfNulls(16); private set
    var nWords = 0; private set
    private var slots = IntArray(32)
    var uniC = IntArray(16); private set
    var biB: Array<LongArray?> = arrayOfNulls(16); private set
    var biL = IntArray(16); private set
    private var tKeys = LongArray(16)
    private var tVals = IntArray(16)          // slot + 1; 0 = trống
    var triCtx = LongArray(8); private set
    var triB: Array<LongArray?> = arrayOfNulls(8); private set
    var triL = IntArray(8); private set
    var nTri = 0; private set
    var uniN = 0; private set
    var biN = 0; private set
    var triN = 0; private set
    /** Σ uni — incremental. */
    var uniTotal = 0; private set

    companion object {
        fun pack(id: Int, c: Int): Long = (id.toLong() shl 32) or (c.toLong() and 0xFFFFFFFFL)
        fun nid(e: Long): Int = (e ushr 32).toInt()
        fun cnt(e: Long): Int = e.toInt()
        fun ctx(p2: Int, p1: Int): Long = pack(p2, p1)
        private fun mix(h: Int): Int { val x = h * -0x61c88647; return x xor (x ushr 16) }
        private fun mixL(k: Long): Int { val x = k * -0x61c8864680b583ebL; return (x xor (x ushr 29)).toInt() }
        private fun clampAdd(a: Int, b: Int): Int = (a.toLong() + b).coerceIn(0, Int.MAX_VALUE.toLong()).toInt()

        /** Vị trí của [id] trong bucket (≥0) hoặc -(chỗ chèn)-1. */
        fun search(b: LongArray?, len: Int, id: Int): Int {
            if (b == null) return -1
            var lo = 0; var hi = len
            while (lo < hi) {
                val m = (lo + hi) ushr 1
                if (nid(b[m]) < id) lo = m + 1 else hi = m
            }
            return if (lo < len && nid(b[lo]) == id) lo else -lo - 1
        }

        /** Dựng từ dict kiểu cũ. Count ≤ 0 bị bỏ; khoá tri phải đúng dạng "p2␁p1". */
        fun fromMaps(uni: Map<String, Int>, bi: Map<String, Map<String, Int>>,
                     tri: Map<String, Map<String, Int>>): UserLMTables {
            val t = UserLMTables()
            for ((w, c) in uni) if (c > 0) t.setUni(t.intern(w), c)
            for ((p, inner) in bi) for ((n, c) in inner) if (c > 0) t.setBi(t.intern(p), t.intern(n), c)
            for ((k, inner) in tri) {
                val parts = k.split(UserLangModel.SEP)
                if (parts.size != 2) continue
                for ((n, c) in inner) if (c > 0) {
                    val a = t.intern(parts[0]); val b = t.intern(parts[1])
                    t.setTri(ctx(a, b), t.intern(n), c)
                }
            }
            return t
        }
    }

    fun word(id: Int): String = words[id]!!

    fun id(w: String): Int {
        val mask = slots.size - 1
        var i = mix(w.hashCode()) and mask
        while (true) {
            val s = slots[i]
            if (s == 0) return -1
            if (words[s - 1] == w) return s - 1
            i = (i + 1) and mask
        }
    }

    fun intern(w: String): Int {
        val have = id(w)
        if (have >= 0) return have
        val id = nWords
        if (id == words.size) {
            val n = maxOf(16, id + (id shr 1))
            words = words.copyOf(n); uniC = uniC.copyOf(n); biB = biB.copyOf(n); biL = biL.copyOf(n)
        }
        words[id] = w; nWords++
        if (nWords * 2 > slots.size) rehashWords(slots.size * 2) else placeWord(id)
        return id
    }

    private fun placeWord(id: Int) {
        val mask = slots.size - 1
        var i = mix(words[id]!!.hashCode()) and mask
        while (slots[i] != 0) i = (i + 1) and mask
        slots[i] = id + 1
    }

    private fun rehashWords(cap: Int) {
        slots = IntArray(cap)
        for (id in 0 until nWords) placeWord(id)
    }

    fun uni(id: Int): Int = uniC[id]
    fun uni(w: String): Int { val i = id(w); return if (i < 0) 0 else uniC[i] }

    fun setUni(id: Int, c: Int) {
        val old = uniC[id]; val v = maxOf(c, 0)
        if (old == 0 && v > 0) uniN++ else if (old > 0 && v == 0) uniN--
        uniTotal += v - old
        uniC[id] = v
    }

    fun biCount(p: Int, n: Int): Int {
        val at = search(biB[p], biL[p], n)
        return if (at >= 0) cnt(biB[p]!![at]) else 0
    }

    /** Cộng/gán vào bucket; trả về mảng (có thể đã nới) và báo mục mới qua [isNew]. */
    private var isNew = false
    private fun add(b0: LongArray?, len: Int, n: Int, by: Int, set: Boolean): LongArray {
        val at = search(b0, len, n)
        if (at >= 0) {
            val b = b0!!
            b[at] = pack(n, if (set) by else clampAdd(cnt(b[at]), by))
            isNew = false
            return b
        }
        val ins = -at - 1
        var b = b0 ?: LongArray(2)
        if (len == b.size) b = b.copyOf(maxOf(2, len + (len shr 1) + 1))
        System.arraycopy(b, ins, b, ins + 1, len - ins)
        b[ins] = pack(n, by)
        isNew = true
        return b
    }

    /** Trừ; trả về true nếu mục bị bỏ hẳn (bucket [b] dài [len]). */
    private fun dec(b: LongArray?, len: Int, n: Int, by: Int): Boolean {
        val at = search(b, len, n)
        if (at < 0) return false
        val c = cnt(b!![at])
        if (c > by) { b[at] = pack(n, c - by); return false }
        System.arraycopy(b, at + 1, b, at, len - at - 1)
        return true
    }

    fun addBi(p: Int, n: Int, by: Int) {
        biB[p] = add(biB[p], biL[p], n, by, set = false)
        if (isNew) { biL[p]++; biN++ }
    }
    fun setBi(p: Int, n: Int, c: Int) {
        biB[p] = add(biB[p], biL[p], n, c, set = true)
        if (isNew) { biL[p]++; biN++ }
    }
    fun decBi(p: Int, n: Int, by: Int) {
        if (dec(biB[p], biL[p], n, by)) { biL[p]--; biN-- }
    }

    /** Slot của ngữ cảnh tri, -1 nếu chưa có. */
    fun triSlotOf(c: Long): Int {
        val mask = tKeys.size - 1
        var i = mixL(c) and mask
        while (true) {
            val v = tVals[i]
            if (v == 0) return -1
            if (tKeys[i] == c) return v - 1
            i = (i + 1) and mask
        }
    }

    private fun placeCtx(c: Long, slot: Int) {
        val mask = tKeys.size - 1
        var i = mixL(c) and mask
        while (tVals[i] != 0) i = (i + 1) and mask
        tKeys[i] = c; tVals[i] = slot + 1
    }

    private fun triSlot(c: Long): Int {
        val s = triSlotOf(c)
        if (s >= 0) return s
        val slot = nTri
        if (slot == triCtx.size) {
            val n = maxOf(8, slot + (slot shr 1))
            triCtx = triCtx.copyOf(n); triB = triB.copyOf(n); triL = triL.copyOf(n)
        }
        triCtx[slot] = c; nTri++
        if (nTri * 2 > tKeys.size) {
            tKeys = LongArray(tKeys.size * 2); tVals = IntArray(tVals.size * 2)
            for (k in 0 until nTri) placeCtx(triCtx[k], k)
        } else placeCtx(c, slot)
        return slot
    }

    fun triCount(slot: Int, n: Int): Int {
        val at = search(triB[slot], triL[slot], n)
        return if (at >= 0) cnt(triB[slot]!![at]) else 0
    }
    fun addTri(c: Long, n: Int, by: Int) {
        val s = triSlot(c)
        triB[s] = add(triB[s], triL[s], n, by, set = false)
        if (isNew) { triL[s]++; triN++ }
    }
    fun setTri(c: Long, n: Int, v: Int) {
        val s = triSlot(c)
        triB[s] = add(triB[s], triL[s], n, v, set = true)
        if (isNew) { triL[s]++; triN++ }
    }
    fun decTri(c: Long, n: Int, by: Int) {
        val s = triSlotOf(c)
        if (s < 0) return
        if (dec(triB[s], triL[s], n, by)) { triL[s]--; triN-- }
    }

    /** Bỏ [id] khỏi uni + mọi bi/tri có nó (trước hay sau). true nếu có gì bị xoá. */
    fun removeWord(id: Int): Boolean {
        var changed = false
        if (uniC[id] > 0) { setUni(id, 0); changed = true }
        if (biL[id] > 0) { biN -= biL[id]; biL[id] = 0; changed = true }
        for (p in 0 until nWords) if (biL[p] > 0 && dec(biB[p], biL[p], id, Int.MAX_VALUE)) {
            biL[p]--; biN--; changed = true
        }
        for (s in 0 until nTri) {
            if (triL[s] == 0) continue
            val c = triCtx[s]
            if (nid(c) == id || cnt(c) == id) { triN -= triL[s]; triL[s] = 0; changed = true }
            else if (dec(triB[s], triL[s], id, Int.MAX_VALUE)) { triL[s]--; triN--; changed = true }
        }
        return changed
    }

    /** Áp [f] lên mọi count của các bảng được chọn; count ≤ 0 bị bỏ. */
    fun mapCounts(uni: Boolean, bi: Boolean, tri: Boolean, f: (Int) -> Int) {
        if (uni) {
            uniN = 0; uniTotal = 0
            for (i in 0 until nWords) {
                val c = uniC[i]; if (c <= 0) continue
                val v = maxOf(f(c), 0)
                uniC[i] = v
                if (v > 0) { uniN++; uniTotal += v }
            }
        }
        fun mapB(bs: Array<LongArray?>, ls: IntArray, n: Int): Int {
            var total = 0
            for (i in 0 until n) {
                val b = bs[i] ?: continue
                var k = 0
                for (j in 0 until ls[i]) {
                    val v = f(cnt(b[j]))
                    if (v > 0) b[k++] = pack(nid(b[j]), v)
                }
                ls[i] = k; total += k
            }
            return total
        }
        if (bi) biN = mapB(biB, biL, nWords)
        if (tri) triN = mapB(triB, triL, nTri)
    }

    /**
     * Bỏ từ mồ côi (không còn ở uni/bi/tri) + slot tri rỗng, cấp lại id liền nhau (giữ thứ tự ⇒
     * bucket vẫn sắp), thu gọn mảng về đúng cỡ. Chỉ chạy lúc prune/decay/xoá từ (hiếm).
     */
    fun compact() {
        val live = BooleanArray(nWords)
        for (i in 0 until nWords) if (uniC[i] > 0) live[i] = true
        for (p in 0 until nWords) if (biL[p] > 0) {
            live[p] = true
            val b = biB[p]!!
            for (j in 0 until biL[p]) live[nid(b[j])] = true
        }
        var liveTri = 0
        for (s in 0 until nTri) if (triL[s] > 0) {
            liveTri++
            live[nid(triCtx[s])] = true; live[cnt(triCtx[s])] = true
            val b = triB[s]!!
            for (j in 0 until triL[s]) live[nid(b[j])] = true
        }
        val remap = IntArray(nWords) { -1 }
        var nLive = 0
        for (i in 0 until nWords) if (live[i]) remap[i] = nLive++
        val n = maxOf(nLive, 1)
        val nw = arrayOfNulls<String>(n); val nu = IntArray(n)
        val nb = arrayOfNulls<LongArray>(n); val nl = IntArray(n)
        fun re(b: LongArray, len: Int): LongArray = LongArray(len) { pack(remap[nid(b[it])], cnt(b[it])) }
        for (i in 0 until nWords) {
            val k = remap[i]; if (k < 0) continue
            nw[k] = words[i]; nu[k] = uniC[i]
            if (biL[i] > 0) { nb[k] = re(biB[i]!!, biL[i]); nl[k] = biL[i] }
        }
        val tn = maxOf(liveTri, 1)
        val tc = LongArray(tn); val tb = arrayOfNulls<LongArray>(tn); val tl = IntArray(tn)
        var ns = 0
        for (s in 0 until nTri) if (triL[s] > 0) {
            tc[ns] = pack(remap[nid(triCtx[s])], remap[cnt(triCtx[s])])
            tb[ns] = re(triB[s]!!, triL[s]); tl[ns] = triL[s]; ns++
        }
        words = nw; uniC = nu; biB = nb; biL = nl; nWords = nLive
        var cap = 32; while (cap < nLive * 2) cap = cap shl 1
        rehashWords(cap)
        triCtx = tc; triB = tb; triL = tl; nTri = ns
        var tcap = 16; while (tcap < ns * 2) tcap = tcap shl 1
        tKeys = LongArray(tcap); tVals = IntArray(tcap)
        for (k in 0 until ns) placeCtx(tc[k], k)
    }

    /** Bản sao sâu (snapshot để lưu nền). */
    fun copy(): UserLMTables {
        val o = UserLMTables()
        o.words = words.copyOf(nWords.coerceAtLeast(1)); o.nWords = nWords
        o.slots = slots.copyOf()
        o.uniC = uniC.copyOf(nWords.coerceAtLeast(1))
        o.biB = Array(nWords.coerceAtLeast(1)) { if (it < nWords && biL[it] > 0) biB[it]!!.copyOf(biL[it]) else null }
        o.biL = biL.copyOf(nWords.coerceAtLeast(1))
        o.tKeys = tKeys.copyOf(); o.tVals = tVals.copyOf()
        o.triCtx = triCtx.copyOf(nTri.coerceAtLeast(1)); o.nTri = nTri
        o.triB = Array(nTri.coerceAtLeast(1)) { if (it < nTri && triL[it] > 0) triB[it]!!.copyOf(triL[it]) else null }
        o.triL = triL.copyOf(nTri.coerceAtLeast(1))
        o.uniN = uniN; o.biN = biN; o.triN = triN; o.uniTotal = uniTotal
        return o
    }

    /** Dựng thẳng từ file đã kiểm ([UserLMCodec]) — bucket đã sắp, không trùng. */
    internal fun loadRaw(ws: Array<String?>, n: Int, u: IntArray, bb: Array<LongArray?>, bl: IntArray,
                         tc: LongArray, tb: Array<LongArray?>, tl: IntArray, nt: Int) {
        words = ws; nWords = n; uniC = u; biB = bb; biL = bl
        var cap = 32; while (cap < n * 2) cap = cap shl 1
        rehashWords(cap)
        triCtx = tc; triB = tb; triL = tl; nTri = nt
        var tcap = 16; while (tcap < nt * 2) tcap = tcap shl 1
        tKeys = LongArray(tcap); tVals = IntArray(tcap)
        for (k in 0 until nt) placeCtx(tc[k], k)
        uniN = 0; uniTotal = 0; biN = 0; triN = 0
        for (i in 0 until n) if (u[i] > 0) { uniN++; uniTotal += u[i] }
        for (i in 0 until n) biN += bl[i]
        for (i in 0 until nt) triN += tl[i]
    }

    /** Có mục trùng khoá (từ) không — file hỏng. */
    internal fun hasDuplicateWords(): Boolean {
        val seen = HashSet<String>(nWords * 2)
        for (i in 0 until nWords) if (!seen.add(words[i]!!)) return true
        return false
    }

    fun uniMap(): Map<String, Int> {
        val m = HashMap<String, Int>(uniN * 2)
        for (i in 0 until nWords) if (uniC[i] > 0) m[words[i]!!] = uniC[i]
        return m
    }

    private fun nested(b: LongArray, len: Int): Map<String, Int> {
        val m = HashMap<String, Int>(len * 2)
        for (j in 0 until len) m[words[nid(b[j])]!!] = cnt(b[j])
        return m
    }

    fun biMap(): Map<String, Map<String, Int>> {
        val m = HashMap<String, Map<String, Int>>()
        for (p in 0 until nWords) if (biL[p] > 0) m[words[p]!!] = nested(biB[p]!!, biL[p])
        return m
    }

    fun triMap(): Map<String, Map<String, Int>> {
        val m = HashMap<String, Map<String, Int>>()
        for (s in 0 until nTri) if (triL[s] > 0) {
            val c = triCtx[s]
            m[words[nid(c)]!! + UserLangModel.SEP + words[cnt(c)]!!] = nested(triB[s]!!, triL[s])
        }
        return m
    }
}

/**
 * Định dạng file VTL2 — CHUNG với iOS (iOS/Keyboard/UserLangModel.swift `UserLMCodec`), little-endian:
 * ```
 * "VTL2" | u16 version=1 | u16 flags=0 | i64 lastDecay (ms từ 1970)
 * u32 nWords | nWords × (u16 len, UTF-8)          — id = thứ tự
 * nWords × u32 uniCount                            — 0 = không có unigram
 * u32 nBi  | nBi  × (u32 prev, u32 n, n × (u32 next, u32 count))
 * u32 nTri | nTri × (u32 p2, u32 p1, u32 n, n × (u32 next, u32 count))
 * u32 nManual | nManual × (u16 len, UTF-8)        — dạng hiển thị
 * [flags & 1] u32 nCase | nCase × (u32 word id, u16 len, UTF-8 form, u16 hits, u16 total)
 *                                                  — hoa/thường đã học ([CaseTable]), id tăng dần
 * u32 CRC32 (IEEE, java.util.zip.CRC32) của mọi byte phía trước
 * ```
 * Đọc: sai magic/version/CRC, id ngoài tầm, count 0, bucket không tăng dần, từ/ngữ cảnh trùng ⇒ null.
 */
internal object UserLMCodec {
    private val MAGIC = byteArrayOf('V'.code.toByte(), 'T'.code.toByte(), 'L'.code.toByte(), '2'.code.toByte())
    private const val VERSION = 1

    const val FLAG_CASE = 1

    /**
     * flags bit 0 (10/2026) = có phần hoa/thường; CHỈ ghi khi bảng có mục ⇒ file không có dữ liệu
     * hoa/thường giữ y từng byte như trước (bản cũ vẫn đọc được). Byte trùng iOS UserLMCodec.
     */
    fun encode(t: UserLMTables, lastDecay: Long, manual: List<String>, cases: CaseTable = CaseTable()): ByteArray {
        val wb = Array(t.nWords) { t.word(it).toByteArray(Charsets.UTF_8) }
        val mb = manual.map { it.toByteArray(Charsets.UTF_8) }
        var size = 16 + 4 + 4 * t.nWords + 4 + 4 + 4 + 4
        for (b in wb) size += 2 + minOf(b.size, 0xFFFF)
        var nb = 0; var nt = 0
        for (p in 0 until t.nWords) if (t.biL[p] > 0) { nb++; size += 8 + 8 * t.biL[p] }
        for (s in 0 until t.nTri) if (t.triL[s] > 0) { nt++; size += 12 + 8 * t.triL[s] }
        for (b in mb) size += 2 + minOf(b.size, 0xFFFF)
        // hoa/thường: chỉ mục có từ trong bảng, theo id tăng dần
        val caseRows = ArrayList<Triple<Int, ByteArray, CaseStat>>()
        for ((k, st) in cases.stats) {
            val id = t.id(k)
            if (id >= 0 && st.total > 0) caseRows.add(Triple(id, st.form.toByteArray(Charsets.UTF_8), st))
        }
        caseRows.sortBy { it.first }
        if (caseRows.isNotEmpty()) {
            size += 4
            for (r in caseRows) size += 4 + 2 + minOf(r.second.size, 0xFFFF) + 4
        }
        val o = ByteBuffer.allocate(size).order(ByteOrder.LITTLE_ENDIAN)
        fun str(b: ByteArray) { val n = minOf(b.size, 0xFFFF); o.putShort(n.toShort()); o.put(b, 0, n) }
        o.put(MAGIC); o.putShort(VERSION.toShort()); o.putShort(if (caseRows.isEmpty()) 0 else FLAG_CASE.toShort())
        o.putLong(lastDecay)
        o.putInt(t.nWords)
        for (b in wb) str(b)
        for (i in 0 until t.nWords) o.putInt(t.uniC[i])
        o.putInt(nb)
        for (p in 0 until t.nWords) if (t.biL[p] > 0) {
            o.putInt(p); o.putInt(t.biL[p])
            val b = t.biB[p]!!
            for (j in 0 until t.biL[p]) { o.putInt(UserLMTables.nid(b[j])); o.putInt(UserLMTables.cnt(b[j])) }
        }
        o.putInt(nt)
        for (s in 0 until t.nTri) if (t.triL[s] > 0) {
            val c = t.triCtx[s]
            o.putInt(UserLMTables.nid(c)); o.putInt(UserLMTables.cnt(c)); o.putInt(t.triL[s])
            val b = t.triB[s]!!
            for (j in 0 until t.triL[s]) { o.putInt(UserLMTables.nid(b[j])); o.putInt(UserLMTables.cnt(b[j])) }
        }
        o.putInt(mb.size)
        for (b in mb) str(b)
        if (caseRows.isNotEmpty()) {
            o.putInt(caseRows.size)
            for ((id, fb, st) in caseRows) {
                o.putInt(id); str(fb)
                o.putShort(st.hits.coerceIn(0, 0xFFFF).toShort()); o.putShort(st.total.coerceIn(0, 0xFFFF).toShort())
            }
        }
        val crc = CRC32().apply { update(o.array(), 0, o.position()) }.value
        o.putInt(crc.toInt())
        return o.array()
    }

    fun decode(bytes: ByteArray): UserLangModel.Loaded? {
        if (bytes.size < 36) return null
        for (i in 0 until 4) if (bytes[i] != MAGIC[i]) return null
        val body = bytes.size - 4
        val crc = CRC32().apply { update(bytes, 0, body) }.value.toInt()
        val bb = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        if (bb.getInt(body) != crc) return null
        bb.limit(body); bb.position(4)
        return try {
            if (bb.short.toInt() and 0xFFFF != VERSION) return null
            val flags = bb.short.toInt() and 0xFFFF
            val lastDecay = bb.long
            fun u32(): Int { val v = bb.int; if (v < 0) throw IllegalStateException(); return v }
            fun str(): String {
                val n = bb.short.toInt() and 0xFFFF
                val s = String(bytes, bb.position(), n, Charsets.UTF_8)
                bb.position(bb.position() + n)
                return s
            }
            val nw = u32()
            if (nw > body / 2) return null
            val words = arrayOfNulls<String>(maxOf(nw, 1))
            for (i in 0 until nw) words[i] = str()
            val uni = IntArray(maxOf(nw, 1))
            for (i in 0 until nw) uni[i] = u32()
            fun bucket(): LongArray? {
                val n = u32()
                if (n == 0 || n > bb.remaining() / 8) return null
                val b = LongArray(n)
                var last = -1
                for (j in 0 until n) {
                    val id = u32(); val c = u32()
                    if (id >= nw || c == 0 || id <= last) return null
                    last = id
                    b[j] = UserLMTables.pack(id, c)
                }
                return b
            }
            val biB = arrayOfNulls<LongArray>(maxOf(nw, 1)); val biL = IntArray(maxOf(nw, 1))
            repeat(u32()) {
                val p = u32()
                if (p >= nw || biB[p] != null) return null
                val b = bucket() ?: return null
                biB[p] = b; biL[p] = b.size
            }
            val nt = u32()
            if (nt > body / 12) return null
            val tc = LongArray(maxOf(nt, 1)); val tb = arrayOfNulls<LongArray>(maxOf(nt, 1)); val tl = IntArray(maxOf(nt, 1))
            val seen = HashSet<Long>(nt * 2)
            for (s in 0 until nt) {
                val a = u32(); val b = u32()
                if (a >= nw || b >= nw) return null
                val c = UserLMTables.pack(a, b)
                if (!seen.add(c)) return null
                val bk = bucket() ?: return null
                tc[s] = c; tb[s] = bk; tl[s] = bk.size
            }
            val nm = u32()
            if (nm > body / 2) return null
            val manual = ArrayList<String>(nm)
            repeat(nm) { manual.add(str()) }
            val cases = HashMap<String, CaseStat>()
            if (flags and FLAG_CASE != 0) {
                val nc = u32()
                if (nc > body / 10) return null
                var last = -1
                repeat(nc) {
                    val id = u32()
                    if (id >= nw || id <= last) return null
                    last = id
                    val f = str()
                    val h = bb.short.toInt() and 0xFFFF
                    val tt = bb.short.toInt() and 0xFFFF
                    if (f.isEmpty() || tt == 0 || h > tt) return null
                    cases[words[id]!!] = CaseStat(f, h, tt)
                }
            }
            if (bb.position() != body) return null
            val t = UserLMTables()
            t.loadRaw(words, nw, uni, biB, biL, tc, tb, tl, nt)
            if (t.hasDuplicateWords()) return null
            UserLangModel.Loaded(t, lastDecay, manual, CaseTable(cases))
        } catch (_: Exception) { null }
    }
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

/**
 * Hoa/thường đã học (port iOS CaseTable — UserLMTables.swift, cùng số): dạng viết hoa người dùng
 * NHẤT QUÁN dùng giữa câu cho một từ ("SenPrints", tên người "Văn"). Chỉ từ ĐÃ TỪNG viết hoa giữa
 * câu mới có mục. Caller lọc đầu câu / chuỗi tên riêng ([DisplayCase.casingEvidence]); ở đây lọc
 * thêm Caps Lock / cả từ hoa và từ một chữ cái. Mỗi mục: [CaseStat.form] (dạng không-thường chiếm
 * ưu thế, đếm phiếu Boyer–Moore), hits (phiếu ròng), total (mọi lần quan sát giữa câu kể cả viết
 * thường; mục mới khởi điểm = count unigram trước đó — bảo thủ). Ưu tiên khi hits ≥ 3 và ≥ 80%
 * total. Bão hoà 255 (chia đôi làm tròn lên). Trần 512 mục.
 */
data class CaseStat(val form: String, val hits: Int, val total: Int)

class CaseTable(initial: Map<String, CaseStat> = emptyMap()) {
    enum class Kind { LOWER, MIXED, IGNORED }

    companion object {
        const val CAP = 512
        const val MAX_COUNT = 255
        const val MIN_HITS = 3

        /** "Hoa" = chữ mà lowercase khác chính nó (cùng định nghĩa Swift/C++). */
        fun kind(form: String): Kind {
            var letters = 0; var upper = 0
            var i = 0
            while (i < form.length) {
                val cp = form.codePointAt(i)
                val s = String(Character.toChars(cp))
                letters++
                if (s.lowercase() != s) upper++
                i += Character.charCount(cp)
            }
            if (upper == 0) return Kind.LOWER
            if (letters < 2 || upper == letters) return Kind.IGNORED
            return Kind.MIXED
        }

        private fun saturate(s: CaseStat): CaseStat =
            if (s.total <= MAX_COUNT) s else CaseStat(s.form, (s.hits + 1) / 2, (s.total + 1) / 2)
    }

    private val map = HashMap<String, CaseStat>(initial)
    val stats: Map<String, CaseStat> get() = map
    val isEmpty: Boolean get() = map.isEmpty()
    val count: Int get() = map.size

    fun copy(): CaseTable = CaseTable(map)

    /** Một lần quan sát GIỮA CÂU của [form] (NFC); [key] chữ thường; [priorCount] = count unigram trước. */
    fun observe(form: String, key: String, priorCount: Int): Boolean {
        when (kind(form)) {
            Kind.IGNORED -> return false
            Kind.LOWER -> {
                val s = map[key] ?: return false
                map[key] = saturate(CaseStat(s.form, s.hits, s.total + 1))
                return true
            }
            Kind.MIXED -> {
                val e = map[key]
                if (e == null && map.size >= CAP) return false
                var f = e?.form ?: form
                var h = e?.hits ?: 0
                val tt = (e?.total ?: priorCount.coerceIn(0, MAX_COUNT)) + 1
                if (f == form) h++ else if (h > 0) h-- else { f = form; h = 1 }
                map[key] = saturate(CaseStat(f, h, tt))
                return true
            }
        }
    }

    /** Dạng ưu tiên của [key], null = chưa đủ nhất quán. */
    fun preferred(key: String): String? {
        val s = map[key] ?: return null
        return if (s.hits >= MIN_HITS && s.hits * 5 >= s.total * 4) s.form else null
    }

    fun remove(key: String) { map.remove(key) }
    fun retain(keep: (String) -> Boolean) { if (map.isNotEmpty()) map.keys.retainAll(keep) }
}
