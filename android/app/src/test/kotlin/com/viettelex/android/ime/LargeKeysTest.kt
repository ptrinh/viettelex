package com.viettelex.android.ime

import com.viettelex.keyboard.SpaceSideKey
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * "Phím to" (LargeKeys, Settings → Phím, mặc định TẮT) — song sinh iOS LargeKeysTests. Hình học thuần:
 * tắt = đúng bố cục cũ; bật (điện thoại) = "," / "." hàng đáy rộng bằng phím 😊, space co lại có sàn,
 * phím khác đứng yên, hàng vẫn kín bề ngang, không chồng nhau; tablet không đổi.
 */
class LargeKeysTest {
    private fun near(exp: Float, act: Float, msg: String = "", eps: Float = 0.05f) = assertEquals(msg, exp, act, eps)

    /** (bề ngang dp, landscape): điện thoại nhỏ / phổ biến / lớn + ngang. */
    private val phones = listOf(360f to false, 393f to false, 411f to false, 430f to false, 780f to true, 891f to true)
    private val densities = listOf(1f, 2.625f)

    private fun cfg(plane: Plane, wDp: Float, land: Boolean, d: Float, large: Boolean,
                    kind: InputKind = InputKind.NORMAL, side: SpaceSideKey = SpaceSideKey.DEFAULT,
                    globe: Boolean = false, emojiInStrip: Boolean = false, numberRow: Boolean = false,
                    oneHand: OneHandSide = OneHandSide.OFF, split: Boolean = false, tablet: Boolean = false) =
        LayoutConfig(plane, wDp * d, d * KeyLayout.keyAreaDp(tablet, land, 0, numberRow), d, kind,
            needsGlobe = globe, tablet = tablet, numberRow = numberRow, oneHand = oneHand,
            spaceSideKey = side, emojiInStrip = emojiInStrip, split = split, largeKeys = large)

    private fun bottom(keys: List<LaidKey>): List<LaidKey> {
        val top = keys.maxOf { it.top }
        return keys.filter { it.top == top }.sortedBy { it.left }
    }

    private fun str(keys: List<LaidKey>) = keys.map { it.toString() }

    /** Mọi tổ hợp bố cục điện thoại có hàng đáy ", ." (plane chữ / số / ký hiệu / mẫu câu / tìm emoji). */
    private fun variants(wDp: Float, land: Boolean, d: Float, large: Boolean): List<Pair<String, LayoutConfig>> {
        val out = ArrayList<Pair<String, LayoutConfig>>()
        for (plane in listOf(Plane.LETTERS, Plane.NUMBERS, Plane.SYMBOLS, Plane.TEMPLATES, Plane.EMOJI_SEARCH))
        for (kind in listOf(InputKind.NORMAL, InputKind.EMAIL, InputKind.URL))
        for (side in SpaceSideKey.entries) for (globe in listOf(false, true)) for (strip in listOf(false, true))
        for (one in listOf(OneHandSide.OFF, OneHandSide.LEFT)) for (nr in listOf(false, true)) {
            if (one != OneHandSide.OFF && land) continue
            out += "$plane $kind $side globe=$globe strip=$strip $one nr=$nr w=$wDp d=$d" to
                cfg(plane, wDp, land, d, large, kind, side, globe, strip, nr, one)
        }
        return out
    }

    /** Tắt (mặc định) = đúng bố cục trước khi có tuỳ chọn; tablet bật cũng không đổi. */
    @Test fun offIsUnchangedAndTabletIgnores() {
        assertEquals(false, LayoutConfig(Plane.LETTERS, 411f, 224f, 1f).largeKeys)
        for ((w, land) in phones) for (d in densities) for ((tag, c) in variants(w, land, d, large = false))
            assertEquals(tag, str(KeyLayout.build(c.copy(largeKeys = false))), str(KeyLayout.build(c)))
        for (land in listOf(false, true)) for (w in listOf(768f, 1024f)) for (side in SpaceSideKey.entries)
        for (plane in listOf(Plane.LETTERS, Plane.NUMBERS, Plane.SYMBOLS, Plane.TEMPLATES))
        for (split in listOf(false, true)) {
            val c = cfg(plane, w, land, 1f, true, side = side, split = split, tablet = true)
            assertEquals("tablet $plane $side $w split=$split", str(KeyLayout.build(c.copy(largeKeys = false))), str(KeyLayout.build(c)))
        }
    }

