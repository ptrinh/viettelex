package com.viettelex.android.ime

import android.annotation.SuppressLint
import android.content.Context
import android.os.Build
import android.view.ViewGroup
import android.view.WindowInsets
import kotlin.math.roundToInt

/**
 * Gốc input view: [KeyboardView] (vùng phím) · [StripView] (strip gợi ý, phủ 4 dp lên
 * mép phím) · [BalloonView] (overlay). Nền ĐỤC toàn khung, cộng inset nav/gesture bar
 * ở đáy (cùng màu bàn phím, spec §6.1). Multi-touch tách theo view con.
 */
@SuppressLint("ViewConstructor")
class ImeRootView(
    context: Context,
    theme: ImeTheme,
    val keyboard: KeyboardView,
    val strip: StripView,
    val balloon: BalloonView,
    /** Vệt gõ vuốt — phủ đúng vùng phím, dưới balloon. */
    val trail: SwipeTrailView,
) : ViewGroup(context) {

    private var navInset = 0

    init {
        setBackgroundColor(theme.bg)
        isMotionEventSplittingEnabled = true
        addView(keyboard)
        addView(strip)
        addView(trail)
        addView(balloon)
    }

    private fun stripPx() = strip.stripPx().roundToInt()

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val w = MeasureSpec.getSize(widthMeasureSpec)
        val keyH = keyboard.keyAreaPx.roundToInt()
        val s = stripPx()
        val h = ImeInsets.totalHeight(s, keyH, navInset)
        keyboard.measure(MeasureSpec.makeMeasureSpec(w, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(keyH, MeasureSpec.EXACTLY))
        strip.measure(MeasureSpec.makeMeasureSpec(w, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(strip.viewHeightPx(), MeasureSpec.EXACTLY))
        trail.measure(MeasureSpec.makeMeasureSpec(w, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(keyH, MeasureSpec.EXACTLY))
        balloon.measure(MeasureSpec.makeMeasureSpec(w, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(s + keyH, MeasureSpec.EXACTLY))
        setMeasuredDimension(w, h)
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        val w = r - l
        val s = stripPx()
        val keyH = keyboard.measuredHeight
        keyboard.layout(0, s, w, s + keyH)
        strip.layout(0, 0, w, strip.measuredHeight)
        trail.layout(0, s, w, s + keyH)
        balloon.layout(0, 0, w, s + keyH)
    }

    private var insetsKnown = false

    override fun onApplyWindowInsets(insets: WindowInsets): WindowInsets {
        applyInsets(insets)
        return insets
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        refreshInsets()
    }

    /**
     * Đọc insets CHƯA bị nuốt của cửa sổ IME (khung IMS có thể consume trước khi tới
     * view này) — gọi mỗi lần bàn phím hiện.
     */
    fun refreshInsets() {
        val ri = rootView?.rootWindowInsets
        if (ri != null) applyInsets(ri) else update(0, 0)
    }

    @Suppress("DEPRECATION")
    private fun applyInsets(insets: WindowInsets) {
        val nav: Int
        val tap: Int
        if (Build.VERSION.SDK_INT >= 30) {
            nav = insets.getInsets(WindowInsets.Type.navigationBars()).bottom
            tap = insets.getInsets(WindowInsets.Type.tappableElement()).bottom
        } else {
            nav = insets.systemWindowInsetBottom
            tap = if (Build.VERSION.SDK_INT >= 29) insets.tappableElementInsets.bottom else 0
        }
        insetsKnown = true
        update(nav, tap)
    }

    private fun update(nav: Int, tap: Int) {
        val pad = ImeInsets.bottomPad(Build.VERSION.SDK_INT, nav, tap, systemNavBarHeight(), insetsKnown)
        if (pad != navInset) { navInset = pad; requestLayout() }
    }

    @android.annotation.SuppressLint("DiscouragedApi", "InternalInsetResource")
    private fun systemNavBarHeight(): Int {
        val r = resources
        for (name in arrayOf("navigation_bar_frame_height", "navigation_bar_height")) {
            val id = r.getIdentifier(name, "dimen", "android")
            if (id != 0) { val v = r.getDimensionPixelSize(id); if (v > 0) return v }
        }
        return 0
    }
}
