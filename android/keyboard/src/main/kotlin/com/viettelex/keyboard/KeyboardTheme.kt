package com.viettelex.keyboard

import kotlin.math.pow

/*
 * Theme bàn phím — MỌI token màu ở một chỗ (ARGB Int thuần, không phụ thuộc Android
 * để test JVM). Bảng màu y hệt iOS (iOS/Keyboard/KeyboardTheme.swift) — sửa màu thì
 * sửa cả hai. Vẽ phím vẫn phẳng: không bóng, không blur runtime.
 */

/** Tiện ích màu ARGB + tương phản WCAG 2.x. */
object ThemeColor {
    fun argb(a: Int, r: Int, g: Int, b: Int) = (a shl 24) or (r shl 16) or (g shl 8) or b
    fun rgb(hex: Int) = hex or (0xFF shl 24)
    fun alpha(c: Int) = (c ushr 24) and 0xFF
    fun red(c: Int) = (c shr 16) and 0xFF
    fun green(c: Int) = (c shr 8) and 0xFF
    fun blue(c: Int) = c and 0xFF
    fun withAlpha(c: Int, a: Float): Int =
        argb((alpha(c) * a).toInt().coerceIn(0, 255), red(c), green(c), blue(c))

    const val WHITE = -0x1          // 0xFFFFFFFF
    const val BLACK = -0x1000000    // 0xFF000000

    /** Trộn [fg] (có alpha) lên nền [bg] (coi như đục) → màu đục. */
    fun over(fg: Int, bg: Int): Int {
        val a = alpha(fg) / 255f
        fun ch(f: Int, b: Int) = (f * a + b * (1 - a) + 0.5f).toInt().coerceIn(0, 255)
        return argb(255, ch(red(fg), red(bg)), ch(green(fg), green(bg)), ch(blue(fg), blue(bg)))
    }

    fun luminance(c: Int): Double {
        fun ch(v: Int): Double { val s = v / 255.0; return if (s <= 0.03928) s / 12.92 else ((s + 0.055) / 1.055).pow(2.4) }
        return 0.2126 * ch(red(c)) + 0.7152 * ch(green(c)) + 0.0722 * ch(blue(c))
    }

    /** Tỉ lệ tương phản WCAG (1…21), bỏ qua alpha. */
    fun contrast(x: Int, y: Int): Double {
        val a = luminance(x); val b = luminance(y)
        return (maxOf(a, b) + 0.05) / (minOf(a, b) + 0.05)
    }
}

/** Bộ token đã giải (theo sáng/tối + ảnh nền). */
data class ThemePalette(
    /** Nền bàn phím; [bgBottom] ≠ null ⇒ gradient dọc (Kính giả lập — Android không có backdrop mờ). */
    val bg: Int,
    val bgBottom: Int? = null,
    val keyFill: Int,
    /** Phím chức năng (Android: nền riêng như Gboard). */
    val specialFill: Int,
    val ink: Int,
    val trail: Int,
    val balloon: Int,
    val popup: Int,
    val action: Int,
    val actionInk: Int,
    val chip: Int,
    /** Viền phím 1dp (tương phản cao / kính) — stroke thường, không offscreen. */
    val keyBorder: Int? = null,
    val isDark: Boolean,
    /** true ⇒ nền là ảnh nền (IME vẽ bitmap + lớp phủ thay cho [bg]). */
    val wallpaper: Boolean = false,
    /** Chữ/icon trên phím (ĐỤC) sau độ trong suốt phím; null = [ink]. Balloon/popup giữ [ink]. */
    val keyLabel: Int? = null,
    /** Alpha chữ/icon trên phím (độ trong suốt ký tự) — IME nhân vào alpha lúc vẽ. */
    val labelAlpha: Float = 1f,
    /**
     * Hệ số alpha bề mặt PHÍM theo độ trong suốt phím (1 = như cũ). KHÔNG áp cho ảnh nền —
     * ảnh nền có độ tối/mờ riêng ([wallpaperLayer]).
     */
    val surfaceAlpha: Float = 1f,
    /** Chữ trên phím do người dùng chọn ([KeyStyle]) — độ trong suốt không đổi sang đen/trắng. */
    val keyLabelPinned: Boolean = false,
    /**
     * Nền phím chức năng + phím cách khi theme tô riêng (Xanh lá); null = như cũ ([specialFill] cho
     * phím chức năng, [keyFill] cho phím cách). Cùng ý nghĩa iOS `functionFill`.
     */
    val functionFill: Int? = null,
    /** Chữ/icon phím chức năng (ĐỤC; alpha theo [labelAlpha] lúc vẽ) — null = [keyInk]. Trắng hồng. */
    val functionInk: Int? = null,
    /** Hoạ tiết nền (tim / hoa) vẽ MỘT lần ở nền IME — null = nền phẳng. */
    val decoration: ThemeDecoration? = null,
    /**
     * Người dùng chọn "Màu nhấn" ([KeyStyle.accentColor]) ⇒ ⇧ bật/Caps tô [action] +
     * [actionInk] (mặc định: Caps tô [chip]). Cùng ý nghĩa iOS `accentShift`.
     */
    val accentShift: Boolean = false,
    /**
     * Chữ/icon thanh gợi ý + bảng emoji/clipboard khi KHÁC chữ phím (theme nền tối phím sáng — Piano); null = như
     * cũ (theo chữ phím). Cùng ý nghĩa iOS `barInk` (ThemeSpec.palette đặt khi chữ không đọc được trên nền).
     */
    val barInk: Int? = null,
    /** Tông vùng không phải phím (thanh điều hướng, …) khi khác [isDark]; null = [isDark]. iOS `surfaceDark`. */
    val surfaceDark: Boolean? = null,
    /**
     * Viền phím cầu vồng (Gaming RGB, slot "borderFx":"rainbow"): MỘT lớp gradient che bằng viền mọi phím
     * (ime/RainbowBorderView) — chỉ trượt màu khi đang gõ, nghỉ thì đứng yên. iOS `rainbowBorder` cùng ý nghĩa.
     */
    val rainbowBorder: Boolean = false,
    /**
     * Lỗ thoát âm trên phím cách (Ghi-ta, slot "spaceDeco":"soundhole"): hình tròn tối + hai vành hoa văn vẽ cùng
     * nền phím cách (Canvas, hình học [Soundhole]) — 0 chi phí mỗi phím. iOS `spaceSoundhole` cùng ý nghĩa.
     */
    val spaceSoundhole: Boolean = false,
) {
    val keyInk: Int get() = keyLabel ?: ink
    /** Nền phím chức năng (⇧ ⌫ 123 🌐 😊…). */
    val fnFill: Int get() = functionFill ?: specialFill
    /** Nền phím cách. */
    val spaceFill: Int get() = functionFill ?: keyFill
    val fnInk: Int get() = functionInk ?: keyInk

    /** Lớp phủ ảnh nền: đen cho theme tối, trắng cho theme sáng. */
    val wallpaperOverlay: Int get() = if (isDark) ThemeColor.BLACK else ThemeColor.WHITE

    /**
     * Cách vẽ ảnh nền (mô hình vẽ thuần — IME + bản xem trước dùng chung): ảnh luôn ĐỤC, lớp phủ
     * theo "Độ tối lớp phủ". Độ trong suốt phím KHÔNG làm mất ảnh nền (bug 100% trước đây: ảnh +
     * lớp phủ nhân surfaceAlpha ⇒ 0 ⇒ ảnh biến mất).
     */
    fun wallpaperLayer(dim: Int): WallpaperLayer =
        WallpaperLayer(1f, ThemeColor.withAlpha(wallpaperOverlay, dim.coerceIn(0, 80) / 100f))

    /**
     * Có ảnh nền: phím hơi trong để ảnh lộ ra. Độ trong chọn sao cho chữ ≥ 4.5:1 (AA)
     * kể cả trên ảnh TỆ NHẤT (trắng dưới theme tối, đen dưới theme sáng), lớp phủ 0%.
     */
    fun overWallpaper(): ThemePalette {
        val worst = if (isDark) ThemeColor.WHITE else ThemeColor.BLACK
        fun legible(base: Int, label: Int = ink): Int {
            val translucent = ThemeColor.alpha(base) < 255
            val solid = if (translucent) (if (isDark) ThemeColor.BLACK else ThemeColor.WHITE) else base
            var a = if (translucent) 0.5f else WALLPAPER_KEY_ALPHA
            while (a < 1f && ThemeColor.contrast(label, ThemeColor.over(ThemeColor.withAlpha(solid, a), worst)) < 4.5) a += 0.05f
            return ThemeColor.withAlpha(solid, a.coerceAtMost(1f))
        }
        // Thanh gợi ý nằm trên lớp phủ ảnh (tông theo isDark) ⇒ chữ riêng của thanh (Piano) đổi cho đọc được.
        val bar = barInk?.let { KeyboardTransparency.readable(it, wallpaperOverlay) }
        return copy(keyFill = legible(keyFill), specialFill = legible(specialFill), functionFill = functionFill?.let { legible(it, functionInk ?: ink) },
            bgBottom = null, wallpaper = true, decoration = null, barInk = bar,
            surfaceDark = if (bar != null && bar != barInk) isDark else surfaceDark)
    }

    companion object { const val WALLPAPER_KEY_ALPHA = 0.8f }
}

