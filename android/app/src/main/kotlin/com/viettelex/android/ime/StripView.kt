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
    private val divX = FloatArray(2)
    private val divVis = BooleanArray(2)
    private var paste = false
    private var lastSig = ""
    private var lastSet: SuggestionSet? = null

    private val wordPaint = TextPaint(theme.text(17f))
    private val wordOff = theme.centerOffset(wordPaint)
    private val emojiPaint = theme.text(20f)
    private val emojiOff = theme.centerOffset(emojiPaint)
    private val divPaint = theme.fill(theme.withAlpha(theme.ink, 0.18f))
    private val iconPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val pasteTitle = theme.text(14f, align = Paint.Align.LEFT)
    private val pasteSub = theme.text(10f, color = theme.withAlpha(theme.ink, 0.55f), align = Paint.Align.LEFT)
    private val pasteTitleText = context.getString(R.string.ime_paste_title)
    private val pasteSubText = context.getString(R.string.ime_paste_sub)
    private var pasteIconCx = 0f; private var pasteTextX = 0f
    private var pasteTitleBase = 0f; private var pasteSubBase = 0f; private var pasteIconCy = 0f

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
        emojiCount = 0; divVis[0] = false; divVis[1] = false; paste = false
        lastSet = null
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
            for (i in 0 until minOf(3, set.nextWords.size)) { disp[i] = set.nextWords[i]; slotPayload[i] = set.nextWords[i] }
        } else {
            set.literal?.let { disp[0] = "“$it”"; slotPayload[0] = it }
            set.word?.let { disp[1] = it; slotPayload[1] = it }
            if (set.emojis.isEmpty()) set.word2?.let { disp[2] = it; slotPayload[2] = it }
        }
        val emojis = if (set.nextWords.isEmpty()) set.emojis.take(3) else emptyList()
        emojiCount = emojis.size
        for (i in emojis.indices) emojiText[i] = emojis[i]
        paste = set.paste

        // fillProportionally: bề rộng theo cỡ chữ intrinsic, divider 1 dp, spacing 6.
        val barL = theme.dp(KeyLayout.STRIP_ZONE_W)
        val barR = width - theme.dp(KeyLayout.STRIP_ZONE_W)
        val vis0 = disp[0] != null; val vis1 = disp[1] != null
        val vis2 = disp[2] != null || emojiCount > 0
        divVis[0] = vis0 && (vis1 || vis2)
        divVis[1] = vis1 && vis2
        val intrinsic = FloatArray(4)
        for (i in 0..2) disp[i]?.let { intrinsic[i] = wordPaint.measureText(it) }
        var maxE = 0f
        for (i in 0 until emojiCount) maxE = maxOf(maxE, emojiPaint.measureText(emojiText[i]))
        intrinsic[3] = maxE * emojiCount
        // thứ tự: s0 d0 s1 d1 s2 emoji
        var visibleCount = 0
        var flexSum = 0f
        for (i in 0..2) if (disp[i] != null) { visibleCount++; flexSum += intrinsic[i] }
        if (emojiCount > 0) { visibleCount++; flexSum += intrinsic[3] }
        val divCount = (if (divVis[0]) 1 else 0) + (if (divVis[1]) 1 else 0)
        visibleCount += divCount
        if (visibleCount == 0) return
        val gap = theme.dp(6f)
        val avail = (barR - barL) - divCount * theme.dp(1f) - gap * (visibleCount - 1)
        val scale = if (flexSum > 0) avail / flexSum else 0f
        var x = barL
        fun place(i: Int) {
            val w = intrinsic[i] * scale
            slotL[i] = x; slotR[i] = x + w
            slotText[i] = TextUtils.ellipsize(disp[i], wordPaint, w, TextUtils.TruncateAt.MIDDLE).toString()
            x += w + gap
        }
        fun divider(k: Int) { divX[k] = x; x += theme.dp(1f) + gap }
        if (disp[0] != null) place(0)
        if (divVis[0]) divider(0)
        if (disp[1] != null) place(1)
        if (divVis[1]) divider(1)
        if (disp[2] != null) place(2)
        if (emojiCount > 0) {
            val w = intrinsic[3] * scale
            val each = w / emojiCount
            for (i in 0 until emojiCount) { emojiL[i] = x + i * each; emojiR[i] = x + (i + 1) * each }
        }
    }

    private fun layoutPaste() {
        val top = theme.dp(KeyLayout.BAR_TOP_PAD)
        val fmT = pasteTitle.fontMetrics; val fmS = pasteSub.fontMetrics
        val hT = fmT.descent - fmT.ascent; val hS = fmS.descent - fmS.ascent
        pasteTitleBase = top - fmT.ascent
        pasteSubBase = top + hT - theme.dp(2f) - fmS.ascent
        pasteIconCy = top + (hT + hS - theme.dp(2f)) / 2
        val iconBox = theme.dp(18f)
        val textW = maxOf(pasteTitle.measureText(pasteTitleText), pasteSub.measureText(pasteSubText))
        val total = iconBox + theme.dp(8f) + textW
        val x0 = (width - total) / 2
        pasteIconCx = x0 + iconBox / 2
        pasteTextX = x0 + iconBox + theme.dp(8f)
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
        // ☰ / ⌄: nội suy giữa vị trí nổi (thu gọn) và vị trí zone (mở)
        val cyOpen = theme.dp(KeyLayout.BAR_TOP_PAD + 10f)
        val cyFloat = theme.dp(7f)
        val cy = cyFloat + (cyOpen - cyFloat) * o
        if (templatesEnabled) {
            val bx = theme.dp(32f) + (theme.dp(26f) - theme.dp(32f)) * o
            val a = if (plane == Plane.TEMPLATES && o > 0.5f) 0.9f else 0.45f
            iconPaint.color = theme.withAlpha(theme.ink, a)
            ImeIcons.draw(c, ImeIcons.MENU, bx, cy, theme.dp(15.6f + 1.4f * o), iconPaint)
        }
        val chx = (w - theme.dp(24f)) + (theme.dp(24f) - theme.dp(26f)) * o
        iconPaint.color = theme.withAlpha(theme.ink, 0.45f)
        ImeIcons.draw(c, ImeIcons.CHEVRON_DOWN, chx, cy, theme.dp(15.6f), iconPaint, rotationDeg = 180f * (1f - o))
        if (o <= 0f || collapsed && anim == null) return
        val alpha = (255 * o).toInt()
        if (paste) { drawPaste(c, alpha); return }
        val barCy = cyOpen
        wordPaint.color = theme.ink
        wordPaint.alpha = alpha
        for (i in 0..2) {
            val s = slotText[i] ?: continue
            c.drawText(s, (slotL[i] + slotR[i]) / 2, barCy + wordOff, wordPaint)
        }
        emojiPaint.alpha = alpha
        for (i in 0 until emojiCount) {
            val s = emojiText[i] ?: continue
            c.drawText(s, (emojiL[i] + emojiR[i]) / 2, barCy + emojiOff, emojiPaint)
        }
        divPaint.alpha = (Math.round(255 * 0.18f) * o).toInt()
        val barTop = theme.dp(KeyLayout.BAR_TOP_PAD)
        for (k in 0..1) if (divVis[k]) {
            c.drawRect(divX[k], barTop + theme.dp(4f), divX[k] + theme.dp(1f), barTop + theme.dp(16f), divPaint)
        }
    }

    private fun drawPaste(c: Canvas, alpha: Int) {
        iconPaint.color = theme.withAlpha(theme.ink, 0.8f * alpha / 255f)
        ImeIcons.draw(c, ImeIcons.CLIPBOARD, pasteIconCx, pasteIconCy, theme.dp(18f), iconPaint)
        pasteTitle.alpha = alpha
        c.drawText(pasteTitleText, pasteTextX, pasteTitleBase, pasteTitle)
        pasteSub.color = theme.withAlpha(theme.ink, 0.55f * alpha / 255f)
        c.drawText(pasteSubText, pasteTextX, pasteSubBase, pasteSub)
    }

    // MARK: touch

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(e: MotionEvent): Boolean {
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                target = findTarget(e.x, e.y)
                downX = e.x; downY = e.y
                return target != T_NONE
            }
            MotionEvent.ACTION_UP -> {
                val t = target; target = T_NONE
                if (abs(e.x - downX) > theme.dp(40f) || abs(e.y - downY) > theme.dp(40f)) return true
                fire(t)
            }
            MotionEvent.ACTION_CANCEL -> target = T_NONE
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
        if (paste) return T_PASTE
        val sx = theme.dp(3f)
        for (i in 0..2) if (slotText[i] != null && x >= slotL[i] - sx && x < slotR[i] + sx) { targetIndex = i; return T_SLOT }
        for (i in 0 until emojiCount) if (x >= emojiL[i] - sx && x < emojiR[i] + sx) { targetIndex = i; return T_EMOJI }
        return T_NONE
    }

    private fun fire(t: Int) {
        when (t) {
            T_BURGER -> { feedback.click(Feedback.MODIFIER, this); listener?.onToggleTemplates() }
            T_CHEVRON -> toggleCollapsed()
            T_PASTE -> { feedback.click(Feedback.MODIFIER, this); listener?.onSuggestion(SuggestionSet.PASTE_TOKEN) }
            T_SLOT -> slotPayload[targetIndex]?.let { feedback.click(Feedback.MODIFIER, this); listener?.onSuggestion(it) }
            T_EMOJI -> emojiText[targetIndex]?.let { feedback.click(Feedback.MODIFIER, this); listener?.onSuggestion(it) }
        }
    }

    fun onHidden() {
        target = T_NONE
    }

    companion object {
        private const val T_NONE = 0
        private const val T_BURGER = 1
        private const val T_CHEVRON = 2
        private const val T_PASTE = 3
        private const val T_SLOT = 4
        private const val T_EMOJI = 5
    }
}
