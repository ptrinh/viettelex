package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** Luồng session: chip số trên bar, ghi lịch sử clipboard, chế độ ẩn danh. */
class ClipboardSessionTests {
    // Luồng tính năng (chip STK/OTP là Plus) chạy với paywall mở; gating kiểm ở PlusGateTests.
    @Before fun setUp() { TestAssets.install(); PlusGate.paywallEnabled = false }
    @org.junit.After fun tearDown() { PlusGate.paywallEnabled = PlusConfig.PAYWALL_ENABLED }

    private class FakeClip(var text: String? = null) : ClipboardSource {
        override var changeCount = 0
        var sensitive = false
        override fun hasText() = text != null
        override fun readText() = text
        override fun isSensitive() = sensitive
        fun copy(s: String) { text = s; changeCount++ }
    }

    private var now = 1_000_000L
    private val clip = FakeClip()
    private fun session(settings: KeyboardSettings = KeyboardSettings(),
                        traits: FieldTraits = FieldTraits()): KeyboardSession {
        val s = KeyboardSession(UserLangModel(), clip) { now }
        s.startInput(settings, traits)
        return s
    }

    private fun KeyboardSession.typeKeys(p: TextProxy, keys: String) {
        for (c in keys) handle(if (c == ' ') Key.Space else Key.Letter(c), p)
    }

    @Test fun incognitoManualDoesNotLearn() {
        val s = session(settings = KeyboardSettings(incognito = true)); val p = MockProxy()
        val before = s.langModel.count("người")
        s.typeKeys(p, "nguoi"); s.acceptSuggestion("người", p)
        assertEquals(before, s.langModel.count("người"))
        assertTrue(s.incognito)
        s.startInput(KeyboardSettings(), FieldTraits())
        assertFalse(s.incognito)
        s.typeKeys(p, "nguoi"); s.acceptSuggestion("người", p)
        assertEquals(before + 2, s.langModel.count("người"))
    }

    @Test fun noLearningFlagCountsAsIncognito() {
        assertTrue(session(traits = FieldTraits(noLearning = true)).incognito)
    }

    @Test fun recordClipRules() {
        val s = session()
        clip.copy("xin chào")
        assertFalse(s.recordClip(fieldSecure = false))                    // lịch sử tắt (null)
        s.clipHistory = ClipboardHistory()
        assertTrue(s.recordClip(fieldSecure = false))
        assertFalse(s.recordClip(fieldSecure = false, onlyIfNew = true))  // đã có
        clip.copy("chép trong ô mật khẩu")
        assertFalse(s.recordClip(fieldSecure = true))
        clip.copy("bí mật"); clip.sensitive = true
        assertFalse(s.recordClip(fieldSecure = false))
        clip.sensitive = false
        val inc = session(settings = KeyboardSettings(incognito = true))
        inc.clipHistory = ClipboardHistory()
        clip.copy("ẩn danh")
        assertFalse(inc.recordClip(fieldSecure = false))
        val incFlag = session(traits = FieldTraits(noLearning = true))
        incFlag.clipHistory = ClipboardHistory()
        assertFalse(incFlag.recordClip(fieldSecure = false))
        assertEquals(listOf("xin chào"), s.clipHistory!!.items(now).map { it.text })
    }

    @Test fun clipChipsOnStripAndAccept() {
        val s = session(); val p = MockProxy()
        clip.copy("Ma OTP cua quy khach la 482913")
        val set = s.suggestionsNow(p)!!
        assertTrue(set.paste)
        assertEquals(listOf("Dán OTP 482913"), set.clipChips.map { it.label })
        s.acceptSuggestion(SuggestionSet.CLIP_CHIP_PREFIX + "482913", p)
        assertEquals("482913", p.text)                   // không space, không học
        now += 3000
        s.invalidatePasteCache()
        p.sb.append(' ')
        assertFalse(s.suggestionsNow(p)!!.paste)         // đã dùng ⇒ hết mời
    }

