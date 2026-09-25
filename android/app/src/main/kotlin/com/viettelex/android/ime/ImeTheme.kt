package com.viettelex.android.ime

import android.content.Context
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.util.TypedValue
import androidx.core.content.ContextCompat
import com.viettelex.android.R

/**
 * Màu + Paint dùng chung cho mọi view IME. Dựng một lần mỗi lần tạo input view
 * (IMS tạo lại view khi đổi cấu hình / night mode ⇒ theme mới). Paint tạo sẵn ở
 * đây — onDraw chỉ đổi màu/alpha, không bao giờ `Paint()`.
 */
class ImeTheme(ctx: Context) {
    val res = ctx.resources
    val density = res.displayMetrics.density
    /** Cỡ chữ theo sp nhưng kẹp fontScale ≤ 1.2 (phím cố định chiều cao như iOS). */
    private val textScale = density * res.configuration.fontScale.coerceIn(0.85f, 1.2f)
    val dark = (res.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
    val tablet = res.configuration.smallestScreenWidthDp >= 600
    val landscape = res.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE

    val bg = ContextCompat.getColor(ctx, R.color.ime_bg)
    val keyFill = ContextCompat.getColor(ctx, R.color.ime_key)
    val specialFill = ContextCompat.getColor(ctx, R.color.ime_key_special)
    val ink = ContextCompat.getColor(ctx, R.color.ime_ink)
    val keyShadow = ContextCompat.getColor(ctx, R.color.ime_key_shadow)
    val balloonFill = ContextCompat.getColor(ctx, R.color.ime_balloon)
    val popupFill = ContextCompat.getColor(ctx, R.color.ime_popup)
    val action = ContextCompat.getColor(ctx, R.color.ime_action)

    fun dp(v: Float) = v * density
    fun sp(v: Float) = v * textScale

    fun withAlpha(color: Int, a: Float) = Color.argb((Color.alpha(color) * a).toInt(), Color.red(color),
        Color.green(color), Color.blue(color))

    fun fill(color: Int) = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color; style = Paint.Style.FILL }

    fun text(sizeSp: Float, color: Int = ink, bold: Boolean = false, medium: Boolean = false,
             align: Paint.Align = Paint.Align.CENTER) =
        Paint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG).apply {
            textSize = sp(sizeSp)
            this.color = color
            textAlign = align
            typeface = when {
                bold -> Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
                medium -> Typeface.create("sans-serif-medium", Typeface.NORMAL)
                else -> Typeface.DEFAULT
            }
        }

    /** Baseline để chữ canh giữa dọc tại cy (hộp dòng, như UILabel). */
    fun baseline(p: Paint, cy: Float): Float {
        val fm = p.fontMetrics   // alloc nhỏ — chỉ gọi ngoài onDraw (cache kết quả)
        return cy - (fm.ascent + fm.descent) / 2f
    }

    /** Nửa (ascent+descent) — cache để tính baseline trong onDraw không alloc. */
    fun centerOffset(p: Paint): Float {
        val fm = p.fontMetrics
        return -(fm.ascent + fm.descent) / 2f
    }
}
