package com.viettelex.keyboard

/**
 * Setting bàn phím — mặc định y iOS (khác macOS: simpleTelex BẬT). Đọc lại mỗi lần
 * bàn phím hiện ([load]).
 */
data class KeyboardSettings(
    var freeMarking: Boolean = true,
    var simpleTelex: Boolean = true,
    var liveSpellCheck: Boolean = true,
    var autoRestore: Boolean = true,
    var quickTelex: Boolean = false,
    var modernTone: Boolean = false,
    /** Chính tả teencode — mặc định TẮT (issue #94). */
    var teencode: Boolean = false,
    var showSuggestions: Boolean = true,
    /** Đi theo showSuggestions (không có toggle riêng). */
    var learnWords: Boolean = true,
    var filterSensitive: Boolean = true,
    var hapticFeedback: Boolean = false,
    /** Gợi ý sửa lỗi chạm trượt (AdjacentKeyFixer) — mặc định BẬT. */
    var autoFixAdjacent: Boolean = true,
    /** Quyết định theo ngữ cảnh ("he is" giữ tiếng Anh) — mặc định BẬT. */
    var contextualEnglish: Boolean = true,
    // Phần UI (iOS đọc rải rác trong KeyboardView) — gom về đây cho IME.
    var templatesEnabled: Boolean = true,
    var showSpaceLogo: Boolean = true,
    /** −10…10 dp mỗi hàng. */
    var rowHeightAdjust: Int = 0,
    var debugTouchLog: Boolean = false,
    /** Giá trị Keys.USERLM_RESET_AT (0 = chưa từng xoá). */
    var userlmResetAt: Long = 0,
) {
    companion object {
        /** [get] trả giá trị thô của key (vd `prefs.all[key]`), null nếu vắng. */
        fun load(get: (String) -> Any?): KeyboardSettings {
            val s = KeyboardSettings()
            fun b(key: String, cur: Boolean): Boolean = (get(key) as? Boolean) ?: cur
            s.freeMarking = b(Keys.FREE_MARKING, s.freeMarking)
            s.simpleTelex = b(Keys.SIMPLE_TELEX, s.simpleTelex)
            s.liveSpellCheck = b(Keys.LIVE_SPELL_CHECK, s.liveSpellCheck)
            s.autoRestore = b(Keys.AUTO_RESTORE, s.autoRestore)
            s.quickTelex = b(Keys.QUICK_TELEX, s.quickTelex)
            s.modernTone = b(Keys.MODERN_TONE, s.modernTone)
            s.teencode = b(Keys.TEENCODE, s.teencode)
            s.showSuggestions = b(Keys.SHOW_SUGGESTIONS, s.showSuggestions)
            s.filterSensitive = b(Keys.FILTER_SENSITIVE, s.filterSensitive)
            s.hapticFeedback = b(Keys.HAPTIC_FEEDBACK, s.hapticFeedback)
            s.autoFixAdjacent = b(Keys.AUTO_FIX_ADJACENT, s.autoFixAdjacent)
            s.contextualEnglish = b(Keys.CONTEXTUAL_ENGLISH, s.contextualEnglish)
            s.templatesEnabled = b(Keys.TEMPLATES_ENABLED, s.templatesEnabled)
            s.showSpaceLogo = b(Keys.SHOW_SPACE_LOGO, s.showSpaceLogo)
            s.debugTouchLog = b(Keys.DEBUG_TOUCH_LOG, s.debugTouchLog)
            s.rowHeightAdjust = ((get(Keys.ROW_HEIGHT_ADJUST) as? Number)?.toInt() ?: 0).coerceIn(-10, 10)
            s.userlmResetAt = (get(Keys.USERLM_RESET_AT) as? Number)?.toLong() ?: 0
            s.learnWords = s.showSuggestions   // bật gợi ý = bật học (quyết định 2026-07-24)
            return s
        }
    }
}