/** Ảnh nền: alpha bitmap + màu lớp phủ (ARGB). */
data class WallpaperLayer(val imageAlpha: Float, val overlay: Int)

/**
 * Độ trong suốt (Cài đặt → Giao diện), hai thanh độc lập 0…100% — y hệt iOS
 * (KeyboardTransparency trong iOS/Keyboard/KeyboardTheme.swift):
 * - phím: nền phím + viền (+ nền theme khi KHÔNG có ảnh nền); 100% = phím vô hình, chỉ còn chữ.
 *   Ảnh nền luôn giữ nguyên (đã có độ tối/mờ riêng).
 * - ký tự: chữ/icon/nhãn phụ trên phím; 100% = phím trơn không chữ.
 * Áp bằng alpha của MÀU lúc dựng theme — không alpha nhóm, 0 chi phí mỗi phím.
 */
object KeyboardTransparency {
    /** Chữ phím ≥ 18sp = "chữ lớn" WCAG → 3:1; dưới ngưỡng mới đổi sang đen/trắng. */
    const val MIN_LABEL_CONTRAST = 3.0

    fun clamp(v: Int) = v.coerceIn(0, 100)
    /** 0% → 1 (như cũ), 100% → 0. */
    fun alpha(pct: Int) = 1f - clamp(pct) / 100f

    /**
     * Thứ lộ ra sau cửa sổ IME trong suốt: cửa sổ app (nền windowBackground — thường
     * trắng / tối Material). Không đo được từ IME → ước lượng theo sáng/tối hệ thống.
     */
    fun systemBackdrop(dark: Boolean) = if (dark) ThemeColor.rgb(0x121212) else ThemeColor.rgb(0xFFFFFF)

    /**
     * Nền bàn phím có lộ cửa sổ app phía sau không (#137) — tức kết quả TUỲ APP: chỉ app vẽ nội dung dưới
     * bàn phím (trình duyệt, app adjustPan / edge-to-edge) mới thấy nội dung xuyên qua; phần lớn app co
     * lại (adjustResize) nên phía sau chỉ là nền trơn của app (trắng/đen) ⇒ bàn phím chỉ nhạt đi.
     * Ảnh nền (ảnh tự đặt hoặc ảnh nền theme) luôn đục ⇒ [keyboard] chỉ đụng phím, giống nhau ở mọi app.
     * Cài đặt dùng để hiện lời giải thích đúng lúc.
     */
    fun revealsHostApp(keyboard: Int, opaqueBackdrop: Boolean): Boolean = clamp(keyboard) > 0 && !opaqueBackdrop

    /** Giữ [ink] nếu còn đọc được trên [bg]; không thì đen/trắng (cái tương phản hơn). */
    fun readable(ink: Int, bg: Int): Int {
        val c = ThemeColor
        if (c.contrast(ink, bg) >= MIN_LABEL_CONTRAST) return ink
        val alt = if (c.contrast(c.WHITE, bg) >= c.contrast(c.BLACK, bg)) c.WHITE else c.BLACK
        return if (c.contrast(alt, bg) > c.contrast(ink, bg)) alt else ink
    }
}

fun ThemePalette.withTransparency(keyboard: Int, labels: Int, systemDark: Boolean): ThemePalette {
    val t = KeyboardTransparency
    val k = t.clamp(keyboard); val l = t.clamp(labels)
    if (k == 0 && l == 0) return this
    var p = copy(labelAlpha = t.alpha(l))
    if (k > 0) {
        val s = t.alpha(k)
        val c = ThemeColor
        fun f(x: Int) = c.withAlpha(x, s)
        p = p.copy(bg = f(bg), bgBottom = bgBottom?.let(::f), keyFill = f(keyFill), specialFill = f(specialFill),
            action = f(action), chip = f(chip), keyBorder = keyBorder?.let(::f), surfaceAlpha = s,
            functionFill = functionFill?.let(::f), decoration = decoration?.let { it.copy(color = f(it.color)) })
        // Nền thật sau chữ ≈ lớp nền mới trên cửa sổ app. Ảnh nền vẫn hiện nguyên ⇒ ước lượng
        // bằng tông lớp phủ (tối cho theme tối, sáng cho theme sáng).
        val sys = t.systemBackdrop(systemDark)
        val behind = c.over(if (wallpaper) wallpaperOverlay else p.bg, sys)
        val label = if (keyLabelPinned) ink else t.readable(ink, c.over(p.keyFill, behind))
        val fnInk = if (keyLabelPinned) functionInk else functionInk?.let { t.readable(it, c.over(p.fnFill, behind)) }
        val bar = barInk?.let { t.readable(it, behind) }
        p = p.copy(keyLabel = label, functionInk = fnInk, actionInk = t.readable(actionInk, c.over(p.action, behind)),
            isDark = if (label != ink) c.luminance(label) > 0.5 else isDark, barInk = bar,
            surfaceDark = if (bar != null) c.luminance(bar) > 0.5 else surfaceDark)
    }
    return p
}

/**
 * Nền chip thanh gợi ý (thẻ Dán "Nội dung vừa copy", chip số clipboard, pill Khôi phục / Hoàn tác) khi vẽ
 * với độ mờ [opacity] (hoạt ảnh thu gọn, nhấn): NHÂN vào alpha gốc của [ThemePalette.chip], không ghi đè.
 * Bug 19/10/2026 (Android, theme tối): StripView đặt `paint.alpha = 255` ⇒ chip bán trong (Kính tối =
 * trắng 30%, chip sau độ trong suốt phím) thành trắng ĐẶC, chữ trắng trên đó biến mất.
 */
fun ThemePalette.chipFill(opacity: Float = 1f): Int = ThemeColor.withAlpha(chip, opacity.coerceIn(0f, 1f))

/**
 * Chữ / icon trên chip thanh gợi ý: [ThemePalette.keyInk] nếu đọc được (≥ 3:1) trên chip đã trộn lên nền
 * bar; không thì đen/trắng — tuỳ chỉnh màu chữ/phím đổi chữ nhưng không đổi chip.
 */
fun ThemePalette.chipInk(systemDark: Boolean): Int {
    val c = ThemeColor
    val behind = c.over(if (wallpaper) wallpaperOverlay else bg, KeyboardTransparency.systemBackdrop(systemDark))
    return KeyboardTransparency.readable(keyInk, c.over(chipFill(), behind))
}

enum class KeyboardTheme(val id: String, val viTitle: String, val isPlus: Boolean) {
    SYSTEM("system", "Hệ thống", false),
    OLED("oled", "Tối OLED", false),
    /** Trợ năng → luôn miễn phí. */
    CONTRAST("contrast", "Tương phản cao", false),
    PEACH("peach", "Hồng đào", true),
    MINT("mint", "Bạc hà", true),
    SKY("sky", "Trời xanh", true),
    LAVENDER("lavender", "Oải hương", true),
    GLASS("glass", "Kính", true),
    // Bộ 10/2026 (gợi ý từ các theme cộng đồng được thích nhất — thiết kế riêng, không dùng tài sản
    // của ai, không nhân vật có thương hiệu). id = giá trị lưu, trùng rawValue iOS.
    BLACK_HEART("blackHeart", "Tim đen", true),
    GREEN_FLORAL("greenFloral", "Hoa xanh", true),
    SAGE("sage", "Xanh lá", true),
    // "Trắng hồng" (pureWhite, 1.5.12) đã bỏ 10/2026: chỉ là Hệ thống + màu nhấn hồng ⇒ chuyển sang
    // Hệ thống + Màu nhấn D6336C ([KeyStyleStore.migrate]). Id lạ / đã bỏ luôn về Hệ thống ([of]).
    NEON("neon", "Neon", true),
    PINK("pink", "Hồng", true),
    // Lễ / mùa (10/2026, hình vẽ vector tự thiết kế) — id trùng iOS.
    TET("tet", "Tết", true), // l10n-key
    TET_MAI("tetMai", "Tết mai vàng", true), // l10n-key
    XMAS("xmas", "Giáng sinh", true), // l10n-key
    XMAS_SNOW("xmasSnow", "Giáng sinh tuyết", true), // l10n-key
    PIANO("piano", "Piano", true), // l10n-key
    // Sen Việt (19/10/2026): hồng sen + xanh lá sen, motif hoa sen, âm đàn tranh — id trùng iOS.
    SEN("sen", "Sen Việt", true), // l10n-key
    // Bộ đủ món 10/2026 (màu + trang trí + hiệu ứng + âm) — id trùng iOS.
    TYPEWRITER("typewriter", "Máy chữ cổ", true), // l10n-key
    RGB("rgb", "Gaming RGB", true), // l10n-key
    SPACE("space", "Vũ trụ", true), // l10n-key
    // Bộ đủ món 10/2026 (màu + hoạ tiết + hiệu ứng + âm) — id trùng iOS.
    TRUNG_THU("trungthu", "Trung Thu", true), // l10n-key
    VALENTINE("valentine", "Valentine", true), // l10n-key
    HALLOWEEN("halloween", "Halloween", true), // l10n-key
    // Bộ đủ món 10/2026: Ghi-ta (mặt đàn gỗ mật ong, phím gỗ hồng sắc, dây đàn + khảm, lỗ thoát âm trên phím cách,
    // âm ghi-ta mộc + hiệu ứng rung dây) — id trùng iOS.
    GUITAR("guitar", "Ghi-ta", true), // l10n-key
    // Trò chơi khi gõ 10/2026: Đập chuột (bãi cỏ + phím hang đất; "game":"mole" — [MoleGame]). Id trùng iOS.
    MOLE("mole", "Đập chuột", true), // l10n-key
    // Xám trung tính (issue #137, 30/10/2026): miễn phí, kiểu Gboard xám — cho người không thích tím Material You của
    // Hệ thống. Theo sáng/tối hệ thống. Id trùng iOS; THÊM CUỐI (id lưu, không đổi thứ tự).
    NEUTRAL("neutral", "Xám trung tính", false); // l10n-key

