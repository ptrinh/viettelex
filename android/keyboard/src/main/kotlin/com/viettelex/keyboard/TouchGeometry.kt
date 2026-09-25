package com.viettelex.keyboard

/** Điểm (dp). */
data class KPoint(val x: Float, val y: Float)

/** Hình chữ nhật (dp): left/top/right/bottom. */
data class KRect(val left: Float, val top: Float, val right: Float, val bottom: Float) {
    fun contains(p: KPoint) = p.x >= left && p.x < right && p.y >= top && p.y < bottom
    fun inset(dx: Float, dy: Float) = KRect(left + dx, top + dy, right - dx, bottom - dy)
}

/** Điểm chọn phím từ điểm chạm (port iOS). */
object TouchGeometry {
    /** Tâm vùng da chạm thấp hơn điểm mắt nhắm → dời điểm chọn lên 4 dp. */
    const val yOffset: Float = 4f
    fun keySelectionPoint(p: KPoint): KPoint = KPoint(p.x, p.y - yOffset)
    /** Toạ độ pixel: dời lên 4 dp × [density]. */
    fun keySelectionPoint(p: KPoint, density: Float): KPoint = KPoint(p.x, p.y - yOffset * density)
}

/**
 * Nearest-key router plane chữ (port KeyboardView.nearestLetterButton /
 * letterCoreContains). Mọi số tính theo dp; overload `density` cho toạ độ pixel.
 */
object KeyRouter {
    const val HIT_DX = 3f
    const val HIT_DY = 5.5f
    const val MAX_DISTANCE = 21f

    /** Hit-area nở của một phím (dx 3, dy 5.5). */
    fun expandedContains(r: KRect, p: KPoint, density: Float = 1f) =
        r.inset(-HIT_DX * density, -HIT_DY * density).contains(p)

    /** Điểm nằm trong FOOTPRINT thật của một phím chữ → phím chữ thắng vùng nở ⇧/⌫. */
    fun letterCoreContains(p: KPoint, letters: List<KRect>, rowsTop: Float): Boolean {
        if (p.y < rowsTop) return false
        return letters.any { it.contains(p) }
    }

    /**
     * Index phím chữ cho điểm [p] (đã qua keySelectionPoint): trong vùng nở ⇒ phím đó;
     * không thì gần nhất nếu ≤ 21 dp. Điểm trên [rowsTop] (strip gợi ý) ⇒ null.
     */
    fun nearestLetter(p: KPoint, letters: List<KRect>, rowsTop: Float, density: Float = 1f): Int? {
        if (letters.isEmpty() || p.y < rowsTop) return null
        var best = -1
        var bestD = Float.MAX_VALUE
        for ((i, f) in letters.withIndex()) {
            if (expandedContains(f, p, density)) return i
            val dx = maxOf(f.left - p.x, 0f, p.x - f.right)
            val dy = maxOf(f.top - p.y, 0f, p.y - f.bottom)
            val d = dx * dx + dy * dy
            if (best < 0 || d < bestD) { best = i; bestD = d }
        }
        val lim = MAX_DISTANCE * density
        return if (best >= 0 && bestD <= lim * lim) best else null
    }
}