    /** Ô địa chỉ: chip địa chỉ lên đầu; luật không ra ⇒ hỏi AI một lần mỗi clip, kết quả kiểm chống bịa. */
    @Test fun addressFieldRanksChipAndAsksAIOnce() {
        val calls = ArrayList<(String?) -> Unit>()
        var ready = 0
        val s = session(traits = FieldTraits(clipPreference = ClipChip.Kind.ADDRESS)); val p = MockProxy()
        s.clipAddressAI = ClipAddressAI { _, _, done -> calls += done }
        s.onClipAddressReady = { ready++ }
        clip.copy("Nguyễn Văn A, 0976543210, 458 Lê Văn Sỹ, P.14, Q.3, TP.HCM")
        assertEquals(listOf("Dán địa chỉ", "Dán SĐT 0976…"), s.suggestionsNow(p)!!.clipChips.map { it.label })
        assertEquals(0, calls.size)                                   // luật đã ra ⇒ không gọi AI
        clip.copy("Chị Lan 0987654321 nhà ở số 5 ngõ 10 láng hạ đống đa hn nha")
        s.invalidatePasteCache()
        assertEquals(listOf(ClipChip.Kind.PHONE), s.suggestionsNow(p)!!.clipChips.map { it.kind })
        s.suggestionsNow(p)
        assertEquals(1, calls.size)                                   // đang chờ ⇒ không gọi lại
        calls[0]("số 5 ngõ 10 láng hạ đống đa hn")
        assertEquals(1, ready)
        assertEquals(listOf(ClipChip.Kind.ADDRESS, ClipChip.Kind.PHONE), s.suggestionsNow(p)!!.clipChips.map { it.kind })
        assertEquals(1, calls.size)
        // Ô thường: không gọi AI
        val plain = session(); plain.clipAddressAI = ClipAddressAI { _, _, done -> calls += done }
        clip.copy("nhà ở số 7 ngõ 3 láng hạ")
        plain.suggestionsNow(p)
        assertEquals(1, calls.size)
    }

    @Test fun aiAddressValidation() {
        val src = "Gửi giúp chị Lan 0987654321\nnhà mình ở số 5 ngõ 10 láng hạ, đống đa hn nha"
        assertEquals("số 5 ngõ 10 láng hạ, đống đa hn", AIAddress.validate(" số 5  ngõ 10 láng hạ, đống đa hn. ", src))
        assertNull(AIAddress.validate("Số 5 ngõ 10 Láng Hạ, Đống Đa, Hà Nội", src))   // "noi" bịa
        assertNull(AIAddress.validate("số 7 ngõ 10 láng hạ", src))
        assertNull(AIAddress.validate("chị Lan 0987654321", src))
        assertNull(AIAddress.validate("", src))
    }

    @Test fun chipsNeedAdvancedClipboardWhenPaywallOn() {
        PlusGate.install({ null }, debugBuild = false)
        PlusGate.paywallEnabled = true
        try {
            val s = session(); val p = MockProxy()
            clip.copy("Ma OTP cua quy khach la 482913")
            val set = s.suggestionsNow(p)!!
            assertTrue(set.paste)                        // thẻ Dán thường vẫn còn
            assertTrue(set.clipChips.isEmpty())          // chip = Plus
            PlusGate.install({ if (it == Keys.PLUS_UNLOCKED) true else null }, debugBuild = false)
            s.invalidatePasteCache()
            assertEquals(listOf("Dán OTP 482913"), s.suggestionsNow(p)!!.clipChips.map { it.label })
        } finally {
            PlusGate.install({ null }, debugBuild = false)
            PlusGate.paywallEnabled = PlusConfig.PAYWALL_ENABLED
        }
    }

    @Test fun plainClipNoChips() {
        val s = session(); val p = MockProxy()
        clip.copy("xin chào cả nhà")
        val set = s.suggestionsNow(p)!!
        assertTrue(set.paste)
        assertTrue(set.clipChips.isEmpty())
    }

    @Test fun sensitiveClipNoChips() {
        val s = session(); val p = MockProxy()
        clip.sensitive = true
        clip.copy("482913")
        val set = s.suggestionsNow(p)!!
        assertTrue(set.paste)
        assertTrue(set.clipChips.isEmpty())
    }

    @Test fun insertClipNoLearningNoSpace() {
        val s = session(); val p = MockProxy()
        s.typeKeys(p, "xin ")
        s.insertClip("0912345678", p)
        assertEquals("xin 0912345678", p.text)
        assertFalse(s.bridge.isComposing)
    }

    // MARK: #113 ô cấm gợi ý chữ (Messenger chat với Trang) vẫn có thanh công cụ + Dán

