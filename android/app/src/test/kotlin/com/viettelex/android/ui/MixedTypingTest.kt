package com.viettelex.android.ui

import com.viettelex.keyboard.Keys
import com.viettelex.keyboard.L10n
import com.viettelex.keyboard.tr
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Nhóm thu gọn "Gõ mixed Việt/Anh" (ui/MixedTyping.kt, docs/ONBOARDING-SPEC.md §4). */
class MixedTypingTest {
    @After fun reset() { L10n.lang = L10n.DEFAULT }

    /** Key lưu KHÔNG đổi khi chuyển chỗ ⇒ hành vi + sao lưu giữ nguyên (cùng tên key iOS). */
    @Test fun storageKeysUnchanged() {
        val expected = mapOf(
            MixedTypingItem.AutoRestore to "autoRestore", MixedTypingItem.ContextualEnglish to "contextualEnglish",
            MixedTypingItem.RetroEnglish to "retroactiveEnglish", MixedTypingItem.EnglishByFrequency to "englishByFrequency",
            MixedTypingItem.SpaceSwipeLanguage to "spaceSwipeLanguage", MixedTypingItem.SwipeEnglish to "swipeEnglish",
        )
        for (item in MixedTypingItem.entries) assertEquals(item.name, expected[item], item.prefKey)
        assertTrue(Keys.ENGINE_KEYS.containsAll(listOf(Keys.AUTO_RESTORE, Keys.CONTEXTUAL_ENGLISH,
            Keys.RETRO_ENGLISH_AUTO, Keys.ENGLISH_BY_FREQUENCY)))
    }

    @Test fun groupsFollowSpecOrder() {
        fun of(g: MixedTypingItem.Group) = MixedTypingItem.entries.filter { it.group == g }
        assertEquals(listOf(MixedTypingItem.AutoRestore, MixedTypingItem.ContextualEnglish, MixedTypingItem.RetroEnglish,
            MixedTypingItem.EnglishByFrequency), of(MixedTypingItem.Group.Recognition))
        assertEquals(listOf(MixedTypingItem.SpaceSwipeLanguage), of(MixedTypingItem.Group.Language))
        assertEquals(listOf(MixedTypingItem.SwipeEnglish, MixedTypingItem.UserDictionary), of(MixedTypingItem.Group.Suggest))
        assertNull(MixedTypingItem.Section.group)
    }

    @Test fun titlesTranslated() {
        L10n.lang = "en"
        assertEquals("Mixed Vietnamese/English typing", MixedTypingItem.Section.title)
        assertEquals("English detection", tr(MixedTypingItem.Group.Recognition.viTitle))
        for (g in MixedTypingItem.Group.entries) assertNotEquals(g.viTitle, tr(g.viTitle))
        for (item in MixedTypingItem.entries) assertNotEquals(item.viTitle, item.title)
    }

    /** Phụ thuộc cũ giữ nguyên; tìm tới mục con đang ẩn ⇒ cuộn về "Quyết định theo ngữ cảnh". */
    @Test fun dependentItemsVisibilityAndScrollTarget() {
        for (item in listOf(MixedTypingItem.RetroEnglish, MixedTypingItem.EnglishByFrequency)) {
            assertTrue(MixedTypingUI.isVisible(item, contextualEnglish = true, vniMode = false))
            assertFalse(MixedTypingUI.isVisible(item, contextualEnglish = false, vniMode = false))
            assertFalse(MixedTypingUI.isVisible(item, contextualEnglish = true, vniMode = true))
            assertEquals(item, MixedTypingUI.scrollTarget(item, true, false))
            assertEquals(MixedTypingItem.ContextualEnglish, MixedTypingUI.scrollTarget(item, false, false))
            assertEquals(MixedTypingItem.ContextualEnglish, MixedTypingUI.scrollTarget(item, true, true))
        }
        for (item in MixedTypingItem.entries - setOf(MixedTypingItem.RetroEnglish, MixedTypingItem.EnglishByFrequency))
            assertEquals(item, MixedTypingUI.scrollTarget(item, false, true))
    }

    /** Mặc định thu gọn (trạng thái chỉ trong phiên, không lưu). */
    @Test fun collapsedByDefault() {
        assertFalse(MixedTypingFocus.expanded.value)
        assertNull(MixedTypingFocus.request.value)
    }
}
