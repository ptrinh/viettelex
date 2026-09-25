package com.viettelex.keyboard

/** Lọc từ tục khỏi THANH GỢI Ý (vẫn học). Emoji không bị lọc. */
object SensitiveWords {
    fun filter(words: List<String>, enabled: Boolean): List<String> =
        if (enabled) words.filter { it.lowercase() !in set } else words

    val set: Set<String> = hashSetOf(
        "đcm", "đm", "dm", "dcm", "vcl", "vkl", "vl", "cl", "clgt", "cmnr",
        "cứt", "lồn", "cặc", "buồi", "đĩ", "điếm", "đụ", "địt",
        "tml", "sml", "dâm",
        "fuck", "shit", "bitch", "wtf",
    )
}