    private val noSuggest = FieldTraits(suggestionsAllowed = false, stripTools = true)

    @Test fun stripModeTable() {
        val on = true
        assertEquals(StripMode.FULL, StripMode.of(on, FieldTraits(), incognito = false))
        assertEquals(StripMode.FULL, StripMode.of(on, FieldTraits(), incognito = true))     // ẩn danh vẫn gợi ý (chỉ đọc)
        assertEquals(StripMode.TOOLS, StripMode.of(on, noSuggest, incognito = false))
        assertEquals(StripMode.TOOLS, StripMode.of(on, noSuggest.copy(passthrough = true), incognito = false))
        assertEquals(StripMode.BLANK, StripMode.of(on, noSuggest, incognito = true))
        assertEquals(StripMode.BLANK, StripMode.of(on, noSuggest.copy(isSecure = true), incognito = false))
        assertEquals(StripMode.BLANK, StripMode.of(on, noSuggest.copy(stripTools = false), incognito = false))
        assertEquals(StripMode.FULL, StripMode.of(on, FieldTraits(passthrough = true, suggestionsAllowed = false,
            emailField = true), incognito = false))                                          // chip đuôi mail
        assertEquals(StripMode.OFF, StripMode.of(false, noSuggest, incognito = false))
        assertEquals(StripMode.OFF, StripMode.of(false, FieldTraits(), incognito = false))
        assertTrue(StripMode.TOOLS.shown); assertTrue(StripMode.FULL.shown)
        assertFalse(StripMode.BLANK.shown); assertFalse(StripMode.OFF.shown)
    }

    @Test fun toolsModeNoWordsButPasteAndChips() {
        val s = session(traits = noSuggest); val p = MockProxy()
        assertFalse(s.suggestionsActive)
        assertEquals(StripMode.TOOLS, s.stripMode)
        val empty = s.suggestionsNow(p)!!                       // bar rỗng ⇒ icon con trỏ/📋 hiện
        assertTrue(empty.nextWords.isEmpty()); assertNull(empty.word); assertFalse(empty.paste)
        assertTrue(empty.idle)
        s.typeKeys(p, "nguoi")
        val typing = s.suggestionsNow(p)!!                      // đang gõ: không chữ, không literal
        assertNull(typing.word); assertNull(typing.literal); assertTrue(typing.nextWords.isEmpty())
        val p2 = MockProxy()
        now += 3000
        s.invalidatePasteCache()
        clip.copy("Ma OTP cua quy khach la 482913")
        val set = s.suggestionsNow(p2)!!
        assertTrue(set.paste)
        assertEquals(listOf("Dán OTP 482913"), set.clipChips.map { it.label })
        assertTrue(set.nextWords.isEmpty())
        s.pasteOfferVisible(true); s.pasteOfferVisible(false)  // mời một lần mỗi mục
        now += 3000
        s.invalidatePasteCache()
        assertFalse(s.suggestionsNow(p2)!!.paste)
        s.barCollapsed = true
        assertNull(s.suggestionsNow(p2))
    }

    @Test fun toolsModeChipsNeedPlus() {
        PlusGate.install({ null }, debugBuild = false)
        PlusGate.paywallEnabled = true
        try {
            val s = session(traits = noSuggest); val p = MockProxy()
            clip.copy("Ma OTP cua quy khach la 482913")
            val set = s.suggestionsNow(p)!!
            assertTrue(set.paste)
            assertTrue(set.clipChips.isEmpty())
        } finally {
            PlusGate.install({ null }, debugBuild = false)
            PlusGate.paywallEnabled = PlusConfig.PAYWALL_ENABLED
        }
    }

    @Test fun sensitiveFieldsKeepBlankBand() {
        val p = MockProxy()
        clip.copy("xin chào")
        for (t in listOf(noSuggest.copy(isSecure = true), noSuggest.copy(noLearning = true), noSuggest.copy(stripTools = false))) {
            val s = session(traits = t)
            assertEquals(StripMode.BLANK, s.stripMode)
            assertNull(s.suggestionsNow(p))
        }
        val inc = session(settings = KeyboardSettings(incognito = true), traits = noSuggest)
        assertEquals(StripMode.BLANK, inc.stripMode)
        assertNull(inc.suggestionsNow(p))
    }
}
