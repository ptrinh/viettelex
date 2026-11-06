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

    /**
     * Test ngân sách hiện bàn phím: gọi mỗi lần một blob được map lần đầu ([buffer]) hoặc giải
     * thành chuỗi ([text]) — biết dữ liệu nào bị nạp trên main trước khung đầu. null ở app thật.
     */
    @Volatile var onLoad: ((name: String, decode: Boolean) -> Unit)? = null

    /** Đã có nguồn blob (IME hoặc app đã install) — app gọi install chỉ khi chưa. */
    val installed: Boolean get() = provider != null

    fun install(provider: (String) -> ByteBuffer) {
        synchronized(cache) { cache.clear() }
        this.provider = provider
    }

    /** Blob `name` (little-endian, duplicate riêng — không đụng position chung). */
    fun buffer(name: String): ByteBuffer = synchronized(cache) {
        cache.getOrPut(name) {
            val p = provider ?: error("KeyboardData.install chưa được gọi ($name)")
            onLoad?.invoke(name, false)
            p(name).duplicate().order(ByteOrder.LITTLE_ENDIAN)
        }
    }

    /** Asset văn bản UTF-8 (seed, emoji data, yaml) — chỉ đọc khi cần. */
    fun text(name: String): String {
        onLoad?.invoke(name, true)
        val b = buffer(name).duplicate()
        b.position(0)
        val bytes = ByteArray(b.remaining())
        b.get(bytes)
        return String(bytes, Charsets.UTF_8)
    }
}
