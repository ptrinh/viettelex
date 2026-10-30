package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** Hành vi controller iOS (KeyboardViewController) — port logic thuần. */
class KeyboardSessionTests {
    @Before fun setUp() = TestAssets.install()

    private class FakeClip(var text: String? = null) : ClipboardSource {
        override var changeCount = 0
        override fun hasText() = text != null
        override fun readText() = text
        fun copy(s: String) { text = s; changeCount++ }
    }

    private var now = 1_000_000L
    private val clip = FakeClip()
    private fun session(settings: KeyboardSettings = KeyboardSettings(),
                        traits: FieldTraits = FieldTraits(capSentences = true)): KeyboardSession {
        val s = KeyboardSession(UserLangModel(), clip) { now }
        s.startInput(settings, traits)
        return s
    }

    private fun KeyboardSession.typeKeys(p: TextProxy, keys: String) {
        for (c in keys) handle(if (c == ' ') Key.Space else Key.Letter(c), p)
    }

    @Test fun testEmptyFieldShowsTop3Seeds() {
        val s = session(); val p = MockProxy()
        assertEquals(true, s.updateAutoShift(p))
        val set = s.suggestionsNow(p)!!
        assertEquals(listOf("Em", "Anh", "Tôi"), set.nextWords)   // đầu câu ⇒ viết hoa
    }

    /**
     * #113: thanh địa chỉ / ô tìm kiếm (Firefox: "bình" ⇒ "Thường | Tĩnh | Dương") — gợi ý chữ
     * thường: không hoa đầu câu, không tên riêng DisplayCase ("bình" → "dương" chứ không "Dương").
     */
    @Test fun testAddressFieldSuggestionsLowercase() {
        val traits = FieldTraits(capSentences = true, urlField = true, lowercaseSuggestions = true)
        val s = session(traits = traits); val p = MockProxy()
        assertNull("không auto-shift đầu ô", s.updateAutoShift(p))
        assertFalse(s.autoShiftOn)
        assertEquals(listOf("em", "anh", "tôi"), s.suggestionsNow(p)!!.nextWords)
        s.typeKeys(p, "binhf ")
        assertEquals("bình ", p.text)
        s.updateAutoShift(p)
        val next = s.suggestionsNow(p)!!.nextWords
        assertTrue(next.isNotEmpty())
        assertEquals(next.map { it.lowercase() }, next)
        // Ô thường cùng ngữ cảnh: tên riêng vẫn viết hoa (đối chứng).
        val n = session(traits = FieldTraits()); val q = MockProxy()
        n.typeKeys(q, "binhf ")
        val normal = n.suggestionsNow(q)!!.nextWords
        assertEquals(normal.map { it.lowercase() }, next)
        // Đang soạn: gợi ý hoàn tất cũng chữ thường.
        s.typeKeys(p, "duo")
        val set = s.suggestionsNow(p)!!
        for (w in listOfNotNull(set.word, set.word2)) assertEquals(w.lowercase(), w)
    }

    /** Ô trước bật auto-shift, ô địa chỉ kế tiếp hạ shift đó (không còn sót hoa). */
    @Test fun testAddressFieldDropsStaleAutoShift() {
        val s = session(); val p = MockProxy()
        assertEquals(true, s.updateAutoShift(p))
        s.startInput(KeyboardSettings(), FieldTraits(capSentences = true, lowercaseSuggestions = true))
        assertEquals(false, s.updateAutoShift(p))
        assertFalse(s.autoShiftOn)
        assertEquals(listOf("em", "anh", "tôi"), s.suggestionsNow(p)!!.nextWords)
    }

    @Test fun testIdleFlagOnlyForEmptyContext() {
        // #113: ô trống ⇒ idle (strip vẫn hiện icon con trỏ/📋); sau một từ / đang soạn ⇒ không.
        val s = session(traits = FieldTraits()); val p = MockProxy()
        assertTrue(s.suggestionsNow(p)!!.idle)
        s.typeKeys(p, "camr ")
        assertFalse(s.suggestionsNow(p)!!.idle)
        val s2 = session(traits = FieldTraits()); val p2 = MockProxy()
        s2.typeKeys(p2, "ng")
        assertFalse(s2.suggestionsNow(p2)!!.idle)
    }

