package com.viettelex.android.ime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.io.RandomAccessFile
import java.nio.channels.FileChannel

/** Về plane chữ đánh giá lại viết hoa đầu câu (port iOS ShiftOnReturnToLettersTests). */
class PlanePolicyTest {
    companion object {
        @org.junit.BeforeClass @JvmStatic fun assets() {
            val dir = listOf(File("src/main/assets"), File("app/src/main/assets"), File("android/app/src/main/assets"))
                .first { File(it, com.viettelex.keyboard.Keys.ASSET_LEXICON).exists() }
            com.viettelex.keyboard.KeyboardData.install { name ->
                RandomAccessFile(File(dir, name), "r").use { f -> f.channel.map(FileChannel.MapMode.READ_ONLY, 0, f.length()) }
            }
        }
    }

    @Test fun lettersReevaluates() {
        assertTrue(PlanePolicy.reevaluatesShift(Plane.LETTERS))
        for (p in Plane.entries.filter { it != Plane.LETTERS })
            assertFalse(p.name, PlanePolicy.reevaluatesShift(p))
    }

    /** Caps Lock / shift một-lần tắt khi rời chữ sang ?123 / emoji (Phil 06/10/2026). */
    @Test fun leavingLettersClearsShift() {
        for (p in listOf(Plane.NUMBERS, Plane.SYMBOLS, Plane.EMOJI, Plane.EMOJI_SEARCH))
            assertTrue(p.name, PlanePolicy.clearsShiftLeavingLetters(p))
        for (p in listOf(Plane.LETTERS, Plane.TEMPLATES, Plane.EDIT))
            assertFalse(p.name, PlanePolicy.clearsShiftLeavingLetters(p))
        // Về chữ vẫn đánh giá lại viết hoa đầu câu (auto-shift áp lại sau khi Caps tắt).
        assertTrue(PlanePolicy.reevaluatesShift(Plane.LETTERS))
    }

    /** Hợp đồng session mà IME dựa vào: ". " tự thêm ở plane 123 ⇒ auto-shift = true lúc về ABC. */
    @Test fun periodAutoSpaceOnNumbersPlaneCapitalizesNextLetter() {
        val s = com.viettelex.keyboard.KeyboardSession(com.viettelex.keyboard.UserLangModel(), null) { 0L }
        s.startInput(com.viettelex.keyboard.KeyboardSettings(autoSpaceAfterPunct = true, showSuggestions = false),
            com.viettelex.keyboard.FieldTraits(capSentences = true))
        val p = Proxy()
        for (c in "hi") s.handle(com.viettelex.keyboard.Key.Letter(c), p)
        s.handle(com.viettelex.keyboard.Key.Text("."), p)     // phím "." của plane 123
        assertEquals("hi. ", p.sb.toString())
        assertEquals(true, s.updateAutoShift(p))
        // Tắt công tắc viết hoa: không hoa.
        val off = com.viettelex.keyboard.KeyboardSession(com.viettelex.keyboard.UserLangModel(), null) { 0L }
        off.startInput(com.viettelex.keyboard.KeyboardSettings(autoSpaceAfterPunct = true, showSuggestions = false,
            autoCapitalize = false), com.viettelex.keyboard.FieldTraits(capSentences = true))
        val q = Proxy()
        for (c in "hi") off.handle(com.viettelex.keyboard.Key.Letter(c), q)
        off.handle(com.viettelex.keyboard.Key.Text("."), q)
        assertTrue(off.updateAutoShift(q) != true)
    }

    // Issue #143 (song sinh iOS NumberRowTests): viết hoa đầu câu + hàng số, chạm "1" đầu câu
    // ⇒ chữ kế vẫn HOA. Phím số trên plane chữ phải nhả Shift một-lần như phím chữ.

