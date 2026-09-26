package com.viettelex.keyboard

import java.io.File
import java.io.RandomAccessFile
import java.nio.channels.FileChannel

/** Nạp assets thật (android/app/src/main/assets) bằng mmap — như IME. */
object TestAssets {
    private val dir: File by lazy {
        listOf(File("../app/src/main/assets"), File("app/src/main/assets"), File("android/app/src/main/assets"))
            .first { File(it, Keys.ASSET_LEXICON).exists() }
    }
    @Volatile private var installed = false
    fun install() {
        if (installed) return
        synchronized(this) {
            if (installed) return
            KeyboardData.install { name ->
                RandomAccessFile(File(dir, name), "r").use { f ->
                    f.channel.map(FileChannel.MapMode.READ_ONLY, 0, f.length())
                }
            }
            installed = true
        }
    }
}

/** Mock proxy ghi lại luồng xoá/chèn (≈ iOS MockProxy). */
class MockProxy(var isSecureField: Boolean = false) : TextProxy {
    val sb = StringBuilder()
    val text: String get() = sb.toString()
    override val isSecure: Boolean get() = isSecureField
    override fun insertText(text: String) { sb.append(text) }
    override fun deleteCodePoints(count: Int) {
        repeat(count) { if (sb.isNotEmpty()) sb.setLength(sb.offsetByCodePoints(sb.length, -1)) }
    }
    override fun deleteBackward() = deleteCodePoints(1)
    override fun contextBeforeInput(): String = text
    override fun clearAll() { sb.setLength(0) }
    override fun confirmTail(expected: String): Boolean = text.endsWith(expected)
    /** Sửa lại từ đã chốt (IcProxy: ô COMMIT thường). */
    var reEdit = true
    /** Chữ SAU con trỏ; null = không đọc được. */
    var after: String? = ""
    var selection = false
    override val canReEdit: Boolean get() = reEdit
    override val hasSelection: Boolean get() = selection
    override fun contextAfterInput(): String? = after
}
