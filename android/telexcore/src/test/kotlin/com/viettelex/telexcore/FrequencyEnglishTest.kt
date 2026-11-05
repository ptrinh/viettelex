package com.viettelex.telexcore

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Port of TelexCore FrequencyEnglishTests.swift: từ trùng theo tần suất + lật lại
 * (TelexEngine.englishByFrequency, THỬ NGHIỆM) và "một từ Anh mạnh chốt mạch" của sửa ngược
 * (RetroEnglish.plan). Cùng ca ở Swift và windows/engine/tests/retro_tests.cpp.
 */
class FrequencyEnglishTest {

    private fun appEngine(retro: Boolean = true, frequency: Boolean = true, teencode: Boolean = false) =
        TelexEngine().apply {
            freeMarking = true; liveSpellCheck = true; eagerEnglishRestore = true
            this.teencode = teencode
            contextualEnglish = true; collisionPrefersVietnamese = true
            retroactiveEnglish = retro; englishByFrequency = frequency
        }

    private fun typed(
        keys: String, retro: Boolean = true, frequency: Boolean = true, auto: Boolean = false,
        teencode: Boolean = false,
    ): String = frequencyType(keys, appEngine(retro, frequency, teencode), auto, strict = true)

    private fun scores(w: String): Int = EnglishFrequency.scores(w)

    private fun pair(p: String): Boolean {
        val k = IntArray(p.length) { p[it].code }
        return EnglishFrequency.hasPair(k, k.size)
    }

    // MARK: Bảng

    @Test fun tableLookups() {
        val his = scores("his")
        assertTrue(his >= 0)
        assertTrue(EnglishFrequency.vn(his) > 0)                                       // hí
        assertTrue(EnglishFrequency.en(his) > EnglishFrequency.vn(his) + 45)           // his ≫ hí
        assertEquals(0, EnglishFrequency.vn(scores("very")))                          // mạnh
        assertEquals(0, EnglishFrequency.vn(scores("fast")))
        assertTrue(EnglishFrequency.en(scores("fast")) >= EnglishFrequency.strongMin)
        assertEquals(-1, scores("zzzz"))
        assertEquals(-1, scores(""))
        // IntArray path agrees with the String path.
        val k = intArrayOf('h'.code, 'i'.code, 's'.code)
        assertEquals(his, EnglishFrequency.scores(k, 3))
        assertTrue(pair("his>huwngr"))                                                // hí hửng
        assertTrue(pair("last>nuwax"))                                                // lát nữa
        assertTrue(pair("this>sinh"))                                                 // thí sinh
        assertFalse(pair("his>car"))
        assertFalse(pair("his>huwng"))
        assertTrue(RetroEnglish.isStrongRaw("fast"))
        assertFalse(RetroEnglish.isStrongRaw("his"))
    }

    /** Every generated entry is found (binary search over the whole table, both ends). */
    @Test fun tableCountsAndEnds() {
        assertEquals(1585, EnglishFrequency.wordCount)
        assertEquals(699, EnglishFrequency.pairCount)
        assertTrue(scores("able") >= 0)
        assertTrue(scores("air") >= 0)
        assertTrue(pair("air>bawcs"))
    }

    // MARK: Một từ Anh mạnh chốt mạch (sửa ngược, không cần cờ tần suất)

    @Test fun strongWordCompletesRun() {
        assertEquals("His car is fast.", typed("His car is fast.", frequency = false, auto = true))
        assertEquals("Hí cả í fast.", typed("His car is fast.", frequency = false, auto = false))
        // Bắn sớm hơn một từ: ngay ở "very".
        val e = appEngine(frequency = false)
        for (k in listOf("His", "car", "is")) {
            for (ch in k) e.feed(ch)
            e.commitText(true)
            e.noteBoundaryCharacter(' ')
            assertNull(e.pendingRetroCorrection)
        }
        for (ch in "very") e.feed(ch)
        e.commitText(true)
        assertEquals("is car is very", e.pendingRetroCorrection?.insert)
        assertEquals(false, e.pendingRetroCorrection?.flipBack)
    }

    @Test fun strongWordNeedsTwoPicksAndAnchor() {
        for (keys in listOf("Mai car team hopj", "lamf car review code", "Guwir file cho car nhaf",
            "car team meeting", "is fast")) {
            assertEquals(keys, typed(keys, retro = false, frequency = false), typed(keys, frequency = false, auto = true))
        }
        assertEquals("í fast", typed("is fast", frequency = false, auto = true))
    }

    // MARK: Luật tần suất

    @Test fun frequencyRuleRestoresSentenceInitialEnglish() {
        assertEquals("His car is fast.", typed("His car is fast.", auto = true))
        assertEquals("His dog is cute.", typed("His dog is cute.", auto = false))
        assertEquals("Is it ok?", typed("Is it ok?", auto = false))
        assertEquals("How are you?", typed("How are you?", auto = false))
        assertEquals("Tôi đi. His dog is cute.", typed("Tooi ddi. His dog is cute.", auto = false))
    }

    @Test fun frequencyRuleNeedsNoVietnameseOnTheLeft() {
        assertEquals("sao í", typed("sao is"))
        assertEquals("em í ạ", typed("em is aj"))
        assertEquals("cho con bú", typed("cho con bus"))
        assertEquals("thắt nơ", typed("thawts now"))
        assertEquals("cái nơ đỏ", typed("cais now ddor"))
    }

    @Test fun commonVietnameseSyllablesStay() {
        assertEquals("ít nhất", typed("its nhaats"))
        assertEquals("Ít nhất là vậy", typed("Its nhaats laf vaayj"))
        assertEquals("Mai cả team họp", typed("Mai car team hopj"))
        assertEquals("Cả nhà ơi", typed("Car nhaf owi"))
        assertEquals("bên trên", typed("been treen"))
    }