    /** Luật thuần: plane chữ nhả ON, giữ CAPS/OFF; plane khác không đụng shift. */
    @Test fun numberRowDigitReleasesOneShotShift() {
        assertEquals(KeyboardView.Shift.OFF, PlanePolicy.shiftAfterCharKey(Plane.LETTERS, KeyboardView.Shift.ON))
        assertEquals(KeyboardView.Shift.CAPS, PlanePolicy.shiftAfterCharKey(Plane.LETTERS, KeyboardView.Shift.CAPS))
        assertEquals(KeyboardView.Shift.OFF, PlanePolicy.shiftAfterCharKey(Plane.LETTERS, KeyboardView.Shift.OFF))
        for (p in Plane.entries.filter { it != Plane.LETTERS }) for (sh in KeyboardView.Shift.entries)
            assertEquals("${p.name} $sh", sh, PlanePolicy.shiftAfterCharKey(p, sh))
    }

    /**
     * Nguyên nhân gốc: session không đánh giá lại viết hoa sau Key.Text ("1" từ hàng số) ⇒
     * IME không hạ shift; bàn phím phải tự nhả. Đầu câu shift = true, sau "1" needsAutoShift = false.
     */
    @Test fun sessionDoesNotReevaluateShiftAfterDigit() {
        val s = com.viettelex.keyboard.KeyboardSession(com.viettelex.keyboard.UserLangModel(), null) { 0L }
        s.startInput(com.viettelex.keyboard.KeyboardSettings(showSuggestions = false),
            com.viettelex.keyboard.FieldTraits(capSentences = true))
        val p = Proxy()
        assertEquals(true, s.updateAutoShift(p))                          // ô trống: đầu câu
        val out = s.handle(com.viettelex.keyboard.Key.Text("1"), p)
        assertEquals("1", p.sb.toString())
        assertFalse("session không đánh giá lại ⇒ KeyboardView phải tự nhả shift", out.needsAutoShift)
    }

    /**
     * Nối dây: mọi phím CHAR (hàng số thường / tách / một tay / tablet đều là KeyKind.CHAR)
     * arm trên plane chữ dùng lettersCharFire — nhả shift lúc CHỐT (KeyCommitQueue), không lúc chạm.
     */
    @Test fun charKeyOnLettersPlaneWiredToShiftRelease() {
        val src = listOf(File("src/main/kotlin"), File("app/src/main/kotlin")).first { it.isDirectory }
            .resolve("com/viettelex/android/ime/KeyboardView.kt").readText()
        val charDown = src.substringAfter("override fun onTouchEvent(").substringAfter("KeyKind.CHAR -> {")
            .substringBefore("KeyKind.PAD -> {")
        assertTrue(charDown, "commits.arm(k, if (plane == Plane.LETTERS) lettersCharFire(k.insert) else textFire(k.insert))" in charDown)
        val fire = src.substringAfter("private fun lettersCharFire(").substringBefore("\n    }\n")
        assertTrue(fire, "emit(k)" in fire && "PlanePolicy.shiftAfterCharKey(Plane.LETTERS, shift)" in fire)
        assertTrue("nhả sau khi chèn", fire.indexOf("emit(k)") < fire.indexOf("shiftAfterCharKey"))
    }

    // Dấu kết vế ở plane ?123 / =\< về chữ ngay, không cần dấu cách (Phil 06/11/2026).
    // Song sinh iOS ClauseEndReturnTests.

