package com.viettelex.keyboard

/**
 * Bộ hiệu ứng riêng của các theme đủ món 11/2026 (Bóng đá, …) + CẢNH nền vẽ thủ tục (motif cảnh trong "deco") — phần
 * thuần. Song sinh iOS/Keyboard/ThemeFxPack.swift.
 */
object ThemeFxFactory {
    /** Kiểu có bộ vẽ riêng (KeyEffectView chuyển tiếp). iOS ThemeFxFactory.effects y hệt. */
    val EFFECTS: Set<KeyEffect> = setOf(KeyEffect.GOAL, KeyEffect.FISHFEED, KeyEffect.ICE)
    fun handles(e: KeyEffect): Boolean = e in EFFECTS
}

/**
 * Motif "cảnh": vẽ TRỌN nền theme một lần mỗi cỡ (không theo khe hàng phím như motif thường): gradient + hình vector.
 * Màu deco.color = màu nét / điểm sáng của cảnh; gradient theo bảng cố định (sáng / tối). iOS ThemeScene y hệt.
 */
object ThemeScene {
    val MOTIFS: Set<String> = setOf(ThemeDecoration.PITCH, ThemeDecoration.AQUARIUM, ThemeDecoration.CAFE)
    fun isScene(motif: String?): Boolean = motif != null && motif in MOTIFS
    /** Gradient trên → dưới (0xRRGGBB); rỗng = giữ màu nền theme. */
    fun gradient(motif: String, dark: Boolean): IntArray = when (motif) {
        ThemeDecoration.AQUARIUM -> intArrayOf(0x0F4C7A, 0x0B3D66, 0x062847)   // nước sâu (sáng = tối)
        ThemeDecoration.CAFE -> if (dark) intArrayOf(0x1A0F09, 0x3A271C, 0x4A3426) else intArrayOf(0xEAD7B8, 0xC9A27E, 0x6B4430)
        else -> IntArray(0)
    }
}

/** Motif cảnh ([ThemeScene]) — không đặt motif nhỏ vào khe hàng. */
val ThemeDecoration.isScene: Boolean get() = ThemeScene.isScene(motif)
