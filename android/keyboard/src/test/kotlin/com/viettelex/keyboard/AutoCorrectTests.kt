package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** Tự sửa từ gõ sai (Thử nghiệm) — parity iOS AutoCorrectTests. */
class AutoCorrectTests {
    @Before fun setUp() = TestAssets.install()

    private val bridge = EngineBridge(KeyboardSettings())
    private val center = AutoCorrect.Touch(0f, 0f)
    /** Điểm chạm: giữa phím, trừ phím thứ [i] lệch (dx, dy). */
    private fun touches(raw: String, i: Int = -1, dx: Float = 0f, dy: Float = 0f) =
        List(raw.length) { if (it == i) AutoCorrect.Touch(dx, dy) else center }

    private fun fix(raw: String, t: List<AutoCorrect.Touch> = touches(raw), known: Set<String> = emptySet()) =
        AutoCorrect.correction(raw, t, compose = { bridge.composeTrial(it) },
            frequency = { VNSuggest.frequency(it) },
            hasCompletion = { VNSuggest.matches(it, poolLimit = 1).isNotEmpty() },
            isKnown = { it in known || AutoCorrect.isEnglish(it) })

    @Test fun offByDefault() = assertFalse(KeyboardSettings().autoCorrect)

    @Test fun fixesSlipTowardNeighbor() {
        assertEquals("tôi", fix("tpoi", touches("tpoi", 1, dx = -0.4f)))        // p chạm lệch về o
        assertEquals("Tôi", fix("Tpoi", touches("Tpoi", 1, dx = -0.4f)))
        assertEquals("này", fix("nayd", touches("nayd", 3, dx = 0.35f)))        // d lệch về f (nảy/nãy kém xa)
        assertNull(fix("ohims", touches("ohims", 0, dx = 0.4f)))               // "phím" (87) không đủ phổ biến
    }

    /** Chạm giữa phím (hoặc lệch về phía khác) ⇒ không phải trượt ⇒ không sửa. */
    @Test fun needsTouchEvidence() {
        assertNull(fix("tpoi"))
        assertNull(fix("tpoi", touches("tpoi", 1, dx = 0.4f)))
        assertNull(fix("tpoi", touches("tpo", 1, dx = -0.4f)))                 // thiếu điểm chạm
    }

    @Test fun leavesValidKnownAndShortWordsAlone() {
        assertNull(fix("tooi", touches("tooi", 1, dx = 0.4f)))                 // đã đúng
        assertNull(fix("toi", touches("toi", 1, dx = 0.4f)))                   // không dấu = từ hợp lệ
        assertNull(fix("github", touches("github", 5, dx = 0.4f)))             // tiếng Anh
        assertNull(fix("tpoi", touches("tpoi", 1, dx = -0.4f), known = setOf("tpoi")))   // từ người dùng / từng hoàn tác
        assertNull(fix("kp", touches("kp", 1, dx = -0.4f)))                    // quá ngắn
        assertNull(fix("tp1i", touches("tp1i", 1, dx = -0.4f)))                // có số
    }

    @Test fun evidenceIsProjectionTowardNeighbor() {
        assertEquals(0f, AutoCorrect.evidence(center, 'o', 'p'), 1e-6f)
        assertEquals(0.4f, AutoCorrect.evidence(AutoCorrect.Touch(0.4f, 0f), 'o', 'p'), 1e-6f)
        assertEquals(-0.4f, AutoCorrect.evidence(AutoCorrect.Touch(0.4f, 0f), 'o', 'i'), 1e-6f)
        assertTrue(AutoCorrect.evidence(AutoCorrect.Touch(0f, 0.5f), 'h', 'b') > 0.3f)   // hàng dưới
    }

    @Test fun boundaryCaseAndField() {
        assertTrue(AutoCorrect.triggers(" ")); assertTrue(AutoCorrect.triggers(",")); assertTrue(AutoCorrect.triggers("?"))
        assertFalse(AutoCorrect.triggers(".")); assertFalse(AutoCorrect.triggers("\n")); assertFalse(AutoCorrect.triggers("'"))
        assertTrue(AutoCorrect.isSentenceStart("")); assertTrue(AutoCorrect.isSentenceStart("Xong. "))
        assertFalse(AutoCorrect.isSentenceStart("anh "))
        assertTrue(AutoCorrect.caseAllows("tpoi", false))
        assertTrue(AutoCorrect.caseAllows("Tpoi", true))
        assertFalse(AutoCorrect.caseAllows("Tpoi", false))                      // giữa câu = tên riêng
        assertFalse(AutoCorrect.caseAllows("TPoi", true))
        assertTrue(AutoCorrect.fieldAllows(FieldTraits()))
        assertFalse(AutoCorrect.fieldAllows(FieldTraits(passthrough = true)))
        assertFalse(AutoCorrect.fieldAllows(FieldTraits(isSecure = true)))
        assertFalse(AutoCorrect.fieldAllows(FieldTraits(urlField = true)))
        assertFalse(AutoCorrect.fieldAllows(FieldTraits(capWords = true)))
        assertFalse(AutoCorrect.fieldAllows(FieldTraits(suggestionsAllowed = false)))
    }

    @Test fun rejectedSetPersistsAndCaps() {
        val r = AutoCorrect.Rejected(cap = 2)
        assertTrue(r.add("Tpoi")); assertFalse(r.add("tpoi"))
        assertTrue("TPOI" in r)
        r.add("b"); r.add("c")
        assertFalse("tpoi" in r)                                               // cũ nhất bị đẩy ra
        val back = AutoCorrect.Rejected.decode(r.encode())
        assertTrue("b" in back && "c" in back); assertEquals(2, back.size)
        assertEquals(0, AutoCorrect.Rejected.decode(null).size)
    }