    /** (văn bản trước con trỏ, ký tự vừa chạm, về chữ?) */
    private val clauseTable: List<Triple<String, String, Boolean>> = listOf(
        Triple("2", ".", false),          // 2.5 — thập phân
        Triple("1", ",", false),          // 1,000 — hàng nghìn
        Triple("10", ":", false),         // 10:30 — giờ
        Triple("ok", ".", true),
        Triple("ok", ",", true),
        Triple("hi", "!", true),
        Triple("hi", "?", true),
        Triple("", "(", false),           // ( mở giữ plane
        Triple("(a", ")", true),          // ) về chữ
        Triple("(1", ")", true),          // ) sau số vẫn về chữ
        Triple("say", "\"", true),
        Triple("it", "'", true),
        Triple("note", ":", true),
        Triple("a", ";", true),
        Triple("2", ";", true),
        Triple("2", "!", true),
        Triple("wait", "…", true),
        Triple("2", "…", true),
        Triple("x", "”", true),
        Triple("x", "’", true),
        Triple("x", "»", true),
        Triple("", "“", false),      // nháy / ngoặc kép MỞ giữ plane
        Triple("", "‘", false),
        Triple("", "«", false),
        Triple("", ".", true),            // đầu ô
        Triple("a ", ".", true),          // sau dấu cách
    ) + listOf("@", "/", "#", "$", "%", "&", "*", "-", "_", "+", "=", "[", "{", "<", ">", "\\", "|",
        "1", "0", "₫", "€", "×", "÷", "]", "}", "~").map { Triple("ok", it, false) }

    @Test fun clauseEnderTable() {
        for ((before, key, want) in clauseTable) for (p in listOf(Plane.NUMBERS, Plane.SYMBOLS))
            assertEquals("'$before' + '$key' on $p", want,
                PlanePolicy.returnToLettersAfterSymbol(key, p, numericField = false, before = before.lastOrNull()))
    }

    @Test fun clauseEnderOtherPlanesAndNumericFieldUnaffected() {
        for (key in PlanePolicy.CLAUSE_ENDERS) {
            for (p in Plane.entries.filter { it != Plane.NUMBERS && it != Plane.SYMBOLS })
                assertFalse("$key on $p", PlanePolicy.returnToLettersAfterSymbol(key, p, false, 'a'))
            assertFalse("$key ô số", PlanePolicy.returnToLettersAfterSymbol(key, Plane.NUMBERS, true, 'a'))
        }
    }

    /** Biến thể in ấn ĐÓNG có trong bàn ?123 / =\< đều thuộc bảng. */
    @Test fun clauseEnderTypographicVariantsCovered() {
        val all = listOf(".", "'", "\"", ">", "?", "!").flatMap {
            com.viettelex.keyboard.KeyVariants.variants(it, symbolPlane = true)
        }.toSet()
        for (v in listOf("…", "”", "’", "»")) {
            assertTrue(v, v in all)
            assertTrue(v, v in PlanePolicy.CLAUSE_ENDERS)
        }
    }

    /**
     * Nối dây: mọi Key.Text của plane ?123 / =\< (chạm CHAR / PUNCT, chọn biến thể) đi qua emit ⇒
     * luật đặt ở emit; ký tự trước con trỏ đọc TRƯỚC onKey và chỉ cho "." "," ":".
     */
    @Test fun clauseEnderWiredInEmit() {
        val src = listOf(File("src/main/kotlin"), File("app/src/main/kotlin")).first { it.isDirectory }
            .resolve("com/viettelex/android/ime/KeyboardView.kt").readText()
        val emit = src.substringAfter("private fun emit(k: Key) {").substringBefore("\n    }\n")
        val probe = emit.indexOf("listener?.charBeforeCursor()")
        val onKey = emit.indexOf("listener?.onKey(k)")
        val rule = emit.indexOf("PlanePolicy.returnToLettersAfterSymbol(")
        assertTrue(emit, probe in 0 until onKey && onKey < rule)
        assertTrue(emit, "PlanePolicy.DIGIT_SEPARATORS" in emit.substring(0, onKey))
        assertTrue(emit, "setPlane(Plane.LETTERS)" in emit.substring(rule))
    }

    private class Proxy : com.viettelex.keyboard.TextProxy {
        val sb = StringBuilder()
        override val isSecure = false
        override fun insertText(text: String) { sb.append(text) }
        override fun deleteCodePoints(count: Int) {
            repeat(count) { if (sb.isNotEmpty()) sb.setLength(sb.offsetByCodePoints(sb.length, -1)) }
        }
        override fun deleteBackward() = deleteCodePoints(1)
        override fun contextBeforeInput(): String = sb.toString()
        override fun confirmTail(expected: String) = sb.endsWith(expected)
    }
}
