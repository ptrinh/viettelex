package com.viettelex.telexcore

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Đối chiếu 3 port: đọc iOS/KeyboardTests/Fixtures/frequency-english-parity.txt (Swift GHI —
 * FrequencyEnglishParityTests.swift), gõ cùng phím bằng đúng thủ tục ([frequencyType]) và so cả
 * ba cột: <retro tự áp> <retro chỉ mời + tần suất> <retro tự áp + tần suất>. "\n" trong file là
 * Enter đã escape.
 */
class FrequencyEnglishParityTest {

    private fun fixture(): File = listOf("../../iOS", "../iOS", "iOS")
        .map { File(it, "KeyboardTests/Fixtures/frequency-english-parity.txt") }
        .firstOrNull { it.exists() } ?: error("không thấy frequency-english-parity.txt")

    private fun unesc(s: String) = s.replace("\\n", "\n")

    private fun engine(frequency: Boolean) = TelexEngine().apply {
        freeMarking = true; liveSpellCheck = true; eagerEnglishRestore = true; teencode = false
        contextualEnglish = true; collisionPrefersVietnamese = true
        retroactiveEnglish = true; englishByFrequency = frequency
    }

    @Test fun parityFixtureMatchesEngine() {
        var rows = 0
        val bad = ArrayList<String>()
        for (line in fixture().readLines()) {
            if (line.isEmpty() || line.startsWith("#")) continue
            val p = line.split('\t')
            if (p.size != 4) continue
            val keys = unesc(p[0])
            val got = listOf(
                frequencyType(keys, engine(false), auto = true),
                frequencyType(keys, engine(true), auto = false),
                frequencyType(keys, engine(true), auto = true),
            )
            for (i in 0 until 3) {
                val want = unesc(p[i + 1])
                if (got[i] != want) bad.add("[$i] $keys\n   want: $want\n   got:  ${got[i]}")
            }
            rows++
        }
        println("FREQ-PARITY kotlin $rows rows, ${bad.size} mismatches")
        assertTrue("too few rows: $rows", rows > 500)
        assertEquals(bad.take(20).joinToString("\n"), 0, bad.size)
    }
}
