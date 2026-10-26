package com.viettelex.android.ime

import android.annotation.SuppressLint
import android.content.Context
import android.os.Build
import android.view.ViewGroup
import android.view.WindowInsets
import kotlin.math.roundToInt

/**
 * Gốc input view: [KeyboardView] (vùng phím) · [StripView] (strip gợi ý, phủ 4 dp lên
 * mép phím) · [BalloonView] (overlay). Nền theme toàn khung (trong suốt được — độ trong suốt phím), cộng inset nav/gesture bar
 * ở đáy (cùng màu bàn phím, spec §6.1). Multi-touch tách theo view con.
 */
@SuppressLint("ViewConstructor")
class ImeRootView(
    context: Context,
    private val theme: ImeTheme,
    val keyboard: KeyboardView,
    val strip: StripView,
    val balloon: BalloonView,
    /** Vệt gõ vuốt — phủ đúng vùng phím, dưới balloon. */
    val trail: SwipeTrailView,
) : ViewGroup(context) {

    private var navInset = 0

    /**
     * "Nâng bàn phím" (#112): đệm nền dưới hàng phím đáy, CỘNG thêm vào đệm điều hướng —
     * chỉ là nền (ảnh nền / màu theme phủ cả khung), không view con nên chạm vào bị nuốt ở
     * cửa sổ IME (touchableInsets = CONTENT), không rơi xuống app. 0 ⇒ y như cũ.
     */
    var raisePx = 0
        set(v) { val c = v.coerceAtLeast(0); if (c != field) { field = c; requestLayout() } }

    /** Ảnh nền (null = không dùng) — vẽ trong onDraw: bitmap center-crop + lớp phủ phẳng. */
    private val wallpaperFile: java.io.File? =
        if (theme.palette.wallpaper) java.io.File(context.filesDir, com.viettelex.keyboard.Keys.WALLPAPER_FILE) else null
    private var wallpaper: android.graphics.Bitmap? = null
    private val wallMatrix = android.graphics.Matrix()
    // Ảnh nền luôn đục, lớp phủ theo độ tối — độ trong suốt phím chỉ đụng phím
    // (ThemePalette.wallpaperLayer; trước đây 100% làm mất ảnh nền).
    private val wallLayer = theme.palette.wallpaperLayer(theme.settings.dim)
    private val wallPaint = android.graphics.Paint(android.graphics.Paint.FILTER_BITMAP_FLAG).apply {
        alpha = (wallLayer.imageAlpha * 255).toInt()
    }
    private val dimColor = wallLayer.overlay

    /**
     * Ảnh nền / tiền cảnh của THEME (tệp tải về, app đã xử lý). Ảnh nền tự đặt của người dùng (đang bật) thắng ảnh
     * nền theme. Không có ⇒ null, không đọc gì. Thứ tự lớp: nền (màu + ảnh) · phím · tiền cảnh · vệt / hiệu ứng · ô
     * phóng to.
     */
    private val themeBgFile: java.io.File? = theme.assets?.background?.takeIf {
        com.viettelex.keyboard.ThemeAssetPlan.showsThemeBackground(userWallpaperActive = theme.palette.wallpaper, themeBackgroundReady = true)
    }
    private var themeBg: android.graphics.Bitmap? = null
    private var themeBgW = 0
    private var themeBgH = 0
    private val themeBgRect = android.graphics.RectF()
    private val themeBgPaint = android.graphics.Paint(android.graphics.Paint.FILTER_BITMAP_FLAG)
    /** Tiền cảnh: view riêng TRÊN phím, dưới vệt vuốt / hiệu ứng / balloon; không nhận chạm. */
    private val foreground: ThemeForegroundView? = theme.assets?.foreground?.let { ThemeForegroundView(context, it) }

    /** Nền theme (màu / gradient kính) — nền view khi dính đáy, vẽ tay trong khung khi thả nổi. */
    private val bgDrawable: android.graphics.drawable.Drawable = theme.palette.bgBottom.let { bottom ->
        // Kính giả lập: gradient dọc (GradientDrawable — vẽ phẳng, không blur).
        val decoration = theme.palette.decoration
        if (wallpaperFile == null && bottom != null) android.graphics.drawable.GradientDrawable(
            android.graphics.drawable.GradientDrawable.Orientation.TOP_BOTTOM, intArrayOf(theme.bg, bottom))
        // Tim đen / Hoa xanh: hoạ tiết là MỘT Path trong nền (vẽ khi nền đổi, không mỗi phím).
        else if (wallpaperFile == null && decoration != null) ThemeDecorDrawable(theme.bg, decoration, theme.density)
        else android.graphics.drawable.ColorDrawable(theme.bg)
    }

    fun refreshStringGaps() = updateStringGaps()

    /** Rung dây: khe hàng phím (px, toạ độ overlay) cho hiệu ứng — kiểu khác / tắt ⇒ thoát ngay (0 chi phí). */
    private fun updateStringGaps() {
        val fx = effects ?: return
        if (fx.effect != com.viettelex.keyboard.KeyEffect.STRING) return
        val off = (keyboard.top - fx.top).toDouble()
        fx.setStringGaps(com.viettelex.keyboard.ThemeDecoration.rowGaps(keyboard.keySpans().map { doubleArrayOf(it[0] + off, it[1] + off) }))
    }

    /** Đặt motif hoạ tiết vào khe giữa các hàng phím (chỉ theme có hoạ tiết; gọi khi layout / dựng phím). */
    private fun updateDecorGaps() {
        val dd = bgDrawable as? ThemeDecorDrawable ?: return
        val off = keyboard.top.toDouble(); val dens = theme.density.toDouble()
        val spans = keyboard.keySpans().map { doubleArrayOf((it[0] + off) / dens, (it[1] + off) / dens) }
        dd.setRowGaps(com.viettelex.keyboard.ThemeDecoration.rowGaps(spans))
    }

    /**
     * Viền phím cầu vồng (theme Gaming RGB — "borderFx":"rainbow"): ngay TRÊN phím, dưới strip / tiền cảnh / vệt /
     * hiệu ứng / balloon; cùng khung KeyboardView. Theme khác ⇒ null (không có view).
     */
    val rainbow: RainbowBorderView? = if (theme.palette.rainbowBorder) RainbowBorderView(context, theme.density) else null
    private val rainbowPath = android.graphics.Path()

    /** Mặt nạ viền theo khung phím hiện tại (gọi khi dựng phím / layout — không mỗi phím). */
    private fun updateRainbowOutline() {
        val r = rainbow ?: return
        keyboard.keyOutlines(rainbowPath, r.lineWidthPx / 2)
        r.setOutline(rainbowPath)
    }

    init {
        background = bgDrawable
        // Mỗi hàm tự thoát ngay nếu theme / hiệu ứng không cần (không hoạ tiết, không cầu vồng, không Rung dây).
        keyboard.onKeysLaidOut = { updateDecorGaps(); updateRainbowOutline(); updateStringGaps() }
        if (wallpaperFile != null || themeBgFile != null) setWillNotDraw(false)
        isMotionEventSplittingEnabled = true
        addView(keyboard)
        rainbow?.let { addView(it); keyboard.rainbow = it }
        addView(strip)
        foreground?.let { addView(it) }
        addView(trail)
        addView(balloon)
    }

    private fun stripPx() = strip.stripPx().roundToInt()

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        if (floating) return              // ảnh nền theo cỡ khung — onLayout lo
        recordPortraitSize(w, h)
        loadWallpaperFor(w, h)
        loadThemeBgFor(w, h)
    }

    /** Ảnh nền theme cho vùng [w]×[h] (đồng bộ — chỉ khi đổi cỡ; ≤ cỡ vùng × 4 byte). */
    private fun loadThemeBgFor(w: Int, h: Int) {
        val f = themeBgFile ?: return
        if (w == themeBgW && h == themeBgH && themeBg != null) return
        themeBgW = w; themeBgH = h
        themeBg = ThemeAssetLoader.loadScreen(f, w, h, fill = true, hardware = isHardwareAccelerated)
        invalidate()
    }

    /** Giải ảnh nền cho vùng [w]×[h] (đồng bộ — chỉ khi đổi cỡ: xoay, đổi chế độ). */
    private fun loadWallpaperFor(w: Int, h: Int) {
        val f = wallpaperFile ?: return
        reloadGen++
        wallW = w; wallH = h
        setWallpaper(WallpaperBitmap.load(f, theme.settings.version, w, h, isHardwareAccelerated))
    }
    /** Cỡ vùng ảnh nền đang dùng (view khi dính đáy, khung khi thả nổi). */
    private var wallW = 0
    private var wallH = 0

    /**
     * Cỡ thật vùng bàn phím dọc (gồm strip + đệm điều hướng) cho khung trình chỉnh ảnh nền ở
     * app. Prefs riêng (không bắn listener của IME, không sao lưu); chỉ ghi khi đổi.
     */
    private fun recordPortraitSize(w: Int, h: Int) {
        if (w <= 0 || h <= 0 ||
            resources.configuration.orientation != android.content.res.Configuration.ORIENTATION_PORTRAIT) return
        val v = "${w}x$h"
        val sp = context.getSharedPreferences(com.viettelex.keyboard.Keys.RUNTIME_PREFS, Context.MODE_PRIVATE)
        if (sp.getString(com.viettelex.keyboard.Keys.IME_PORTRAIT_SIZE, null) != v)
            sp.edit().putString(com.viettelex.keyboard.Keys.IME_PORTRAIT_SIZE, v).apply()
    }

    private fun setWallpaper(b: android.graphics.Bitmap?) {
        wallpaper = b
        updateWallMatrix()
        invalidate()
    }

    /** center-crop vào vùng nền (bitmap đã là vùng thấy được — tỉ lệ ≈ vùng; phần lệch cắt nốt). */
    private fun updateWallMatrix() {
        val b = wallpaper ?: return
        val x0 = if (floating) panel.left else 0
        val y0 = if (floating) panel.top else 0
        val w = if (floating) panel.width() else width
        val h = if (floating) panel.height() else height
        val s = maxOf(w.toFloat() / b.width, h.toFloat() / b.height)
        wallMatrix.setScale(s, s)
        wallMatrix.postTranslate(x0 + (w - b.width * s) / 2f, y0 + (h - b.height * s) / 2f)
    }

    private var reloadGen = 0

    /** Hẹn giờ ẩn: bỏ bitmap (true nếu đã có) — [reloadWallpaper] lúc hiện lại. */
    fun dropWallpaper(): Boolean {
        var had = wallpaper != null
        wallpaper = null; reloadGen++
        if (themeBg != null) { themeBg = null; themeBgW = 0; themeBgH = 0; had = true }
        if (foreground?.drop() == true) had = true
        return had
    }

    /** Giải lại ảnh nền trên [background] (không chặn main); chưa xong thì nền màu theme. */
    fun reloadWallpaper(background: (Runnable) -> Unit) {
        foreground?.reload(background)
        themeBgFile?.let { tf ->
            val w = if (floating) panel.width() else width
            val h = if (floating) panel.height() else height
            if (themeBg == null && w > 0 && h > 0) {
                val gen = reloadGen; val hw = isHardwareAccelerated
                background(Runnable {
                    val b = ThemeAssetLoader.loadScreen(tf, w, h, fill = true, hardware = hw)
                    post { if (gen == reloadGen && themeBg == null) { themeBg = b; themeBgW = w; themeBgH = h; invalidate() } }
                })
            }
        }
        val f = wallpaperFile ?: return
        val w = if (floating) panel.width() else width
        val h = if (floating) panel.height() else height
        if (wallpaper != null || w <= 0 || h <= 0) return
        val gen = ++reloadGen
        val hw = isHardwareAccelerated
        wallW = w; wallH = h
        background(Runnable {
            val b = WallpaperBitmap.load(f, theme.settings.version, w, h, hw)
            post { if (gen == reloadGen && wallW == w && wallH == h) setWallpaper(b) }
        })
    }

    override fun onDraw(canvas: android.graphics.Canvas) {
        super.onDraw(canvas)
        if (floating) { drawFloatingPanel(canvas); return }
        drawWallpaper(canvas)
    }

    private fun drawWallpaper(canvas: android.graphics.Canvas) {
        drawThemeBg(canvas)
        val b = wallpaper ?: return
        // Bitmap HARDWARE chỉ vẽ được trên canvas GPU (canvas phần mềm — vd chụp view — bỏ qua).
        if (b.config == android.graphics.Bitmap.Config.HARDWARE && !canvas.isHardwareAccelerated) return
        canvas.drawBitmap(b, wallMatrix, wallPaint)
        canvas.drawColor(dimColor)
    }

    /** Ảnh nền theme (đã cắt đúng tỉ lệ vùng) vẽ đè màu nền theme. */
    private fun drawThemeBg(canvas: android.graphics.Canvas) {
        val b = themeBg ?: return
        if (b.config == android.graphics.Bitmap.Config.HARDWARE && !canvas.isHardwareAccelerated) return
        if (floating) themeBgRect.set(panel) else themeBgRect.set(0f, 0f, width.toFloat(), height.toFloat())
        canvas.drawBitmap(b, null, themeBgRect, themeBgPaint)
    }

    // MARK: thả nổi (#112) — FloatingKeyboard. Tắt ⇒ không nhánh nào dưới đây chạy.

    /** Bàn phím thả nổi: khung bo góc ở (fx, fy), ngoài khung trong suốt. Đặt qua [setFloating]. */
    var floating = false; private set
    private var floatFx = FloatingKeyboard.DEFAULT_FX
    private var floatFy = FloatingKeyboard.DEFAULT_FY
    /** Khung (toạ độ view gốc) — hợp lệ sau onLayout khi [floating]. */
    val panel = android.graphics.Rect()
    private val panelPath = android.graphics.Path()
    private var statusTop = 0
    /** Kéo xong (fx, fy) ⇒ IME lưu theo chiều màn hình. */
    var onFloatMoved: ((Float, Float) -> Unit)? = null
    /** Nút ⤓ trên thanh kéo ⇒ IME gắn bàn phím lại. */
    var onFloatExit: (() -> Unit)? = null
    private val handlePx get() = Math.round(theme.dp(FloatingKeyboard.HANDLE_DP))
    private var floatPaint: android.graphics.Paint? = null
    private var dragMode = -1                  // -1 không, 0 kéo, 1 nút gắn lại
    private var downRawX = 0f; private var downRawY = 0f
    private var downLeft = 0; private var downTop = 0

    fun setFloating(on: Boolean, fx: Float = FloatingKeyboard.DEFAULT_FX, fy: Float = FloatingKeyboard.DEFAULT_FY) {
        val f = FloatingKeyboard.clampFraction(fx); val g = FloatingKeyboard.clampFraction(fy)
        if (on == floating && f == floatFx && g == floatFy) return
        floatFx = f; floatFy = g
        if (on != floating) {
            floating = on
            dragMode = -1
            background = if (on) null else bgDrawable
            setWillNotDraw(!on && wallpaperFile == null && themeBgFile == null)
            clipChildren = !on              // balloon / popup vẽ được phía trên khung
            if (on && floatPaint == null) floatPaint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG)
            panel.setEmpty()
            wallW = 0; wallH = 0           // vùng nền đổi ⇒ giải lại theo cỡ mới
        }
        requestLayout(); invalidate()
    }

    private fun drawFloatingPanel(canvas: android.graphics.Canvas) {
        if (panel.isEmpty) return
        val save = canvas.save()
        canvas.clipPath(panelPath)
        bgDrawable.setBounds(panel)
        bgDrawable.draw(canvas)
        drawWallpaper(canvas)
        canvas.restoreToCount(save)
        val p = floatPaint ?: return
        // Viền mảnh tách khung khỏi app bên dưới.
        p.style = android.graphics.Paint.Style.STROKE
        p.strokeWidth = theme.dp(1f)
        p.color = theme.withAlpha(theme.barInk, 0.14f)
        canvas.drawPath(panelPath, p)
        // Thanh kéo: vạch giữa + nút ⤓ (gắn lại) đầu phải.
        val hTop = panel.bottom - handlePx
        val cy = hTop + handlePx / 2f
        val cx = panel.exactCenterX()
        p.style = android.graphics.Paint.Style.FILL
        p.color = theme.withAlpha(theme.barInk, 0.38f)
        val half = theme.dp(18f); val th = theme.dp(2f)
        canvas.drawRoundRect(cx - half, cy - th, cx + half, cy + th, th, th, p)
        p.color = theme.withAlpha(theme.barInk, 0.75f)
        ImeIcons.draw(canvas, ImeIcons.DOCK, panel.right - theme.dp(FloatingKeyboard.EXIT_W_DP) / 2f, cy, theme.dp(18f), p)
    }

    override fun drawChild(canvas: android.graphics.Canvas, child: android.view.View, drawingTime: Long): Boolean {
        if (!floating || child === balloon) return super.drawChild(canvas, child, drawingTime)
        val save = canvas.save()
        canvas.clipPath(panelPath)           // phím / strip theo góc bo của khung
        val r = super.drawChild(canvas, child, drawingTime)
        canvas.restoreToCount(save)
        return r
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(event: android.view.MotionEvent): Boolean {
        if (!floating) return super.onTouchEvent(event)
        when (event.actionMasked) {
            android.view.MotionEvent.ACTION_DOWN -> {
                val exitW = Math.round(theme.dp(FloatingKeyboard.EXIT_W_DP))
                dragMode = FloatingKeyboard.handleHit(panel.left, panel.right, panel.bottom - handlePx, panel.bottom,
                    exitW, event.x, event.y)
                if (dragMode < 0) return false
                downRawX = event.rawX; downRawY = event.rawY
                downLeft = panel.left; downTop = panel.top
                return true
            }
            android.view.MotionEvent.ACTION_MOVE -> {
                if (dragMode < 0) return false
                val dx = event.rawX - downRawX; val dy = event.rawY - downRawY
                // Chạm nút ⤓ rồi kéo đi xa ⇒ thành kéo khung.
                if (dragMode == 1 && maxOf(Math.abs(dx), Math.abs(dy)) > theme.dp(12f)) dragMode = 0
                if (dragMode == 0) moveTo(downLeft + Math.round(dx), downTop + Math.round(dy))
                return true
            }
            android.view.MotionEvent.ACTION_UP -> {
                val m = dragMode; dragMode = -1
                if (m == 1) onFloatExit?.invoke()
                else if (m == 0) onFloatMoved?.invoke(floatFx, floatFy)
                return m >= 0
            }
            android.view.MotionEvent.ACTION_CANCEL -> {
                if (dragMode == 0) onFloatMoved?.invoke(floatFx, floatFy)
                dragMode = -1
                return true
            }
        }
        return dragMode >= 0
    }

    private fun moveTo(left: Int, top: Int) {
        val pw = panel.width(); val ph = panel.height()
        val fx = FloatingKeyboard.fraction(left, 0, width, pw)
        val fy = FloatingKeyboard.fraction(top, statusTop, height - navInset, ph)
        if (fx == floatFx && fy == floatFy) return
        floatFx = fx; floatFy = fy
        requestLayout(); invalidate()
    }

    private fun layoutFloating(w: Int, h: Int) {
        val s = stripPx()
        val keyH = keyboard.measuredHeight
        val pw = keyboard.measuredWidth
        val ph = FloatingKeyboard.panelHeight(s, keyH, handlePx)
        val px = FloatingKeyboard.place(floatFx, 0, w, pw)
        val py = FloatingKeyboard.place(floatFy, statusTop, h - navInset, ph)
        if (panel.left != px || panel.top != py || panel.right != px + pw || panel.bottom != py + ph) {
            panel.set(px, py, px + pw, py + ph)
            panelPath.reset()
            val r = theme.dp(FloatingKeyboard.RADIUS_DP)
            panelPath.addRoundRect(px.toFloat(), py.toFloat(), (px + pw).toFloat(), (py + ph).toFloat(), r, r,
                android.graphics.Path.Direction.CW)
        }
        keyboard.layout(px, py + s, px + pw, py + s + keyH)
        rainbow?.layout(px, py + s, px + pw, py + s + keyH)
        updateDecorGaps()
        updateRainbowOutline()
        strip.layout(px, py, px + pw, py + strip.measuredHeight)
        trail.layout(px, py + s, px + pw, py + s + keyH)
        foreground?.layout(px, py, px + pw, py + s + keyH)
        overlay?.layout(px, py + s, px + pw, py + s + keyH)
        // Balloon: x theo khung (toạ độ phím), y theo view gốc (KeyboardView cộng `top` của nó)
        // ⇒ trùm từ đỉnh cửa sổ tới đáy vùng phím: preview / popup hàng trên nổi ra ngoài khung.
        balloon.layout(px, 0, px + pw, py + s + keyH)
        effects?.layout(px, 0, px + pw, py + s + keyH)
        layoutBuddy(px, py, pw, s)
        updateStringGaps()
        mole?.layout(px, 0, px + pw, py + s + keyH)
        if (wallpaperFile != null && (wallW != pw || wallH != ph)) loadWallpaperFor(pw, ph) else updateWallMatrix()
        loadThemeBgFor(pw, ph)
    }
    /**
     * "Hiệu ứng khi bấm phím" ([KeyEffectView], Plus) — cùng khung với balloon. Dải trên phím: ngay DƯỚI
     * balloon; dải dưới phím (Matrix / Mực loang / Sóng nước): ngay TRƯỚC KeyboardView — trên nền + ảnh nền
     * (vẽ trong onDraw của view này), dưới phím. null = tắt (mặc định: không có view, 0 chi phí). IME
     * gắn/gỡ mỗi lần hiện (cấu hình kiểu TRƯỚC khi gán để biết dải).
     */
    var effects: KeyEffectView? = null
        set(v) {
            if (field === v && (v == null || effectsBand == v.effect.band)) return
            field?.let { removeView(it) }
            field = v
            if (v != null) {
                effectsBand = v.effect.band
                addView(v, com.viettelex.keyboard.KeyEffectBand.insertIndex(effectsBand, indexOfChild(keyboard), indexOfChild(balloon)))
            }
        }
    private var effectsBand = com.viettelex.keyboard.KeyEffectBand.ABOVE_KEYS

    /**
     * "Bạn đồng hành" ([BuddyView], Plus) — ô ngay trái ⌄ trong strip (StripView chừa [StripView.buddyDp]), tràn
     * xuống hàng phím đầu (vẽ trên phím, không nhận chạm). null = tắt (mặc định: không view, 0 chi phí).
     */
    var buddy: BuddyView? = null
        set(v) {
            if (field === v) return
            field?.let { it.halt(); removeView(it) }
            field = v
            if (v != null) {
                addView(v)                          // trên cùng: không bị phím / balloon / hiệu ứng đè hay chèn
                v.outlineProvider = null; v.translationZ = 1000f
            }
            strip.onBuddySlot = if (v == null) null else ({ v.shownInSlot = strip.buddySlotShown() })
            requestLayout()
        }

    /** "Vị trí & cỡ" ([BuddyPlacement], chung mọi nhân vật) — IME đặt lúc hiện; đổi ⇒ layout lại (không dựng view). */
    var buddyPlacement = com.viettelex.keyboard.BuddyPlacement.STANDARD
        set(v) { if (field != v) { field = v; requestLayout() } }

    /** Khung ô nhân vật (px, gốc = khung bàn phím): sát mép phải, cao = strip + phần tràn xuống phím; cỡ / lề neo đáy-phải. */
    private fun layoutBuddy(px: Int, py: Int, pw: Int, s: Int) {
        val b = buddy ?: return
        val r = px + pw
        val l = r - Math.round(theme.dp(StripGeometry.BUDDY_W))
        val h = StripGeometry.buddyHeight(s)
        val w = StripGeometry.buddyDrawWidth(s, r - l)
        val bl = minOf((l + r - w) / 2, px + pw - w)
        val f = buddyPlacement.frame(com.viettelex.keyboard.BuddyRect(bl, py, w, h), (r - l).toDouble(), theme.dp(1f).toDouble())
        val fl = Math.round(f.x).toInt(); val ft = Math.round(f.y).toInt()
        val fw = Math.round(f.w).toInt(); val fh = Math.round(f.h).toInt()
        b.measure(MeasureSpec.makeMeasureSpec(fw, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(fh, MeasureSpec.EXACTLY))
        b.layout(fl, ft, fl + fw, ft + fh)
        b.shownInSlot = strip.buddySlotShown() && s > 0
    }

    /**
     * Đập chuột ([MoleView], theme có "game":"mole") — cùng khung với balloon, ngay DƯỚI balloon (trên phím +
     * hiệu ứng), không nhận chạm. null = theme khác (không có view, 0 chi phí). IME gắn/gỡ mỗi lần hiện.
     */
    var mole: MoleView? = null
        set(v) {
            if (field === v) return
            field?.let { it.halt(); removeView(it) }
            field = v
            if (v != null) addView(v, indexOfChild(balloon))
        }

    /** Bảng phủ đúng vùng phím (lịch sử clipboard); null = không có. Thêm lười khi mở lần đầu. */
    var overlay: android.view.View? = null
        set(v) {
            if (field === v) return
            field?.let { removeView(it) }
            field = v
            if (v != null) addView(v, indexOfChild(balloon))
        }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        if (floating) { measureFloating(widthMeasureSpec, heightMeasureSpec); return }
        val w = MeasureSpec.getSize(widthMeasureSpec)
        val keyH = keyboard.keyAreaPx.roundToInt()
        val s = stripPx()
        val h = ImeInsets.totalHeight(s, keyH, navInset + raisePx)
        keyboard.measure(MeasureSpec.makeMeasureSpec(w, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(keyH, MeasureSpec.EXACTLY))
        rainbow?.measure(MeasureSpec.makeMeasureSpec(w, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(keyH, MeasureSpec.EXACTLY))
        strip.measure(MeasureSpec.makeMeasureSpec(w, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(strip.viewHeightPx(), MeasureSpec.EXACTLY))
        trail.measure(MeasureSpec.makeMeasureSpec(w, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(keyH, MeasureSpec.EXACTLY))
        foreground?.measure(MeasureSpec.makeMeasureSpec(w, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(s + keyH, MeasureSpec.EXACTLY))
        overlay?.measure(MeasureSpec.makeMeasureSpec(w, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(keyH, MeasureSpec.EXACTLY))
        balloon.measure(MeasureSpec.makeMeasureSpec(w, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(s + keyH, MeasureSpec.EXACTLY))
        effects?.measure(MeasureSpec.makeMeasureSpec(w, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(s + keyH, MeasureSpec.EXACTLY))
        mole?.measure(MeasureSpec.makeMeasureSpec(w, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(s + keyH, MeasureSpec.EXACTLY))
        setMeasuredDimension(w, h)
    }

    /** Thả nổi: view gốc chiếm hết chiều cao được cấp (cửa sổ IME ≈ cả màn hình), con theo khung. */
    private fun measureFloating(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val w = MeasureSpec.getSize(widthMeasureSpec)
        val avail = if (MeasureSpec.getMode(heightMeasureSpec) == MeasureSpec.UNSPECIFIED)
            resources.displayMetrics.heightPixels else MeasureSpec.getSize(heightMeasureSpec)
        val keyH = keyboard.keyAreaPx.roundToInt()
        val s = stripPx()
        val pw = FloatingKeyboard.panelWidth(w, theme.tablet, theme.landscape)
        val h = maxOf(avail, FloatingKeyboard.panelHeight(s, keyH, handlePx))
        val ew = MeasureSpec.makeMeasureSpec(pw, MeasureSpec.EXACTLY)
        keyboard.measure(ew, MeasureSpec.makeMeasureSpec(keyH, MeasureSpec.EXACTLY))
        rainbow?.measure(ew, MeasureSpec.makeMeasureSpec(keyH, MeasureSpec.EXACTLY))
        strip.measure(ew, MeasureSpec.makeMeasureSpec(strip.viewHeightPx(), MeasureSpec.EXACTLY))
        trail.measure(ew, MeasureSpec.makeMeasureSpec(keyH, MeasureSpec.EXACTLY))
        foreground?.measure(ew, MeasureSpec.makeMeasureSpec(s + keyH, MeasureSpec.EXACTLY))
        overlay?.measure(ew, MeasureSpec.makeMeasureSpec(keyH, MeasureSpec.EXACTLY))
        balloon.measure(ew, MeasureSpec.makeMeasureSpec(h, MeasureSpec.EXACTLY))
        effects?.measure(ew, MeasureSpec.makeMeasureSpec(h, MeasureSpec.EXACTLY))
        mole?.measure(ew, MeasureSpec.makeMeasureSpec(h, MeasureSpec.EXACTLY))
        setMeasuredDimension(w, h)
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        if (floating) { layoutFloating(r - l, b - t); return }
        val w = r - l
        val s = stripPx()
        val keyH = keyboard.measuredHeight
        keyboard.layout(0, s, w, s + keyH)
        rainbow?.layout(0, s, w, s + keyH)
        updateDecorGaps()
        updateRainbowOutline()
        strip.layout(0, 0, w, strip.measuredHeight)
        trail.layout(0, s, w, s + keyH)
        foreground?.layout(0, 0, w, s + keyH)
        overlay?.layout(0, s, w, s + keyH)
        balloon.layout(0, 0, w, s + keyH)
        effects?.layout(0, 0, w, s + keyH)
        layoutBuddy(0, 0, w, s)
        updateStringGaps()
        mole?.layout(0, 0, w, s + keyH)
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
        val top: Int
        if (Build.VERSION.SDK_INT >= 30) {
            nav = insets.getInsets(WindowInsets.Type.navigationBars()).bottom
            tap = insets.getInsets(WindowInsets.Type.tappableElement()).bottom
            top = insets.getInsets(WindowInsets.Type.statusBars() or WindowInsets.Type.displayCutout()).top
        } else {
            nav = insets.systemWindowInsetBottom
            tap = if (Build.VERSION.SDK_INT >= 29) insets.tappableElementInsets.bottom else 0
            top = insets.systemWindowInsetTop
        }
        // Thả nổi: khung không chui dưới thanh trạng thái (cửa sổ tràn lên đỉnh màn hình).
        if (top != statusTop) { statusTop = maxOf(top, 0); if (floating) requestLayout() }
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
