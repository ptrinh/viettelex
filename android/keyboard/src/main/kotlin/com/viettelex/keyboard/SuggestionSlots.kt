package com.viettelex.keyboard

/**
 * Thứ tự ưu tiên các loại chip tranh slot trên thanh gợi ý — THUẦN, song sinh
 * iOS/Keyboard/SuggestionSlots.swift, cùng bảng ca kiểm (SuggestionSlotsTests). Tài liệu:
 * iOS/docs/IOS-SUGGESTIONS.md mục "Thứ tự ưu tiên slot".
 *
 * Từ cao xuống thấp (tầng trên thắng / đè tầng dưới):
 *  1. **Hoàn tác một lượt** — "↩︎ Khôi phục" (vuốt ⌫; Android là pill riêng của StripView,
 *     đè mọi thứ), "↩︎ Hoàn tác" công cụ văn bản (cùng pill), "↩︎ Hoàn tác" thêm dấu
 *     ([SuggestionSet.UNDO_TONES_TOKEN]). Android: một pill giữa bar ([BarLayout.Pill]);
 *     iOS: slot đầu, gợi ý dời phải.
 *  2. **Clipboard vừa copy** — tối đa 2 chip tách STK/SĐT/OTP + ô "Dán" nguyên văn
 *     ([BarLayout.Chips]) thắng thẻ Dán ([BarLayout.PasteCard]); cả hai thay cả bar.
 *  3. **"Thêm dấu"** ([SuggestionSet.ADD_TONES_TOKEN]) — slot đầu, nhường clipboard.
 *  4. **Chip số** — slot 1 (GIỮA khi 3 ô); nội dung từ đó dời phải một ô (ô cuối là vùng
 *     emoji thì vẫn là emoji). **Kết quả phép tính** "…=" ([MathResults]) — slot ĐẦU như bàn phím
 *     gốc, mọi chip khác dời phải một ô.
 *  5. **Chữ** — nguyên văn / ứng viên (chip gõ tắt nằm ở ứng viên chính) / emoji, hoặc từ
 *     kế tiếp (bigram, email/TLD, biến thể gõ vuốt).
 */
data class BarChip(val label: String, val payload: String)

sealed class BarLayout {
    /** Một pill giữa bar (Android: hoàn tác thêm dấu — cùng kiểu ô Khôi phục). */
    data class Pill(val chip: BarChip) : BarLayout()
    /** Chip chia đều bar (clipboard). */
    data class Chips(val chips: List<BarChip>) : BarLayout()
    /** Thẻ Dán thay cả bar. */
    object PasteCard : BarLayout()
    /** `count` slot trái→phải + emoji (chiếm vùng slot CUỐI, slots[count-1] khi đó = null). */
    data class Slots(val slots: List<BarChip?>, val emojis: List<String>) : BarLayout()
}

object SuggestionSlots {
    /** Số emoji tối đa trong vùng emoji (ô cuối): 3 khi ≤ 3 ô; ô hẹp hơn (4–5 ô) ⇒ 2. */
    fun maxEmojis(count: Int): Int = if (count <= 3) 3 else 2

    /**
     * Thứ tự ô cho từ kế tiếp (hạng 0, 1, 2…). [bestInMiddle] (Android/Gboard): hạng 0 ở ô GIỮA
     * ((count−1)/2), rồi xen kẽ trái/phải ra ngoài — 3 ô: [1, 0, 2]; 5 ô: [2, 1, 3, 0, 4]. iOS: trái→phải.
     */
    fun nextOrder(count: Int, bestInMiddle: Boolean): List<Int> {
        if (!bestInMiddle || count <= 1) return (0 until maxOf(count, 0)).toList()
        val c = (count - 1) / 2
        val order = arrayListOf(c)
        var d = 1
        while (order.size < count) {
            if (c - d >= 0) order += c - d
            if (c + d < count) order += c + d
            d++
        }
        return order
    }

    /**
     * Ô "chính" (tô đậm): từ kế tiếp + [bestInMiddle] ⇒ ô giữa; còn lại ô ngay sau nguyên văn /
     * chip dẫn đầu (1); 1 ô ⇒ 0. 3 ô ⇒ luôn 1 như trước.
     */
    fun primaryIndex(count: Int, nextWords: Boolean, bestInMiddle: Boolean): Int = when {
        count <= 1 -> 0
        nextWords && bestInMiddle -> (count - 1) / 2
        else -> 1
    }

