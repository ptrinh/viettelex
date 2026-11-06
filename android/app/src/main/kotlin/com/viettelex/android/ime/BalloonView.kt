package com.viettelex.android.ime

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.os.Build
import android.view.View

/**
 * Preview phím kiểu Gboard (spec §6.5 — hình dạng Android từ 26/09/2026).
 * Overlay phủ toàn bàn phím, không nhận touch. Path dựng lại CHỈ khi hình dạng đổi
 * (cùng hàng phím ⇒ cùng path) bằng path.reset() — không alloc trên hot path.
 * Toạ độ theo view gốc (strip + phím).
 */
@SuppressLint("ViewConstructor")
class BalloonView(context: Context, private val theme: ImeTheme) : View(context) {
    private val path = Path()
    /** Kiểu phím của theme (nền đục, viền, bo góc, chữ, cỡ) — giải sẵn trong ImeTheme. */
    private val ps = theme.popupStyle
    private val fill = theme.fill(ps.fill).apply {
        // Bóng mềm 2dp lệch xuống 1dp, opacity 0.3. Shadow layer trên path chỉ được
        // tăng tốc phần cứng từ API 28; máy cũ bỏ bóng.
        if (Build.VERSION.SDK_INT >= 28) setShadowLayer(theme.dp(3f), 0f, theme.dp(1.5f), 0x33000000)
    }
    private val textPaint = theme.text(28f * ps.labelScale, color = ps.ink).apply { theme.keyTypeface?.let { typeface = it } }
    /** Viền như phím (Hoa xanh, Neon, Tương phản cao); null = không viền. */
    private val borderPaint: Paint? = ps.border?.let { bc ->
        Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; color = bc; strokeWidth = theme.dp(ps.borderWidth) }
    }
    /** Bo góc ô cỡ [w]×[h] theo % của phím ([KeyPopupStyle.cornerPercent]); mặc định [fallback]. */
    private fun popupRadius(kw: Float, kh: Float, w: Float, h: Float, fallback: Float): Float =
        com.viettelex.keyboard.KeyStyle.cornerRadius(ps.cornerPercent, kw, kh, fallback).coerceAtMost(minOf(w, h) / 2)
    private var textOff = theme.centerOffset(textPaint)
    /** Tuỳ chỉnh nâng cao: phông nhãn ⇒ kẹp cỡ để dấu chồng (Ễ, Ỗ) không tràn khỏi ô. */
    private val styled = theme.keyStyle.customizesLabels

    /** Cỡ chữ lớn nhất ≤ [want] để [sample] căn giữa trong khung cao [h] không tràn mực (lúc đổi hình). */
    private fun fitCentered(p: Paint, want: Float, h: Float): Float {
        p.textSize = want
        val b = android.graphics.Rect()
        var above = 0f; var below = 0f
        val sample = com.viettelex.keyboard.KeyLabelFitter.STACKED_SAMPLE
        for (i in sample.indices) {
            p.getTextBounds(sample, i, i + 1, b)
            above = maxOf(above, -b.top.toFloat()); below = maxOf(below, b.bottom.toFloat())
        }
        val fm = p.fontMetrics
        return com.viettelex.keyboard.KeyLabelFitter.centeredSize(want, -fm.ascent / want, fm.descent / want,
            above / want, below / want, h - 2 * theme.dp(com.viettelex.keyboard.KeyLabelFitter.V_PAD_DP))
    }

    private var visible = false
    private var text = ""
    /** Skin phím của theme cho ô phóng to (null = nền đục như cũ). */
    private var bubbleSkin: LoadedSkin? = null
    private val skinPainter: SkinPainter? = if (theme.assets?.skins != null) SkinPainter() else null
    private var ox = 0f; private var oy = 0f          // gốc bubble trong view
    private var bubbleW = 0f; private var bubbleH = 0f
    private var shapeW = -1f; private var shapeH = -1f

    init {
        isClickable = false
        isFocusable = false
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    override fun onTouchEvent(event: android.view.MotionEvent?) = false

    // MARK: phím sẫm khi bấm (Keys.KEY_PRESS_HIGHLIGHT)
    // Lớp ink 12% trên khung phím đang đè — cùng màu theme.pressed(keyFill) của phím space/chức
    // năng, nhãn ink không đổi. Vẽ ở overlay này (display list vài lệnh, vốn đã vẽ lại mỗi chạm
    // vì balloon) thay vì KeyboardView ⇒ chạm phím chữ không ghi lại ~40 phím. Toạ độ view gốc.
    /** Trạng thái theo ngón — KeyboardView ghi (chỉ khi công tắc BẬT). */
    val press = KeyPressHighlight()
    private val pressPaint = theme.fill(theme.withAlpha(theme.ink, 0.12f))
    private val pressRadius = theme.dp(KeyLayout.KEY_RADIUS)

    @Suppress("DEPRECATION")
    fun invalidatePress(pid: Int) {
        invalidate(press.left(pid).toInt() - 1, press.top(pid).toInt() - 1,
            press.right(pid).toInt() + 1, press.bottom(pid).toInt() + 1)
    }

    fun clearPress() { if (press.clearAll()) invalidate() }

    private fun drawPress(c: Canvas) {
        val p = press
        for (i in 0 until p.capacity) if (p.isPressed(i))
            theme.keyRadius(p.right(i) - p.left(i), p.bottom(i) - p.top(i), pressRadius).let { r ->
                c.drawRoundRect(p.left(i), p.top(i), p.right(i), p.bottom(i), r, r, pressPaint)
            }
    }

    /**
     * keyRect theo toạ độ view gốc. Preview kiểu Gboard/Material: thẻ bo góc nổi NGAY
     * TRÊN phím (không cổ nối như iOS), rộng hơn phím chút, chữ lớn.
     */
    fun show(kl: Float, kt: Float, kr: Float, kb: Float, text: String, skin: LoadedSkin? = null) {
        bubbleSkin = skin
        val kw = kr - kl; val kh = kb - kt
        val bw = maxOf(kw * 1.2f, theme.dp(44f))
        val bh = maxOf(kh * 1.15f, theme.dp(52f))
        // Không vẽ ra ngoài cửa sổ IME được: kẹp ở 0 (strip gợi ý là headroom).
        val top = maxOf(kt - theme.dp(4f) - bh, 0f)
        val x = ((kl + kr) / 2 - bw / 2).coerceIn(0f, maxOf(0f, width - bw))
        if (bw != shapeW || bh != shapeH) {
            shapeW = bw; shapeH = bh
            path.reset()
            val r = popupRadius(kw, kh, bw, bh, theme.dp(10f))
            path.addRoundRect(0f, 0f, bw, bh, r, r, Path.Direction.CW)
            if (styled) {
                textPaint.textSize = fitCentered(textPaint, theme.sp(28f) * ps.labelScale, bh)
                textOff = theme.centerOffset(textPaint)
            }
        }
        invalidateBalloon()          // vùng cũ
        ox = x; oy = top; bubbleW = bw; bubbleH = bh
        this.text = text
        visible = true
        invalidateBalloon()          // vùng mới
    }

    fun hide() {
        if (!visible) return
        visible = false
        invalidateBalloon()
    }

    @Suppress("DEPRECATION")
    private fun invalidateBalloon() {
        val pad = theme.dp(4f)
        invalidate((ox - pad).toInt(), (oy - pad).toInt(), (ox + bubbleW + pad).toInt(), (oy + shapeH + pad).toInt())
    }

    // MARK: popup nhiều lựa chọn (DomainPopup / KeyVariants)
    // Hàng ô nổi trên phím: ô đang chọn nền màu nhấn (action) chữ actionInk như stock (ô xanh
    // chữ trắng). Paint/mảng dựng LƯỜI lần đầu mở popup — bàn phím không bao giờ giữ thì 0 chi phí.

    private class Pop(theme: ImeTheme) {
        val panel = theme.fill(theme.popupStyle.fill).apply {
            if (Build.VERSION.SDK_INT >= 28) setShadowLayer(theme.dp(3f), 0f, theme.dp(1.5f), 0x4D000000)
        }
        val hi = theme.fill(theme.popupStyle.selectedFill)
        val text = theme.text(18f, color = theme.popupStyle.ink).apply { theme.keyTypeface?.let { typeface = it } }
        val ink = theme.popupStyle.ink
        val selInk = theme.popupStyle.selectedInk
        var radius = 0f
        val rect = android.graphics.RectF()
        val fm = Paint.FontMetrics()
        var choices: List<String> = emptyList()
        var slotL = FloatArray(0)
        var size = FloatArray(0)
        var itemW = 0f
        var sel = -1
        /** Hàng (0 = trên cùng) từng ô khi popup hai hàng (#154); null = một hàng. */
        var slotRow: IntArray? = null
        var rowH = 0f
        /** Icon [ImeIcons] từng ô (menu giữ 😊); null = ô chữ. */
        var icons: IntArray? = null
        var iconSize = 0f
        val iconPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    }
    private var pop: Pop? = null
    private var popVisible = false

    /** Popup đang hiện (test/debug). */
    val popupVisible: Boolean get() = popVisible
    /** Ô đang chọn (-1 = không chọn / huỷ). */
    val popupSelection: Int get() = if (popVisible) pop?.sel ?: -1 else -1

    /**
     * Hiện hàng [choices] trong khung panel (toạ độ view gốc); [slotLefts] mép trái từng ô,
     * [itemW] bề rộng ô, [textSp] cỡ chữ (tự thu nhỏ cho vừa ô, vd ".com.vn"), [sel] ô chọn sẵn.
     * Hai hàng: [slotRows] hàng từng ô (0 = trên cùng), [rowH] cao một hàng; null ⇒ một hàng.
     */
    fun showPopup(l: Float, t: Float, r: Float, b: Float, slotLefts: FloatArray, itemW: Float,
                  choices: List<String>, textSp: Float, sel: Int, icons: IntArray? = null,
                  rowH: Float = b - t, slotRows: IntArray? = null) {
        val p = pop ?: Pop(theme).also { pop = it }
        p.rect.set(l, t, r, b)
        p.choices = choices; p.slotL = slotLefts; p.itemW = itemW; p.sel = sel
        p.slotRow = slotRows; p.rowH = rowH
        p.icons = icons; p.iconSize = theme.dp(24f)
        val inset = theme.dp(4f)
        p.radius = popupRadius(itemW, rowH, r - l, rowH, theme.dp(10f))
        val want = theme.sp(textSp) * ps.labelScale
        val full = if (styled) fitCentered(p.text, want, rowH - 2 * inset) else want
        p.text.textSize = full
        val room = itemW - theme.dp(6f)
        p.size = FloatArray(choices.size) { i ->
            val w = p.text.measureText(choices[i])
            if (w > room && w > 0f) full * maxOf(0.6f, room / w) else full
        }
        popVisible = true
        invalidate()
    }

    fun selectPopup(sel: Int) {
        val p = pop ?: return
        if (!popVisible || p.sel == sel) return
        p.sel = sel
        invalidate()
    }

    fun hidePopup() {
        if (!popVisible) return
        popVisible = false
        invalidate()
    }

    private fun drawPopup(c: Canvas, p: Pop) {
        val r = p.radius
        c.drawRoundRect(p.rect, r, r, p.panel)
        borderPaint?.let { c.drawRoundRect(p.rect, r, r, it) }
        val inset = theme.dp(4f)
        for (i in p.choices.indices) {
            val rowTop = p.rect.top + (p.slotRow?.getOrNull(i) ?: 0) * p.rowH
            val top = rowTop + inset; val bot = rowTop + p.rowH - inset
            val x0 = p.slotL[i]
            if (i == p.sel) c.drawRoundRect(x0 + theme.dp(1f), top, x0 + p.itemW - theme.dp(1f), bot, theme.dp(7f), theme.dp(7f), p.hi)
            val icon = p.icons?.getOrNull(i) ?: -1
            if (icon >= 0) {
                p.iconPaint.color = if (i == p.sel) p.selInk else p.ink
                ImeIcons.draw(c, icon, x0 + p.itemW / 2, (top + bot) / 2, p.iconSize, p.iconPaint)
                continue
            }
            p.text.textSize = p.size[i]
            p.text.color = if (i == p.sel) p.selInk else p.ink
            p.text.getFontMetrics(p.fm)
            c.drawText(p.choices[i], x0 + p.itemW / 2, (top + bot) / 2 - (p.fm.ascent + p.fm.descent) / 2, p.text)
        }
    }

    override fun onDraw(c: Canvas) {
        ImeTrace.drew(keys = false)
        if (press.count > 0) drawPress(c)      // dưới popup / bubble (bubble hàng dưới đè phím hàng trên)
        if (popVisible) pop?.let { drawPopup(c, it) }
        if (!visible) return
        c.save()
        c.translate(ox, oy)
        val sk = bubbleSkin
        if (sk != null && skinPainter != null) skinPainter.draw(c, sk, false, 0f, 0f, bubbleW, bubbleH)
        else {
            c.drawPath(path, fill)
            borderPaint?.let { c.drawPath(path, it) }
        }
        c.drawText(text, bubbleW / 2, bubbleH / 2 + textOff, textPaint)
        c.restore()
    }
}
