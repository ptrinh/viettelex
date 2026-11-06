package com.viettelex.keyboard

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Onboarding + hồ sơ (Onboarding.kt, docs/ONBOARDING-SPEC.md §2–§5): giá trị từng hồ sơ đúng bảng §3,
 * khớp / "Tuỳ chỉnh", người dùng cũ khi nâng cấp không chạy onboarding (thẻ một lần), "Bỏ qua" giữ
 * mặc định, sao lưu/khôi phục không đụng key onboarding. Song sinh iOS OnboardingTests.swift.
 */
class OnboardingTest {
    @After fun reset() { L10n.lang = L10n.DEFAULT }

    private val retro = "retroactiveEnglish"
    private val freq = "englishByFrequency"

    /** prefs giả: map + áp các ghi như OnboardingStore. */
    private class Store(val m: MutableMap<String, Any> = LinkedHashMap()) {
        fun migrate(settingKeys: Set<String> = OnboardingFlow.SETTING_KEYS) =
            OnboardingFlow.upgradeWrites(m.keys, settingKeys)?.also { m.putAll(it) }
        fun apply(p: OnboardingProfile, now: Long = 1000) { m.putAll(OnboardingSettings.writes(p, now)) }
        fun finish() { m[OnboardingFlow.DONE_KEY] = true }
        fun current() = OnboardingSettings.current { m[it] as? Boolean }
        fun screen(enabled: Boolean) = OnboardingFlow.screen(m[OnboardingFlow.DONE_KEY] as? Boolean ?: true,
            OnboardingProfile.of(m[OnboardingFlow.PROFILE_KEY] as? String), enabled)
    }

    // §3 bảng hồ sơ

    @Test fun profileValuesFollowSpecTable() {
        assertEquals(listOf("autoRestore", "contextualEnglish", retro, freq, "spaceSwipeLanguage", "swipeEnglish"), OnboardingSettings.KEYS)
        assertEquals(mapOf("autoRestore" to true, "contextualEnglish" to true, retro to false, freq to false,
            "spaceSwipeLanguage" to false, "swipeEnglish" to true), OnboardingProfile.VI.values)
        assertEquals(OnboardingSettings.KEYS.associateWith { true }, OnboardingProfile.MIXED.values)
        assertEquals("en = như mixed (§3)", OnboardingProfile.MIXED.values, OnboardingProfile.EN.values)
        assertEquals(KeyboardLanguage.EN, OnboardingProfile.EN.keyboardLanguage)
        assertEquals(KeyboardLanguage.VI, OnboardingProfile.MIXED.keyboardLanguage)
        assertEquals(KeyboardLanguage.VI, OnboardingProfile.VI.keyboardLanguage)
        assertEquals("thứ tự + id như iOS", listOf("vi", "mixed", "en"), OnboardingProfile.entries.map { it.id })
    }

    /** Hồ sơ `vi` = mặc định hiện tại; khớp mặc định sao lưu; key hồ sơ là cài đặt thường (có sao lưu). */
    @Test fun defaultsMatchBackupDefaults() {
        val backup = BackupSettings.all.associateBy { it.key }
        for (k in OnboardingSettings.KEYS) {
            val kind = backup[k]?.kind as? SettingKind.Bool ?: error("$k không trong sao lưu")
            assertEquals(k, kind.default, OnboardingSettings.DEFAULTS[k])
        }
        assertEquals(OnboardingSettings.DEFAULTS, OnboardingProfile.VI.values)
    }

    @Test fun applyWritesConcreteValuesAndLanguageRequest() {
        val s = Store()
        s.apply(OnboardingProfile.EN, now = 1000)
        assertEquals(OnboardingProfile.EN.values, s.current())
        assertEquals("en", s.m[OnboardingFlow.PROFILE_KEY])
        assertEquals("en@1000", s.m[KeyboardLanguageRequest.KEY])
        assertNull("áp hồ sơ không tự đánh dấu xong", s.m[OnboardingFlow.DONE_KEY])
        // Không lưu "chế độ": sửa một công tắc sau đó thì giữ nguyên.
        s.m["spaceSwipeLanguage"] = false
        assertEquals(false, s.current()["spaceSwipeLanguage"])
        s.apply(OnboardingProfile.VI, now = 2000)
        assertEquals(OnboardingSettings.DEFAULTS, s.current())
        assertEquals("vi@2000", s.m[KeyboardLanguageRequest.KEY])
    }

    // §4 khớp đúng / Tuỳ chỉnh

