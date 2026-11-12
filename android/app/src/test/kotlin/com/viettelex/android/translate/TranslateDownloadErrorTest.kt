package com.viettelex.android.translate

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Báo lỗi 12/11/2026: "(-15)" bị báo là lỗi kết nối — -15 là APP_NOT_OWNED, cần mở Google Play. */
class TranslateDownloadErrorTest {
    private val id: (String) -> String = { it }

    @Test fun appNotOwnedPointsToPlay() {
        val m = TranslateDownloadError.of(-15)
        assertTrue(m.openPlay)
        assertFalse(m.viText.contains("kết nối"))
        assertFalse(TranslateDownloadError.text(-15, id).contains("(-15)"))
    }

    @Test fun knownCodesHaveTheirOwnText() {
        for (c in listOf(-2, -10, -14)) assertTrue("$c", TranslateDownloadError.of(c).viText != TranslateDownloadError.GENERIC)
        assertFalse(TranslateDownloadError.of(-14).openPlay)
        assertTrue(TranslateDownloadError.of(-2).openPlay)
    }

    @Test fun networkAndUnknownStayGenericWithCode() {
        assertEquals(TranslateDownloadError.GENERIC + " (-6)", TranslateDownloadError.text(-6, id))
        assertEquals(TranslateDownloadError.GENERIC + " (-100)", TranslateDownloadError.text(-100, id))
        assertEquals(TranslateDownloadError.GENERIC, TranslateDownloadError.text(null, id))
    }
}
