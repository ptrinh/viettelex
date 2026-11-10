package com.viettelex.android.ime

import android.content.Context
import android.inputmethodservice.InputMethodService
import android.os.Build
import android.view.inputmethod.InputMethodInfo
import android.view.inputmethod.InputMethodManager
import android.view.inputmethod.InputMethodSubtype

/**
 * Gõ giọng nói = chuyển sang IME giọng nói của hệ thống (vd Google voice typing) — như
 * Gboard: IME đó nghe xong tự trả về bàn phím trước. VietTelex không tự ghi âm (không
 * quyền micro, không mạng cho việc này).
 */
object VoicePicker {
    /** Một subtype của IME đã bật: [mode] = InputMethodSubtype.getMode() ("voice", "keyboard"…). */
    data class Sub(val mode: String, val locale: String = "")
    data class Candidate(val id: String, val packageName: String, val subtypes: List<Sub>)
    /** IME + chỉ số subtype (trong [Candidate.subtypes]) sẽ chuyển sang. */
    data class Pick(val id: String, val subtypeIndex: Int)

    private const val GOOGLE = "com.google.android.googlequicksearchbox"

    /**
     * Chọn IME giọng nói: IME khác chính mình, có subtype mode "voice"; ưu tiên Google voice
     * typing, rồi thứ tự hệ thống. Trong IME: ưu tiên subtype tiếng Việt, không thì cái đầu.
     */
    fun pick(cands: List<Candidate>, selfPackage: String): Pick? {
        val voice = cands.filter { c -> c.packageName != selfPackage && c.subtypes.any { it.mode == "voice" } }
        val best = voice.firstOrNull { it.packageName == GOOGLE } ?: voice.firstOrNull() ?: return null
        val idx = best.subtypes.indices.filter { best.subtypes[it].mode == "voice" }
        val vi = idx.firstOrNull { best.subtypes[it].locale.startsWith("vi") }
        return Pick(best.id, vi ?: idx.first())
    }
}

/** Nối [VoicePicker] với InputMethodManager thật. */
class VoiceInput(private val ims: InputMethodService) {
    private val imm get() = ims.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager

    class Target internal constructor(val imi: InputMethodInfo, val subtype: InputMethodSubtype)

    /**
     * Đọc lại mỗi lần vào ô mới (user có thể bật/tắt IME giọng nói trong Cài đặt) — IME dò bằng [probe]
     * trên worker SAU khung đầu rồi [apply] trên main. Chỉ main đọc/ghi.
     */
    private var target: Target? = null
    val available: Boolean get() = target != null

    /** Dò đồng bộ (main) — đường chạm 🎤 khi lần chuyển trước thất bại. */
    fun refresh() { apply(probe()) }

    /** 1 + N binder tới InputMethodManager; gọi được từ thread nền. */
    fun probe(): Target? = try { find() } catch (_: Exception) { null }

    /** Áp kết quả [probe] (main). */
    fun apply(t: Target?) { target = t }

    private fun find(): Target? {
        val m = imm
        val imis = m.enabledInputMethodList
        val subs = imis.map { imi ->
            val enabled = m.getEnabledInputMethodSubtypeList(imi, true)
            val list = enabled.ifEmpty { (0 until imi.subtypeCount).map { imi.getSubtypeAt(it) } }
            imi to list
        }
        val cands = subs.map { (imi, list) ->
            @Suppress("DEPRECATION")
            VoicePicker.Candidate(imi.id, imi.packageName, list.map { VoicePicker.Sub(it.mode ?: "", it.languageTag.ifEmpty { it.locale ?: "" }) })
        }
        val p = VoicePicker.pick(cands, ims.packageName) ?: return null
        val (imi, list) = subs.first { it.first.id == p.id }
        return Target(imi, list[p.subtypeIndex])
    }

    /** Chuyển sang IME giọng nói; false nếu không có / hệ thống từ chối. */
    fun launch(): Boolean {
        val t = target ?: return false
        return try {
            if (Build.VERSION.SDK_INT >= 28) ims.switchInputMethod(t.imi.id, t.subtype)
            else {
                val token = ims.window?.window?.attributes?.token ?: return false
                @Suppress("DEPRECATION") imm.setInputMethodAndSubtype(token, t.imi.id, t.subtype)
            }
            true
        } catch (_: Exception) { false }
    }
}
