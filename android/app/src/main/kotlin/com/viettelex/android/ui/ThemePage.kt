package com.viettelex.android.ui

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Slider
import androidx.compose.material3.TextButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.animation.core.animateFloat
import androidx.compose.foundation.background
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.foundation.layout.Spacer
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asComposePath
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.viettelex.keyboard.KeyboardSettings
import com.viettelex.keyboard.KeyboardTheme
import com.viettelex.keyboard.KeyboardTransparency
import com.viettelex.keyboard.KeyStyle
import com.viettelex.keyboard.KeyStyleStore
import com.viettelex.keyboard.Keys
import com.viettelex.keyboard.ThemeGate
import com.viettelex.keyboard.ThemePicker
import com.viettelex.keyboard.ThemePalette
import com.viettelex.keyboard.ThemeSettings
import com.viettelex.keyboard.WallpaperCrop
import com.viettelex.keyboard.WallpaperMath
import com.viettelex.keyboard.withTransparency
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.io.File
import com.viettelex.keyboard.tr

/**
 * Ảnh nền: app giữ bản gốc (inSampleSize + scale ≤2048px, xoay theo EXIF, chưa mờ, chưa cắt)
 * ở filesDir/wallpaper-src.jpg + khung cắt [WallpaperCrop] trong prefs; "nướng" đúng vùng cắt
 * ≤1080px, mờ (hộp 3 lượt), nén JPEG ≤400KB → filesDir/wallpaper.jpg (IME cùng process đọc,
 * chỉ giải vùng thấy được). Hai file KHÔNG vào sao lưu (backup_rules.xml).
 */
object WallpaperStore {
    fun file(ctx: Context) = File(ctx.filesDir, Keys.WALLPAPER_FILE)
    private fun src(ctx: Context) = File(ctx.filesDir, Keys.WALLPAPER_SRC_FILE)
    fun hasSource(ctx: Context) = src(ctx).exists()

    /** Ảnh từ picker → bitmap ≤ [maxEdge] (không giải bản gốc full-size). */
    fun decodeSmall(ctx: Context, uri: Uri, maxEdge: Int = WallpaperMath.SOURCE_MAX_EDGE): Bitmap? {
        val cr = ctx.contentResolver
        val b = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        cr.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, b) }
        if (b.outWidth <= 0) return null
        val (tw, th) = WallpaperMath.targetSize(b.outWidth, b.outHeight, maxEdge)
        val o = BitmapFactory.Options().apply { inSampleSize = WallpaperMath.sampleSize(b.outWidth, b.outHeight, tw, th) }
        var bmp = cr.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, o) } ?: return null
        val (sw, sh) = WallpaperMath.targetSize(bmp.width, bmp.height, maxEdge)
        if (sw != bmp.width) bmp = Bitmap.createScaledBitmap(bmp, sw, sh, true)
        val rot = runCatching {
            when (cr.openInputStream(uri)?.use {
                ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
            }) {
                ExifInterface.ORIENTATION_ROTATE_90 -> 90
                ExifInterface.ORIENTATION_ROTATE_180 -> 180
                ExifInterface.ORIENTATION_ROTATE_270 -> 270
                else -> 0
            }
        }.getOrDefault(0)
        if (rot != 0) bmp = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, Matrix().apply { postRotate(rot.toFloat()) }, true)
        return bmp
    }

    fun encode(bmp: Bitmap): ByteArray {
        var q = 80
        while (true) {
            val out = ByteArrayOutputStream()
            bmp.compress(Bitmap.CompressFormat.JPEG, q, out)
            if (out.size() <= WallpaperMath.MAX_BYTES || q <= 40) return out.toByteArray()
            q -= 10
        }
    }

    fun blurred(bmp: Bitmap, radius: Int): Bitmap {
        if (radius <= 0) return bmp
        val px = IntArray(bmp.width * bmp.height)
        bmp.getPixels(px, 0, bmp.width, 0, 0, bmp.width, bmp.height)
        WallpaperMath.blur(px, bmp.width, bmp.height, radius)
        return Bitmap.createBitmap(px, bmp.width, bmp.height, Bitmap.Config.ARGB_8888)
    }

    /** Bản gốc đã lưu (≤2048; ảnh chọn trước bản có trình chỉnh ≤1080). */
    fun loadSource(ctx: Context): Bitmap? =
        src(ctx).takeIf { it.exists() }?.let { BitmapFactory.decodeFile(it.path) }

    /**
     * Ảnh cho IME: cắt vùng [crop] (null = cả ảnh — ảnh cũ chưa có khung, IME tự cắt giữa như
     * trước), thu ≤1080, mờ. Luôn là bitmap MỚI.
     */
    fun render(source: Bitmap, crop: WallpaperCrop?, blur: Int): Bitmap {
        val r = crop?.pixelRect(source.width, source.height) ?: intArrayOf(0, 0, source.width, source.height)
        val cw = r[2] - r[0]; val ch = r[3] - r[1]
        val (tw, th) = WallpaperMath.bakedSize(source.width, source.height, crop)
        val m = Matrix().apply { setScale(tw.toFloat() / cw, th.toFloat() / ch) }
        var cut = Bitmap.createBitmap(source, r[0], r[1], cw, ch, m, true)
        if (cut === source) cut = source.copy(Bitmap.Config.ARGB_8888, false)
        return blurred(cut, blur)
    }

    /** "Xong" ở trình chỉnh: lưu bản gốc (nếu mới chọn) + nướng vùng cắt cho IME. */
    fun save(ctx: Context, source: Bitmap, isNew: Boolean, crop: WallpaperCrop?, blur: Int): Boolean {
        val out = encode(render(source, crop, blur))
        if (isNew) src(ctx).writeBytes(encodeSource(source))
        file(ctx).writeBytes(out)
        return true
    }

    fun encodeSource(bmp: Bitmap): ByteArray =
        ByteArrayOutputStream().also { bmp.compress(Bitmap.CompressFormat.JPEG, 88, it) }.toByteArray()

    fun reblur(ctx: Context, blur: Int, crop: WallpaperCrop?): Boolean {
        val bmp = loadSource(ctx) ?: return false
        file(ctx).writeBytes(encode(render(bmp, crop, blur)))
        return true
    }

    fun remove(ctx: Context) { file(ctx).delete(); src(ctx).delete() }

    fun preview(ctx: Context): ImageBitmap? {
        val f = file(ctx).takeIf { it.exists() } ?: return null
        val o = BitmapFactory.Options().apply { inSampleSize = 2 }
        return BitmapFactory.decodeFile(f.path, o)?.asImageBitmap()
    }
}

