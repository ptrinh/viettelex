package com.viettelex.android.translate

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.google.mlkit.common.MlKit
import com.google.mlkit.common.MlKitException
import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.common.model.RemoteModelManager
import com.google.mlkit.nl.translate.TranslateRemoteModel
import com.google.mlkit.nl.translate.Translation
import com.google.mlkit.nl.translate.Translator
import com.google.mlkit.nl.translate.TranslatorOptions
import com.viettelex.keyboard.Cancellable
import com.viettelex.keyboard.KeepAlive
import com.viettelex.keyboard.MainThread
import com.viettelex.keyboard.TranslateDirection
import com.viettelex.keyboard.TranslateEngine
import com.viettelex.keyboard.TranslateEngineFactory
import com.viettelex.keyboard.TranslateResult

/**
 * Máy dịch ML Kit (on-device), lấy qua [TranslateFeature.load]. Chữ KHÔNG rời máy: Translator chạy
 * model cục bộ; mạng chỉ dùng khi người dùng bấm tải gói trong app.
 *
 * MlKitInitProvider bị gỡ (manifest app) ⇒ khởi tạo ML Kit ngay khi tạo backend — tức lúc
 * chạm "Dịch" / mở trang cài đặt dịch, không bao giờ lúc mở process.
 */
class MlKitBackend(ctx: Context) {
    init {
        try { MlKit.initialize(ctx.applicationContext) } catch (_: IllegalStateException) { /* đã khởi tạo */ }
    }

    private fun model(code: String) = TranslateRemoteModel.Builder(code).build()

    /**
     * Translator theo cặp ngôn ngữ, giữ [TRANSLATOR_TTL_MS] sau lượt dịch cuối (dịch vài câu liên
     * tiếp không nạp lại model mỗi lần), rồi đóng. Mọi truy cập trên main thread.
     */
    private val translators = KeepAlive<TranslateDirection.Plan, Translator>(TRANSLATOR_TTL_MS, MainLooper,
        create = { p -> Translation.getClient(TranslatorOptions.Builder().setSourceLanguage(p.from).setTargetLanguage(p.to).build()) },
        close = { it.close() })

    val engineFactory = TranslateEngineFactory { plan -> MlKitEngine(plan, translators) }

    /** Mã ngôn ngữ đã có gói trên máy; null = không đọc được. Callback main thread. */
    fun downloadedModels(onDone: (Set<String>?) -> Unit) {
        RemoteModelManager.getInstance().getDownloadedModels(TranslateRemoteModel::class.java)
            .addOnSuccessListener { ms -> onDone(ms.map { it.language }.toSet()) }
            .addOnFailureListener { onDone(null) }
    }

    /**
     * Tải tuần tự (DownloadConditions: chỉ Wi-Fi nếu bật); onDone(null) = xong hết, khác = mã lỗi
     * MlKitException của lỗi đầu tiên (0 = lỗi không phải MlKitException) — xem [TranslateDownloadError].
     */
    fun downloadModels(langs: List<String>, wifiOnly: Boolean, onDone: (Int?) -> Unit) {
        val cond = DownloadConditions.Builder().apply { if (wifiOnly) requireWifi() }.build()
        val mgr = RemoteModelManager.getInstance()
        fun next(i: Int) {
            if (i >= langs.size) { onDone(null); return }
            mgr.download(model(langs[i]), cond)
                .addOnSuccessListener { next(i + 1) }
                .addOnFailureListener { onDone((it as? MlKitException)?.errorCode ?: 0) }
        }
        next(0)
    }

    fun deleteModel(lang: String, onDone: () -> Unit) {
        RemoteModelManager.getInstance().deleteDownloadedModel(model(lang)).addOnCompleteListener { onDone() }
    }
}

/** Một lượt dịch; Translator lấy từ cache theo cặp ngôn ngữ, [close] trả lại (đóng sau TTL). */
private class MlKitEngine(
    private val plan: TranslateDirection.Plan,
    private val translators: KeepAlive<TranslateDirection.Plan, Translator>,
) : TranslateEngine {
    private var translator: Translator? = null
    private var closed = false

    override fun translate(text: String, onDone: (TranslateResult) -> Unit) {
        // Kiểm tra gói TRƯỚC: không bao giờ tự tải gói từ bàn phím.
        RemoteModelManager.getInstance().getDownloadedModels(TranslateRemoteModel::class.java)
            .addOnSuccessListener { ms ->
                if (closed) return@addOnSuccessListener
                // English: ML Kit coi là luôn có (pivot) — có thể không nằm trong danh sách ⇒ không đòi.
                val have = ms.map { it.language }.toSet() + "en"
                if (plan.from !in have || plan.to !in have) { onDone(TranslateResult.MissingModel); return@addOnSuccessListener }
                val t = translators.acquire(plan)
                translator = t
                t.translate(text)          // executor nền của ML Kit; listener về main thread
                    .addOnSuccessListener { if (!closed) onDone(TranslateResult.Ok(it)) }
                    .addOnFailureListener { if (!closed) onDone(TranslateResult.Failed(it.toString())) }
            }
            .addOnFailureListener { if (!closed) onDone(TranslateResult.Failed(it.toString())) }
    }

    override fun close() {
        closed = true
        translator?.let { translators.release(plan, it) }
        translator = null
    }
}

/** Main looper cho hẹn giờ đóng Translator. */
private object MainLooper : MainThread {
    private val h = Handler(Looper.getMainLooper())
    override fun post(r: Runnable) { h.post(r) }
    override fun postDelayed(delayMs: Long, r: Runnable): Cancellable {
        h.postDelayed(r, delayMs); return Cancellable { h.removeCallbacks(r) }
    }
}

/** Giữ Translator bấy lâu sau lượt dịch cuối. */
internal const val TRANSLATOR_TTL_MS = 30_000L