    @Test fun undoChipLeadsTheBar() {
        val set = SuggestionSet(nextWords = listOf("a", "b", "c"), actionLabel = "↩︎ tpoi", action = SuggestionSet.UNDO_AUTOCORRECT_TOKEN)
        val l = SuggestionSlots.arrange(set, undoAsPill = false, bestInMiddle = false) as BarLayout.Slots
        assertEquals(listOf(SuggestionSet.UNDO_AUTOCORRECT_TOKEN, "a", "b"), l.slots.map { it?.payload })
    }

    @Test fun userWordNeedsThreeUses() {
        val m = UserLangModel()
        m.record("anh", null); m.record("anh", null)
        assertFalse(m.isUserWord("anh"))
        m.record("anh", null)
        assertTrue(m.isUserWord("Anh"))
    }

    // MARK: session

    private fun session(on: Boolean = true, traits: FieldTraits = FieldTraits(), settings: KeyboardSettings = KeyboardSettings()) =
        KeyboardSession(UserLangModel(), null).also { it.startInput(settings.copy(autoCorrect = on), traits) }

    /** Gõ [keys]; phím thứ [slip] chạm lệch dx (âm = về bên trái). */
    private fun KeyboardSession.type(p: TextProxy, keys: String, slip: Int = -1, dx: Float = -0.4f, touch: Boolean = true) {
        for ((i, c) in keys.withIndex()) {
            val t = if (!touch) null else if (i == slip) AutoCorrect.Touch(dx, 0f) else center
            handle(if (c == ' ') Key.Space else Key.Letter(c), p, t)
        }
    }

    @Test fun sessionCorrectsAtSpaceAndBackspaceRestores() {
        val s = session(); val p = MockProxy()
        val base = s.langModel.count("tôi")
        s.type(p, "tpoi ", slip = 1)
        assertEquals("tôi ", p.text)
        assertEquals(base + 1, s.langModel.count("tôi"))                       // học từ đã sửa
        assertEquals(0, s.langModel.count("tpoi"))
        s.handle(Key.Backspace, p)
        assertEquals("tpoi ", p.text)                                          // giữ dấu cách như hoàn tác gõ tắt
        assertTrue("tpoi" in s.autoCorrectRejected)
        assertEquals(base, s.langModel.count("tôi"))                           // rút lượt học
        assertEquals(1, s.langModel.count("tpoi"))
        s.type(p, "tpoi ", slip = 1)
        assertEquals("tpoi tpoi ", p.text)                                     // từng hoàn tác ⇒ không sửa lại
    }

    @Test fun sessionChipReverts() {
        val s = session(); val p = MockProxy()
        var saved = 0
        s.onAutoCorrectRejected = { saved++ }
        s.type(p, "tpoi ", slip = 1)
        val set = s.suggestionsNow(p)!!
        assertEquals("↩︎ tpoi", set.actionLabel)
        assertEquals(SuggestionSet.UNDO_AUTOCORRECT_TOKEN, set.action)
        s.acceptSuggestion(SuggestionSet.UNDO_AUTOCORRECT_TOKEN, p)
        assertEquals("tpoi ", p.text)
        assertEquals(1, saved)
        s.type(p, "an ")
        assertFalse(s.suggestionsNow(p)?.action == SuggestionSet.UNDO_AUTOCORRECT_TOKEN)   // chip chỉ sống tới phím kế
    }

    @Test fun sessionOffOrNoTouchDoesNothing() {
        // Tắt + thanh gợi ý tắt ⇒ không ghi điểm chạm (thanh bật thì vẫn ghi cho ô tô nền §8).
        assertFalse(session(on = false, settings = KeyboardSettings(showSuggestions = false)).wantsTouches)
        val off = session(on = false); val p = MockProxy()
        off.type(p, "tpoi ", slip = 1)
        assertEquals("tpoi ", p.text)
        val hw = session(); val q = MockProxy()
        hw.type(q, "tpoi ", touch = false)                                     // bàn phím cứng: không điểm chạm
        assertEquals("tpoi ", q.text)
    }

    @Test fun sessionSkipsFieldsCaseAndGlue() {
        assertFalse(session(traits = FieldTraits(capWords = true)).wantsTouches)          // ô tên
        assertFalse(session(settings = KeyboardSettings(vniMode = true)).wantsTouches)    // VNI
        val s = session(); val q = MockProxy()
        q.insertText("gặp ")
        s.type(q, "Tpoi ", slip = 1)
        assertEquals("gặp Tpoi ", q.text)                                     // hoa giữa câu = tên riêng
        val t = session(); val r = MockProxy()
        r.insertText("a@")
        t.type(r, "tpoi ", slip = 1)
        assertEquals("a@tpoi ", r.text)                                        // dính email/URL
        val u = session(); val w = MockProxy()
        u.type(w, "tpoi", slip = 1); u.handle(Key.Text("."), w)
        assertEquals("tpoi.", w.text)                                          // "." không sửa (tên miền)
        val v = session(); val x = MockProxy()
        v.type(x, "tpoo", slip = 1); v.handle(Key.Backspace, x); v.type(x, "i ")
        assertFalse(x.text.startsWith("tôi"))                                  // ⌫ giữa từ ⇒ không sửa
        val e = session(settings = KeyboardSettings(spaceSwipeLanguage = true)); val y = MockProxy()
        e.toggleLanguage(y)                                                    // chế độ Tiếng Anh
        e.type(y, "tpoi ", slip = 1)
        assertEquals("tpoi ", y.text)
    }
}