    /**
     * Bật: "," / "." = phím 😊 (0.10 W) trừ khi space chạm sàn [KeyLayout.LARGE_MIN_SPACE_DP]; không bao giờ
     * hẹp hơn lúc tắt; space co đúng phần dấu câu nở; mọi phím khác cùng khung; hàng kín, không chồng.
     */
    @Test fun onWidensPunctShrinksSpaceWithFloor() {
        var widened = 0
        for ((w, land) in phones) for (d in densities) for ((tag, c) in variants(w, land, d, large = true)) {
            val on = KeyLayout.build(c); val off = KeyLayout.build(c.copy(largeKeys = false))
            assertEquals(tag, off.size, on.size)
            val gap = KeyLayout.KEY_SPACING * d
            val bo = bottom(on); val bf = bottom(off)
            // Hàng trên hàng đáy y hệt.
            assertEquals(tag, str(off - bf.toSet()), str(on - bo.toSet()))
            assertEquals(tag, bf.map { it.kind to it.label }, bo.map { it.kind to it.label })
            val rowW = if (c.oneHand != OneHandSide.OFF && OneHand.appliesTo(c.plane)) OneHand.span(c.widthPx, c.oneHand).second
                else c.widthPx
            val emojiW = KeyLayout.LARGE_PUNCT * rowW
            var grown = 0f
            for ((a, b) in bf.zip(bo)) {
                if (a.kind == KeyKind.PUNCT && KeyLayout.largeWidens(a.label)) {
                    assertTrue("$tag ${a.label} hẹp hơn lúc tắt", b.width >= a.width - 0.01f)
                    assertTrue("$tag ${a.label} rộng hơn 😊", b.width <= emojiW + 0.05f)
                    grown += b.width - a.width
                    if (b.width > a.width + 0.01f) widened++
                } else if (a.kind != KeyKind.SPACE && a.kind != KeyKind.PUNCT) {
                    // 123 / 😊 / 🌐 / ↵ cùng bề rộng (có thể dời do dấu câu bên trái nở).
                    near(a.width, b.width, "$tag ${a.kind}")
                } else if (a.kind == KeyKind.PUNCT) near(a.width, b.width, "$tag ${a.label}")   // @ / không nở
            }
            val so = bo.single { it.kind == KeyKind.SPACE }; val sf = bf.single { it.kind == KeyKind.SPACE }
            near(sf.width - grown, so.width, "$tag space co đúng phần nở")
            assertTrue("$tag space dưới sàn", so.width >= minOf(sf.width, KeyLayout.LARGE_MIN_SPACE_DP * d) - 0.05f)
            // Nở chưa đủ 😊 ⇒ space đúng bằng sàn.
            if (bo.any { it.kind == KeyKind.PUNCT && KeyLayout.largeWidens(it.label) && it.width < emojiW - 0.05f } && grown > 0.01f)
                near(KeyLayout.LARGE_MIN_SPACE_DP * d, so.width, "$tag sàn")
            // Kín hàng, khe đều, không chồng.
            near(bf.first().left, bo.first().left, tag); near(bf.last().right, bo.last().right, tag)
            for (i in 1 until bo.size) near(bo[i - 1].right + gap, bo[i].left, "$tag khe $i")
        }
        assertTrue("có bố cục thật sự nở", widened > 100)
    }

    /** Điện thoại 411 dp dọc, bàn chữ mặc định: "," 0.085 W → 0.10 W (≈ 34.9 → 41.1 dp), space bớt đúng chừng đó. */
    @Test fun typical411() {
        val off = bottom(KeyLayout.build(cfg(Plane.LETTERS, 411f, false, 1f, false)))
        val on = bottom(KeyLayout.build(cfg(Plane.LETTERS, 411f, false, 1f, true)))
        val kinds = listOf(KeyKind.PLANE, KeyKind.EMOJI, KeyKind.SPACE, KeyKind.PUNCT, KeyKind.RETURN)
        assertEquals(kinds, on.map { it.kind })
        near(0.085f * 411f, off[3].width); near(0.10f * 411f, on[3].width)
        near(off[1].width, on[3].width)            // = phím 😊
        near(185.67f, off[2].width); near(179.5f, on[2].width)
        for (i in listOf(0, 1)) assertEquals(off[i].toString(), on[i].toString())   // ?123, 😊 đứng yên
        assertEquals(off[4].toString(), on[4].toString())                           // ↵ đứng yên
        // Cả hai: "," trái + "." phải đều 41.1, space 185.67 − (34.94 + khe 5) − 2 × 6.17.
        val both = bottom(KeyLayout.build(cfg(Plane.LETTERS, 411f, false, 1f, true, side = SpaceSideKey.BOTH)))
        near(41.1f, both[2].width); near(41.1f, both[4].width)
        near(185.67f - 34.935f - 5f - 2 * 6.165f, both[3].width)
    }

