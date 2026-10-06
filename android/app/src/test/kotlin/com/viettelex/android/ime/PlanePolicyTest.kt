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
