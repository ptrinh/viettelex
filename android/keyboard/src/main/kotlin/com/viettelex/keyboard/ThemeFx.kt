package com.viettelex.keyboard

import java.text.Normalizer
import java.util.Locale
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/*
 * Theme JSON tương tác KHÔNG cần mã: "particles" (hạt tự tạo) + "keywords" (từ khoá tự tạo). CHỈ dữ liệu — không biểu
 * thức / kịch bản / mã. Song sinh iOS/Keyboard/ThemeFx.swift (đặc tả đầy đủ ở đầu tệp đó): cùng luật đọc, cùng chuỗi
 * chuẩn, cùng hàm phát hạt (FxRandom chung) — fixture chung theme-json-cases.txt.
 *
 * "particles": {"glyphs":["🍜"] | "shape":"circle|star|heart|square|spark", "colors":[…1…8], "count":1…12,
 *   "spread":0…360, "direction":-360…360 (0 = lên, 90 = phải), "speed":20…600 dp/s, "gravity":-800…800 dp/s² (dương =
 *   xuống), "lifeMs":200…2500, "size":8…48 dp, "sizeJitter":0…100 %, "spin":-720…720 độ/s, "fade":"out|inOut",
 *   "origin":"key|bottom|top"} — dùng khi hiệu ứng = "Theo giao diện" (KeyEffect.THEME, id "theme").
 * "keywords": [{"words":[…1…8, ≤ 32 ký tự, chỉ chữ, ≤ 2 từ], "burst":{…}?, "text":"≤ 16"?}] ≤ 20 mục — nổ THÊM cùng
 *   mọi hiệu ứng ở ranh giới từ (dấu có nghĩa, không phân biệt hoa thường; cụm hai từ khớp với từ liền trước).
 */

/** Hạt tự tạo — trường null = mặc định (giữ đúng những gì người dùng viết để "Chép JSON" khứ hồi). */
data class ThemeParticles(
    val glyphs: List<String>? = null,
    val shape: String? = null,
    val colors: List<Int>? = null,
    val count: Int? = null,
    val spread: Int? = null,
    val direction: Int? = null,
    val speed: Int? = null,
    val gravity: Int? = null,
    val lifeMs: Int? = null,
    val size: Int? = null,
    val sizeJitter: Int? = null,
    val spin: Int? = null,
    val fade: String? = null,
    val origin: String? = null,
) {
    fun int(k: String): Int? = when (k) {
        "count" -> count; "spread" -> spread; "direction" -> direction; "speed" -> speed; "gravity" -> gravity
        "lifeMs" -> lifeMs; "size" -> size; "sizeJitter" -> sizeJitter; "spin" -> spin
        else -> null
    }
    fun withInt(k: String, v: Int): ThemeParticles = when (k) {
        "count" -> copy(count = v); "spread" -> copy(spread = v); "direction" -> copy(direction = v)
        "speed" -> copy(speed = v); "gravity" -> copy(gravity = v); "lifeMs" -> copy(lifeMs = v)
        "size" -> copy(size = v); "sizeJitter" -> copy(sizeJitter = v); "spin" -> copy(spin = v)
        else -> this
    }

    val effCount: Int get() = count ?: 4
    val effSpread: Int get() = spread ?: 60
    val effDirection: Int get() = direction ?: 0
    val effSpeed: Int get() = speed ?: 120
    val effGravity: Int get() = gravity ?: 0
    val effLifeMs: Int get() = lifeMs ?: 900
    val effSize: Int get() = size ?: 16
    val effSizeJitter: Int get() = sizeJitter ?: 0
    val effSpin: Int get() = spin ?: 0
    val effShape: String get() = shape ?: "circle"
    val fadesIn: Boolean get() = fade == "inOut"
    val effOrigin: String get() = origin ?: "key"
    val life: Double get() = effLifeMs / 1000.0

    /** Hạt thứ [i] của lần bấm số [seed] — y hệt iOS `ThemeParticles.particle` (dp / giây / radian). */
    fun particle(i: Int, seed: Int): ThemeParticle {
        val r = FxRandom(seed * 131 + i)
        val n = max(effCount, 1)
        val spread = effSpread.toDouble(); val dir = effDirection.toDouble()
        var deg = when {
            n == 1 -> dir
            effSpread >= 360 -> dir + 360.0 * i / n
            else -> dir - spread / 2 + spread * i / (n - 1)
        }
        deg += (r.next() - 0.5) * spread / n * 0.5
        val a = deg * Math.PI / 180
        val sp = effSpeed * (0.8 + 0.4 * r.next())
        val jitter = effSizeJitter / 100.0
        val sz = max(4.0, effSize * (1 + jitter * (r.next() * 2 - 1)))
        val life = this.life
        return ThemeParticle(sin(a) * sp, -cos(a) * sp, effGravity.toDouble(), life, sz, effSpin * Math.PI / 180 * life,
            fadesIn, i % max(colors?.size ?: 1, 1), i % max(glyphs?.size ?: 1, 1))
    }

    companion object {
        val SHAPES = listOf("circle", "star", "heart", "square", "spark")
        val FADES = listOf("out", "inOut")
        val ORIGINS = listOf("key", "bottom", "top")
        const val MAX_GLYPHS = 8
        const val MAX_COLORS = 8
        /** Khoảng từng trường số (iOS ThemeParticles.ranges y hệt, cùng thứ tự). */
        val RANGES: List<Pair<String, IntRange>> = listOf("count" to 1..12, "spread" to 0..360, "direction" to -360..360,
            "speed" to 20..600, "gravity" to -800..800, "lifeMs" to 200..2500, "size" to 8..48, "sizeJitter" to 0..100,
            "spin" to -720..720)
        val KEYS: Set<String> = setOf("glyphs", "shape", "colors", "fade", "origin") + RANGES.map { it.first }

        /** "Theo giao diện" khi theme không có "particles": chùm sao nhỏ theo màu nhấn. */
        val FALLBACK = ThemeParticles(shape = "star", count = 5, spread = 120, speed = 140, gravity = 220, lifeMs = 800,
            size = 12, sizeJitter = 30, spin = 180)
        /** Chùm từ khoá khi mục không có "burst" và theme không có "particles": tim toả tròn. */
        val KEYWORD_FALLBACK = ThemeParticles(shape = "heart", colors = listOf(0xFFFF3B6B.toInt(), 0xFFFF7AA2.toInt(),
            0xFFE91E63.toInt()), count = 8, spread = 360, speed = 110, gravity = -40, lifeMs = 1000, size = 14, sizeJitter = 30)

        /** Số chùm xoay vòng: tổng hạt sống ≤ [KeyEffectPool.CAP]. */
        fun slots(perBurst: Int): Int = max(1, min(8, KeyEffectPool.CAP / max(perBurst, 1)))
    }
}