    @Test fun testNextWordsAfterSpace() {
        val s = session(traits = FieldTraits()); val p = MockProxy()
        s.typeKeys(p, "camr ")
        assertEquals("cảm ", p.text)
        assertEquals("ơn", s.suggestionsNow(p)!!.nextWords.first())
    }

    @Test fun testComposingLiteralSlotAndCandidates() {
        val s = session(traits = FieldTraits()); val p = MockProxy()
        s.typeKeys(p, "nguoi")
        val set = s.suggestionsNow(p)!!
        assertEquals("nguoi", set.literal)            // predicted == composed ⇒ raw
        assertEquals("người", set.word)
    }

    @Test fun testAcceptWordReplacesAndAddsSpace() {
        val s = session(traits = FieldTraits()); val p = MockProxy()
        s.typeKeys(p, "nguoi")
        val before = s.langModel.count("người")
        s.acceptSuggestion("người", p)
        assertEquals("người ", p.text)
        assertEquals(before + 2, s.langModel.count("người"))
        assertFalse(s.bridge.isComposing)
    }

    @Test fun testAdjacentFixWhenNoCandidates() {
        val s = session(traits = FieldTraits()); val p = MockProxy()
        s.typeKeys(p, "ohims")
        assertEquals("phím", s.suggestionsNow(p)!!.word)
    }

    /** Bug 27/09: gõ "casn" bar chỉ có "casn" | cánh | cắn — không có "cân" để chạm. */
    @Test fun testToneSlipOffersIntendedWord() {
        val s = session(traits = FieldTraits()); val p = MockProxy()
        s.typeKeys(p, "casn")
        val set = s.suggestionsNow(p)!!
        assertEquals("cân", set.word2)
        s.acceptSuggestion(set.word2!!, p)
        assertEquals("cân ", p.text)
        val off = session(KeyboardSettings(autoFixAdjacent = false), FieldTraits()); val p2 = MockProxy()
        off.typeKeys(p2, "casn")
        assertTrue(off.suggestionsNow(p2)!!.let { it.word != "cân" && it.word2 != "cân" })
    }

    @Test fun testEmailAndTldRules() {
        val s = session(traits = FieldTraits()); val p = MockProxy()
        s.typeKeys(p, "phuc")
        s.handle(Key.Text("@"), p)
        assertEquals(KeyboardSession.EMAIL_SUFFIXES, s.suggestionsNow(p)!!.nextWords)
        s.acceptSuggestion("gmail.com", p)
        assertEquals("phuc@gmail.com", p.text)          // fragment: không space
        val p2 = MockProxy(); val s2 = session(traits = FieldTraits())
        s2.typeKeys(p2, "github"); s2.handle(Key.Text("."), p2)
        assertEquals(KeyboardSession.DOMAIN_TLDS, s2.suggestionsNow(p2)!!.nextWords)
    }

    @Test fun testDoubleSpacePeriod() {
        val s = session(traits = FieldTraits()); val p = MockProxy()
        s.typeKeys(p, "xin ")
        s.handle(Key.DoubleSpacePeriod, p)
        assertEquals("xin. ", p.text)
        // đầu ô: không thành ". "
        val p2 = MockProxy(); val s2 = session(traits = FieldTraits())
        s2.handle(Key.Space, p2); s2.handle(Key.DoubleSpacePeriod, p2)
        assertEquals("  ", p2.text)
    }

    @Test fun testAutoShiftRules() {
        assertTrue(KeyboardSession.autoShiftFor(""))
        assertTrue(KeyboardSession.autoShiftFor("Xong. "))
        assertTrue(KeyboardSession.autoShiftFor("Hả? "))
        assertTrue(KeyboardSession.autoShiftFor("a\n"))
        assertFalse(KeyboardSession.autoShiftFor("xin "))
        assertFalse(KeyboardSession.autoShiftFor("Xong."))
        assertNull(session(traits = FieldTraits(capSentences = false)).updateAutoShift(MockProxy()))
    }

