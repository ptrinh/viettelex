package com.viettelex.android.ime

/**
 * Hình học bàn phím — port 1:1 các constraint UIStackView của iOS KeyboardView
 * (spec §6.1, §6.3, §6.4). THUẦN (không Android API) để unit-test; mọi toạ độ là
 * px, tính từ dp qua [density]. Chỉ chạy khi đổi plane / cỡ / cấu hình — không
 * bao giờ trong onDraw.
 */
enum class Plane { LETTERS, NUMBERS, SYMBOLS, EMOJI, TEMPLATES }
enum class InputKind { NORMAL, NUMBER, EMAIL, URL }

object KeyKind {
    const val LETTER = 0      // chèn lúc DOWN, qua router
    const val CHAR = 1        // số/ký hiệu plane 123/#+=: arm DOWN, chốt UP, có balloon
    const val SHIFT = 2
    const val BACKSPACE = 3
    const val PLANE = 4       // 123 / ABC (hàng đáy)
    const val MORE = 5        // #+= / 123 (hàng 3 plane số)
    const val GLOBE = 6
    const val EMOJI = 7
    const val CLEAR = 8       // 🗑 plane mẫu câu
    const val SPACE = 9
    const val PUNCT = 10      // , @ . / .com cạnh space: arm DOWN, chốt UP, không balloon
    const val RETURN = 11
    const val DISMISS = 12    // tablet: ẩn bàn phím

    fun isSpecial(k: Int) = when (k) {
        LETTER, CHAR, PUNCT, SPACE -> false
        else -> true
    }
}

/** Một phím đã đặt chỗ. Mutable field chỉ là trạng thái vẽ (pressed). */
class LaidKey(
    @JvmField val kind: Int,
    /** Nhãn thường (chữ thường cho phím chữ). */
    @JvmField val label: String,
    /** Nhãn khi shift ON/CAPS (phím chữ); = label với phím khác. */
    @JvmField val upper: String,
    /** Chuỗi chèn (CHAR/PUNCT) hoặc đích plane ("123","ABC","#+="). */
    @JvmField val insert: String,
    @JvmField var left: Float, @JvmField var top: Float,
    @JvmField var right: Float, @JvmField var bottom: Float,
) {
    @JvmField var pressed = false
    /** Chỉ số ổn định trong plane — làm id cho KeyCommitQueue. */
    @JvmField var index = 0
    val width get() = right - left
    val height get() = bottom - top
    val centerX get() = (left + right) / 2
    val centerY get() = (top + bottom) / 2
    fun contains(x: Float, y: Float) = x >= left && x < right && y >= top && y < bottom
    override fun toString() = "LaidKey($label k=$kind [$left,$top,$right,$bottom])"
}

data class LayoutConfig(
    val plane: Plane,
    val widthPx: Float,
    /** Chiều cao VÙNG PHÍM (không gồm strip gợi ý / nav bar). */
    val keyAreaPx: Float,
    val density: Float,
    val kind: InputKind = InputKind.NORMAL,
    val needsGlobe: Boolean = false,
    val tablet: Boolean = false,
    val returnLabel: String = "return",
)

object KeyLayout {
    // dp — kiểu Gboard / Material (26/09/2026; hành vi giữ nguyên bản iOS)
    const val KEY_SPACING = 5f
    const val ROW_MARGIN_V = 5f
    const val ROW_MARGIN_H = 3f
    /** Hàng đáy dùng cùng margin như mọi hàng (Gboard), không sát đáy như iOS. */
    const val BOTTOM_ROW_TOP = ROW_MARGIN_V
    const val BOTTOM_ROW_BOTTOM = ROW_MARGIN_V
    const val KEY_RADIUS = 7f
    const val OPEN_STRIP = 34f
    const val COLLAPSED_STRIP = 14f
    const val BAR_TOP_PAD = 4f
    const val STRIP_ZONE_W = 52f

