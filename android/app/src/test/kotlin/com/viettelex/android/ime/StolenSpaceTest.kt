package com.viettelex.android.ime

import com.viettelex.keyboard.Key
import com.viettelex.keyboard.SpaceSideKey
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Test

/**
 * Issue #145 (Android 1.5.22, "Phím cạnh dấu cách" = Cả hai): gõ nhanh, chạm "," (trái space)
 * thỉnh thoảng ra ".". Đường lỗi: chạm "," < 150 ms sau một chữ rơi vào dải mép 40 % mà
 * [HitBias] giao cho space ⇒ ra dấu cách; dấu cách thật ngay sau (< 350 ms) ⇒ double-space
 * ⇒ ". ". Sửa: space đôi mà lần đầu là chạm trong khung "," ⇒ "<,> " ([StolenSpace]).
 */
class StolenSpaceTest {
    private val d = 1f
    private val keys = KeyLayout.build(LayoutConfig(Plane.LETTERS, 390f, 218f, d, spaceSideKey = SpaceSideKey.BOTH))
    private val space = keys.first { it.kind == KeyKind.SPACE }
    private val comma = keys.first { it.kind == KeyKind.PUNCT && it.label == "," }
    private val dot = keys.first { it.kind == KeyKind.PUNCT && it.label == "." }
    private val dbl = 350L

    private fun hit(x: Float, y: Float, since: Long) = KeyLayout.hit(keys, Plane.LETTERS, x, y, 0f, d, since)!!

    @Test fun reproducesCommaTapBecomingSpaceThenPeriod() {
        // Bố cục Cả hai: [?123][😊][,][space][.][↵].
        assertEquals(true, comma.right <= space.left && dot.left >= space.right)
        // Chạm TRONG khung "," (mép phải, 35 % bề rộng), 100 ms sau một chữ ⇒ router chọn space.
        val x = comma.right - 0.35f * comma.width
        val y = comma.centerY
        val k = hit(x, y, since = 100)
        assertSame(space, k)
        assertEquals(",", StolenSpace.punct(keys, k, x, y))
        // Hành vi cũ: space kế trong < 350 ms ⇒ DoubleSpacePeriod ⇒ "chữ. " (lỗi #145).
        assertEquals(Key.DoubleSpacePeriod, StolenSpace.key(200, dbl, pad = false, prevStolen = null))
        // Sửa: biết space trước là "," bị lấy ⇒ "chữ, ".
        assertEquals(Key.DoubleSpacePunct(","), StolenSpace.key(200, dbl, pad = false, prevStolen = ","))
    }

    @Test fun periodSideAlsoTracked() {
        val x = dot.left + 0.35f * dot.width
        val k = hit(x, dot.centerY, since = 100)
        assertSame(space, k)
        assertEquals(".", StolenSpace.punct(keys, k, x, dot.centerY))
    }

    @Test fun realSpaceOrGapIsNotStolen() {
        assertNull(StolenSpace.punct(keys, space, space.centerX, space.centerY))
        val gapX = (comma.right + space.left) / 2
        assertNull(StolenSpace.punct(keys, hit(gapX, space.centerY, 100), gapX, space.centerY))
        // Chạm đúng tâm "," ⇒ ","; không phải space ⇒ null.
        val c = hit(comma.centerX, comma.centerY, 100)
        assertSame(comma, c)
        assertNull(StolenSpace.punct(keys, c, comma.centerX, comma.centerY))
    }

    @Test fun keyDecisionTable() {
        assertEquals(Key.Space, StolenSpace.key(400, dbl, false, ","))       // chậm ⇒ space thường
        assertEquals(Key.Space, StolenSpace.key(350, dbl, false, null))
        assertEquals(Key.Space, StolenSpace.key(100, dbl, true, ","))        // bàn số: luôn literal
        assertEquals(Key.DoubleSpacePeriod, StolenSpace.key(100, dbl, false, null))
        assertEquals(Key.DoubleSpacePunct("."), StolenSpace.key(100, dbl, false, "."))
    }
}
