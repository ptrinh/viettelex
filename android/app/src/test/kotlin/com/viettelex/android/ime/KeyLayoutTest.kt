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

    // --- bàn số ---

    private fun pad(plane: Plane, kind: InputKind, signed: Boolean = false, decimal: Boolean = false, ret: String = "done") =
        KeyLayout.build(LayoutConfig(plane, W, H, d, kind, returnLabel = ret, numberSigned = signed, numberDecimal = decimal))

    private fun padLabels(keys: List<LaidKey>) = keys.filter { it.kind == KeyKind.PAD }.map { it.label }.toSet()

    @Test fun phonePadGridHintsAndSides() {
        val k = pad(Plane.PHONE, InputKind.PHONE)
        assertEquals(setOf("1","2","3","4","5","6","7","8","9","*","0","#","+","-","(",")",",",";"), padLabels(k))
        assertEquals("ABC", k.first { it.label == "2" }.hint)
        assertEquals("WXYZ", k.first { it.label == "9" }.hint)
        assertEquals("", k.first { it.label == "1" }.hint)
        // lưới 3 cột bằng nhau, 0 giữa * và #
        val star = k.first { it.label == "*" }; val zero = k.first { it.label == "0" }; val hash = k.first { it.label == "#" }
        near(star.width, zero.width); near(zero.width, hash.width)
        assertTrue(star.right < zero.left && zero.right < hash.left)
        near(zero.centerX, k.first { it.label == "5" }.centerX)
        // cột phải: ⌫ trên cùng, enter dưới cùng; có space + toggle ?123
        val bs = k.first { it.kind == KeyKind.BACKSPACE }; val ret = k.first { it.kind == KeyKind.RETURN }
        assertTrue(bs.top < ret.top && bs.left > hash.right && ret.left > hash.right)
        assertTrue(k.any { it.kind == KeyKind.SPACE })
        assertEquals("?123", k.first { it.kind == KeyKind.MORE }.label)
        assertTrue(k.first { it.label == "+" }.side)
        assertTrue(!k.first { it.label == "5" }.side)
    }

    @Test fun numpadFlagsControlSideKeys() {
        val plain = padLabels(pad(Plane.NUMPAD, InputKind.NUMBER))
        assertEquals(setOf("0","1","2","3","4","5","6","7","8","9"), plain)
        val signed = padLabels(pad(Plane.NUMPAD, InputKind.NUMBER, signed = true))
        assertTrue("-" in signed && "." !in signed && "," !in signed)
        val dec = padLabels(pad(Plane.NUMPAD, InputKind.NUMBER, decimal = true))
        assertTrue("." in dec && "," in dec && "-" !in dec)
        val both = pad(Plane.NUMPAD, InputKind.NUMBER, signed = true, decimal = true)
        assertTrue(padLabels(both).containsAll(listOf("-", ".", ",")))
        // 0 ở hàng dưới, giữa cột
        val zero = both.first { it.label == "0" }
        near(zero.centerX, both.first { it.label == "8" }.centerX)
        assertTrue(zero.top > both.first { it.label == "8" }.bottom)
        // không DECIMAL ⇒ 0 nở phủ cả hàng lưới dưới (không ô trống)
        val p = pad(Plane.NUMPAD, InputKind.NUMBER)
        val z = p.first { it.label == "0" }
        near(z.left, p.first { it.label == "7" }.left); near(z.right, p.first { it.label == "9" }.right)
        // không cột trái khi không có phím phụ ⇒ lưới rộng hơn
        assertTrue(p.first { it.label == "1" }.width > both.first { it.label == "1" }.width)
        // toggle ?123 + space + ⌫ + enter luôn có
        assertTrue(both.any { it.kind == KeyKind.SPACE } && both.any { it.kind == KeyKind.BACKSPACE }
            && both.any { it.kind == KeyKind.RETURN })
        assertEquals("?123", both.first { it.kind == KeyKind.MORE }.label)
    }

    @Test fun datetimePadHasSeparators() {
        val k = padLabels(pad(Plane.NUMPAD, InputKind.DATETIME))
        assertTrue(k.containsAll(listOf("/", ":", "-")))
        assertTrue("." !in k)
    }

    @Test fun padKeysDoNotOverlapAndNoDeadGaps() {
        for (k in listOf(pad(Plane.PHONE, InputKind.PHONE), pad(Plane.NUMPAD, InputKind.DATETIME),
                         pad(Plane.NUMPAD, InputKind.NUMBER), pad(Plane.NUMPAD, InputKind.NUMBER, signed = true, decimal = true))) {
            for (a in k) for (b in k) if (a !== b) {
                val overlap = a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom
                assertTrue("overlap $a / $b", !overlap)
            }
            var y = 1f
            while (y < H - 1f) {
                var x = 1f
                while (x < W - 1f) {
                    assertNotNull("dead at $x,$y", KeyLayout.hit(k, Plane.NUMPAD, x, y, 4f, d)); x += 7f
                }
                y += 3f
            }
        }
    }

    @Test fun symbolsPlaneReturnsToPadForNumericFields() {
        val n = KeyLayout.build(LayoutConfig(Plane.NUMBERS, W, H, d, InputKind.PHONE))
        assertEquals("123", n.first { it.kind == KeyKind.PLANE }.label)
        val t = KeyLayout.build(LayoutConfig(Plane.NUMBERS, W, H, d, InputKind.NORMAL))
        assertEquals("ABC", t.first { it.kind == KeyKind.PLANE }.label)
    }
}
