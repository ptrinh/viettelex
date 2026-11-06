package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Popup nhiều lựa chọn (giữ "." ô URL/email ra đuôi tên miền; luật trượt-chọn/huỷ) và chip
 * đuôi mail sau "@" ở ô email. Song sinh iOS/KeyboardTests/DomainPopupTests.swift.
 */
class DomainPopupTests {
    // MARK: lựa chọn theo loại ô

    @Test fun choicesPerField() {
        val t = DomainPopup.tlds
        assertEquals(".com mặc định, .vn/.com.vn kế (#113)", listOf(".com", ".vn", ".com.vn", ".net", ".org", ".edu"), t)
        assertEquals(t, DomainPopup.choices(DomainPopup.Field.URL, ".", lettersPlane = true))
        assertEquals(t, DomainPopup.choices(DomainPopup.Field.EMAIL, ".", lettersPlane = true))
        assertEquals("không còn phím .com", emptyList<String>(), DomainPopup.choices(DomainPopup.Field.URL, ".com", true))
        assertEquals(emptyList<String>(), DomainPopup.choices(DomainPopup.Field.URL, "/", true))
        assertEquals(emptyList<String>(), DomainPopup.choices(DomainPopup.Field.EMAIL, "@", true))
        assertEquals("ô thường: không", emptyList<String>(), DomainPopup.choices(DomainPopup.Field.NORMAL, ".", true))
        assertEquals("chỉ bàn chữ", emptyList<String>(), DomainPopup.choices(DomainPopup.Field.URL, ".", false))
    }

    // MARK: bố cục + chỉ số dưới ngón

    /** Ô dưới ngón (tuyệt đối, #154). `startX` chỉ để đọc test: chỗ mở không còn ảnh hưởng. */
    @Suppress("UNUSED_PARAMETER")
    private fun idx(l: DomainPopup.Layout, x: Float, y: Float = 20f, startX: Float) =
        DomainPopup.index(x, y, l, top = 0f, bottom = 60f)

    @Test fun layoutLeftToRightWhenRoomOnRight() {
        val l = DomainPopup.layout(keyMidX = 60f, itemWidth = 56f, count = 6, containerWidth = 390f)
        assertFalse(l.mirrored)
        assertEquals(32f, l.originX, 0.001f)
        assertEquals(32f, l.slotMinX(0), 0.001f)
        assertEquals("ô dưới ngón lúc mở = .com", 0, idx(l, 60f, startX = 60f))
        assertEquals(1, idx(l, 60f + 56, startX = 60f))
        assertEquals(5, idx(l, 60f + 56 * 5, startX = 60f))
        assertEquals("lố mép trong ngần: kẹp ô cuối", 5, idx(l, l.originX + l.width + 10, startX = 60f))
        assertEquals(0, idx(l, l.originX - 10, startX = 60f))
        assertNull("trượt xa ngang ⇒ huỷ", idx(l, l.originX + l.width + DomainPopup.CANCEL_SLACK_X + 1, startX = 60f))
        assertNull(idx(l, l.originX - DomainPopup.CANCEL_SLACK_X - 1, startX = 60f))
        assertNull("trượt lên quá ⇒ huỷ", idx(l, 60f, -DomainPopup.CANCEL_SLACK_Y - 1, 60f))
        assertNull("trượt xuống quá ⇒ huỷ", idx(l, 60f, 60 + DomainPopup.CANCEL_SLACK_Y + 1, 60f))
        assertEquals("ngón vẫn trên phím ⇒ chọn", 0, idx(l, 60f, 70f, 60f))
    }

    @Test fun layoutMirrorsNearRightEdge() {
        val l = DomainPopup.layout(keyMidX = 350f, itemWidth = 56f, count = 6, containerWidth = 390f)
        assertTrue(l.mirrored)
        assertEquals(".com vẫn ngay trên phím", 350f - 28, l.slotMinX(0), 0.001f)
        assertTrue(l.originX >= 2f)
        assertEquals(0, idx(l, 350f, startX = 350f))
        assertEquals("loe sang trái: trượt trái ra .vn", 1, idx(l, 350f - 56, startX = 350f))
        assertEquals(5, idx(l, 350f - 56 * 5, startX = 350f))
    }

