package com.viettelex.android.ime

import android.text.InputType
import android.view.inputmethod.EditorInfo

/**
 * EditorInfo → cấu hình bàn phím (spec §12, đã chốt). THUẦN: chỉ đọc hai số
 * nguyên, hằng số Android inline lúc biên dịch ⇒ unit-test JVM được.
 */
data class FieldConfig(
    val kind: InputKind,
    /** Ô mật khẩu: literal, bỏ engine. */
    val isSecure: Boolean,
    /** Ô "không autocorrect" (URI/email/visible-password/filter) hoặc TYPE_NULL: literal. */
    val passthrough: Boolean,
    val capSentences: Boolean,
    /** Bar gợi ý được phép hiện (ẩn ở mật khẩu, passthrough, NO_SUGGESTIONS). */
    val suggestionsAllowed: Boolean,
    /** "return" | go | search | send | next | done. */
    val returnLabel: String,
    /** EditorInfo.IME_ACTION_* để performEditorAction; 0 ⇒ xuống dòng (KEYCODE_ENTER). */
    val actionId: Int,
    /** TYPE_NULL (terminal…): app chỉ hiểu key event. */
    val rawKeys: Boolean,
)

object FieldMapping {
    fun map(inputType: Int, imeOptions: Int): FieldConfig {
        val cls = inputType and InputType.TYPE_MASK_CLASS
        val variation = inputType and InputType.TYPE_MASK_VARIATION
        val flags = inputType and InputType.TYPE_MASK_FLAGS
        val rawKeys = inputType == InputType.TYPE_NULL
        val text = cls == InputType.TYPE_CLASS_TEXT

        val secure = (text && (variation == InputType.TYPE_TEXT_VARIATION_PASSWORD
                || variation == InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD
                || variation == InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD))
            || (cls == InputType.TYPE_CLASS_NUMBER && variation == InputType.TYPE_NUMBER_VARIATION_PASSWORD)

        val email = text && (variation == InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS
                || variation == InputType.TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS)
        val uri = text && variation == InputType.TYPE_TEXT_VARIATION_URI
        // URI (thanh địa chỉ Chrome) và FILTER (ô tìm trong Cài đặt/danh bạ) là nơi người
        // dùng GÕ TÌM KIẾM tiếng Việt → giữ Telex; auto-restore trả lại chữ Anh/URL.
        val passthrough = rawKeys || email ||
            (text && variation == InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD)

        val kind = when {
            cls == InputType.TYPE_CLASS_NUMBER || cls == InputType.TYPE_CLASS_PHONE
                || cls == InputType.TYPE_CLASS_DATETIME -> InputKind.NUMBER
            email -> InputKind.EMAIL
            uri -> InputKind.URL
            else -> InputKind.NORMAL
        }
        val capSentences = text && (flags and InputType.TYPE_TEXT_FLAG_CAP_SENTENCES) != 0
        // NO_SUGGESTIONS chỉ ẩn bar, KHÔNG tắt Telex (quyết định §12/§16.1).
        val noSuggest = text && (flags and InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS) != 0
        val suggestionsAllowed = !secure && !passthrough && !noSuggest && cls != InputType.TYPE_CLASS_NUMBER
            && cls != InputType.TYPE_CLASS_PHONE && cls != InputType.TYPE_CLASS_DATETIME

        val multiLine = text && (flags and InputType.TYPE_TEXT_FLAG_MULTI_LINE) != 0
        val noEnterAction = (imeOptions and EditorInfo.IME_FLAG_NO_ENTER_ACTION) != 0
        val action = imeOptions and EditorInfo.IME_MASK_ACTION
        var label = "return"
        var actionId = 0
        if (!multiLine && !noEnterAction) {
            when (action) {
                EditorInfo.IME_ACTION_GO -> { label = "go"; actionId = action }
                EditorInfo.IME_ACTION_SEARCH -> { label = "search"; actionId = action }
                EditorInfo.IME_ACTION_SEND -> { label = "send"; actionId = action }
                EditorInfo.IME_ACTION_NEXT -> { label = "next"; actionId = action }
                EditorInfo.IME_ACTION_DONE -> { label = "done"; actionId = action }
                EditorInfo.IME_ACTION_PREVIOUS -> { label = "return"; actionId = action }
            }
        }
        return FieldConfig(kind, secure, passthrough, capSentences, suggestionsAllowed,
            label, actionId, rawKeys)
    }
}