    /** Bo góc mặc định (% như [KeyStyle.corner]) khi người dùng chưa chỉnh — null = bo stock. iOS cùng giá trị. */
    val defaultCorner: Int? get() = spec?.corner

    /** Tên hiển thị theo ngôn ngữ giao diện ([L10n]); [viTitle] = khoá dịch. */
    val title: String get() = tr(viTitle)

    /**
     * Palette cố định của theme; SYSTEM trả null (IME dùng màu Material You trong
     * resources như trước — không đổi hình người dùng cũ).
     */
    fun palette(systemDark: Boolean): ThemePalette? {
        val c = ThemeColor
        return when (this) {
            SYSTEM -> null
            // Android không có backdrop mờ sau cửa sổ IME → giả lập: gradient dịu +
            // phím trắng bán trong + viền sáng mảnh.
            GLASS -> if (systemDark) ThemePalette(bg = c.rgb(0x2B3040), bgBottom = c.rgb(0x16181F),
                keyFill = c.withAlpha(c.WHITE, 0.16f), specialFill = c.withAlpha(c.WHITE, 0.08f),
                ink = c.WHITE, trail = c.withAlpha(c.WHITE, 0.6f), balloon = c.rgb(0x4A4A4E),
                popup = c.rgb(0x3A3D48), action = c.rgb(0xA8C7FA), actionInk = c.rgb(0x062E6F),
                chip = c.withAlpha(c.WHITE, 0.3f), keyBorder = c.withAlpha(c.WHITE, 0.18f), isDark = true)
            else ThemePalette(bg = c.rgb(0xDCE6F2), bgBottom = c.rgb(0xC5D0DE),
                keyFill = c.withAlpha(c.WHITE, 0.55f), specialFill = c.withAlpha(c.WHITE, 0.3f),
                ink = c.rgb(0x1F1F1F), trail = c.withAlpha(c.rgb(0x0B57D0), 0.6f), balloon = c.WHITE,
                popup = c.WHITE, action = c.rgb(0x0B57D0), actionInk = c.WHITE,
                chip = c.withAlpha(c.WHITE, 0.8f), keyBorder = c.withAlpha(c.WHITE, 0.6f), isDark = false)
            // Theme có sẵn khác: dữ liệu JSON (themes/builtin-themes.json → BuiltinThemes, đọc MỘT lần).
            // Thiếu (không xảy ra — test khoá) ⇒ null ⇒ IME vẽ như Hệ thống, không crash.
            else -> spec?.palette(systemDark)
        }
    }

    /** Đặc tả JSON của theme có sẵn (null = Hệ thống / Kính — vẽ theo nền tảng). */
    val spec: ThemeSpec? get() = BuiltinThemes.specs[id]

    companion object {
        fun of(id: String?): KeyboardTheme = entries.firstOrNull { it.id == id } ?: SYSTEM
    }
}

/**
 * Hoạ tiết nền theme (Tim đen: tim; Hoa xanh: hoa) — MỘT Path vẽ trong Drawable nền IME (display
 * list ghi một lần, dựng lại khi cỡ / hàng phím đổi). 0 chi phí mỗi phím, không ảnh. Motif CHỈ nằm
 * trong khe GIỮA các hàng phím (không ở thanh gợi ý, không dưới nhãn phím). Hình học y hệt iOS
 * (KeyboardDecoration trong iOS/Keyboard/KeyboardTheme.swift), đơn vị dp.
 */
