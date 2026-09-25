package com.viettelex.android.ime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class KeyLayoutTest {
    private val d = 1f   // dp = px
    private val W = 390f
    private val H = 218f

    private fun build(plane: Plane, kind: InputKind = InputKind.NORMAL, globe: Boolean = false, tablet: Boolean = false,
                      ret: String = "return") =
        KeyLayout.build(LayoutConfig(plane, W, H, d, kind, globe, tablet, ret))

    private fun near(a: Float, b: Float, eps: Float = 0.01f) = assertEquals(b, a, eps)

    @Test fun heights() {
        // Gboard: 4 hàng × 56 dp dọc, 42 ngang
        near(KeyLayout.keyAreaDp(false, false, 0), 224f)
        near(KeyLayout.keyAreaDp(false, true, 0), 168f)
        near(KeyLayout.keyAreaDp(true, false, 0), 256f)
        near(KeyLayout.keyAreaDp(true, true, 0), 300f)
        near(KeyLayout.keyAreaDp(false, false, 10), 264f)
        near(KeyLayout.keyAreaDp(false, false, -99), 184f)       // kẹp −10
        near(KeyLayout.stripDp(true, false), 34f)
        near(KeyLayout.stripDp(true, true), 14f)
        near(KeyLayout.stripDp(false, false), 0f)
    }

    @Test fun lettersRowsAndIndent() {
        val keys = build(Plane.LETTERS)
        val row1 = keys.filter { it.kind == KeyKind.LETTER && it.label in "qwertyuiop" }
        val row2 = keys.filter { it.kind == KeyKind.LETTER && it.label in "asdfghjkl" }
        assertEquals(10, row1.size); assertEquals(9, row2.size)
        // phím chữ hàng 1 và hàng 2 cùng bề rộng (thụt 0.5 phím mỗi bên)
        near(row1[0].width, row2[0].width)
        near(row1[0].left, 3f)
        near(row2[0].left, 3f + (row1[0].width + KeyLayout.KEY_SPACING) / 2)
        near(row1.last().right, W - 3f)
        // khe giữa phím (Gboard 5 dp)
        near(row1[1].left - row1[0].right, KeyLayout.KEY_SPACING)
        // hàng 54.5 cao: margin 5 trên/dưới
        near(row1[0].top, 5f); near(row1[0].bottom, H / 4 - 5f)
    }

    @Test fun thirdRowShiftBackspaceAreOneAndHalfKeys() {
        val keys = build(Plane.LETTERS)
        val shift = keys.first { it.kind == KeyKind.SHIFT }
        val back = keys.first { it.kind == KeyKind.BACKSPACE }
        val z = keys.first { it.label == "z" }
        near(shift.width, z.width * 1.5f)
        near(back.width, z.width * 1.5f)
        near(back.right, W - 3f)
    }

    @Test fun bottomRowProportions() {
        val keys = build(Plane.LETTERS, ret = "go")
        val bottom = keys.filter { it.top > 3 * H / 4 - 1 }
        // Gboard: ?123 , 😊 space . enter
        assertEquals(listOf(KeyKind.PLANE, KeyKind.PUNCT, KeyKind.EMOJI, KeyKind.SPACE, KeyKind.PUNCT, KeyKind.RETURN),
            bottom.map { it.kind })
        assertEquals("?123", bottom[0].label)
        assertEquals(listOf(",", "."), bottom.filter { it.kind == KeyKind.PUNCT }.map { it.insert })
        near(bottom[0].width, 0.15f * W)
        near(bottom[1].width, 0.10f * W)
        near(bottom[2].width, 0.10f * W)
        near(bottom[4].width, 0.10f * W)
        near(bottom[5].width, 0.15f * W)
        near(bottom.last().right, W - 3f, 0.05f)
        // cùng margin như mọi hàng
        near(bottom[0].top, 3 * H / 4 + KeyLayout.ROW_MARGIN_V)
        near(bottom[0].bottom, H - KeyLayout.ROW_MARGIN_V)
        near(bottom[0].height, keys.first { it.label == "q" }.height)
        assertEquals("go", bottom[5].label)
    }

    @Test fun emailAndUrlVariants() {
        val email = build(Plane.LETTERS, InputKind.EMAIL).filter { it.kind == KeyKind.PUNCT }
        assertEquals(listOf("@", "."), email.map { it.insert })
        val url = build(Plane.LETTERS, InputKind.URL).filter { it.kind == KeyKind.PUNCT }
        assertEquals(listOf("/", ".com", "."), url.map { it.insert })
        near(url[1].width, 0.15f * W)
        // plane số không đổi theo kind
        val num = build(Plane.NUMBERS, InputKind.EMAIL).filter { it.kind == KeyKind.PUNCT }
        assertEquals(listOf(",", "."), num.map { it.insert })
    }

    @Test fun globeAndTabletDismiss() {
        val k = build(Plane.LETTERS, globe = true, tablet = true)
        val kinds = k.filter { it.top > 3 * H / 4 - 1 }.map { it.kind }
        assertEquals(listOf(KeyKind.PLANE, KeyKind.PUNCT, KeyKind.GLOBE, KeyKind.EMOJI, KeyKind.SPACE,
            KeyKind.PUNCT, KeyKind.RETURN, KeyKind.DISMISS), kinds)
        val space = k.first { it.kind == KeyKind.SPACE }
        assertTrue(space.width > 0.10f * W)
    }

    @Test fun numberAndSymbolPlanes() {
        val n = build(Plane.NUMBERS)
        assertEquals("1234567890".map { it.toString() }, n.filter { it.top < H / 4 }.map { it.label })
        assertTrue(n.any { it.label == "$" } && n.any { it.kind == KeyKind.MORE && it.label == "=\\<" })
        val s = build(Plane.SYMBOLS)
        assertTrue(s.any { it.label == "₫" } && s.any { it.kind == KeyKind.MORE && it.label == "?123" })
        assertEquals("ABC", s.first { it.kind == KeyKind.PLANE }.label)
        val row3 = n.filter { it.top > H / 2 && it.top < 3 * H / 4 }
        assertEquals(7, row3.size)
        near(row3.last().right, W - 3f)
    }

    @Test fun templatesBottomRowOnly() {
        val t = build(Plane.TEMPLATES)
        assertTrue(t.any { it.kind == KeyKind.CLEAR })
        assertTrue(t.none { it.kind == KeyKind.EMOJI || it.kind == KeyKind.LETTER })
        near(t[0].top, H - H / 4 + KeyLayout.BOTTOM_ROW_TOP)
    }

    // --- router ---

    @Test fun letterWinsOverShiftExpandedArea() {
        val keys = build(Plane.LETTERS)
        val z = keys.first { it.label == "z" }
        // mép trái của z, trong vùng nở 3 dp của shift
        val hit = KeyLayout.hit(keys, Plane.LETTERS, z.left + 1f, z.centerY, 4f, d)
        assertEquals("z", hit?.label)
    }

    @Test fun gapBetweenKeysRoutesToNearest() {
        val keys = build(Plane.LETTERS)
        val q = keys.first { it.label == "q" }; val w = keys.first { it.label == "w" }
        val midGapX = (q.right + w.left) / 2
        assertNotNull(KeyLayout.hit(keys, Plane.LETTERS, midGapX, q.centerY, 4f, d))
        // khe giữa hàng 1 và 2 (dời lên 4 dp ⇒ hàng trên)
        val a = keys.first { it.label == "a" }
        val gapY = (q.bottom + a.top) / 2
        assertEquals("q", KeyLayout.hit(keys, Plane.LETTERS, q.centerX, gapY, 4f, d)?.label)
    }

    @Test fun yOffsetShiftsSelectionUp() {
        val keys = build(Plane.LETTERS)
        val a = keys.first { it.label == "a" }
        // chạm 2 dp dưới mép trên của a: điểm chọn dời lên 4 dp ⇒ vẫn trong footprint nở
        // của hàng trên (q/w) — y hệt iOS keySelectionPoint.
        val hit = KeyLayout.hit(keys, Plane.LETTERS, a.centerX, a.top + 1f, 4f, d)
        assertTrue(hit?.label == "a" || hit?.label == "q" || hit?.label == "w")
    }

    @Test fun noDeadGapAboveBottomRow() {
        val keys = build(Plane.LETTERS)
        val shift = keys.first { it.kind == KeyKind.SHIFT }
        val plane = keys.first { it.kind == KeyKind.PLANE }
        // khe giữa hàng 3 và hàng đáy: mọi điểm phải trúng một phím
        var y = shift.bottom
        while (y < plane.top) {
            assertNotNull("dead at y=$y", KeyLayout.hit(keys, Plane.LETTERS, plane.centerX, y, 4f, d))
            y += 0.5f
        }
    }

    @Test fun controlKeysByExpandedArea() {
        val keys = build(Plane.NUMBERS)
        val one = keys.first { it.label == "1" }
        assertEquals("1", KeyLayout.hit(keys, Plane.NUMBERS, one.left - 2f, one.top - 4f, 4f, d)?.label)
        val space = keys.first { it.kind == KeyKind.SPACE }
        assertEquals(KeyKind.SPACE, KeyLayout.hit(keys, Plane.NUMBERS, space.centerX, space.bottom - 1f, 4f, d)?.kind)
    }

    @Test fun farPointMisses() {
        val keys = build(Plane.LETTERS)
        assertNull(KeyLayout.nearestLetter(keys, W / 2, -40f, d))
    }
}