    /**
     * @param undo ô hoàn tác do view giữ (iOS: restoreLabel); Android truyền null vì ô
     *   Khôi phục / Hoàn tác công cụ là pill riêng vẽ đè (vẫn là tầng 1).
     * @param undoAsPill Android true (pill), iOS false (slot đầu).
     * @param bestInMiddle từ kế tiếp tốt nhất ở GIỮA (Android/Gboard) hay trái (iOS).
     * @param pasteLabel nhãn ô "Dán" thêm sau chip clipboard.
     * @param count số ô ([SuggestionCount.fit], 1…5; mặc định 3 — hành vi cũ). Tổng quát hoá:
     *   đang gõ: ô 0 nguyên văn, ô 1 ứng viên chính, rồi word2, moreWords… theo thứ tự đọc; có
     *   emoji (count ≥ 3) ⇒ ô CUỐI là vùng emoji; count = 1 ⇒ chỉ ứng viên chính (không có thì
     *   nguyên văn). Từ kế tiếp: [nextOrder]. Chip dẫn đầu ô 0, chữ dời phải. Chip số chèn ô 1
     *   (count = 1: ô 0), phần sau dời phải; kết quả phép tính chèn ô 0.
     */
    fun arrange(set: SuggestionSet, undo: BarChip? = null, undoAsPill: Boolean,
                bestInMiddle: Boolean, pasteLabel: String = "Dán",
                count: Int = SuggestionCount.AUTO_SLOTS): BarLayout {
        val n = count.coerceIn(1, SuggestionCount.MAX)
        val action = if (set.action != null && set.actionLabel != null) BarChip(set.actionLabel, set.action) else null
        // 1. hoàn tác một lượt
        val u = undo ?: action?.takeIf { it.payload == SuggestionSet.UNDO_TONES_TOKEN }
        if (u != null && undoAsPill) return BarLayout.Pill(u)
        // 2. clipboard
        if (u == null && set.clipChips.isNotEmpty()) {
            val chips = set.clipChips.take(2).map { BarChip(it.label, SuggestionSet.CLIP_CHIP_PREFIX + it.value) }.toMutableList()
            if (set.paste && chips.size < 3) chips += BarChip(pasteLabel, SuggestionSet.PASTE_TOKEN)
            return BarLayout.Chips(chips)
        }
        if (u == null && set.paste) return BarLayout.PasteCard
        // 5. chữ
        var slots = arrayOfNulls<BarChip>(n).toMutableList()
        val emojis = if (set.nextWords.isEmpty() && n >= 3) set.emojis.take(maxEmojis(n)) else emptyList()
        if (set.nextWords.isNotEmpty()) {
            nextOrder(n, bestInMiddle).zip(set.nextWords).forEach { (i, w) -> slots[i] = BarChip(w, w) }
        } else if (n == 1) {
            (set.word ?: set.literal)?.let { slots[0] = BarChip(it, it) }
        } else {
            set.literal?.let { slots[0] = BarChip(it, it) }
            // ứng viên theo vị trí (word, word2, moreWords…) vào ô 1…; ô cuối nhường emoji
            val words = listOf(set.word, set.word2) + set.moreWords
            val room = n - 1 - (if (emojis.isEmpty()) 0 else 1)
            words.take(room).forEachIndexed { i, w -> slots[1 + i] = w?.let { BarChip(it, it) } }
        }
        // 1 (slot) / 3. hoàn tác (iOS), "Thêm dấu", "↩︎ từ cũ" (vuốt vừa sửa từ trước) hoặc
        // "↩︎ chữ gốc" (vừa tự sửa) chiếm slot đầu, chữ dời phải theo thứ tự đọc.
        val lead = u ?: action?.takeIf { it.payload == SuggestionSet.ADD_TONES_TOKEN || it.payload == SuggestionSet.UNDO_REVISE_TOKEN ||
            it.payload == SuggestionSet.UNDO_AUTOCORRECT_TOKEN || it.payload == SuggestionSet.RETRO_OFFER_TOKEN ||
            it.payload == SuggestionSet.UNDO_RETRO_TOKEN }
        if (lead != null) {
            val words = if (set.nextWords.isNotEmpty())
                set.nextWords.take(n).map { BarChip(it, it) } else slots.filterNotNull()
            slots = (listOf<BarChip?>(lead) + (0 until n - 1).map { words.getOrNull(it) }).toMutableList()
        }
        // 4. chip số: ô 1 (giữa khi 3 ô); phần sau dời phải.
        set.number?.let { insert(slots, BarChip(it, SuggestionSet.NUMBER_TOKEN), minOf(1, n - 1)) }
        // 4. kết quả phép tính: slot đầu; còn lại dời phải.
        set.math?.let { insert(slots, BarChip(it, SuggestionSet.MATH_TOKEN), 0) }
        if (emojis.isNotEmpty()) slots[n - 1] = null
        return BarLayout.Slots(slots.toList(), emojis)
    }

    /** Chèn [chip] ở ô [i], các ô sau dời phải một ô (ô cuối rơi ra), giữ nguyên số ô. */
    private fun insert(slots: MutableList<BarChip?>, chip: BarChip, i: Int) {
        slots.add(i, chip)
        slots.removeAt(slots.size - 1)
    }
}

/**
 * Chạm slot gợi ý: chốt payload lúc CHẠM XUỐNG. Gợi ý nền (VNSuggest) có thể về giữa
 * down và up và thay nội dung ô — đọc payload lúc nhấc tay từng chèn từ MỚI thay vì từ
 * người dùng nhắm (bug 27/09). Song sinh iOS KeyboardView (slot touchDown).
 */
class SlotTapLatch {
    private var payload: String? = null
    fun down(p: String?) { payload = p }
    /** Payload chốt lúc down (null = không có / đã huỷ); dùng một lần. */
    fun up(): String? = payload.also { payload = null }
    fun cancel() { payload = null }
}