internal fun loadThemeSettings(ctx: Context): ThemeSettings {
    val all = Prefs.of(ctx).all
    return ThemeSettings.load { all[it] }
}

/**
 * Chuyển đổi đã lưu MỘT lần (MainActivity.onCreate): khoá "Tuỳ chỉnh nâng cao" chung cũ → theme đang
 * chọn, "Trắng hồng" → Hệ thống + màu nhấn hồng. Không có gì cũ ⇒ không ghi. Lặp lại vô hại. IME tự
 * chuyển trong bộ nhớ nếu app chưa chạy.
 */
internal fun migrateThemeSettings(ctx: Context) {
    val all = Prefs.of(ctx).all
    if (ThemeSettings.needsMigration { all[it] }) saveThemeSettings(ctx, ThemeSettings.load { all[it] })
    // Giao diện JSON: theme tự tạo đang chọn khớp lại với kho (sửa / xoá qua sao lưu).
    val now = Prefs.of(ctx).all
    ThemeSettings.refreshCustom { now[it] }?.let { saveThemeSettings(ctx, it) }
}

internal fun saveThemeSettings(ctx: Context, s: ThemeSettings) {
    Prefs.of(ctx).edit().apply {
        putString(Keys.KEYBOARD_THEME, s.theme.id)
        putBoolean(Keys.WALLPAPER_ENABLED, s.wallpaper)
        putInt(Keys.WALLPAPER_DIM, s.dim)
        putInt(Keys.WALLPAPER_BLUR, s.blur)
        putLong(Keys.WALLPAPER_VERSION, s.version)
        s.crop?.let { putString(Keys.WALLPAPER_CROP, it.serialize()) } ?: remove(Keys.WALLPAPER_CROP)
        putInt(Keys.KEYBOARD_TRANSPARENCY, s.keyboardTransparency)
        putInt(Keys.KEY_LABEL_TRANSPARENCY, s.labelTransparency)
        // Tuỳ chỉnh nâng cao theo theme: một chuỗi JSON chuẩn; khoá chung cũ bỏ (đã chuyển vào chuỗi).
        putString(Keys.KEY_STYLES, KeyStyleStore.serialize(s.keyStyles))
        // IME chỉ đọc theme tự tạo đang chọn — bản chuẩn hoá ở khoá riêng.
        s.custom?.let { putString(Keys.ACTIVE_THEME_SPEC, it.canonical) } ?: remove(Keys.ACTIVE_THEME_SPEC)
        for (k in KeyStyleStore.LEGACY_KEYS) remove(k)
    }.apply()
}

/** Dòng trong section Giao diện mở trang theme. */
@Composable
fun ThemeRow(onOpen: () -> Unit) {
    val c = LocalVT.current
    val ctx = LocalContext.current
    val current = remember { loadThemeSettings(ctx).theme.title }
    VTRow(onClick = onOpen) {
        Text(tr("Theme & ảnh nền"), style = VTType.body, color = c.label, modifier = Modifier.weight(1f))
        Text("$current ›", style = VTType.body, color = c.secondary)
    }
}

/** Palette để xem trước trong app: SYSTEM mô phỏng màu sáng/tối mặc định. */
internal fun previewPalette(t: KeyboardTheme, dark: Boolean): ThemePalette = t.palette(dark) ?: if (dark)
    ThemePalette(bg = 0xFF1F1F1F.toInt(), keyFill = 0xFF3C3C3F.toInt(), specialFill = 0xFF2B2F36.toInt(),
        ink = 0xFFE3E3E3.toInt(), trail = 0xFFA8C7FA.toInt(), balloon = 0xFF4A4A4E.toInt(), popup = 0xFF3C3C3F.toInt(),
        action = 0xFFA8C7FA.toInt(), actionInk = 0xFF062E6F.toInt(), chip = 0xFF004A77.toInt(), isDark = true)
