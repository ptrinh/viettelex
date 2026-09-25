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
) : ViewGroup(context) {

    private var navInset = 0

    init {
        setBackgroundColor(theme.bg)
        isMotionEventSplittingEnabled = true
        addView(keyboard)
        addView(strip)
        addView(balloon)
    }

    private fun stripPx() = strip.stripPx().roundToInt()

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val w = MeasureSpec.getSize(widthMeasureSpec)
        val keyH = keyboard.keyAreaPx.roundToInt()
        val s = stripPx()
        val h = s + keyH + navInset
        keyboard.measure(MeasureSpec.makeMeasureSpec(w, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(keyH, MeasureSpec.EXACTLY))
        strip.measure(MeasureSpec.makeMeasureSpec(w, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(strip.viewHeightPx(), MeasureSpec.EXACTLY))
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
        balloon.layout(0, 0, w, s + keyH)
    }

    @Suppress("DEPRECATION")
    override fun onApplyWindowInsets(insets: WindowInsets): WindowInsets {
        val bottom = if (Build.VERSION.SDK_INT >= 30) {
            insets.getInsets(WindowInsets.Type.navigationBars()).bottom
        } else insets.systemWindowInsetBottom
        if (bottom != navInset) { navInset = bottom; requestLayout() }
        return insets
    }
}