/** Một hạt đã giải: vận tốc đầu (dp/s), gia tốc dọc, đời (s), cỡ (dp), góc quay tổng (rad). iOS ThemeParticle. */
data class ThemeParticle(val vx: Double, val vy: Double, val gravity: Double, val life: Double, val size: Double,
                         val rotation: Double, val fadeIn: Boolean, val colorIndex: Int, val glyphIndex: Int) {
    fun offsetX(t: Double): Double = vx * t.coerceIn(0.0, life)
    fun offsetY(t: Double): Double { val u = t.coerceIn(0.0, life); return vy * u + 0.5 * gravity * u * u }
    fun alpha(t: Double): Double {
        if (life <= 0 || t < 0 || t >= life) return 0.0
        val f = t / life
        if (fadeIn && f < 0.15) return f / 0.15
        return if (f < 0.5) 1.0 else max(0.0, (1 - f) / 0.5)
    }
}

data class ThemeKeyword(val words: List<String>, val burst: ThemeParticles? = null, val text: String? = null) {
    companion object {
        const val MAX_ENTRIES = 20
        const val MAX_WORDS = 8
        const val MAX_WORD_LENGTH = 32
        const val MAX_TEXT = 16
        val KEYS = setOf("words", "burst", "text")
    }
}

/** Bảng tra từ khoá tự tạo — luật như "Từ khoá" có sẵn (iOS ThemeKeywordTable y hệt). */
class ThemeKeywordTable(list: List<ThemeKeyword>) {
    val entries: List<ThemeKeyword> = list.take(ThemeKeyword.MAX_ENTRIES)
    private val index: Map<String, Int> = HashMap<String, Int>().also { m ->
        entries.forEachIndexed { i, e -> e.words.forEach { w -> val k = normalize(w); if (k.isNotEmpty()) m.putIfAbsent(k, i) } }
    }
    val isEmpty: Boolean get() = index.isEmpty()

    override fun equals(other: Any?): Boolean = other is ThemeKeywordTable && other.entries == entries
    override fun hashCode(): Int = entries.hashCode()

