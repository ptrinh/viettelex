package com.viettelex.android.translate

import android.os.Handler
import android.os.Looper
import com.viettelex.android.ai.GeminiNano
import com.viettelex.android.ai.GeminiNanoBridge
import com.viettelex.keyboard.AITranslate
import com.viettelex.keyboard.TranslateDirection
import com.viettelex.keyboard.TranslateEngine
import com.viettelex.keyboard.TranslateResult
import com.viettelex.keyboard.TouchLog

/**
 * "Dịch bằng AI trên máy" (thử nghiệm, Keys.TRANSLATE_AI): hỏi Gemini Nano trước; lỗi / quá
 * [TIMEOUT_MS] / kết quả không qua [AITranslate.validate] ⇒ dịch bằng ML Kit ([fallback]) như thường.
 * Đoạn dài hơn [AITranslate.MAX_CHARS] ⇒ ML Kit ngay.
 */
class NanoFirstEngine(
    private val plan: TranslateDirection.Plan,
    private val fallback: TranslateEngine,
) : TranslateEngine {
    private val main = Handler(Looper.getMainLooper())
    private var closed = false
    private var settled = false

    override fun translate(text: String, onDone: (TranslateResult) -> Unit) {
        if (text.length > AITranslate.MAX_CHARS) { fallback.translate(text, onDone); return }
        val t0 = android.os.SystemClock.elapsedRealtime()
        fun toMlKit(why: String) {
            if (settled || closed) return
            settled = true
            TouchLog.write("translate ai → mlkit ($why)")
            fallback.translate(text, onDone)
        }
        main.postDelayed({ toMlKit("timeout") }, TIMEOUT_MS)
        GeminiNanoBridge.run(AITranslate.prompt(text, plan), MAX_TOKENS, GeminiNano.executor) { out ->
            main.post {
                if (settled || closed) return@post
                val ok = out?.let { AITranslate.validate(it, text, plan) }
                if (ok == null) { toMlKit(if (out == null) "unavailable" else "rejected"); return@post }
                settled = true
                TouchLog.write("translate ai ok ${android.os.SystemClock.elapsedRealtime() - t0}ms")
                onDone(TranslateResult.Ok(ok))
            }
        }
    }

    override fun close() {
        closed = true
        main.removeCallbacksAndMessages(null)
        fallback.close()
    }

    private companion object {
        const val TIMEOUT_MS = 8_000L
        const val MAX_TOKENS = 512
    }
}