    @Test fun testBackspaceUndoAfterAutoRestore() {
        val s = session(traits = FieldTraits()); val p = MockProxy()
        // "test" (collision, "tét" hợp lệ ⇒ restore ở boundary). Không còn dùng "google":
        // eager English restore (18/10/2026) đưa nó về raw giữa từ ⇒ không có restore để undo.
        s.typeKeys(p, "test ")
        val composed = "tét"                        // engine restore tét → test
        assertEquals("test ", p.text)
        s.handle(Key.Backspace, p)
        val set = s.suggestionsNow(p)!!
        assertEquals(composed, set.literal)
        assertEquals("test", p.text)
        s.acceptSuggestion(composed, p)
        assertEquals("$composed ", p.text)
    }

    /** Viết tắt "NAS" (NÁ hiếm ⇒ khôi phục): ⌫ ngay sau mời lại "NÁ" như mọi lần khôi phục. */
    @Test fun testBackspaceUndoAfterAcronymRestore() {
        val s = session(traits = FieldTraits()); val p = MockProxy()
        s.typeKeys(p, "NAS ")
        assertEquals("NAS ", p.text)
        s.handle(Key.Backspace, p)
        assertEquals("NÁ", s.suggestionsNow(p)!!.literal)
        s.acceptSuggestion("NÁ", p)
        assertEquals("NÁ ", p.text)
    }

    @Test fun testPasteOfferConditions() {
        val s = session(traits = FieldTraits()); val p = MockProxy()
        assertFalse(s.suggestionsNow(p)!!.paste)       // clipboard trống
        clip.copy("copied"); s.invalidatePasteCache()
        assertTrue(s.suggestionsNow(p)!!.paste)
        s.acceptSuggestion(SuggestionSet.PASTE_TOKEN, p)
        assertEquals("copied", p.text)
        s.invalidatePasteCache()
        assertFalse(s.suggestionsNow(p)!!.paste)       // đã dùng / trước con trỏ không trắng
        val p2 = MockProxy(); clip.copy("new"); s.invalidatePasteCache()
        assertTrue(s.suggestionsNow(p2)!!.paste)       // thấy đổi lúc này
        now += 181_000; s.invalidatePasteCache()
        assertFalse(s.suggestionsNow(p2)!!.paste)      // quá 180 s kể từ lần thấy đổi
        clip.copy("again"); s.invalidatePasteCache()
        assertTrue(s.suggestionsNow(p2)!!.paste)
        now += 1000; clip.text = null                  // cache 2 s
        assertTrue(s.suggestionsNow(p2)!!.paste)
    }

    @Test fun testStaleBackgroundResultDropped() {
        val s = session(traits = FieldTraits()); val p = MockProxy()
        s.typeKeys(p, "ng")
        val plan = s.requestSuggestions(p) as SuggestionPlan.Background
        val r = plan.job.compute()
        s.handle(Key.Letter('u'), p)                   // phím mới tới trước
        assertNull(s.completeSuggestions(plan.job, r))
    }

    @Test fun testCollapsedBarStopsPipeline() {
        val s = session(traits = FieldTraits()); val p = MockProxy()
        s.barCollapsed = true
        assertNull(s.suggestionsNow(p))
        val sec = session(traits = FieldTraits(isSecure = true))
        assertFalse(sec.suggestionsActive)
    }

    @Test fun testTemplateInsertAndDeleteWord() {
        val s = session(traits = FieldTraits()); val p = MockProxy()
        s.typeKeys(p, "xin chao")
        s.insertTemplate("Chúc ngủ ngon", p)
        assertEquals("xin Chúc ngủ ngon", p.text)
        assertFalse(s.bridge.isComposing)
        p.insertText("  ")
        s.deleteWordBackward(p)
        assertEquals("xin Chúc ngủ ", p.text)
        s.handle(Key.ClearField, p)
        assertEquals("", p.text)
    }

    @Test fun testLearnsCommittedWordsAndNotSecure() {
        val s = session(traits = FieldTraits()); val p = MockProxy()
        val before = s.langModel.count("việt")
        s.typeKeys(p, "vieetj ")
        assertEquals(before + 1, s.langModel.count("việt"))
        val sec = KeyboardSession(UserLangModel(), null) { now }
        sec.startInput(KeyboardSettings(), FieldTraits(isSecure = true))
        val sp = MockProxy(isSecureField = true)
        for (c in "vieetj ") sec.handle(if (c == ' ') Key.Space else Key.Letter(c), sp)
        assertEquals("vieetj ", sp.text)
        assertEquals(0, sec.langModel.count("vieetj"))
    }

