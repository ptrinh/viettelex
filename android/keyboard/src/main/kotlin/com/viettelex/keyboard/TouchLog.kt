package com.viettelex.keyboard

import java.io.File
import java.io.RandomAccessFile
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.concurrent.Executors

/**
 * Log gỡ lỗi chạm phím (port iOS TouchLog). TẮT mặc định (pref debugTouchLog). Ghi
 * filesDir/touchlog.txt trên thread nền, cap ~300 KB (giữ 150 KB mới). KÝ TỰ gõ chỉ
 * được ghi khi [recordsCharacters] = true — caller đặt = BuildConfig.DEBUG; bản
 * Release KHÔNG BAO GIỜ ghi nội dung gõ.
 */
object TouchLog {
    @Volatile var enabled = false
    @Volatile var recordsCharacters = false
        private set
    @Volatile private var file: File? = null
    private var seq = 0
    private val stamp = DateTimeFormatter.ofPattern("HH:mm:ss.SSS").withZone(ZoneId.systemDefault())
    private val io by lazy {
        Executors.newSingleThreadExecutor { r -> Thread(r, "vt-touchlog").apply { isDaemon = true } }
    }
    /** Chờ ghi xong (test). */
    internal var synchronous = false

    fun configure(file: File?, recordsCharacters: Boolean) {
        this.file = file
        this.recordsCharacters = recordsCharacters
    }

    fun write(line: String) {
        val f = file
        if (!enabled || f == null) return
        val stamped = stamp.format(Instant.now()) + " " + line + "\n"
        val job = Runnable { append(f, stamped) }
        if (synchronous) job.run() else io.execute(job)
    }

    private fun append(f: File, s: String) {
        try {
            if (f.exists() && f.length() > 300_000) {
                val keep = RandomAccessFile(f, "r").use { raf ->
                    val n = 150_000
                    raf.seek(raf.length() - n)
                    ByteArray(n).also { raf.readFully(it) }
                }
                f.writeBytes(keep)
            }
            f.appendText(s)
        } catch (_: Exception) {}
    }

    private fun chars(s: String?): String = if (recordsCharacters && s != null) " [$s]" else ""

    fun touchBegan(active: Int, batch: Int, lagMs: Double, hit: Boolean, y: Double, key: String? = null) {
        if (!enabled) return
        seq++
        val where = if (hit) "hit" else String.format("MISS y=%.0f", y)
        write(String.format("#%d BEGAN batch=%d active=%d lag=%.1fms ", seq, batch, active, lagMs) + where + chars(key))
    }

    fun buttonDown(name: String, lagMs: Double?) {
        if (!enabled) return
        write("$name DOWN lag=" + (lagMs?.let { String.format("%.1fms", it) } ?: "?"))
    }

    fun hitTest(target: String, y: Double) {
        if (!enabled) return
        write(String.format("HIT %s y=%.0f", target, y))
    }

    fun touchEnded(cancelled: Boolean, routed: Boolean) {
        if (!enabled) return
        write("${if (cancelled) "CANCELLED" else "ended"} routed=${if (routed) 1 else 0}")
    }

    fun key(kind: String, composing: Boolean, lagMs: Double, char: String? = null) {
        if (!enabled) return
        write(String.format("key=%s composing=%d handle=%.2fms", kind, if (composing) 1 else 0, lagMs) + chars(char))
    }

    fun edit(bs: Int, insertLen: Int, insert: String? = null) {
        if (!enabled) return
        write("edit bs=$bs ins=$insertLen" + chars(insert))
    }

    fun host(event: String, applyingEdit: Boolean, composing: Boolean) {
        if (!enabled) return
        write("host $event applyingEdit=${if (applyingEdit) 1 else 0} composing=${if (composing) 1 else 0}")
    }

    fun session(header: String) {
        if (!enabled) return
        write("=== keyboard appear — $header")
    }

    /** N dòng cuối (app: "Hiện log", 80 dòng). */
    fun tail(lines: Int = 80, f: File? = file): String {
        if (f == null || !f.exists()) return ""
        return try { f.readLines().takeLast(lines).joinToString("\n") } catch (_: Exception) { "" }
    }

    fun clear(f: File? = file) { try { f?.delete() } catch (_: Exception) {} }
}