/** [density] % ("Giao diện JSON" deco.density, 50…200): bước ngang = STEP_X × 100 / density. */
data class ThemeDecoration(val motif: String, val color: Int, val density: Int = 100,
                           /** Motif thứ hai xen kẽ (deco.alt; motif lẻ dùng alt) — iOS KeyboardDecoration.alt. */
                           val alt: String? = null) {
    data class Gap(val center: Double, val height: Double)
    data class Placement(val x: Double, val y: Double, val size: Double)

    /** Motif của vị trí thứ [k] (theo thứ tự [placements]). */
    fun motifAt(k: Int): String = if (k % 2 == 1) alt ?: motif else motif

    /** Có dây đàn (motif chính hoặc alt = strings) ⇒ path thêm mỗi khe một dây ngang. */
    val hasStrings: Boolean get() = motif == STRINGS || alt == STRINGS

    /** Một dây đàn: hình chữ nhật mảnh [x0, x1] × [y − h/2, y + h/2]. */
    data class StringLine(val x0: Double, val x1: Double, val y: Double, val h: Double)

    companion object {
        const val HEARTS = "hearts"
        const val FLOWERS = "flowers"
        const val MAI = "mai"
        const val DAO = "dao"
        const val SNOWFLAKE = "snowflake"
        const val STAR = "star"
        const val NOTES = "notes"
        const val LOTUS = "lotus"
        const val STARFIELD = "starfield"
        /** Danh sách trắng motif (theme JSON chỉ nhận các id này) — iOS KeyboardDecoration.Motif y hệt. */
        // Trung Thu / Halloween (10/2026, vector tự vẽ).
        const val LANTERN = "lantern"
        const val MOON = "moon"
        const val PUMPKIN = "pumpkin"
        const val BAT = "bat"
        // Ghi-ta (10/2026): dây đàn kéo NGANG HẾT khe hàng (một lần mỗi khe, dày dần ở khe dưới) + chấm khảm xà cừ.
        const val STRINGS = "strings"
        const val INLAY = "inlay"
        /** Danh sách trắng motif (theme JSON chỉ nhận các id này) — iOS KeyboardDecoration.Motif y hệt. */
        val MOTIFS = listOf(HEARTS, FLOWERS, MAI, DAO, SNOWFLAKE, STAR, NOTES,
            LOTUS, STARFIELD, LANTERN, MOON, PUMPKIN, BAT, STRINGS, INLAY)

        /** Độ dày dây ở khe thứ [i] (0 = khe trên cùng; dp) — dây dưới dày hơn như dây trầm. iOS y hệt. */
        fun stringThickness(i: Int): Double = minOf(0.6 + 0.3 * i, 1.5)
        /** Lề hai đầu dây (dp). */
        const val STRING_INSET = 6.0

        /**
         * Dây đàn: mỗi khe có motif (tâm y khác nhau của [placements]) một hình chữ nhật mảnh từ [STRING_INSET] tới
         * [width] − [STRING_INSET] (null ⇒ motif xa nhất + [INSET]). iOS KeyboardDecoration.strings y hệt.
         */
        fun strings(placements: List<Placement>, width: Double?): List<StringLine> {
            val ys = placements.map { it.y }.distinct().sorted()
            if (ys.isEmpty()) return emptyList()
            val right = width ?: ((placements.maxOfOrNull { it.x + it.size / 2 } ?: 0.0) + INSET)
            val x0 = STRING_INSET; val x1 = right - STRING_INSET
            if (x1 <= x0) return emptyList()
            return ys.mapIndexed { i, y -> StringLine(x0, x1, y, stringThickness(i)) }
        }

        /** Chấm sao nhỏ của motif "starfield": (x, y, bán kính) theo đơn vị motif — iOS starDots y hệt. */
        val STAR_DOTS = arrayOf(doubleArrayOf(-2.6, -0.3, 0.1), doubleArrayOf(-1.4, 0.34, 0.07), doubleArrayOf(1.5, -0.24, 0.08),
            doubleArrayOf(2.7, 0.3, 0.11), doubleArrayOf(0.8, 0.4, 0.05))
        const val STEP_X = 64.0
        const val MOTIF_SIZE = 8.0
        const val INSET = 14.0
        const val MIN_MOTIF_SIZE = 5.0
        /** Cách mép phím tối thiểu (motif không chạm phím). */
        const val CLEARANCE = 1.0
        const val MAX_MOTIFS = 120

        /**
         * Khe giữa các HÀNG phím từ khung phím [top, bottom]: gộp phím cùng hàng (chồng dọc), khe = từ
         * đáy hàng trên tới đỉnh hàng dưới. Không tính phía trên hàng đầu (thanh gợi ý).
         */
        fun rowGaps(spans: List<DoubleArray>): List<Gap> {
            val rows = ArrayList<DoubleArray>()
            for (sp in spans.sortedBy { it[0] }) {
                if (sp[1] <= sp[0]) continue
                val last = rows.lastOrNull()
                if (last != null && sp[0] < last[1]) last[1] = maxOf(last[1], sp[1]) else rows.add(doubleArrayOf(sp[0], sp[1]))
            }
            return (1 until rows.size).mapNotNull { i ->
                val h = rows[i][0] - rows[i - 1][1]
                if (h > 0) Gap(rows[i - 1][1] + h / 2, h) else null
            }
        }

        /** Motif dọc từng khe (so le giữa các khe), cỡ vừa khe (chừa [CLEARANCE] mỗi bên); khe quá hẹp bỏ. */
        fun placements(w: Double, gaps: List<Gap>, density: Int = 100): List<Placement> {
            if (w <= 2 * INSET) return emptyList()
            fun layout(step: Double): List<Placement> {
                val out = ArrayList<Placement>()
                gaps.forEachIndexed { i, g ->
                    val size = minOf(MOTIF_SIZE, g.height - 2 * CLEARANCE)
                    if (size < MIN_MOTIF_SIZE) return@forEachIndexed
                    var x = INSET + size / 2 + if (i % 2 == 1) step / 2 else 0.0
                    while (x + size / 2 <= w - INSET) { out.add(Placement(x, g.center, size)); x += step }
                }
                return out
            }
            var step = STEP_X * 100 / density.coerceIn(50, 200).toDouble()   // kẹp lại: bước luôn > 0
            var pts = layout(step)
            while (pts.size > MAX_MOTIFS) { step *= 1.15; pts = layout(step) }
            return pts
        }

        /**
         * Đường tim theo đơn vị motif (tâm 0,0; y xuống): điểm đầu rồi 6 đoạn cubic
         * (c1x, c1y, c2x, c2y, x, y) — y hệt iOS.
         */
        val HEART_START = doubleArrayOf(0.0, 0.45)
        val HEART_CUBICS = arrayOf(
            doubleArrayOf(-0.35, 0.2, -0.5, 0.0, -0.5, -0.18),
            doubleArrayOf(-0.5, -0.38, -0.36, -0.5, -0.22, -0.5),
            doubleArrayOf(-0.1, -0.5, -0.03, -0.43, 0.0, -0.33),
            doubleArrayOf(0.03, -0.43, 0.1, -0.5, 0.22, -0.5),
            doubleArrayOf(0.36, -0.5, 0.5, -0.38, 0.5, -0.18),
            doubleArrayOf(0.5, 0.0, 0.35, 0.2, 0.0, 0.45),
        )

        /** Hoa: 5 cánh tròn (tâm, bán kính) không chồng nhau + nhuỵ — [cx, cy, r] theo đơn vị motif. */
        val FLOWER_CIRCLES: List<DoubleArray> = (0 until 5).map { i ->
            val a = i * 2 * Math.PI / 5 - Math.PI / 2
            doubleArrayOf(0.32 * Math.cos(a), 0.32 * Math.sin(a), 0.18)
        } + listOf(doubleArrayOf(0.0, 0.0, 0.12))

        /**
         * Hình motif dạng dữ liệu (đơn vị motif: tâm 0,0, trong ô ±0.5, y xuống) — Y HỆT iOS
         * KeyboardDecoration.shape. Mọi đường con cùng chiều quay ⇒ tô nonzero = hợp, không thủng. Tim / hoa ⇒ rỗng.
         */
        fun shape(motif: String): List<MotifSub> {
            fun pol(r: Double, a: Double) = doubleArrayOf(r * Math.cos(a), r * Math.sin(a))
            fun rect(bx: Double, by: Double, ang: Double, len: Double, w: Double): MotifSub {
                val dx = Math.cos(ang); val dy = Math.sin(ang); val nx = -dy; val ny = dx
                return MotifSub(bx - nx * w, by - ny * w, listOf(
                    doubleArrayOf(bx + dx * len - nx * w, by + dy * len - ny * w),
                    doubleArrayOf(bx + dx * len + nx * w, by + dy * len + ny * w),
                    doubleArrayOf(bx + nx * w, by + ny * w)))
            }
            fun ell(cx: Double, cy: Double, rx: Double, ry: Double): MotifSub {
                val k = 0.5523
                return MotifSub(cx + rx, cy, listOf(
                    doubleArrayOf(cx + rx, cy + k * ry, cx + k * rx, cy + ry, cx, cy + ry),
                    doubleArrayOf(cx - k * rx, cy + ry, cx - rx, cy + k * ry, cx - rx, cy),
                    doubleArrayOf(cx - rx, cy - k * ry, cx - k * rx, cy - ry, cx, cy - ry),
                    doubleArrayOf(cx + k * rx, cy - ry, cx + rx, cy - k * ry, cx + rx, cy)))
            }
            fun poly(vararg q: DoubleArray) = MotifSub(q[0][0], q[0][1], q.drop(1))
            fun d(vararg v: Double) = v
            return when (motif) {
                MAI -> (0 until 5).map { i ->
                    val a = i * 2 * Math.PI / 5 - Math.PI / 2
                    MotifSub(0.0, 0.0, listOf(pol(0.74, a - 0.6) + pol(0.74, a + 0.6) + doubleArrayOf(0.0, 0.0)))
                }
                DAO -> (0 until 5).map { i ->
                    val a = i * 2 * Math.PI / 5 - Math.PI / 2
                    MotifSub(0.0, 0.0, listOf(pol(0.5, a - 0.62) + pol(0.58, a - 0.28) + pol(0.4, a),
                        pol(0.58, a + 0.28) + pol(0.5, a + 0.62) + doubleArrayOf(0.0, 0.0)))
                }
                SNOWFLAKE -> (0 until 6).flatMap { i ->
                    val a = i * Math.PI / 3 - Math.PI / 2
                    val b = pol(0.27, a)
                    listOf(rect(0.0, 0.0, a, 0.48, 0.055)) +
                        listOf(-1.0, 1.0).map { sg -> rect(b[0], b[1], a + sg * Math.PI / 3, 0.17, 0.045) }
                }
                STAR -> {
                    val pts = (0 until 10).map { k -> pol(if (k % 2 == 0) 0.5 else 0.21, k * Math.PI / 5 - Math.PI / 2) }
                    listOf(MotifSub(pts[0][0], pts[0][1], pts.drop(1)))
                }
                STARFIELD -> {
                    // Vũ trụ: sao lấp lánh 4 cánh + vài chấm sao nhỏ trải ngang trong khe (dọc ±0.45 — không chạm phím).
                    val pts = (0 until 8).map { k -> pol(if (k % 2 == 0) 0.5 else 0.13, k * Math.PI / 4 - Math.PI / 2) }
                    listOf(MotifSub(pts[0][0], pts[0][1], pts.drop(1))) + STAR_DOTS.map { d ->
                        MotifSub(d[0] + d[2], d[1], listOf(doubleArrayOf(d[0], d[1] + d[2]), doubleArrayOf(d[0] - d[2], d[1]),
                            doubleArrayOf(d[0], d[1] - d[2])))
                    }
                }
                NOTES -> {
                    val k = 0.5523; val cx = -0.14; val cy = 0.3; val rx = 0.19; val ry = 0.14
                    listOf(
                        MotifSub(cx + rx, cy, listOf(
                            doubleArrayOf(cx + rx, cy + k * ry, cx + k * rx, cy + ry, cx, cy + ry),
                            doubleArrayOf(cx - k * rx, cy + ry, cx - rx, cy + k * ry, cx - rx, cy),
                            doubleArrayOf(cx - rx, cy - k * ry, cx - k * rx, cy - ry, cx, cy - ry),
                            doubleArrayOf(cx + k * rx, cy - ry, cx + rx, cy - k * ry, cx + rx, cy))),
                        MotifSub(0.01, 0.3, listOf(doubleArrayOf(0.01, -0.48), doubleArrayOf(0.07, -0.48), doubleArrayOf(0.07, 0.3))),
                        MotifSub(0.07, -0.48, listOf(doubleArrayOf(0.1, -0.3, 0.38, -0.3, 0.3, -0.02),
                            doubleArrayOf(0.3, -0.2, 0.18, -0.26, 0.07, -0.28))))
                }
                LOTUS -> {
                    // Hoa sen (tự vẽ): 5 cánh nhọn toả từ gốc + đài / mặt nước hình thấu kính — y hệt iOS.
                    val by = 0.28; val up = -Math.PI / 2
                    fun petal(a: Double, r: Double, d: Double) = MotifSub(0.0, by, listOf(doubleArrayOf(
                        r * Math.cos(a - d), by + r * Math.sin(a - d), r * Math.cos(a + d), by + r * Math.sin(a + d), 0.0, by)))
                    listOf(petal(up, 0.95, 0.3), petal(up - 0.5, 0.8, 0.3), petal(up + 0.5, 0.8, 0.3),
                        petal(up - 1.1, 0.6, 0.32), petal(up + 1.1, 0.6, 0.32),
                        MotifSub(-0.38, by, listOf(doubleArrayOf(-0.15, by - 0.1, 0.15, by - 0.1, 0.38, by),
                            doubleArrayOf(0.15, by + 0.16, -0.15, by + 0.16, -0.38, by))))
                }
                LANTERN -> listOf(
                    poly(d(-0.015, -0.5), d(0.015, -0.5), d(0.015, -0.36), d(-0.015, -0.36)),
                    poly(d(-0.13, -0.38), d(0.13, -0.38), d(0.13, -0.27), d(-0.13, -0.27)),
                    ell(0.0, 0.0, 0.37, 0.3),
                    poly(d(-0.13, 0.26), d(0.13, 0.26), d(0.13, 0.36), d(-0.13, 0.36)),
                    poly(d(-0.03, 0.35), d(0.03, 0.35), d(0.07, 0.5), d(-0.07, 0.5)))
                MOON -> {
                    val rr = 0.44; val r = 0.37; val cx = 0.17; val cy = -0.12
                    val dd = Math.sqrt(cx * cx + cy * cy); val dir = Math.atan2(cy, cx)
                    val a = (rr * rr - r * r + dd * dd) / (2 * dd)
                    val al = Math.acos(a / rr); val ga = Math.acos((dd - a) / r)
                    val q = ArrayList<DoubleArray>()
                    for (i in 0..24) q.add(pol(rr, dir + al + i / 24.0 * (2 * Math.PI - 2 * al)))
                    for (i in 1 until 16) {
                        val t = dir + Math.PI + ga - i / 16.0 * 2 * ga
                        q.add(doubleArrayOf(cx + r * Math.cos(t), cy + r * Math.sin(t)))
                    }
                    listOf(MotifSub(q[0][0], q[0][1], q.drop(1)))
                }
                PUMPKIN -> listOf(
                    ell(-0.2, 0.07, 0.22, 0.29), ell(0.2, 0.07, 0.22, 0.29), ell(0.0, 0.05, 0.23, 0.33),
                    poly(d(-0.01, -0.45), d(0.07, -0.42), d(0.04, -0.24), d(-0.04, -0.24)),
                    MotifSub(0.03, -0.31, listOf(d(0.1, -0.45, 0.24, -0.44, 0.29, -0.36), d(0.21, -0.35, 0.11, -0.31, 0.03, -0.31))))
                BAT -> listOf(
                    ell(0.0, 0.04, 0.11, 0.17), ell(0.0, -0.14, 0.1, 0.1),
                    poly(d(-0.09, -0.18), d(-0.08, -0.3), d(-0.02, -0.22)),
                    poly(d(0.02, -0.22), d(0.08, -0.3), d(0.09, -0.18)),
                    MotifSub(0.06, -0.08, listOf(d(0.18, -0.22, 0.36, -0.24, 0.48, -0.12), d(0.44, -0.04, 0.4, -0.04, 0.36, 0.02),
                        d(0.32, -0.04, 0.26, -0.02, 0.22, 0.06), d(0.18, 0.0, 0.12, 0.02, 0.08, 0.1))),
                    MotifSub(-0.08, 0.1, listOf(d(-0.12, 0.02, -0.18, 0.0, -0.22, 0.06), d(-0.26, -0.02, -0.32, -0.04, -0.36, 0.02),
                        d(-0.4, -0.04, -0.44, -0.04, -0.48, -0.12), d(-0.36, -0.24, -0.18, -0.22, -0.06, -0.08))))
                INLAY -> listOf(ell(0.0, 0.0, 0.22, 0.22))   // chấm khảm xà cừ tròn nhỏ
                else -> emptyList()
            }
        }
    }
}