    @Test fun layoutClampedInsideNarrowContainerWrapsToTwoRows() {
        // 5 ô 56 vừa bề ngang 300 nhưng phải kẹp, ô đầu lệch > 1 ô khỏi phím ⇒ hai hàng (3 + 2).
        val l = DomainPopup.layout(keyMidX = 150f, itemWidth = 56f, count = 5, containerWidth = 300f, rowHeight = 30f)
        assertEquals(2, l.rows)
        assertEquals(3, l.perRow)
        assertTrue(l.originX >= 2f)
        assertTrue(l.originX + l.width <= 298f)
        assertTrue("ô 0 ngay trên phím", l.slotMinX(0) <= 150f && 150f <= l.slotMinX(0) + 56f)
        assertEquals("ô 3 ngay trên ô 0", l.slotMinX(0), l.slotMinX(3), 0.001f)
        assertEquals(0, l.rowOf(2)); assertEquals(1, l.rowOf(3))
        // hàng 0 dưới ranh giới top + rowHeight, hàng 1 trên
        assertEquals(0, DomainPopup.index(150f, 45f, l, top = 0f, bottom = 100f))
        assertEquals(3, DomainPopup.index(150f, 15f, l, top = 0f, bottom = 100f))
        assertEquals("ngón trên phím (dưới popup) ⇒ hàng 0", 0, DomainPopup.index(150f, 90f, l, top = 0f, bottom = 100f))
        val far = if (l.mirrored) l.originX + 1 else l.originX + l.width - 1
        assertEquals("hàng trên thiếu ô ⇒ kẹp ô cuối", 4, DomainPopup.index(far, 15f, l, top = 0f, bottom = 100f))
    }

    @Test fun oneRowUnchangedWhenItFits() {
        val l = DomainPopup.layout(keyMidX = 60f, itemWidth = 56f, count = 6, containerWidth = 390f, rowHeight = 46f)
        assertEquals(1, l.rows); assertEquals(6, l.perRow)
        val m = DomainPopup.layout(keyMidX = 350f, itemWidth = 56f, count = 6, containerWidth = 390f, rowHeight = 46f)
        assertEquals(1, m.rows)
        assertEquals(1, DomainPopup.layout(150f, 56f, 5, 300f, maxRows = 1).rows)
    }

    @Test fun tooWideForOneRowWraps() {
        // 10 ô × 34 = 340 > 316 (một tay / máy hẹp) ⇒ hai hàng 5 ô, bề rộng ô giữ nguyên.
        val l = DomainPopup.layout(keyMidX = 250f, itemWidth = 34f, count = 10, containerWidth = 320f)
        assertEquals(2, l.rows)
        assertEquals(34f, l.itemWidth, 0.001f)
        // maxRows = 1 (không có chỗ phía trên): một hàng, ô co lại cho vừa
        val one = DomainPopup.layout(keyMidX = 250f, itemWidth = 34f, count = 10, containerWidth = 320f, maxRows = 1)
        assertEquals(1, one.rows)
        assertTrue(one.originX >= 2f && one.originX + one.width <= 318.001f)
    }

    /**
     * #154: MỌI ô với tới được ở MỌI chỗ đặt phím (kể cả hàng bị kẹp mép): mở ở tâm phím, quét
     * ngón ngang trong màn hình (chừa 1 dp mép) trên từng hàng ⇒ chọn được đủ mọi ô.
     */
    @Test fun everyCellReachableAnywhere() {
        val rowH = 46f
        for (w in listOf(280f, 320f, 360f, 390f, 430f, 600f))
            for (n in 1..12)
                for (iw in listOf(34f, 38f, 48f, 56f))
                    for (maxRows in 1..2) {
                        var kx = 10f
                        while (kx < w - 10f) {
                            val l = DomainPopup.layout(kx, iw, n, w, rowHeight = rowH, maxRows = maxRows)
                            val keyY = rowH * l.rows + 28f; val bottom = keyY + 20f
                            val h = DomainPopup.Hold(List(n) { "$it" })
                            assertTrue(h.open(l, 0f, bottom, kx, keyY))
                            assertEquals(0, h.selection)
                            val got = HashSet<Int>()
                            for (r in 0 until l.rows) {
                                val cy = (l.rows - 1 - r) * rowH + rowH / 2
                                var x = 1f
                                while (x <= w - 1f) { h.move(x, cy); h.selection?.let { got += it }; x += 1f }
                            }
                            assertEquals("w=$w n=$n iw=$iw kx=$kx rows=${l.rows}", (0 until n).toSet(), got)
                            kx += 7f
                        }
                    }
    }