    /** Gboard: điện thoại 224 dọc (4 × 56) / 168 ngang; tablet 256 / 300; + rowHeightAdjust × 4 hàng. */
    fun keyAreaDp(tablet: Boolean, landscape: Boolean, rowHeightAdjust: Int): Float {
        val base = if (tablet) (if (landscape) 300f else 256f) else (if (landscape) 168f else 224f)
        return base + rowHeightAdjust.coerceIn(-10, 10) * 4f
    }

    fun stripDp(suggestionsEnabled: Boolean, collapsed: Boolean): Float =
        if (!suggestionsEnabled) 0f else if (collapsed) COLLAPSED_STRIP else OPEN_STRIP

    private val ROW1 = "qwertyuiop"
    private val ROW2 = "asdfghjkl"
    private val ROW3 = "zxcvbnm"
    private val NUM1 = listOf("1", "2", "3", "4", "5", "6", "7", "8", "9", "0")
    private val NUM2 = listOf("-", "/", ":", ";", "(", ")", "$", "&", "@", "\"")
    private val SYM1 = listOf("[", "]", "{", "}", "#", "%", "^", "*", "+", "=")
    private val SYM2 = listOf("_", "\\", "|", "~", "<", ">", "€", "¥", "₫", "•")
    private val PUNCT3 = listOf(".", ",", "?", "!", "'")

    fun build(c: LayoutConfig): List<LaidKey> {
        val out = ArrayList<LaidKey>(40)
        val rowH = c.keyAreaPx / 4f
        when (c.plane) {
            Plane.LETTERS -> {
                equalRow(out, ROW1.map { it.toString() }, KeyKind.LETTER, c, 0, rowH, 0f)
                equalRow(out, ROW2.map { it.toString() }, KeyKind.LETTER, c, 1, rowH, 0.5f)
                thirdRow(out, c, rowH, letters = true)
                bottomRow(out, c, 3 * rowH, rowH, planeKey = "?123", clearInsteadOfEmoji = false)
            }
            Plane.NUMBERS, Plane.SYMBOLS -> {
                val num = c.plane == Plane.NUMBERS
                equalRow(out, if (num) NUM1 else SYM1, KeyKind.CHAR, c, 0, rowH, 0f)
                equalRow(out, if (num) NUM2 else SYM2, KeyKind.CHAR, c, 1, rowH, 0f)
                thirdRow(out, c, rowH, letters = false)
                bottomRow(out, c, 3 * rowH, rowH, planeKey = "ABC", clearInsteadOfEmoji = false)
            }
            Plane.TEMPLATES -> {
                // Chips giãn phần trên; hàng đáy cao ĐÚNG 1 hàng phím (keyArea/4).
                bottomRow(out, c, c.keyAreaPx - rowH, rowH, planeKey = "ABC", clearInsteadOfEmoji = true)
            }
            Plane.EMOJI -> Unit   // EmojiPane tự vẽ
        }
        for (i in out.indices) out[i].index = i
        return out
    }

    private fun keyTop(rowIndex: Int, rowH: Float, d: Float) = rowIndex * rowH + ROW_MARGIN_V * d
    private fun keyBottom(rowIndex: Int, rowH: Float, d: Float) = (rowIndex + 1) * rowH - ROW_MARGIN_V * d

    /** Hàng phím bằng nhau; sideInset tính theo "phím" = W/10 như iOS (hàng 2 thụt 0.5). */
    private fun equalRow(out: MutableList<LaidKey>, labels: List<String>, kind: Int,
                         c: LayoutConfig, rowIndex: Int, rowH: Float, sideInset: Float) {
        val d = c.density
        val gap0 = KEY_SPACING * d
        // Thụt theo BƯỚC phím hàng 10 (phím + khe) ⇒ phím hàng 2 đúng bằng hàng 1.
        val pitch = (c.widthPx - 2 * ROW_MARGIN_H * d - 9 * gap0) / 10f + gap0
        val inset = ROW_MARGIN_H * d + sideInset * pitch
        val n = labels.size
        val gap = KEY_SPACING * d
        val w = (c.widthPx - 2 * inset - gap * (n - 1)) / n
        val t = keyTop(rowIndex, rowH, d); val b = keyBottom(rowIndex, rowH, d)
        var x = inset
        for (s in labels) {
            val up = if (kind == KeyKind.LETTER) s.uppercase() else s
            out += LaidKey(kind, s, up, s, x, t, x + w, b)
            x += w + gap
        }
    }

