package com.viettelex.keyboard

import java.io.File
import java.nio.file.Files
import java.util.concurrent.Executor
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Bảng gọn của UserLangModel (intern id + file VTL2) — android/docs/RAM-AUDIT.md.
 * - Property test: chuỗi thao tác ngẫu nhiên áp lên LegacyUserLangModel (bản cũ nguyên vẹn) và
 *   UserLangModel, so MỌI đầu ra sau từng bước — gồm chạm trần (prune), decay, retract, thêm/xoá tay.
 * - Chuyển file v1 → VTL2 (fixture), fixture VTL2 dựng bằng Python (iOS đọc cùng file), file hỏng,
 *   sao lưu JSON không đổi.
 * - Đo trước/sau (heap, nạp/lưu, độ trễ tra) — dòng "USERLM …".
 */
class UserLMCompactTests {
    private val direct = Executor { it.run() }

    private class RNG(var s: Long) {
        fun next(): Long {
            s += -0x61c8864680b583ebL
            var z = s
            z = (z xor (z ushr 30)) * -0x40a7b892e31b1a47L
            z = (z xor (z ushr 27)) * -0x6b2fb644ecceee15L
            return z xor (z ushr 31)
        }
        fun int(n: Int): Int = ((next() ushr 1) % n).toInt()
        fun chance(p: Double): Boolean = ((next() ushr 1) % 1_000_000) / 1_000_000.0 < p
    }

    companion object {
        val onsets = listOf("b", "c", "ch", "d", "đ", "g", "gh", "h", "k", "kh", "l", "m", "n", "ng",
            "nh", "ph", "qu", "r", "s", "t", "th", "tr", "v", "x", "")
        val rimes = listOf("a", "á", "à", "ả", "ã", "ạ", "ăn", "ắt", "ân", "ấy", "anh", "ành", "ong", "óng",
            "ương", "ường", "iêu", "iếu", "ưa", "ứa", "ơi", "ời", "uôi", "uối", "em", "ém",
            "ên", "ết", "inh", "ình", "oa", "oá", "oan", "oàn", "ui", "úi", "ưng", "ừng",
            "ai", "ái", "ao", "áo", "êu", "ều", "ia", "ìa", "ôm", "ốm", "ơn", "ớn", "uyên",
            "uyền", "yêu", "ỷ", "ốc", "ọc", "ắc", "ặc", "iệt", "ược", "ưởng", "uống")
        /** Âm tiết giả tiếng Việt (có dấu) — cùng bộ sinh với iOS UserLMCompactTests. */
        fun syllables(n: Int): List<String> {
            val out = ArrayList<String>()
            for (x in listOf("", "x", "y", "z")) for (r in rimes) for (o in onsets) {
                out.add(o + r + x)
                if (out.size >= n) return out
            }
            return out
        }

        fun fixtureFile(name: String): File =
            listOf("../../iOS", "../iOS", "iOS").map { File(it, "KeyboardTests/Fixtures/$name") }
                .firstOrNull { it.exists() } ?: error("không thấy iOS/KeyboardTests/Fixtures/$name")

        val FIX_UNI = mapOf("cảm" to 7, "ơn" to 6, "nhiều" to 4, "viettelex" to 5, "sếp" to 3)
        val FIX_BI = mapOf("cảm" to mapOf("ơn" to 5), "ơn" to mapOf("nhiều" to 3, "sếp" to 1))
        val FIX_TRI = mapOf("cảm\u0001ơn" to mapOf("nhiều" to 3))
        const val FIX_DECAY = 1_788_220_800_000L
    }

    private fun tmpDir(tag: String): File = Files.createTempDirectory("ulm-$tag").toFile().apply { deleteOnExit() }

