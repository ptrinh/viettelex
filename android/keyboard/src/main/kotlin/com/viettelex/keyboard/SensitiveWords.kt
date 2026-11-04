package com.viettelex.keyboard

/**
 * Lọc từ tục khỏi THANH GỢI Ý (vẫn học). Emoji không bị lọc. Cặp chửi/tục ghép từ hai TỪ THƯỜNG
 * (thằng chó, sờ chim…) = bảng [pairs] (SensitivePairs, sinh từ Scripts/seed-curated.txt
 * [sensitive-bigram]) — song sinh iOS SensitiveWords.swift. Bộ ba ("ngu như chó", "thằng mất dạy"…, cặp cuối là cụm
 * thường) = bảng [triples] (cần prev2, [sensitive-trigram]); [chains] = chuỗi seed ba từ ([chain]).
 */
object SensitiveWords {
    fun filter(words: List<String>, enabled: Boolean): List<String> =
        if (enabled) words.filter { it.lowercase() !in set } else words

    /**
     * Gợi ý đứng SAU [after]: bỏ từ nhạy cảm, từ tạo cặp nhạy cảm với [after] và từ tạo bộ ba nhạy cảm với
     * ([prev2], [after]). = iOS filter(_:after:prev2:enabled:).
     */
    fun filter(words: List<String>, enabled: Boolean, after: String?, prev2: String? = null): List<String> {
        if (!enabled) return words
        val gated = after?.let { pairs[it.lowercase()] }
        val gated3 = tripleGate(prev2, after)
        return words.filter {
            val l = it.lowercase()
            l !in set && (gated == null || l !in gated) && (gated3 == null || l !in gated3)
        }
    }

    /** Chỉ phần CẶP / BỘ BA — tập ngữ cảnh (điểm thưởng từ kế tiếp): lọc bật ⇒ cặp (bộ ba) nhạy cảm không thưởng. */
    fun dropPairs(words: List<String>, after: String?, enabled: Boolean, prev2: String? = null): List<String> {
        if (!enabled) return words
        val g = after?.let { pairs[it.lowercase()] }
        val g3 = tripleGate(prev2, after)
        if (g == null && g3 == null) return words
        return words.filter { val l = it.lowercase(); (g == null || l !in g) && (g3 == null || l !in g3) }
    }

    fun isPair(prev: String?, word: String): Boolean =
        prev != null && pairs[prev.lowercase()]?.contains(word.lowercase()) == true

    /** (prev2, prev, word) có trong bảng bộ ba nhạy cảm. = iOS isTriple. */
    fun isTriple(prev2: String?, prev: String?, word: String): Boolean =
        tripleGate(prev2, prev)?.contains(word.lowercase()) == true

    /** Chuỗi seed ba từ sau ([prev2], [prev]) — CHƯA lọc (người gọi lọc bằng [filter]). = iOS chain(after:prev2:). */
    fun chain(prev: String?, prev2: String?): List<String> =
        if (prev == null || prev2 == null) emptyList()
        else chains[prev2.lowercase() + " " + prev.lowercase()] ?: emptyList()

    private fun tripleGate(prev2: String?, prev: String?): Set<String>? =
        if (prev == null || prev2 == null) null else triples[prev2.lowercase() + " " + prev.lowercase()]

    val set: Set<String> = hashSetOf(
        "đcm", "đm", "dm", "dcm", "vcl", "vkl", "vl", "cl", "clgt", "cmnr",
        "cứt", "lồn", "cặc", "buồi", "đĩ", "điếm", "đụ", "địt",
        "tml", "sml", "dâm", "đkm", "dkm", "buscu",
        "đéo", "nứng", "chịch", "trym", "loz", "cmm", "cmn", "đmm", "dmm", "đcmm", "dcmm", "clm", "clg", "vcc", "dume",
        "cc", "đb", "lìn", "fuckboy",
        "fuck", "shit", "bitch", "wtf", "motherfucker", "asshole", "bullshit", "dick", "dickhead", "pussy",
        "bastard", "dumbass", "fucking", "fucked", "fucker", "shitty", "stfu",
    )

