package com.viettelex.keyboard

import java.time.Instant

/**
 * CHẾ ĐỘ LUYỆN VUỐT (app, không phải bàn phím) — phần THUẦN: từ mục tiêu, chấm một nét,
 * định dạng nét vuốt thật để xuất/đánh giá decoder. Song sinh iOS App/Practice/SwipePractice.swift;
 * cùng định dạng JSON (fixture chung KeyboardTests/Fixtures/swipe-traces-sample.json).
 *
 * Định dạng xuất (v1): {"format":"viettelex-swipe-traces","version":1,"platform":…,
 * "exported":ISO-8601,"traces":[trace…]}; trace = {"target","folded","lang":"vi"|"en",
 * "keyWidth","keys":{"a":[x,y]…},"points":[[x,y,ms]…],"decoded":[top-K],"time":epoch ms}.
 * Toạ độ cùng hệ với keyWidth (px Android / pt iOS) — decoder chuẩn hoá theo bước phím.
 * Lưu trên máy dạng JSON Lines (mỗi dòng một trace, ghi nối) — không bao giờ gửi mạng.
 */
data class SwipeTrace(
    val target: String,
    val folded: String,
    val lang: SwipeLang,
    val keyWidth: Float,
    val keys: Map<Char, Pair<Float, Float>>,
    /** x, y, ms kể từ điểm đầu. */
    val points: List<Triple<Float, Float, Float>>,
    val decoded: List<String>,
    val timeMs: Long,
) {
    val layout: SwipeLayout get() = SwipeLayout(keyWidth, keys)

    fun path(): SwipePath {
        val p = SwipePath(minDistance = keyWidth / 5f)
        for ((i, pt) in points.withIndex()) p.add(pt.first, pt.second, pt.third / 1000.0, force = i == points.size - 1)
        return p
    }

    /** Đúng khi top-1 lúc ghi = chuỗi mục tiêu. */
    val hit: Boolean get() = decoded.firstOrNull() == folded
}

object SwipePractice {
    const val FORMAT = "viettelex-swipe-traces"
    const val VERSION = 1
    const val MAX_TRACES = 5000

    data class Target(val word: String, val folded: String, val lang: SwipeLang)

    /** Âm tiết Việt phổ biến (tần suất lexicon) — ≥ 2 phím sau gộp chữ lặp (1 phím là chạm). */
    val vietnamese: List<Target> by lazy {
        val lex = VNLexicon2Data.blob
        (0 until VNLexicon2Data.count).asSequence()
            .map { it to lex.freq(it) }
            .sortedByDescending { it.second }
            .map { VNSuggest.display(it.first) }
            .filter { w -> keyCount(SwipeSuggest.fold(w)) >= 2 && SwipeLexicon.indexOf(SwipeSuggest.fold(w)) >= 0 }
            .distinct().take(VI_POOL)
            .map { Target(it, SwipeSuggest.fold(it), SwipeLang.VI) }.toList()
    }

    /** Từ tiếng Anh phổ biến, ≥ 3 chữ, KHÔNG trùng chuỗi dạng Việt (the/thế — nét y hệt). */
    val english: List<Target> by lazy {
        val en = SwipeEnglish.lexicon
        (0 until en.count).sortedByDescending { en.freq(it) }.asSequence()
            .map { en.word(it) }
            .filter { it.length >= 3 && SwipeLexicon.indexOf(it) < 0 }
            .take(EN_POOL).map { Target(it, it, SwipeLang.EN) }.toList()
    }

    private const val VI_POOL = 400
    private const val EN_POOL = 120
    /** ~1/5 mục tiêu là tiếng Anh. */
    private const val EN_EVERY = 5

    /** Số phím sau gộp chữ lặp (luu → lu). */
    fun keyCount(folded: String): Int { var n = 0; var prev = ' '; for (c in folded) { if (c != prev) n++; prev = c }; return n }

    /** Mục tiêu thứ [i] của phiên [seed] — tất định (SplitMix64 như SwipeSim). */
    fun target(seed: Long, i: Int): Target {
        var z = (seed + (i + 1) * -0x61c8864680b583ebL)
        z = (z xor (z ushr 30)) * -0x40a7b892e31b1a47L
        z = (z xor (z ushr 27)) * -0x6b2fb644ecceee15L
        z = z xor (z ushr 31)
        val r = (z ushr 1)
        val pool = if (r % EN_EVERY == 0L && english.isNotEmpty()) english else vietnamese
        return pool[((r / EN_EVERY) % pool.size).toInt()]
    }

    /** Giải mã một nét như bàn phím, ngữ cảnh ngôn ngữ theo mục tiêu (luyện từng từ rời). */
    fun decode(decoder: SwipeDecoder, path: SwipePath, lang: SwipeLang, topK: Int = SwipeSuggest.TOP_K): List<SwipeCandidate> =
        decoder.decode(path, topK, null, if (lang == SwipeLang.EN) SwipeLangContext.ENGLISH else SwipeLangContext.DEFAULT)