    @Test fun testResetAtChangeReloadsModel() {
        val s = session(traits = FieldTraits()); val p = MockProxy()
        val seeded = s.langModel.count("việt")
        s.typeKeys(p, "vieetj ")
        assertEquals(seeded + 1, s.langModel.count("việt"))
        s.startInput(KeyboardSettings(userlmResetAt = 123), FieldTraits())
        assertEquals(seeded, s.langModel.count("việt"))
        assertTrue(s.langModel.topWords(3).isNotEmpty())   // seed lại
    }

    @Test fun testSignatureStable() {
        val a = SuggestionSet(word = "a", emojis = listOf("x"))
        assertEquals(a.signature(), a.copy().signature())
        assertTrue(a.signature() != a.copy(word = "b").signature())
        assertNotNull(SuggestionSet().signature())
    }

    /** Ô không cho đọc ngược (getTextBeforeCursor = null). */
    private class NullCtxProxy : TextProxy {
        val inner = MockProxy()
        override val isSecure: Boolean get() = false
        override fun insertText(text: String) = inner.insertText(text)
        override fun deleteCodePoints(count: Int) = inner.deleteCodePoints(count)
        override fun deleteBackward() = inner.deleteBackward()
        override fun contextBeforeInput(): String? = null
        override fun clearAll() = inner.clearAll()
    }

    @Test fun testNullContextKeepsShift() {
        // Regression: context null bị coi là ô trống ⇒ bật shift sai giữa câu.
        val s = session(traits = FieldTraits(capSentences = true)); val p = NullCtxProxy()
        assertEquals(false, s.updateAutoShift(p))          // initialCaps=false, chưa gõ
        s.typeKeys(p, "xin ")
        assertNull(s.updateAutoShift(p))                    // đã gõ: không đoán
        val s2 = session(traits = FieldTraits(capSentences = true, initialCaps = true))
        assertEquals(true, s2.updateAutoShift(NullCtxProxy()))   // editor báo initialCapsMode
        val chars = session(traits = FieldTraits(capCharacters = true))
        assertEquals(true, chars.updateAutoShift(NullCtxProxy()))
    }

    /** Công tắc "Tự động viết hoa đầu câu" TẮT: không auto-shift, không đọc context cho nó. */
    @Test fun testAutoCapitalizeOffNeverShifts() {
        for (t in listOf(FieldTraits(capSentences = true, initialCaps = true), FieldTraits(capWords = true),
                         FieldTraits(capCharacters = true))) {
            val s = session(KeyboardSettings(autoCapitalize = false), t); val p = MockProxy()
            fun shiftNoRead(): Boolean? {
                val r0 = p.contextReads
                return s.updateAutoShift(p).also { assertEquals(r0, p.contextReads) }
            }
            assertNull(shiftNoRead())                                 // ô trống: không bật shift
            assertFalse(s.handle(Key.Space, p).needsAutoShift)        // IME khỏi hẹn auto-shift
            s.typeKeys(p, "xin"); s.handle(Key.Text("."), p); s.handle(Key.Space, p)
            assertNull(shiftNoRead())                                 // sau ". " vẫn không
            assertFalse(s.handle(Key.Newline, p).needsAutoShift)
            assertNull(shiftNoRead())
            assertFalse(s.autoShiftOn)
        }
        // BẬT: như cũ.
        val on = session(); val p = MockProxy()
        assertEquals(true, on.updateAutoShift(p))
        on.typeKeys(p, "xin"); on.handle(Key.Text("."), p); on.handle(Key.Space, p)
        assertEquals(true, on.updateAutoShift(p))
        assertTrue(on.handle(Key.Space, p).needsAutoShift)
    }

    /** Tắt giữa chừng (ô Thử gõ) khi shift đang do auto bật ⇒ hạ một lần, rồi thôi đụng shift. */
    @Test fun testAutoCapitalizeTurnedOffLowersOnce() {
        val s = session(); val p = MockProxy()
        assertEquals(true, s.updateAutoShift(p))
        s.autoCapitalize = false
        assertEquals(false, s.updateAutoShift(p))
        assertNull(s.updateAutoShift(p))
    }

