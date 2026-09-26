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
    /** Ô email / visible-password (không nhiều dòng) / FORCE_ASCII / số / TYPE_NULL: literal. */
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
    /** Ô số: TYPE_NUMBER_FLAG_SIGNED ⇒ phím "−"; FLAG_DECIMAL ⇒ phím "," "." (bàn NUMPAD). */
    val numberSigned: Boolean = false,
    val numberDecimal: Boolean = false,
    /** TYPE_TEXT_FLAG_CAP_WORDS / CAP_CHARACTERS (auto-shift theo từ / luôn hoa). */
    val capWords: Boolean = false,
    val capCharacters: Boolean = false,
    /** IME_FLAG_NO_PERSONALIZED_LEARNING (Chrome ẩn danh…): không học từ. */
    val noLearning: Boolean = false,
)

object FieldMapping {
    /** Pixel Launcher: ô tìm đặt MULTI_LINE + NO_ENTER_ACTION nhưng Enter phải là "tìm". */
    const val PIXEL_LAUNCHER = "com.google.android.apps.nexuslauncher"

    /**
     * @param packageName EditorInfo.packageName (workaround theo app).
     * @param hasActionLabel EditorInfo.actionLabel != null — app tự đặt nhãn Enter,
     *   bấm Enter ⇒ performEditorAction([customActionId]) (≈ LatinIME IME_ACTION_CUSTOM_LABEL).
     * @param customActionId EditorInfo.actionId.
     */
    fun map(inputType: Int, imeOptions: Int, packageName: String? = null,
            hasActionLabel: Boolean = false, customActionId: Int = 0): FieldConfig {
        val cls = inputType and InputType.TYPE_MASK_CLASS
        val variation = inputType and InputType.TYPE_MASK_VARIATION
        val flags = inputType and InputType.TYPE_MASK_FLAGS
        val rawKeys = inputType == InputType.TYPE_NULL
        val text = cls == InputType.TYPE_CLASS_TEXT

        val multiLineFlag = text && (flags and InputType.TYPE_TEXT_FLAG_MULTI_LINE) != 0
        // VISIBLE_PASSWORD + MULTI_LINE: vài app RN/Flutter dùng VISIBLE_PASSWORD chỉ để tắt
        // gợi ý của bàn phím hệ thống ở ô CHAT — mật khẩu không bao giờ nhiều dòng ⇒ vẫn gõ Telex.
        val visiblePw = text && variation == InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD
        val fakeVisiblePw = visiblePw && multiLineFlag
        val secure = (text && (variation == InputType.TYPE_TEXT_VARIATION_PASSWORD
                || variation == InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD
                || (visiblePw && !fakeVisiblePw)))
            || (cls == InputType.TYPE_CLASS_NUMBER && variation == InputType.TYPE_NUMBER_VARIATION_PASSWORD)

        val email = text && (variation == InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS
                || variation == InputType.TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS)
        val uri = text && variation == InputType.TYPE_TEXT_VARIATION_URI
        // URI (thanh địa chỉ Chrome) và FILTER (ô tìm trong Cài đặt/danh bạ) là nơi người
        // dùng GÕ TÌM KIẾM tiếng Việt → giữ Telex; auto-restore trả lại chữ Anh/URL.
        val numeric = cls == InputType.TYPE_CLASS_NUMBER || cls == InputType.TYPE_CLASS_PHONE
            || cls == InputType.TYPE_CLASS_DATETIME
        // Bàn số chèn ký tự literal, không bao giờ qua engine Telex.
        // IME_FLAG_FORCE_ASCII: app yêu cầu chỉ ASCII (mã, tên đăng nhập…) ⇒ literal.
        val forceAscii = (imeOptions and EditorInfo.IME_FLAG_FORCE_ASCII) != 0
        val passthrough = rawKeys || numeric || email || forceAscii || (visiblePw && !fakeVisiblePw)

        val kind = when {
            cls == InputType.TYPE_CLASS_PHONE -> InputKind.PHONE
            cls == InputType.TYPE_CLASS_DATETIME -> InputKind.DATETIME
            cls == InputType.TYPE_CLASS_NUMBER -> InputKind.NUMBER
            email -> InputKind.EMAIL
            uri -> InputKind.URL
            else -> InputKind.NORMAL
        }
        val capSentences = text && (flags and InputType.TYPE_TEXT_FLAG_CAP_SENTENCES) != 0
        val capWords = text && (flags and InputType.TYPE_TEXT_FLAG_CAP_WORDS) != 0
        val capCharacters = text && (flags and InputType.TYPE_TEXT_FLAG_CAP_CHARACTERS) != 0
        // NO_SUGGESTIONS chỉ ẩn bar, KHÔNG tắt Telex (quyết định §12/§16.1).
        // Cờ mâu thuẫn (Google Keep: NO_SUGGESTIONS + AUTO_CORRECT/AUTO_COMPLETE) ⇒ app thật ra
        // muốn gợi ý → bỏ qua NO_SUGGESTIONS (như AnySoftKeyboard IMEUtil).
        val wantsAssist = (flags and (InputType.TYPE_TEXT_FLAG_AUTO_CORRECT or InputType.TYPE_TEXT_FLAG_AUTO_COMPLETE)) != 0
        val noSuggest = text && !wantsAssist && ((flags and InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS) != 0
            || fakeVisiblePw)   // ô chat "VISIBLE_PASSWORD" muốn tắt gợi ý: tôn trọng như NO_SUGGESTIONS
        val suggestionsAllowed = !secure && !passthrough && !noSuggest && cls != InputType.TYPE_CLASS_NUMBER
            && cls != InputType.TYPE_CLASS_PHONE && cls != InputType.TYPE_CLASS_DATETIME

        // Pixel Launcher (HeliBoard AppWorkarounds, issue #1989): gỡ MULTI_LINE/NO_ENTER_ACTION.
        val pixelLauncher = packageName == PIXEL_LAUNCHER
        val multiLine = multiLineFlag && !pixelLauncher
        val noEnterAction = (imeOptions and EditorInfo.IME_FLAG_NO_ENTER_ACTION) != 0 && !pixelLauncher
        val action = imeOptions and EditorInfo.IME_MASK_ACTION
        var label = "return"
        var actionId = 0
        if (!multiLine && hasActionLabel && customActionId != 0) {
            // Nhãn riêng của app ("Đăng", "Lưu"…) thắng NO_ENTER_ACTION (≈ LatinIME), nhưng
            // ô nhiều dòng vẫn xuống dòng. Chưa vẽ chữ nhãn → icon ✓.
            label = "done"; actionId = customActionId
        } else if (!multiLine && !noEnterAction) {
            when (action) {
                EditorInfo.IME_ACTION_GO -> { label = "go"; actionId = action }
                EditorInfo.IME_ACTION_SEARCH -> { label = "search"; actionId = action }
                EditorInfo.IME_ACTION_SEND -> { label = "send"; actionId = action }
                EditorInfo.IME_ACTION_NEXT -> { label = "next"; actionId = action }
                EditorInfo.IME_ACTION_DONE -> { label = "done"; actionId = action }
                EditorInfo.IME_ACTION_PREVIOUS -> { label = "return"; actionId = action }
            }
        }
        val isNumber = cls == InputType.TYPE_CLASS_NUMBER
        return FieldConfig(kind, secure, passthrough, capSentences, suggestionsAllowed,
            label, actionId, rawKeys,
            // Chrome gửi <input type=number> là DECIMAL không SIGNED nhưng web cho phép số âm
            // → DECIMAL cũng hiện "−" (như Gboard).
            numberSigned = isNumber && (flags and (InputType.TYPE_NUMBER_FLAG_SIGNED or InputType.TYPE_NUMBER_FLAG_DECIMAL)) != 0,
            numberDecimal = isNumber && (flags and InputType.TYPE_NUMBER_FLAG_DECIMAL) != 0,
            capWords = capWords, capCharacters = capCharacters,
            noLearning = (imeOptions and EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING) != 0)
    }
}
