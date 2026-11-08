package com.viettelex.keyboard

import java.io.File
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Màn "Hiệu ứng khi bấm phím": chú thích dưới lưới chỉ là mô tả của kiểu ĐANG CHỌN + một câu chung (Phil 11/2026) —
 * mọi kiểu (trừ "Không") có mô tả vi + en ngắn; đoạn liệt kê dài cũ không còn. iOS: KeyEffectDescriptionTests.
 */
class KeyEffectDescriptionTest {
    @AfterTest fun reset() { L10n.lang = L10n.DEFAULT }

    @Test fun everyEffectHasShortBilingualDescription() {
        assertNull(KeyEffect.NONE.viDescription)
        assertNull(KeyEffect.NONE.description)
        for (e in KeyEffect.entries) {
            if (e == KeyEffect.NONE) continue
            val vi = e.viDescription ?: error("thiếu mô tả: $e")
            val en = L10nTable.EN[vi] ?: error("thiếu bản dịch mô tả: $e")
            assertTrue(vi.isNotBlank() && en.isNotBlank(), "mô tả rỗng: $e")
            assertTrue(vi.length <= 200, "mô tả quá dài: $e (${vi.length})")
            assertTrue(en.length <= 200, "mô tả quá dài (en): $e (${en.length})")
        }
        val all = KeyEffect.entries.mapNotNull { it.viDescription }
        assertEquals(all.size, all.toSet().size, "mỗi kiểu một mô tả riêng")
    }

    @Test fun descriptionFollowsLanguage() {
        assertEquals(KeyEffect.GOAL.viDescription, KeyEffect.GOAL.description)
        L10n.lang = "en"
        assertEquals(L10nTable.EN[KeyEffect.GOAL.viDescription!!], KeyEffect.GOAL.description)
        assertNotEquals(KeyEffect.GOAL.viDescription, KeyEffect.GOAL.description)
    }

    /** Dữ kiện lỗi thời: "vào" thường không còn là từ cổ vũ (chỉ "vàooo"); Giảm chuyển động KHÔNG tắt hiệu ứng. */
    @Test fun factsUpToDate() {
        val goal = KeyEffect.GOAL.viDescription!!
        assertFalse("\"vào\"" in goal, goal)
        assertTrue("vàooo" in goal)
        for (e in KeyEffect.entries) {
            val vi = e.viDescription ?: continue
            assertFalse("Giảm chuyển động" in vi, "$e")
            assertFalse("Reduce Motion" in (L10nTable.EN[vi] ?: ""), "$e")
        }
    }

    @Test fun oldLongFooterGone() {
        val page = listOf("../app/src/main/kotlin", "app/src/main/kotlin").map { File(it) }.first { it.isDirectory }
            .resolve("com/viettelex/android/ui/KeyEffectPage.kt").readText()
        for (old in listOf("Hình nhỏ bay ra từ phím vừa bấm", "Matrix, Mực loang, Sóng nước chạy dưới phím", "Rung combo rung cả hàng phím")) {
            assertFalse(old in page, old)
            assertTrue(L10nTable.EN.keys.none { it.startsWith(old) }, old)
        }
        assertTrue("current.description" in page)
    }
}