    @Test fun testCapModes() {
        assertTrue(KeyboardSession.autoShiftFor("nguyễn ", CapMode.WORDS))
        assertTrue(KeyboardSession.autoShiftFor("", CapMode.WORDS))
        assertTrue(KeyboardSession.autoShiftFor("nói \"", CapMode.WORDS))
        assertFalse(KeyboardSession.autoShiftFor("nguyễn", CapMode.WORDS))
        assertTrue(KeyboardSession.autoShiftFor("abc", CapMode.CHARACTERS))
        assertFalse(KeyboardSession.autoShiftFor("xin ", CapMode.SENTENCES))
        assertEquals(CapMode.CHARACTERS, KeyboardSession.capMode(FieldTraits(capSentences = true, capCharacters = true)))
        assertEquals(CapMode.NONE, KeyboardSession.capMode(FieldTraits()))
        // ô CAP_WORDS: sau space bật shift; CAP_CHARACTERS: phím chữ cũng xin auto-shift lại
        val w = session(traits = FieldTraits(capWords = true)); val p = MockProxy()
        w.typeKeys(p, "an ")
        assertEquals(true, w.updateAutoShift(p))
        val c = session(traits = FieldTraits(capCharacters = true))
        assertTrue(c.handle(Key.Letter('A'), MockProxy()).needsAutoShift)
        assertFalse(session(traits = FieldTraits()).handle(Key.Letter('a'), MockProxy()).needsAutoShift)
    }

    @Test fun testNoPersonalizedLearning() {
        // Regression: IME_FLAG_NO_PERSONALIZED_LEARNING (Chrome ẩn danh) không được học từ.
        val s = session(traits = FieldTraits(noLearning = true)); val p = MockProxy()
        val before = s.langModel.count("người")
        s.typeKeys(p, "nguoi ")
        s.typeKeys(p, "nguoi"); s.acceptSuggestion("người", p)
        assertEquals(before, s.langModel.count("người"))
        assertNotNull(s.suggestionsNow(p))                  // gợi ý vẫn hiện
        // ô thường cùng session: học lại
        s.startInput(KeyboardSettings(), FieldTraits())
        s.typeKeys(p, "nguoi"); s.acceptSuggestion("người", p)
        assertEquals(before + 2, s.langModel.count("người"))
    }

    @Test fun testWriteModeTable() {
        assertEquals(WriteMode.KEY_ONLY, WriteMode.forPackage("com.xiaomi.wps"))
        assertEquals(WriteMode.KEY_ONLY, WriteMode.forPackage("com.xiaomi.wpsoffice"))
        assertEquals(WriteMode.KEY_ONLY, WriteMode.forPackage("com.huawei.hsl"))
        assertEquals(WriteMode.KEY_ONLY, WriteMode.forPackage("cn.wps.huawei"))
        assertEquals(WriteMode.DEL_VIA_KEY_EVENT, WriteMode.forPackage("com.onlyoffice.documents"))
        assertEquals(WriteMode.COMMIT, WriteMode.forPackage("com.huawei.hslx"))
        assertEquals(WriteMode.COMMIT, WriteMode.forPackage(null))
        assertEquals(WriteMode.COMMIT, WriteMode.forPackage("com.android.chrome"))
        assertEquals(WriteMode.KEY_ONLY, FieldTraits(packageName = "cn.wps.huawei").writeMode)
    }

    // MARK: chip số (NumberChips)

    /** Chữ số / ký hiệu → Key.Text (như phím số), chữ cái → Key.Letter, ' ' → Space. */
    private fun KeyboardSession.typeMixed(p: TextProxy, keys: String) {
        for (c in keys) handle(when {
            c == ' ' -> Key.Space
            c.isLetter() -> Key.Letter(c)
            else -> Key.Text(c.toString())
        }, p)
    }

    @Test fun testNumberChipReadsDigitsAndKeepsNextWords() {
        val s = session(traits = FieldTraits()); val p = MockProxy()
        s.typeMixed(p, "gia 1250000")
        val set = s.suggestionsNow(p)!!
        assertEquals("một triệu hai trăm năm mươi nghìn", set.number)
        assertEquals(3, set.nextWords.size)                   // chip chỉ thêm 1 slot, không lấy mất gợi ý
        s.acceptSuggestion(SuggestionSet.NUMBER_TOKEN, p)
        assertEquals("gia một triệu hai trăm năm mươi nghìn", p.text)
    }