    /** Hàng một dòng kẹp mép trái ⇒ bù kéo ≤ nửa ô (trước #154 bù trọn ⇒ ô xa ngoài màn hình). */
    @Test fun dragOffsetCappedAtHalfCell() {
        val l = DomainPopup.layout(keyMidX = 127f, itemWidth = 34f, count = 10, containerWidth = 390f, maxRows = 1)
        assertEquals(17f, kotlin.math.abs(DomainPopup.dragOffset(127f, l)), 0.001f)
        val h = DomainPopup.Hold(CommaPopup.choices)
        h.open(l, 0f, 100f, 127f, 80f)
        assertEquals(48f, l.originX, 0.001f)     // kẹp: ô 0 (trái) lệch 62 dp khỏi phím
        h.move(40f, 20f)
        val farLeft = h.selection
        h.move(388f, 20f)
        assertEquals("hai đầu hàng đều chọn được", setOf(0, 9), setOf(farLeft, h.selection))
    }

    @Test fun jitterKeepsPreselectUntilEngaged() {
        // hàng kẹp mép: ô 0 không nằm dưới ngón — run tay nhẹ vẫn giữ ô 0
        val l = DomainPopup.layout(keyMidX = 300f, itemWidth = 34f, count = 10, containerWidth = 360f, maxRows = 1)
        val h = DomainPopup.Hold(CommaPopup.choices)
        h.open(l, 0f, 100f, 300f, 80f)
        assertFalse(h.move(303f, 82f))
        assertEquals(0, h.selection)
        assertTrue(h.move(300f - 3 * 34f, 80f))
        assertTrue(h.selection != 0)
    }

    // MARK: lượt giữ (KeyCommitQueue) — chạm thường / giữ / trượt / huỷ / ngón khác

    private class Rig {
        val out = ArrayList<String>()
        val commits = KeyCommitQueue()
        val key = Any()
        val layout = DomainPopup.layout(60f, 56f, DomainPopup.tlds.size, 390f)
        val hold = DomainPopup.Hold(DomainPopup.tlds)
        fun down() = commits.arm(key) { out += "." }
        fun fire(x: Float = 60f, y: Float = 80f) = hold.fire(commits, key, layout, 0f, 100f, x, y) { out += it }
        fun up() = commits.release(key)
    }

    @Test fun tapStillTypesBase() {
        val r = Rig(); r.down(); r.up()
        assertEquals(listOf("."), r.out)
        assertFalse("đã chốt ⇒ không mở", r.fire())
    }

    @Test fun holdAndReleaseInsertsPreselected() {
        val r = Rig(); r.down()
        assertTrue(r.fire())
        assertEquals(".com", r.hold.chosen)
        assertEquals("chưa nhấc: chưa chèn", emptyList<String>(), r.out)
        r.up()
        assertEquals(listOf(".com"), r.out)
    }

    @Test fun slideSelectsNext() {
        val r = Rig(); r.down(); r.fire()
        assertTrue(r.hold.move(60f + 56, 80f))
        assertFalse("cùng ô: không đổi", r.hold.move(60f + 60, 80f))
        assertEquals(".vn", r.hold.chosen)
        assertTrue(r.hold.move(60f + 112, 80f))
        r.up()
        assertEquals(listOf(".com.vn"), r.out)
    }