else ThemePalette(bg = 0xFFEEF0F4.toInt(), keyFill = 0xFFFFFFFF.toInt(), specialFill = 0xFFD6DBE3.toInt(),
    ink = 0xFF1F1F1F.toInt(), trail = 0xFF0B57D0.toInt(), balloon = 0xFFFFFFFF.toInt(), popup = 0xFFFFFFFF.toInt(),
    action = 0xFF0B57D0.toInt(), actionInk = 0xFFFFFFFF.toInt(), chip = 0xFFD3E3FD.toInt(), isDark = false)

@Composable
fun ThemePage(onBack: () -> Unit, onOpenPlus: () -> Unit = {}) {
    val c = LocalVT.current
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    BackHandler(onBack = onBack)
    val dark = (ctx.resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
        android.content.res.Configuration.UI_MODE_NIGHT_YES
    var s by remember { mutableStateOf(loadThemeSettings(ctx)) }
    var wall by remember { mutableStateOf(WallpaperStore.preview(ctx)) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var confirmReset by remember { mutableStateOf(false) }
    /** Trang con "Chọn giao diện" đang mở. */
    var picking by remember { mutableStateOf(false) }
    /** Trang con "Hiệu ứng khi bấm phím" (Plus) đang mở. */
    var pickingEffect by remember { mutableStateOf(false) }
    val keyEffectRaw by rememberStringPref(Keys.KEY_EFFECT, com.viettelex.keyboard.KeyEffect.DEFAULT.id)
    /** Trang con "Bạn đồng hành" (Plus) đang mở. */
    var pickingBuddy by remember { mutableStateOf(false) }
    /** Đã mở trang "Bạn đồng hành" ⇒ nhãn HOT thôi nhún (vẫn hiện). */
    var buddyPageSeen by rememberBoolPref("buddyPageSeen", false)
    val buddyRaw by rememberStringPref(Keys.KEYBOARD_BUDDY, com.viettelex.keyboard.BuddyCharacter.DEFAULT.id)
    // Ảnh đưa vào trình chỉnh (mới chọn: chưa ghi gì — Huỷ thì ảnh nền cũ còn nguyên).
    var editor by remember { mutableStateOf<EditorInput?>(null) }
    fun update(n: ThemeSettings) { s = n; saveThemeSettings(ctx, n) }
    val assetPrompt = rememberAssetPrompt()

    fun afterWrite(ok: Boolean, enable: Boolean) {
        busy = false
        if (!ok) { error = tr("Không đọc được ảnh này."); return }
        error = null
        wall = WallpaperStore.preview(ctx)
        update(s.copy(wallpaper = if (enable) true else s.wallpaper, version = System.currentTimeMillis()))
    }

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        busy = true
        scope.launch {
            val bmp = withContext(Dispatchers.Default) { runCatching { WallpaperStore.decodeSmall(ctx, uri) }.getOrNull() }
            busy = false
            if (bmp == null) error = tr("Không đọc được ảnh này.") else { error = null; editor = EditorInput(bmp, null, isNew = true) }
        }
    }

    editor?.let { input ->
        WallpaperEditorDialog(input.image, input.crop, remember(input) { KeyboardFrame.portrait(ctx) },
            palette = s.styledCurrent(s.basePalette(dark) ?: previewPalette(KeyboardTheme.SYSTEM, dark), dark).overWallpaper()
                .withTransparency(s.keyboardTransparency, s.labelTransparency, dark),
            initialDim = s.dim, initialBlur = s.blur,
            onCancel = { editor = null },
            onDone = { crop, dim, blur ->
                editor = null
                busy = true
                scope.launch {
                    val ok = withContext(Dispatchers.Default) {
                        runCatching { WallpaperStore.save(ctx, input.image, input.isNew, crop, blur) }.getOrDefault(false)
                    }
                    if (ok) s = s.copy(crop = crop, dim = dim, blur = blur)
                    afterWrite(ok, enable = true)
                }
            })
    }

    if (picking) {
        ThemePickerPage(s, dark, onSelect = { update(it) }, onOpenPlus = onOpenPlus, onBack = { picking = false })
        return
    }

    if (pickingEffect) {
        KeyEffectPage(s.styledCurrent(s.basePalette(dark) ?: previewPalette(KeyboardTheme.SYSTEM, dark), dark),
            onOpenPlus = onOpenPlus, onBack = { pickingEffect = false })
        return
    }

    if (pickingBuddy) {
        BuddyPage(s.styledCurrent(s.basePalette(dark) ?: previewPalette(KeyboardTheme.SYSTEM, dark), dark), s.effectiveTheme.id,
            onOpenPlus = onOpenPlus, onBack = { pickingBuddy = false })
        return
    }

    SubPageHeader(FeaturePage.GiaoDien.title, onBack)

    val active = s.wallpaperActive(wall != null)
    val pal = s.styledCurrent(s.basePalette(dark) ?: previewPalette(KeyboardTheme.SYSTEM, dark), dark)
        .let { if (active) it.overWallpaper() else it }
        .withTransparency(s.keyboardTransparency, s.labelTransparency, dark)
    val raise by rememberIntPref(Keys.KEYBOARD_RAISE, Prefs.D.keyboardRaise)
    VTSection(footer = tr("Áp dụng lần mở bàn phím kế tiếp.")) {
        // Nâng bàn phím: khung cao thêm đúng tỉ lệ thu nhỏ của bản xem trước, phím giữ cỡ.
        val raisePreview = raise * PREVIEW_SCALE
        KeyboardPreview(pal, if (active) wall else null, s.dim, large = true, backdrop = KeyboardTransparency.systemBackdrop(dark),
            keyStyle = s.effectiveKeyStyle,
            modifier = Modifier.fillMaxWidth().height(180.dp + raisePreview.dp), bottomPadDp = raisePreview)
    }

    if (!ThemeGate.allowsWallpaper) {
        VTSection(footer = tr("Theme có nhãn Plus và ảnh nền thuộc VietTelex Plus (Giới Thiệu → VietTelex Plus). Hệ thống, Tối OLED và Tương phản cao luôn miễn phí.")) {}
    }

    // Bộ theme dài (14) ⇒ chọn ở trang con "Chọn giao diện"; ở đây một dòng tóm tắt.
    VTSection(header = "Theme") {
        VTRow(onClick = { picking = true }) {
            KeyboardPreview(s.custom?.let { s.styledCustom(it, dark) } ?: s.styled(s.theme, previewPalette(s.theme, dark), dark), null, 0,
                large = false, keyStyle = s.custom?.let { s.effectiveStyleFor(it.id ?: "", it.typography) } ?: s.effectiveStyleFor(s.theme),
                modifier = Modifier.width(56.dp).height(36.dp).clip(RoundedCornerShape(6.dp))
                    .border(1.dp, c.separator, RoundedCornerShape(6.dp)))
            Text(tr("Giao diện bàn phím"), style = VTType.body, color = c.label,
                modifier = Modifier.weight(1f).padding(start = 12.dp))
            Text("${s.effectiveCustom?.name ?: s.effectiveTheme.title} ›", style = VTType.body, color = c.secondary, maxLines = 1)
        }
        RowDivider()
        VTRow(onClick = { pickingEffect = true }) {
            val fxOn = com.viettelex.keyboard.KeyEffectGate.allows
            Text(tr("Hiệu ứng khi bấm phím") + if (fxOn) "" else " · Plus", style = VTType.body, color = c.label,
                modifier = Modifier.weight(1f))
            Text("${(if (fxOn) com.viettelex.keyboard.KeyEffect.of(keyEffectRaw) else com.viettelex.keyboard.KeyEffect.NONE).title} ›",
                style = VTType.body, color = c.secondary, maxLines = 1)
        }
        // "Bạn đồng hành" (Plus) — mục riêng, mặc định Tắt.
        RowDivider()
        VTRow(onClick = { pickingBuddy = true; buddyPageSeen = true }) {
            val on = com.viettelex.keyboard.BuddyGate.allows
            Text(tr("Bạn đồng hành") + if (on) "" else " · Plus", style = VTType.body, color = c.label)
            HotBadge(animated = !buddyPageSeen, modifier = Modifier.padding(start = 6.dp))
            Spacer(Modifier.weight(1f))
            val ch = com.viettelex.keyboard.BuddyCharacter.of(buddyRaw)
            val shown = if (com.viettelex.keyboard.BuddyGate.allows(ch)) ch else com.viettelex.keyboard.BuddyCharacter.OFF
            val name by rememberStringPref(com.viettelex.keyboard.BuddyName.key(shown), "")
            Text("${shown.title}${if (name.isEmpty()) "" else " · $name"} ›",
                style = VTType.body, color = c.secondary, maxLines = 1)
        }
    }

    // Đập chuột: thẻ thống kê khi theme đang dùng có trò chơi, hoặc đã từng chơi (IME ghi file thống kê).
    val mole = remember(s) { com.viettelex.android.ime.MoleStatsFile.read(ctx) }
    if (s.effectiveKeyStyle.game == com.viettelex.keyboard.MoleGame.THEME_GAME || mole.total > 0) {
        VTSection(footer = tr("Gõ như thường — chú chuột thò lên ở phím bạn sắp gõ. Gõ trúng lúc nó đang lên là đập được!")) {
            VTRow {
                Text("🐭", style = VTType.body.copy(fontSize = 30.sp))
                Column(Modifier.weight(1f).padding(start = 12.dp)) {
                    Text(tr("Hôm nay đập %s con chuột 🐭", mole.count(com.viettelex.keyboard.MoleStats.dayNumber())),
                        style = VTType.body, color = c.label)
                    Text(tr("Chuỗi dài nhất: %s · Tổng: %s", mole.best, mole.total), style = VTType.body.copy(fontSize = 13.sp),
                        color = c.secondary)
                }
            }
        }
    }

    VTSection(header = tr("Ảnh nền · Plus"),
        footer = tr("Ảnh được thu nhỏ và nén ngay trên máy, không gửi đi đâu. Lớp phủ giúp chữ trên phím dễ đọc.")) {
        VTRow(onClick = if (busy || !ThemeGate.allowsWallpaper) null else {
            { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }
        }) {
            Text(if (wall != null) tr("Đổi ảnh nền") else tr("Chọn ảnh nền"), style = VTType.body,
                color = if (ThemeGate.allowsWallpaper) c.accent else c.secondary)
        }
        if (wall != null && WallpaperStore.hasSource(ctx)) {
            RowDivider()
            // Mở lại bản gốc với khung đang dùng (ảnh cũ chưa có khung ⇒ bắt đầu từ khung giữa).
            VTRow(onClick = if (busy || !ThemeGate.allowsWallpaper) null else {
                {
                    busy = true
                    scope.launch {
                        val bmp = withContext(Dispatchers.Default) { runCatching { WallpaperStore.loadSource(ctx) }.getOrNull() }
                        busy = false
                        if (bmp == null) error = tr("Không đọc được ảnh này.") else editor = EditorInput(bmp, s.crop, isNew = false)
                    }
                }
            }) {
                Text(tr("Chỉnh ảnh"), style = VTType.body, color = if (ThemeGate.allowsWallpaper) c.accent else c.secondary)
            }
        }
        if (wall != null) {
            RowDivider()
            SettingToggle(tr("Dùng ảnh nền"), null, s.wallpaper) { update(s.copy(wallpaper = it)) }
            RowDivider()
            Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                Text(tr("Độ tối lớp phủ: %s%%", s.dim), style = VTType.body, color = c.label)
                Slider(value = s.dim.toFloat(), onValueChange = { update(s.copy(dim = (it / 5).toInt() * 5)) }, valueRange = 0f..80f)
                Text(tr("Độ mờ ảnh: %s", s.blur), style = VTType.body, color = c.label)
                Slider(value = s.blur.toFloat(), onValueChange = { s = s.copy(blur = it.toInt()) }, valueRange = 0f..20f,
                    onValueChangeFinished = {
                        busy = true
                        val blur = s.blur; val crop = s.crop
                        scope.launch {
                            val ok = withContext(Dispatchers.Default) { runCatching { WallpaperStore.reblur(ctx, blur, crop) }.getOrDefault(false) }
                            afterWrite(ok, enable = false)
                        }
                    })
            }
            RowDivider()
            VTRow(onClick = {
                WallpaperStore.remove(ctx); wall = null
                update(s.copy(wallpaper = false, crop = null, version = System.currentTimeMillis()))
            }) { Text(tr("Xoá ảnh nền"), style = VTType.body, color = c.red) }
        }
        if (busy) VTRow { Text(tr("Đang xử lý ảnh…"), style = VTType.footnote, color = c.secondary) }
        error?.let { VTRow { Text(it, style = VTType.footnote, color = c.red) } }
    }

    VTSection(header = tr("Độ trong suốt"),
        footer = tr("Phím: nền và viền phím (cả nền bàn phím khi không dùng ảnh nền) — 100% chỉ còn chữ, ảnh nền vẫn giữ nguyên. Ký tự: chữ và biểu tượng trên phím — 100% là phím trơn không chữ.")) {
        Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
            Text(tr("Độ trong suốt phím: %s%%", s.keyboardTransparency), style = VTType.body, color = c.label)
            Slider(value = s.keyboardTransparency.toFloat(), valueRange = 0f..100f,
                onValueChange = { update(s.copy(keyboardTransparency = Math.round(it / 5) * 5)) })
            Text(tr("Độ trong suốt ký tự: %s%%", s.labelTransparency), style = VTType.body, color = c.label)
            Slider(value = s.labelTransparency.toFloat(), valueRange = 0f..100f,
                onValueChange = { update(s.copy(labelTransparency = Math.round(it / 5) * 5)) })
            // #137: nền trong suốt chỉ "xuyên" được ở app vẽ nội dung dưới bàn phím — nói rõ thay vì hứa.
            if (KeyboardTransparency.revealsHostApp(s.keyboardTransparency, opaqueBackdrop = active))
                Text(tr("Phía sau bàn phím là gì do từng app quyết định. Trình duyệt và một số app vẽ nội dung dưới bàn phím nên thấy xuyên qua; phần lớn app thu màn hình lên trên bàn phím, phía sau chỉ còn nền trơn của app (trắng hoặc đen), nên bàn phím chỉ nhạt đi. Muốn trong giống nhau ở mọi app: dùng ảnh nền, độ trong suốt khi đó chỉ áp lên phím."), style = VTType.footnote, color = c.secondary)
        }
    }

    AdvancedStyleSection(s.keyStyle, pal, onChange = { st ->
        val before = s.keyStyle.assets
        update(s.withKeyStyle(st))
        if (st.assets != before) ThemeAssetFlow.gcAsync(ctx)
    }, onOpenPlus = onOpenPlus, onFontAsset = { st ->
        // Chọn phông tải về = đặt phông cho theme hiện tại, rồi HỎI trước khi tải.
        val ns = s.withKeyStyle(st)
        update(ns)
        ThemeAssetFlow.gcAsync(ctx)
        assetPrompt.offer(ctx, ns.effectiveKeyStyle.assets)
    })
    ThemeAssetPromptHost(assetPrompt, onOpenPlus)

    // Tính Năng → Giao diện gộp luôn chiều cao hàng + logo (không thuộc "Khôi phục giao diện gốc").
    VTSection(header = tr("Bàn phím")) {
        var adj by rememberIntPref(Keys.ROW_HEIGHT_ADJUST, Prefs.D.rowHeightAdjust)
        val numberRow by rememberBoolPref(Keys.NUMBER_ROW, Prefs.D.numberRow)
        val numberRowFull by rememberBoolPref(Keys.NUMBER_ROW_FULL_HEIGHT, Prefs.D.numberRowFullHeight)
        VTRow {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(tr("Chiều cao hàng phím"), style = VTType.body, color = c.label)
                Text(
                    if (adj == 0) tr("Chuẩn") else String.format(java.util.Locale.ROOT, tr("%+d dp mỗi hàng (%+d dp cả bàn phím)"), adj,
                        com.viettelex.android.ime.KeyLayout.adjustTotalDp(adj, numberRow, numberRowFull)),
                    style = VTType.footnote, color = c.secondary,
                )
                // Trên trần cũ +10: IME kẹp theo cao màn hình (KeyLayout.effectiveRowAdjust).
                if (adj > com.viettelex.keyboard.KeyboardSettings.ROW_HEIGHT_UNCLAMPED_MAX)
                    Text(tr("Màn hình thấp hoặc xoay ngang: tự giới hạn để bàn phím không quá nửa màn hình."),
                        style = VTType.footnote, color = c.secondary)
            }
            IosStepper(adj, com.viettelex.keyboard.KeyboardSettings.ROW_HEIGHT_MIN..com.viettelex.keyboard.KeyboardSettings.ROW_HEIGHT_MAX) { adj = it }
        }
        RowDivider()
        KeyboardRaiseRow()
        RowDivider()
        // "Chiều cao thanh gợi ý" Thấp / Vừa (mặc định) / Cao — SuggestionBarHeight, cùng khoá iOS.
        ChoiceRow(Keys.SUGGESTION_BAR_HEIGHT, Prefs.D.suggestionBarHeight.id, tr("Chiều cao thanh gợi ý"),
            tr("Thanh gợi ý cao hơn thì dễ chạm trúng từ gợi ý hơn; bàn phím cao thêm đúng phần đó. Khi xoay ngang, mức Cao dùng như Vừa."),
            listOf(com.viettelex.keyboard.SuggestionBarHeight.LOW.id to tr("Thấp"),
                com.viettelex.keyboard.SuggestionBarHeight.MEDIUM.id to tr("Vừa"),
                com.viettelex.keyboard.SuggestionBarHeight.HIGH.id to tr("Cao"))) {
            com.viettelex.keyboard.SuggestionBarHeight.of(it).id
        }
        RowDivider()
        // "Màu chữ gợi ý" Xám (mặc định, như bàn phím Apple) / Sáng — SuggestionInk, cùng khoá iOS.
        ChoiceRow(Keys.SUGGESTION_INK, Prefs.D.suggestionInk.id, tr("Màu chữ gợi ý"),
            tr("Xám: chữ gợi ý dịu như bàn phím Apple, đỡ rối mắt khi gõ. Sáng: chữ đậm cùng màu chữ phím."),
            listOf(com.viettelex.keyboard.SuggestionInk.MUTED.id to tr("Xám"),
                com.viettelex.keyboard.SuggestionInk.BRIGHT.id to tr("Sáng"))) {
            com.viettelex.keyboard.SuggestionInk.of(it).id
        }
        RowDivider()
        BoolToggle(Keys.SHOW_SPACE_LOGO, Prefs.D.showSpaceLogo, tr("Hiện logo Vᴛ"), tr("Logo mờ ở góc phải phím cách."))
        RowDivider()
        // Bàn phím tách đôi (SplitLayout, cùng khoá iOS) — mặc định TẮT; chỉ tách khi bàn phím ≥ 600 dp.
        BoolToggle(Keys.SPLIT_KEYBOARD, Prefs.D.splitKeyboard, tr("Bàn phím tách đôi"),
            tr("Màn hình rộng (điện thoại gập khi mở, điện thoại xoay ngang, máy tính bảng): chia bàn phím làm hai nửa để gõ bằng hai ngón cái. Khi đang tách, gõ vuốt và chế độ một tay tạm tắt."))
    }

    VTSection(footer = tr("Về theme Hệ thống, tắt ảnh nền (ảnh vẫn giữ để bật lại), độ tối/mờ, độ trong suốt và tuỳ chỉnh nâng cao về mặc định. Chiều cao hàng và logo giữ nguyên.")) {
        VTRow(onClick = if (s.isDefault || busy) null else { { confirmReset = true } }) {
            Text(tr("Khôi phục giao diện gốc"), style = VTType.body, color = if (s.isDefault) c.secondary else c.red)
        }
    }
    if (confirmReset) AlertDialog(
        onDismissRequest = { confirmReset = false },
        title = { Text(tr("Khôi phục giao diện gốc?")) },
        text = { Text(tr("Theme, ảnh nền và độ trong suốt về mặc định. Ảnh nền không bị xoá.")) },
        confirmButton = { TextButton(onClick = {
            confirmReset = false
            val blurChanged = s.blur != 0
            update(s.resetToDefaults())
            // Ảnh đang lưu đã mờ theo độ cũ → dựng lại bản không mờ từ ảnh gốc.
            if (blurChanged && wall != null) {
                busy = true
                scope.launch {
                    val crop = s.crop
                    val ok = withContext(Dispatchers.Default) { runCatching { WallpaperStore.reblur(ctx, 0, crop) }.getOrDefault(false) }
                    afterWrite(ok, enable = false)
                }
            }
        }) { Text(tr("Khôi phục"), color = c.red) } },
        dismissButton = { TextButton(onClick = { confirmReset = false }) { Text(tr("Huỷ")) } },
    )
}