    private fun assertSame(a: LegacyUserLangModel, b: UserLangModel, words: List<String>, rng: RNG, full: Boolean, ctx: String) {
        repeat(6) {
            val w = words[rng.int(words.size)]
            val p2 = if (rng.chance(0.5)) words[rng.int(words.size)] else null
            val lim = 1 + rng.int(6)
            assertEquals(a.nextWords(w, p2, lim), b.nextWords(w, p2, lim), "nextWords($w,$p2) $ctx")
            assertEquals(a.count(w), b.count(w), "count $w $ctx")
            assertEquals(a.isUserWord(w), b.isUserWord(w), "isUserWord $w $ctx")
            val n = words[rng.int(words.size)]
            assertEquals(a.bigramCount(w, n), b.bigramCount(w, n), "bigram $w→$n $ctx")
            val q = words[rng.int(words.size)]
            assertEquals(a.trigramCount(q, w, n), b.trigramCount(q, w, n), "trigram $q,$w→$n $ctx")
        }
        val k = 1 + rng.int(20)
        assertEquals(a.topWords(k), b.topWords(k), "topWords($k) $ctx")
        val pre = words[rng.int(words.size)].take(1 + rng.int(2))
        assertEquals(a.manualCompletions(pre), b.manualCompletions(pre), "manual($pre) $ctx")
        assertEquals(a.isManualEmpty, b.isManualEmpty)
        if (full) {
            val (u, bi, tri) = legacyTables(a)
            assertEquals(u, b.uniMap(), "uni $ctx")
            assertEquals(bi, b.biMap(), "bi $ctx")
            assertEquals(tri, b.triMap(), "tri $ctx")
            assertEquals(a.entries().map { Triple(it.word, it.count, it.manual) }, b.entries().map { Triple(it.word, it.count, it.manual) }, "entries $ctx")
            assertEquals(u.size, b.uniSize)
            assertEquals(bi.values.sumOf { it.size }, b.biPairCount)
            assertEquals(tri.values.sumOf { it.size }, b.triPairCount)
        }
    }

    /** Bảng của model cũ (private) — đọc qua reflection, chỉ trong test. */
    @Suppress("UNCHECKED_CAST")
    private fun legacyTables(a: LegacyUserLangModel): Triple<Map<String, Int>, Map<String, Map<String, Int>>, Map<String, Map<String, Int>>> {
        fun f(n: String) = LegacyUserLangModel::class.java.getDeclaredField(n).apply { isAccessible = true }.get(a)
        return Triple(f("uni") as Map<String, Int>, f("bi") as Map<String, Map<String, Int>>, f("tri") as Map<String, Map<String, Int>>)
    }

    private fun runRandom(seed: Long, vocab: Int, steps: Int, fullEvery: Int) {
        val rng = RNG(seed)
        val words = syllables(vocab) + listOf("abc1", "heeeyyy", "", "Anh", "EM", "a b", "quáaaa", "VietTelex", "Kubernetes")
        val base = 1_790_000_000_000L
        val a = LegacyUserLangModel(clock = { base }); val b = UserLangModel(clock = { base })
        val known: (String) -> Boolean = { w -> w.codePoints().sum() % 3 != 0 }
        a.isKnownWord = known; b.isKnownWord = known
        if (seed % 2 == 0L) {
            val su = LinkedHashMap<String, Int>(); words.take(40).forEachIndexed { i, w -> su[w] = 5 + i % 40 }
            val sb = (0 until 60).map { Triple(words[it % 40], words[(it * 7) % 40], 1 + it % 9) }
            a.seedIfEmpty(su, sb); b.seedIfEmpty(su, sb)
        }
        val receipts = ArrayList<Pair<LegacyUserLangModel.Learned?, UserLangModel.Learned?>>()
        var p1: String? = null; var p2: String? = null
        var week = 0
        for (step in 0 until steps) {
            when (rng.int(1000)) {
                in 0 until 900 -> {
                    val w = if (rng.chance(0.5)) words[rng.int(maxOf(1, words.size / 8))] else words[rng.int(words.size)]
                    val wt = if (rng.chance(0.1)) 2 else 1
                    val ra = a.record(w, p1, p2, wt); val rb = b.record(w, p1, p2, wt)
                    assertEquals(ra == null, rb == null)
                    receipts.add(ra to rb)
                    if (receipts.size > 50) receipts.removeAt(0)
                    if (rng.chance(0.15)) { p1 = null; p2 = null } else { p2 = p1; p1 = w }
                }
                in 900 until 940 -> if (receipts.isNotEmpty()) {
                    val (ra, rb) = receipts.removeAt(rng.int(receipts.size))
                    ra?.let { a.retract(it) }; rb?.let { b.retract(it) }
                }
                in 940 until 955 -> { val w = words[rng.int(words.size)]; assertEquals(a.addWord(w), b.addWord(w)) }
                in 955 until 970 -> { val w = words[rng.int(words.size)]; assertEquals(a.removeWord(w), b.removeWord(w), "removeWord $w") }
                in 970 until 975 -> {
                    week += 1 + rng.int(3)
                    val now = base + week * 7L * 86_400_000L + 3_600_000L
                    a.decayIfDue(now); b.decayIfDue(now)
                }
                else -> {}
            }
            assertSame(a, b, words, rng, step % fullEvery == 0, "seed=$seed step=$step")
        }
        assertSame(a, b, words, rng, true, "seed=$seed end")
    }