    /** Công tắc chip số TẮT: không chip, và lượt gợi ý sau chữ số không đọc context cho nó. */
    @Test fun testNumberChipSwitchOffCostsNothing() {
        val on = session(traits = FieldTraits()); val pOn = MockProxy()
        on.typeMixed(pOn, "gia 1250000")
        pOn.contextReads = 0
        assertNotNull(on.suggestionsNow(pOn)!!.number)
        val readsOn = pOn.contextReads
        val off = session(KeyboardSettings(numberChips = false), FieldTraits()); val p = MockProxy()
        off.typeMixed(p, "gia 1250000")
        p.contextReads = 0
        assertNull(off.suggestionsNow(p)!!.number)
        assertTrue("tắt chip số phải đọc context ít hơn ($readsOn → ${p.contextReads})", p.contextReads < readsOn)
        assertTrue(KeyboardSettings().numberChips)
        assertFalse(KeyboardSettings.load { if (it == Keys.NUMBER_CHIPS) false else null }.numberChips)
    }

    @Test fun testNumberChipShorthandChainsToWords() {
        val s = session(traits = FieldTraits()); val p = MockProxy()
        s.typeMixed(p, "1tr2")
        assertEquals("1.200.000 ₫", s.suggestionsNow(p)!!.number)
        s.acceptSuggestion(SuggestionSet.NUMBER_TOKEN, p)
        assertEquals("1.200.000 ₫", p.text)
        assertEquals("Một triệu hai trăm nghìn đồng", s.suggestionsNow(p)!!.number)   // đầu ô ⇒ viết hoa
    }

    @Test fun testNumberChipWhileComposingKeepsLiteral() {
        val s = session(traits = FieldTraits()); val p = MockProxy()
        s.typeMixed(p, "50k")
        assertTrue(s.bridge.isComposing)
        val set = s.suggestionsNow(p)!!
        assertEquals("k", set.literal)
        assertEquals("50.000 ₫", set.number)
        s.acceptSuggestion(SuggestionSet.NUMBER_TOKEN, p)
        assertEquals("50.000 ₫", p.text)
        assertFalse(s.bridge.isComposing)
    }

    // MARK: kết quả phép tính (MathResults)

    @Test fun testMathChipInsertsAfterEquals() {
        val s = session(traits = FieldTraits()); val p = MockProxy()
        s.typeMixed(p, "12*3=")
        val set = s.suggestionsNow(p)!!
        assertEquals("36", set.math)
        assertNull(set.number)                                 // chip số không nhận "…="
        s.acceptSuggestion(SuggestionSet.MATH_TOKEN, p)
        assertEquals("12*3=36", p.text)
        assertNull(s.suggestionsNow(p)!!.math)
    }

    /** Phím khác sau "=" ⇒ mất chip; phím chữ không đọc context vì chip phép tính. */
    @Test fun testMathChipOnlyRightAfterEquals() {
        val s = session(traits = FieldTraits()); val p = MockProxy()
        s.typeMixed(p, "(1+2)*3=")
        assertEquals("9", s.suggestionsNow(p)!!.math)
        s.typeMixed(p, "+")
        assertNull(s.suggestionsNow(p)!!.math)
        val on = session(traits = FieldTraits()); val pOn = MockProxy()
        val off = session(KeyboardSettings(mathResults = false), FieldTraits()); val pOff = MockProxy()
        on.typeMixed(pOn, "xin chao"); off.typeMixed(pOff, "xin chao")
        pOn.contextReads = 0; pOff.contextReads = 0
        on.suggestionsNow(pOn); off.suggestionsNow(pOff)
        assertEquals(pOff.contextReads, pOn.contextReads)
    }

