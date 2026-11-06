package com.viettelex.android.ime

import com.viettelex.keyboard.CommaPopup
import com.viettelex.keyboard.DomainPopup
import com.viettelex.keyboard.SpaceSideKey
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Issue #154 (Android 1.5.27): giữ "," cạnh space ra 10 dấu câu nhưng trượt chỉ chọn được 4 ô
 * đầu. Gốc: chọn ô theo ĐỘ DỜI từ chỗ mở; hàng bị kẹp mép (ô "." đầu lệch xa khỏi phím) ⇒ ô xa
 * cần ngón ra ngoài màn hình. Dựng hàng đáy THẬT (KeyLayout) ở mọi "Phím cạnh dấu cách", vài bề
 * ngang điện thoại + một tay, rồi trượt từ tâm phím tới tâm từng ô như [KeyboardView.firePopover].
 */
class CommaPopoverReachTest {
    private val d = 1f
    private val H = 218f
    private val panelH = 46f
    /** Đỉnh phím hàng đáy trong overlay: strip 42 dp phía trên, như máy thật (đủ chỗ hai hàng). */
    private val off = 42f

    private fun popKeys(w: Float, side: SpaceSideKey, oneHand: OneHandSide = OneHandSide.OFF) =
        KeyLayout.build(LayoutConfig(Plane.LETTERS, w, H, d, spaceSideKey = side, oneHand = oneHand))
            .filter { it.kind == KeyKind.PUNCT && (it.label == "," || (it.label == "." && side == SpaceSideKey.PERIOD)) }

    private fun layoutFor(k: LaidKey, w: Float, n: Int): Pair<DomainPopup.Layout, Float> {
        val keyTop = k.top + off
        val l = DomainPopup.layout(k.centerX, CommaPopup.itemWidthDp(false), n, w, rowHeight = panelH,
            maxRows = if (keyTop - 8f - 2 * panelH >= 0f) 2 else 1)
        return l to maxOf(keyTop - 8f - panelH * l.rows, 0f)
    }

    /**
     * Mở popup ở tâm phím rồi quét ngón ngang từng dp trên mỗi hàng (trong màn hình, chừa 1 dp
     * mép) — tập ô chọn được phải đủ mọi ô.
     */
    private fun reachable(k: LaidKey, w: Float, choices: List<String>): Set<Int> {
        val (l, popTop) = layoutFor(k, w, choices.size)
        val h = DomainPopup.Hold(choices)
        assertTrue(h.open(l, popTop, k.bottom + off, k.centerX, k.centerY + off))
        assertEquals("giữ rồi nhả tại chỗ ⇒ ô chọn sẵn", CommaPopup.PRESELECT, h.selection)
        val got = HashSet<Int>()
        for (r in 0 until l.rows) {
            val cy = popTop + (l.rows - 1 - r) * panelH + panelH / 2
            var x = 1f
            while (x <= w - 1f) { h.move(x, cy); h.selection?.let { got += it }; x += 1f }
        }
        return got
    }

    @Test fun everyPunctuationCellReachable() {
        for (w in listOf(320f, 360f, 393f, 412f, 480f))
            for (side in listOf(SpaceSideKey.COMMA, SpaceSideKey.PERIOD, SpaceSideKey.BOTH))
                for (hand in listOf(OneHandSide.OFF, OneHandSide.LEFT, OneHandSide.RIGHT)) {
                    val keys = popKeys(w, side, hand)
                    assertTrue("$w $side $hand", keys.isNotEmpty())
                    for (k in keys) {
                        val choices = CommaPopup.choices(k.label, lettersPlane = true, periodKey = side == SpaceSideKey.PERIOD)
                        assertEquals("w=$w $side $hand phím \"${k.label}\"", choices.indices.toSet(), reachable(k, w, choices))
                    }
                }
    }

    /** "Cả hai": "," bên TRÁI space — trước fix chỉ với tới ô 0…3 ⇒ giờ hai hàng loe sang phải từ phím. */
    @Test fun leftCommaWrapsIntoTwoRowsAboveKey() {
        val k = popKeys(390f, SpaceSideKey.BOTH).first { it.label == "," }
        val l = layoutFor(k, 390f, CommaPopup.choices.size).first
        assertEquals(2, l.rows)
        assertEquals(5, l.perRow)
        assertTrue("ô \".\" ngay trên phím", l.slotMinX(0) <= k.centerX && k.centerX <= l.slotMinX(0) + l.itemWidth)
        assertEquals("ô 5 ngay trên ô 0", l.slotMinX(0), l.slotMinX(5), 0.001f)
    }

    /** "," bên phải space, máy rộng (≥ 393 dp): một hàng vừa, ô đầu vẫn trên phím ⇒ như cũ. */
    @Test fun rightCommaStaysOneRowWhenItFits() {
        for (w in listOf(393f, 412f)) {
            val k = popKeys(w, SpaceSideKey.COMMA).single()
            val l = layoutFor(k, w, CommaPopup.choices.size).first
            assertEquals("$w", 1, l.rows)
            assertTrue(l.mirrored)
        }
    }
}
