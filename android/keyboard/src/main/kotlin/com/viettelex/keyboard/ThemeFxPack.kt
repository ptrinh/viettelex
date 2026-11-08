package com.viettelex.keyboard

/**
 * Bộ hiệu ứng riêng của các theme đủ món 11/2026 (Bóng đá, …) + CẢNH nền vẽ thủ tục (motif cảnh trong "deco") — phần
 * thuần. Song sinh iOS/Keyboard/ThemeFxPack.swift.
 */
object ThemeFxFactory {
    /** Kiểu có bộ vẽ riêng (KeyEffectView chuyển tiếp). iOS ThemeFxFactory.effects y hệt. */
    val EFFECTS: Set<KeyEffect> = setOf(KeyEffect.GOAL)
    fun handles(e: KeyEffect): Boolean = e in EFFECTS
}

/**
 * Motif "cảnh": vẽ TRỌN nền theme một lần mỗi cỡ (không theo khe hàng phím như motif thường): gradient + hình vector.
 * Màu deco.color = màu nét / điểm sáng của cảnh; gradient theo bảng cố định (sáng / tối). iOS ThemeScene y hệt.
 */
object ThemeScene {
    val MOTIFS: Set<String> = setOf(ThemeDecoration.PITCH)
    fun isScene(motif: String?): Boolean = motif != null && motif in MOTIFS
    /** Gradient trên → dưới (0xRRGGBB); rỗng = giữ màu nền theme. */
    fun gradient(motif: String, dark: Boolean): IntArray = when (motif) {
        else -> IntArray(0)
    }
}

/** Motif cảnh ([ThemeScene]) — không đặt motif nhỏ vào khe hàng. */
val ThemeDecoration.isScene: Boolean get() = ThemeScene.isScene(motif)
