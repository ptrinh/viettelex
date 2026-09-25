package com.viettelex.android.ime

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.os.SystemClock
import android.view.MotionEvent
import android.view.View
import android.view.animation.DecelerateInterpolator
import com.viettelex.android.R
import com.viettelex.keyboard.Key
import com.viettelex.keyboard.KeyCommitQueue
import com.viettelex.keyboard.TemplateItem
import com.viettelex.keyboard.TouchGeometry
import com.viettelex.keyboard.TouchLog
import kotlin.math.abs

/**
 * Vùng PHÍM của bàn phím (port iOS KeyboardView, phần rows): MỘT View vẽ mọi phím
 * bằng Canvas và là MỘT mặt touch multi-pointer (spec §5). Strip gợi ý và balloon là
 * view anh em riêng ([StripView], [BalloonView]) để gõ chữ KHÔNG ghi lại display
 * list của ~40 phím: phím chữ không đổi hình khi bấm (balloon lo), nên chỉ overlay
 * balloon bị invalidate — lớp phím chỉ vẽ lại khi shift / plane / pressed phím chức
 * năng đổi.
 *
 * Không Handler/timer nào chạy khi không có ngón trên phím (0% CPU idle).
 */
@SuppressLint("ViewConstructor")
class KeyboardView(
    context: Context,
    private val theme: ImeTheme,
    private val balloon: BalloonView,
    private val feedback: Feedback,
) : View(context) {

    interface Listener {
        fun onKey(key: Key)
        /** Giữ ⌫ > 3 s — xoá theo từ. */
        fun onDeleteWord()
        fun onGlobe(longPress: Boolean)
        fun onDismissKeyboard()
        fun onTemplate(item: TemplateItem)
        fun onOpenTemplates()
        fun onPlaneChanged(plane: Plane)
        /** Recents emoji (đọc/ghi pref). */
        fun emojiRecents(): List<String>
        fun noteEmojiUsed(e: String)
    }

    var listener: Listener? = null

    enum class Shift { OFF, ON, CAPS }

    // --- cấu hình (đặt bởi IME mỗi lần hiện; rebuild khi chữ ký đổi) ---
    var plane = Plane.LETTERS; private set
    var shift = Shift.ON; private set
    private var returnLabel = "return"
    private var inputKind = InputKind.NORMAL
    private var needsGlobe = false
    private var showLogo = true
    private var templatesEnabled = true
    private var templates: List<TemplateItem> = emptyList()
    var keyAreaPx = theme.dp(218f); private set

    private var keys: List<LaidKey> = emptyList()
    private var builtSig = ""
    private val planeCache = HashMap<Plane, List<LaidKey>>()

    private val commits = KeyCommitQueue()
    private var lastShiftTap = 0L
    private var lastSpaceTap = 0L

    // --- pointer → phím (id pointer ≤ 31) ---
    private val ptrKey = arrayOfNulls<LaidKey>(MAX_PTR)
    private val ptrDownX = FloatArray(MAX_PTR)
    private val ptrDownY = FloatArray(MAX_PTR)
    /** Pointer đang thuộc pane emoji/mẫu câu thay vì phím. */
    private val ptrPane = BooleanArray(MAX_PTR)
    private var balloonOwner: LaidKey? = null

    // --- paint (tạo 1 lần) ---
    private val d = theme.density
    private val radius = theme.dp(KeyLayout.KEY_RADIUS)
    private val facePaint = theme.fill(theme.keyFill)
    // Gboard: chữ 22 sp regular, nhãn chức năng 14 sp medium (font hệ thống sans-serif)
    private val letterPaint = theme.text(22f)
    private val controlPaint = theme.text(14f, medium = true)
    private val comPaint = theme.text(16f)
    private val badgePaint = theme.text(14f, medium = true)
    private val iconPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = theme.ink }
    private val letterOff = theme.centerOffset(letterPaint)
    private val controlOff = theme.centerOffset(controlPaint)
    private val comOff = theme.centerOffset(comPaint)
    private val keyPressed = theme.pressed(theme.keyFill)
    private val specialPressed = theme.pressed(theme.specialFill)
    private val actionPressed = theme.blend(theme.action, theme.actionInk, 0.12f)
    // Logo Vᴛ mờ ở góc phải phím space như iOS (thay nhãn "Tiếng Việt").
    private val logoPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply {
        colorFilter = android.graphics.PorterDuffColorFilter(theme.withAlpha(theme.ink, 0.16f), android.graphics.PorterDuff.Mode.SRC_IN)
    }
    private val logo: android.graphics.Bitmap? by lazy { android.graphics.BitmapFactory.decodeResource(resources, R.drawable.ime_space_logo) }
    private val logoRect = android.graphics.RectF()

    private val emojiPane = EmojiPane(this, theme, feedback)
    private val templatesPane = TemplatesPane(this, theme, feedback)

    // --- trackpad / giữ phím ---
    private var trackpad = false
    private var spaceKey: LaidKey? = null
    private var spaceHoldX = 0f
    private var spacePtr = -1
    private var bsPtr = -1
    private var bsHoldStart = 0L
    private var bsTick = 0
    private var bsRepeating = false
    private var globePtr = -1
    private var globeFired = false
    private val slop = theme.dp(10f)   // allowableMovement của UILongPressGestureRecognizer

    private val spaceHoldRun = Runnable { beginTrackpad() }
    private val bsStartRun = Runnable {
        bsRepeating = true; bsHoldStart = SystemClock.uptimeMillis(); bsTick = 0
        postDelayed(bsTickRun, BS_INTERVAL)
    }
    private val bsTickRun = object : Runnable {
        override fun run() {
            val held = SystemClock.uptimeMillis() - bsHoldStart
            if (held > 3000) {
                bsTick++
                if (bsTick % 4 == 1) listener?.onDeleteWord()
            } else {
                listener?.onKey(Key.Backspace)
                if (held > 1600) listener?.onKey(Key.Backspace)
            }
            postDelayed(this, BS_INTERVAL)
        }
    }
    private val globeLongRun = Runnable { globeFired = true; listener?.onGlobe(true) }

    // --- badge "ViệtTelex" ---
    private var badgeAlpha = 0f
    private var badgeAnim: ValueAnimator? = null
    private val badgeText = context.getString(R.string.ime_badge)

    private val spaceFire: () -> Unit = {
        val now = SystemClock.uptimeMillis()
        listener?.onKey(if (now - lastSpaceTap < DOUBLE_SPACE_MS) Key.DoubleSpacePeriod else Key.Space)
        lastSpaceTap = now
    }
    private val newlineFire: () -> Unit = { listener?.onKey(Key.Newline) }
    private val textFires = HashMap<String, () -> Unit>()
    private fun textFire(s: String) = textFires.getOrPut(s) { val k = Key.Text(s); { listener?.onKey(k) } }

    init {
        isHapticFeedbackEnabled = true
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    // MARK: cấu hình

    fun configure(returnLabel: String, kind: InputKind, needsGlobe: Boolean, showLogo: Boolean,
                  templatesEnabled: Boolean, templates: List<TemplateItem>, keyAreaPx: Float) {
        this.returnLabel = returnLabel
        this.needsGlobe = needsGlobe
        this.showLogo = showLogo
        this.templatesEnabled = templatesEnabled
        this.templates = templates
        if (this.keyAreaPx != keyAreaPx) { this.keyAreaPx = keyAreaPx; requestLayout() }
        // Loại ô: số ⇒ plane 123; chữ ⇒ shift ON (nếu có) rớt về OFF như iOS configureInputKind.
        inputKind = kind
        plane = if (kind == InputKind.NUMBER) Plane.NUMBERS else Plane.LETTERS
        if (plane == Plane.LETTERS && shift == Shift.ON) shift = Shift.OFF
        templatesPane.setItems(templates)
        rebuild()
        listener?.onPlaneChanged(plane)
    }

    fun setNeedsGlobe(on: Boolean) {
        if (on == needsGlobe) return
        needsGlobe = on
        rebuild()
    }

    /** Auto-shift đầu câu: chỉ nâng OFF→ON, không bao giờ hạ CAPS. */
    fun setAutoShift(on: Boolean) {
        if (shift == Shift.CAPS) return
        val want = if (on) Shift.ON else Shift.OFF
        if (shift != want) { shift = want; if (plane == Plane.LETTERS) invalidate() }
    }

    fun setPlane(p: Plane) {
        if (p == Plane.TEMPLATES && !templatesEnabled) return
        if (plane == p) return
        plane = p
        if (p == Plane.LETTERS && shift == Shift.ON) shift = Shift.OFF
        if (p == Plane.EMOJI) emojiPane.open(listener?.emojiRecents() ?: emptyList())
        if (p == Plane.TEMPLATES) templatesPane.resetScroll()
        rebuild()
        listener?.onPlaneChanged(p)
    }

    fun toggleTemplates() {
        if (!templatesEnabled) return
        setPlane(if (plane == Plane.TEMPLATES) Plane.LETTERS else Plane.TEMPLATES)
    }

    private fun signature() = "$returnLabel|$inputKind|$needsGlobe|$width|$keyAreaPx"

    private fun rebuild() {
        if (width == 0) return
        val sig = signature()
        if (sig != builtSig) { planeCache.clear(); builtSig = sig }
        keys = planeCache.getOrPut(plane) {
            KeyLayout.build(LayoutConfig(plane, width.toFloat(), keyAreaPx, d, inputKind, needsGlobe,
                theme.tablet, returnLabel))
        }
        spaceKey = keys.firstOrNull { it.kind == KeyKind.SPACE }
        spaceKey?.let {
            val sz = theme.dp(22f)
            logoRect.set(it.right - theme.dp(10f) - sz, it.centerY - sz / 2, it.right - theme.dp(10f), it.centerY + sz / 2)
        }
        val paneBottom = if (plane == Plane.TEMPLATES) keyAreaPx - keyAreaPx / 4f else keyAreaPx
        templatesPane.layout(width.toFloat(), paneBottom)
        emojiPane.layout(width.toFloat(), keyAreaPx)
        invalidate()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        setMeasuredDimension(MeasureSpec.getSize(widthMeasureSpec), Math.round(keyAreaPx))
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        rebuild()
    }

    /** Bàn phím ẩn: dọn mọi pointer/timer — không để Handler nào sống. */
    fun onHidden() {
        cancelAllTouches()
        badgeAnim?.cancel(); badgeAlpha = 0f
        emojiPane.onHidden()
        templatesPane.onHidden()
    }

    // MARK: badge ngôn ngữ

    /** "ViệtTelex" giữa space 0.7 s rồi fade 0.3 s; logo Vᴛ ẩn trong lúc đó. */
    fun showLanguageBadge() {
        badgeAnim?.cancel()
        badgeAlpha = 1f
        badgeAnim = ValueAnimator.ofFloat(1f, 0f).apply {
            startDelay = 700; duration = 300
            interpolator = DecelerateInterpolator()
            addUpdateListener { badgeAlpha = it.animatedValue as Float; invalidateSpace() }
            start()
        }
        invalidateSpace()
    }

    private fun invalidateSpace() {
        val k = spaceKey ?: return
        @Suppress("DEPRECATION")
        invalidate(k.left.toInt(), k.top.toInt(), k.right.toInt() + 1, k.bottom.toInt() + 1)
    }

    @Suppress("DEPRECATION")
    private fun invalidateKey(k: LaidKey) =
        invalidate(k.left.toInt() - 1, k.top.toInt() - 1, k.right.toInt() + 1, k.bottom.toInt() + 1)

    // MARK: vẽ

    override fun onDraw(c: Canvas) {
        when (plane) {
            Plane.EMOJI -> { emojiPane.draw(c); return }
            Plane.TEMPLATES -> templatesPane.draw(c)
            else -> Unit
        }
        val ks = keys
        for (i in ks.indices) drawKey(c, ks[i])
    }

    private fun drawKey(c: Canvas, k: LaidKey) {
        // Gboard: phím phẳng bo góc, KHÔNG bóng; phím chức năng tô màu phụ (secondary
        // container); enter là pill màu nhấn. Nhấn = state layer ink 12%.
        val special = KeyKind.isSpecial(k.kind) && k.kind != KeyKind.RETURN
        var face = when {
            k.kind == KeyKind.RETURN -> if (k.pressed) actionPressed else theme.action
            k.kind == KeyKind.SHIFT && shift == Shift.CAPS -> theme.chip
            special -> if (k.pressed) specialPressed else theme.specialFill
            k.kind == KeyKind.LETTER || k.kind == KeyKind.CHAR -> theme.keyFill   // popup lo phản hồi
            else -> if (k.pressed) keyPressed else theme.keyFill
        }
        if (trackpad) face = theme.keyFill
        facePaint.color = face
        val r = if (k.kind == KeyKind.RETURN) minOf(k.width, k.height) / 2 else radius
        c.drawRoundRect(k.left, k.top, k.right, k.bottom, r, r, facePaint)

        val contentAlpha = if (trackpad) 51 else 255   // 0.2
        val cx = k.centerX; val cy = k.centerY
        when (k.kind) {
            KeyKind.LETTER -> drawLabel(c, if (shift == Shift.OFF) k.label else k.upper, cx, cy, letterPaint, letterOff, contentAlpha)
            KeyKind.CHAR -> drawLabel(c, k.label, cx, cy, letterPaint, letterOff, contentAlpha)
            KeyKind.PUNCT -> if (k.label == ".com") drawLabel(c, k.label, cx, cy, comPaint, comOff, contentAlpha)
                             else drawLabel(c, k.label, cx, cy, letterPaint, letterOff, contentAlpha)
            KeyKind.PLANE, KeyKind.MORE -> drawLabel(c, k.label, cx, cy, controlPaint, controlOff, contentAlpha)
            KeyKind.SHIFT -> {
                val id = when (shift) { Shift.CAPS -> ImeIcons.CAPS; Shift.ON -> ImeIcons.SHIFT_FILL; Shift.OFF -> ImeIcons.SHIFT }
                icon(c, id, cx, cy, 22f, theme.ink, contentAlpha)
            }
            KeyKind.BACKSPACE -> if (k.pressed && !trackpad) {
                icon(c, ImeIcons.DELETE_FILL, cx, cy, 22f, theme.ink, contentAlpha)
                icon(c, ImeIcons.DELETE_X, cx, cy, 22f, face, 255)
            } else icon(c, ImeIcons.DELETE, cx, cy, 22f, theme.ink, contentAlpha)
            KeyKind.GLOBE -> icon(c, ImeIcons.GLOBE, cx, cy, 21f, theme.ink, contentAlpha)
            KeyKind.EMOJI -> icon(c, ImeIcons.FACE, cx, cy, 22f, theme.ink, contentAlpha)
            KeyKind.CLEAR -> icon(c, ImeIcons.TRASH, cx, cy, 21f, theme.ink, contentAlpha)
            KeyKind.DISMISS -> icon(c, ImeIcons.KB_DISMISS, cx, cy, 22f, theme.ink, contentAlpha)
            KeyKind.RETURN -> {
                val id = when (returnLabel) {
                    "search" -> ImeIcons.SEARCH
                    "send" -> ImeIcons.SEND
                    "done" -> ImeIcons.CHECK
                    "go", "next" -> ImeIcons.ARROW_RIGHT
                    else -> ImeIcons.RETURN
                }
                icon(c, id, cx, cy, 22f, theme.actionInk, contentAlpha)
            }
            KeyKind.SPACE -> {
                // Badge "ViệtTelex" lúc hiện rồi mờ dần về logo Vᴛ (như iOS).
                if (badgeAlpha > 0f) {
                    badgePaint.alpha = (badgeAlpha * contentAlpha).toInt()
                    c.drawText(badgeText, cx, cy + badgeOff, badgePaint)
                }
                if (showLogo && badgeAlpha < 1f) {
                    val bmp = logo
                    if (bmp != null) {
                        logoPaint.alpha = ((1f - badgeAlpha) * contentAlpha).toInt()
                        c.drawBitmap(bmp, null, logoRect, logoPaint)
                    }
                }
            }
        }
    }

    private val badgeOff = theme.centerOffset(badgePaint)

    private fun drawLabel(c: Canvas, s: String, cx: Float, cy: Float, p: Paint, off: Float, alpha: Int) {
        p.alpha = alpha
        c.drawText(s, cx, cy + off, p)
    }

    private fun icon(c: Canvas, id: Int, cx: Float, cy: Float, sizeDp: Float, color: Int, alpha: Int) {
        iconPaint.color = color
        iconPaint.alpha = (android.graphics.Color.alpha(color) * alpha) / 255
        ImeIcons.draw(c, id, cx, cy, sizeDp * d, iconPaint)
    }

    // MARK: touch

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(e: MotionEvent): Boolean {
        if (plane == Plane.EMOJI) emojiPane.track(e) else if (plane == Plane.TEMPLATES) templatesPane.track(e)
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                val i = e.actionIndex
                down(e.getPointerId(i), e.getX(i), e.getY(i), e)
            }
            MotionEvent.ACTION_MOVE -> for (i in 0 until e.pointerCount) move(e.getPointerId(i), e.getX(i), e.getY(i))
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> {
                val i = e.actionIndex
                up(e.getPointerId(i), e.getX(i), e.getY(i), cancelled = false)
            }
            MotionEvent.ACTION_CANCEL -> for (i in 0 until e.pointerCount)
                up(e.getPointerId(i), e.getX(i), e.getY(i), cancelled = true)
        }
        return true
    }

    private fun down(pid: Int, x: Float, y: Float, e: MotionEvent) {
        if (pid !in 0 until MAX_PTR) return
        ptrDownX[pid] = x; ptrDownY[pid] = y
        if (plane == Plane.EMOJI) { commits.flush(); ptrPane[pid] = true; emojiPane.down(pid, x, y); return }
        if (plane == Plane.TEMPLATES && templatesPane.contains(x, y)) {
            commits.flush(); ptrPane[pid] = true; templatesPane.down(pid, x, y); return
        }
        val k = KeyLayout.hit(keys, plane, x, y, TouchGeometry.yOffset * d, d)
        if (TouchLog.enabled) {
            val lag = (SystemClock.uptimeMillis() - e.eventTime).toDouble()
            TouchLog.touchBegan(activeCount(), e.pointerCount, lag, k != null, (y / d).toDouble(),
                k?.let { if (it.kind == KeyKind.LETTER) it.label else null })
        }
        if (k == null) return
        // ĐẦU TIÊN: chốt các phím nhấc-mới-chốt đang đè (thứ tự khi gõ chồng ngón).
        commits.flush(k)
        ptrKey[pid] = k
        when (k.kind) {
            KeyKind.LETTER -> {
                feedback.click(Feedback.LETTER, this)
                showBalloon(k, if (shift == Shift.OFF) k.label else k.upper)
                val ch = (if (shift == Shift.OFF) k.label else k.upper)[0]
                listener?.onKey(Key.Letter(ch))
                if (shift == Shift.ON) { shift = Shift.OFF; invalidate() }
            }
            KeyKind.CHAR -> {
                feedback.click(Feedback.LETTER, this)
                showBalloon(k, k.label)
                commits.arm(k, textFire(k.insert))
            }
            KeyKind.PUNCT -> {
                feedback.click(Feedback.LETTER, this)
                press(k)
                commits.arm(k, textFire(k.insert))
            }
            KeyKind.SPACE -> {
                feedback.click(Feedback.SPACE, this)
                press(k)
                commits.arm(k, spaceFire)
                spacePtr = pid
                removeCallbacks(spaceHoldRun)
                postDelayed(spaceHoldRun, SPACE_HOLD_MS)
            }
            KeyKind.RETURN -> {
                feedback.click(Feedback.RETURN, this)
                press(k)
                commits.arm(k, newlineFire)
            }
            KeyKind.SHIFT -> {
                feedback.click(Feedback.MODIFIER, this)
                val now = SystemClock.uptimeMillis()
                shift = if (now - lastShiftTap < SHIFT_DOUBLE_MS) Shift.CAPS
                        else if (shift == Shift.OFF) Shift.ON else Shift.OFF
                lastShiftTap = now
                k.pressed = true
                invalidate()   // mọi nhãn chữ đổi hoa/thường
            }
            KeyKind.BACKSPACE -> {
                feedback.click(Feedback.DELETE, this)
                press(k)
                listener?.onKey(Key.Backspace)
                bsPtr = pid; bsRepeating = false
                removeCallbacks(bsStartRun); removeCallbacks(bsTickRun)
                postDelayed(bsStartRun, BS_HOLD_MS)
            }
            KeyKind.GLOBE -> {
                feedback.click(Feedback.MODIFIER, this)
                press(k)
                globePtr = pid; globeFired = false
                removeCallbacks(globeLongRun)
                postDelayed(globeLongRun, GLOBE_HOLD_MS)
            }
            else -> {   // PLANE, MORE, EMOJI, CLEAR, DISMISS: hành động lúc nhấc
                feedback.click(Feedback.MODIFIER, this)
                press(k)
            }
        }
    }

    private fun move(pid: Int, x: Float, y: Float) {
        if (pid !in 0 until MAX_PTR) return
        if (ptrPane[pid]) {
            if (plane == Plane.EMOJI) emojiPane.move(pid, x, y) else templatesPane.move(pid, x, y)
            return
        }
        val k = ptrKey[pid] ?: return
        val movedFar = abs(x - ptrDownX[pid]) > slop || abs(y - ptrDownY[pid]) > slop
        when {
            k.kind == KeyKind.SPACE && pid == spacePtr -> {
                if (trackpad) {
                    val delta = ((x - spaceHoldX) / (TRACKPAD_STEP_DP * d)).toInt()
                    if (delta != 0) {
                        listener?.onKey(Key.MoveCursor(delta))
                        spaceHoldX = x
                    }
                } else if (movedFar) removeCallbacks(spaceHoldRun)
            }
            k.kind == KeyKind.BACKSPACE && pid == bsPtr && !bsRepeating && movedFar -> removeCallbacks(bsStartRun)
        }
    }

    private fun up(pid: Int, x: Float, y: Float, cancelled: Boolean) {
        if (pid !in 0 until MAX_PTR) return
        if (ptrPane[pid]) {
            ptrPane[pid] = false
            if (plane == Plane.EMOJI) emojiPane.up(pid, x, y, cancelled)
            else if (plane == Plane.TEMPLATES) templatesPane.up(pid, x, y, cancelled)
            return
        }
        val k = ptrKey[pid] ?: run { if (TouchLog.enabled) TouchLog.touchEnded(cancelled, false); return }
        ptrKey[pid] = null
        if (TouchLog.enabled) TouchLog.touchEnded(cancelled, true)
        when (k.kind) {
            KeyKind.LETTER -> hideBalloon(k)
            KeyKind.CHAR -> { hideBalloon(k); commits.release(k) }
            KeyKind.PUNCT, KeyKind.RETURN -> commits.release(k)
            KeyKind.SPACE -> {
                if (pid == spacePtr) {
                    removeCallbacks(spaceHoldRun); spacePtr = -1
                    // Cancel VẪN chốt (KeyCommitQueue); trackpad đã disarm nên không có space.
                    commits.release(k)
                    if (trackpad) endTrackpad()
                } else commits.release(k)
            }
            KeyKind.BACKSPACE -> if (pid == bsPtr) {
                removeCallbacks(bsStartRun); removeCallbacks(bsTickRun)
                bsPtr = -1; bsRepeating = false
            }
            KeyKind.GLOBE -> if (pid == globePtr) {
                removeCallbacks(globeLongRun); globePtr = -1
                if (!globeFired && !cancelled) listener?.onGlobe(false)
            }
            KeyKind.SHIFT -> Unit
            else -> if (!cancelled) controlAction(k)
        }
        if (k.pressed) { k.pressed = false; if (k.kind == KeyKind.SHIFT) invalidate() else invalidateKey(k) }
    }

    private fun controlAction(k: LaidKey) {
        when (k.kind) {
            KeyKind.PLANE -> setPlane(if (plane == Plane.LETTERS) Plane.NUMBERS else Plane.LETTERS)
            KeyKind.MORE -> setPlane(if (plane == Plane.NUMBERS) Plane.SYMBOLS else Plane.NUMBERS)
            KeyKind.EMOJI -> setPlane(Plane.EMOJI)
            KeyKind.CLEAR -> listener?.onKey(Key.ClearField)
            KeyKind.DISMISS -> listener?.onDismissKeyboard()
        }
    }

    private fun press(k: LaidKey) { k.pressed = true; invalidateKey(k) }

    private fun activeCount(): Int { var n = 0; for (k in ptrKey) if (k != null) n++; return n }

    private fun cancelAllTouches() {
        for (i in 0 until MAX_PTR) {
            ptrKey[i]?.pressed = false
            ptrKey[i] = null; ptrPane[i] = false
        }
        commits.flush()
        removeCallbacks(spaceHoldRun); removeCallbacks(bsStartRun); removeCallbacks(bsTickRun)
        removeCallbacks(globeLongRun)
        spacePtr = -1; bsPtr = -1; globePtr = -1; bsRepeating = false
        if (trackpad) endTrackpad()
        balloon.hide(); balloonOwner = null
        invalidate()
    }

    // MARK: trackpad

    private fun beginTrackpad() {
        val k = spaceKey ?: return
        if (spacePtr < 0) return
        trackpad = true
        spaceHoldX = lastPointerX(spacePtr)
        balloon.hide(); balloonOwner = null
        // Nhả ra KHÔNG có dấu cách (stock), kể cả khi chưa di con trỏ.
        commits.disarm(k)
        invalidate()
    }

    private var lastX = FloatArray(MAX_PTR)
    private fun lastPointerX(pid: Int) = lastX[pid]

    override fun dispatchTouchEvent(e: MotionEvent): Boolean {
        for (i in 0 until e.pointerCount) {
            val id = e.getPointerId(i)
            if (id in 0 until MAX_PTR) lastX[id] = e.getX(i)
        }
        return super.dispatchTouchEvent(e)
    }

    private fun endTrackpad() {
        trackpad = false
        invalidate()
    }

    // MARK: balloon

    private fun showBalloon(k: LaidKey, text: String) {
        balloonOwner = k
        balloon.show(k.left, k.top + top, k.right, k.bottom + top, text)
    }

    private fun hideBalloon(k: LaidKey) {
        if (balloonOwner === k) { balloon.hide(); balloonOwner = null }
    }

    // MARK: pane callbacks

    internal fun paneEmoji(e: String) {
        listener?.noteEmojiUsed(e)
        listener?.onKey(Key.Text(e))
    }
    internal fun paneBackspace() = listener?.onKey(Key.Backspace)
    internal fun paneABC() = setPlane(Plane.LETTERS)
    internal fun paneTemplate(item: TemplateItem) {
        setPlane(Plane.LETTERS)
        listener?.onTemplate(item)
    }
    internal fun paneGear() = listener?.onOpenTemplates()

    override fun computeScroll() {
        if (plane == Plane.EMOJI) emojiPane.computeScroll()
        else if (plane == Plane.TEMPLATES) templatesPane.computeScroll()
    }

    companion object {
        private const val MAX_PTR = 32
        const val DOUBLE_SPACE_MS = 350L
        const val SHIFT_DOUBLE_MS = 300L
        const val SPACE_HOLD_MS = 400L
        const val BS_HOLD_MS = 500L
        const val BS_INTERVAL = 90L
        const val GLOBE_HOLD_MS = 500L
        const val TRACKPAD_STEP_DP = 9f
    }
}