    /**
     * Hàng 3: plane chữ = ⇧(1.5) z…m ⌫(1.5) trên lưới 10 cột; plane số =
     * [=\\</?123](1.5) . , ? ! ' ⌫(1.5) — 5 dấu chia đều phần còn lại (iOS
     * fillProportionally; stock đo được ≈ 1.45 phím chữ).
     */
    private fun thirdRow(out: MutableList<LaidKey>, c: LayoutConfig, rowH: Float, letters: Boolean) {
        val d = c.density
        val m = ROW_MARGIN_H * d
        val gap = KEY_SPACING * d
        val inner = c.widthPx - 2 * m
        val k = (inner - 8 * gap) / 10f            // phím chữ hàng 3 (1.5+7+1.5 = 10)
        val side = 1.5f * k
        val t = keyTop(2, rowH, d); val b = keyBottom(2, rowH, d)
        var x = m
        if (letters) {
            out += LaidKey(KeyKind.SHIFT, "", "", "", x, t, x + side, b); x += side + gap
            for (ch in ROW3) {
                val s = ch.toString()
                out += LaidKey(KeyKind.LETTER, s, s.uppercase(), s, x, t, x + k, b); x += k + gap
            }
        } else {
            val more = if (c.plane == Plane.NUMBERS) "=\\<" else "?123"
            out += LaidKey(KeyKind.MORE, more, more, more, x, t, x + side, b); x += side + gap
            val p = (inner - 2 * side - 6 * gap) / 5f
            for (s in PUNCT3) { out += LaidKey(KeyKind.CHAR, s, s, s, x, t, x + p, b); x += p + gap }
        }
        out += LaidKey(KeyKind.BACKSPACE, "", "", "", x, t, c.widthPx - m, b)
    }

    /**
     * Hàng đáy kiểu Gboard: [?123|ABC 0.15][, 0.10][🌐 0.10?][😊|🗑 0.10][space còn lại][. 0.10]
     * [enter 0.15][ẩn 0.07 tablet]. Ô email: "," ⇒ "@"; ô URL: "," ⇒ "/" và thêm ".com" 0.15
     * trước ".". Hệ số nhân với bề ngang CẢ hàng.
     */
    private fun bottomRow(out: MutableList<LaidKey>, c: LayoutConfig, rowTop: Float, rowH: Float,
                          planeKey: String, clearInsteadOfEmoji: Boolean) {
        val d = c.density
        val W = c.widthPx
        val m = ROW_MARGIN_H * d
        val gap = KEY_SPACING * d
        val t = rowTop + BOTTOM_ROW_TOP * d
        val b = rowTop + rowH - BOTTOM_ROW_BOTTOM * d
        data class Slot(val kind: Int, val label: String, val insert: String, val mult: Float)
        val slots = ArrayList<Slot>(9)
        val letters = c.plane == Plane.LETTERS
        slots += Slot(KeyKind.PLANE, planeKey, planeKey, 0.15f)
        val left = if (letters) when (c.kind) {
            InputKind.EMAIL -> "@"
            InputKind.URL -> "/"
            else -> ","
        } else ","
        slots += Slot(KeyKind.PUNCT, left, left, 0.10f)
        if (c.needsGlobe) slots += Slot(KeyKind.GLOBE, "", "", 0.10f)
        slots += if (clearInsteadOfEmoji) Slot(KeyKind.CLEAR, "", "", 0.10f)
                 else Slot(KeyKind.EMOJI, "", "", 0.10f)
        slots += Slot(KeyKind.SPACE, "", " ", -1f)
        if (letters && c.kind == InputKind.URL) slots += Slot(KeyKind.PUNCT, ".com", ".com", 0.15f)
        slots += Slot(KeyKind.PUNCT, ".", ".", 0.10f)
        slots += Slot(KeyKind.RETURN, c.returnLabel, "\n", 0.15f)
        if (c.tablet) slots += Slot(KeyKind.DISMISS, "", "", 0.07f)
        var fixed = 0f
        for (s in slots) if (s.mult > 0) fixed += s.mult * W
        val space = (W - 2 * m - fixed - gap * (slots.size - 1)).coerceAtLeast(gap)
        var x = m
        for (s in slots) {
            val w = if (s.mult > 0) s.mult * W else space
            out += LaidKey(s.kind, s.label, s.label, s.insert, x, t, x + w, b)
            x += w + gap
        }
    }

