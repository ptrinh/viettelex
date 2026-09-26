package com.viettelex.android.ime

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.text.TextPaint
import android.text.TextUtils
import android.view.MotionEvent
import android.view.View
import android.view.animation.AccelerateDecelerateInterpolator
import com.viettelex.android.R
import com.viettelex.keyboard.SuggestionSet
import kotlin.math.abs

/**
 * Strip gợi ý (spec §6.6, §7.1): [☰ 52][ "nguyên văn" | từ 1 | từ 2 / ≤3 emoji ][⌄ 52],
 * thẻ Dán kiểu iOS 27, trạng thái thu gọn 14 dp với ☰/⌄ nổi. View này PHỦ lên mép trên
 * vùng phím 4 dp (nút nổi cao 18 dp như iOS) — chạm không trúng mục tiêu nào trả false
 * để rơi xuống [KeyboardView].
 */
@SuppressLint("ViewConstructor")
class StripView(context: Context, private val theme: ImeTheme, private val feedback: Feedback) : View(context) {

    interface Listener {
        fun onSuggestion(item: String)
        fun onToggleTemplates()
        /** Chevron đã đổi trạng thái; gọi SAU animation (refresh gợi ý khi mở lại). */
        fun onBarToggled(collapsed: Boolean)
        /** Chiều cao strip đổi (animation) — root đo lại. */
        fun onStripHeightChanged()
        /** Chạm ô "↩︎ Khôi phục" sau vuốt ⌫ xoá theo từ. */
        fun onRestoreDeleted()
    }

    var listener: Listener? = null

    private val d = theme.density
    var suggestionsEnabled = false; private set
    var collapsed = false; private set
    /** 1 = mở, 0 = thu gọn (animation 200 ms). */
    private var openness = 1f
    private var anim: ValueAnimator? = null
    private var plane = Plane.LETTERS
    private var templatesEnabled = true

    // --- nội dung bar ---
    private val slotText = arrayOfNulls<String>(3)      // đã ellipsize
    private val slotPayload = arrayOfNulls<String>(3)
    private val slotL = FloatArray(3); private val slotR = FloatArray(3)
    private val emojiText = arrayOfNulls<String>(3)
    private val emojiL = FloatArray(3); private val emojiR = FloatArray(3)
    private var emojiCount = 0
    private var paste = false
    private var lastSig = ""
    private var lastSet: SuggestionSet? = null

    private val wordPaint = TextPaint(theme.text(16f))
    private val wordOff = theme.centerOffset(wordPaint)
    /** Gboard nhấn mạnh gợi ý giữa (medium). */
    private val wordCenterPaint = TextPaint(theme.text(16f, medium = true))
    private val wordCenterOff = theme.centerOffset(wordCenterPaint)
    private val emojiPaint = theme.text(20f)
    private val emojiOff = theme.centerOffset(emojiPaint)
    private val iconPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val pasteTitle = theme.text(14f, medium = true, align = Paint.Align.LEFT)
    private val pasteSub = theme.text(12f, color = theme.withAlpha(theme.ink, 0.7f), align = Paint.Align.LEFT)
    private val pasteTitleText = context.getString(R.string.ime_paste_title)
    private val pasteSubText = context.getString(R.string.ime_paste_sub)
    private var pasteIconCx = 0f; private var pasteTextX = 0f; private var pasteSubX = 0f
    private var pasteL = 0f; private var pasteR = 0f; private var pasteT = 0f; private var pasteB = 0f
    private var pasteShowSub = true
    private val chipPaint = theme.fill(theme.chip)
    private val pressPaint = theme.fill(theme.withAlpha(theme.ink, 0.10f))
    private var pressed = T_NONE
    private var pressedIndex = 0
    private var pasteTitleBase = 0f; private var pasteSubBase = 0f; private var pasteIconCy = 0f

