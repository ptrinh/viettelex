package com.viettelex.android.ime

/**
 * Ưu tiên phím ở MÉP CHUNG (THUẦN — pinned by HitBiasTest; song sinh iOS KeyHitBias trong
 * TouchGeometry.swift, sửa cả hai). Phil 06/10/2026. Hình phím KHÔNG đổi; chỉ đường chia
 * vùng chạm giữa 2 phím kề dời vào phía phím "thua" một dải = band × bề rộng (cao) phím thua:
 *  - space thắng "," / "." kề bên (hàng đáy [?123][😊][space][,][↵] hay chạm nhầm ",");
 *  - phím chữ thắng ⇧ / ⌫ kề bên (z/a cạnh ⇧, m cạnh ⌫).
 * Gõ cuộn (chạm ngay sau một chữ) ⇒ dải rộng hơn. Dải luôn < 0.5 ⇒ TÂM phím thua vẫn là
 * của nó (chạm ⇧ / "," cố ý ở giữa phím không bao giờ bị cướp).
 */
object HitBias {
    /** Phần "," / "." thuộc về space (tỉ lệ bề rộng phím dấu câu). */
    const val SPACE_BAND = 0.30f
    /** … khi "," chạm trong [SPACE_ROLL_MS] sau một chữ. */
    const val SPACE_BAND_ROLLING = 0.40f
    const val SPACE_ROLL_MS = 150L
    /** Phần ⇧ / ⌫ thuộc về phím chữ kề (tỉ lệ bề rộng — hay bề cao với hàng trên). */
    const val LETTER_BAND = 0.20f
    /** … khi ⇧ / ⌫ chạm trong [LETTER_ROLL_MS] sau một chữ (gõ nhanh). */
    const val LETTER_BAND_ROLLING = 0.35f
    const val LETTER_ROLL_MS = 200L
    /** Hai phím coi là KỀ khi khe ≤ chừng này dp. */
    const val MAX_GAP_DP = 16f

    /** `sinceLetterMs` = ms từ lần chạm chữ gần nhất (âm / rất lớn = không tính). */
    fun spaceBand(sinceLetterMs: Long): Float =
        if (sinceLetterMs in 0 until SPACE_ROLL_MS) SPACE_BAND_ROLLING else SPACE_BAND
    fun letterBand(sinceLetterMs: Long): Float =
        if (sinceLetterMs in 0 until LETTER_ROLL_MS) LETTER_BAND_ROLLING else LETTER_BAND

    /**
     * Điểm (đang thuộc phím thua `l` hoặc nằm trong khe) có rơi vào dải của phím thắng `w`
     * kề bên không. Cùng hàng: dải tính từ mép `l` phía `w`. `w` ở hàng TRÊN `l` (a trên ⇧):
     * dải tính từ mép trên `l`, chỉ trong khoảng x của `w`. Không kề ⇒ false.
     */
    fun intrudes(x: Float, y: Float, l: LaidKey, w: LaidKey, band: Float, maxGap: Float): Boolean {
        val vOverlap = minOf(l.bottom, w.bottom) - maxOf(l.top, w.top)
        if (vOverlap > 0.5f * minOf(l.height, w.height)) {
            if (w.right <= l.left + 0.5f) {
                if (l.left - w.right > maxGap) return false
                return x >= w.right && x < l.left + band * l.width
            }
            if (w.left >= l.right - 0.5f) {
                if (w.left - l.right > maxGap) return false
                return x <= w.left && x > l.right - band * l.width
            }
            return false
        }
        if (w.bottom <= l.top + 0.5f) {
            if (l.top - w.bottom > maxGap || x < w.left || x > w.right) return false
            return y >= w.bottom && y < l.top + band * l.height
        }
        return false
    }

    /**
     * Router chọn `hit` (theo vùng nở) ⇒ ưu tiên mép: space thay "," / "." kề; phím chữ
     * gần nhất thay ⇧ / ⌫ (chỉ plane có phím chữ). Không đổi ⇒ trả `hit`.
     */
    fun refine(keys: List<LaidKey>, hit: LaidKey, x: Float, y: Float, sinceLetterMs: Long,
               d: Float, letters: Boolean): LaidKey {
        val gap = MAX_GAP_DP * d
        when (hit.kind) {
            KeyKind.PUNCT -> {
                if (hit.label != "," && hit.label != ".") return hit
                val band = spaceBand(sinceLetterMs)
                for (k in keys) if (k.kind == KeyKind.SPACE && intrudes(x, y, hit, k, band, gap)) return k
            }
            KeyKind.SHIFT, KeyKind.BACKSPACE -> {
                if (!letters) return hit
                val band = letterBand(sinceLetterMs)
                var best: LaidKey? = null
                var bestD = Float.MAX_VALUE
                for (k in keys) {
                    if (k.kind != KeyKind.LETTER || !intrudes(x, y, hit, k, band, gap)) continue
                    val dd = KeyLayout.dist2(k, x, y)
                    if (dd < bestD) { bestD = dd; best = k }
                }
                if (best != null) return best
            }
        }
        return hit
    }
}
