package com.viettelex.android.translate

import android.content.Context
import com.viettelex.keyboard.TranslateEngineFactory

/**
 * Dịch trên máy (ML Kit Translation) — nằm thẳng trong app. Trước đây là module Play Feature Delivery
 * on-demand `:translate`, nhưng SplitInstall báo APP_NOT_OWNED (-15) cả với máy cài từ Google Play
 * (#162) ⇒ bỏ module, ML Kit vào app gốc (APK GitHub cũng dùng được).
 *
 * Gói ngôn ngữ (~30 MB mỗi thứ tiếng) vẫn chỉ tải khi người dùng bấm trong app ([MlKitBackend.downloadModels]).
 * Backend (khởi tạo ML Kit) chỉ tạo lúc chạm "Dịch" / mở trang cài đặt dịch — không bao giờ lúc khởi động
 * process (MlKitInitProvider bị gỡ trong manifest app).
 */
object TranslateFeature {
    @Volatile private var backend: MlKitBackend? = null

    fun load(ctx: Context): MlKitBackend {
        backend?.let { return it }
        synchronized(this) {
            return backend ?: MlKitBackend(ctx.applicationContext).also { backend = it }
        }
    }

    /** Factory cho bàn phím: gói chưa tải ⇒ máy dịch trả MissingModel (nhắc mở app). */
    fun engineFactory(ctx: Context): TranslateEngineFactory = TranslateEngineFactory { plan ->
        load(ctx).engineFactory.create(plan)
    }
}