    /**
     * Field report 18/10/2026 ("dấu bằng để rất sâu"): gõ "12*3" (không "=") ⇒ chip "= 36" ở slot
     * đầu; chạm ⇒ "12*3 = 36". Ngày "12/10" không; công tắc tắt ⇒ không, và không đọc thêm context.
     */
    @Test fun testImplicitMathChip() {
        val s = session(traits = FieldTraits()); val p = MockProxy()
        s.typeMixed(p, "12*3")
        assertEquals("= 36", s.suggestionsNow(p)!!.math)
        s.acceptSuggestion(SuggestionSet.MATH_TOKEN, p)
        assertEquals("12*3 = 36", p.text)
        assertNull(s.suggestionsNow(p)!!.math)
        val d = session(traits = FieldTraits()); val pd = MockProxy()
        d.typeMixed(pd, "12/10")
        assertNull(d.suggestionsNow(pd)!!.math)
        // ⌫ về một phép tính ⇒ chip hiện lại.
        val b = session(traits = FieldTraits()); val pb = MockProxy()
        b.typeMixed(pb, "12*35")
        assertEquals("= 420", b.suggestionsNow(pb)!!.math)
        b.handle(Key.Backspace, pb)
        assertEquals("= 36", b.suggestionsNow(pb)!!.math)
        // Công tắc tắt: không chip, số lượt đọc context y như chưa có tính năng (chỉ chip số đọc).
        val off = session(KeyboardSettings(mathResults = false), FieldTraits()); val pOff = MockProxy()
        val noNum = session(KeyboardSettings(mathResults = false, numberChips = false), FieldTraits()); val pN = MockProxy()
        off.typeMixed(pOff, "12*3"); noNum.typeMixed(pN, "12*3")
        assertNull(off.suggestionsNow(pOff)?.math)
        pN.contextReads = 0
        noNum.suggestionsNow(pN)
        val on = session(KeyboardSettings(numberChips = false), FieldTraits()); val pOn = MockProxy()
        on.typeMixed(pOn, "12*3"); pOn.contextReads = 0
        on.suggestionsNow(pOn)
        assertTrue("bật ⇒ có đọc context cho chip ngầm", pOn.contextReads > pN.contextReads)
    }

    @Test fun testMathChipSwitchAndFieldGate() {
        val off = session(KeyboardSettings(mathResults = false), FieldTraits()); val p = MockProxy()
        off.typeMixed(p, "12*3=")
        assertNull(off.suggestionsNow(p)?.math)
        val url = session(traits = FieldTraits(urlField = true)); val pu = MockProxy()
        url.typeMixed(pu, "12*3=")
        assertNull(url.suggestionsNow(pu)?.math)
        assertTrue(KeyboardSettings().mathResults)
        assertFalse(KeyboardSettings.load { if (it == Keys.MATH_RESULTS) false else null }.mathResults)
    }

    @Test fun testMathChipSkipsWhenTextChanged() {
        val s = session(traits = FieldTraits()); val p = MockProxy()
        s.typeMixed(p, "2+2=")
        assertEquals("4", s.suggestionsNow(p)!!.math)
        p.sb.append("5")                                       // host đổi chữ sau lượt gợi ý
        s.acceptSuggestion(SuggestionSet.MATH_TOKEN, p)
        assertEquals("2+2=5", p.text)
    }

    /**
     * ⌫ mở cổng chip số (không biết vừa xoá gì) — nhưng sau một lượt đọc không thấy chữ số thì
     * phím chữ tiếp theo KHÔNG đọc lại context cho chip số (trước: copy ≤256 ký tự mỗi phím).
     */
    @Test fun testNumberChipGateClosesWithoutDigits() {
        val s = session(traits = FieldTraits()); val p = MockProxy()
        s.typeMixed(p, "xin chao ban ")
        s.handle(Key.Backspace, p)
        s.suggestionsNow(p)
        val nums = session(KeyboardSettings(numberChips = false), FieldTraits()); val q = MockProxy()
        nums.typeMixed(q, "xin chao ban ")
        nums.handle(Key.Backspace, q)
        nums.suggestionsNow(q)
        // Cùng chuỗi phím chữ: số lần đọc context phải bằng phiên TẮT chip số (0 đọc thêm vì chip).
        p.contextReads = 0; q.contextReads = 0
        for (c in "nhe") {
            s.handle(Key.Letter(c), p); s.suggestionsNow(p)
            nums.handle(Key.Letter(c), q); nums.suggestionsNow(q)
        }
        assertEquals(q.contextReads, p.contextReads)
        // Chữ số mới ⇒ cổng mở lại; ⌫ về sát số ⇒ chip hiện lại.
        s.typeMixed(p, " 12")
        assertEquals("mười hai", s.suggestionsNow(p)!!.number)
        s.typeMixed(p, "a")
        s.handle(Key.Backspace, p)
        assertEquals("mười hai", s.suggestionsNow(p)!!.number)
    }

