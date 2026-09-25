package com.viettelex.keyboard

import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Nguồn blob tĩnh (assets). IME gọi [install] một lần với provider trả ByteBuffer
 * (khuyên mmap). Module giữ thuần JVM; blob chỉ đọc bằng absolute get (thread-safe).
 */
object KeyboardData {
    @Volatile private var provider: ((String) -> ByteBuffer)? = null
    private val cache = HashMap<String, ByteBuffer>()

    fun install(provider: (String) -> ByteBuffer) {
        synchronized(cache) { cache.clear() }
        this.provider = provider
    }

    /** Blob `name` (little-endian, duplicate riêng — không đụng position chung). */
    fun buffer(name: String): ByteBuffer = synchronized(cache) {
        cache.getOrPut(name) {
            val p = provider ?: error("KeyboardData.install chưa được gọi ($name)")
            p(name).duplicate().order(ByteOrder.LITTLE_ENDIAN)
        }
    }

    /** Asset văn bản UTF-8 (seed, emoji data, yaml) — chỉ đọc khi cần. */
    fun text(name: String): String {
        val b = buffer(name).duplicate()
        b.position(0)
        val bytes = ByteArray(b.remaining())
        b.get(bytes)
        return String(bytes, Charsets.UTF_8)
    }
}
