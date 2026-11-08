package com.viettelex.keyboard

/**
 * Lưu "Tuỳ chỉnh nâng cao" (= bản vá "Giao diện JSON") theo theme: MỘT pref [KEY] = chuỗi JSON chuẩn —
 * y hệt iOS KeyStyleStore (iOS/Keyboard/KeyboardTheme.swift); sao lưu chuyển nguyên chuỗi:
 *   {"pink":{"accent":"#D6336C","corner":70},"system":{"dark":{"key":"#202020"},"fill":"#102030"}}
 * Trường (tuỳ chọn): label / fill / accent = "#RRGGBB" (áp cả sáng lẫn tối, chữ tự đọc được), corner
 * 0…100, fontScale 80…150, font, weight, light / dark = vá màu từng chế độ (khoá như theme JSON).
 * Theme chưa chỉnh không có mục; trống = "{}".
 */
object KeyStyleStore {
    const val KEY = Keys.KEY_STYLES
    const val EMPTY = "{}"
    /** Màu nhấn của "Trắng hồng" (đã bỏ) — người dùng theme đó chuyển sang Hệ thống + màu này. */
    const val PURE_WHITE_ACCENT = 0xD6336C
    const val REMOVED_PURE_WHITE = "pureWhite"
    /** Khoá chung CŨ (≤ 1.5.12) — chỉ để chuyển đổi; app xoá sau khi chuyển. */
    val LEGACY_KEYS = listOf(Keys.KEY_LABEL_COLOR, Keys.KEY_FILL_COLOR, Keys.KEY_CORNER_RADIUS, Keys.KEY_FONT_SCALE,
        Keys.KEY_LABEL_FONT, Keys.KEY_LABEL_WEIGHT)

    /** Id theme hợp lệ để lưu: ASCII chữ/số/_/-, ≤ 40 ký tự (iOS cùng luật). */
    fun validId(s: String): Boolean = s.isNotEmpty() && s.length <= 40 &&
        s.all { it in '0'..'9' || it in 'A'..'Z' || it in 'a'..'z' || it == '_' || it == '-' }

    /** Cả kho bản vá: tối đa ~ (50 theme tự tạo + 13 có sẵn) × vài KB. */
    private val LIMITS = StrictJson.Limits(maxBytes = 512 * 1024, maxMembers = 128)

    /**
     * Đọc CHẶT ([ThemeSpecParser.override]): mục có khoá lạ / màu sai ⇒ bỏ cả mục (theme vẽ như chưa
     * chỉnh); chuỗi hỏng ⇒ rỗng. Không bao giờ ném ra ngoài.
     */
    fun parse(raw: String?): Map<String, KeyStyle> {
        if (raw == null || raw == EMPTY) return emptyMap()
        val m = (StrictJson.parse(raw, LIMITS) as? StrictJson.Result.Ok)?.v as? SJ.Obj ?: return emptyMap()
        val out = LinkedHashMap<String, KeyStyle>()
        for ((id, v) in m.m) {
            if (!validId(id)) continue
            val st = ThemeSpecParser.override(v) ?: continue
            if (!st.isDefault) out[id] = st
        }
        return out
    }

    fun json(st: KeyStyle): SJ {
        val f = ArrayList<Pair<String, SJ>>()
        fun rgb(v: Int) = SJ.Str(ThemeColorCode.format((0xFF shl 24) or (v and 0xFFFFFF)))
        st.labelColor?.let { f.add("label" to rgb(it)) }
        st.fillColor?.let { f.add("fill" to rgb(it)) }
        st.accentColor?.let { f.add("accent" to rgb(it)) }
        st.corner?.let { f.add("corner" to SJ.Num(it)) }
        st.fontScale?.let { f.add("fontScale" to SJ.Num(it)) }
        val fa = st.assets.font
        if (st.font != KeyLabelFont.DEFAULT && fa == null) f.add("font" to SJ.Str(st.font.id))
        if (fa != null) f.add("font" to ThemeSpec.json(fa))
        if (st.weight != KeyLabelWeight.REGULAR) f.add("weight" to SJ.Str(st.weight.id))
        ThemeSpec.appendImages(st.assets, f)
        st.sound?.let { f.add("sound" to SJ.Str(it)) }
        st.effect?.let { f.add("effect" to SJ.Str(it)) }
        st.swipe?.let { f.add("swipe" to SJ.Str(it)) }
        st.game?.let { f.add("game" to SJ.Str(it)) }
        st.photoFx?.let { f.add("photoFx" to SJ.Str(it)) }
        if (!st.light.isEmpty) f.add("light" to ThemeSpec.json(st.light))
        if (!st.dark.isEmpty) f.add("dark" to ThemeSpec.json(st.dark))
        return SJ.Obj(f)
    }

    /** Chuỗi CHUẨN ([SJ.canonical]: khoá sắp xếp, không khoảng trắng, màu "#RRGGBB") — trùng iOS. */
    fun serialize(m: Map<String, KeyStyle>): String =
        SJ.Obj(m.filter { (id, st) -> validId(id) && !st.isDefault }.map { (id, st) -> id to json(st) }).canonical

    /** Chuẩn hoá chuỗi từ file sao lưu / đồng bộ; null = không phải object JSON (bỏ qua). */
    fun normalize(raw: String): String? =
        if ((StrictJson.parse(raw, LIMITS) as? StrictJson.Result.Ok)?.v is SJ.Obj) serialize(parse(raw)) else null
    fun hasLegacy(get: (String) -> Any?): Boolean = LEGACY_KEYS.any { get(it) != null }

    /** Bộ chung cũ; null = không có khoá cũ nào. */
    fun loadLegacy(get: (String) -> Any?): KeyStyle? = if (hasLegacy(get)) KeyStyle.loadLegacy(get) else null

    fun needsMigration(theme: String?, hasLegacy: Boolean) = hasLegacy || theme == REMOVED_PURE_WHITE

    data class Migrated(val theme: String?, val styles: Map<String, KeyStyle>)

    /**
     * Chuyển đổi THUẦN (iOS cùng quy tắc), áp lại lên kết quả của chính nó không đổi gì:
     * 1. theme "pureWhite" (đã bỏ, bản 1.5.12) ⇒ "system"; "system" chưa có màu nhấn ⇒ màu nhấn D6336C;
     * 2. bộ chung cũ (khác mặc định) ⇒ theme ĐANG CHỌN (sau bước 1; id lạ ⇒ "system"), chỉ khi theme
     *    đó chưa có mục riêng — không ghi đè thứ người dùng chỉnh sau này;
     * 3. mục "pureWhite" (nếu có) bỏ.
     */
    fun migrate(theme: String?, styles: Map<String, KeyStyle>, legacy: KeyStyle?): Migrated {
        val sys = KeyboardTheme.SYSTEM.id
        val fromPureWhite = theme == REMOVED_PURE_WHITE
        val t = if (fromPureWhite) sys else theme
        val m = LinkedHashMap(styles)
        if (legacy != null && !legacy.isDefault) {
            val id = KeyboardTheme.entries.firstOrNull { it.id == t }?.id ?: sys
            if (m[id] == null) m[id] = legacy
        }
        if (fromPureWhite) {
            val st = m[sys] ?: KeyStyle.DEFAULT
            if (st.accentColor == null) m[sys] = st.copy(accentColor = PURE_WHITE_ACCENT)
        }
        m.remove(REMOVED_PURE_WHITE)
        return Migrated(t, m)
    }
}
