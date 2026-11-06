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

    // MARK: kiểu gõ — key không đổi, chỉ-Telex ẩn khi VNI

    @Test fun typingOptionsKeysAndTelexOnly() {
        val keys = mapOf(TypingOption.InputMethod to "vniMode", TypingOption.AutoCapitalize to "autoCapitalize",
            TypingOption.SimpleTelex to "simpleTelex", TypingOption.FreeMarking to "freeMarking",
            TypingOption.QuickTelex to "quickTelex", TypingOption.ModernTone to "modernTone",
            TypingOption.Teencode to "teencode")
        for (o in TypingOption.entries) assertEquals(o.name, keys[o], o.prefKey)
        // VNI ⇒ ẨN Telex đơn giản / Bỏ dấu tự do / Gõ nhanh (§6); teencode chạy cả ở VNI ⇒ luôn hiện.
        val telexOnly = setOf(TypingOption.SimpleTelex, TypingOption.FreeMarking, TypingOption.QuickTelex)
        for (o in TypingOption.entries) {
            assertFalse(o.name, TypingOption.hidden(o, vniMode = false))
            assertEquals(o.name, o in telexOnly, TypingOption.hidden(o, vniMode = true))
        }
        assertFalse(TypingOption.Teencode.hiddenInVni)
        assertEquals("Chỉ áp dụng cho Telex", MixedTypingUI.TELEX_ONLY)
        // Cấp 1 tab Kiểu Gõ chỉ còn Telex/VNI + Tự viết hoa; còn lại ở Nâng cao.
        assertEquals(listOf(TypingOption.InputMethod, TypingOption.AutoCapitalize), TypingOption.entries.filter { !it.advanced })
    }

    // MARK: §1 VNI ẩn nhóm Gõ lẫn tiếng Anh (06/11/2026)

    @Test fun vniHidesMixedGroup() {
        // Telex: như cũ.
        assertEquals(listOf(MixedTypingUI.Row.ProfilePicker, MixedTypingUI.Row.SpaceSwipeLanguage, MixedTypingUI.Row.UserDictionary, MixedTypingUI.Row.Advanced), MixedTypingUI.rows(false))
        // VNI: bộ chọn hồ sơ + Nâng cao thay bằng MỘT dòng ghi chú; giữ Vuốt phím cách + Từ điển cá nhân.
        assertEquals(listOf(MixedTypingUI.Row.VniNote, MixedTypingUI.Row.SpaceSwipeLanguage, MixedTypingUI.Row.UserDictionary), MixedTypingUI.rows(true))
        val advanced = setOf(MixedTypingItem.AutoRestore, MixedTypingItem.ContextualEnglish,
            MixedTypingItem.RetroEnglish, MixedTypingItem.EnglishByFrequency)
        for (item in MixedTypingItem.entries) {
            assertFalse(item.name, MixedTypingUI.hidden(item, vniMode = false))
            assertEquals(item.name, item in advanced, MixedTypingUI.hidden(item, vniMode = true))
        }
        // Key lưu không đổi.
        assertEquals(mapOf(MixedTypingItem.AutoRestore to Keys.AUTO_RESTORE, MixedTypingItem.ContextualEnglish to Keys.CONTEXTUAL_ENGLISH,
            MixedTypingItem.RetroEnglish to Keys.RETRO_ENGLISH_AUTO, MixedTypingItem.EnglishByFrequency to Keys.ENGLISH_BY_FREQUENCY,
            MixedTypingItem.SpaceSwipeLanguage to Keys.SPACE_SWIPE_LANGUAGE),
            MixedTypingItem.entries.filter { it.prefKey != null }.associateWith { it.prefKey })
        // Tóm tắt khi thu gọn: VNI bỏ hai mục nhận diện tiếng Anh.
        assertEquals(listOf("Khôi phục tiếng Anh", "Ngữ cảnh", "Vuốt phím cách"),
            MixedTypingUI.summaryParts(false, true, true, true, false))
        assertEquals(listOf("Vuốt phím cách"), MixedTypingUI.summaryParts(true, true, true, true, false))
        assertEquals(emptyList<String>(), MixedTypingUI.summaryParts(true, true, true, false, false))
        // Trang Nâng cao của nhóm không mở khi VNI; trang khác giữ nguyên.
        assertNull(MixedTypingUI.page(KieuGoPage.MixedAdvanced, true))
        assertEquals(KieuGoPage.MixedAdvanced, MixedTypingUI.page(KieuGoPage.MixedAdvanced, false))
        assertEquals(KieuGoPage.TypingAdvanced, MixedTypingUI.page(KieuGoPage.TypingAdvanced, true))
    }

    @Test fun vniSearchLandsOnNote() {
        for (lang in listOf("vi", "en")) {
            L10n.lang = lang
            // Mục ẩn vẫn tìm được…
            for (t in listOf("Tự khôi phục từ tiếng Anh", "Quyết định theo ngữ cảnh", "Tự sửa từ phía trước", "Đoán từ trùng theo tần suất")) {
                val target = FeatureSearchEntry.all.single { it.viTitle == t }.kieuGoTarget!!
                assertEquals(t, target, MixedTypingUI.resolve(target, vniMode = false))
                // …và mở ra thì ở nhóm, tô sáng dòng ghi chú.
                assertEquals(t, KieuGoTarget(MixedTypingUI.VNI_NOTE_ID, null, expandMixed = true), MixedTypingUI.resolve(target, vniMode = true))
            }
            // Mục còn hiện: đích không đổi.
            val space = hit("vuot phim cach", "Vuốt phím cách đổi Tiếng Việt / Tiếng Anh").kieuGoTarget!!
            assertEquals(space, MixedTypingUI.resolve(space, vniMode = true))
            val teen = hit("teencode", "Chính tả teencode").kieuGoTarget!!
            assertEquals(teen, MixedTypingUI.resolve(teen, vniMode = true))
        }
    }

    @Test fun vniNoteText() {
        assertEquals("Gõ VNI không làm đổi từ tiếng Anh nên không cần chỉnh phần này.", SettingCaption.vniMixedNote)
        assertEquals("VNI leaves English words as typed, so there is nothing to set here.", L10nTable.EN[SettingCaption.vniMixedNote])
        assertTrue(SettingCaption.vniMixedNote in SettingCaption.all)
    }

    // MARK: §0.4 + §6 bảng ẩn theo mục cha (06/11/2026)

    @Test fun typingAdvancedRowsVni() {
        assertEquals(listOf(TypingOption.SimpleTelex, TypingOption.FreeMarking, TypingOption.QuickTelex,
            TypingOption.ModernTone, TypingOption.Teencode), TypingOption.advancedRows(false))
        assertEquals(listOf(TypingOption.ModernTone, TypingOption.Teencode), TypingOption.advancedRows(true))
        assertEquals(TYPING_ADVANCED_SUMMARY, TypingOption.advancedSummary(false))
        assertEquals(TYPING_ADVANCED_SUMMARY_VNI, TypingOption.advancedSummary(true))
        assertEquals("Modern tones, teencode", L10nTable.EN[TYPING_ADVANCED_SUMMARY_VNI])
        // Tìm tới mục đang ẩn (VNI) ⇒ tô sáng bộ chọn Telex/VNI; mục còn hiện giữ đích.
        for (o in TypingOption.entries) {
            val expected = if (TypingOption.hidden(o, true)) TypingOption.InputMethod.target else o.target
            assertEquals(o.name, expected, TypingOption.resolve(o.target, vniMode = true))
            assertEquals(o.name, o.target, TypingOption.resolve(o.target, vniMode = false))
        }
        // Đích không phải kiểu gõ: không đụng.
        val mixed = MixedTypingItem.AutoRestore.target
        assertEquals(mixed, TypingOption.resolve(mixed, vniMode = true))
    }

    @Test fun suggestionBarHidesChildren() {
        assertEquals(SettingDeps.SuggestionRow.entries, SettingDeps.suggestionRows(true))
        // Thanh tắt ⇒ chỉ còn công tắc + Lọc từ nhạy cảm (không phụ thuộc).
        assertEquals(listOf(SettingDeps.SuggestionRow.Toggle, SettingDeps.SuggestionRow.FilterSensitive),
            SettingDeps.suggestionRows(false))
        // Chạm trượt (nhóm khác) ⇒ mờ + lý do.
        assertNull(SettingDeps.autoFixAdjacentReason(true))
        assertEquals("Cần bật Thanh gợi ý", SettingDeps.autoFixAdjacentReason(false))
        assertEquals("Needs Suggestion bar", L10nTable.EN[SettingDeps.NEEDS_SUGGESTIONS])
    }

    @Test fun vniDimsTelexOnlyFeatures() {
        assertNull(SettingDeps.telexOnlyReason(false))
        assertEquals(MixedTypingUI.TELEX_ONLY, SettingDeps.telexOnlyReason(true))
    }

    @Test fun swipeOffHidesChildren() {
        assertEquals(SettingDeps.SwipeRow.entries, SettingDeps.swipeRows(true))
        assertEquals(listOf(SettingDeps.SwipeRow.Toggle), SettingDeps.swipeRows(false))
    }

    /** Nguồn trang Sửa lỗi & gợi ý: "Thêm dấu" (Plus) có dòng khoá khi chưa mở khoá. */
    @Test fun addTonesPlusLocked() {
        val src = File(appSrc, "com/viettelex/android/ui/FeaturePages.kt").readText()
        assertTrue("PlusGate.isUnlocked(PlusFeature.SENTENCE_DIACRITICS)" in src)
        assertTrue("PlusLockedRow(tr(\"Thêm dấu\")" in src)
    }

    // MARK: §5(d) nhãn bảng §3 (chuỗi vi trong mã nguồn)

    @Test fun section3Labels() {
        val src = code(appSrc)
        for (label in listOf("Bỏ dấu tự do", "Bỏ dấu kiểu mới (oà, uý)", "Sửa dấu từ đã gõ", "Gợi ý số tiền",
                "Tự khôi phục từ tiếng Anh", "Thêm dấu", "Phản hồi khi chạm", "Sửa lỗi & gợi ý", "Riêng tư & sao lưu",
                "Gõ lẫn tiếng Anh", "Nâng cao"))
            assertTrue("thiếu nhãn «$label»", "\"$label\"" in src)
        assertTrue("chú thích Tự khôi phục phải có ví dụ", "(google, github)" in src)
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

    // MARK: chú thích một dòng (06/11/2026, cùng chữ với macOS + iOS)

    /** Mỗi chú thích ≤ 95 ký tự (cả tiếng Việt lẫn tiếng Anh), có bản dịch, không trùng. */
    @Test fun captionsAreShort() {
        assertTrue("bảng chú thích rỗng?", SettingCaption.all.size > 60)
        assertEquals("trùng chú thích", SettingCaption.all.size, SettingCaption.all.toSet().size)
        for (k in SettingCaption.all) {
            assertTrue("dài ${k.length}: $k", k.length <= 95)
            val en = L10nTable.EN[k]
            assertTrue("thiếu bản dịch: $k", !en.isNullOrBlank())
            assertTrue("dài ${en!!.length}: $en", en.length <= 95)
        }
    }

    /** Trang cài đặt không còn chú thích dài viết thẳng trong tr("…") (phải đi qua [SettingCaption]). */
    @Test fun settingsPagesUseCaptionTable() {
        val files = listOf("KieuGoNav.kt", "MixedTyping.kt", "FeaturePages.kt", "PrivacySection.kt", "BackupSection.kt", "Tabs.kt", "ThemePage.kt")
        val re = Regex("(?<![\\w.])tr\\(\"((?:[^\"\\\\\\n]|\\\\.)*)\"\\)")
        val long = ArrayList<String>()
        for (n in files) {
            val f = File(appSrc, "com/viettelex/android/ui/$n")
            for (m in re.findAll(f.readText())) if (m.groupValues[1].length > 95) long.add("$n: ${m.groupValues[1].take(60)}…")
        }
        // Ngoại lệ có chủ đích: trang Mẫu Câu (không phải trang cài đặt), hộp thoại xác nhận, onboarding.
        val allowed = listOf("Bấm ☰ trên bàn phím để chèn nhanh", "Mẫu có nội dung bắt đầu bằng https://", "YAML phẳng",
            "Cảnh báo này hiện với mọi bàn phím", "Bàn phím quên mọi từ đã học")
        val rest = long.filterNot { l -> allowed.any { it in l } }
        assertTrue("chú thích dài ngoài bảng SettingCaption:\n" + rest.joinToString("\n"), rest.isEmpty())
    }
}