    // --- vuốt ⌫: xem trước đoạn sẽ xoá / ô Khôi phục (đè nội dung bar tới khi gỡ) ---
    private var swipePreview: String? = null
    private var restoreOffer = false
    private val restoreText = "↩\uFE0E " + context.getString(R.string.ime_restore)
    private val chipText = TextPaint(theme.text(14f, medium = true))
    private val chipTextOff = theme.centerOffset(chipText)

    // --- touch ---
    private var target = T_NONE
    private var targetIndex = 0
    private var downX = 0f; private var downY = 0f

    init {
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        layoutPaste()
    }

    /** Chiều cao strip (dp → px) — root dùng để đặt vùng phím. */
    fun stripPx(): Float = if (!suggestionsEnabled) 0f
        else theme.dp(KeyLayout.COLLAPSED_STRIP + (KeyLayout.OPEN_STRIP - KeyLayout.COLLAPSED_STRIP) * openness)

    /** Chiều cao view = strip + 4 dp phủ lên mép hàng phím (nút nổi 18 dp). */
    fun viewHeightPx(): Int = if (!suggestionsEnabled) 0 else (stripPx() + theme.dp(4f)).toInt()

    fun configure(enabled: Boolean, collapsed: Boolean, templatesEnabled: Boolean) {
        anim?.cancel()
        this.suggestionsEnabled = enabled
        this.collapsed = collapsed
        this.templatesEnabled = templatesEnabled
        openness = if (collapsed) 0f else 1f
        lastSig = ""
        if (!enabled || collapsed) clearContent()
        invalidate()
    }

    fun setPlane(p: Plane) {
        if (p == plane) return
        plane = p
        if (p == Plane.EMOJI) paste = false
        invalidate()
    }

    private val barVisible get() = suggestionsEnabled && plane != Plane.EMOJI

    private fun clearContent() {
        for (i in 0..2) { slotText[i] = null; slotPayload[i] = null; emojiText[i] = null }
        emojiCount = 0; paste = false
        lastSet = null
    }

    /** Vuốt ⌫: đoạn sẽ xoá (null = gỡ). */
    fun showSwipePreview(text: String?) {
        if (text == swipePreview) return
        swipePreview = text
        invalidate()
    }

    /** Ô "↩︎ Khôi phục" một lượt sau vuốt ⌫ xoá. */
    fun showRestore(on: Boolean) {
        if (on == restoreOffer) return
        restoreOffer = on
        invalidate()
    }

    /** Có phím chữ ⇒ ẩn thẻ Dán NGAY (không đợi gợi ý nền). */
    fun hidePasteCard() {
        if (!paste) return
        paste = false; lastSig = ""
        invalidate()
    }

    fun show(set: SuggestionSet?) {
        if (!suggestionsEnabled || collapsed) return
        if (set == null) return
        val sig = set.signature() + (if (set.paste) "\u0005p" else "")
        if (sig == lastSig && width > 0) return
        lastSig = sig
        lastSet = set
        layoutSlots(set)
        invalidate()
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        if (w != oldw) { lastSet?.let { layoutSlots(it) }; layoutPaste() }
    }