    // MARK: property test cũ ≡ mới

    @Test fun randomOpsMatchLegacy() {
        for (seed in 1L..6L) runRandom(seed, 120, 1500, 25)
    }

    /** Vượt trần uni 3000 / bi 6000 / tri 3000 nhiều lần (prune halve + compact id). */
    @Test fun capsAndPruneMatchLegacy() {
        runRandom(42, 3600, 40_000, 2000)
        runRandom(43, 3600, 40_000, 2000)
    }

    @Test fun retractRestoresTables() {
        val m = UserLangModel().apply { isKnownWord = { true } }
        repeat(3) { m.record("cảm", null); m.record("ơn", "cảm") }
        val before = Triple(m.uniMap(), m.biMap(), m.triMap())
        val l1 = m.record("nhiều", "ơn", "cảm")!!
        val l2 = m.record("ơn", "cảm", weight = 2)!!
        assertEquals(1, m.trigramCount("cảm", "ơn", "nhiều"))
        m.retract(l2); m.retract(l1)
        assertEquals(before, Triple(m.uniMap(), m.biMap(), m.triMap()))
        m.retract(l1)
        assertEquals(before.first, m.uniMap())
    }

    @Test fun compactDropsOrphanWords() {
        val m = UserLangModel()
        m.record("một", null); m.record("hai", "một")
        assertEquals(2, m.vocabSize)
        assertTrue(m.removeWord("hai"))
        assertEquals(1, m.vocabSize)
        assertEquals(1, m.count("một"))
        assertEquals(0, m.bigramCount("một", "hai"))
    }

    // MARK: file

    @Test fun saveReloadRoundTrip() {
        val f = File(tmpDir("rt"), "userlm.bin")
        val a = UserLangModel(f, ImmediateMainThread(), direct).apply { isKnownWord = { true } }
        val rng = RNG(7); val words = syllables(300)
        var p1: String? = null; var p2: String? = null
        repeat(5000) {
            val w = words[rng.int(if (rng.chance(0.5)) 30 else words.size)]
            a.record(w, p1, p2); p2 = p1; p1 = w
        }
        a.addWord("VietTelex"); a.save()
        val b = UserLangModel(f, ImmediateMainThread(), direct).apply { isKnownWord = { true } }
        assertEquals(a.uniMap(), b.uniMap()); assertEquals(a.biMap(), b.biMap()); assertEquals(a.triMap(), b.triMap())
        assertEquals(a.manualMap(), b.manualMap())
        for (w in words.take(50)) assertEquals(a.nextWords(w, limit = 5), b.nextWords(w, limit = 5))
        assertContentEquals("VTL2".toByteArray(), f.readBytes().copyOf(4))
    }

