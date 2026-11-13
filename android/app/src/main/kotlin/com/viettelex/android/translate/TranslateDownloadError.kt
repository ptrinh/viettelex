package com.viettelex.android.translate

/**
 * Lỗi tải gói ngôn ngữ ML Kit (MlKitException.errorCode) → câu cho người dùng. THUẦN (test được).
 * Mã (com.google.mlkit.common.MlKitException): 17 NETWORK_ISSUE, 101 NOT_ENOUGH_SPACE,
 * 15 DATA_LOSS / 102 MODEL_HASH_MISMATCH (tệp tải về hỏng). Mã lạ ⇒ câu chung kèm mã để dễ báo lỗi.
 */
object TranslateDownloadError {
    const val NETWORK_ISSUE = 17
    const val DATA_LOSS = 15
    const val NOT_ENOUGH_SPACE = 101
    const val MODEL_HASH_MISMATCH = 102

    const val GENERIC = "Chưa tải được — kiểm tra kết nối rồi thử lại." // l10n-key
    const val NEED_WIFI = "Chưa tải được — cần Wi-Fi (hoặc tắt “Chỉ tải qua Wi-Fi”)." // l10n-key
    const val NO_SPACE = "Không đủ dung lượng trống để tải gói dịch." // l10n-key
    const val CORRUPT = "Gói dịch tải về bị lỗi — thử tải lại." // l10n-key

    /** Câu tiếng Việt (khoá L10n) cho mã lỗi; [wifiOnly] = người dùng bật "Chỉ tải qua Wi-Fi". */
    fun of(code: Int?, wifiOnly: Boolean): String = when (code) {
        NOT_ENOUGH_SPACE -> NO_SPACE
        DATA_LOSS, MODEL_HASH_MISMATCH -> CORRUPT
        NETWORK_ISSUE -> if (wifiOnly) NEED_WIFI else GENERIC
        else -> GENERIC
    }

    /** Câu hiển thị (đã dịch theo [tr]); mã lạ (không phải lỗi mạng) được kèm theo để dễ báo lỗi. */
    fun text(code: Int?, wifiOnly: Boolean, tr: (String) -> String): String {
        val m = of(code, wifiOnly)
        return tr(m) + if (m == GENERIC && code != null && code != 0 && code != NETWORK_ISSUE) " ($code)" else ""
    }
}