/** Ảnh đưa vào trình chỉnh ảnh nền. */
private data class EditorInput(val image: Bitmap, val crop: WallpaperCrop?, val isNew: Boolean)

/** Bản xem trước ≈ 0.7 cỡ bàn phím thật (180 dp cho ~258 dp phím + strip). */
private const val PREVIEW_SCALE = 0.7f

/**
 * "Nâng bàn phím" (#112): thanh trượt 0…48 dp (bước 4) — đệm nền dưới hàng phím đáy để
 * bàn phím nằm cao hơn (ngón cái dễ với, tránh thanh cử chỉ). Bản xem trước trên trang cao theo.
 */
@Composable
private fun KeyboardRaiseRow() {
    val c = LocalVT.current
    var raise by rememberIntPref(Keys.KEYBOARD_RAISE, Prefs.D.keyboardRaise)
    Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
        Text(tr("Nâng bàn phím"), style = VTType.body, color = c.label)
        Text(if (raise == 0) tr("Tắt") else tr("Cao hơn %d dp", raise), style = VTType.footnote, color = c.secondary)
        Slider(value = raise.toFloat(), valueRange = 0f..KeyboardSettings.KEYBOARD_RAISE_MAX.toFloat(),
            steps = KeyboardSettings.KEYBOARD_RAISE_MAX / 4 - 1,
            onValueChange = { raise = KeyboardSettings.clampRaise(Math.round(it / 4) * 4) })
        Text(tr("Thêm khoảng trống dưới hàng phím cuối để bàn phím nằm cao hơn."), style = VTType.footnote, color = c.secondary)
    }
}