    /** Chỉ số mục cho từ vừa chốt [word] (từ liền trước [prev]). O(1); null = không khớp. */
    fun lookup(word: String, prev: String?): Int? {
        if (index.isEmpty()) return null
        val w = clean(word)
        if (w.isEmpty() || w.codePointCount(0, w.length) > ThemeKeyword.MAX_WORD_LENGTH) return null
        val p = prev?.let(::clean)
        if (EmojiWords.blocked(w, p)) return null
        if (!p.isNullOrEmpty()) index["$p $w"]?.let { return it }
        return index[w]
    }

    companion object {
        fun normalize(s: String): String = Normalizer.normalize(s.lowercase(Locale.ROOT), Normalizer.Form.NFC)
        private fun isLetterCp(cp: Int): Boolean = Character.isLetter(cp) || isMark(cp)
        fun isMark(cp: Int): Boolean = when (Character.getType(cp).toByte()) {
            Character.NON_SPACING_MARK, Character.COMBINING_SPACING_MARK, Character.ENCLOSING_MARK -> true
            else -> false
        }
        /** Bỏ ký tự không phải chữ ở hai đầu (theo code point — như iOS CharacterSet.letters). */
        fun clean(s: String): String {
            var a = 0; var b = s.length
            while (a < b && !isLetterCp(s.codePointAt(a))) a += Character.charCount(s.codePointAt(a))
            while (b > a && !isLetterCp(s.codePointBefore(b))) b -= Character.charCount(s.codePointBefore(b))
            return normalize(s.substring(a, b))
        }
        /** Từ khoá hợp lệ: 1–2 phần cách đúng một dấu cách, mỗi phần chỉ chữ (gồm dấu kết hợp). */
        fun isValidWord(s: String): Boolean {
            val parts = s.split(' ')
            if (parts.size !in 1..2) return false
            return parts.all { p -> p.isNotEmpty() && p.codePoints().allMatch { isLetterCp(it) } }
        }
    }
}

/** Phần tương tác của theme đang dùng (IME giải một lần lúc hiện). iOS ThemeFx. */
data class ThemeFx(val particles: ThemeParticles?, val keywords: ThemeKeywordTable?) {
    fun burst(keyword: Int): ThemeParticles = keywords?.entries?.getOrNull(keyword)?.burst ?: particles ?: ThemeParticles.KEYWORD_FALLBACK
    /** Số chùm từ khoá xoay vòng: mọi mục ≤ 10 phần tử ⇒ 2, không thì 1. */
    val keywordSlots: Int get() {
        val k = keywords ?: return 0
        val worst = k.entries.indices.maxOfOrNull { burst(it).effCount + (if (k.entries[it].text == null) 0 else 1) } ?: 0
        return if (worst <= KeyEffectPool.CAP / 2) 2 else 1
    }

    companion object {
        fun make(spec: ThemeSpec?): ThemeFx? {
            spec ?: return null
            val table = spec.keywords?.let { ThemeKeywordTable(it) }?.takeIf { !it.isEmpty }
            if (spec.particles == null && table == null) return null
            return ThemeFx(spec.particles, table)
        }
    }
}

/** Thực chạy: hết Plus / tiết kiệm pin ⇒ null (như [KeyEffectPolicy]). */
object ThemeFxPolicy {
    fun active(fx: ThemeFx?, plus: Boolean, powerSave: Boolean): ThemeFx? = if (fx == null || !plus || powerSave) null else fx
}

/** Gốc chùm theo "origin" (toạ độ overlay): "key" = tâm phím; "bottom"/"top" = mép bàn phím lùi nửa cỡ. iOS y hệt. */
object ThemeFxOrigin {
    fun x(keyX: Double, minX: Double, maxX: Double): Double = keyX.coerceIn(minX, maxX)
    fun y(origin: String, keyY: Double, size: Double, minY: Double, maxY: Double): Double = when (origin) {
        "bottom" -> maxY - size / 2
        "top" -> minY + size / 2
        else -> keyY.coerceIn(minY, maxY)
    }
}

/** MỘT ký tự hiển thị (grapheme) — luật thuần theo code point, y hệt iOS ThemeGlyph. */
object ThemeGlyph {
    const val MAX_SCALARS = 16
    private fun isExtender(v: Int): Boolean = v in 0xFE00..0xFE0F || v in 0x1F3FB..0x1F3FF || v == 0x20E3 ||
        v in 0x0300..0x036F || v in 0xE0020..0xE007F || v in 0x1AB0..0x1AFF || v in 0x20D0..0x20FF
    private fun isRegional(v: Int): Boolean = v in 0x1F1E6..0x1F1FF
    private fun isSpaceOrControl(v: Int): Boolean = v <= 0x20 || v in 0x7F..0xA0 || v == 0x1680 || v in 0x2000..0x200B ||
        v == 0x2028 || v == 0x2029 || v == 0x202F || v == 0x205F || v == 0x3000 || v == 0xFEFF

