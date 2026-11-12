package com.viettelex.android.translate

/**
 * Lỗi tải module Dịch (Play Feature Delivery, SplitInstallErrorCode) → câu cho người dùng + có nên mời mở
 * Google Play không. THUẦN (test được). Báo lỗi 12/11/2026: "Chưa tải được — kiểm tra kết nối rồi thử lại. (-15)" —
 * -15 = APP_NOT_OWNED (Play không coi app này thuộc tài khoản đang dùng trên máy: cài từ file APK rồi Play cập nhật,
 * hoặc máy có nhiều tài khoản) — chẳng liên quan kết nối; người dùng cần cài/cập nhật lại qua Google Play.
 * Mã: -2 MODULE_UNAVAILABLE, -6 NETWORK_ERROR, -10 INSUFFICIENT_STORAGE, -14 PLAY_STORE_NOT_FOUND, -15 APP_NOT_OWNED.
 */
object TranslateDownloadError {
    class Message(val viText: String, val openPlay: Boolean)

    const val GENERIC = "Chưa tải được — kiểm tra kết nối rồi thử lại." // l10n-key

    fun of(code: Int?): Message = when (code) {
        -15 -> Message("Google Play chưa ghi nhận VietTelex thuộc tài khoản trên máy (thường do cài từ file APK, hoặc Play đang dùng tài khoản khác). Mở Google Play, cài lại hoặc cập nhật VietTelex bằng tài khoản đó rồi thử lại.", true) // l10n-key
        -14 -> Message("Máy chưa có Google Play — tính năng Dịch cần Google Play để tải.", false) // l10n-key
        -10 -> Message("Không đủ dung lượng trống để tải tính năng Dịch (~7 MB).", false) // l10n-key
        -2 -> Message("Bản VietTelex này chưa có gói Dịch trên Google Play — cập nhật VietTelex lên bản mới nhất rồi thử lại.", true) // l10n-key
        else -> Message(GENERIC, false)
    }

    /** Câu hiển thị (đã dịch theo [tr]) kèm mã lỗi lạ để dễ báo lỗi. */
    fun text(code: Int?, tr: (String) -> String): String {
        val m = of(code)
        return tr(m.viText) + if (m.viText == GENERIC && code != null && code != 0) " ($code)" else ""
    }
}