/** Bàn phím thu nhỏ vẽ bằng đúng token theme. [keysOnly]: chỉ phím (lớp phủ trình chỉnh ảnh nền).
 *  [bottomPadDp]: dải nền trống dưới hàng phím đáy (xem trước "Nâng bàn phím"). */
@Composable
internal fun KeyboardPreview(p: ThemePalette, wallpaper: ImageBitmap?, dim: Int, large: Boolean, modifier: Modifier,
                             backdrop: Int? = null, keysOnly: Boolean = false, bottomPadDp: Float = 0f,
                             keyStyle: KeyStyle = KeyStyle.DEFAULT) {
    // Nhãn chữ (chỉ bản lớn, khi chữ được tuỳ chỉnh): phông đọc lại khi kho đổi (tải xong) ⇒ vẽ lại bằng phông mới.
    val labels = PreviewLabelFont.showsLabels(large, keyStyle)
    val labelPaint = if (labels) rememberPreviewLabelPaint(keyStyle) else null
    Box(modifier) {
        val bottom = p.bgBottom
        if (!keysOnly) Canvas(Modifier.fillMaxSize()) {
            // Nền trong suốt: lộ app phía sau (giả lập bằng màu nền app sáng/tối).
            backdrop?.let { drawRect(Color(it)) }
            if (bottom != null) drawRect(Brush.verticalGradient(listOf(Color(p.bg), Color(bottom))))
            else drawRect(Color(p.bg))
            // Hoạ tiết (Tim đen / Hoa xanh) cùng hình học bàn phím thật, thu theo bề ngang 390 dp.
            val d = p.decoration
            if (d != null && wallpaper == null) {
                // Khe giữa các hàng của bản thu nhỏ (cùng lưới phím bên dưới), phóng về khe thật ~11 dp.
                val unit = size.width / 390f
                val pad = if (large) 6.dp.toPx() else 3.dp.toPx()
                val gap = if (large) 5.dp.toPx() else 2.dp.toPx()
                val kh = (size.height - bottomPadDp.dp.toPx() - pad * 2 - gap * 3) / 4
                val gaps = (1..3).map { i -> com.viettelex.keyboard.ThemeDecoration.Gap(((pad + i * kh + (i - 0.5f) * gap) / unit).toDouble(), 11.0) }
                val path = android.graphics.Path()
                com.viettelex.android.ime.decorPath(path, d.motif, com.viettelex.keyboard.ThemeDecoration.placements(390.0, gaps, d.density), unit,
                    alt = d.alt, width = 390.0)
                drawPath(path.asComposePath(), Color(d.color))
            }
        }
        if (wallpaper != null) {
            // Ảnh nền không theo độ trong suốt phím (ThemePalette.wallpaperLayer).
            val wl = p.wallpaperLayer(dim)
            Image(wallpaper, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop, alpha = wl.imageAlpha)
            Canvas(Modifier.fillMaxSize()) { drawRect(Color(wl.overlay)) }
        }
        Canvas(Modifier.fillMaxSize()) {
            val pad = if (large) 6.dp.toPx() else 3.dp.toPx()
            val gap = if (large) 5.dp.toPx() else 2.dp.toPx()
            val r = if (large) 6.dp.toPx() else 2.dp.toPx()
            val rainbow = if (p.rainbowBorder) com.viettelex.keyboard.RainbowBorder.stops().let { (cols, pos) ->
                Brush.horizontalGradient(*Array(cols.size) { pos[it].toFloat() to Color(cols[it] or (0xFF shl 24)) },
                    startX = 0f, endX = size.width * 2)
            } else null
            val kw = (size.width - pad * 2 - gap * 9) / 10
            val kh = (size.height - bottomPadDp.dp.toPx() - pad * 2 - gap * 3) / 4
            fun key(x: Float, y: Float, w: Float, fill: Int) {
                val kr = KeyStyle.cornerRadius(keyStyle.corner, w, kh, r)
                drawRoundRect(Color(fill), Offset(x, y), Size(w, kh), CornerRadius(kr))
                p.keyBorder?.let { drawRoundRect(Color(it), Offset(x, y), Size(w, kh), CornerRadius(kr), style = Stroke(1.dp.toPx())) }
                // Gaming RGB: viền cầu vồng tĩnh — MỘT gradient ngang trải cả bản thu nhỏ (như bàn phím thật lúc nghỉ).
                rainbow?.let { drawRoundRect(it, Offset(x, y), Size(w, kh), CornerRadius(kr), style = Stroke((if (large) 1.5f else 1f) * density)) }
                if (large && labelPaint == null) drawCircle(Color(p.keyInk).copy(alpha = 0.8f * p.labelAlpha), minOf(w, kh) * 0.09f, Offset(x + w / 2, y + kh / 2))
            }
            fun label(text: String, x: Float, y: Float, w: Float, ink: Int, size: Float) {
                val lp = labelPaint ?: return
                lp.textSize = size
                lp.color = ink
                lp.alpha = (255 * p.labelAlpha).toInt().coerceIn(0, 255)
                val fm = lp.fontMetrics
                drawContext.canvas.nativeCanvas.drawText(text, x + w / 2, y + kh / 2 - (fm.ascent + fm.descent) / 2, lp)
            }
            val counts = intArrayOf(10, 9, 7)
            for (row in 0..2) {
                val n = counts[row]
                val x0 = pad + (10 - n) * (kw + gap) / 2
                for (i in 0 until n) {
                    val x = x0 + i * (kw + gap); val ky = pad + row * (kh + gap)
                    key(x, ky, kw, p.keyFill)
                    label(PREVIEW_ROWS[row][i].toString(), x, ky, kw, p.keyInk, kh * 0.55f * keyStyle.letterScale)
                }
            }
            val y = pad + 3 * (kh + gap)
            key(pad, y, kw * 2 + gap, p.fnFill)
            label("123", pad, y, kw * 2 + gap, p.fnInk, kh * 0.36f * keyStyle.controlScale)
            key(pad + 2 * (kw + gap), y, kw * 6 + gap * 5, p.spaceFill)
            if (p.spaceSoundhole) {
                // Ghi-ta: lỗ thoát âm + hai vành hoa văn (cùng hình học Soundhole của bàn phím thật).
                val sw = kw * 6 + gap * 5
                val c = Offset(pad + 2 * (kw + gap) + sw / 2, y + kh / 2)
                val rr = com.viettelex.keyboard.Soundhole.radius(sw.toDouble(), kh.toDouble()).toFloat()
                drawCircle(Color.Black.copy(alpha = com.viettelex.keyboard.Soundhole.HOLE_ALPHA.toFloat()), rr, c)
                val rings = com.viettelex.keyboard.Soundhole.RINGS
                drawCircle(Color(p.action).copy(alpha = 0.85f), (rings[0][0] * rr).toFloat(), c, style = Stroke((rings[0][1] * rr).toFloat()))
                drawCircle(Color(p.fnInk).copy(alpha = 0.45f), (rings[1][0] * rr).toFloat(), c, style = Stroke((rings[1][1] * rr).toFloat()))
            }
            key(pad + 8 * (kw + gap), y, kw * 2 + gap, p.action)
        }
    }
}