    fun isSingle(cps: IntArray): Boolean {
        if (cps.isEmpty() || cps.size > MAX_SCALARS) return false
        if (cps.any { isSpaceOrControl(it) }) return false
        val first = cps[0]
        if (isExtender(first) || first == 0x200D) return false
        if (isRegional(first)) return cps.size == 2 && isRegional(cps[1])
        var i = 1
        while (i < cps.size) {
            val v = cps[i]
            if (isExtender(v)) { i++; continue }
            if (v == 0x200D) {
                if (i + 1 >= cps.size || isExtender(cps[i + 1]) || cps[i + 1] == 0x200D || isRegional(cps[i + 1])) return false
                i += 2; continue
            }
            return false
        }
        return true
    }
    fun isSingle(s: String): Boolean = isSingle(s.codePoints().toArray())
}

/** Đọc / kiểm / ghi chuẩn — ThemeSpecParser gọi; lỗi cùng bảng mã. iOS ThemeFxParser y hệt. */
object ThemeFxParser {
    private fun cpLen(s: String) = s.codePointCount(0, s.length)

    fun particles(v: SJ, p: String): Pair<ThemeParticles?, List<ThemeIssue>> {
        if (v !is SJ.Obj) return null to listOf(ThemeIssue(ThemeIssue.Code.wrongType, p))
        val issues = ArrayList<ThemeIssue>()
        fun err(c: ThemeIssue.Code, path: String) { issues.add(ThemeIssue(c, path)) }
        for ((k, _) in v.m) if (k !in ThemeParticles.KEYS) err(ThemeIssue.Code.unknownKey, "$p.$k")
        var out = ThemeParticles()
        v["glyphs"]?.let { g ->
            if (g is SJ.Arr) {
                if (g.a.isEmpty() || g.a.size > ThemeParticles.MAX_GLYPHS) err(ThemeIssue.Code.badValue, "$p.glyphs")
                val list = ArrayList<String>()
                g.a.forEachIndexed { i, e ->
                    val ip = "$p.glyphs[$i]"
                    when {
                        e !is SJ.Str -> err(ThemeIssue.Code.wrongType, ip)
                        !ThemeGlyph.isSingle(e.s) -> err(ThemeIssue.Code.badValue, ip)
                        else -> list.add(e.s)
                    }
                }
                out = out.copy(glyphs = list)
            } else err(ThemeIssue.Code.wrongType, "$p.glyphs")
        }
        v["shape"]?.let { s ->
            if (s is SJ.Str) {
                when {
                    s.s !in ThemeParticles.SHAPES -> err(ThemeIssue.Code.badValue, "$p.shape")
                    v["glyphs"] != null -> err(ThemeIssue.Code.badValue, "$p.shape")
                    else -> out = out.copy(shape = s.s)
                }
            } else err(ThemeIssue.Code.wrongType, "$p.shape")
        }
        v["colors"]?.let { cv ->
            if (cv is SJ.Arr) {
                if (cv.a.isEmpty() || cv.a.size > ThemeParticles.MAX_COLORS) err(ThemeIssue.Code.badValue, "$p.colors")
                val list = ArrayList<Int>()
                cv.a.forEachIndexed { i, e ->
                    val ip = "$p.colors[$i]"
                    if (e !is SJ.Str) { err(ThemeIssue.Code.wrongType, ip); return@forEachIndexed }
                    val c = ThemeColorCode.parse(e.s)
                    if (c == null) err(ThemeIssue.Code.badColor, ip) else list.add(c)
                }
                out = out.copy(colors = list)
            } else err(ThemeIssue.Code.wrongType, "$p.colors")
        }
        for ((k, r) in ThemeParticles.RANGES) {
            val x = v[k] ?: continue
            if (x !is SJ.Num) { err(ThemeIssue.Code.wrongType, "$p.$k"); continue }
            if (x.v !in r) err(ThemeIssue.Code.clamped, "$p.$k")
            out = out.withInt(k, x.v.coerceIn(r.first, r.last))
        }
        fun pick(k: String, allowed: List<String>): String? {
            val x = v[k] ?: return null
            if (x !is SJ.Str) { err(ThemeIssue.Code.wrongType, "$p.$k"); return null }
            if (x.s !in allowed) { err(ThemeIssue.Code.badValue, "$p.$k"); return null }
            return x.s
        }
        out = out.copy(fade = pick("fade", ThemeParticles.FADES), origin = pick("origin", ThemeParticles.ORIGINS))
        return (if (issues.any { it.isError }) null else out) to issues
    }