    @Test fun exactMatchAndCustom() {
        for (p in OnboardingProfile.entries) assertEquals(p, OnboardingSettings.match(p.values, p))
        assertEquals(OnboardingProfile.VI, OnboardingSettings.match(OnboardingSettings.DEFAULTS, null))
        assertEquals(OnboardingProfile.MIXED, OnboardingSettings.match(OnboardingProfile.MIXED.values, null))
        assertEquals(OnboardingProfile.MIXED, OnboardingSettings.match(OnboardingProfile.MIXED.values, OnboardingProfile.VI))
        assertEquals(OnboardingProfile.EN, OnboardingSettings.match(OnboardingProfile.MIXED.values, OnboardingProfile.EN))
        for (p in OnboardingProfile.entries) for (k in OnboardingSettings.KEYS) {
            val v = p.values.toMutableMap().also { it[k] = !it.getValue(k) }
            assertNull("$p lệch $k", OnboardingSettings.match(v, p))
        }
        assertEquals(OnboardingProfile.VI, OnboardingSettings.match(OnboardingSettings.DEFAULTS, OnboardingProfile.EN))
    }

    @Test fun changesAndConfirmation() {
        assertEquals(listOf(retro, freq, "spaceSwipeLanguage"), OnboardingSettings.changes(OnboardingSettings.DEFAULTS, OnboardingProfile.MIXED))
        assertEquals(emptyList<String>(), OnboardingSettings.changes(OnboardingProfile.MIXED.values, OnboardingProfile.EN))
        assertFalse(OnboardingSettings.needsConfirmation(OnboardingSettings.DEFAULTS, OnboardingProfile.MIXED, null))
        val custom = OnboardingSettings.DEFAULTS + ("autoRestore" to false)
        assertTrue(OnboardingSettings.needsConfirmation(custom, OnboardingProfile.MIXED, null))
        assertTrue(OnboardingSettings.needsConfirmation(custom, OnboardingProfile.VI, null))
    }

    // §2 luồng

    @Test fun screenFlow() {
        assertEquals(OnboardingFlow.Screen.CHOOSE, OnboardingFlow.screen(false, null, false))
        assertEquals(OnboardingFlow.Screen.CHOOSE, OnboardingFlow.screen(false, null, true))
        assertNull(OnboardingFlow.screen(false, OnboardingProfile.MIXED, false))
        assertEquals(OnboardingFlow.Screen.TRY_IT, OnboardingFlow.screen(false, OnboardingProfile.MIXED, true))
        assertNull(OnboardingFlow.screen(true, null, true))
        assertNull(OnboardingFlow.screen(true, OnboardingProfile.EN, true))
        // VNI: bỏ màn hỏi hồ sơ gõ lẫn tiếng Anh (SETTINGS-CLEANUP-SPEC §1).
        assertEquals(OnboardingFlow.Screen.TRY_IT, OnboardingFlow.screen(false, null, true, vniMode = true))
        assertNull(OnboardingFlow.screen(false, null, false, vniMode = true))
        assertNull(OnboardingFlow.screen(true, null, true, vniMode = true))
        assertEquals(OnboardingFlow.Screen.CHOOSE, OnboardingFlow.screen(false, null, true, vniMode = false))
    }

    @Test fun newUserSkipKeepsDefaults() {
        val s = Store()
        assertEquals(mapOf(OnboardingFlow.DONE_KEY to false), s.migrate())
        assertEquals(OnboardingFlow.Screen.CHOOSE, s.screen(false))
        s.finish()
        assertEquals(setOf(OnboardingFlow.DONE_KEY), s.m.keys)
        assertEquals(OnboardingSettings.DEFAULTS, s.current())
        assertNull(s.screen(true))
    }

    @Test fun newUserChoosesBeforeKeyboardEnabled() {
        val s = Store()
        s.migrate()
        s.apply(OnboardingProfile.MIXED)
        s.m[Keys.KEYBOARD_THEME] = "dark"; s.m[Keys.SHOW_SUGGESTIONS] = false
        assertNull("đã quyết định một lần", s.migrate())
        assertNull(s.screen(false))
        assertEquals(OnboardingFlow.Screen.TRY_IT, s.screen(true))
        s.finish()
        assertNull("màn 2 chỉ hiện một lần", s.screen(true))
    }

    // §5 người dùng cũ

