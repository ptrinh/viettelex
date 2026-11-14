package com.viettelex.keyboard

/**
 * VietTelex Plus — cấu hình sản phẩm (đổi ID ở ĐÂY cho khớp Play Console).
 * Module thuần JVM: không phụ thuộc Billing; app ghi cờ, IME chỉ đọc.
 */
object PlusConfig {
    /**
     * CÔNG TẮC THANH TOÁN. `false` = chưa bán: [PlusGate] mở MỌI tính năng Plus
     * cho mọi người. Chỉ bật `true` sau khi đã tạo sản phẩm trên Play Console
     * (xem android/store/PRODUCTS.md). BẬT 27/09/2026 (Phil) cho bản 1.2 — upload bản này
     * lên track nội bộ để Play mở mục sản phẩm, TẠO 4 sản phẩm rồi mới phát hành rộng.
     */
    const val PAYWALL_ENABLED = true

    /** In-app, mua một lần (acknowledge, không consume). Giá: 69.000đ. */
    const val PLUS_PRODUCT_ID = "plus"

    /** In-app consumable (consume sau khi mua): 25.000đ / 49.000đ / 99.000đ. */
    val TIP_PRODUCT_IDS = listOf("tip_small", "tip_medium", "tip_large")

    val ALL_PRODUCT_IDS: List<String> get() = listOf(PLUS_PRODUCT_ID) + TIP_PRODUCT_IDS

    /** Giá gợi ý khi Play chưa trả giá thật. */
    const val PLUS_PRICE_HINT = "69.000đ"

    /** Bản miễn phí vẫn ghim được tối đa chừng này mục clipboard. */
    const val FREE_PINNED_CLIP_LIMIT = 5
}

/**
 * Tính năng thuộc gói Plus. LUÔN MIỄN PHÍ (không bao giờ thêm vào đây): toàn bộ
 * phần gõ (Telex/VNI, bỏ dấu tự do, khôi phục tiếng Anh, sửa dấu từ đã gõ), gợi
 * ý/emoji/bigram, gõ vuốt, gõ tắt cơ bản, mẫu câu, hàng số, một tay, vuốt ⌫,
 * trackpad, theme hệ thống + sáng/tối + tương phản cao, sao lưu/nhập file.
 */
enum class PlusFeature(val viTitle: String, val viDetail: String) {
    PREMIUM_THEMES("Theme cao cấp & ảnh nền", "Thêm bộ màu bàn phím và đặt ảnh riêng làm nền."),
    SENTENCE_DIACRITICS("Thêm dấu cả câu", "Gõ không dấu cả câu, một chạm thêm dấu."),
    ADVANCED_CLIPBOARD("Clipboard nâng cao", "Ghim không giới hạn, chip tách số tài khoản, số điện thoại, mã OTP."),
    CLOUD_SYNC("Đồng bộ", "Cài đặt, gõ tắt và mẫu câu theo bạn sang máy Android khác qua Google Drive."),
    TEXT_TOOLS("Công cụ văn bản", "Đổi HOA/thường, hoa đầu từ/đầu câu, xoá dấu tiếng Việt."),
    TRANSLATE("Dịch trên máy", "Dịch đoạn vừa gõ hoặc vùng chọn giữa tiếng Việt và ngôn ngữ bạn chọn — ngay trên máy, không gửi chữ đi đâu."),
    THANKS_BADGE("Huy hiệu cảm ơn", "Dấu ★ nhỏ trong app — lời cảm ơn vì đã ủng hộ.");

    /** Hiển thị theo ngôn ngữ giao diện ([L10n]). */
    val title: String get() = tr(viTitle)
    val detail: String get() = tr(viDetail)