    fun keywords(v: SJ): Pair<List<ThemeKeyword>?, List<ThemeIssue>> {
        if (v !is SJ.Arr) return null to listOf(ThemeIssue(ThemeIssue.Code.wrongType, "keywords"))
        if (v.a.size > ThemeKeyword.MAX_ENTRIES) return null to listOf(ThemeIssue(ThemeIssue.Code.badValue, "keywords"))
        val issues = ArrayList<ThemeIssue>()
        fun err(c: ThemeIssue.Code, path: String) { issues.add(ThemeIssue(c, path)) }
        val out = ArrayList<ThemeKeyword>()
        v.a.forEachIndexed { i, e ->
            val p = "keywords[$i]"
            if (e !is SJ.Obj) { err(ThemeIssue.Code.wrongType, p); return@forEachIndexed }
            for ((k, _) in e.m) if (k !in ThemeKeyword.KEYS) err(ThemeIssue.Code.unknownKey, "$p.$k")
            val words = ArrayList<String>()
            when (val ws = e["words"]) {
                null -> err(ThemeIssue.Code.missingKey, "$p.words")
                is SJ.Arr -> {
                    if (ws.a.isEmpty() || ws.a.size > ThemeKeyword.MAX_WORDS) err(ThemeIssue.Code.badValue, "$p.words")
                    ws.a.forEachIndexed { j, w ->
                        val wp = "$p.words[$j]"
                        when {
                            w !is SJ.Str -> err(ThemeIssue.Code.wrongType, wp)
                            cpLen(w.s) > ThemeKeyword.MAX_WORD_LENGTH -> err(ThemeIssue.Code.tooLong, wp)
                            !ThemeKeywordTable.isValidWord(w.s) -> err(ThemeIssue.Code.badValue, wp)
                            else -> words.add(w.s)
                        }
                    }
                }
                else -> err(ThemeIssue.Code.wrongType, "$p.words")
            }
            var burst: ThemeParticles? = null
            e["burst"]?.let { b -> val (pt, is2) = particles(b, "$p.burst"); issues.addAll(is2); burst = pt }
            var text: String? = null
            e["text"]?.let { t ->
                if (t is SJ.Str) {
                    val tt = t.s.trim { it == '\t' || Character.getType(it) == Character.SPACE_SEPARATOR.toInt() }
                    when {
                        tt.isEmpty() -> err(ThemeIssue.Code.badValue, "$p.text")
                        cpLen(tt) > ThemeKeyword.MAX_TEXT -> err(ThemeIssue.Code.tooLong, "$p.text")
                        else -> text = tt
                    }
                } else err(ThemeIssue.Code.wrongType, "$p.text")
            }
            out.add(ThemeKeyword(words, burst, text))
        }
        if (issues.any { it.isError }) return null to issues
        return (if (out.isEmpty()) null else out) to issues
    }

    fun json(t: ThemeParticles): SJ {
        val m = ArrayList<Pair<String, SJ>>()
        t.glyphs?.let { g -> m.add("glyphs" to SJ.Arr(g.map { SJ.Str(it) })) }
        t.shape?.let { m.add("shape" to SJ.Str(it)) }
        t.colors?.let { c -> m.add("colors" to SJ.Arr(c.map { SJ.Str(ThemeColorCode.format(it)) })) }
        for ((k, _) in ThemeParticles.RANGES) t.int(k)?.let { m.add(k to SJ.Num(it)) }
        t.fade?.let { m.add("fade" to SJ.Str(it)) }
        t.origin?.let { m.add("origin" to SJ.Str(it)) }
        return SJ.Obj(m)
    }

    fun json(ks: List<ThemeKeyword>): SJ = SJ.Arr(ks.map { k ->
        val m = arrayListOf<Pair<String, SJ>>("words" to SJ.Arr(k.words.map { SJ.Str(it) }))
        k.burst?.let { m.add("burst" to json(it)) }
        k.text?.let { m.add("text" to SJ.Str(it)) }
        SJ.Obj(m)
    })
}
