package com.viettelex.keyboard

import com.viettelex.telexcore.EnglishContextLookup
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.text.Normalizer
import java.util.Random

/**
 * Đo TỰ SỬA ([AutoCorrect]) bằng mô phỏng chạm (TouchSim): câu heldout gõ Telex qua chọn phím
 * thông minh (mặc định) → từ ra sai/đúng → autocorrect ở dấu cách.
 * - precision = sửa đúng / mọi lần sửa (gồm sửa từ ĐÚNG = sửa oan); recall = sửa đúng / từ ra sai.
 * - Tập "giữ nguyên": tiếng Anh, chat/viết tắt, từ lạ (OOV), gõ không dấu — gõ đúng mà bị sửa = oan;
 *   gõ trượt thì chỉ tính đúng nếu sửa về đúng từ đó.
 * AUTOCORRECT_EVAL=1: dò ngưỡng trên DEV + bảng TEST; VT_SLOW_TESTS=1: ngưỡng hồi quy trên TEST.
 */
class AutoCorrectEvalTests {
    @Before fun setUp() = TestAssets.install()

    private val g = TouchSim.Geo()
    private val all by lazy { TouchSim.heldout() }
    private val dev by lazy { all.filterIndexed { i, _ -> i % 2 == 0 } }
    private val test by lazy { all.filterIndexed { i, _ -> i % 2 == 1 } }
    private val bridge = EngineBridge(KeyboardSettings())
    private val seed by lazy { SeedData.load().unigrams.keys }

    private fun compose(r: String) = bridge.composeTrial(r)
    private fun freq(w: String) = VNSuggest.frequency(w)
    private fun hasCompletion(w: String) = VNSuggest.matches(w, poolLimit = 1).isNotEmpty()
    /** ≈ bàn phím thật: tiếng Anh + từ seed của model cá nhân (chat "ko", "dc"…). */
    private fun known(w: String) = SwipeEnglish.contains(w) || EnglishContextLookup.opensEnglishRun(w) || w in seed

    /** Một từ đã gõ: ứng viên (null = không đủ điều kiện sửa), đúng/sai, dạng muốn (chuẩn hoá). */
    private class Rec(val typed: String, val touches: List<AutoCorrect.Touch>, val cands: List<AdjacentKeyFixer.Candidate>?, val ok: Boolean, val want: String)

    private fun candidatesFor(typed: String): List<AdjacentKeyFixer.Candidate>? {
        if (typed.length !in 2..10 || !typed.all { it in 'a'..'z' }) return null
        if (known(typed)) return null
        val cur = compose(typed)
        if (cur != typed && known(cur.lowercase())) return null
        if (freq(cur) != null || hasCompletion(cur)) return null
        // = AutoCorrect.plan: thay phím kề + bỏ phím chạm đúp.
        return AdjacentKeyFixer.oneEditCandidates(typed, ::compose, ::freq, ::hasCompletion) +
            AutoCorrect.repeatCandidates(typed, ::compose, ::freq)
    }

    /** Gõ [keys] bằng chạm mô phỏng ([pr] null = gõ chuẩn giữa phím). */
    private fun typeKeys(keys: String, pr: TouchSim.Profile?, rng: Random, router: (KPoint, String) -> Int): Pair<String, List<AutoCorrect.Touch>> {
        val typed = StringBuilder()
        val touches = ArrayList<AutoCorrect.Touch>()
        for (ch in keys) {
            val k = g.index[ch - 'a']
            val p = if (pr == null) KPoint(g.center(k).x, g.center(k).y + TouchGeometry.yOffset) else TouchSim.tap(g, k, pr, rng)
            val m = router(p, typed.toString())
            if (m < 0) continue
            typed.append(g.keys[m])
            val q = TouchGeometry.keySelectionPoint(p)
            val r = g.rects[m]
            touches.add(AutoCorrect.Touch((q.x - (r.left + r.right) / 2) / (r.right - r.left), (q.y - (r.top + r.bottom) / 2) / (r.bottom - r.top)))
        }
        return typed.toString() to touches
    }

    private fun collectVn(sents: List<List<String>>, pr: TouchSim.Profile, seedN: Long, router: (KPoint, String) -> Int): List<Rec> {
        val rng = Random(seedN)
        val out = ArrayList<Rec>()
        for (sent in sents) for (syl in sent) {
            val intended = TouchSim.pickVariant(syl, rng) ?: continue
            val (t, touches) = typeKeys(intended, pr, rng, router)
            val want = SyllableLM.normalize(compose(intended))
            out.add(Rec(t, touches, candidatesFor(t), SyllableLM.normalize(compose(t)) == want, want))
        }
        return out
    }

    /** Từ phải để nguyên khi gõ đúng; gõ trượt thì chỉ được sửa về đúng nó. */
    private fun collectKeep(words: List<String>, pr: TouchSim.Profile?, seedN: Long, router: (KPoint, String) -> Int): List<Rec> {
        val rng = Random(seedN)
        return words.filter { w -> w.isNotEmpty() && w.all { it in 'a'..'z' } }.map { w ->
            val (t, touches) = typeKeys(w, pr, rng, router)
            Rec(t, touches, candidatesFor(t), t == w, w)
        }
    }

