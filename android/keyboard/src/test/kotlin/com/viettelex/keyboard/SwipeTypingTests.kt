package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** Tích hợp gõ vuốt — phần thuần: phân loại cử chỉ, huỷ chữ đầu, luồng session. */
class SwipeTypingTests {
    @Before fun setUp() = TestAssets.install()

    // ---- GestureClassifier (dp, ms) ----

    /** Phím 35×50 dp ở (0,0); bề rộng phím 35 dp. */
    private fun classifier(x: Float = 17f, y: Float = 25f, since: Long = Long.MAX_VALUE) =
        GestureClassifier().also { it.begin(x, y, 0L, 0f, 0f, 35f, 50f, 35f, since) }

    /** Trượt thẳng (dx, dy) trong [ms], mẫu mỗi 8 ms; trả trạng thái cuối. */
    private fun GestureClassifier.slide(dx: Float, dy: Float, ms: Long, x0: Float = 17f, y0: Float = 25f,
                                        t0: Long = 0L): GestureClassifier.State {
        var s = state
        var t = 8L
        while (t <= ms) {
            val f = t.toFloat() / ms
            s = move(x0 + dx * f, y0 + dy * f, t0 + t)
            t += 8
        }
        return s
    }

    @Test fun quickTapWithSlideIsNotSwipe() {
        for (d in listOf(5f, 10f, 15f)) {
            // giữa phím, trượt ngang/chéo 5–15 dp nhanh
            assertNotEquals(GestureClassifier.State.SWIPE, classifier().slide(d, 0f, 60))
            assertNotEquals(GestureClassifier.State.SWIPE, classifier().slide(d, d, 40))
            // sát mép phím: ra khỏi phím nhưng chưa đủ 1 bề rộng phím
            assertNotEquals(GestureClassifier.State.SWIPE, classifier(x = 30f).slide(d, 0f, 50, x0 = 30f))
        }
    }

    @Test fun secondFingerLocksTap() {
        val c = classifier()
        c.move(20f, 25f, 8)
        c.pointerAdded()
        assertEquals(GestureClassifier.State.TAP, c.state)
        assertEquals(GestureClassifier.State.TAP, c.slide(120f, 0f, 200, t0 = 16))
    }

    @Test fun swipeRightAfterTapIsSuppressed() {
        // 100 ms sau phím trước: ngưỡng ×2.43 ⇒ kéo 2 phím (70 dp) chưa thành vuốt
        assertNotEquals(GestureClassifier.State.SWIPE, classifier(since = 100).slide(70f, 0f, 120))
        // cùng cử chỉ khi không vừa gõ ⇒ vuốt
        assertEquals(GestureClassifier.State.SWIPE, classifier().slide(70f, 0f, 120))
        val c = GestureClassifier()
        assertEquals(3f, c.factorAfterTyping(0), 1e-4f)
        assertEquals(1f, c.factorAfterTyping(350), 1e-4f)
        assertTrue(c.factorAfterTyping(100) > c.factorAfterTyping(200))
    }

    @Test fun realSwipeIsSwipe() {
        assertEquals(GestureClassifier.State.SWIPE, classifier().slide(60f, 10f, 150))
        // lên hàng trên (ra khỏi phím theo trục dọc)
        assertEquals(GestureClassifier.State.SWIPE, classifier().slide(20f, -45f, 120))
    }

    @Test fun slowDragLocksTapAfterTimeout() {
        val c = classifier()
        // 0.05 dp/ms: sau 500 ms mới đi 25 dp — khoá chạm, đi xa hơn cũng không thành vuốt
        assertEquals(GestureClassifier.State.TAP, c.slide(40f, 0f, 800))
    }

    // ---- EngineBridge.undoLastLetter ----

    private fun bridge() = EngineBridge().also { it.trackLetterUndo = true }

    @Test fun undoTelexKeyRestoresWordAndEngine() {
        val b = bridge(); val p = MockProxy()
        for (c in "tieng") b.letter(c, p)
        b.letter('s', p)
        assertEquals("tiéng", p.text)
        assertTrue(b.undoLastLetter(p))           // "tieng" + s huỷ về "tieng"
        assertEquals("tieng", p.text)
        assertEquals("tieng", b.composedWord)
        assertEquals("tieng", b.rawWord)          // engine trở về ĐÚNG trước phím s
        b.letter('f', p)
        assertEquals("tièng", p.text)
        val b2 = bridge(); val p2 = MockProxy()
        for (c in "tieeng") b2.letter(c, p2)
        b2.letter('s', p2)
        assertEquals("tiếng", p2.text)
        assertTrue(b2.undoLastLetter(p2))
        assertEquals("tiêng", p2.text)
        b2.letter('s', p2)
        assertEquals("tiếng", p2.text)            // KHÔNG "tiến#" như khi dùng ⌫
    }

