package com.viettelex.android.translate

import com.google.mlkit.nl.translate.TranslateLanguage
import com.viettelex.keyboard.TranslateLangs
import org.junit.Assert.assertEquals
import org.junit.Test

class TranslateLangsMlKitTest {
    /** Danh sách chép tay ở :keyboard phải khớp ML Kit đang dùng. */
    @Test fun languageListMatchesMlKit() {
        assertEquals(TranslateLanguage.getAllLanguages().toSet(), TranslateLangs.ALL.toSet())
    }
}
