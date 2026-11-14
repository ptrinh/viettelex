package com.viettelex.android.ai

import android.os.Handler
import android.os.Looper
import com.viettelex.keyboard.ClipAddressAI
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Trích địa chỉ bằng Gemini Nano (ML Kit GenAI Prompt API → AICore của hệ thống; model chạy ở tiến
 * trình hệ thống, app không nhúng model). Chỉ được gọi ở ô địa chỉ khi luật thuần không ra
 * (KeyboardSession.aiAddress) — client tạo lười ở lần gọi đầu, không bao giờ lúc mở bàn phím.
 * Chữ không rời máy. Hạn [TIMEOUT_MS]; trả kết quả trên main thread đúng một lần.
 */
class GeminiNanoAddress : ClipAddressAI {
    private val main = Handler(Looper.getMainLooper())
    private val executor by lazy { Executors.newSingleThreadExecutor { r -> Thread(r, "vt-nano").apply { isDaemon = true } } }

    override fun extract(instructions: String, prompt: String, done: (String?) -> Unit) {
        val once = AtomicBoolean(false)
        fun finish(v: String?) { if (once.compareAndSet(false, true)) main.post { done(v) } }
        main.postDelayed({ finish(null) }, TIMEOUT_MS)
        GeminiNanoBridge.run("$instructions\n\n$prompt", executor) { finish(it) }
    }

    private companion object { const val TIMEOUT_MS = 10_000L }
}