    // MARK: Lật lại

    @Test fun flipBackOnVietnamesePair() {
        assertEquals("hí hửng", typed("his huwngr"))
        assertEquals("Hí hửng quá", typed("His huwngr quas"))
        assertEquals("lát nữa gọi lại nhé", typed("last nuwax goij laij nhes"))
        assertEquals("Lát nữa anh về", typed("Last nuwax anh veef"))
        assertEquals("Thí sinh đến muộn", typed("This sinh ddeens muoonj"))
        assertEquals("hí hửng\n", typed("his huwngr\n"))           // Enter: lật trước khi gửi
    }

    @Test fun flipBackOnReduplication() {
        assertEquals("hí hí", typed("his his"))
        assertEquals("Hí Hí", typed("His His"))
        assertEquals("hí hí hí vui ghê", typed("his his his vui ghee"))
        assertEquals("Hì hì", typed("Hif hif"))
        assertEquals("hớ hớ", typed("hows hows"))
        assertEquals("Hơ hơ", typed("How how"))
        assertEquals("ừ ừ", typed("uwf uwf"))
        // Lặp qua một từ Việt (tiếng cười "hí ha hí hửng").
        assertEquals("Hí ha hí hửng", typed("His ha his huwngr"))
    }

    @Test fun flipCorrectionShape() {
        val e = appEngine()
        for (ch in "His") e.feed(ch)
        assertEquals("His", e.commitText(true))
        e.noteBoundaryCharacter(' ')
        assertNull(e.pendingRetroCorrection)
        for (ch in "huwngr") e.feed(ch)
        assertEquals("hửng", e.commitText(true))
        assertEquals(RetroCorrection(7, "is hửng", "í hửng", 1, flipBack = true), e.pendingRetroCorrection)
        e.noteBoundaryCharacter(' ')
        val c = e.takeRetroCorrection()
        assertNotNull(c)
        assertEquals("í hửng ", c!!.insert)
        assertTrue(c.flipBack)
        // Lịch sử ghi lại chữ Việt: không bị đổi sang Anh lần nữa.
        assertEquals("Hí", e.debugRetroHistory.first().shown)
        assertEquals(false, e.debugRetroHistory.first().english)
    }

    /** Không lật lại khi từ kế là tiếng Anh, hay tiếng Việt không có bằng chứng cặp ("Test xong"). */
    @Test fun noFlipWithoutEvidence() {
        assertEquals("Test xong rồi nhé", typed("Test xong roofi nhes"))
        assertEquals("His cả", typed("His car"))
    }

    // MARK: Cổng

    @Test fun inertWhenOffOrWithoutRetro() {
        val corpus = listOf("His car is fast.", "his huwngr", "His His", "sao is", "Test xong roofi nhes",
            "Is it ok?", "last nuwax")
        for (k in corpus) {
            assertEquals(k, typed(k, retro = true, frequency = false), typed(k, frequency = false))
            // Cần sửa ngược đang chạy: không có nó thì cờ tần suất trơ.
            assertEquals(k, typed(k, retro = false, frequency = false), typed(k, retro = false, frequency = true))
        }
        val e = appEngine(retro = false)
        assertFalse(e.englishByFrequencyActive)
        e.retroactiveEnglish = true
        assertTrue(e.englishByFrequencyActive)
        e.vniMode = true
        assertFalse(e.englishByFrequencyActive)
    }

    /** Teencode bật: tần suất Việt đếm trên corpus đã chuẩn hoá teencode ⇒ luật tắt. */
    @Test fun teencodeDisablesFrequencyRule() {
        assertEquals("bít gòi khổ lắm", typed("bits gofi khoor lawms", teencode = true))
    }

    /** copyInto (EngineBridge undo checkpoint) carries the new flag and phrase state. */
    @Test fun copyKeepsFrequencyState() {
        val e = appEngine()
        for (ch in "sao") e.feed(ch)
        e.commitText(true)
        e.noteBoundaryCharacter(' ')
        val c = e.copy()
        assertTrue(c.englishByFrequency)
        for (ch in "is") c.feed(ch)
        assertEquals("í", c.commitText(true))   // previousWordVietnamese came along
    }
}

/**
 * Gõ như controller (cùng thủ tục với Swift FrequencyEnglishTests/FrequencyEnglishParityTests):
 * chữ → feed; ký tự khác → commitText, áp phép sửa đang chờ nếu [auto] (và không phải "\n") hoặc
 * là phép LẬT LẠI (luôn tự áp), chèn ký tự, báo noteBoundaryCharacter. Hết chuỗi = như Enter.
 * [strict]: phép sửa có `expected` không khớp đuôi màn hình là lỗi test (không chỉ bỏ qua).
 */
internal fun frequencyType(keys: String, e: TelexEngine, auto: Boolean, strict: Boolean = false): String {
    val screen = StringBuilder()
    fun apply(enter: Boolean) {
        val c = e.pendingRetroCorrection ?: return
        if (!(c.flipBack || (auto && !enter))) return
        val tail = if (c.backspaces <= screen.length) screen.substring(screen.length - c.backspaces) else null
        if (strict) assertEquals("expected-text mismatch in $keys", c.expected, tail)
        if (tail != c.expected) return
        e.takeRetroCorrection()
        screen.setLength(screen.length - c.backspaces)
        screen.append(c.insert)
    }
    for (ch in keys) {
        if (ch.code < 128 && ch.isLetter()) {
            e.feed(ch)
        } else {
            screen.append(e.commitText(true))
            apply(enter = ch == '\n')
            screen.append(ch)
            e.noteBoundaryCharacter(ch)
        }
    }
    screen.append(e.commitText(true))
    apply(enter = true)
    return screen.toString()
}