    /** File v1 (DataOutputStream "VTLM", fixture Python) → đọc đúng, ghi lại VTL2 tại chỗ. */
    @Test fun migratesLegacyV1Fixture() {
        val f = File(tmpDir("mig"), "userlm.bin")
        fixtureFile("userlm-legacy-android-v1.bin").copyTo(f)
        val p = UserLangModel.readPlain(f)!!                     // đường sao lưu: không ghi
        assertEquals(LearnedWords(FIX_UNI, FIX_BI, FIX_TRI, listOf("VietTelex")), p.learned)
        assertEquals(FIX_DECAY, p.lastDecay)
        assertContentEquals("VTLM".toByteArray(), f.readBytes().copyOf(4))
        // cũ và mới cùng nạp (cùng decay) ⇒ bảng giống hệt; file thành VTL2
        val legacyCopy = File(f.parentFile, "legacy.bin"); fixtureFile("userlm-legacy-android-v1.bin").copyTo(legacyCopy)
        val old = LegacyUserLangModel(legacyCopy, ImmediateMainThread(), direct)
        val m = UserLangModel(f, ImmediateMainThread(), direct)
        val (u, bi, tri) = legacyTables(old)
        assertEquals(u, m.uniMap()); assertEquals(bi, m.biMap()); assertEquals(tri, m.triMap())
        assertEquals(old.entries().map { Triple(it.word, it.count, it.manual) }, m.entries().map { Triple(it.word, it.count, it.manual) })
        assertContentEquals("VTL2".toByteArray(), f.readBytes().copyOf(4))
        assertFalse(File(f.parentFile, "userlm.bin.tmp").exists())
        assertEquals(listOf("VietTelex"), UserLangModel(f, ImmediateMainThread(), direct).manualCompletions("viet"))
    }

    @Test fun migratesFileWrittenByLegacyModel() {
        val f = File(tmpDir("mig2"), "userlm.bin")
        val old = LegacyUserLangModel(f, ImmediateMainThread(), direct).apply { isKnownWord = { true } }
        val rng = RNG(99); val words = syllables(400)
        var p1: String? = null; var p2: String? = null
        repeat(8000) {
            val w = words[rng.int(if (rng.chance(0.6)) 40 else words.size)]
            old.record(w, p1, p2); p2 = p1; p1 = w
        }
        old.addWord("Kubernetes"); old.save()
        val m = UserLangModel(f, ImmediateMainThread(), direct)
        val (u, bi, tri) = legacyTables(old)
        assertEquals(u, m.uniMap()); assertEquals(bi, m.biMap()); assertEquals(tri, m.triMap())
        assertEquals(old.entries().map { Triple(it.word, it.count, it.manual) }, m.entries().map { Triple(it.word, it.count, it.manual) })
    }

    /** Ghi bản mới thất bại (chỗ file tạm bị chiếm) ⇒ file v1 KHÔNG bị thay, dữ liệu vẫn nạp. */
    @Test fun migrationWriteFailureKeepsLegacy() {
        val dir = tmpDir("migfail")
        val f = File(dir, "userlm.bin")
        fixtureFile("userlm-legacy-android-v1.bin").copyTo(f)
        val original = f.readBytes()
        val blocker = File(dir, "userlm.bin.tmp").apply { mkdirs(); File(this, "chặn").writeText("x") }
        // Đồng hồ cố định = lastDecay của fixture: không decay lúc nạp. Trước đây test dùng giờ
        // thật ⇒ từ 01/09/2026 trở đi decay 0.7^tuần làm count fixture rơi về 0 (test hỏng theo lịch).
        val m = UserLangModel(f, ImmediateMainThread(), direct, clock = { FIX_DECAY })
        // Ghi bản mới thất bại ⇒ file cũ (v1 "VTLM") còn nguyên từng byte, dữ liệu vẫn dùng được.
        assertContentEquals(original, f.readBytes())
        assertEquals(7, m.count("cảm"))
        assertEquals(6, m.count("ơn"))
        assertEquals(listOf("VietTelex"), m.manualCompletions("viet"))
        m.close()

        // Gỡ vật cản ⇒ lần nạp sau chuyển thành VTL2.
        blocker.deleteRecursively()
        val again = UserLangModel(f, ImmediateMainThread(), direct, clock = { FIX_DECAY })
        assertEquals(7, again.count("cảm"))
        assertNotNull(UserLMCodec.decode(f.readBytes()))
    }