    /**
     * "Cách dùng" một dòng trên màn Plus — chỉ ĐÚNG chỗ bật / lối vào (góp ý Hữu Đông
     * 28/09/2026: mua Plus xong không biết "Thêm dấu cả câu" nằm đâu).
     */
    val howTo: String get() = when (this) {
        PREMIUM_THEMES -> tr("Cách dùng: Tính Năng → Giao diện → chọn theme hoặc ảnh nền.")
        SENTENCE_DIACRITICS -> tr("Cách dùng: bật “Thêm dấu” ở Tính Năng → Sửa lỗi & gợi ý, gõ không dấu cả câu (hom nay troi dep), gõ dấu cách rồi chạm chip ở đầu thanh gợi ý. Hoặc chạm “Thêm dấu” trong thẻ Công cụ (☰) / bảng sửa văn bản.")
        ADVANCED_CLIPBOARD -> tr("Cách dùng: bật Lịch sử clipboard (Tính Năng → Riêng tư & sao lưu), chạm nút clipboard trên thanh gợi ý. Copy STK/SĐT/OTP → chip “Dán …” hiện trên thanh gợi ý.")
        CLOUD_SYNC -> tr("Cách dùng: Tính Năng → Riêng tư & sao lưu → bật Đồng bộ qua Google Drive trên mỗi máy Android. Chuyển sang iPhone: Xuất / nhập file.")
        TEXT_TOOLS -> tr("Cách dùng: chạm ☰ trên thanh gợi ý → thẻ “Công cụ”, hoặc các hàng công cụ cuối bảng sửa văn bản (icon con trỏ trên thanh gợi ý).")
        TRANSLATE -> tr("Cách dùng: Tính Năng → Gõ tắt & mẫu câu → Dịch trên máy: chọn ngôn ngữ đích, tải gói dịch; rồi chạm ☰ trên thanh gợi ý → thẻ “Công cụ” → “Dịch” (hoặc ô “Dịch” cuối bảng sửa văn bản).")
        THANKS_BADGE -> tr("Tự hiện sau khi mua.")
    }

    /**
     * Công tắc bật/tắt tính năng — màn Plus đặt công tắc ngay dưới dòng cách dùng (khi đã mở
     * khoá). Chip "Thêm dấu" mặc định TẮT; Công cụ văn bản mặc định BẬT ([settingDefault]).
     */
    val settingKey: String? get() = when (this) {
        SENTENCE_DIACRITICS -> Keys.ADD_TONES_CHIP
        TEXT_TOOLS -> Keys.TEXT_TOOLS_ENABLED
        else -> null
    }

    /** Giá trị khi chưa từng đặt — khớp mặc định [KeyboardSettings]. */
    val settingDefault: Boolean get() = this == TEXT_TOOLS

    /** Nhãn + một dòng mô tả của công tắc trên màn Plus. */
    val settingTitle: String get() = if (this == TEXT_TOOLS) tr("Công cụ văn bản") else tr("Bật chip “Thêm dấu”")
    val settingCaption: String? get() =
        if (this == TEXT_TOOLS) tr("Thẻ Công cụ trong bảng ☰ và bảng sửa văn bản: đổi HOA/thường, thêm/xoá dấu, dịch…") else null
}

/**
 * Cổng kiểm tra Plus, dùng chung app + IME (cùng process, cùng SharedPreferences
 * [Keys.PREFS]).
 *
 *     if (PlusGate.isUnlocked(PlusFeature.TEXT_TOOLS)) { … }
 *
 * App gọi [install] một lần (Application/Activity/IME onCreate) với hàm đọc prefs.
 * Chưa install ⇒ coi như chưa mua.
 */
object PlusGate {
    @Volatile private var read: (String) -> Any? = { null }

    /** Chỉ bản debug mới nghe công tắc giả lập [Keys.PLUS_DEBUG_OVERRIDE]. */
    @Volatile var allowDebugOverride: Boolean = false

    /** Mặc định theo [PlusConfig.PAYWALL_ENABLED]; test đổi được. */
    @Volatile var paywallEnabled: Boolean = PlusConfig.PAYWALL_ENABLED

    /** [get] trả giá trị thô của key (vd `prefs.all[key]`). */
    fun install(get: (String) -> Any?, debugBuild: Boolean) {
        read = get
        allowDebugOverride = debugBuild
    }

    /** Riêng huy hiệu cảm ơn chỉ hiện khi đã mua thật. */
    fun isUnlocked(feature: PlusFeature): Boolean =
        if (feature == PlusFeature.THANKS_BADGE) isPlus else !paywallEnabled || isPlus

    /** Đã có Plus (mua thật, hoặc giả lập ở bản debug). */
    val isPlus: Boolean get() = resolve(purchased, debugOverride, allowDebugOverride)

    /** Cờ mua thật (app ghi sau khi Play xác nhận). */
    val purchased: Boolean get() = read(Keys.PLUS_UNLOCKED) as? Boolean ?: false

    val debugOverride: Boolean get() = read(Keys.PLUS_DEBUG_OVERRIDE) as? Boolean ?: false

    /** Số mục ghim clipboard tối đa; null = không giới hạn. */
    val pinnedClipLimit: Int? get() =
        if (isUnlocked(PlusFeature.ADVANCED_CLIPBOARD)) null else PlusConfig.FREE_PINNED_CLIP_LIMIT

    fun resolve(purchased: Boolean, debugOverride: Boolean, allowDebugOverride: Boolean): Boolean =
        purchased || (allowDebugOverride && debugOverride)
}
