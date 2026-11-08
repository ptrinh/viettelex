package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Ngày âm lịch Việt Nam (UTC+7) + chip "âm lịch" — cùng bộ ca với iOS LunarDateTests.swift. */
class LunarDateTests {
    private fun lunar(d: Int, m: Int, y: Int) = LunarDate.lunar(d, m, y)
    private fun L(d: Int, m: Int, y: Int, leap: Boolean = false) = LunarDate.Lunar(d, m, y, leap)

    @Test fun tetMatchesBuddyTable() {
        assertEquals(10, BuddySeason.LUNAR_NEW_YEAR.size)
        for ((y, md) in BuddySeason.LUNAR_NEW_YEAR) {
            assertEquals("Tết $y", L(1, 1, y), lunar(md.second, md.first, y))
            val eve = lunar(md.second - 1, md.first, y)        // bảng không có ngày 1 ⇒ hôm trước cùng tháng
            assertEquals("giao thừa $y", y - 1, eve.year)
            assertEquals("giao thừa $y", 12, eve.month)
        }
    }

    @Test fun midAutumnMatchesBuddyTable() {
        assertEquals(10, BuddySeason.MID_AUTUMN_DAY.size)
        for ((y, md) in BuddySeason.MID_AUTUMN_DAY) assertEquals("Trung Thu $y", L(15, 8, y), lunar(md.second, md.first, y))
    }

    /** UTC+7 khác UTC+8: sóc rơi 23h–24h giờ Việt Nam. */
    @Test fun vietnamTimezoneDivergence() {
        assertEquals(L(1, 1, 2030), lunar(2, 2, 2030))
        assertEquals(L(15, 8, 2034), lunar(26, 9, 2034))
        assertEquals(L(1, 1, 1985), lunar(21, 1, 1985))      // Tết 1985 VN
        assertEquals(L(30, 12, 2029), LunarDate.lunar(2, 2, 2030, tz = 8.0))   // cùng ngày theo UTC+8
    }

    @Test fun leapMonths() {
        assertEquals(L(1, 6, 2025, leap = true), lunar(25, 7, 2025))
        assertEquals(L(30, 6, 2025), lunar(24, 7, 2025))
        assertEquals(L(1, 2, 2023, leap = true), lunar(22, 3, 2023))
        assertEquals("1/6 nhuận năm Ất Tỵ", LunarDate.label(lunar(25, 7, 2025)))
    }

    @Test fun labelAndYearName() {
        assertEquals("Bính Ngọ", LunarDate.yearName(2026))
        assertEquals("Ất Tỵ", LunarDate.yearName(2025))
        assertEquals("Đinh Mùi", LunarDate.yearName(2027))
        assertEquals("Giáp Tý", LunarDate.yearName(1984))
        assertEquals("30/9 năm Bính Ngọ", LunarDate.label(lunar(8, 11, 2026)))
        assertEquals("29/12 năm Ất Tỵ", LunarDate.label(lunar(16, 2, 2026)))   // trước Tết ⇒ năm cũ
        assertEquals("1/1 năm Bính Ngọ", LunarDate.label(lunar(17, 2, 2026)))
        assertEquals("13/11 năm Ất Tỵ", LunarDate.label(lunar(1, 1, 2026)))
    }

    @Test fun triggers() {
        assertEquals("âm lịch ", LunarDate.triggerTail("Hôm nay âm lịch "))
        assertEquals("Âm Lịch ", LunarDate.triggerTail("Âm Lịch "))
        assertEquals("ngày âm ", LunarDate.triggerTail("hôm nay ngày âm "))
        assertEquals("ÂL ", LunarDate.triggerTail("ÂL "))
        assertEquals("âl", LunarDate.triggerTail("x âl"))
        val nfd = "âm lịch "
        assertEquals(nfd, LunarDate.triggerTail("hôm nay $nfd"))
        for (s in listOf("", " ", "lịch ", "âm ", "ngày ", "đâm lịch ", "âm\nlịch ", "âm  lịch ", "ÂLL ", "ngày âm lịch  ",
                         "âm lịch.", "ngàyâm ", "AL ")) {
            assertNull("«$s» không được khớp", LunarDate.triggerTail(s))
        }
    }

    @Test fun mayTrigger() {
        for (w in listOf("lịch", "Lịch", "âm", "ÂM", "ÂL", "âl")) assertTrue(w, LunarDate.mayTrigger(w))
        for (w in listOf(null, "ngày", "lich", "am", "AAL", "lịchs")) assertFalse("$w", LunarDate.mayTrigger(w))
    }

    @Test fun chipReplacesTriggerPhrase() {
        assertEquals(NumberChip("30/9 năm Bính Ngọ", "âm lịch ", "30/9 năm Bính Ngọ "),
            LunarDate.chip("Hôm nay âm lịch ", 2026, 11, 8))
        assertEquals("ngày âm ", LunarDate.chip("ngày âm ", 2026, 11, 8)?.replace)
        assertEquals("ÂL ", LunarDate.chip("ÂL ", 2026, 11, 8)?.replace)
        assertEquals("1/6 nhuận năm Ất Tỵ ", LunarDate.chip("ÂL ", 2025, 7, 25)?.insert)
        assertNull(LunarDate.chip("ngày ", 2026, 11, 8))
        for (b in listOf("a âm lịch ", "x ngày âm ", "ÂL")) {
            assertTrue(b, b.endsWith(LunarDate.chip(b, 2026, 11, 8)!!.replace))
        }
        assertNull(NumberChips.chip("hôm nay 30/9 năm Bính Ngọ "))
        assertNotNull(LunarDate.chip("ÂL "))
    }
}
