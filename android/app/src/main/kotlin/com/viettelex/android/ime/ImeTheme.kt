package com.viettelex.android.ime

import android.content.Context
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.util.TypedValue
import androidx.core.content.ContextCompat
import com.viettelex.android.R
import com.viettelex.keyboard.KeyLabelFont
import com.viettelex.keyboard.KeyLabelWeight
import com.viettelex.keyboard.KeyStyle
import com.viettelex.keyboard.ThemePalette
import com.viettelex.keyboard.ThemeSettings
import com.viettelex.keyboard.chipFill
import com.viettelex.keyboard.chipInk
import com.viettelex.keyboard.withTransparency

/**
 * Màu + Paint dùng chung cho mọi view IME. Dựng một lần mỗi lần tạo input view
 * (IMS tạo lại view khi đổi cấu hình / night mode ⇒ theme mới). Paint tạo sẵn ở
 * đây — onDraw chỉ đổi màu/alpha, không bao giờ `Paint()`.
 */
class ImeTheme(ctx: Context, val settings: ThemeSettings = ThemeSettings(), wallpaperFile: Boolean = false) {
    val res = ctx.resources
    val density = res.displayMetrics.density
    /** Cỡ chữ theo sp nhưng kẹp fontScale ≤ 1.2 (phím cố định chiều cao như iOS). */
    private val textScale = density * res.configuration.fontScale.coerceIn(0.85f, 1.2f)
    private val systemDark = (res.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
    val tablet = res.configuration.smallestScreenWidthDp >= 600
    val landscape = res.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE

    /**
     * Token theme (module :keyboard, [KeyboardTheme]). Hệ thống = màu Material You
     * trong resources như trước; theme khác/ảnh nền ghi đè.
     */
    /** "Tuỳ chỉnh nâng cao" thực dùng (sau cổng Plus) — mặc định ⇒ y như cũ. */
    val keyStyle: KeyStyle = settings.effectiveKeyStyle

    /** Tệp tải về của theme (phông / ảnh nền / tiền cảnh / skin); null = không có ⇒ không đọc đĩa. */
    private val assetPlan: com.viettelex.keyboard.ThemeAssetPlan? =
        keyStyle.assets.takeIf { !it.isEmpty }?.let { com.viettelex.keyboard.ThemeAssetPlan.make(it) }
    private val assetDir = com.viettelex.keyboard.ThemeAssetStore.dir(ctx.filesDir)
    /** Mốc mục lục (app tải xong ⇒ đổi ⇒ dựng lại view). Chỉ stat khi theme có tệp. */
    private val assetStamp: Long = if (assetPlan == null) 0L
        else java.io.File(assetDir, com.viettelex.keyboard.ThemeAssetStore.INDEX_NAME).lastModified()
    /** Giải LƯỜI (view đầu tiên cần) — dựng ImeTheme chỉ để so chữ ký không giải ảnh nào. */
    val assets: LoadedThemeAssets? by lazy { assetPlan?.let { ThemeAssetLoader.load(it, assetDir, assetStamp) } }

    private val basePalette: ThemePalette = run {
        // Theme tự tạo ("Giao diện JSON") hoặc có sẵn; Hệ thống = màu resource (Material You) hoặc bảng tĩnh
        // khi tắt "Dùng màu hình nền (Material You)" ([com.viettelex.keyboard.SystemColors]).
        val base = settings.basePalette(systemDark, android.os.Build.VERSION.SDK_INT) ?: imeResourcePalette(ctx, systemDark)
        // Tuỳ chỉnh nâng cao (Plus): màu chữ / nền phím — trước ảnh nền và độ trong suốt.
        // Vá chế độ + màu chữ/phím + Màu nhấn (Nhập, ⇧ bật/Caps, vệt vuốt) — riêng theme đang dùng, giải MỘT lần ở đây.
        val styled = settings.styledCurrent(base, systemDark)
        if (settings.wallpaperActive(wallpaperFile)) styled.overWallpaper() else styled
    }
    /** Sau hai thanh độ trong suốt (phím / ký tự) — áp một lần ở đây, không mỗi phím. */
    val palette: ThemePalette = basePalette.withTransparency(settings.keyboardTransparency,
        settings.labelTransparency, systemDark)
    /** Tông vùng không phải phím (thanh điều hướng): theme nền tối phím sáng (Piano) theo nền. */
    val dark = palette.surfaceDark ?: palette.isDark
    val bg = palette.bg
    val keyFill = palette.keyFill
    val specialFill = palette.specialFill
    /** Phím chức năng / phím cách / chữ-icon phím chức năng (= như cũ trừ theme tô riêng — Xanh lá). */
    val fnFill = palette.fnFill
    val spaceFill = palette.spaceFill
    val fnInk = palette.fnInk
    /** Nhãn / logo trên phím cách: phím cách tô nền chức năng riêng (Piano: đen) ⇒ chữ phím chức năng. */
    val spaceInk = if (palette.functionFill != null) palette.fnInk else palette.keyInk
    /** Chữ/icon trên phím, strip, pane (đã đổi đen/trắng nếu nền trong suốt lộ nền khác tông). */
    val ink = palette.keyInk
    /**
     * Chữ/icon thanh gợi ý, bảng emoji / clipboard / ô tìm emoji (nằm trên NỀN, không trên phím): = [ink] trừ theme
     * nền tối phím sáng (Piano) — khi đó đen/trắng đọc được trên nền.
     */
    val barInk = palette.barInk ?: ink
    /** Chữ balloon/popup — nền balloon không trong suốt nên giữ màu theme gốc. */
    val balloonInk = palette.ink
    /** Alpha chữ/icon trên phím (độ trong suốt ký tự). */
    val labelAlpha = palette.labelAlpha
    /** Nền pane phủ lên vùng phím (clipboard) — luôn đục, không để phím lộ qua. */
    val paneBg = basePalette.bg
    val balloonFill = palette.balloon
    val popupFill = palette.popup
    /** Nền phím enter/hành động (pill màu nhấn) + màu icon trên nó. */
    val action = palette.action
    val actionInk = palette.actionInk
    /** Chip (thẻ Dán, highlight category emoji, nhấn slot gợi ý). */
    val chip = palette.chip
    /** Chữ/icon trên chip thanh gợi ý (thẻ Dán, chip số, pill) — luôn đọc được trên [chip]. */
    val chipInk = palette.chipInk(systemDark)
    /** Nền chip với độ mờ hoạt ảnh/nhấn [opacity] — nhân alpha gốc của chip (Kính: trắng 30%), không ghi đè. */
    fun chipFill(opacity: Float = 1f) = palette.chipFill(opacity)
    /** Ô phóng to / popup: kiểu phím của theme ([KeyPopupStyle]) — giải MỘT lần ở đây, không mỗi lần bấm. */
    val popupStyle: com.viettelex.keyboard.KeyPopupStyle = com.viettelex.keyboard.KeyPopupStyle.make(palette, keyStyle, systemDark)
    /** Người dùng chọn Màu nhấn ⇒ ⇧ bật/Caps tô [action] / [actionInk]. */
    val accentShift = palette.accentShift
    val trail = palette.trail
    /** Viền phím (tương phản cao / kính) — null = không viền. */
    val keyBorder = palette.keyBorder
    /** Nhận diện theme để IME biết khi nào phải dựng lại input view. */
    val signature = "${settings.effectiveTheme.id}|${settings.materialYou}|$systemDark|${palette.wallpaper}|${settings.dim}|${settings.version}" +
        "|${settings.keyboardTransparency}|${settings.labelTransparency}|$keyStyle|${settings.effectiveCustom?.canonical?.hashCode()}" +
        "|$assetStamp"

    /** Màu khi đè phím: phủ ink 12% kiểu state layer Material. */
    fun pressed(color: Int): Int = blend(color, ink, 0.12f)

    fun blend(a: Int, b: Int, t: Float): Int = Color.argb(Color.alpha(a),
        (Color.red(a) + (Color.red(b) - Color.red(a)) * t).toInt(),
        (Color.green(a) + (Color.green(b) - Color.green(a)) * t).toInt(),
        (Color.blue(a) + (Color.blue(b) - Color.blue(a)) * t).toInt())

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
            // Font hệ thống "sans-serif" (Roboto / Google Sans trên máy Pixel) như Gboard.
            typeface = when {
                bold -> Typeface.create("sans-serif", Typeface.BOLD)
                medium -> Typeface.create("sans-serif-medium", Typeface.NORMAL)
                else -> Typeface.create("sans-serif", Typeface.NORMAL)
            }
        }