    // BEGIN GENERATED SensitivePairs — Scripts/gen-seed-data.py từ Scripts/seed-curated.txt [sensitive-bigram] / [trigram] / [sensitive-trigram]; KHÔNG sửa tay.
    val pairs: Map<String, Set<String>> = hashMapOf(
        "bú" to hashSetOf("cu"),
        "bố" to hashSetOf("mày"),
        "chó" to hashSetOf("chết", "má"),
        "chúa" to hashSetOf("phòng"),
        "chơi" to hashSetOf("cave", "gái"),
        "clip" to hashSetOf("nóng"),
        "cái" to hashSetOf("mâm"),
        "cò" to hashSetOf("hương"),
        "damn" to hashSetOf("it"),
        "fuck" to hashSetOf("boy"),
        "kích" to hashSetOf("dục"),
        "láo" to hashSetOf("chó"),
        "lùn" to hashSetOf("tịt"),
        "lộ" to hashSetOf("clip"),
        "massage" to hashSetOf("kích"),
        "má" to hashSetOf("mày"),
        "móc" to hashSetOf("lốp"),
        "mẹ" to hashSetOf("mày"),
        "như" to hashSetOf("cột"),
        "nâng" to hashSetOf("bi"),
        "não" to hashSetOf("phẳng"),
        "nện" to hashSetOf("nhau"),
        "phang" to hashSetOf("nhau"),
        "phim" to hashSetOf("heo"),
        "piss" to hashSetOf("off"),
        "quay" to hashSetOf("tay"),
        "rờ" to hashSetOf("cu"),
        "sờ" to hashSetOf("chim", "cu"),
        "thằng" to hashSetOf("chó", "khốn", "mặt", "ngu", "điên"),
        "vãi" to hashSetOf("đái"),
        "xoạc" to hashSetOf("nhau"),
        "óc" to hashSetOf("lợn"),
        "đù" to hashSetOf("má"),
        "đậu" to hashSetOf("má"),
        "đồ" to hashSetOf("chó", "khốn", "ngu", "điên"),
    )
    /** Chuỗi seed BA từ ("prev2 prev" → từ kế tiếp, nặng trước) — = iOS SensitiveWords.chains. */
    val chains: Map<String, List<String>> = hashMapOf(
        "bố mày" to listOf("đây"),
        "bố tiên" to listOf("sư"),
        "cha mày" to listOf("chứ"),
        "con đĩ" to listOf("mẹ"),
        "cái máu" to listOf("lồn"),
        "cút con" to listOf("mẹ"),
        "mả cha" to listOf("mày"),
        "mặt dày" to listOf("vãi"),
        "mặt lồn" to listOf("ra"),
        "mẹ kiếp" to listOf("mày"),
        "ngu như" to listOf("chó", "lợn"),
        "real hay" to listOf("fake"),
        "thằng ất" to listOf("ơ"),
        "tiên sư" to listOf("bố"),
        "tổ cha" to listOf("mày"),
        "vãi cả" to listOf("lồn", "chưởng"),
        "óc bã" to listOf("đậu"),
        "ông mày" to listOf("đây"),
        "đcm thằng" to listOf("này"),
        "đéo ai" to listOf("thèm"),
        "đéo hiểu" to listOf("sao"),
        "địt con" to listOf("mẹ"),
        "địt cụ" to listOf("mày"),
        "đồ chó" to listOf("má"),
        "đồ ăn" to listOf("hại"),
    )
    /** Bộ ba nhạy cảm ("prev2 prev" → từ): lọc bật ⇒ không gợi ý — = iOS SensitiveWords.triples. */
    val triples: Map<String, Set<String>> = hashMapOf(
        "bố mày" to hashSetOf("đây"),
        "bố tiên" to hashSetOf("sư"),
        "cha mày" to hashSetOf("chứ"),
        "con mất" to hashSetOf("dạy"),
        "con đĩ" to hashSetOf("mẹ"),
        "câm mồm" to hashSetOf("lại"),
        "cút con" to hashSetOf("mẹ"),
        "im mồm" to hashSetOf("đi"),
        "mả cha" to hashSetOf("mày"),
        "mặt dày" to hashSetOf("vãi"),
        "mặt lồn" to hashSetOf("ra"),
        "mẹ kiếp" to hashSetOf("mày"),
        "ngu như" to hashSetOf("bò", "chó", "lợn"),
        "thằng khốn" to hashSetOf("nạn"),
        "thằng mất" to hashSetOf("dạy"),
        "thằng ất" to hashSetOf("ơ"),
        "tiên sư" to hashSetOf("bố"),
        "tổ cha" to hashSetOf("mày"),
        "vcl thật" to hashSetOf("sự"),
        "óc bã" to hashSetOf("đậu"),
        "ông mày" to hashSetOf("đây"),
        "đcm thằng" to hashSetOf("này"),
        "đm cuộc" to hashSetOf("đời"),
        "đéo ai" to hashSetOf("thèm"),
        "đéo hiểu" to hashSetOf("sao"),
        "đéo quan" to hashSetOf("tâm"),
        "địt con" to hashSetOf("mẹ"),
        "địt cụ" to hashSetOf("mày"),
        "đồ con" to hashSetOf("lợn"),
        "đồ khốn" to hashSetOf("nạn"),
        "đồ mất" to hashSetOf("dạy"),
        "đồ ăn" to hashSetOf("hại"),
    )
    // END GENERATED SensitivePairs
}
