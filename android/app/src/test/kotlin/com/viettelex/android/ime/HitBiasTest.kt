package com.viettelex.android.ime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Ưu tiên phím ở mép chung (HitBias, Phil 06/10/2026) — song sinh iOS KeyHitBiasTests:
 * space thắng "," / "." kề trong dải 30% (gõ cuộn < 150 ms: 40%); chữ thắng ⇧ / ⌫ kề
 * trong dải 20% (gõ nhanh < 200 ms: 35%); tâm mọi phím không đổi.
 */
class HitBiasTest {
    private val d = 1f
    private val W = 390f
    private val H = 218f
    private val slow = Long.MAX_VALUE

    private fun build(plane: Plane = Plane.LETTERS, period: Boolean = false) =
        KeyLayout.build(LayoutConfig(plane, W, H, d, periodKey = period))

    private fun hit(keys: List<LaidKey>, x: Float, y: Float, since: Long = slow, plane: Plane = Plane.LETTERS) =
        KeyLayout.hit(keys, plane, x, y, 0f, d, since)

    @Test fun bandTables() {
        assertEquals(0.30f, HitBias.spaceBand(slow))
        assertEquals(0.40f, HitBias.spaceBand(100))
        assertEquals(0.30f, HitBias.spaceBand(150))
        assertEquals(0.30f, HitBias.spaceBand(-5))
        assertEquals(0.20f, HitBias.letterBand(slow))
        assertEquals(0.35f, HitBias.letterBand(199))
        assertEquals(0.20f, HitBias.letterBand(200))
        for (b in listOf(HitBias.SPACE_BAND, HitBias.SPACE_BAND_ROLLING, HitBias.LETTER_BAND, HitBias.LETTER_BAND_ROLLING))
            assertTrue(b < 0.5f)
    }

    @Test fun keyCentersUnchanged() {
        for (period in listOf(false, true)) {
            val keys = build(period = period)
            for (k in keys) assertSame(k.label + k.kind, k, hit(keys, k.centerX, k.centerY, since = 50))
        }
    }

    @Test fun spaceWinsNearCommaBoundary() {
        val keys = build(period = true)
        val space = keys.first { it.kind == KeyKind.SPACE }
        val comma = keys.first { it.kind == KeyKind.PUNCT && it.label == "," }
        val dot = keys.first { it.kind == KeyKind.PUNCT && it.label == "." }
        val y = comma.centerY
        val w = comma.width
        // (x, since, mong đợi)
        val table = listOf(
            Triple((space.right + comma.left) / 2 + 0.5f, slow, space),   // khe, phía ","
            Triple(comma.left + 0.5f, slow, space),
            Triple(comma.left + 0.29f * w, slow, space),
            Triple(comma.left + 0.31f * w, slow, comma),
            Triple(comma.left + 0.38f * w, 100L, space),                   // gõ cuộn
            Triple(comma.left + 0.38f * w, 300L, comma),
            Triple(comma.left + 0.42f * w, 100L, comma),
            Triple(comma.right - 1f, 50L, comma),
            Triple(dot.left + 1f, 50L, dot),                               // "." không kề space
        )
        for ((x, since, want) in table) assertSame("x=$x since=$since", want, hit(keys, x, y, since))
    }

    @Test fun spaceWinsOverPeriodLeftOrRight() {
        // Plane số: [ABC][,][😊][space][.][↵] — "." BÊN PHẢI space.
        val keys = build(Plane.NUMBERS)
        val space = keys.first { it.kind == KeyKind.SPACE }
        val dot = keys.first { it.kind == KeyKind.PUNCT && it.label == "." }
        assertSame(space, hit(keys, dot.left + 0.2f * dot.width, dot.centerY, plane = Plane.NUMBERS))
        assertSame(dot, hit(keys, dot.centerX, dot.centerY, plane = Plane.NUMBERS))
        // Pure: "," bên TRÁI space cũng đúng chiều.
        val l = LaidKey(KeyKind.PUNCT, ",", ",", ",", 60f, 0f, 90f, 40f)
        val s = LaidKey(KeyKind.SPACE, "", "", " ", 95f, 0f, 300f, 40f)
        assertTrue(HitBias.intrudes(85f, 20f, l, s, 0.3f, 16f))
        assertFalse(HitBias.intrudes(75f, 20f, l, s, 0.3f, 16f))
        assertFalse(HitBias.intrudes(85f, 20f, l, s, 0.3f, 4f))       // khe > maxGap: không kề
    }

    @Test fun lettersWinNearShiftAndBackspace() {
        val keys = build()
        val shift = keys.first { it.kind == KeyKind.SHIFT }
        val back = keys.first { it.kind == KeyKind.BACKSPACE }
        val z = keys.first { it.label == "z" }
        val m = keys.first { it.label == "m" }
        val a = keys.first { it.label == "a" }
        val y = shift.centerY
        val sw = shift.width
        val table = listOf(
            Triple(shift.right - 0.1f * sw to y, slow, z),
            Triple(shift.right - 0.25f * sw to y, slow, shift),
            Triple(shift.right - 0.25f * sw to y, 100L, z),               // gõ nhanh
            Triple(shift.right - 0.4f * sw to y, 100L, shift),
            Triple(shift.centerX to y, 10L, shift),                        // tâm ⇧ luôn ⇧
            Triple(back.left + 0.1f * back.width to back.centerY, slow, m),
            Triple(back.left + 0.3f * back.width to back.centerY, slow, back),
            Triple(back.left + 0.3f * back.width to back.centerY, 100L, m),
            Triple(back.centerX to back.centerY, 10L, back),
        )
        for ((p, since, want) in table)
            assertSame("p=$p since=$since", want, hit(keys, p.first, p.second, since))
        // Đỉnh ⇧ ngay dưới "a" (trong khoảng x của a, xa mép z) ⇒ a; thấp hơn dải ⇒ ⇧.
        val ax = maxOf(a.left, shift.left) + 1f
        assertTrue(ax < shift.right - 0.25f * sw)
        assertSame(a, hit(keys, ax, shift.top + 0.1f * shift.height))
        assertSame(shift, hit(keys, ax, shift.top + 0.3f * shift.height))
    }
}