    /**
     * Typeface nhãn phím (+ ô phóng to / popup) theo Tuỳ chỉnh nâng cao. null = mặc định (paint
     * giữ typeface cũ — không đổi gì). Độ đậm 100…900 cần API 28; máy cũ: Đậm/Rất đậm ⇒ BOLD,
     * Mỏng/Vừa ⇒ họ "-light"/"-medium" của sans-serif.
     */
    val keyTypeface: Typeface? by lazy { keyLabelTypeface(keyStyle, assets?.typeface) }

    /** Bo góc phím [w]×[h] px (Tuỳ chỉnh nâng cao); mặc định ⇒ [fallback]. */
    fun keyRadius(w: Float, h: Float, fallback: Float): Float = KeyStyle.cornerRadius(keyStyle.corner, w, h, fallback)

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

/**
 * Màu Hệ thống từ resource ime_colors.xml (API 31+: Material You theo hình nền; máy cũ: bảng tĩnh). Dùng chung IME
 * và bản xem trước trong app (cùng [ctx] cấu hình sáng/tối ⇒ [dark] khớp).
 */
fun imeResourcePalette(ctx: Context, dark: Boolean): ThemePalette = ThemePalette(
    bg = ContextCompat.getColor(ctx, R.color.ime_bg),
    keyFill = ContextCompat.getColor(ctx, R.color.ime_key),
    specialFill = ContextCompat.getColor(ctx, R.color.ime_key_special),
    ink = ContextCompat.getColor(ctx, R.color.ime_ink),
    trail = ContextCompat.getColor(ctx, R.color.ime_action),
    balloon = ContextCompat.getColor(ctx, R.color.ime_balloon),
    popup = ContextCompat.getColor(ctx, R.color.ime_popup),
    action = ContextCompat.getColor(ctx, R.color.ime_action),
    actionInk = ContextCompat.getColor(ctx, R.color.ime_action_ink),
    chip = ContextCompat.getColor(ctx, R.color.ime_chip),
    isDark = dark)

/**
 * Typeface nhãn phím theo Tuỳ chỉnh nâng cao — DÙNG CHUNG bàn phím ([ImeTheme.keyTypeface]) và ô xem trước trong app
 * (KeyboardPreview) để hai bên không lệch nhau. [downloaded] = phông tải về đã nạp từ kho (đã kiểm ở app); null (chưa
 * tải / thiếu tệp) ⇒ phông hệ thống như chưa chọn. Kết quả null = mặc định (paint giữ typeface cũ).
 */
fun keyLabelTypeface(st: KeyStyle, downloaded: Typeface?): Typeface? {
    downloaded?.let { tf ->
        return if (android.os.Build.VERSION.SDK_INT >= 28 && st.weight != KeyLabelWeight.REGULAR)
            Typeface.create(tf, st.weight.weight, false) else tf
    }
    if (st.font == KeyLabelFont.DEFAULT || st.font == KeyLabelFont.ROUNDED) {
        if (st.weight == KeyLabelWeight.REGULAR) return null
    }
    val family = st.font.androidFamily ?: "sans-serif"
    val base = Typeface.create(family, Typeface.NORMAL)
    return if (android.os.Build.VERSION.SDK_INT >= 28) Typeface.create(base, st.weight.weight, false)
    else when (st.weight) {
        KeyLabelWeight.BOLD, KeyLabelWeight.HEAVY -> Typeface.create(family, Typeface.BOLD)
        KeyLabelWeight.LIGHT -> if (st.font.androidFamily == null) Typeface.create("sans-serif-light", Typeface.NORMAL) else base
        KeyLabelWeight.MEDIUM -> if (st.font.androidFamily == null) Typeface.create("sans-serif-medium", Typeface.NORMAL) else base
        KeyLabelWeight.REGULAR -> base
    }
}
