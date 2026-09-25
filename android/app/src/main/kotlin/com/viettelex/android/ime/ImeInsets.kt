package com.viettelex.android.ime

/**
 * Đệm dưới hàng phím đáy cho nút hệ thống của IME (⌄ ẩn bàn phím / 🌐 đổi bàn phím)
 * và nav bar 3 nút. Android 15+ vẽ IME edge-to-edge: các nút đó đè LÊN hàng phím đáy
 * nếu không chừa dải như Gboard. THUẦN — pinned by ImeInsetsTest.
 */
object ImeInsets {
    /**
     * @param navBottom      WindowInsets navigationBars().bottom (px)
     * @param tappableBottom WindowInsets tappableElement().bottom (px)
     * @param fallbackNavBar chiều cao nav bar IME của hệ thống (px, từ dimen android) —
     *                       chỉ dùng khi API ≥ 35 mà insets không tới view (bị ancestor nuốt).
     * @param insetsKnown    đã nhận được WindowInsets thật hay chưa
     */
    fun bottomPad(sdk: Int, navBottom: Int, tappableBottom: Int, fallbackNavBar: Int, insetsKnown: Boolean): Int {
        val reported = maxOf(navBottom, tappableBottom, 0)
        if (reported > 0) return reported
        // API < 35: hệ thống tự đặt cửa sổ IME TRÊN nav bar ⇒ không đệm (tránh đệm đôi).
        if (sdk < 35) return 0
        return if (insetsKnown) 0 else maxOf(fallbackNavBar, 0)
    }

    /** Tổng chiều cao input view. */
    fun totalHeight(strip: Int, keyArea: Int, bottomPad: Int) = strip + keyArea + bottomPad
}