    /** autoShiftFor duyệt ngược (không trim copy) — y hệt bản cũ trên mọi đuôi. */
    @Test fun testAutoShiftForMatchesTrimVersion() {
        fun old(before: String): Boolean {
            val t = before.trim(' ', '\t')
            return before.isEmpty() ||
                (before.endsWith(" ") && (t.endsWith(".") || t.endsWith("!") || t.endsWith("?"))) ||
                before.endsWith("\n")
        }
        val parts = listOf("", " ", "\t", ".", "!", "?", "a", "\n", ",")
        for (a in parts) for (b in parts) for (c in parts) for (d in parts) {
            val s = a + b + c + d
            assertEquals("«$s»", old(s), KeyboardSession.autoShiftFor(s))
        }
    }

    @Test fun testNumberChipTailHasDigit() {
        assertTrue(NumberChips.tailHasDigit("gia 12"))
        assertTrue(NumberChips.tailHasDigit("12 tr "))
        assertTrue(NumberChips.tailHasDigit("50k"))
        assertFalse(NumberChips.tailHasDigit("12 xin chao"))
        assertFalse(NumberChips.tailHasDigit(""))
        assertFalse(NumberChips.tailHasDigit("abc "))
    }

    @Test fun testNumberChipGoneAfterNextWord() {
        val s = session(traits = FieldTraits()); val p = MockProxy()
        s.typeMixed(p, "2 ")
        assertEquals("Hai", s.suggestionsNow(p)!!.number)
        s.typeMixed(p, "nguoi ")
        assertNull(s.suggestionsNow(p)!!.number)
    }

    @Test fun testNumberChipSkipsWhenTextChanged() {
        val s = session(traits = FieldTraits()); val p = MockProxy()
        s.typeMixed(p, "5")
        assertEquals("Năm", s.suggestionsNow(p)!!.number)
        p.sb.append("x")                                       // host đổi chữ sau lượt gợi ý
        s.acceptSuggestion(SuggestionSet.NUMBER_TOKEN, p)
        assertEquals("5x", p.text)                             // không xoá mù
    }

    /** Proxy phân biệt "\n" thật (giữ lâu) với Enter thường (có thể là action "Gửi"). */
    private class EnterProxy : TextProxy {
        val sb = StringBuilder(); var actions = 0
        override fun insertText(text: String) { if (text == "\n") actions++ else sb.append(text) }
        override fun insertLineBreak() { sb.append("\n") }
        override fun deleteCodePoints(count: Int) { repeat(count) { if (sb.isNotEmpty()) sb.setLength(sb.length - 1) } }
        override fun deleteBackward() = deleteCodePoints(1)
        override val isSecure = false
        override fun contextBeforeInput(): String = sb.toString()
        override fun confirmTail(expected: String) = sb.endsWith(expected)
    }

    @Test fun testLineBreakCommitsWordLearnsAndSkipsAction() {
        val s = session(traits = FieldTraits()); val p = EnterProxy()
        val before = s.langModel.count("việt")
        for (c in "vieetj") s.handle(Key.Letter(c), p)
        val out = s.handle(Key.LineBreak, p)
        assertEquals("việt\n", p.sb.toString())
        assertEquals(0, p.actions)
        assertEquals(before + 1, s.langModel.count("việt"))
        assertTrue(out.needsAutoShift)
        // ⌫ sau xuống dòng chỉ xoá "\n", không mở lại từ cũ.
        s.handle(Key.Backspace, p)
        assertEquals("việt", p.sb.toString())
        // Enter thường vẫn đi đường cũ (action).
        s.handle(Key.Newline, p)
        assertEquals(1, p.actions)
    }

    @Test fun testLineBreakPassthroughStillLiteralNewline() {
        val s = session(traits = FieldTraits(passthrough = true)); val p = EnterProxy()
        s.handle(Key.Letter('a'), p)
        s.handle(Key.LineBreak, p)
        assertEquals("a\n", p.sb.toString()); assertEquals(0, p.actions)
    }
}