    // ---- JSON ----

    fun toJson(t: SwipeTrace): Map<String, Any?> = linkedMapOf(
        "target" to t.target, "folded" to t.folded, "lang" to if (t.lang == SwipeLang.EN) "en" else "vi",
        "keyWidth" to r2(t.keyWidth),
        "keys" to t.keys.entries.sortedBy { it.key }.associate { (c, p) -> c.toString() to listOf(r2(p.first), r2(p.second)) },
        "points" to t.points.map { listOf(r2(it.first), r2(it.second), r2(it.third)) },
        "decoded" to t.decoded, "time" to t.timeMs,
    )

    private fun r2(v: Float): Double = Math.round(v * 100.0) / 100.0

    fun fromJson(m: Any?): SwipeTrace? {
        if (m !is Map<*, *>) return null
        val target = m["target"] as? String ?: return null
        val folded = m["folded"] as? String ?: return null
        val kw = (m["keyWidth"] as? Number)?.toFloat()?.takeIf { it > 0f } ?: return null
        val keys = HashMap<Char, Pair<Float, Float>>()
        for ((k, v) in m["keys"] as? Map<*, *> ?: return null) {
            val c = (k as? String)?.singleOrNull()?.takeIf { it in 'a'..'z' } ?: return null
            val xy = v as? List<*> ?: return null
            val x = (xy.getOrNull(0) as? Number)?.toFloat() ?: return null
            val y = (xy.getOrNull(1) as? Number)?.toFloat() ?: return null
            keys[c] = x to y
        }
        val pts = (m["points"] as? List<*> ?: return null).map { p ->
            val a = p as? List<*> ?: return null
            Triple((a.getOrNull(0) as? Number)?.toFloat() ?: return null,
                (a.getOrNull(1) as? Number)?.toFloat() ?: return null,
                (a.getOrNull(2) as? Number)?.toFloat() ?: return null)
        }
        if (pts.isEmpty()) return null
        return SwipeTrace(target, folded, if (m["lang"] == "en") SwipeLang.EN else SwipeLang.VI, kw, keys, pts,
            (m["decoded"] as? List<*>)?.filterIsInstance<String>() ?: emptyList(),
            (m["time"] as? Number)?.toLong() ?: 0L)
    }

    /** Một dòng JSON Lines để ghi nối vào kho trên máy. */
    fun line(t: SwipeTrace): String = MiniJson.write(toJson(t), pretty = false)

    /** Đọc kho JSON Lines (dòng hỏng bỏ qua). */
    fun parseLines(text: String): List<SwipeTrace> = text.lineSequence().filter { it.isNotBlank() }.mapNotNull {
        try { fromJson(MiniJson.parse(it)) } catch (e: IllegalArgumentException) { null }
    }.toList()

    /** Tài liệu xuất (share sheet). */
    fun export(traces: List<SwipeTrace>, platform: String, now: Instant = Instant.now()): String =
        MiniJson.write(linkedMapOf("format" to FORMAT, "version" to VERSION.toLong(), "platform" to platform,
            "exported" to now.toString(), "traces" to traces.map(::toJson)), pretty = false) + "\n"

    /** Đọc tài liệu xuất; null nếu không phải định dạng này / phiên bản mới hơn. */
    fun parseExport(text: String): List<SwipeTrace>? {
        val root = try { MiniJson.parse(text.removePrefix("﻿")) } catch (e: IllegalArgumentException) { return null }
        if (root !is Map<*, *> || root["format"] != FORMAT) return null
        if (((root["version"] as? Number)?.toInt() ?: return null) > VERSION) return null
        return (root["traces"] as? List<*>)?.mapNotNull(::fromJson)
    }

    /** Độ chính xác một tập nét: top-1 / top-3 theo decoder hiện tại. */
    data class Report(val n: Int, val top1: Int, val top3: Int, val recorded: Int) {
        fun fmt() = String.format(java.util.Locale.ROOT, "n=%d top1 %.3f top3 %.3f (lúc ghi %.3f)",
            n, top1.toDouble() / maxOf(1, n), top3.toDouble() / maxOf(1, n), recorded.toDouble() / maxOf(1, n))
    }

    fun evaluate(traces: List<SwipeTrace>): Report {
        var t1 = 0; var t3 = 0; var rec = 0
        val decoders = HashMap<SwipeLayout, SwipeDecoder>()
        for (t in traces) {
            val d = decoders.getOrPut(t.layout) { SwipeDecoder().also { it.setLayout(t.layout) } }
            val c = decode(d, t.path(), t.lang).map { it.folded }
            if (c.firstOrNull() == t.folded) t1++
            if (t.folded in c.take(3)) t3++
            if (t.hit) rec++
        }
        return Report(traces.size, t1, t3, rec)
    }
}