    /** Máy hẹp + 🌐 + Cả hai + một tay: space chạm sàn, dấu câu nở ít hơn (không hẹp hơn lúc tắt). */
    @Test fun narrowPhoneCapsGrowth() {
        val c = cfg(Plane.LETTERS, 360f, false, 1f, true, side = SpaceSideKey.BOTH, globe = true)
        val b = bottom(KeyLayout.build(c))
        val sp = b.single { it.kind == KeyKind.SPACE }
        near(KeyLayout.LARGE_MIN_SPACE_DP, sp.width)
        val p = b.filter { it.kind == KeyKind.PUNCT }
        assertEquals(2, p.size)
        for (k in p) assertTrue(k.width > KeyLayout.PHONE_LETTERS_COMMA * 360f && k.width < 36f)
        // Một tay trên máy hẹp: space lúc tắt đã dưới sàn ⇒ không nở gì.
        val one = c.copy(oneHand = OneHandSide.LEFT)
        assertEquals(str(KeyLayout.build(one.copy(largeKeys = false))), str(KeyLayout.build(one)))
    }

    /**
     * Hàng Z: ⇧ / ⌫ Android vốn sát z / m đúng một khe phím (không có khe rộng như iPhone) ⇒ bật hay tắt
     * như nhau; pin để giữ bất biến đó.
     */
    @Test fun zRowAlreadyClosesGap() {
        for ((w, land) in phones) for (d in densities) for (plane in listOf(Plane.LETTERS, Plane.NUMBERS, Plane.SYMBOLS))
        for (split in listOf(false, true)) for (large in listOf(false, true)) {
            val keys = KeyLayout.build(cfg(plane, w, land, d, large, split = split))
            val gap = KeyLayout.KEY_SPACING * d
            val back = keys.single { it.kind == KeyKind.BACKSPACE }
            val row = keys.filter { it.top == back.top }.sortedBy { it.left }
            val tag = "$plane w=$w d=$d split=$split large=$large"
            for (i in 1 until row.size) {
                if (row[i - 1].right + gap * 3 < row[i].left) continue   // khe giữa bàn tách đôi
                near(row[i - 1].right + gap, row[i].left, "$tag ${row[i - 1].label}→${row[i].label}")
            }
        }
    }

    /** Bàn tách đôi (điện thoại ngang ≥ 600 dp): "," "." = phím 😊 nửa trái, space nửa phải co (có sàn). */
    @Test fun splitPunctMatchesEmoji() {
        for (w in listOf(780f, 891f)) for (side in SpaceSideKey.entries)
        for (plane in listOf(Plane.LETTERS, Plane.NUMBERS, Plane.SYMBOLS)) {
            val c = cfg(plane, w, true, 1f, true, side = side, split = true)
            assertTrue(KeyLayout.splitActive(c))
            val on = KeyLayout.build(c); val off = KeyLayout.build(c.copy(largeKeys = false))
            val bo = bottom(on); val bf = bottom(off)
            val emoji = bo.single { it.kind == KeyKind.EMOJI }
            val spaces = bo.filter { it.kind == KeyKind.SPACE }
            val spacesOff = bf.filter { it.kind == KeyKind.SPACE }
            val tag = "$plane $side w=$w"
            for ((a, b) in bf.zip(bo)) {
                if (a.kind == KeyKind.PUNCT) {
                    assertTrue(tag, b.width >= a.width - 0.01f && b.width <= emoji.width + 0.05f)
                    if (spaces.last().width > KeyLayout.LARGE_MIN_SPACE_DP + 0.05f) near(emoji.width, b.width, tag)
                }
            }
            near(spacesOff[0].width, spaces[0].width, tag)   // nửa trái không đổi
            assertTrue(tag, spaces[1].width >= minOf(spacesOff[1].width, KeyLayout.LARGE_MIN_SPACE_DP) - 0.05f)
            near(bf.last().right, bo.last().right, tag)
            assertEquals(tag, str(off - bf.toSet()), str(on - bo.toSet()))
        }
    }

    /** Router theo khung thật: chạm mép trái phần "," vừa nở (ngoài khung cũ, ngoài dải ưu tiên space) ra ",". */
    @Test fun hitFollowsRealRects() {
        val c = cfg(Plane.LETTERS, 411f, false, 1f, true)
        val on = KeyLayout.build(c); val off = KeyLayout.build(c.copy(largeKeys = false))
        val comma = on.single { it.kind == KeyKind.PUNCT }; val commaOff = off.single { it.kind == KeyKind.PUNCT }
        assertTrue(comma.left < commaOff.left - 5f)
        val y = comma.centerY
        assertEquals(",", KeyLayout.hit(on, Plane.LETTERS, comma.centerX, y, 4f, 1f)?.label)
        assertEquals(KeyKind.SPACE, KeyLayout.hit(off, Plane.LETTERS, comma.left + 2f, y, 4f, 1f)?.kind)
        val x = comma.left + 0.35f * comma.width   // ngoài dải space (0.30)
        assertEquals(",", KeyLayout.hit(on, Plane.LETTERS, x, y, 4f, 1f)?.label)
    }
}
