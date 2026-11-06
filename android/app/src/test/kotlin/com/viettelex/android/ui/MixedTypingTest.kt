package com.viettelex.android.ui

import com.viettelex.keyboard.Keys
import com.viettelex.keyboard.L10n
import com.viettelex.keyboard.OnboardingProfile
import com.viettelex.keyboard.OnboardingSettings
import com.viettelex.keyboard.tr
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Nhóm thu gọn "Gõ lẫn tiếng Anh" (ui/MixedTyping.kt, docs/ONBOARDING-SPEC.md §4,
 * docs/SETTINGS-CLEANUP-SPEC.md §1).
 */
class MixedTypingTest {
    @After fun reset() { L10n.lang = L10n.DEFAULT }

    /** Key lưu KHÔNG đổi khi chuyển chỗ ⇒ hành vi + sao lưu giữ nguyên (cùng tên key iOS). */
    @Test fun storageKeysUnchanged() {
        val expected = mapOf(
            MixedTypingItem.AutoRestore to "autoRestore", MixedTypingItem.ContextualEnglish to "contextualEnglish",
            MixedTypingItem.RetroEnglish to "retroactiveEnglish", MixedTypingItem.EnglishByFrequency to "englishByFrequency",
            MixedTypingItem.SpaceSwipeLanguage to "spaceSwipeLanguage",
        )
        for (item in MixedTypingItem.entries) assertEquals(item.name, expected[item], item.prefKey)
        assertEquals("swipeEnglish", Keys.SWIPE_ENGLISH)
        assertTrue(Keys.ENGINE_KEYS.containsAll(listOf(Keys.AUTO_RESTORE, Keys.CONTEXTUAL_ENGLISH,
            Keys.RETRO_ENGLISH_AUTO, Keys.ENGLISH_BY_FREQUENCY)))
    }

    /** §1: cấp 1 = Vuốt phím cách + Từ điển cá nhân; công tắc nhận diện tiếng Anh ở trang "Nâng cao". */
    @Test fun placementFollowsSpec() {
        fun of(p: MixedTypingItem.Placement) = MixedTypingItem.entries.filter { it.placement == p && it != MixedTypingItem.Section }
        assertEquals(listOf(MixedTypingItem.SpaceSwipeLanguage, MixedTypingItem.UserDictionary), of(MixedTypingItem.Placement.Group))
        assertEquals(listOf(MixedTypingItem.AutoRestore, MixedTypingItem.ContextualEnglish, MixedTypingItem.RetroEnglish,
            MixedTypingItem.EnglishByFrequency), of(MixedTypingItem.Placement.Advanced))
        // "Vuốt từ tiếng Anh" không còn trong nhóm (đã về trang Gõ vuốt).
        assertTrue(MixedTypingItem.entries.none { it.viTitle == "Vuốt từ tiếng Anh" })
    }

    /** Ô tìm kiếm mở đúng chỗ: dòng cấp 1 ⇒ trang chính + mở nhóm; dòng Nâng cao ⇒ trang con. */
    @Test fun searchTargetsOpenRightPage() {
        for (item in MixedTypingItem.entries) {
            val t = item.target
            if (item.placement == MixedTypingItem.Placement.Advanced) {
                assertEquals(item.name, KieuGoPage.MixedAdvanced, t.page)
                assertFalse(item.name, t.expandMixed)
            } else {
                assertNull(item.name, t.page)
                assertTrue(item.name, t.expandMixed)
            }
        }
        assertEquals(MixedTypingItem.entries.size, MixedTypingItem.entries.map { it.target.id }.toSet().size)
    }

    @Test fun titlesTranslated() {
        assertEquals("Gõ lẫn tiếng Anh", MixedTypingItem.Section.title)
        L10n.lang = "en"
        assertEquals("Mixed Vietnamese/English typing", MixedTypingItem.Section.title)
        for (item in MixedTypingItem.entries) assertNotEquals(item.viTitle, item.title)
        for (k in listOf(MIXED_ADVANCED_SUMMARY, MixedTypingUI.TELEX_ONLY))
            assertNotEquals(k, tr(k))
    }

    /** Công tắc con ngay dưới "Quyết định theo ngữ cảnh": ngữ cảnh tắt ⇒ ẨN (SETTINGS-CLEANUP-SPEC §6). */
    @Test fun dependentItemsHiddenUnderContextual() {
        for (item in listOf(MixedTypingItem.RetroEnglish, MixedTypingItem.EnglishByFrequency)) {
            assertFalse(MixedTypingUI.hidden(item, vniMode = false, contextualEnglish = true))
            assertTrue(MixedTypingUI.hidden(item, vniMode = false, contextualEnglish = false))
            assertTrue(MixedTypingUI.hidden(item, vniMode = true, contextualEnglish = true))
            // Tìm kiếm tới mục đang ẩn ⇒ tô sáng công tắc cha.
            assertEquals(MixedTypingItem.ContextualEnglish.target, MixedTypingUI.resolve(item.target, false, contextualEnglish = false))
            assertEquals(item.target, MixedTypingUI.resolve(item.target, false, contextualEnglish = true))
        }
        for (item in MixedTypingItem.entries - setOf(MixedTypingItem.RetroEnglish, MixedTypingItem.EnglishByFrequency)) {
            assertFalse(item.name, MixedTypingUI.hidden(item, vniMode = false, contextualEnglish = false))
            assertEquals(item.name, item.target, MixedTypingUI.resolve(item.target, false, contextualEnglish = false))
        }
    }

    /** Bộ chọn hồ sơ vẫn áp đúng các key (kể cả "Vuốt từ tiếng Anh" đã dời sang trang Gõ vuốt). */
    @Test fun profileStillWritesMovedKeys() {
        val keys = OnboardingSettings.KEYS
        assertTrue(keys.containsAll(listOf(Keys.AUTO_RESTORE, Keys.CONTEXTUAL_ENGLISH, Keys.RETRO_ENGLISH_AUTO,
            Keys.ENGLISH_BY_FREQUENCY, Keys.SPACE_SWIPE_LANGUAGE, Keys.SWIPE_ENGLISH)))
        for (k in keys) assertEquals(k, true, OnboardingProfile.MIXED.values[k])
        val mixedVals = OnboardingProfile.MIXED.values
        assertEquals(OnboardingProfile.MIXED, OnboardingSettings.match(mixedVals, null))
    }

    /** Mặc định thu gọn, trang chính (trạng thái chỉ trong phiên, không lưu). */
    @Test fun collapsedByDefault() {
        assertFalse(MixedTypingFocus.expanded.value)
        assertNull(KieuGoNav.request.value)
        assertNull(KieuGoNav.page.value)
    }
}
