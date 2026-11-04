package com.viettelex.keyboard

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Vuốt nhanh phím cách sang trái/phải để đổi Tiếng Việt ↔ Tiếng Anh (kiểu Gboard/HeliBoard
 * "Swipe to switch languages"). Phần THUẦN, port 1:1 iOS SpaceFlick.swift — sửa bên này thì
 * sửa y hệt bên kia (SpaceFlickTests hai bên cùng số liệu). Đơn vị dp (≙ pt iOS), ms.
 *
 * Không đụng trackpad: flick phải NHẤC TAY trước ngưỡng giữ trackpad (SPACE_HOLD_MS của
 * KeyboardView = 300 ms). Giữ rồi mới kéo vẫn là trackpad; chạm thường vẫn ra dấu cách.
 *
 * Kéo chậm (#147): ngón đã trượt quá slop TRƯỚC khi giữ đủ lâu ⇒ trackpad không thể bật nữa
 * (`trackpadPossible = false`) ⇒ bỏ giới hạn thời gian/tốc độ, chỉ còn quãng + độ dốc.
 */
enum class KeyboardLanguage(val id: String, val displayName: String) {
    VI("vi", "Tiếng Việt"), EN("en", "English");

    val toggled: KeyboardLanguage get() = if (this == VI) EN else VI
    /** Mã nhỏ góc dưới-phải phím cách khi bật vuốt đổi ngôn ngữ (như stock iOS nhiều ngôn ngữ). */
    val shortCode: String get() = if (this == VI) "VI" else "EN"

    companion object {
        /** Công tắc tắt ⇒ luôn Tiếng Việt (không với tới EN); giá trị lạ ⇒ Tiếng Việt. */
        fun effective(stored: String?, flickEnabled: Boolean): KeyboardLanguage =
            if (flickEnabled && stored == EN.id) EN else VI
    }
}

/**
 * Dấu hiệu trên phím cách: bật vuốt đổi ngôn ngữ ⇒ mã "VI"/"EN" nhỏ góc dưới-phải (như stock
 * iOS khi bật nhiều ngôn ngữ); tắt ⇒ logo Vᴛ (công tắc showSpaceLogo) như cũ. Giống iOS SpaceMark.
 */
sealed class SpaceMark {
    object None : SpaceMark()
    data class Logo(val language: KeyboardLanguage) : SpaceMark()
    data class Code(val text: String) : SpaceMark()

    companion object {
        fun choose(flickEnabled: Boolean, showLogo: Boolean, language: KeyboardLanguage): SpaceMark = when {
            flickEnabled -> Code(language.shortCode)
            showLogo -> Logo(language)
            else -> None
        }
    }
}

object SpaceFlick {
    enum class Direction { LEFT, RIGHT }

    data class Params(
        /** Quãng ngang tối thiểu theo bề rộng phím — như ngưỡng vuốt của [GestureClassifier]. */
        val minDistanceKeys: Float = GestureClassifier.Params().minDistanceKeys,
        /** Sàn tuyệt đối (dp) khi phím quá hẹp. */
        val minDistance: Float = 24f,
        /** dp/ms trung bình từ lúc chạm — như [GestureClassifier]. */
        val minSpeed: Float = GestureClassifier.Params().minSpeed,
        /** Phải nhấc TRƯỚC ngưỡng giữ trackpad. */
        val maxDurationMs: Long = 300,
        /** |dy| ≤ maxSlope·|dx| (chủ yếu ngang). */
        val maxSlope: Float = 0.5f,
        /** Kéo quá ngưỡng này mới vẽ nhãn trượt theo ngón. */
        val previewSlop: Float = 8f,
    )

    /**
     * Nhấc tay: có phải flick đổi ngôn ngữ không (null = chạm/kéo thường).
     * [trackpadPossible] = false khi ngón đã trượt quá slop trước ngưỡng giữ (trackpad không thể
     * bật) ⇒ kéo chậm bao lâu cũng được, miễn đủ quãng và chủ yếu ngang (#147).
     */
    fun classify(dx: Float, dy: Float, durationMs: Long, keyWidth: Float,
                 trackpadPossible: Boolean = true, p: Params = Params()): Direction? {
        val ax = abs(dx)
        if (ax < max(p.minDistance, keyWidth * p.minDistanceKeys) || abs(dy) > ax * p.maxSlope) return null
        if (trackpadPossible) {
            if (durationMs < 0 || durationMs >= p.maxDurationMs) return null
            if (ax / max(durationMs, 1L).toFloat() < p.minSpeed) return null
        }
        return if (dx < 0) Direction.LEFT else Direction.RIGHT
    }

    /**
     * Đang kéo: tiến độ trượt nhãn -1…1 (±1 ở quãng [span]); 0 = dưới slop / quá giờ / kéo dọc.
     * [trackpadPossible] = false ⇒ không "quá giờ": nhãn theo ngón suốt lúc kéo chậm (#147).
     */
    fun progress(dx: Float, dy: Float, elapsedMs: Long, span: Float,
                 trackpadPossible: Boolean = true, p: Params = Params()): Float {
        val ax = abs(dx)
        if (span <= 0f || (trackpadPossible && elapsedMs >= p.maxDurationMs) ||
            ax < p.previewSlop || abs(dy) > ax * p.maxSlope * 2) return 0f
        return max(-1f, min(1f, dx / span))
    }

    /** Quãng kéo mà nhãn trượt trọn (= 2 × ngưỡng flick). */
    fun previewSpan(keyWidth: Float, p: Params = Params()): Float = 2 * max(p.minDistance, keyWidth * p.minDistanceKeys)
}
