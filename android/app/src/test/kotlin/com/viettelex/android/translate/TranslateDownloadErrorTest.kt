package com.viettelex.android.translate

import com.google.mlkit.common.MlKitException
import com.viettelex.keyboard.L10nTable
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Lỗi tải gói ngôn ngữ ML Kit → câu cho người dùng (#162: bỏ Play Feature Delivery, chỉ còn lỗi ML Kit). */
class TranslateDownloadErrorTest {
    private val id: (String) -> String = { it }

    @Test fun codesMatchMlKit() {
        assertEquals(MlKitException.NETWORK_ISSUE, TranslateDownloadError.NETWORK_ISSUE)
        assertEquals(MlKitException.NOT_ENOUGH_SPACE, TranslateDownloadError.NOT_ENOUGH_SPACE)
        assertEquals(MlKitException.DATA_LOSS, TranslateDownloadError.DATA_LOSS)
        assertEquals(MlKitException.MODEL_HASH_MISMATCH, TranslateDownloadError.MODEL_HASH_MISMATCH)
    }

    @Test fun storageAndCorruptHaveTheirOwnText() {
        assertEquals(TranslateDownloadError.NO_SPACE, TranslateDownloadError.of(MlKitException.NOT_ENOUGH_SPACE, true))
        assertEquals(TranslateDownloadError.CORRUPT, TranslateDownloadError.of(MlKitException.MODEL_HASH_MISMATCH, false))
        assertEquals(TranslateDownloadError.CORRUPT, TranslateDownloadError.of(MlKitException.DATA_LOSS, false))
        assertFalse(TranslateDownloadError.text(MlKitException.NOT_ENOUGH_SPACE, false, id).contains("("))
    }

    @Test fun networkDependsOnWifiOnly() {
        assertEquals(TranslateDownloadError.NEED_WIFI, TranslateDownloadError.of(MlKitException.NETWORK_ISSUE, true))
        assertEquals(TranslateDownloadError.GENERIC, TranslateDownloadError.text(MlKitException.NETWORK_ISSUE, false, id))
    }

    @Test fun unknownStaysGenericWithCode() {
        assertEquals(TranslateDownloadError.GENERIC + " (13)", TranslateDownloadError.text(MlKitException.INTERNAL, true, id))
        assertEquals(TranslateDownloadError.GENERIC, TranslateDownloadError.text(0, false, id))
        assertEquals(TranslateDownloadError.GENERIC, TranslateDownloadError.text(null, false, id))
    }

    @Test fun everyMessageHasEnglish() {
        for (m in listOf(TranslateDownloadError.GENERIC, TranslateDownloadError.NEED_WIFI,
                TranslateDownloadError.NO_SPACE, TranslateDownloadError.CORRUPT))
            assertTrue(m, !L10nTable.EN[m].isNullOrBlank())
    }
}