/**
 * Lỗ thoát âm trên phím cách (theme Ghi-ta, "spaceDeco":"soundhole") — hình học thuần, iOS Soundhole y hệt. Tâm =
 * tâm phím; R = min(0.34 × cao, 0.18 × rộng); hai vành hoa văn đồng tâm vẽ nét (bán kính, độ dày theo bội R).
 */
object Soundhole {
    const val HOLE_RATIO = 0.34
    const val MAX_WIDTH_RATIO = 0.18
    const val HOLE_ALPHA = 0.55
    /** (bán kính / R, độ dày nét / R): vành ngoài (màu nhấn) rồi vành trong (màu chữ mờ). */
    val RINGS = listOf(doubleArrayOf(1.28, 0.12), doubleArrayOf(1.13, 0.06))
    fun radius(w: Double, h: Double): Double = maxOf(0.0, minOf(HOLE_RATIO * h, MAX_WIDTH_RATIO * w))
    fun outerExtent(w: Double, h: Double): Double {
        val r = radius(w, h)
        return RINGS.maxOf { (it[0] + it[1] / 2) * r }
    }
}

/** Một đường con khép kín của motif: điểm đầu + các đoạn ([x, y] thẳng / [c1x, c1y, c2x, c2y, x, y] cubic). */
class MotifSub(val sx: Double, val sy: Double, val segs: List<DoubleArray>)

/**
 * Danh sách trắng id "sound" / "effect" của theme JSON = đúng danh sách kiểu âm dựng sẵn / hiệu ứng của app
 * ([KeySoundStyle.PRESET_IDS], [KeyEffect]) — iOS ThemeExtraIds y hệt (fixture chung chốt).
 */
object ThemeExtraIds {
    val SOUNDS: Set<String> get() = KeySoundStyle.PRESET_IDS.toSet()
    val EFFECTS: Set<String> get() = KeyEffect.entries.map { it.id }.toSet()
    /** "swipe": kiểu nét vuốt cụ thể (không có "theme" — theme không trỏ về chính nó). */
    val SWIPES: Set<String> get() = SwipeTrailStyle.THEME_IDS.toSet()
    /** "game": trò chơi khi gõ (iOS ThemeExtraIds.games y hệt). */
    val GAMES: Set<String> = setOf(MoleGame.THEME_GAME)
}

/**
 * "sound" / "effect" đi kèm theme: áp MỘT lần ĐÚNG LÚC người dùng chọn theme (chạm thẻ "Chọn giao diện", dán rồi áp
 * theme tự tạo). Đổi tay sau đó thì giữ tới lần chọn theme kế; theme không khai báo ⇒ không đổi gì. KHÔNG BAO GIỜ
 * bật âm thanh phím: tắt thì chỉ lưu kiểu âm + [Outcome.soundHint] để app gợi ý "Bật". Id máy chưa có / bị khoá
 * Plus ⇒ bỏ qua. iOS ThemeExtras y hệt.
 */
object ThemeExtras {
    data class Outcome(val effect: String?, val sound: String?, val soundHint: Boolean)

    /** Logic thuần: [st] = kiểu thực dùng của theme vừa chọn ([ThemeSettings.effectiveKeyStyle]). */
    fun plan(st: KeyStyle, soundOn: Boolean, effectAllowed: (String) -> Boolean, soundAllowed: (String) -> Boolean): Outcome {
        val e = st.effect?.takeIf(effectAllowed)
        val snd = st.sound?.takeIf(soundAllowed)
        return Outcome(e, snd, snd != null && !soundOn)
    }

    /** Hiệu ứng có trên máy + được phép (Plus) — id chưa có ⇒ bỏ qua. */
    fun effectAllowed(id: String): Boolean = KeyEffect.entries.firstOrNull { it.id == id }?.let(KeyEffectGate::allows) ?: false
    /** Kiểu âm dựng sẵn (kiểu âm không thuộc Plus — trang Âm thanh gõ chọn tự do). */
    fun soundAllowed(id: String): Boolean = id in KeySoundStyle.PRESET_IDS