    @Test fun undoPlainLetterAndCircumflex() {
        val b = bridge(); val p = MockProxy()
        for (c in "tie") b.letter(c, p)
        b.letter('e', p)                         // tie + e → tiê (xoá e, chèn ê)
        assertEquals("tiê", p.text)
        assertTrue(b.undoLastLetter(p))
        assertEquals("tie", p.text); assertEquals("tie", b.composedWord)
        b.letter('v', p)
        assertTrue(b.undoLastLetter(p))
        assertEquals("tie", p.text)
    }

    @Test fun undoRefusesWhenContextChanged() {
        val b = bridge(); val p = MockProxy()
        for (c in "tieng") b.letter(c, p)
        b.letter('s', p)
        p.sb.setLength(0); p.sb.append("khác")   // ô đổi mà không được báo
        assertFalse(b.undoLastLetter(p))
        assertEquals("khác", p.text)
    }

    @Test fun undoOnlyOnceAndOnlyRightAfterLetter() {
        val b = bridge(); val p = MockProxy()
        b.letter('a', p)
        assertTrue(b.undoLastLetter(p))
        assertFalse(b.undoLastLetter(p))
        b.letter('a', p); b.boundary(" ", p)
        assertFalse(b.undoLastLetter(p))
        b.letter('b', p); b.backspace(p)
        assertFalse(b.undoLastLetter(p))
        val off = EngineBridge(); off.letter('a', p)
        assertFalse(off.undoLastLetter(p))      // tắt ⇒ không checkpoint
    }

    @Test fun undoReEditSeedRestoresScreen() {
        val b = bridge(); val p = MockProxy()
        p.sb.append("chao")                       // từ có sẵn, con trỏ cuối từ
        b.letter('f', p)                          // seed lại từ ⇒ chào
        assertEquals("chào", p.text)
        assertTrue(b.undoLastLetter(p))
        assertEquals("chao", p.text)
        assertFalse(b.isComposing)
    }

    // ---- luồng session ----

    private val layout = SwipeLayout.qwerty(keyWidth = 36f, rowHeight = 54f)
    private val decoder = SwipeDecoder().also { it.setLayout(layout) }

    private fun session(traits: FieldTraits = FieldTraits()): KeyboardSession {
        val s = KeyboardSession(UserLangModel(), null) { 0L }
        s.startInput(KeyboardSettings(), traits)
        s.setSwipeTyping(true)
        return s
    }

    private fun KeyboardSession.type(p: TextProxy, keys: String) {
        for (c in keys) handle(when (c) { ' ' -> Key.Space; ',', '.' -> Key.Text(c.toString()); else -> Key.Letter(c) }, p)
    }

    /** Chạm xuống chữ đầu (chèn ngay) → thành vuốt (huỷ) → nhấc tay (decode + chèn). */
    private fun KeyboardSession.swipe(p: TextProxy, word: String, case: SwipeSuggest.Case = SwipeSuggest.Case.LOWER,
                                      first: Char = word[0]): SwipeChoice {
        handle(Key.Letter(if (case == SwipeSuggest.Case.LOWER) first else first.uppercaseChar()), p)
        assertTrue("huỷ chữ đầu", undoLastLetter(p))
        val path = SwipeSim(7).path(word, layout, sigma = 0.0, jitter = 0.0)
        val ctx = swipeContext()
        val choice = SwipeSuggest.choose(decoder.decode(path, SwipeSuggest.TOP_K, ctx.folded), ctx.word, case)
        assertNotNull(choice)
        commitSwipe(choice!!, p)
        return choice
    }

