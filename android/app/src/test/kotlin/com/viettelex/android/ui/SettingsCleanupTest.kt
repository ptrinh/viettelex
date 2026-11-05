package com.viettelex.android.ui

import com.viettelex.keyboard.Keys
import com.viettelex.keyboard.L10n
import com.viettelex.keyboard.L10nTable
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Thu gọn cài đặt Android — docs/SETTINGS-CLEANUP-SPEC.md §1, §3, §4, §5. */
class SettingsCleanupTest {
    @After fun reset() { L10n.lang = L10n.DEFAULT }

    private fun dir(vararg c: String): File = c.map { File(it) }.first { it.isDirectory }
    private val appSrc get() = dir("src/main/kotlin", "app/src/main/kotlin")
    private val kbSrc get() = dir("../keyboard/src/main/kotlin", "keyboard/src/main/kotlin")
    private val coreSrc get() = dir("../telexcore/src/main/kotlin", "telexcore/src/main/kotlin")
    private fun source(root: File) = root.walkTopDown().filter { it.extension == "kt" }.joinToString("\n") { it.readText() }
    /** Mã nguồn bỏ dòng chú thích (nhãn cũ còn được nhắc trong chú thích lịch sử thì không sao). */
    private fun code(root: File) = source(root).lines().filterNot { l ->
        l.trimStart().let { it.startsWith("//") || it.startsWith("*") || it.startsWith("/*") }
    }.joinToString("\n")

    // MARK: §4 cấu trúc tab Tính Năng

    @Test fun featureTabStructure() {
        assertEquals(listOf(FeaturePage.SuaLoi, FeaturePage.GoVuot, FeaturePage.GoTat, FeaturePage.Phim,
            FeaturePage.GiaoDien, FeaturePage.RiengTu, FeaturePage.NangCao), FeaturePage.groups.flatten())
        assertEquals(FeaturePage.NangCao, FeaturePage.groups.last().single())   // Gỡ lỗi cuối danh sách
        assertEquals("Sửa lỗi & gợi ý", FeaturePage.SuaLoi.title)
        assertEquals("Riêng tư & sao lưu", FeaturePage.RiengTu.title)
        assertEquals("Nâng cao / Gỡ lỗi", FeaturePage.NangCao.title)
        L10n.lang = "en"
        assertEquals("Corrections & suggestions", FeaturePage.SuaLoi.title)
        assertEquals("Privacy & backup", FeaturePage.RiengTu.title)
        assertEquals("Advanced / Debugging", FeaturePage.NangCao.title)
    }

    // MARK: §5(b) tìm kiếm trỏ đúng chỗ mới

    private fun hit(q: String, title: String) = FeatureSearchEntry.search(q).single { it.viTitle == title }

    @Test fun searchPointsToNewPlaces() {
        for (lang in listOf("vi", "en")) {
            L10n.lang = lang
            // Chạm trượt gom về Sửa lỗi & gợi ý (trước ở tab Kiểu Gõ).
            assertEquals(FeaturePage.SuaLoi, hit("cham truot", "Gợi ý sửa lỗi chạm trượt").page)
            assertEquals(FeaturePage.SuaLoi, hit("smart touch", "Chọn phím thông minh").page)
            assertEquals(FeaturePage.SuaLoi, hit("spell", "Kiểm tra chính tả khi gõ").page)
            assertEquals(FeaturePage.SuaLoi, hit("so tien", "Gợi ý số tiền").page)
            assertEquals(FeaturePage.SuaLoi, hit("them dau", "Thêm dấu").page)
            // Phản hồi khi chạm: trang con của Phím & cử chỉ.
            for (t in listOf("Rung phím", "Âm thanh phím", "Phóng to chữ khi bấm", "Phím sẫm khi bấm", "Phản hồi khi chạm"))
                FeatureSearchEntry.all.single { it.viTitle == t }.let { assertEquals(t, FeaturePage.Phim, it.page); assertTrue(t, it.feedback) }
            assertFalse(hit("mot tay", "Chế độ một tay").feedback)
            // Riêng tư & sao lưu; Nâng cao / Gỡ lỗi.
            assertEquals(FeaturePage.RiengTu, hit("backup", "Xuất / nhập file sao lưu").page)
            assertEquals(FeaturePage.RiengTu, hit("incognito", "Chế độ ẩn danh").page)
            assertEquals(FeaturePage.NangCao, hit("debug", "Debug mode — ghi log chạm phím").page)
            // Kiểu gõ: trang "Nâng cao".
            for (o in listOf(TypingOption.SimpleTelex, TypingOption.FreeMarking, TypingOption.QuickTelex,
                    TypingOption.ModernTone, TypingOption.Teencode)) {
                val e = FeatureSearchEntry.all.single { it.typing == o }
                assertNull(e.page)
                assertEquals(o.name, KieuGoPage.TypingAdvanced, e.kieuGoTarget?.page)
            }
            assertEquals(TypingOption.Teencode, hit("teencode", "Chính tả teencode").typing)
            assertNull(hit("viet hoa", "Tự động viết hoa đầu câu").kieuGoTarget!!.page)
            // Nhóm gõ lẫn tiếng Anh: công tắc nhận diện ở trang Nâng cao của nhóm.
            assertEquals(KieuGoPage.MixedAdvanced, hit("ngu canh", "Quyết định theo ngữ cảnh").kieuGoTarget?.page)
            assertEquals(KieuGoPage.MixedAdvanced, hit("tan suat", "Đoán từ trùng theo tần suất").kieuGoTarget?.page)
            val space = hit("vuot phim cach", "Vuốt phím cách đổi Tiếng Việt / Tiếng Anh").kieuGoTarget!!
            assertNull(space.page); assertTrue(space.expandMixed)
        }
        // Mỗi tên cài đặt chỉ một đích (trừ Từ điển cá nhân: cả nhóm mixed lẫn Sửa lỗi & gợi ý).
        val dup = FeatureSearchEntry.all.groupBy { it.viTitle }.filter { it.value.size > 1 }.keys - "Từ điển cá nhân"
        assertTrue("trùng: $dup", dup.isEmpty())
    }