    /** Fixture VTL2 do bộ mã hoá Python độc lập dựng — iOS đọc cùng file (layout chung). */
    @Test fun decodesCrossPlatformFixture() {
        val bytes = fixtureFile("userlm-vtl2.bin").readBytes()
        val d = assertNotNull(UserLMCodec.decode(bytes))
        assertEquals(FIX_UNI, d.t.uniMap()); assertEquals(FIX_BI, d.t.biMap()); assertEquals(FIX_TRI, d.t.triMap())
        assertEquals(listOf("VietTelex"), d.manual)
        assertEquals(FIX_DECAY, d.lastDecay)
        assertContentEquals(bytes, UserLMCodec.encode(d.t, d.lastDecay, d.manual))   // trùng từng byte với Python
    }

    @Test fun corruptFilesAreRejected() {
        val good = fixtureFile("userlm-vtl2.bin").readBytes()
        for (i in good.indices step 3) {
            val bad = good.copyOf(); bad[i] = (bad[i].toInt() xor 0x5A).toByte()
            assertNull(UserLMCodec.decode(bad), "byte $i")
        }
        for (n in listOf(0, 3, 20, good.size - 1)) assertNull(UserLMCodec.decode(good.copyOf(n)))
        assertNull(UserLMCodec.decode(ByteArray(500) { it.toByte() }))
        assertNull(UserLMCodec.decode(good + byteArrayOf(0)))
        // file hỏng ⇒ rỗng, không crash, vẫn học
        val f = File(tmpDir("corrupt"), "userlm.bin")
        f.writeBytes(good.copyOf().also { it[40] = (it[40].toInt() xor 1).toByte() })
        val m = UserLangModel(f, ImmediateMainThread(), direct)
        assertEquals(0, m.uniSize)
        m.record("chào", null)
        assertEquals(1, m.count("chào"))
        assertNull(UserLangModel.readLearned(f))
    }

    // MARK: sao lưu — JSON không đổi

    @Test fun backupJsonUnchanged() {
        val fixture = fixtureFile("backup-ios-v1.json").readText()
        val lw = BackupCodec.decode(fixture).learnedWords!!
        val f = File(tmpDir("bk"), "userlm.bin")
        UserLangModel.mergeLearnedIntoFile(lw, f)
        val expectUni = HashMap(lw.uni).apply { for (m in lw.manual) putIfAbsent(m.lowercase(), 1) }
        val back = UserLangModel.readLearned(f)!!
        assertEquals(lw.copy(uni = expectUni), back)
        val m = UserLangModel(f, ImmediateMainThread(), direct)
        assertEquals(expectUni, m.uniMap())
    }

    // MARK: đo trước/sau

    private fun usedHeap(): Long {
        val r = Runtime.getRuntime()
        repeat(4) { System.gc(); Thread.sleep(40) }
        return r.totalMemory() - r.freeMemory()
    }