private val PREVIEW_ROWS = arrayOf("qwertyuiop", "asdfghjkl", "zxcvbnm")

/** Paint nhãn ô xem trước: Typeface cùng luật bàn phím; phụ thuộc [ThemeAssetFlow.storeVersion] (tải xong ⇒ nạp lại). */
@Composable
private fun rememberPreviewLabelPaint(style: KeyStyle): android.graphics.Paint {
    val ctx = LocalContext.current
    val version = ThemeAssetFlow.storeVersion
    return remember(style.font, style.weight, style.assets.font, version) {
        val file = PreviewLabelFont.downloadedFile(style, ThemeAssetFlow.dir(ctx))
        val downloaded = file?.let { runCatching { android.graphics.Typeface.createFromFile(it) }.getOrNull() }
        android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
            textAlign = android.graphics.Paint.Align.CENTER
            typeface = com.viettelex.android.ime.keyLabelTypeface(style, downloaded)
                ?: android.graphics.Typeface.create("sans-serif", android.graphics.Typeface.NORMAL)
        }
    }
}

/** Nhãn "HOT" (mục mới cần gây chú ý) = iOS HotBadge: viên đỏ-cam, nhún nhẹ tới khi user mở trang lần đầu. */
@Composable
internal fun HotBadge(animated: Boolean, modifier: Modifier = Modifier) {
    val scale = if (animated) {
        val t = androidx.compose.animation.core.rememberInfiniteTransition(label = "hot")
        t.animateFloat(1f, 1.12f, androidx.compose.animation.core.infiniteRepeatable(
            androidx.compose.animation.core.tween(700, easing = androidx.compose.animation.core.FastOutSlowInEasing),
            androidx.compose.animation.core.RepeatMode.Reverse), label = "hotScale").value
    } else 1f
    Text("HOT", style = VTType.caption2, color = Color.White, fontWeight = androidx.compose.ui.text.font.FontWeight.Black,
        modifier = modifier.graphicsLayer { scaleX = scale; scaleY = scale }
            .clip(RoundedCornerShape(50))
            .background(Brush.horizontalGradient(listOf(Color(0xFFFF3B30), Color(0xFFFF9500))))
            .padding(horizontal = 5.dp, vertical = 1.dp))
}