    @Test fun searchResultPaths() {
        fun path(t: String) = FeatureSearchEntry.all.single { it.viTitle == t }.path
        assertEquals("Kiểu Gõ › Kiểu gõ › Nâng cao", path("Chính tả teencode"))
        assertEquals("Kiểu Gõ › Kiểu gõ", path("Tự động viết hoa đầu câu"))
        assertEquals("Kiểu Gõ › Gõ lẫn tiếng Anh › Nâng cao", path("Tự sửa từ phía trước"))
        assertEquals("Kiểu Gõ › Gõ lẫn tiếng Anh", path("Vuốt phím cách đổi Tiếng Việt / Tiếng Anh"))
        assertEquals("Kiểu Gõ", path("Gõ lẫn tiếng Anh"))
        assertEquals("Tính Năng › Phím & cử chỉ › Phản hồi khi chạm", path("Rung phím"))
        assertEquals("Tính Năng › Gõ vuốt", path("Vuốt từ tiếng Anh"))
    }

    // MARK: kiểu gõ — key không đổi, chỉ-Telex mờ khi VNI

    @Test fun typingOptionsKeysAndTelexOnly() {
        val keys = mapOf(TypingOption.InputMethod to "vniMode", TypingOption.AutoCapitalize to "autoCapitalize",
            TypingOption.SimpleTelex to "simpleTelex", TypingOption.FreeMarking to "freeMarking",
            TypingOption.QuickTelex to "quickTelex", TypingOption.ModernTone to "modernTone",
            TypingOption.Teencode to "teencode")
        for (o in TypingOption.entries) assertEquals(o.name, keys[o], o.prefKey)
        for (o in TypingOption.entries) {
            assertNull(TypingOption.disabledReason(o, vniMode = false))
            val expected = if (o in setOf(TypingOption.SimpleTelex, TypingOption.FreeMarking, TypingOption.QuickTelex,
                    TypingOption.Teencode)) MixedTypingUI.TELEX_ONLY else null
            assertEquals(o.name, expected, TypingOption.disabledReason(o, vniMode = true))
        }
        assertEquals("Chỉ áp dụng cho Telex", MixedTypingUI.TELEX_ONLY)
        // Cấp 1 tab Kiểu Gõ chỉ còn Telex/VNI + Tự viết hoa; còn lại ở Nâng cao.
        assertEquals(listOf(TypingOption.InputMethod, TypingOption.AutoCapitalize), TypingOption.entries.filter { !it.advanced })
    }

    // MARK: §5(d) nhãn bảng §3 (chuỗi vi trong mã nguồn)

    @Test fun section3Labels() {
        val src = code(appSrc)
        for (label in listOf("Bỏ dấu tự do", "Bỏ dấu kiểu mới (oà, uý)", "Sửa dấu từ đã gõ", "Gợi ý số tiền",
                "Tự khôi phục từ tiếng Anh", "Thêm dấu", "Phản hồi khi chạm", "Sửa lỗi & gợi ý", "Riêng tư & sao lưu",
                "Gõ lẫn tiếng Anh", "Nâng cao"))
            assertTrue("thiếu nhãn «$label»", "\"$label\"" in src)
        assertTrue("chú thích Tự khôi phục phải có ví dụ", "(google, github…)" in src)
        // Không còn nhãn cũ.
        for (old in listOf("tr(\"Chip số\")", "tr(\"Chip “Thêm dấu”\")", "\"Chính tả & sửa lỗi\"", "\"Gợi ý & từ điển\"",
                "\"Riêng tư & clipboard\"", "\"Sao lưu & đồng bộ\"", "\"Gõ mixed Việt/Anh\"", "tr(\"Bỏ dấu kiểu mới\")"))
            assertFalse("còn nhãn cũ $old", old in src)
        // Gợi ý sửa lỗi chạm trượt không còn ở tab Kiểu Gõ (Tabs.kt).
        val tabs = File(appSrc, "com/viettelex/android/ui/Tabs.kt").readText()
        assertFalse(Keys.AUTO_FIX_ADJACENT, "Keys.AUTO_FIX_ADJACENT" in tabs)
        assertFalse("Gỡ lỗi còn ở Giới Thiệu", "    DebugSection()" in tabs)
    }

    // MARK: §5(c) không nhắc tên bộ gõ khác

    /** Tên đảo ngược (không để tên thật trong repo). */
    private val reversedNames = listOf("yekinu", "yekve", "yeknepo", "nabal", "teivgneitog", "yekteiv", "yekiv")

    @Test fun noOtherInputMethodNames() {
        val names = reversedNames.map { it.reversed() }
        val texts = mapOf("app" to source(appSrc), "keyboard" to source(kbSrc), "telexcore" to source(coreSrc),
            "L10nTable.EN" to L10nTable.EN.entries.joinToString("\n") { it.key + " " + it.value })
        for ((where, text) in texts) {
            val lower = text.lowercase()
            val found = names.filter { it in lower }
            assertTrue("$where nhắc tên bộ gõ khác: ${found.map { it.reversed() }}", found.isEmpty())
        }
    }
}
