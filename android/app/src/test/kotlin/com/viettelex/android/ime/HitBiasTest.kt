package com.viettelex.android.ime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Ưu tiên phím ở mép chung (HitBias, Phil 06/10/2026) — song sinh iOS KeyHitBiasTests:
 * space thắng "," / "." kề trong dải 30% (gõ cuộn < 150 ms: 40%); tâm mọi phím không đổi.
 * 10/10/2026 (bug "bấm ⌫ hay thành m / l"): phím chữ KHÔNG còn lấn ⇧ / ⌫; khe quanh phím
 * chức năng thuộc nó (KeyLayout.gutterOwner) — xem backspaceAndShiftNeverStolenByLetters.
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
        for (b in listOf(HitBias.SPACE_BAND, HitBias.SPACE_BAND_ROLLING))
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

    /**
     * Mọi điểm trong hình ⇧ / ⌫ (lưới 7×7 sát mép) và khe cùng hàng cạnh nó ra ĐÚNG phím chức
     * năng — gõ chậm lẫn gõ cuộn (10 ms sau chữ), mọi bề ngang điện thoại dọc / ngang, có/không
     * hàng số. Lõi m / l / z / a (và 1 dp ngoài mép — khe Android chỉ 5 dp) vẫn ra chữ.
     */
    @Test fun backspaceAndShiftNeverStolenByLetters() {
        val fr = listOf(0.01f, 0.1f, 0.2f, 0.34f, 0.5f, 0.8f, 0.99f)
        for ((w, h) in listOf(360f to 218f, 390f to 218f, 412f to 230f, 430f to 230f, 800f to 160f, 915f to 170f)) {
            for (numberRow in listOf(false, true)) {
                val keys = KeyLayout.build(LayoutConfig(Plane.LETTERS, w, if (numberRow) h * 1.2f else h, d, numberRow = numberRow))
                val shift = keys.first { it.kind == KeyKind.SHIFT }
                val back = keys.first { it.kind == KeyKind.BACKSPACE }
                val m = keys.first { it.label == "m" }
                val z = keys.first { it.label == "z" }
                val tag = "w=$w numberRow=$numberRow"
                val backPts = ArrayList<Pair<Float, Float>>()
                val shiftPts = ArrayList<Pair<Float, Float>>()
                for (fx in fr) for (fy in fr) {
                    backPts += (back.left + fx * back.width) to (back.top + fy * back.height)
                    shiftPts += (shift.left + fx * shift.width) to (shift.top + fy * shift.height)
                }
                var x = m.right + 3.5f
                while (x < back.left) { backPts += x to back.centerY; x += 1f }
                x = z.left - 3.5f
                while (x > shift.right) { shiftPts += x to shift.centerY; x -= 1f }
                backPts += back.centerX to (back.top - 4.5f)            // khe trên ⌫ (dưới l)
                for (since in listOf(slow, 10L, 150L)) {
                    // yOffset 4 dp như KeyboardView (điểm chọn phím chữ dời lên).
                    for ((px, py) in backPts)
                        assertSame("$tag ⌫ tại ($px,$py) since=$since", back,
                            KeyLayout.hit(keys, Plane.LETTERS, px, py, 4f * d, d, since))
                    for ((px, py) in shiftPts)
                        assertSame("$tag ⇧ tại ($px,$py) since=$since", shift,
                            KeyLayout.hit(keys, Plane.LETTERS, px, py, 4f * d, d, since))
                }
                for (c in listOf("m", "l", "z", "a")) {
                    val k = keys.first { it.label == c }
                    assertSame("$tag lõi $c", k, KeyLayout.hit(keys, Plane.LETTERS, k.centerX, k.centerY, 4f * d, d, 10L))
                }
                assertSame("$tag 1dp phải m", m, KeyLayout.hit(keys, Plane.LETTERS, m.right + 1f, m.centerY, 4f * d, d, 10L))
                assertSame("$tag 1dp trái z", z, KeyLayout.hit(keys, Plane.LETTERS, z.left - 1f, z.centerY, 4f * d, d, 10L))
            }
        }
    }

    @Test fun gutterOwnerPure() {
        // Hình học iPhone 402 (song sinh iOS testSpecialKeyGutterPure).
        val back = LaidKey(KeyKind.BACKSPACE, "", "", "", 353f, 108f, 395.5f, 151f)
        val m = LaidKey(KeyKind.LETTER, "m", "M", "m", 308f, 108f, 341.3f, 151f)
        val l = LaidKey(KeyKind.LETTER, "l", "L", "l", 347.9f, 54f, 381.2f, 98f)
        val keys = listOf(m, l, back)
        val y = back.centerY
        assertSame(back, KeyLayout.gutterOwner(keys, 353.5f, y, d))
        assertSame(back, KeyLayout.gutterOwner(keys, 365f, 108.5f, d))   // đỉnh ⌫ dưới l
        assertSame(back, KeyLayout.gutterOwner(keys, 347f, y, d))        // khe m↔⌫
        assertSame(back, KeyLayout.gutterOwner(keys, 400f, y, d))        // mép màn hình
        assertSame(back, KeyLayout.gutterOwner(keys, 365f, 103f, d))     // khe trên ≤ 5.5
        assertEquals(null, KeyLayout.gutterOwner(keys, 343.5f, y, d))    // ≤ 3 dp sát m
        assertEquals(null, KeyLayout.gutterOwner(keys, m.centerX, y, d)) // lõi m
        assertEquals(null, KeyLayout.gutterOwner(keys, 365f, 100f, d))   // khe trên, nửa của l
        assertEquals(null, KeyLayout.gutterOwner(keys, back.right + 17f, y, d))
    }
}
