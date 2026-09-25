package com.viettelex.keyboard

/** Đệm thanh gợi ý cho đủ 3 (port iOS SuggestionFill). */
object SuggestionFill {
    fun pad(base: List<String>, with: List<String>, need: Int, excluding: String = ""): List<String> {
        if (base.size >= need) return base.take(need)
        val out = base.toMutableList()
        val seen = base.mapTo(HashSet()) { it.lowercase() }
        if (excluding.isNotEmpty()) seen.add(excluding.lowercase())
        for (c in with) {
            if (out.size >= need) break
            if (seen.add(c.lowercase())) out.add(c)
        }
        return out
    }
}

object TypingHeuristics {
    /** Double-space → ". " (hành vi Apple): trước space là chữ/số, không phải dấu câu. */
    fun doubleSpaceMakesPeriod(context: String, lastWasSpace: Boolean): Boolean {
        if (!lastWasSpace || !context.endsWith(" ")) return false
        val rest = context.dropLast(1)
        val prev = Cp.lastCodePoint(rest) ?: return false
        return !Character.isWhitespace(prev) && prev != '.'.code && prev != '!'.code &&
            prev != '?'.code && prev != ','.code
    }
}

/** Nhịp thời gian iOS (giây) cho IME. */
object TypingTimings {
    const val DOUBLE_SPACE_S = 0.35
    const val SUGGESTION_DEBOUNCE_MS = 30L
    const val SHIFT_DOUBLE_TAP_S = 0.3
    const val BACKSPACE_REPEAT_DELAY_S = 0.5
    const val BACKSPACE_REPEAT_INTERVAL_S = 0.09
    const val BACKSPACE_DOUBLE_AFTER_S = 1.6
    const val BACKSPACE_WORD_AFTER_S = 3.0
    const val BACKSPACE_WORD_EVERY_NTH_TICK = 4
    const val SPACE_TRACKPAD_HOLD_S = 0.4
    const val TRACKPAD_DP_PER_CHAR = 9f
    const val USERLM_SAVE_COALESCE_MS = 5000L
}
