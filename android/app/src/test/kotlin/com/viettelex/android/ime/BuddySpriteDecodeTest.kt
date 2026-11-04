package com.viettelex.android.ime

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * #144: mở "Bạn đồng hành" văng app — BuddyView nạp atlas Hoạt hình bằng vòng `max(w, h) / options.inSampleSize`,
 * mà BitmapFactory.Options.inSampleSize mặc định 0 ⇒ ArithmeticException (chia cho 0) ngay khi dựng ô xem thử.
 * Không chạy được BitmapFactory trên JVM ⇒ khoá ở mức nguồn: phải dùng hàm thuần [com.viettelex.keyboard.BuddySprites.sampleSize]
 * (test ở BuddyPreviewSmokeTests) và lỗi decode lùi về vector thay vì văng.
 */
class BuddySpriteDecodeTest {
    private val src = listOf(File("src/main/kotlin"), File("app/src/main/kotlin")).first { it.isDirectory }
        .resolve("com/viettelex/android/ime/BuddyView.kt").readText()

    @Test fun neverDividesByOptionsSampleSize() {
        assertFalse(Regex("""/\s*options\.inSampleSize""").containsMatchIn(src))
        assertTrue(src.contains("BuddySprites.sampleSize("))
    }

    @Test fun decodeFailureFallsBackToVector() {
        assertTrue(src.contains("catch (_: RuntimeException) { null }"))
        assertTrue(src.contains("catch (_: OutOfMemoryError) { null }"))
    }
}