    /** Gọi NGAY sau khi lưu theme vừa chọn — đọc/ghi qua hai hàm (SharedPreferences ở app). */
    fun applyOnSelect(st: KeyStyle, soundOn: Boolean, write: (key: String, value: String) -> Unit): Outcome {
        val r = plan(st, soundOn, ::effectAllowed, ::soundAllowed)
        r.effect?.let { write(Keys.KEY_EFFECT, it) }
        r.sound?.let { write(Keys.KEY_SOUND_STYLE, it) }
        return r
    }

    const val HINT = "Giao diện này có âm thanh riêng — bật Âm thanh phím để nghe." // l10n-key
}

/**
 * Màu Hệ thống (Android): Material You (values-v31 / values-night-v31, theo hình nền) hay bảng tĩnh xám + nhấn xanh
 * (values/ + values-night/ ime_colors.xml — [static] y hệt, test khoá). Công tắc "Dùng màu hình nền (Material You)"
 * chỉ có nghĩa từ Android 12 (API 31); máy cũ vốn đã dùng bảng tĩnh.
 */
object SystemColors {
    const val DYNAMIC_MIN_SDK = 31

    /** Máy có màu động (Material You) ⇒ mới hiện công tắc. */
    fun dynamicAvailable(sdk: Int) = sdk >= DYNAMIC_MIN_SDK

    /** true ⇒ IME đọc màu resource (Material You); false ⇒ dùng [static]. */
    fun useDynamic(materialYou: Boolean, sdk: Int) = materialYou && dynamicAvailable(sdk)

    /** Bảng tĩnh = values/ime_colors.xml (sáng) / values-night/ime_colors.xml (tối). */
    fun static(dark: Boolean): ThemePalette = if (dark)
        ThemePalette(bg = 0xFF1F1F1F.toInt(), keyFill = 0xFF3C3C3F.toInt(), specialFill = 0xFF2B2F36.toInt(),
            ink = 0xFFE3E3E3.toInt(), trail = 0xFFA8C7FA.toInt(), balloon = 0xFF4A4A4E.toInt(), popup = 0xFF3C3C3F.toInt(),
            action = 0xFFA8C7FA.toInt(), actionInk = 0xFF062E6F.toInt(), chip = 0xFF004A77.toInt(), isDark = true)
    else ThemePalette(bg = 0xFFEEF0F4.toInt(), keyFill = 0xFFFFFFFF.toInt(), specialFill = 0xFFD6DBE3.toInt(),
        ink = 0xFF1F1F1F.toInt(), trail = 0xFF0B57D0.toInt(), balloon = 0xFFFFFFFF.toInt(), popup = 0xFFFFFFFF.toInt(),
        action = 0xFF0B57D0.toInt(), actionInk = 0xFFFFFFFF.toInt(), chip = 0xFFD3E3FD.toInt(), isDark = false)
}

/** Trang "Chọn giao diện" (logic thuần — test JVM; iOS: ThemePicker trong KeyboardTheme.swift). */
object ThemePicker {
    data class Section(val title: String, val themes: List<KeyboardTheme>)
    /** "Miễn phí" (Hệ thống, OLED, Tương phản cao, Xám trung tính) rồi "Plus" (còn lại), giữ thứ tự khai báo. */
    val sections: List<Section> get() = listOf(
        Section("Miễn phí", KeyboardTheme.entries.filter { !it.isPlus }),
        Section("Plus", KeyboardTheme.entries.filter { it.isPlus }))
    /** Chạm thẻ: chọn ngay nếu được phép; theme Plus bị khoá ⇒ null (IME/app không đổi gì). */
    fun select(t: KeyboardTheme, s: ThemeSettings): ThemeSettings? =
        if (ThemeGate.allows(t)) s.copy(theme = t, custom = null) else null
    /** Chạm thẻ theme tự tạo: cần Plus ⇒ không có thì null (mở màn Plus). */
    fun select(custom: ThemeSpec, s: ThemeSettings): ThemeSettings? =
        if (ThemeGate.allowsCustom) s.copy(theme = KeyboardTheme.SYSTEM, custom = custom) else null
}

/**
 * Cổng Plus cho theme — dùng [PlusGate] thật: [PlusFeature.PREMIUM_THEMES] gồm theme
 * cao cấp + ảnh nền. Hệ thống/OLED/tương phản cao/xám trung tính luôn miễn phí.
 */
object ThemeGate {
    fun allows(t: KeyboardTheme) = !t.isPlus || PlusGate.isUnlocked(PlusFeature.PREMIUM_THEMES)
    val allowsWallpaper: Boolean get() = PlusGate.isUnlocked(PlusFeature.PREMIUM_THEMES)
    /** "Tuỳ chỉnh nâng cao" đi cùng quyền theme cao cấp (Plus). */
    val allowsAdvanced: Boolean get() = PlusGate.isUnlocked(PlusFeature.PREMIUM_THEMES)
    /** Theme tự tạo / dán / sửa JSON (Plus). "Chép JSON" luôn miễn phí. */
    val allowsCustom: Boolean get() = PlusGate.isUnlocked(PlusFeature.PREMIUM_THEMES)
}

