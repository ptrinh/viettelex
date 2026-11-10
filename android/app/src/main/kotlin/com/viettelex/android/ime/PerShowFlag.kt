package com.viettelex.android.ime

/**
 * Cờ hệ thống đọc tối đa MỘT lần mỗi lần hiện bàn phím, và chỉ khi có tính năng thật sự cần
 * (vd. Trình tiết kiệm pin cho Đập chuột / Đèn rọi / Lơ lửng — binder tới PowerManager).
 * IME gọi [reset] ở mỗi lần hiện; [get] lần đầu mới đọc. THUẦN — pinned by PerShowFlagTest.
 */
internal class PerShowFlag(private val read: () -> Boolean) {
    private var cached: Boolean? = null
    /** Số lần đọc thật (test). */
    var reads = 0
        private set

    fun reset() { cached = null }

    fun get(): Boolean = cached ?: read().also { reads++; cached = it }
}
