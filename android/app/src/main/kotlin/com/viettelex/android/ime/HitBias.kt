package com.viettelex.android.ime

import com.viettelex.keyboard.Key

/**
 * Ưu tiên phím ở MÉP CHUNG (THUẦN — pinned by HitBiasTest; song sinh iOS KeyHitBias trong
 * TouchGeometry.swift, sửa cả hai). Phil 06/10/2026. Hình phím KHÔNG đổi; chỉ đường chia
 * vùng chạm giữa 2 phím kề dời vào phía phím "thua" một dải = band × bề rộng (cao) phím thua:
 *  - space thắng "," / "." kề bên (hàng đáy [?123][😊][space][,][↵] hay chạm nhầm ",").
 * Gõ cuộn (chạm ngay sau một chữ) ⇒ dải rộng hơn. Dải luôn < 0.5 ⇒ TÂM "," vẫn là của nó.
 *
 * ĐÃ BỎ (10/10/2026, bug tester iOS 1.2.6/1.2.7 "bấm ⌫ hay thành chữ m hoặc l", cùng logic
 * ở đây): nhánh "phím chữ thắng mép ⇧ / ⌫" (m lấn 20–35 % mép trái ⌫, l lấn 20–35 % đỉnh ⌫).
 * Phím chức năng giờ có vùng chạm ổn định — [KeyLayout.gutterOwner].
 */
object HitBias {
    /** Phần "," / "." thuộc về space (tỉ lệ bề rộng phím dấu câu). */
    const val SPACE_BAND = 0.30f
    /** … khi "," chạm trong [SPACE_ROLL_MS] sau một chữ. */
    const val SPACE_BAND_ROLLING = 0.40f
    const val SPACE_ROLL_MS = 150L
    /** Hai phím coi là KỀ khi khe ≤ chừng này dp. */
    const val MAX_GAP_DP = 16f

    /** `sinceLetterMs` = ms từ lần chạm chữ gần nhất (âm / rất lớn = không tính). */
    fun spaceBand(sinceLetterMs: Long): Float =
        if (sinceLetterMs in 0 until SPACE_ROLL_MS) SPACE_BAND_ROLLING else SPACE_BAND

    /**
     * Điểm (đang thuộc phím thua `l` hoặc nằm trong khe) có rơi vào dải của phím thắng `w`
     * kề bên CÙNG HÀNG không — dải tính từ mép `l` phía `w`. Không kề ⇒ false.
     */
    fun intrudes(x: Float, y: Float, l: LaidKey, w: LaidKey, band: Float, maxGap: Float): Boolean {
        val vOverlap = minOf(l.bottom, w.bottom) - maxOf(l.top, w.top)
        if (vOverlap <= 0.5f * minOf(l.height, w.height)) return false
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

    /**
     * Router chọn `hit` (theo vùng nở) ⇒ ưu tiên mép: space thay "," / "." kề. ⇧ / ⌫
     * KHÔNG BAO GIỜ nhường cho phím chữ. Không đổi ⇒ trả `hit`.
     */
    fun refine(keys: List<LaidKey>, hit: LaidKey, x: Float, y: Float, sinceLetterMs: Long, d: Float): LaidKey {
        if (hit.kind != KeyKind.PUNCT || (hit.label != "," && hit.label != ".")) return hit
        val gap = MAX_GAP_DP * d
        val band = spaceBand(sinceLetterMs)
        for (k in keys) if (k.kind == KeyKind.SPACE && intrudes(x, y, hit, k, band, gap)) return k
        return hit
    }
}

/**
 * Issue #145 (THUẦN — pinned by StolenSpaceTest): [HitBias] cho space lấy dải mép "," / "."
 * (gõ cuộn: 40 % bề rộng). Chạm "," nhanh sau một chữ mà rơi vào dải đó ⇒ ra DẤU CÁCH; dấu
 * cách thật ngay sau (< DOUBLE_SPACE_MS) ⇒ double-space ⇒ ". " — người gõ "chữ, " thấy
 * "chữ. " ("," thành "."). Space đôi mà lần đầu là chạm nằm TRONG khung thật của "," / "."
 * ⇒ lần đầu chính là phím dấu đó: thay dấu cách trước bằng "<dấu> " ([Key.DoubleSpacePunct]).
 */
object StolenSpace {
    /**
     * Nhãn "," / "." nếu điểm chạm (toạ độ như [KeyLayout.hit]) nằm trong khung THẬT của phím
     * dấu đó nhưng router chọn [hit] = space (dải mép HitBias); khác ⇒ null. Khe giữa hai phím
     * không tính (thật sự mơ hồ).
     */
    fun punct(keys: List<LaidKey>, hit: LaidKey, x: Float, y: Float): String? {
        if (hit.kind != KeyKind.SPACE) return null
        for (k in keys) if (k.kind == KeyKind.PUNCT && (k.label == "," || k.label == ".") && k.contains(x, y))
            return k.insert
        return null
    }

    /**
     * Phím phát ra khi space chốt: [sinceLastSpaceMs] từ lần space trước, [pad] = bàn số (space
     * luôn literal), [prevStolen] = lần space trước là chạm "," / "." bị space lấy ([punct]).
     */
    fun key(sinceLastSpaceMs: Long, doubleSpaceMs: Long, pad: Boolean, prevStolen: String?): Key = when {
        pad || sinceLastSpaceMs >= doubleSpaceMs -> Key.Space
        prevStolen != null -> Key.DoubleSpacePunct(prevStolen)
        else -> Key.DoubleSpacePeriod
    }
}