    @Test fun upgradeDetection() {
        val newUser = mapOf(OnboardingFlow.DONE_KEY to false)
        val old = mapOf(OnboardingFlow.DONE_KEY to true, OnboardingFlow.TIP_KEY to true)
        assertEquals(newUser, OnboardingFlow.upgradeWrites(emptySet()))
        // Key IME tự ghi / key lạ ⇒ vẫn người mới.
        assertEquals(newUser, OnboardingFlow.upgradeWrites(setOf(Keys.PASTE_OFFERED_ID, Keys.EMOJI_RECENTS, Keys.AUTO_CORRECT_REJECTED, "plusUnlocked")))
        assertEquals(old, OnboardingFlow.upgradeWrites(setOf(Keys.SHOW_SUGGESTIONS)))
        assertEquals(old, OnboardingFlow.upgradeWrites(setOf(Keys.SHORTCUTS)))
        assertEquals(old, OnboardingFlow.upgradeWrites(setOf(Keys.USER_TEMPLATES)))
        assertNull(OnboardingFlow.upgradeWrites(setOf(OnboardingFlow.DONE_KEY, Keys.SHOW_SUGGESTIONS)))
    }

    @Test fun existingUserNeverOnboardedAndValuesUntouched() {
        val s = Store(linkedMapOf(Keys.AUTO_RESTORE to false, Keys.SPACE_SWIPE_LANGUAGE to true, Keys.UI_LANGUAGE to "en"))
        val before = s.m.toMap()
        assertEquals(mapOf(OnboardingFlow.DONE_KEY to true, OnboardingFlow.TIP_KEY to true), s.migrate())
        assertNull(s.screen(true)); assertNull(s.screen(false))
        assertEquals(before, s.m.filterKeys { it != OnboardingFlow.DONE_KEY && it != OnboardingFlow.TIP_KEY })
        s.m[OnboardingFlow.TIP_KEY] = false   // đóng thẻ
        assertNull(s.migrate())
        assertEquals(false, s.m[OnboardingFlow.TIP_KEY])
    }

    // sao lưu / khôi phục

    @Test fun backupRestoreUnaffected() {
        val own = listOf(OnboardingFlow.DONE_KEY, OnboardingFlow.PROFILE_KEY, OnboardingFlow.TIP_KEY,
            KeyboardLanguageRequest.KEY, KeyboardLanguageRequest.APPLIED_KEY)
        val backupKeys = BackupSettings.all.map { it.key }.toSet()
        for (k in own) assertFalse("$k không được vào sao lưu", k in backupKeys)
        val src = Store(); src.migrate(); src.apply(OnboardingProfile.EN); src.finish()
        val snap = BackupPrefs.snapshot({ src.m[it] }, emptyList(), null)
        val decoded = BackupCodec.decode(BackupCodec.encode(snap))
        for (k in own) assertNull(decoded.settings?.get(k))
        assertEquals(true, decoded.settings?.get(Keys.SPACE_SWIPE_LANGUAGE))
        val dst = Store(linkedMapOf(OnboardingFlow.DONE_KEY to true, OnboardingFlow.TIP_KEY to false))
        val plan = BackupPrefs.plan(decoded, { dst.m[it] }, emptyList())
        for (k in own) assertFalse(k in plan.writes)
        dst.m.putAll(plan.writes)
        assertEquals(true, dst.m[OnboardingFlow.DONE_KEY]); assertEquals(false, dst.m[OnboardingFlow.TIP_KEY])
        assertEquals(OnboardingProfile.EN.values, dst.current())
    }

    // ngôn ngữ khởi đầu (IME)

    @Test fun keyboardLanguageRequest() {
        assertEquals("en@1500", KeyboardLanguageRequest.encode(KeyboardLanguage.EN, 1500))
        assertNull(KeyboardLanguageRequest.pending(null, null))
        assertEquals(KeyboardLanguage.EN, KeyboardLanguageRequest.pending("en@1500", null))
        assertNull("áp một lần", KeyboardLanguageRequest.pending("en@1500", "en@1500"))
        assertEquals("chọn lại ⇒ áp lại", KeyboardLanguage.EN, KeyboardLanguageRequest.pending("en@1600", "en@1500"))
        assertEquals(KeyboardLanguage.VI, KeyboardLanguageRequest.pending("vi@1700", "en@1600"))
        assertNull(KeyboardLanguageRequest.pending("xx@1", null))
        assertNull(KeyboardLanguageRequest.pending("", null))
        assertEquals(true, OnboardingProfile.EN.values[Keys.SPACE_SWIPE_LANGUAGE])
        assertEquals(KeyboardLanguage.EN, KeyboardLanguage.effective("en", true))
    }

    @Test fun titlesTranslated() {
        L10n.lang = "en"
        assertEquals("Mostly Vietnamese", OnboardingProfile.VI.title)
        assertEquals("Vietnamese + lots of English", OnboardingProfile.MIXED.title)
        assertEquals("Mostly English", OnboardingProfile.EN.title)
        for (k in OnboardingSettings.KEYS) assertNotEquals(OnboardingSettings.viTitle(k), tr(OnboardingSettings.viTitle(k)))
    }
}
