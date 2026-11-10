package com.viettelex.keyboard

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.File
import java.nio.file.Files
import java.util.concurrent.Executor

/**
 * RAM-AUDIT #2/#4/#6/#7: dữ liệu nhả khi bàn phím ẩn lâu nạp lại Y HỆT; UserLangModel.close
 * (service bị huỷ khi đổi IME) ghi nốt rồi bỏ bảng RAM, không bao giờ ghi đè file bằng bảng rỗng.
 */
class IdleReleaseTests {
    @Before fun setUp() = TestAssets.install()

    @Test fun swipeEnglishReleaseReloadsSameLexicon() {
        val a = SwipeEnglish.lexicon
        assertTrue(SwipeEnglish.isLoaded)
        val hello = SwipeEnglish.indexOf("hello")
        SwipeEnglish.release()
        assertFalse(SwipeEnglish.isLoaded)
        assertTrue("người giữ tham chiếu cũ vẫn dùng được", a.count > 0 && a.word(hello) == "hello")
        val b = SwipeEnglish.lexicon
        assertNotSame(a, b)
        assertEquals(a.count, b.count)
        for (i in 0 until a.count) { assertEquals(a.word(i), b.word(i)); assertEquals(a.freq(i), b.freq(i)) }
        assertArrayEquals(a.swipe.keys, b.swipe.keys)
        assertArrayEquals(a.swipe.order, b.swipe.order)
        assertEquals(hello, SwipeEnglish.indexOf("hello"))
        assertSame(b, SwipeEnglish.lexicon)
    }

    @Test fun emojiCategoriesReleaseRebuildsSame() {
        val a = EmojiData.categories
        EmojiData.releaseCategories()
        val b = EmojiData.categories
        assertNotSame(a, b)
        assertEquals(a, b)
    }

    @Test fun visibleCropIsCenteredAspectFill() {
        // ảnh dọc 810×1080 trên bàn phím 1080×880 (tỉ lệ ~1.23) ⇒ dải ngang giữa, đủ bề ngang
        val c = WallpaperMath.visibleCrop(810, 1080, 1080, 880)
        assertEquals(0, c[0]); assertEquals(810, c[2])
        val ch = c[3] - c[1]
        assertEquals(660, ch)
        assertEquals((1080 - ch) / 2, c[1])
        // ảnh ngang rất rộng ⇒ cắt hai bên
        val d = WallpaperMath.visibleCrop(4000, 1000, 1000, 1000)
        assertEquals(listOf(1500, 0, 2500, 1000), d.toList())
        // cùng tỉ lệ ⇒ cả ảnh
        assertEquals(listOf(0, 0, 1080, 880), WallpaperMath.visibleCrop(1080, 880, 540, 440).toList())
        // dữ liệu hỏng ⇒ cả ảnh
        assertEquals(listOf(0, 0, 10, 10), WallpaperMath.visibleCrop(10, 10, 0, 5).toList())
    }

    private val dir: File = Files.createTempDirectory("userlm-close").toFile()
    private val file = File(dir, Keys.USERLM_FILE)
    private val direct = Executor { it.run() }

    private fun model(main: MainThread = ImmediateMainThread()) =
        UserLangModel(file, main, direct).apply { isKnownWord = { true } }

    @Test fun closeFlushesPendingThenDropsTables() {
        val m = model()
        m.record("việt", null, null, 4)
        assertTrue(m.hasPendingSave)
        m.close()
        assertFalse(m.hasPendingSave)
        assertEquals("bảng RAM đã bỏ", 0, m.count("việt"))
        assertEquals("đã ghi trước khi bỏ", 4, model().count("việt"))
    }

    @Test fun closedModelNeverOverwritesFile() {
        model().apply { record("nam", null, null, 3); saveNow() }
        val m = model()
        m.close()
        m.record("khác", null, null, 9)   // gõ muộn sau onDestroy: không học, không ghi
        m.save(); m.saveNow()
        m.reloadAfterExternalErase()       // listener pref muộn: không nạp/ghi gì
        val again = model()
        assertEquals(3, again.count("nam"))
        assertEquals(0, again.count("khác"))
    }
}