/** Cài đặt giao diện — app ghi, IME đọc mỗi lần dựng input view. */
data class ThemeSettings(
    val theme: KeyboardTheme = KeyboardTheme.SYSTEM,
    val wallpaper: Boolean = false,
    /** % lớp phủ 0…80. */
    val dim: Int = 30,
    /** Bán kính mờ 0…20 — app áp lúc lưu ảnh, IME chỉ hiện. */
    val blur: Int = 0,
    /** Đổi mỗi lần lưu ảnh → IME bỏ bitmap cũ. */
    val version: Long = 0,
    /** Độ trong suốt phím / ký tự 0…100 (miễn phí, mọi theme). */
    val keyboardTransparency: Int = 0,
    val labelTransparency: Int = 0,
    /**
     * Khung cắt đã chỉnh (null = ảnh cũ / chưa chỉnh → cắt giữa). Thuộc về ẢNH (như file) nên
     * "Khôi phục giao diện gốc" giữ nguyên.
     */
    val crop: WallpaperCrop? = null,
    /**
     * "Tuỳ chỉnh nâng cao" (Plus) RIÊNG từng theme: id theme → [KeyStyle] (= bản vá "Giao diện JSON");
     * theme chưa chỉnh không có mục. Lưu nguyên kể cả khi hết quyền; áp qua [effectiveKeyStyle].
     */
    val keyStyles: Map<String, KeyStyle> = emptyMap(),
    /**
     * Theme tự tạo ĐANG CHỌN ("Giao diện JSON", Plus) — có thì thay [theme] (khi đó [theme] = SYSTEM làm dự
     * phòng). IME chỉ đọc theme này ([CustomThemeStore.ACTIVE_KEY]), không đọc cả kho.
     */
    val custom: ThemeSpec? = null,
    /**
     * Hệ thống: "Dùng màu hình nền (Material You)" (Android 12+, mặc định bật = như cũ). Tắt ⇒ bảng tĩnh
     * [SystemColors.static] (xám, nhấn xanh) thay màu theo hình nền ([basePalette] với sdk).
     */
    val materialYou: Boolean = true,
) {
    /** Id theme đang chọn (có sẵn hoặc tự tạo) — khoá của [keyStyles]. */
    val themeId: String get() = custom?.id ?: theme.id
    /** Tuỳ chỉnh của theme ĐANG CHỌN (màn Giao diện đọc qua đây; ghi bằng [withKeyStyle]). */
    val keyStyle: KeyStyle get() = keyStyles[themeId] ?: KeyStyle.DEFAULT
    fun styleFor(t: KeyboardTheme): KeyStyle = keyStyles[t.id] ?: KeyStyle.DEFAULT
    /** Đặt tuỳ chỉnh cho theme đang chọn; mặc định ⇒ xoá mục ("Đặt lại về mặc định của giao diện"). */
    fun withKeyStyle(st: KeyStyle): ThemeSettings = withKeyStyle(st, themeId)
    fun withKeyStyle(st: KeyStyle, t: KeyboardTheme): ThemeSettings = withKeyStyle(st, t.id)
    fun withKeyStyle(st: KeyStyle, id: String): ThemeSettings =
        copy(keyStyles = if (st.isDefault) keyStyles - id else keyStyles + (id to st))

    /**
     * "Khôi phục giao diện gốc": mọi chỉnh ở màn Giao diện về mặc định. Ảnh nền chỉ bỏ
     * chọn (file giữ để bật lại); version giữ nguyên (không vứt bitmap cache vô cớ).
     */
    fun resetToDefaults() = ThemeSettings(version = version, crop = crop)
    val isDefault: Boolean get() = this == resetToDefaults()

    val effectiveTheme: KeyboardTheme get() = if (ThemeGate.allows(theme)) theme else KeyboardTheme.SYSTEM
    /** Theme tự tạo thực dùng: hết Plus ⇒ null (vẽ Hệ thống; dữ liệu giữ để mua lại là có lại). */
    val effectiveCustom: ThemeSpec? get() = if (ThemeGate.allowsCustom) custom else null
    fun wallpaperActive(fileExists: Boolean) = wallpaper && fileExists && ThemeGate.allowsWallpaper
    /** Tuỳ chỉnh nâng cao thực dùng: hết quyền Plus ⇒ mặc định (giá trị lưu giữ nguyên). */
    val effectiveKeyStyle: KeyStyle get() = effectiveCustom?.let { effectiveStyleFor(it.id ?: "", it.typography) }
        ?: effectiveStyleFor(effectiveTheme)
    /** Như [effectiveKeyStyle] cho theme [t] bất kỳ (thẻ "Chọn giao diện" xem trước tuỳ chỉnh riêng). */
    fun effectiveStyleFor(t: KeyboardTheme): KeyStyle = effectiveStyleFor(t.id, t.spec?.typography)
    fun effectiveStyleFor(id: String, typography: KeyStyle?): KeyStyle {
        var s = if (ThemeGate.allowsAdvanced) keyStyles[id] ?: KeyStyle.DEFAULT else KeyStyle.DEFAULT
        if (typography != null) {
            // Phông người dùng chọn (hệ thống hoặc tải về) thắng phông của theme — iOS effectiveStyle y hệt.
            val userSystemFont = s.font != KeyLabelFont.DEFAULT && s.assets.font == null
            if (s.corner == null) s = s.copy(corner = typography.corner)
            if (s.fontScale == null) s = s.copy(fontScale = typography.fontScale)
            if (s.font == KeyLabelFont.DEFAULT) s = s.copy(font = typography.font)
            if (s.weight == KeyLabelWeight.REGULAR) s = s.copy(weight = typography.weight)
            if (s.sound == null) s = s.copy(sound = typography.sound)
            if (s.effect == null) s = s.copy(effect = typography.effect)
            if (s.swipe == null) s = s.copy(swipe = typography.swipe)
            if (s.game == null) s = s.copy(game = typography.game)
            var a = s.assets.mergedOver(typography.assets)
            if (userSystemFont) a = a.copy(font = null)
            s = s.copy(assets = a)
            if (a.font != null) s = s.copy(font = KeyLabelFont.DEFAULT)
        }
        return s
    }

    /** Palette gốc thực dùng (theme tự tạo hoặc có sẵn); null = Hệ thống (màu resource — app/IME cấp). */
    fun basePalette(dark: Boolean): ThemePalette? = effectiveCustom?.palette(dark) ?: effectiveTheme.palette(dark)

    /**
     * Như [basePalette] nhưng giải luôn Hệ thống theo [materialYou] trên máy API [sdk]: null CHỈ khi Hệ thống dùng màu
     * Material You (IME/app đọc resource v31); Hệ thống tắt Material You (hoặc máy < 12) ⇒ [SystemColors.static].
     */
    fun basePalette(dark: Boolean, sdk: Int): ThemePalette? = basePalette(dark)
        ?: if (SystemColors.useDynamic(materialYou, sdk)) null else SystemColors.static(dark)

    /** Theme + tuỳ chỉnh RIÊNG của nó (vá chế độ → màu chữ/phím → màu nhấn), trước ảnh nền / độ trong suốt. */
    fun styled(t: KeyboardTheme, base: ThemePalette, dark: Boolean): ThemePalette = styled(effectiveStyleFor(t), base, dark)
    fun styledCustom(c: ThemeSpec, dark: Boolean): ThemePalette =
        styled(effectiveStyleFor(c.id ?: "", c.typography), c.palette(dark), dark)
    /** Theme ĐANG dùng (IME): [base] = [basePalette] hoặc màu resource cho Hệ thống. */
    fun styledCurrent(base: ThemePalette, dark: Boolean): ThemePalette = styled(effectiveKeyStyle, base, dark)

    /** "Chép JSON": theme thực thấy (gồm tuỳ chỉnh) dạng đặc tả đầy đủ — miễn phí. */
    fun exportSpec(t: KeyboardTheme, baseLight: ThemePalette, baseDark: ThemePalette): ThemeSpec =
        ThemeSpec.export(t.id, t.spec?.nameVi ?: t.viTitle, t.spec?.nameEn ?: if (t == KeyboardTheme.GLASS) "Glass" else "System",
            styled(t, baseLight, false), styled(t, baseDark, true), effectiveStyleFor(t))
    fun exportSpec(c: ThemeSpec): ThemeSpec = ThemeSpec.export(c.id, c.nameVi, c.nameEn, styledCustom(c, false),
        styledCustom(c, true), effectiveStyleFor(c.id ?: "", c.typography))

    fun toMap(): Map<String, Any> = mapOf(Keys.KEYBOARD_THEME to themeId, Keys.WALLPAPER_ENABLED to wallpaper,
        Keys.WALLPAPER_DIM to dim, Keys.WALLPAPER_BLUR to blur, Keys.WALLPAPER_VERSION to version,
        Keys.KEYBOARD_TRANSPARENCY to keyboardTransparency, Keys.KEY_LABEL_TRANSPARENCY to labelTransparency,
        Keys.SYSTEM_MATERIAL_YOU to materialYou,
        Keys.KEY_STYLES to KeyStyleStore.serialize(keyStyles),
        // IME chỉ đọc theme tự tạo đang chọn — bản chuẩn hoá ở khoá riêng ("" = không có).
        Keys.ACTIVE_THEME_SPEC to (custom?.canonical ?: "")) +
        (crop?.let { mapOf(Keys.WALLPAPER_CROP to it.serialize()) } ?: emptyMap())

    companion object {
        /** Palette sau tuỳ chỉnh (vá → màu chữ/phím → màu nhấn) — y hệt iOS ThemeSettings.styled. */
        fun styled(st: KeyStyle, base: ThemePalette, dark: Boolean): ThemePalette =
            st.applyAccent(st.applyColors(st.applyPatch(base, dark)))

        /**
         * Đọc + chuyển đổi trong bộ nhớ ([KeyStyleStore.migrate] — thuần; IME gọi mỗi lần dựng view).
         * App ghi bản đã chuyển một lần ([needsMigration] ⇒ lưu lại, xoá khoá cũ).
         */
        fun load(get: (String) -> Any?): ThemeSettings {
            val m = KeyStyleStore.migrate(get(Keys.KEYBOARD_THEME) as? String,
                KeyStyleStore.parse(get(Keys.KEY_STYLES) as? String), KeyStyleStore.loadLegacy(get))
            return loadWith(get, m)
        }

        /** Cần ghi bản chuyển đổi (khoá chung cũ còn / theme "Trắng hồng"). */
        fun needsMigration(get: (String) -> Any?) =
            KeyStyleStore.needsMigration(get(Keys.KEYBOARD_THEME) as? String, KeyStyleStore.hasLegacy(get))

        private fun loadWith(get: (String) -> Any?, m: KeyStyleStore.Migrated): ThemeSettings {
            // Id có sẵn ⇒ theme đó; id theme tự tạo ⇒ đọc (và kiểm lại) bản app đã chuẩn hoá; id lạ / đã bỏ /
            // dữ liệu hỏng ⇒ Hệ thống, không crash.
            val raw = m.theme
            val builtin = KeyboardTheme.entries.firstOrNull { it.id == raw }
            val custom = if (builtin == null && raw != null && KeyStyleStore.validId(raw))
                CustomThemeStore.active(get(Keys.ACTIVE_THEME_SPEC) as? String, raw) else null
            return ThemeSettings(
                theme = builtin ?: KeyboardTheme.SYSTEM,
                custom = custom,
                keyStyles = m.styles,
                wallpaper = get(Keys.WALLPAPER_ENABLED) as? Boolean ?: false,
                dim = ((get(Keys.WALLPAPER_DIM) as? Number)?.toInt() ?: 30).coerceIn(0, 80),
                blur = ((get(Keys.WALLPAPER_BLUR) as? Number)?.toInt() ?: 0).coerceIn(0, 20),
                version = (get(Keys.WALLPAPER_VERSION) as? Number)?.toLong() ?: 0,
                keyboardTransparency = KeyboardTransparency.clamp((get(Keys.KEYBOARD_TRANSPARENCY) as? Number)?.toInt() ?: 0),
                labelTransparency = KeyboardTransparency.clamp((get(Keys.KEY_LABEL_TRANSPARENCY) as? Number)?.toInt() ?: 0),
                crop = WallpaperCrop.parse(get(Keys.WALLPAPER_CROP) as? String),
                materialYou = get(Keys.SYSTEM_MATERIAL_YOU) as? Boolean ?: true,
            )
        }

        /**
         * App (khởi động): theme tự tạo đang chọn đồng bộ lại với kho (sửa / xoá qua sao lưu); mất khỏi kho
         * ⇒ về Hệ thống. Trả bản cần ghi, hoặc null nếu không đổi.
         */
        fun refreshCustom(get: (String) -> Any?): ThemeSettings? {
            val raw = get(Keys.KEYBOARD_THEME) as? String ?: return null
            if (KeyboardTheme.entries.any { it.id == raw } || raw == KeyStyleStore.REMOVED_PURE_WHITE) return null
            val s = load(get)
            val fresh = CustomThemeStore.parse(get(Keys.CUSTOM_THEMES) as? String)[raw]
            if (fresh == s.custom) return null
            return if (fresh != null) s.copy(theme = KeyboardTheme.SYSTEM, custom = fresh) else s.copy(theme = KeyboardTheme.SYSTEM, custom = null)
        }
    }
}

