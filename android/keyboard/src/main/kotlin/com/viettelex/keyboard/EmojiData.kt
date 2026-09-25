package com.viettelex.keyboard

/** Emoji theo 8 category chuẩn Apple cho emoji plane (assets/emojidata.tsv, lazy). */
object EmojiData {
    data class Category(val name: String, val emoji: List<String>)

    /** Đúng thứ tự stock: smileys → flags (cờ 🇻🇳 đầu). */
    val categories: List<Category> by lazy {
        KeyboardData.text(Keys.ASSET_EMOJI_DATA).lineSequence().filter { it.isNotBlank() }.map { line ->
            val tab = line.indexOf('\t')
            Category(line.substring(0, tab), line.substring(tab + 1).split(' ').filter { it.isNotEmpty() })
        }.toList()
    }

    const val RECENTS = "recents"

    /** Tên hiển thị tiêu đề section. */
    val displayNames: Map<String, String> = mapOf(
        "recents" to "THƯỜNG DÙNG", "smileys" to "MẶT CƯỜI & NGƯỜI",
        "animals" to "ĐỘNG VẬT & THIÊN NHIÊN", "food" to "ĐỒ ĂN & ĐỒ UỐNG",
        "activity" to "HOẠT ĐỘNG", "travel" to "DU LỊCH & ĐỊA ĐIỂM",
        "objects" to "ĐỒ VẬT", "symbols" to "BIỂU TƯỢNG", "flags" to "CỜ",
    )
    fun displayName(name: String): String = displayNames[name] ?: name.uppercase()

    /** SF Symbol iOS cho 9 icon category (recents trước) — IME map sang vector riêng. */
    val categoryIcons = listOf("clock", "face.smiling", "hare", "fork.knife", "soccerball",
        "car.fill", "lightbulb", "heart", "flag")

    // Emoji_Modifier_Base (Unicode 15.1, sinh từ JDK Character.isEmojiModifierBase).
    private val modifierBaseRanges = intArrayOf(
        0x261D, 0x261D, 0x26F9, 0x26F9, 0x270A, 0x270D, 0x1F385, 0x1F385, 0x1F3C2, 0x1F3C4,
        0x1F3C7, 0x1F3C7, 0x1F3CA, 0x1F3CC, 0x1F442, 0x1F443, 0x1F446, 0x1F450, 0x1F466, 0x1F478,
        0x1F47C, 0x1F47C, 0x1F481, 0x1F483, 0x1F485, 0x1F487, 0x1F48F, 0x1F48F, 0x1F491, 0x1F491,
        0x1F4AA, 0x1F4AA, 0x1F574, 0x1F575, 0x1F57A, 0x1F57A, 0x1F590, 0x1F590, 0x1F595, 0x1F596,
        0x1F645, 0x1F647, 0x1F64B, 0x1F64F, 0x1F6A3, 0x1F6A3, 0x1F6B4, 0x1F6B6, 0x1F6C0, 0x1F6C0,
        0x1F6CC, 0x1F6CC, 0x1F90C, 0x1F90C, 0x1F90F, 0x1F90F, 0x1F918, 0x1F91F, 0x1F926, 0x1F926,
        0x1F930, 0x1F939, 0x1F93C, 0x1F93E, 0x1F977, 0x1F977, 0x1F9B5, 0x1F9B6, 0x1F9B8, 0x1F9B9,
        0x1F9BB, 0x1F9BB, 0x1F9CD, 0x1F9CF, 0x1F9D1, 0x1F9DD, 0x1FAC3, 0x1FAC5, 0x1FAF0, 0x1FAF8,
    )

    fun isModifierBase(cp: Int): Boolean {
        var i = 0
        while (i < modifierBaseRanges.size) {
            if (cp < modifierBaseRanges[i]) return false
            if (cp <= modifierBaseRanges[i + 1]) return true
            i += 2
        }
        return false
    }

    /** [gốc + 5 tông da] nếu có modifier base; tông áp cho MỌI base trong ZWJ. */
    fun toneVariants(e: String): List<String>? {
        val cps = e.codePoints().toArray()
        if (cps.none(::isModifierBase)) return null
        val out = ArrayList<String>(6)
        out.add(e)
        for (t in 0x1F3FB..0x1F3FF) {
            val sb = StringBuilder()
            for (c in cps) {
                if (c in 0x1F3FB..0x1F3FF) continue
                sb.appendCodePoint(c)
                if (isModifierBase(c)) sb.appendCodePoint(t)
            }
            out.add(sb.toString())
        }
        return out
    }
}

/** Recents emoji (tối đa 30, mới nhất đầu) — lưu pref [Keys.EMOJI_RECENTS]. */
object EmojiRecents {
    const val MAX = 30
    fun noteUsed(recents: List<String>, e: String): List<String> {
        val r = ArrayList<String>(recents.size + 1)
        r.add(e)
        for (x in recents) if (x != e) r.add(x)
        return if (r.size > MAX) r.subList(0, MAX).toList() else r
    }
    fun encode(list: List<String>): String = list.joinToString("\n")
    fun decode(s: String?): List<String> = s?.split('\n')?.filter { it.isNotEmpty() } ?: emptyList()
}
