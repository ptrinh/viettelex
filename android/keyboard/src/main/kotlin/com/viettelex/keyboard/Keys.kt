package com.viettelex.keyboard

/**
 * Tên SharedPreferences, key và file dùng chung IME (agent C) + app settings (agent D).
 * Key giữ nguyên tên iOS (App Group `group.com.viettelex`), spec §9.
 */
object Keys {
    const val PREFS = "viettelex"

    // Kiểu Gõ
    const val SIMPLE_TELEX = "simpleTelex"
    const val FREE_MARKING = "freeMarking"
    const val QUICK_TELEX = "quickTelex"
    const val MODERN_TONE = "modernTone"
    const val CONTEXTUAL_ENGLISH = "contextualEnglish"
    const val AUTO_FIX_ADJACENT = "autoFixAdjacent"
    const val TEENCODE = "teencode"
    // Tính Năng
    const val AUTO_RESTORE = "autoRestore"
    const val LIVE_SPELL_CHECK = "liveSpellCheck"
    const val SHOW_SUGGESTIONS = "showSuggestions"
    const val FILTER_SENSITIVE = "filterSensitive"
    const val TEMPLATES_ENABLED = "templatesEnabled"
    const val SHOW_SPACE_LOGO = "showSpaceLogo"
    const val HAPTIC_FEEDBACK = "hapticFeedback"
    /** Int −10…10 (dp mỗi hàng). */
    const val ROW_HEIGHT_ADJUST = "rowHeightAdjust"
    /** String JSON `[{"label":…,"text":…}]`; vắng ⇒ mặc định từ assets/ios-mau-cau.yml. */
    const val USER_TEMPLATES = "userTemplates"
    const val DEBUG_TOUCH_LOG = "debugTouchLog"
    // nội bộ IME
    const val SUGGESTION_BAR_COLLAPSED = "suggestionBarCollapsed"
    /** String, emoji nối bằng '\n' (xem [EmojiRecents]). */
    const val EMOJI_RECENTS = "emojiRecents"
    /** Long ms — app ghi khi user bấm "Xóa từ đã học" (đã xoá [USERLM_FILE]). */
    const val USERLM_RESET_AT = "userlmResetAt"

    // file trong filesDir
    const val USERLM_FILE = "userlm.bin"
    const val TOUCHLOG_FILE = "touchlog.txt"

    // assets
    const val ASSET_LEXICON = "vnlexicon.bin"
    const val ASSET_EMOJI_SUGGEST = "emojisuggest.bin"
    const val ASSET_SEED = "seed.tsv"
    const val ASSET_EMOJI_DATA = "emojidata.tsv"
    const val ASSET_TEMPLATES_YAML = "ios-mau-cau.yml"
    const val ASSET_SPACE_LOGO = "spacelogo.png"
}
