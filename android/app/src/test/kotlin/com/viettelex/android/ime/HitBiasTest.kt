package com.viettelex.android.ime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import com.viettelex.keyboard.SpaceSideKey

/**
 * Ưu tiên phím ở mép chung (HitBias, Phil 06/10/2026) — song sinh iOS KeyHitBiasTests:
 * space thắng "," / "." kề trong dải 30% (gõ cuộn < 150 ms: 40%); tâm mọi phím không đổi.
 * 04/11/2026 (#145): dải chỉ áp ở khe / phần nở NGOÀI khung — trong khung thật của phím dấu
 * câu luôn ra phím dấu đó (xem insidePunctNeverSpace).
 * 10/10/2026 (bug "bấm ⌫ hay thành m / l"): phím chữ KHÔNG còn lấn ⇧ / ⌫; khe quanh phím
 * chức năng thuộc nó (KeyLayout.gutterOwner) — xem backspaceAndShiftNeverStolenByLetters.
 */
class HitBiasTest {
    private val d = 1f
    private val W = 390f
    private val H = 218f
    private val slow = Long.MAX_VALUE

    private fun build(plane: Plane = Plane.LETTERS, tablet: Boolean = false) =
        KeyLayout.build(LayoutConfig(plane, W, H, d, tablet = tablet))

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
        for (tablet in listOf(false, true)) {
            val keys = build(tablet = tablet)
            for (k in keys) assertSame(k.label + k.kind, k, hit(keys, k.centerX, k.centerY, since = 50))
        }
    }

    @Test fun spaceWinsNearCommaBoundary() {
        // Bố cục duy nhất (12/10/2026): [?123][😊][space][,][↵] — "," kề space bên phải, ↵ sau nó.
        val keys = build()
        val space = keys.first { it.kind == KeyKind.SPACE }
        val comma = keys.first { it.kind == KeyKind.PUNCT && it.label == "," }
        val ret = keys.first { it.kind == KeyKind.RETURN }
        val y = comma.centerY
        val w = comma.width
        // (x, since, mong đợi)
        val table = listOf(
            Triple((space.right + comma.left) / 2 + 0.5f, slow, space),   // khe, phía ","
            Triple(comma.left - 0.5f, 100L, space),                        // khe sát ",": space
            Triple(comma.left + 0.5f, slow, comma),                        // trong khung: luôn ","
            Triple(comma.left + 0.29f * w, slow, comma),
            Triple(comma.left + 0.31f * w, slow, comma),
            Triple(comma.left + 0.38f * w, 100L, comma),                   // gõ cuộn
            Triple(comma.left + 0.01f, 10L, comma),
            Triple(comma.left + 0.38f * w, 300L, comma),
            Triple(comma.left + 0.42f * w, 100L, comma),
            Triple(comma.right - 1f, 50L, comma),
            Triple(ret.left + 1f, 50L, ret),                               // ↵ không nhường ai
            Triple(ret.centerX, 50L, ret),
        )
        for ((x, since, want) in table) assertSame("x=$x since=$since", want, hit(keys, x, y, since))
    }

    @Test fun tabletCommaAndPeriodBothSidesOfSpace() {
        // Tablet (16/10/2026): [?123][😊][,][space][.][↵][ẩn] — "," TRÁI, "." PHẢI space, cả hai
        // nhường dải mép cho space; tâm vẫn là của nó; 😊 / ↵ không nhường ai.
        val keys = build(tablet = true)
        val space = keys.first { it.kind == KeyKind.SPACE }
        val comma = keys.first { it.kind == KeyKind.PUNCT && it.label == "," }
        val dot = keys.first { it.kind == KeyKind.PUNCT && it.label == "." }
        val emoji = keys.first { it.kind == KeyKind.EMOJI }
        val ret = keys.first { it.kind == KeyKind.RETURN }
        assertTrue(comma.right < space.left && dot.left > space.right)
        val y = space.centerY
        assertSame(comma, hit(keys, comma.right - 0.2f * comma.width, y))
        assertSame(comma, hit(keys, comma.right - 0.35f * comma.width, y))
        assertSame(comma, hit(keys, comma.right - 0.35f * comma.width, y, 50L))   // gõ cuộn
        assertSame(comma, hit(keys, comma.right - 0.01f, y, 50L))                 // sát mép space
        assertSame(comma, hit(keys, comma.centerX, y, 50L))
        assertSame(comma, hit(keys, comma.left + 1f, y, 50L))                    // mép 😊 không phải space
        assertSame(emoji, hit(keys, emoji.right - 1f, y, 50L))
        assertSame(dot, hit(keys, dot.left + 0.2f * dot.width, y))
        assertSame(dot, hit(keys, dot.left + 0.35f * dot.width, y))
        assertSame(dot, hit(keys, dot.left, y, 50L))
        assertSame(dot, hit(keys, dot.centerX, y, 50L))
        assertSame(dot, hit(keys, dot.right - 1f, y, 50L))
        assertSame(ret, hit(keys, ret.left + 1f, y, 50L))
        // Khe ","↔space, space↔"." ⇒ space.
        assertSame(space, hit(keys, (comma.right + space.left) / 2, y))
        assertSame(space, hit(keys, (space.right + dot.left) / 2, y))
    }

    @Test fun spaceWinsOverPeriodLeftOrRight() {
        // Plane số: [ABC][,][😊][space][.][↵] — "." BÊN PHẢI space.
        val keys = build(Plane.NUMBERS)
        val space = keys.first { it.kind == KeyKind.SPACE }
        val dot = keys.first { it.kind == KeyKind.PUNCT && it.label == "." }
        assertSame(dot, hit(keys, dot.left + 0.2f * dot.width, dot.centerY, 10L, plane = Plane.NUMBERS))
        assertSame(space, hit(keys, dot.left - 0.5f, dot.centerY, 10L, plane = Plane.NUMBERS))   // khe
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

    /** "Phím cạnh dấu cách" (16/10/2026): "." thay "," được space lấn y hệt; Tắt ⇒ không có gì để lấn. */
    @Test fun spaceSideKeyOptions() {
        val dotKeys = KeyLayout.build(LayoutConfig(Plane.LETTERS, W, H, d, spaceSideKey = SpaceSideKey.PERIOD))
        val space = dotKeys.first { it.kind == KeyKind.SPACE }
        val dot = dotKeys.first { it.kind == KeyKind.PUNCT && it.label == "." }
        assertSame(dot, hit(dotKeys, dot.left + 0.29f * dot.width, dot.centerY))
        assertSame(dot, hit(dotKeys, dot.left + 0.38f * dot.width, dot.centerY, 100L))
        assertSame(space, hit(dotKeys, dot.left - 0.5f, dot.centerY, 100L))       // khe
        assertSame(dot, hit(dotKeys, dot.centerX, dot.centerY, 50L))
        val off = KeyLayout.build(LayoutConfig(Plane.LETTERS, W, H, d, spaceSideKey = SpaceSideKey.OFF))
        val offSpace = off.first { it.kind == KeyKind.SPACE }
        val ret = off.first { it.kind == KeyKind.RETURN }
        assertTrue(off.none { it.kind == KeyKind.PUNCT })
        // Space kề ↵: mép phải space vẫn là space, ↵ không nhường ai.
        assertSame(offSpace, hit(off, offSpace.right - 1f, offSpace.centerY, 50L))
        assertSame(ret, hit(off, ret.left + 1f, ret.centerY, 50L))
    }
    /** "Cả hai" (16/10/2026): space lấn mép CẢ "," bên trái lẫn "." bên phải; tâm mỗi phím vẫn của nó. */
    @Test fun spaceSideBothBias() {
        val keys = KeyLayout.build(LayoutConfig(Plane.LETTERS, W, H, d, spaceSideKey = SpaceSideKey.BOTH))
        val space = keys.first { it.kind == KeyKind.SPACE }
        val comma = keys.first { it.kind == KeyKind.PUNCT && it.label == "," }
        val dot = keys.first { it.kind == KeyKind.PUNCT && it.label == "." }
        assertTrue(comma.right <= space.left && dot.left >= space.right)
        // "," bên trái space (#145: chạm mép phải "," gõ nhanh từng ra space ⇒ space đôi ". ").
        assertSame(comma, hit(keys, comma.right - 0.29f * comma.width, comma.centerY))
        assertSame(comma, hit(keys, comma.right - 0.35f * comma.width, comma.centerY, 100L))
        assertSame(comma, hit(keys, comma.right - 0.01f, comma.centerY, 10L))
        assertSame(comma, hit(keys, comma.centerX, comma.centerY, 50L))
        // "." bên phải space: như Dấu chấm.
        assertSame(dot, hit(keys, dot.left + 0.29f * dot.width, dot.centerY))
        assertSame(dot, hit(keys, dot.left + 0.31f * dot.width, dot.centerY))
        assertSame(dot, hit(keys, dot.centerX, dot.centerY, 50L))
        // Khe giữa "," và space ⇒ space.
        assertSame(space, hit(keys, (comma.right + space.left) / 2, space.centerY))
        // Thanh trên (không 😊): "," kề ?123 — ?123 không lấn ",".
        val top = KeyLayout.build(LayoutConfig(Plane.LETTERS, W, H, d, spaceSideKey = SpaceSideKey.BOTH, emojiInStrip = true))
        val c2 = top.first { it.kind == KeyKind.PUNCT && it.label == "," }
        assertSame(c2, hit(top, c2.left + 1f, c2.centerY, 50L))
        assertSame(c2, hit(top, c2.right - 1f, c2.centerY))
        assertSame(top.first { it.kind == KeyKind.SPACE }, hit(top, c2.right + 1f, c2.centerY))
    }

    /**
     * Phil 04/11/2026 (#145, "bấm , toàn trượt sang space"): MỌI điểm trong khung nhìn thấy của
     * phím dấu câu kề space (lưới 9×9 tới sát mép, gồm mép phía space) ra đúng phím đó — gõ chậm
     * lẫn gõ cuộn 10 / 100 ms sau chữ — ở mọi bố cục: điện thoại / tablet, ",", ".", Cả hai, ô
     * email / URL, tách đôi, một tay, phím to, hàng số, plane 123 / #+=. Khe giữa phím dấu và space
     * (ngoài khung) vẫn ra space.
     */
    @Test fun insidePunctNeverSpace() {
        val fr = listOf(0f, 0.01f, 0.1f, 0.3f, 0.35f, 0.4f, 0.5f, 0.9f, 0.999f)
        val configs = ArrayList<LayoutConfig>()
        for ((w, h, tablet) in listOf(Triple(360f, 218f, false), Triple(390f, 218f, false), Triple(430f, 230f, false),
                Triple(915f, 170f, false), Triple(800f, 300f, true), Triple(1280f, 360f, true))) {
            for (plane in listOf(Plane.LETTERS, Plane.NUMBERS, Plane.SYMBOLS)) {
                for (kind in listOf(InputKind.NORMAL, InputKind.EMAIL, InputKind.URL)) {
                    for (side in SpaceSideKey.values()) {
                        configs += LayoutConfig(plane, w, h, d, kind = kind, tablet = tablet, spaceSideKey = side)
                    }
                }
                configs += LayoutConfig(plane, w, h, d, tablet = tablet, split = true)
                configs += LayoutConfig(plane, w, h, d, tablet = tablet, largeKeys = true, spaceSideKey = SpaceSideKey.BOTH)
                configs += LayoutConfig(plane, w, h, d, tablet = tablet, emojiInStrip = true, spaceSideKey = SpaceSideKey.BOTH)
                if (!tablet) for (oh in OneHandSide.values())
                    configs += LayoutConfig(plane, w, h, d, oneHand = oh, spaceSideKey = SpaceSideKey.BOTH)
            }
            configs += LayoutConfig(Plane.LETTERS, w, h * 1.2f, d, tablet = tablet, numberRow = true)
        }
        var checked = 0
        for (cfg in configs) {
            val keys = KeyLayout.build(cfg)
            val spaces = keys.filter { it.kind == KeyKind.SPACE }
            for (p in keys.filter { it.kind == KeyKind.PUNCT }) {
                val adj = spaces.firstOrNull { s ->
                    minOf(s.bottom, p.bottom) - maxOf(s.top, p.top) > 0.5f * minOf(s.height, p.height) &&
                        (s.left - p.right in 0f..HitBias.MAX_GAP_DP * d || p.left - s.right in 0f..HitBias.MAX_GAP_DP * d)
                } ?: continue
                val tag = "$cfg '${p.label}'"
                for (fx in fr) for (fy in fr) {
                    val x = p.left + fx * p.width; val y = p.top + fy * p.height
                    for (since in listOf(slow, 10L, 100L))
                        assertSame("$tag ($x,$y) since=$since", p, KeyLayout.hit(keys, cfg.plane, x, y, 4f * d, d, since))
                }
                // Khe giữa (ngoài khung) ⇒ space như trước.
                val gx = if (adj.left >= p.right) (p.right + adj.left) / 2 else (adj.right + p.left) / 2
                assertSame("$tag khe", adj, KeyLayout.hit(keys, cfg.plane, gx, p.centerY, 4f * d, d, 100L))
                checked++
            }
        }
        assertTrue("không phím dấu nào được kiểm: $checked", checked > 50)
    }

    @Test fun refineGivesInsidePunctBackFromSpace() {
        // Khe hẹp (1 dp < vùng nở 3 dp của space): router có thể chọn space trong khung "," ⇒ trả lại.
        val comma = LaidKey(KeyKind.PUNCT, ",", ",", ",", 60f, 0f, 90f, 40f)
        val space = LaidKey(KeyKind.SPACE, "", "", " ", 91f, 0f, 300f, 40f)
        val keys = listOf(comma, space)
        assertSame(comma, HitBias.refine(keys, space, 89f, 20f, 10L, d))
        assertSame(comma, HitBias.refine(keys, comma, 89.9f, 20f, 10L, d))
        assertSame(space, HitBias.refine(keys, comma, 90.5f, 20f, 10L, d))      // khe
        assertSame(space, HitBias.refine(keys, space, 150f, 20f, 10L, d))
        // Phần nở NGOÀI khung (dưới ",", trong dải) vẫn theo dải cũ.
        assertSame(space, HitBias.refine(keys, comma, 85f, 42f, 10L, d))
        assertSame(comma, HitBias.refine(keys, comma, 65f, 42f, 10L, d))
    }
}