    private fun layoutSlots(set: SuggestionSet) {
        val disp = arrayOfNulls<String>(3)
        clearContent()
        lastSet = set
        if (set.nextWords.isNotEmpty()) {
            // Gboard: gợi ý tốt nhất ở GIỮA (slot 1), rồi trái, rồi phải.
            val order = intArrayOf(1, 0, 2)
            for (i in 0 until minOf(3, set.nextWords.size)) {
                disp[order[i]] = set.nextWords[i]; slotPayload[order[i]] = set.nextWords[i]
            }
        } else {
            // Không ngoặc kép kiểu iOS: Gboard hiện nguyên chữ đã gõ ở slot trái.
            set.literal?.let { disp[0] = it; slotPayload[0] = it }
            set.word?.let { disp[1] = it; slotPayload[1] = it }
            if (set.emojis.isEmpty()) set.word2?.let { disp[2] = it; slotPayload[2] = it }
        }
        val emojis = if (set.nextWords.isEmpty()) set.emojis.take(3) else emptyList()
        emojiCount = emojis.size
        for (i in emojis.indices) emojiText[i] = emojis[i]
        paste = set.paste

        // Gboard: 3 ô bằng nhau, không vạch ngăn; emoji chia đều ô thứ 3.
        val barL = theme.dp(KeyLayout.STRIP_ZONE_W)
        val barR = width - theme.dp(KeyLayout.STRIP_ZONE_W)
        val third = (barR - barL) / 3f
        val pad = theme.dp(4f)
        for (i in 0..2) {
            slotL[i] = barL + i * third; slotR[i] = slotL[i] + third
            val t = disp[i] ?: continue
            val p = if (i == 1) wordCenterPaint else wordPaint
            slotText[i] = TextUtils.ellipsize(t, p, third - 2 * pad, TextUtils.TruncateAt.MIDDLE).toString()
        }
        if (emojiCount > 0) {
            val each = third / emojiCount
            for (i in 0 until emojiCount) { emojiL[i] = slotL[2] + i * each; emojiR[i] = slotL[2] + (i + 1) * each }
        }
    }

    /** Chip clipboard kiểu Gboard: pill màu secondary container giữa bar, icon + "Dán" + mô tả. */
    private fun layoutPaste() {
        val cy = theme.dp(KeyLayout.BAR_TOP_PAD + 10f)
        val h = theme.dp(28f)
        val icon = theme.dp(16f); val gap = theme.dp(6f); val padH = theme.dp(12f)
        val tW = pasteTitle.measureText(pasteTitleText); val sW = pasteSub.measureText(pasteSubText)
        val maxW = maxOf(0f, width - 2 * theme.dp(KeyLayout.STRIP_ZONE_W))
        var total = padH + icon + gap + tW + gap + sW + padH
        pasteShowSub = total <= maxW
        if (!pasteShowSub) total = padH + icon + gap + tW + padH
        pasteL = (width - total) / 2; pasteR = pasteL + total
        pasteT = cy - h / 2; pasteB = cy + h / 2
        pasteIconCx = pasteL + padH + icon / 2
        pasteIconCy = cy
        pasteTextX = pasteL + padH + icon + gap
        pasteSubX = pasteTextX + tW + gap
        pasteTitleBase = cy + theme.centerOffset(pasteTitle)
        pasteSubBase = cy + theme.centerOffset(pasteSub)
    }

    // MARK: animation thu gọn

