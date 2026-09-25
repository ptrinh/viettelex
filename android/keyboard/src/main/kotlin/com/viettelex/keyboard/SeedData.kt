package com.viettelex.keyboard

/**
 * Seed ban đầu cho UserLangModel (GENERATED — assets/seed.tsv, xuất từ iOS SeedData.swift).
 * Chỉ parse khi thật sự seed (store trống); không găm trong RAM.
 */
object SeedData {
    class Seed(val unigrams: Map<String, Int>, val bigrams: List<Triple<String, String, Int>>)

    /** Parse mỗi lần gọi — gọi hiếm (seed), kết quả không cache. */
    fun load(): Seed = parse(KeyboardData.text(Keys.ASSET_SEED))

    fun parse(tsv: String): Seed {
        val uni = LinkedHashMap<String, Int>(1024)
        val bi = ArrayList<Triple<String, String, Int>>(512)
        for (line in tsv.lineSequence()) {
            if (line.isEmpty()) continue
            val p = line.split('\t')
            when (p[0]) {
                "u" -> uni[p[1]] = p[2].toInt()
                "b" -> bi.add(Triple(p[1], p[2], p[3].toInt()))
            }
        }
        return Seed(uni, bi)
    }

    val unigrams: Map<String, Int> get() = load().unigrams
    val bigrams: List<Triple<String, String, Int>> get() = load().bigrams
}