    // MARK: router (port KeyboardView.routedHitTest / nearestLetterButton)

    /** Footprint nở của phím: dx 3 dp, dy 5.5 dp (UIButton.point(inside:)). */
    fun expandedContains(k: LaidKey, x: Float, y: Float, d: Float): Boolean {
        val dx = 3f * d; val dy = 5.5f * d
        return x >= k.left - dx && x < k.right + dx && y >= k.top - dy && y < k.bottom + dy
    }

    /** Khoảng cách² từ điểm tới hình chữ nhật phím (0 nếu nằm trong). */
    fun dist2(k: LaidKey, x: Float, y: Float): Float {
        val dx = maxOf(k.left - x, 0f, x - k.right)
        val dy = maxOf(k.top - y, 0f, y - k.bottom)
        return dx * dx + dy * dy
    }

    /**
     * Chọn phím cho một điểm chạm. `x, y` = điểm chạm thô; `yOffsetPx` =
     * TouchGeometry.yOffset (4 dp) — điểm chọn phím chữ dời lên.
     *
     * Plane chữ (y iOS): phím chữ thắng trong footprint THẬT của nó (kể cả khi vùng
     * nở của ⇧/⌫ đè lên); rồi tới phím chức năng theo vùng nở; rồi phím chữ gần
     * nhất trong 21 dp. Cuối cùng (Android, bịt khe chết giữa hàng 3 và hàng đáy):
     * phím bất kỳ gần nhất trong 21 dp.
     */
    fun hit(keys: List<LaidKey>, plane: Plane, x: Float, y: Float, yOffsetPx: Float, d: Float): LaidKey? {
        val py = y - yOffsetPx
        if (plane == Plane.LETTERS) {
            var inCore = false
            for (i in keys.indices) {
                val k = keys[i]
                if (k.kind == KeyKind.LETTER && k.contains(x, y)) { inCore = true; break }
            }
            if (inCore) return nearestLetter(keys, x, py, d)
            for (i in keys.indices.reversed()) {
                val k = keys[i]
                if (k.kind != KeyKind.LETTER && expandedContains(k, x, y, d)) return k
            }
            nearestLetter(keys, x, py, d)?.let { return it }
        } else {
            for (i in keys.indices.reversed()) {
                val k = keys[i]
                if (expandedContains(k, x, y, d)) return k
            }
        }
        var best: LaidKey? = null
        var bestD = Float.MAX_VALUE
        for (i in keys.indices) {
            val dd = dist2(keys[i], x, y)
            if (dd < bestD) { bestD = dd; best = keys[i] }
        }
        val lim = 21f * d
        return if (best != null && bestD <= lim * lim) best else null
    }

    /** nearestLetterButton: footprint nở ⇒ phím đó; không thì gần nhất nếu ≤ 21 dp. */
    fun nearestLetter(keys: List<LaidKey>, x: Float, y: Float, d: Float): LaidKey? {
        var best: LaidKey? = null
        var bestD = Float.MAX_VALUE
        for (i in keys.indices) {
            val k = keys[i]
            if (k.kind != KeyKind.LETTER) continue
            if (expandedContains(k, x, y, d)) return k
            val dd = dist2(k, x, y)
            if (dd < bestD) { bestD = dd; best = k }
        }
        val lim = 21f * d
        return if (best != null && bestD <= lim * lim) best else null
    }
}