    @Test fun slideFarCancelsAndCanComeBack() {
        val r = Rig(); r.down(); r.fire()
        assertTrue(r.hold.move(60f, -300f))
        assertNull(r.hold.chosen)
        r.up()
        assertEquals("trượt xa ⇒ không chèn gì", emptyList<String>(), r.out)
        val r2 = Rig(); r2.down(); r2.fire()
        r2.hold.move(60f, -300f); r2.hold.move(60f + 56, 80f)
        r2.up()
        assertEquals("quay lại hàng thì chọn lại được", listOf(".vn"), r2.out)
    }

    @Test fun otherFingerCommitsSelectionFirst() {
        val r = Rig(); r.down(); r.fire()
        // ngón khác chạm: view chốt popup (release/flush) trước khi chèn phím mới
        r.commits.flush(); r.out += "a"
        assertEquals(listOf(".com", "a"), r.out)
    }

    @Test fun moveBeforeFireIsIgnored() {
        val r = Rig(); r.down()
        assertFalse(r.hold.move(200f, 80f))
        assertNull(r.hold.chosen)
    }

    // MARK: chip đuôi mail

    @Test fun emailChipsAfterAt() {
        val c = EmailDomains.chips("phuc@")
        assertEquals("gmail trước, tối đa 3", listOf("@gmail.com", "@icloud.com", "@yahoo.com"), c.map { it.label })
        assertEquals("không lặp \"@\"", "gmail.com", c.first().insert)
        assertEquals("@outlook.com", EmailDomains.chips("phuc@", limit = 4).last().label)
        assertEquals("gmail.com", EmailDomains.chips("To: a, phuc@").first().insert)
    }

    @Test fun emailChipsCompletePrefix() {
        assertEquals(listOf(EmailDomains.Chip("@gmail.com", "ail.com")), EmailDomains.chips("phuc@gm"))
        assertEquals("ail.com", EmailDomains.chips("phuc@GM").first().insert)
        assertEquals(listOf("@outlook.com"), EmailDomains.chips("phuc@o").map { it.label })
        assertEquals("com", EmailDomains.chips("phuc@gmail.").first().insert)
        assertEquals("m", EmailDomains.chips("phuc@gmail.co").first().insert)
    }

    @Test fun emailChipsGone() {
        for (s in listOf("", "phuc", "@", "hi @", "phuc@gmail.com", "phuc@abc.", "ban@congty", "a@b@", "phuc@ "))
            assertEquals(s, emptyList<EmailDomains.Chip>(), EmailDomains.chips(s))
        assertEquals(emptyList<EmailDomains.Chip>(), EmailDomains.chips("phuc@", limit = 0))
    }

    // MARK: session — ô email có thanh chỉ chứa chip đuôi mail; ô khác không đổi

    private fun session(traits: FieldTraits, settings: KeyboardSettings = KeyboardSettings()) =
        KeyboardSession(UserLangModel(), null) { 1_000_000L }.also { it.startInput(settings, traits) }

    private val email = FieldTraits(passthrough = true, suggestionsAllowed = false, emailField = true)

    @Test fun emailFieldShowsChipsAndInsertsMissingPart() {
        TestAssets.install()
        val s = session(email)
        assertTrue("ô email luôn có thanh", s.suggestionsActive)
        val p = MockProxy()
        p.insertText("phuc@")
        assertEquals(listOf("@gmail.com", "@icloud.com", "@yahoo.com"), s.suggestionsNow(p)?.nextWords)
        s.acceptSuggestion("@gmail.com", p)
        assertEquals("phuc@gmail.com", p.text)
        assertEquals(emptyList<String>(), s.suggestionsNow(p)?.nextWords)
        // context đổi giữa chừng ⇒ không chèn mù
        val q = MockProxy(); q.insertText("phuc@gm")
        s.acceptSuggestion("@yahoo.com", q)
        assertEquals("phuc@gm", q.text)
    }

    @Test fun emailBarOffWhenSuggestionsOffOrSecure() {
        TestAssets.install()
        assertFalse(session(email, KeyboardSettings(showSuggestions = false)).suggestionsActive)
        assertFalse(session(email.copy(isSecure = true)).suggestionsActive)
        assertFalse("ô URL literal: không thanh", session(FieldTraits(passthrough = true, suggestionsAllowed = false,
            urlField = true)).suggestionsActive)
    }
}