    private fun toggleCollapsed() {
        feedback.click(Feedback.MODIFIER, this)
        val target = !collapsed
        collapsed = target
        lastSig = ""
        if (target) clearContent()
        anim?.cancel()
        anim = ValueAnimator.ofFloat(openness, if (target) 0f else 1f).apply {
            duration = 200
            interpolator = AccelerateDecelerateInterpolator()
            addUpdateListener {
                openness = it.animatedValue as Float
                listener?.onStripHeightChanged()
                invalidate()
            }
            addListener(object : android.animation.AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: android.animation.Animator) {
                    anim = null
                    listener?.onBarToggled(collapsed)
                }
            })
            start()
        }
    }

    // MARK: vẽ

    override fun onDraw(c: Canvas) {
        if (!barVisible) return
        val w = width.toFloat()
        val o = openness
        // Icon toolbar kiểu Gboard ở đúng vị trí ☰/⌄ cũ: nội suy giữa vị trí nổi (thu gọn)
        // và vị trí zone (mở).
        val cyOpen = theme.dp(KeyLayout.BAR_TOP_PAD + 10f)
        val cyFloat = theme.dp(7f)
        val cy = cyFloat + (cyOpen - cyFloat) * o
        if (templatesEnabled) {
            val bx = theme.dp(32f) + (theme.dp(26f) - theme.dp(32f)) * o
            val active = plane == Plane.TEMPLATES && o > 0.5f
            if (active) c.drawCircle(bx, cy, theme.dp(15f), chipPaint)
            iconPaint.color = theme.withAlpha(theme.ink, if (active) 1f else 0.75f)
            ImeIcons.draw(c, ImeIcons.GRID, bx, cy, theme.dp(14f + 4f * o), iconPaint)
        }
        val chx = (w - theme.dp(24f)) + (theme.dp(24f) - theme.dp(26f)) * o
        iconPaint.color = theme.withAlpha(theme.ink, 0.75f)
        ImeIcons.draw(c, ImeIcons.CHEVRON_DOWN, chx, cy, theme.dp(14f + 2f * o), iconPaint, rotationDeg = 180f * (1f - o))
        if (o <= 0f || collapsed && anim == null) return
        val alpha = (255 * o).toInt()
        swipePreview?.let { drawChip(c, "⌫ " + it.replace('\n', ' '), alpha, TextUtils.TruncateAt.START); return }
        if (restoreOffer) { drawChip(c, restoreText, alpha, TextUtils.TruncateAt.END); return }
        if (paste) { drawPaste(c, alpha); return }
        val barCy = cyOpen
        val hh = theme.dp(14f); val inset = theme.dp(2f)
        if (pressed == T_SLOT) {
            val i = pressedIndex
            c.drawRoundRect(slotL[i] + inset, barCy - hh, slotR[i] - inset, barCy + hh, hh, hh, pressPaint)
        } else if (pressed == T_EMOJI) {
            val i = pressedIndex
            c.drawRoundRect(emojiL[i] + inset, barCy - hh, emojiR[i] - inset, barCy + hh, hh, hh, pressPaint)
        }
        wordPaint.color = theme.ink; wordPaint.alpha = alpha
        wordCenterPaint.color = theme.ink; wordCenterPaint.alpha = alpha
        for (i in 0..2) {
            val s = slotText[i] ?: continue
            if (i == 1) c.drawText(s, (slotL[i] + slotR[i]) / 2, barCy + wordCenterOff, wordCenterPaint)
            else c.drawText(s, (slotL[i] + slotR[i]) / 2, barCy + wordOff, wordPaint)
        }
        emojiPaint.alpha = alpha
        for (i in 0 until emojiCount) {
            val s = emojiText[i] ?: continue
            c.drawText(s, (emojiL[i] + emojiR[i]) / 2, barCy + emojiOff, emojiPaint)
        }
    }

    /** Pill giữa bar (cùng kiểu thẻ Dán) cho xem trước vuốt ⌫ / Khôi phục. */
    private fun drawChip(c: Canvas, text: String, alpha: Int, trunc: TextUtils.TruncateAt) {
        val cy = theme.dp(KeyLayout.BAR_TOP_PAD + 10f)
        val padH = theme.dp(14f); val h = theme.dp(28f)
        val maxW = maxOf(0f, width - 2 * theme.dp(KeyLayout.STRIP_ZONE_W) - 2 * padH)
        val t = TextUtils.ellipsize(text, chipText, maxW, trunc).toString()
        val w = chipText.measureText(t) + 2 * padH
        val l = (width - w) / 2
        chipPaint.alpha = if (pressed == T_RESTORE) (alpha * 0.8f).toInt() else alpha
        c.drawRoundRect(l, cy - h / 2, l + w, cy + h / 2, h / 2, h / 2, chipPaint)
        chipPaint.alpha = 255
        chipText.color = theme.ink; chipText.alpha = alpha
        c.drawText(t, width / 2f, cy + chipTextOff, chipText)
    }

    private fun drawPaste(c: Canvas, alpha: Int) {
        chipPaint.alpha = if (pressed == T_PASTE) (alpha * 0.8f).toInt() else alpha
        val r = (pasteB - pasteT) / 2
        c.drawRoundRect(pasteL, pasteT, pasteR, pasteB, r, r, chipPaint)
        chipPaint.alpha = 255
        iconPaint.color = theme.withAlpha(theme.ink, alpha / 255f)
        ImeIcons.draw(c, ImeIcons.CLIPBOARD, pasteIconCx, pasteIconCy, theme.dp(16f), iconPaint)
        pasteTitle.alpha = alpha
        c.drawText(pasteTitleText, pasteTextX, pasteTitleBase, pasteTitle)
        if (pasteShowSub) {
            pasteSub.color = theme.withAlpha(theme.ink, 0.7f * alpha / 255f)
            c.drawText(pasteSubText, pasteSubX, pasteSubBase, pasteSub)
        }
    }

    // MARK: touch

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(e: MotionEvent): Boolean {
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                target = findTarget(e.x, e.y)
                downX = e.x; downY = e.y
                if (target == T_SLOT || target == T_EMOJI || target == T_PASTE || target == T_RESTORE) {
                    pressed = target; pressedIndex = targetIndex; invalidate()
                }
                return target != T_NONE
            }
            MotionEvent.ACTION_UP -> {
                val t = target; target = T_NONE
                if (pressed != T_NONE) { pressed = T_NONE; invalidate() }
                if (abs(e.x - downX) > theme.dp(40f) || abs(e.y - downY) > theme.dp(40f)) return true
                fire(t)
            }
            MotionEvent.ACTION_CANCEL -> { target = T_NONE; if (pressed != T_NONE) { pressed = T_NONE; invalidate() } }
        }
        return true
    }

    private fun findTarget(x: Float, y: Float): Int {
        if (!barVisible) return T_NONE
        val w = width.toFloat()
        val strip = stripPx()
        if (collapsed || openness < 1f) {
            if (y > theme.dp(18f)) return T_NONE
            if (templatesEnabled && x < theme.dp(64f)) return T_BURGER
            if (x >= w - theme.dp(48f)) return T_CHEVRON
            return T_NONE
        }
        if (y > strip) return T_NONE          // không lấn hàng Q–P
        val zone = theme.dp(KeyLayout.STRIP_ZONE_W)
        if (x < zone) return if (templatesEnabled) T_BURGER else T_NONE
        if (x >= w - zone) return T_CHEVRON
        if (swipePreview != null) return T_NONE
        if (restoreOffer) return T_RESTORE
        if (paste) return T_PASTE
        for (i in 0 until emojiCount) if (x >= emojiL[i] && x < emojiR[i]) { targetIndex = i; return T_EMOJI }
        for (i in 0..2) if (slotText[i] != null && x >= slotL[i] && x < slotR[i]) { targetIndex = i; return T_SLOT }
        return T_NONE
    }

    private fun fire(t: Int) {
        when (t) {
            T_BURGER -> { feedback.click(Feedback.MODIFIER, this); listener?.onToggleTemplates() }
            T_CHEVRON -> toggleCollapsed()
            T_PASTE -> { feedback.click(Feedback.MODIFIER, this); listener?.onSuggestion(SuggestionSet.PASTE_TOKEN) }
            T_RESTORE -> { feedback.click(Feedback.MODIFIER, this); listener?.onRestoreDeleted() }
            T_SLOT -> slotPayload[targetIndex]?.let { feedback.click(Feedback.MODIFIER, this); listener?.onSuggestion(it) }
            T_EMOJI -> emojiText[targetIndex]?.let { feedback.click(Feedback.MODIFIER, this); listener?.onSuggestion(it) }
        }
    }

    fun onHidden() {
        target = T_NONE; pressed = T_NONE
    }

    companion object {
        private const val T_NONE = 0
        private const val T_BURGER = 1
        private const val T_CHEVRON = 2
        private const val T_PASTE = 3
        private const val T_SLOT = 4
        private const val T_EMOJI = 5
        private const val T_RESTORE = 6
    }
}
