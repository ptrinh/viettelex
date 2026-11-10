package com.viettelex.android.ime

import com.viettelex.keyboard.Keys

/**
 * Các file SharedPreferences process IME đọc trên đường mở lạnh. `getSharedPreferences` bắt đầu nạp
 * file trên thread riêng NGAY khi gọi; lần đọc đầu mới chờ. Gọi lần lượt từng file đúng lúc cần thì
 * ba lần nạp nối đuôi nhau trên main ⇒ `VietTelexIME.onCreate` mở cả ba trước theo [PRIME_ORDER]:
 * hai file phụ trước (nạp nền song song), file cài đặt cuối (đọc ngay sau đó).
 */
internal object ImePrefFiles {
    /** Trạng thái bàn phím (không sao lưu, không kích listener cài đặt). */
    const val STATE = "ime_state"

    val PRIME_ORDER: List<String> = listOf(STATE, Keys.RUNTIME_PREFS, Keys.PREFS)
}