    private class Score(var fix: Int = 0, var good: Int = 0, var wrong: Int = 0, var falseFix: Int = 0, var err: Int = 0, var words: Int = 0) {
        val precision get() = if (fix == 0) 1.0 else good.toDouble() / fix
        val recall get() = if (err == 0) 0.0 else good.toDouble() / err
        fun add(o: Score) { fix += o.fix; good += o.good; wrong += o.wrong; falseFix += o.falseFix; err += o.err; words += o.words }
        override fun toString() = "từ $words | sai $err | sửa $fix (đúng $good, nhầm $wrong, oan $falseFix) | P=" +
            "%.1f%% R=%.1f%%".format(100 * precision, 100 * recall)
    }

    private fun decide(r: Rec, p: AutoCorrect.Params): AdjacentKeyFixer.Candidate? {
        if (r.typed.length < p.minLen) return null
        return r.cands?.let { AutoCorrect.pick(r.typed, it, r.touches, p) }
    }

    private fun score(recs: List<Rec>, p: AutoCorrect.Params): Score {
        val s = Score()
        for (r in recs) {
            s.words++
            if (!r.ok) s.err++
            val c = decide(r, p) ?: continue
            s.fix++
            when {
                r.ok -> s.falseFix++
                SyllableLM.normalize(c.word) == r.want -> s.good++
                else -> s.wrong++
            }
        }
        return s
    }

    private fun toneless(s: String): String {
        val d = Normalizer.normalize(s.replace('đ', 'd').replace('Đ', 'D'), Normalizer.Form.NFD)
        return d.filter { it.code < 0x300 || it.code > 0x36F }
    }

    private val prior by lazy { TelexKeyPrior.fromLexicon() }
    private fun router() = TouchSim.bayes(g, prior, TouchTarget.DEFAULT)

    private fun keepSets(n: Int, sents: List<List<String>>): List<Pair<String, List<String>>> {
        val en = TouchSim.englishWords(n, Random(7)).map { it[0] }
        val chat = TouchSim.chatWords(n, Random(8)).map { it[0] }
        val oov = TouchSim.oovWords(3).map { it[0] }
        val tl = sents.take(400).flatten().map { toneless(it) }
        return listOf("en" to en, "chat" to chat, "oov" to oov, "khôngdấu" to tl)
    }

    @Test fun report() {
        if (System.getenv("AUTOCORRECT_EVAL") == null) return
        val r = router()
        val profiles = TouchSim.PROFILES.take(3)
        val devRecs = profiles.flatMap { collectVn(dev, it, 1L, r) }
        val devKeep = keepSets(1500, dev).flatMap { (_, w) -> collectKeep(w, TouchSim.PROFILES[1], 2L, r) + collectKeep(w, null, 0L, r) }
        fun line(p: AutoCorrect.Params): String {
            val v = score(devRecs, p); val k = score(devKeep, p)
            val tot = Score().also { it.add(v); it.add(k) }
            return "vn $v | giữ-nguyên sửa ${k.fix} (oan ${k.falseFix}, nhầm ${k.wrong}) | P(tổng)=" + "%.1f%%".format(100 * tot.precision)
        }
        for (minEv in listOf(0f, 0.1f, 0.2f, 0.3f)) for (minFreq in listOf(130, 150, 170, 190)) for (margin in listOf(0, 15, 30, 45))
            for (ml in listOf(3, 4)) {
                val p = AutoCorrect.Params(ml, minFreq, margin, minEv)
                println("TUNE len=$ml minFreq=$minFreq margin=$margin minEv=$minEv | ${line(p)}")
            }
        if (System.getenv("AUTOCORRECT_DUMP") != null) for (r0 in devRecs + devKeep) {
            val c = decide(r0, AutoCorrect.DEFAULT) ?: continue
            if (!r0.ok && SyllableLM.normalize(c.word) == r0.want) continue
            println("DUMP ${r0.typed} → ${c.word} (muốn ${r0.want}) | " +
                r0.cands!!.joinToString { "${it.word}:${it.freq}@${it.pos}${it.key}" })
        }
        val p = AutoCorrect.DEFAULT
        val tot = Score()
        for (pr in profiles) for (sd in listOf(11L, 22L)) {
            val s = score(collectVn(test, pr, sd, r), p); tot.add(s)
            println("TEST ${pr.name} seed=$sd | $s")
        }
        for ((name, w) in keepSets(2500, test)) {
            val a = score(collectKeep(w, null, 0L, r), p); val b = score(collectKeep(w, TouchSim.PROFILES[1], 3L, r), p)
            tot.add(a); tot.add(b)
            println("TEST giữ-nguyên $name gõ-đúng | $a")
            println("TEST giữ-nguyên $name chạm-vừa | $b")
        }
        println("TEST TỔNG | $tot")
    }

    /** Hồi quy (test chậm): precision ≥ 97% trên TEST (VN + tập giữ nguyên), recall không tụt. */
    @Test fun precisionFloor() {
        SlowTests.assume()
        val r = router()
        val p = AutoCorrect.DEFAULT
        val tot = Score()
        for (pr in TouchSim.PROFILES.take(3)) tot.add(score(collectVn(test, pr, 11L, r), p))
        for ((_, w) in keepSets(1500, test)) {
            tot.add(score(collectKeep(w, null, 0L, r), p)); tot.add(score(collectKeep(w, TouchSim.PROFILES[1], 3L, r), p))
        }
        println("AUTOCORRECT test: $tot")
        assertTrue("precision $tot", tot.precision >= 0.97)
        assertTrue("recall $tot", tot.recall >= 0.15)
    }
}