    @Test fun swipeInSentenceSpacesAndPunctuation() {
        val s = session(); val p = MockProxy()
        s.type(p, "tooi")                         // đang soạn "tôi"
        s.swipe(p, "viet")
        assertEquals("tôi viết", p.text)          // từ đang soạn được chốt + dấu cách treo
        s.type(p, ",")
        assertEquals("tôi viết,", p.text)         // dấu câu dính sát
        s.swipe(p, "nam")
        assertTrue(p.text, p.text.startsWith("tôi viết, n"))
        s.type(p, " ")
        s.swipe(p, "rat")
        assertFalse(p.text, p.text.contains("  "))   // sau space của user: không thêm space
    }

    @Test fun swipeAtFieldStartAndAfterNewlineNoLeadingSpace() {
        val s = session(); val p = MockProxy()
        val c = s.swipe(p, "viet", SwipeSuggest.Case.FIRST)
        assertEquals("Viết", c.word)
        assertEquals("Viết", p.text)
        p.sb.setLength(0); p.sb.append("a\n"); s.externalSelectionChange()
        s.swipe(p, "viet")
        assertEquals("a\nviết", p.text)
    }

    @Test fun firstLetterUndoneCleanlyEvenTelexKey() {
        val s = session(); val p = MockProxy()
        s.type(p, "tieng")
        s.swipe(p, "sao")                         // chạm s ⇒ "tiếng" rồi huỷ
        assertTrue(p.text, p.text.startsWith("tieng "))
        assertFalse(p.text.contains("tiếng"))
        assertEquals(1, p.text.count { it == ' ' })
    }

    @Test fun firstBackspaceDeletesWholeSwipedWord() {
        val s = session(); val p = MockProxy()
        s.type(p, "tooi ")
        s.swipe(p, "viet")
        assertEquals("tôi viết", p.text)
        s.handle(Key.Backspace, p)
        assertEquals("tôi ", p.text)
        s.handle(Key.Backspace, p)                // sau đó ⌫ như thường
        assertEquals("tôi", p.text)
    }

    @Test fun telexKeyAfterSwipeChangesTone() {
        val s = session(); val p = MockProxy()
        s.swipe(p, "viet")
        assertEquals("viết", p.text)
        s.handle(Key.Letter('j'), p)              // phím dấu Telex sửa từ vuốt
        assertEquals("việt", p.text)
        s.handle(Key.Backspace, p)                // không còn là từ vuốt ⇒ ⌫ engine thường
        assertNotEquals("", p.text)
    }

    @Test fun alternativesReplaceAndLearnOnCommit() {
        val s = session(); val p = MockProxy()
        s.swipe(p, "viet")
        val alts = s.swipeAlternatives!!
        assertTrue(alts.toString(), "việt" in alts)
        assertEquals(alts, s.suggestionsNow(p)!!.nextWords)
        s.acceptSuggestion("việt", p)
        assertEquals("việt", p.text)
        assertTrue("viết" in s.swipeAlternatives!!)  // đổi lại được
        s.handle(Key.Backspace, p)                   // vẫn là từ vuốt: ⌫ xoá cả từ
        assertEquals("", p.text)
        s.swipe(p, "viet")
        s.acceptSuggestion("việt", p)
        s.type(p, " ")
        assertEquals("việt ", p.text)
        assertTrue(s.langModel.count("việt") > 0)
        assertNull(s.swipeAlternatives)
    }

    @Test fun swipeAfterSwipeCommitsAndLearnsFirst() {
        val s = session(); val p = MockProxy()
        s.swipe(p, "viet")
        s.swipe(p, "nam")
        assertTrue(p.text, p.text.startsWith("viết n"))
        assertTrue(s.langModel.count("viết") > 0)
    }

    @Test fun leadingSpaceRule() {
        assertFalse(SwipeSuggest.needsLeadingSpace(null))
        assertFalse(SwipeSuggest.needsLeadingSpace(""))
        assertTrue(SwipeSuggest.needsLeadingSpace("abc"))
        assertTrue(SwipeSuggest.needsLeadingSpace("abc,"))
        assertTrue(SwipeSuggest.needsLeadingSpace("abc."))
        assertFalse(SwipeSuggest.needsLeadingSpace("abc "))
        assertFalse(SwipeSuggest.needsLeadingSpace("abc\n"))
        assertFalse(SwipeSuggest.needsLeadingSpace("("))
        assertFalse(SwipeSuggest.needsLeadingSpace("“"))
    }

    @Test fun foldMatchesLexicon() {
        assertEquals("duong", SwipeSuggest.fold("Đường"))
        assertEquals("viet", SwipeSuggest.fold("việt"))
    }
}