/** Toán ảnh nền thuần (test JVM): cỡ lưu, inSampleSize, mờ hộp 3 lượt ≈ Gauss. */
object WallpaperMath {
    const val MAX_EDGE = 1080
    const val MAX_BYTES = 400_000
    /** Bản gốc giữ để chỉnh khung về sau — cạnh dài ≤ chừng này. */
    const val SOURCE_MAX_EDGE = 2048

    /**
     * Cỡ px ảnh nướng cho IME từ bản gốc iw×ih + khung [crop] (null = cả ảnh, như cũ).
     * Mật độ điểm ảnh = đúng bản cũ (cả ảnh thu ≤[MAX_EDGE]) × zoom, kẹp cạnh dài ≤[MAX_EDGE]
     * và không phóng to ⇒ ở khung mặc định (zoom 1) IME giải ĐÚNG bằng số điểm ảnh như trước;
     * zoom vào thì nét hơn nhưng không bao giờ vượt trần cũ (file ≤1080 px).
     */
    fun bakedSize(iw: Int, ih: Int, crop: WallpaperCrop?): Pair<Int, Int> {
        if (crop == null || iw <= 0 || ih <= 0) return targetSize(iw, ih)
        val r = crop.pixelRect(iw, ih)
        val cw = r[2] - r[0]; val ch = r[3] - r[1]
        val base = minOf(1.0, MAX_EDGE.toDouble() / maxOf(iw, ih))
        val s = minOf(1.0, base * crop.zoom(iw, ih), MAX_EDGE.toDouble() / maxOf(cw, ch))
        return maxOf(1, Math.round(cw * s).toInt()) to maxOf(1, Math.round(ch * s).toInt())
    }

    /**
     * Ước lượng cỡ px vùng bàn phím dọc khi IME chưa từng đo (xem [Keys.IME_PORTRAIT_SIZE]):
     * vùng phím + strip gợi ý mở + đệm thanh điều hướng.
     */
    fun estimatePortraitPx(screenShortPx: Int, density: Float, keyAreaDp: Float, stripDp: Float, navPx: Int): Pair<Int, Int> =
        screenShortPx to Math.round((keyAreaDp + stripDp) * density + navPx)

    /** "w×h" → cặp px dương, sai ⇒ null. */
    fun parseSize(s: String?): Pair<Int, Int>? {
        val p = s?.split("x")?.mapNotNull { it.trim().toIntOrNull() } ?: return null
        return if (p.size == 2 && p[0] > 0 && p[1] > 0 && p[0] < 20000 && p[1] < 20000) p[0] to p[1] else null
    }

    /** Cỡ lưu: cạnh dài ≤ [maxEdge], giữ tỉ lệ, không phóng to. */
    fun targetSize(w: Int, h: Int, maxEdge: Int = MAX_EDGE): Pair<Int, Int> {
        val long = maxOf(w, h)
        if (long <= maxEdge) return w to h
        val s = maxEdge.toDouble() / long
        return maxOf(1, Math.round(w * s).toInt()) to maxOf(1, Math.round(h * s).toInt())
    }

    /** inSampleSize (lũy thừa 2) lớn nhất mà ảnh giải ra vẫn ≥ req ở cả hai chiều. */
    fun sampleSize(srcW: Int, srcH: Int, reqW: Int, reqH: Int): Int {
        var s = 1
        while (srcW / (s * 2) >= reqW && srcH / (s * 2) >= reqH) s *= 2
        return s
    }

    /** Cỡ cần giải để aspect-fill view vw×vh px (kẹp ≤ bản lưu). */
    fun fillSize(imgW: Int, imgH: Int, vw: Int, vh: Int): Pair<Int, Int> {
        if (vw <= 0 || vh <= 0 || imgW <= 0 || imgH <= 0) return imgW to imgH
        val s = maxOf(vw.toDouble() / imgW, vh.toDouble() / imgH).coerceAtMost(1.0)
        return maxOf(1, Math.ceil(imgW * s).toInt()) to maxOf(1, Math.ceil(imgH * s).toInt())
    }

    /**
     * Vùng ảnh THẤY ĐƯỢC khi aspect-fill (center-crop) view vw×vh: [left, top, right, bottom]
     * theo px ảnh gốc — IME chỉ giải vùng này (BitmapRegionDecoder), không giải cả ảnh.
     */
    fun visibleCrop(imgW: Int, imgH: Int, vw: Int, vh: Int): IntArray {
        if (vw <= 0 || vh <= 0 || imgW <= 0 || imgH <= 0) return intArrayOf(0, 0, imgW, imgH)
        val s = maxOf(vw.toDouble() / imgW, vh.toDouble() / imgH)
        val cw = minOf(imgW, Math.ceil(vw / s - 1e-9).toInt().coerceAtLeast(1))
        val ch = minOf(imgH, Math.ceil(vh / s - 1e-9).toInt().coerceAtLeast(1))
        val l = (imgW - cw) / 2; val t = (imgH - ch) / 2
        return intArrayOf(l, t, l + cw, t + ch)
    }

    /**
     * Kế hoạch giải của IME cho file w×h trên view vw×vh: [left, top, right, bottom, inSampleSize]
     * — chỉ vùng thấy được (cắt giữa), sample vừa phủ view. File đã nướng theo khung ⇒ vùng =
     * gần cả file ở hướng dọc, dải giữa ([WallpaperCrop.landscape]) ở hướng ngang.
     */
    fun decodePlan(w: Int, h: Int, vw: Int, vh: Int): IntArray {
        val c = visibleCrop(w, h, vw, vh)
        val (needW, needH) = fillSize(w, h, vw, vh)
        return intArrayOf(c[0], c[1], c[2], c[3], sampleSize(w, h, needW, needH))
    }

    /** Mờ hộp 3 lượt (ngang + dọc) trên ARGB — thay RenderScript đã bỏ. In-place. */
    fun blur(px: IntArray, w: Int, h: Int, radius: Int) {
        if (radius <= 0 || w <= 0 || h <= 0) return
        val tmp = IntArray(px.size)
        val r = maxOf(1, radius / 2)   // 3 lượt hộp bán kính r ≈ Gauss σ≈radius
        repeat(3) {
            boxPass(px, tmp, w, h, r, horizontal = true)
            boxPass(tmp, px, w, h, r, horizontal = false)
        }
    }

    private fun boxPass(src: IntArray, dst: IntArray, w: Int, h: Int, r: Int, horizontal: Boolean) {
        val lines = if (horizontal) h else w
        val len = if (horizontal) w else h
        val div = 2 * r + 1
        for (line in 0 until lines) {
            fun idx(i: Int): Int { val k = i.coerceIn(0, len - 1); return if (horizontal) line * w + k else k * w + line }
            var sa = 0; var sr = 0; var sg = 0; var sb = 0
            for (i in -r..r) { val c = src[idx(i)]; sa += c ushr 24; sr += (c shr 16) and 0xFF; sg += (c shr 8) and 0xFF; sb += c and 0xFF }
            for (i in 0 until len) {
                dst[idx(i)] = ((sa / div) shl 24) or ((sr / div) shl 16) or ((sg / div) shl 8) or (sb / div)
                val out = src[idx(i - r)]; val inn = src[idx(i + r + 1)]
                sa += (inn ushr 24) - (out ushr 24)
                sr += ((inn shr 16) and 0xFF) - ((out shr 16) and 0xFF)
                sg += ((inn shr 8) and 0xFF) - ((out shr 8) and 0xFF)
                sb += (inn and 0xFF) - (out and 0xFF)
            }
        }
    }
}