    /** Người dùng nặng tại trần: 2.990 uni / 5.990 bi / 2.990 tri. In "USERLM …". */
    @Test fun measureHeavyUser() {
        val words = syllables(2990)
        val uni = HashMap<String, Int>(); val bi = HashMap<String, HashMap<String, Int>>(); val tri = HashMap<String, HashMap<String, Int>>()
        words.forEachIndexed { i, w -> uni[w] = 1 + (2990 - i) / 30 }
        var n = 0; var i = 0
        while (n < 5990) {
            val p = words[(i * 13) % 600]; val x = words[(i * 7919) % words.size]
            if (bi[p]?.get(x) == null) { bi.getOrPut(p) { HashMap() }[x] = 1 + i % 7; n++ }
            i++
        }
        n = 0; i = 0
        while (n < 2990) {
            val k = words[(i * 17) % 200] + UserLangModel.SEP + words[(i * 31) % 300]; val x = words[(i * 104_729) % words.size]
            if (tri[k]?.get(x) == null) { tri.getOrPut(k) { HashMap() }[x] = 1 + i % 5; n++ }
            i++
        }
        val now = System.currentTimeMillis()
        val dir = tmpDir("bench")
        val oldF = File(dir, "old.bin"); val newF = File(dir, "new.bin")
        // file v1 bằng chính model cũ
        LegacyUserLangModel.mergeLearnedIntoFile(LearnedWords(uni, bi, tri), oldF, now)
        assertTrue(UserLangModel.writePlain(UserLangModel.Plain(LearnedWords(uni, bi, tri), now), newF))
        fun ms(f: () -> Unit): Double { val t = System.nanoTime(); f(); return (System.nanoTime() - t) / 1e6 }
        // làm ấm JIT
        repeat(5) { LegacyUserLangModel(oldF, ImmediateMainThread(), direct, { now }); UserLangModel(newF, ImmediateMainThread(), direct, { now }) }
        var oldLoad = Double.MAX_VALUE; var newLoad = Double.MAX_VALUE
        repeat(5) {
            oldLoad = minOf(oldLoad, ms { LegacyUserLangModel(oldF, ImmediateMainThread(), direct, { now }) })
            newLoad = minOf(newLoad, ms { UserLangModel(newF, ImmediateMainThread(), direct, { now }) })
        }
        var h0 = usedHeap()
        val old = LegacyUserLangModel(oldF, ImmediateMainThread(), direct, { now })
        val oldHeap = usedHeap() - h0
        h0 = usedHeap()
        val new = UserLangModel(newF, ImmediateMainThread(), direct, { now })
        val newHeap = usedHeap() - h0
        val (u, b, t) = legacyTables(old)
        assertEquals(u, new.uniMap()); assertEquals(b, new.biMap()); assertEquals(t, new.triMap())

        var oldSave = Double.MAX_VALUE; var newSave = Double.MAX_VALUE
        repeat(8) { k ->
            old.record(words[k], words[k + 1]); new.record(words[k], words[k + 1])
            oldSave = minOf(oldSave, ms { old.save() })
            newSave = minOf(newSave, ms { new.save() })
        }
        old.isKnownWord = { true }; new.isKnownWord = { true }
        val prevs = List(2000) { words[(it * 13) % 600] }; val p2s = List(2000) { words[(it * 17) % 200] }
        fun bench(f: (Int) -> Unit): Double {
            repeat(20_000) { f(it) }                                  // làm ấm JIT + knownCache
            var best = Double.MAX_VALUE
            repeat(3) { best = minOf(best, ms { for (j in 0 until 20_000) f(j) }) }
            return best * 1e6 / 20_000
        }
        val oldNext = bench { j -> old.nextWords(prevs[j % 2000], p2s[j % 2000], 3) }
        val newNext = bench { j -> new.nextWords(prevs[j % 2000], p2s[j % 2000], 3) }
        val oldCount = bench { j -> old.count(words[j % 2990]) }
        val newCount = bench { j -> new.count(words[j % 2990]) }
        val oldBig = bench { j -> old.bigramCount(prevs[j % 2000], words[(j * 7919) % 2990]) }
        val newBig = bench { j -> new.bigramCount(prevs[j % 2000], words[(j * 7919) % 2990]) }
        val oldTri = bench { j -> old.trigramCount(p2s[j % 2000], prevs[j % 2000], words[(j * 7919) % 2990]) }
        val newTri = bench { j -> new.trigramCount(p2s[j % 2000], prevs[j % 2000], words[(j * 7919) % 2990]) }
        println(String.format("USERLM heap old=%.2fMB new=%.2fMB (%.0f%%)", oldHeap / 1048576.0, newHeap / 1048576.0, 100.0 * newHeap / maxOf(oldHeap, 1)))
        println("USERLM file old=${oldF.length() / 1024}KB new=${newF.length() / 1024}KB")
        println(String.format("USERLM load old=%.1fms new=%.1fms  save old=%.1fms new=%.1fms", oldLoad, newLoad, oldSave, newSave))
        println(String.format("USERLM nextWords old=%.0fns new=%.0fns  count old=%.0fns new=%.0fns  bigram old=%.0fns new=%.0fns  trigram old=%.0fns new=%.0fns",
            oldNext, newNext, oldCount, newCount, oldBig, newBig, oldTri, newTri))
        assertTrue(newHeap < oldHeap / 2, "bảng gọn phải nhẹ hơn hẳn ($newHeap vs $oldHeap)")
        assertTrue(newNext < oldNext * 1.5 + 2000, "nextWords không được chậm đi đáng kể")
        assertTrue(newCount < oldCount * 1.5 + 200)
        println("USERLM keep ${old.hashCode() xor new.hashCode()}")
    }
}
