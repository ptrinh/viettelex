package com.viettelex.android.ime

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.os.SystemClock
import android.view.MotionEvent
import android.view.View
import com.viettelex.keyboard.ComboMeter
import com.viettelex.keyboard.DanceFloor
import com.viettelex.keyboard.EmojiWords
import com.viettelex.keyboard.FlashPulse
import com.viettelex.keyboard.FlyingLetters
import com.viettelex.keyboard.GlitchFx
import com.viettelex.keyboard.KeywordBursts
import com.viettelex.keyboard.KeywordKind
import com.viettelex.keyboard.LaserBeam
import com.viettelex.keyboard.PlasmaArc
import com.viettelex.keyboard.PlasmaChain
import com.viettelex.keyboard.RepsFx
import com.viettelex.keyboard.SandPile
import com.viettelex.keyboard.SeaFx
import com.viettelex.keyboard.ShakeFx
import com.viettelex.keyboard.ShakeMeter
import com.viettelex.keyboard.ToneBurst
import com.viettelex.keyboard.ToneFx
import com.viettelex.keyboard.GlowSprite
import com.viettelex.keyboard.InkBloom
import com.viettelex.keyboard.KeyEffect
import com.viettelex.keyboard.KeyEffectParticles
import com.viettelex.keyboard.LightningBolt
import com.viettelex.keyboard.LightningShards
import com.viettelex.keyboard.MatrixClock
import com.viettelex.keyboard.MatrixRain
import com.viettelex.keyboard.MeteorStreak
import com.viettelex.keyboard.StringPluck
import com.viettelex.keyboard.ShimmerGate
import com.viettelex.keyboard.TokenStream
import com.viettelex.keyboard.ThemeDecoration
import com.viettelex.keyboard.WaveRings

/**
 * Lớp phủ "Hiệu ứng khi bấm phím" (Plus) — song sinh iOS KeyEffectOverlay. MỘT View không nhận chạm.
 * Dải TRÊN phím (đa số kiểu): cùng khung với [BalloonView], ngay DƯỚI nó. Dải DƯỚI phím (Matrix / Mực loang /
 * Sóng nước, [KeyEffect.band]): ImeRootView chèn ngay TRƯỚC KeyboardView (trên nền / ảnh nền vẽ trong
 * onDraw của view gốc, dưới phím).
 *
 * Hiệu năng (gõ mượt là số 1):
 *  • Chỉ tồn tại khi bật (IME gắn/gỡ theo [com.viettelex.keyboard.KeyEffectPolicy]) — tắt ⇒ không có view.
 *  • [burst] chỉ ghi khung phím + `post` MỘT Runnable cấp sẵn: vẽ ở lượt sau, SAU khi phím đã chèn chữ.
 *  • Vẽ: path vector / bitmap dựng sẵn (dải Matrix, emoji, đốm mực — dựng NGOÀI main / một lần) bằng biến
 *    đổi canvas — display list ghi trên UI thread, RenderThread/GPU rasterize. Mảng trạng thái, Path, Paint
 *    cấp sẵn ⇒ không cấp phát mỗi khung hình; hết hiệu ứng thì thôi hẹn khung hình (idle = 0 CPU). Tự đếm
 *    giờ (SystemClock) — tắt hiệu ứng động hệ thống không tắt hiệu ứng phím (Phil 19/10/2026).
 */
@SuppressLint("ViewConstructor")
open class KeyEffectView(context: Context, private val density: Float) : View(context) {
    private val sim = KeyEffectParticles()
    private val paths = Array(3) { Path() }
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
    private val bmpPaint = Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG)
    private val mtx = Matrix()
    private var useFill = true
    private var useStroke = false
    private var fillAlpha = 255
    private var strokeAlpha = 255
    private var color = 0
    private var keyFill = 0xFFFFFFFF.toInt()
    private var dark = false
    private var fillColors = IntArray(0)

    /** Khung chờ (gõ chồng trong cùng lượt) — giữ tối đa [MAX_PENDING] khung mới nhất. */
    private val pendX = FloatArray(MAX_PENDING)
    private val pendY = FloatArray(MAX_PENDING)
    private val pendW = FloatArray(MAX_PENDING)
    private val pendH = FloatArray(MAX_PENDING)
    private var pendN = 0
    private var posted = false
    private val flushRun = Runnable { flush() }

    // Nháy sáng
    private val flash = FlashPulse()
    private var flashStart = Long.MIN_VALUE / 2
    // Lửa combo
    private val combo = ComboMeter()
    // Tia sét — pool 3 cú đánh, Path cấp sẵn
    private val strikeStart = LongArray(STRIKES) { Long.MIN_VALUE / 2 }
    private val strikeX = FloatArray(STRIKES)
    private val strikeY = FloatArray(STRIKES)
    private val boltPaths = Array(STRIKES) { Path() }
    private val glowRects = Array(STRIKES) { RectF() }
    private val shardPaths = Array(STRIKES) { Array(LightningShards.COUNT) { Path() } }
    private val shardCx = Array(STRIKES) { FloatArray(LightningShards.COUNT) }
    private val shardCy = Array(STRIKES) { FloatArray(LightningShards.COUNT) }
    private var strikeCursor = 0
    private var strikeSeq = 0
    private val boltPts = DoubleArray(2 * (LightningBolt.SEGMENTS + 1))
    private val shardCache = HashMap<Int, List<LightningShards.Piece>>()
    // Emoji / mực / sóng — các ô xoay vòng
    private val slotStart = LongArray(SLOTS) { Long.MIN_VALUE / 2 }
    private val slotX = FloatArray(SLOTS)
    private val slotY = FloatArray(SLOTS)
    private val slotBmp = arrayOfNulls<Bitmap>(SLOTS)
    private var slotCursor = 0
    private var pendingEmoji: String? = null
    @Volatile private var emojiBitmaps: Map<String, Bitmap> = emptyMap()
    private var blob: Bitmap? = null
    /** Đèn lồng / Sương ma: một bitmap đốm sáng mỗi màu cố định (dựng lúc đổi kiểu). */
    private var glows: Array<Bitmap> = emptyArray()
    // Rung dây — pool đoạn dây (mảng cấp sẵn, một Path dùng lại); hết 0,3 s thì thôi hẹn khung hình (idle = 0).
    /** Khe hàng phím (px, toạ độ view này) — ImeRootView đặt lúc layout, chỉ khi kiểu là Rung dây. */
    internal var stringGaps: List<ThemeDecoration.Gap> = emptyList()
        private set
    fun setStringGaps(g: List<ThemeDecoration.Gap>) { if (g != stringGaps) stringGaps = g }
    private val strStart = LongArray(StringPluck.POOL) { Long.MIN_VALUE / 2 }
    private val strX = FloatArray(StringPluck.POOL)
    private val strY = FloatArray(StringPluck.POOL)
    private val strLen = FloatArray(StringPluck.POOL)
    private val strWidth = FloatArray(StringPluck.POOL)
    private var strCursor = 0
    private val strPath = Path()
    // Matrix
    internal val matrixClock = MatrixClock()
    @Volatile private var strips: Array<Bitmap>? = null
    private var columns: Array<MatrixRain.Column> = emptyArray()

    // ---- Đợt 3 (11/2026) — mảng cấp sẵn, Path dùng lại; hết hiệu ứng thì thôi hẹn khung hình (idle = 0).
    // Plasma
    private val plasma = PlasmaChain()
    private val arcStart = LongArray(PlasmaArc.POOL) { Long.MIN_VALUE / 2 }
    private val arcLinked = BooleanArray(PlasmaArc.POOL)
    private val arcX = FloatArray(PlasmaArc.POOL)
    private val arcY = FloatArray(PlasmaArc.POOL)
    private val arcPaths = Array(PlasmaArc.POOL) { Path() }
    private val arcPts = DoubleArray(2 * (PlasmaArc.SEGMENTS + 1))
    private var arcCursor = 0
    private var arcSeq = 0
    // Rung combo — dời HÌNH của [shakeTarget] (translationX/Y, RenderThread), xong về 0. Giảm chuyển động vẫn rung.
    /** View hàng phím bị rung (IME đặt = KeyboardView). */
    var shakeTarget: View? = null
        set(v) { if (field !== v) field?.let { it.translationX = 0f; it.translationY = 0f }; field = v }
    private val shakeMeter = ShakeMeter()
    private var shakeStart = Long.MIN_VALUE / 2
    private var shakeAmp = 0f
    // Laser — khung phím cách (toạ độ view này) do IME cấp; không có ⇒ gốc giữa đáy.
    var spaceFrame: ((RectF) -> Boolean)? = null
    private val spaceRect = RectF()
    private val laserStart = LongArray(LaserBeam.POOL) { Long.MIN_VALUE / 2 }
    private val laserOx = FloatArray(LaserBeam.POOL)
    private val laserOy = FloatArray(LaserBeam.POOL)
    private val laserTx = FloatArray(LaserBeam.POOL)
    private val laserTy = FloatArray(LaserBeam.POOL)
    private var laserCursor = 0
    // Glitch
    private val glStart = LongArray(GlitchFx.POOL) { Long.MIN_VALUE / 2 }
    private val glRect = Array(GlitchFx.POOL) { RectF() }
    private val glVariant = IntArray(GlitchFx.POOL)
    private val glSlices = DoubleArray(3 * GlitchFx.SLICES)
    private val glTmp = RectF()
    private var glCursor = 0
    private var glSeq = 0
    // Dấu thanh
    private var pendingTone: ToneFx? = null
    private val toneStart = LongArray(ToneBurst.POOL) { Long.MIN_VALUE / 2 }
    private val toneKind = IntArray(ToneBurst.POOL)
    private val toneX = FloatArray(ToneBurst.POOL)
    private val toneY = FloatArray(ToneBurst.POOL)
    private var toneCursor = 0
    private val toneTraj = Array(ToneFx.entries.size) { k ->
        val kind = ToneFx.entries[k]; Array(ToneBurst.count(kind)) { ToneBurst.trajectory(kind, it) }
    }
    private val tonePaths = Array(ToneFx.entries.size) { Path() }
    // Từ khoá
    private var pendingKeyword: KeywordKind? = null
    private val kwStart = LongArray(KeywordBursts.POOL) { Long.MIN_VALUE / 2 }
    private val kwKind = IntArray(KeywordBursts.POOL)
    private val kwX = FloatArray(KeywordBursts.POOL)
    private val kwY = FloatArray(KeywordBursts.POOL)
    private var kwCursor = 0
    private val kwHeart = Path()
    private val kwStar = Path()
    @Volatile private var kwEmoji: Map<String, Bitmap> = emptyMap()
    private val kwRect = RectF()
    // Chữ bay
    private var pendingLetter: String? = null
    private val letterText = arrayOfNulls<String>(FlyingLetters.POOL)
    private val letterStart = LongArray(FlyingLetters.POOL) { Long.MIN_VALUE / 2 }
    private val letterX = FloatArray(FlyingLetters.POOL)
    private val letterY = FloatArray(FlyingLetters.POOL)
    private val letterSeed = IntArray(FlyingLetters.POOL)
    private var letterCursor = 0
    private var letterSeq = 0
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textAlign = Paint.Align.CENTER; typeface = android.graphics.Typeface.DEFAULT_BOLD
    }
    // Hạt cát — đống = mảng chiều cao theo cột (SandPile), hạt bay pool cố định.
    internal var sand: SandPile? = null
        private set
    private val grainStart = LongArray(SandPile.FLYING) { Long.MIN_VALUE / 2 }
    private val grainX = FloatArray(SandPile.FLYING)
    private val grainY = FloatArray(SandPile.FLYING)
    private val grainFallMs = LongArray(SandPile.FLYING)
    private val grainAlive = BooleanArray(SandPile.FLYING)
    private var grainCursor = 0
    private var grainSeq = 0
    private var sandLast = Long.MIN_VALUE / 2
    private val sandPath = Path()
    // Biển — sóng (pool MAX_WAVES), chùm bọt + bong bóng (pool TAP_SLOTS), một con cá; mảng cấp sẵn, Path dùng lại.
    private val seaTapStart = LongArray(SeaFx.TAP_SLOTS) { Long.MIN_VALUE / 2 }
    private val seaTapX = FloatArray(SeaFx.TAP_SLOTS)
    private val seaTapY = FloatArray(SeaFx.TAP_SLOTS)
    private var seaTapCursor = 0
    private val seaWaveStart = LongArray(SeaFx.MAX_WAVES) { Long.MIN_VALUE / 2 }
    private val seaWaveSize = DoubleArray(SeaFx.MAX_WAVES)
    private var seaWaveCursor = 0
    private var seaLastWave = Long.MIN_VALUE / 2
    private var seaLevel = 0
    private var seaFishStart = Long.MIN_VALUE / 2
    private var seaLastFish = Long.MIN_VALUE / 2
    private var seaFishSeq = 0
    private var seaFishCur = 0
    @Volatile private var seaFishBmp: Array<Bitmap>? = null
    private val seaPath = Path()
    private val seaEdge = Path()
    private val seaTmp = DoubleArray(4)
    // Token AI — pool chùm (chữ + ≤ 6 chip), mảng cấp sẵn; đường bay (px) tính MỘT lần lúc bắn.
    /** Đích bay (toạ độ view này, px) ghi vào out[0..1] — IME đặt khi kiểu là Token AI; false/null ⇒ giữa mép trên. */
    var tokenTarget: ((FloatArray) -> Boolean)? = null
    /** Biển: mỗi con sóng MỚI (không mỗi phím) — cỡ sóng. IME đặt khi kiểu là Biển ⇒ tiếng sóng vỗ ([Feedback.surf]). */
    var onSeaWave: ((Double) -> Unit)? = null
    private var pendingToken: String? = null
    private val tokGlyph = arrayOfNulls<String>(TokenStream.POOL)
    private val tokStart = LongArray(TokenStream.POOL) { Long.MIN_VALUE / 2 }
    private val tokGX = FloatArray(TokenStream.POOL)
    private val tokGY = FloatArray(TokenStream.POOL)
    private val tokN = IntArray(TokenStream.POOL)
    private val tokPts = DoubleArray(TokenStream.CAP * 6)   // mỗi chip: x0 y0 cx cy x1 y1
    private var tokCursor = 0
    private val tokTarget = FloatArray(2)
    private val tokTmp = DoubleArray(2)
    private val tokTmp2 = DoubleArray(2)
    private val tokRect = RectF()
    private val tokChip = arrayOfNulls<Paint>(3)
    private val tokGlow = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val tokText = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textAlign = Paint.Align.CENTER; typeface = android.graphics.Typeface.DEFAULT_BOLD; color = 0xFFFFFFFF.toInt()
    }
    private val shimmerGate = ShimmerGate()
    private var shimStart = Long.MIN_VALUE / 2
    private val shimBar = RectF()
    private val shimPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private var shimBandW = -1f
    // Sàn nhảy LED — pool chùm ô (mảng phẳng cấp sẵn: vòng, màu, x, y, w, h mỗi ô), nháy cả bàn phím một lớp.
    private val danceStart = LongArray(DanceFloor.POOL) { Long.MIN_VALUE / 2 }
    private val danceTiles = Array(DanceFloor.POOL) { FloatArray(DANCE_TILES * 6) }
    private val danceN = IntArray(DanceFloor.POOL)
    private var danceCursor = 0
    private var danceSeq = 0
    private val flickerGate = DanceFloor.FlickerGate()
    /** Sàn nhảy LED: cổng an toàn chung với flash phím cách ([BeatFlashView.gate]). null ⇒ chỉ FlickerGate. */
    var flashGate: com.viettelex.keyboard.BeatFlash.Gate? = null
    private var flickerStart = Long.MIN_VALUE / 2
    private val flickerTiles = FloatArray(DanceFloor.MAX_GRID * 6)
    private var flickerN = 0
    private val danceRect = RectF()
    // Rep (theme Gym) — mảng cấp sẵn; thanh rep vẽ tĩnh, chỉ hẹn khung hình khi có thứ đang chuyển động (nghỉ = 0).
    private val repCounter = RepsFx.Counter()
    private var repFill = 0
    private var repFrom = 0
    private var repTo = 0
    private var repStart = Long.MIN_VALUE / 2
    private var repActive = false
    private var badgeStart = Long.MIN_VALUE / 2
    private var badgeLabel = ""
    private val repLabelStart = LongArray(RepsFx.LABEL_CAP) { Long.MIN_VALUE / 2 }
    private val repLabelX = FloatArray(RepsFx.LABEL_CAP)
    private val repLabelY = FloatArray(RepsFx.LABEL_CAP)
    private var repLabelCursor = 0
    private var repSeq = 0
    private var pendingSlam = false
    private var slamStart = Long.MIN_VALUE / 2
    private var repLastMs = 0L
    private var repSweepPosted = false
    private val repSweep = Runnable { sweepReps() }
    private val repTmp = DoubleArray(2)
    private val repRect = RectF()
    private val repText = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textAlign = Paint.Align.CENTER; typeface = android.graphics.Typeface.DEFAULT_BOLD
    }

    val effect: KeyEffect get() = sim.effect

    init {
        isClickable = false
        isFocusable = false
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        setWillNotDraw(false)
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(event: MotionEvent?) = false

    fun configure(e: KeyEffect, accent: Int, keyFill: Int = this.keyFill, dark: Boolean = this.dark) {
        if (e == sim.effect && accent == color && keyFill == this.keyFill && dark == this.dark) return
        val changed = e != sim.effect
        if (changed) halt()
        sim.configure(e)
        color = accent; this.keyFill = keyFill; this.dark = dark
        for (i in paths.indices) buildPath(e, i, paths[i])
        val opaque = accent or (0xFF shl 24)
        fill.color = opaque; stroke.color = opaque
        fillColors = e.fixedColors.map { it or (0xFF shl 24) }.toIntArray()
        when (e) {
            KeyEffect.BUBBLE -> { useFill = true; useStroke = true; fillAlpha = 46; strokeAlpha = 255; stroke.strokeWidth = 1.5f }
            KeyEffect.RIPPLE -> { useFill = false; useStroke = true; strokeAlpha = 204; stroke.strokeWidth = 2f }
            KeyEffect.METEOR -> {
                useFill = true; useStroke = !dark; fillAlpha = 255; strokeAlpha = 255; stroke.strokeWidth = 0.6f
                stroke.color = MeteorStreak.EDGE or (0xFF shl 24)
            }
            KeyEffect.SNOW -> {
                useFill = true; useStroke = !dark; fillAlpha = 255; strokeAlpha = 255; stroke.strokeWidth = 0.6f
                fillColors = intArrayOf(if (dark) 0xFFFFFFFF.toInt() else 0xFFDCEBFF.toInt())
                stroke.color = 0xFF8FB3E0.toInt()
            }
            else -> { useFill = true; useStroke = false; fillAlpha = 255 }
        }
        blob = if (e == KeyEffect.INK) renderBlob(opaque) else null
        glows = if (e.usesGlow) Array(e.fixedColors.size) { renderGlow(e, e.fixedColors[it]) } else emptyArray()
        if (changed) { shardCache.clear(); combo.reset(); shakeMeter.reset(); plasma.reset(); prewarm(e); buildFx3Paths(e) }
        if (e != KeyEffect.SHAKE) shakeTarget?.let { it.translationX = 0f; it.translationY = 0f }
        if (e != KeyEffect.SAND) sand = null
        pendN = 0
        invalidate()
    }

    /** "Emoji theo chữ": IME tra bảng ở ranh giới từ rồi xếp emoji — lần vẽ kế (phím ranh giới) bắn nó. */
    fun queueEmoji(e: String) { if (sim.effect == KeyEffect.EMOJIWORD) pendingEmoji = e }

    /** "Dấu thanh": IME so từ trước/sau phím ([com.viettelex.keyboard.ToneMarks.detect]) — lần vẽ kế bắn tại phím đó. */
    fun queueTone(t: ToneFx) { if (sim.effect == KeyEffect.TONE) pendingTone = t }

    /** "Từ khoá": IME tra bảng ở ranh giới từ — lần vẽ kế (phím ranh giới) bắn chùm. */
    fun queueKeyword(k: KeywordKind) { if (sim.effect == KeyEffect.KEYWORD) pendingKeyword = k }

    /** "Chữ bay": chữ vừa ra ([FlyingLetters.glyph]) — lần vẽ kế thả từ phím vừa bấm. */
    fun queueLetter(s: String) { if (sim.effect == KeyEffect.LETTERS) pendingLetter = s }

    /** "Rep": từ vừa chốt là từ khoá gym ([RepsFx.isKeyword]) — lần vẽ kế đập chữ BEAST MODE + vòng xung kích. */
    fun queueBeastMode() { if (sim.effect == KeyEffect.REPS) pendingSlam = true }

    /** "Token AI": chữ vừa ra — lần vẽ kế loé tại phím rồi vỡ thành token bay vào thanh gợi ý. */
    fun queueToken(s: String) { if (sim.effect == KeyEffect.TOKENS) pendingToken = s }

    /**
     * "Token AI": thanh gợi ý vừa hiện [words] trong khung ([l], [t], [r], [b]) px theo toạ độ view này. Chỉ đổi THẬT
     * ([ShimmerGate]) mới quét vệt sáng ~0,3 s; kiểu khác ⇒ return ngay.
     */
    fun suggestionsChanged(words: List<String>, l: Float, t: Float, r: Float, b: Float) {
        if (sim.effect != KeyEffect.TOKENS) return
        if (!shimmerGate.update(words, SystemClock.uptimeMillis() / 1000.0) || r <= l || b <= t) return
        shimBar.set(l, t, r, b)
        val bw = ((r - l) * ShimmerGate.BAND).toFloat()
        if (bw != shimBandW) {
            shimBandW = bw
            val w = (ShimmerGate.PEAK_ALPHA * 255).toInt() shl 24 or 0xFFFFFF
            shimPaint.shader = android.graphics.LinearGradient(0f, 0f, bw, 0f, intArrayOf(0x00FFFFFF, w, 0x00FFFFFF), null,
                android.graphics.Shader.TileMode.CLAMP)
        }
        shimStart = SystemClock.uptimeMillis()
        postInvalidateOnAnimation()
    }

    private val hasQueued: Boolean get() = when (sim.effect) {
        KeyEffect.EMOJIWORD -> pendingEmoji != null
        KeyEffect.TONE -> pendingTone != null
        KeyEffect.KEYWORD -> pendingKeyword != null
        KeyEffect.LETTERS -> pendingLetter != null
        KeyEffect.TOKENS -> pendingToken != null
        else -> true
    }

    /** Một phím vừa chèn chữ, tâm phím ([x], [y]), cỡ [w]×[h] (px) theo toạ độ view này. */
    fun burst(x: Float, y: Float, w: Float = 0f, h: Float = 0f) {
        if (sim.effect == KeyEffect.NONE) return
        if (sim.effect.isQueued && !hasQueued) return   // Emoji / Dấu thanh / Từ khoá / Chữ bay: không có sự kiện ⇒ không hẹn gì
        if (pendN == MAX_PENDING) {
            for (i in 1 until MAX_PENDING) { pendX[i - 1] = pendX[i]; pendY[i - 1] = pendY[i]; pendW[i - 1] = pendW[i]; pendH[i - 1] = pendH[i] }
            pendN--
        }
        pendX[pendN] = x; pendY[pendN] = y; pendW[pendN] = w; pendH[pendN] = h; pendN++
        if (!posted) { posted = true; post(flushRun) }
    }

    /** Bắn các khung chờ (test gọi thẳng). */
    fun flush() {
        posted = false
        if (pendN == 0) return
        val now = SystemClock.uptimeMillis()
        when (sim.effect) {
            KeyEffect.EMOJIWORD -> {
                val em = pendingEmoji
                pendingEmoji = null
                val b = em?.let { emojiBitmaps[it] ?: renderEmoji(it).also { r -> emojiBitmaps = emojiBitmaps + (it to r) } }
                if (b != null) fireSlot(pendX[pendN - 1], pendY[pendN - 1], now, b)
            }
            KeyEffect.TONE -> {
                val t = pendingTone; pendingTone = null
                if (t != null) fireTone(t, pendX[pendN - 1], pendY[pendN - 1], pendH[pendN - 1], now)
            }
            KeyEffect.KEYWORD -> {
                val k = pendingKeyword; pendingKeyword = null
                if (k != null) fireKeyword(k, pendX[pendN - 1], pendY[pendN - 1], pendH[pendN - 1], now)
            }
            KeyEffect.LETTERS -> {
                val g = pendingLetter; pendingLetter = null
                if (g != null) fireLetter(g, pendX[pendN - 1], pendY[pendN - 1], pendH[pendN - 1], now)
            }
            KeyEffect.TOKENS -> {
                val g = pendingToken; pendingToken = null
                if (g != null) fireToken(g, pendX[pendN - 1], pendY[pendN - 1], pendH[pendN - 1], now)
            }
            else -> {
                for (i in 0 until pendN) fire(pendX[i], pendY[i], pendW[i], pendH[i], now)
                if (pendingSlam) { pendingSlam = false; slamStart = now }
            }
        }
        pendN = 0
        postInvalidateOnAnimation()
    }

    private fun fire(x: Float, y: Float, w: Float, h: Float, now: Long) {
        when (sim.effect) {
            KeyEffect.NONE, KeyEffect.EMOJIWORD, KeyEffect.TONE, KeyEffect.KEYWORD, KeyEffect.LETTERS, KeyEffect.TOKENS -> {}
            KeyEffect.PLASMA -> firePlasma(x, y, now)
            KeyEffect.SHAKE -> {
                val amp = ShakeFx.amplitude(shakeMeter.press(now))
                if (amp > 0.0 && shakeTarget != null) { shakeStart = now; shakeAmp = (amp * density).toFloat() }
            }
            KeyEffect.LASER -> fireLaser(x, y, now)
            KeyEffect.GLITCH -> {
                val s = glCursor; glCursor = (s + 1) % GlitchFx.POOL
                val hw = (if (w > 0f) w else DEFAULT_W * density) / 2; val hh = (if (h > 0f) h else DEFAULT_H * density) / 2
                glStart[s] = now; glRect[s].set(x - hw, y - hh, x + hw, y + hh); glVariant[s] = glSeq++ % GlitchFx.VARIANTS
            }
            KeyEffect.SAND -> fireSand(x, y, now)
            KeyEffect.SEA -> fireSea(x, y, now)
            KeyEffect.REPS -> fireRep(x, y, if (h > 0f) h else DEFAULT_H * density, now)
            KeyEffect.DANCEFLOOR -> fireDance(x, y, if (w > 0f) w else DEFAULT_W * density, if (h > 0f) h else DEFAULT_H * density, now)
            KeyEffect.FLASH -> if (flash.trigger(now)) flashStart = now
            KeyEffect.LIGHTNING -> fireLightning(x, y, if (w > 0f) w else DEFAULT_W * density, if (h > 0f) h else DEFAULT_H * density, now)
            KeyEffect.MATRIX -> pokeMatrix(now)
            KeyEffect.INK, KeyEffect.WAVE -> fireSlot(x, y, now, null)
            KeyEffect.STRING -> fireString(x, y, if (w > 0f) w else DEFAULT_W * density, if (h > 0f) h else DEFAULT_H * density, now)
            KeyEffect.COMBO -> {
                val lv = combo.press(now)
                if (lv > 0) sim.spawn(x, y, now, lv, ComboMeter.SCALES[minOf(lv, 3)].toFloat())
            }
            else -> sim.spawn(x, y, now)
        }
    }

    private fun fireSlot(x: Float, y: Float, now: Long, b: Bitmap?) {
        val cap = when (sim.effect) { KeyEffect.INK -> InkBloom.SLOTS; KeyEffect.WAVE -> WaveRings.SLOTS; else -> 3 }
        val s = slotCursor % cap
        slotCursor = (s + 1) % cap
        slotStart[s] = now; slotX[s] = x; slotY[s] = y; slotBmp[s] = b
    }

    private fun fireString(x: Float, y: Float, w: Float, h: Float, now: Long) {
        val s = strCursor
        strCursor = (s + 1) % StringPluck.POOL
        val (gy, gi) = if (stringGaps.isEmpty()) (y + h / 2 + StringPluck.FALLBACK_OFFSET * density).toDouble() to 0
            else StringPluck.target((y - h / 2).toDouble(), (y + h / 2).toDouble(), stringGaps)
        strStart[s] = now; strX[s] = x; strY[s] = gy.toFloat()
        strLen[s] = (StringPluck.length((w / density).toDouble()) * density).toFloat()
        strWidth[s] = ((ThemeDecoration.stringThickness(gi) + 0.4) * density).toFloat()
    }

    /** Test: số đoạn dây đang rung lúc [now] + vị trí y (px) đoạn thứ [i]. */
    internal fun stringsAlive(now: Long): Int = strStart.count { now - it in 0 until STRING_MS }
    internal fun stringY(i: Int): Float = strY[i]

    private fun fireLightning(x: Float, y: Float, w: Float, h: Float, now: Long) {
        val s = strikeCursor
        strikeCursor = (s + 1) % STRIKES
        strikeSeq++
        strikeStart[s] = now; strikeX[s] = x; strikeY[s] = y
        // Tia: từ đỉnh view (y = 0) xuống tâm phím — điểm tất định theo lần bấm (dp → px).
        LightningBolt.points((y / density).toDouble(), strikeSeq % LightningBolt.VARIANTS, boltPts)
        val p = boltPaths[s]
        p.reset()
        for (i in 0..LightningBolt.SEGMENTS) {
            val px = (boltPts[2 * i] * density).toFloat(); val py = (boltPts[2 * i + 1] * density).toFloat()
            if (i == 0) p.moveTo(px, py) else p.lineTo(px, py)
        }
        glowRects[s].set(-w / 2, -h / 2, w / 2, h / 2)
        val key = Math.round(w) * 4096 + Math.round(h)
        val pieces = shardCache[key] ?: LightningShards.pieces(w.toDouble(), h.toDouble()).also {
            if (shardCache.size > 16) shardCache.clear()
            shardCache[key] = it
        }
        for (i in 0 until LightningShards.COUNT) {
            val pc = pieces[i]; val sp = shardPaths[s][i]
            sp.reset()
            for (k in pc.xs.indices) {
                val qx = (pc.xs[k] - pc.cx).toFloat(); val qy = (pc.ys[k] - pc.cy).toFloat()
                if (k == 0) sp.moveTo(qx, qy) else sp.lineTo(qx, qy)
            }
            sp.close()
            shardCx[s][i] = pc.cx.toFloat(); shardCy[s][i] = pc.cy.toFloat()
        }
    }

    private fun pokeMatrix(now: Long) {
        val started = matrixClock.poke(now)
        if (started && columns.isEmpty() && width > 0) {
            columns = Array(MatrixRain.columnCount((width / density).toDouble())) { MatrixRain.column(it) }
        }
    }

    /** Dừng mọi thứ đang chạy (ẩn bàn phím / đổi kiểu / gỡ) — sau đó không còn khung hình nào. */
    fun halt() {
        matrixClock.stop()
        sim.clear()
        strikeStart.fill(Long.MIN_VALUE / 2)
        slotStart.fill(Long.MIN_VALUE / 2)
        strStart.fill(Long.MIN_VALUE / 2)
        flashStart = Long.MIN_VALUE / 2
        pendingEmoji = null
        pendingTone = null; pendingKeyword = null; pendingLetter = null; pendingToken = null
        tokStart.fill(Long.MIN_VALUE / 2); shimStart = Long.MIN_VALUE / 2; shimmerGate.reset()
        arcStart.fill(Long.MIN_VALUE / 2); laserStart.fill(Long.MIN_VALUE / 2); glStart.fill(Long.MIN_VALUE / 2)
        toneStart.fill(Long.MIN_VALUE / 2); kwStart.fill(Long.MIN_VALUE / 2); letterStart.fill(Long.MIN_VALUE / 2)
        grainAlive.fill(false); sand?.clear(); plasma.reset()
        seaTapStart.fill(Long.MIN_VALUE / 2); seaWaveStart.fill(Long.MIN_VALUE / 2); seaFishStart = Long.MIN_VALUE / 2
        seaLastWave = Long.MIN_VALUE / 2; seaLevel = 0
        shakeStart = Long.MIN_VALUE / 2; shakeMeter.reset()
        shakeTarget?.let { it.translationX = 0f; it.translationY = 0f }
        danceStart.fill(Long.MIN_VALUE / 2); flickerStart = Long.MIN_VALUE / 2
        removeCallbacks(repSweep); repSweepPosted = false; resetReps()   // ẩn bàn phím ⇒ hiệp về 0
        pendN = 0
        invalidate()
    }

    // ---- Sàn nhảy LED ([DanceFloor] — hình học thuần chung iOS; ở đây px vì cỡ ô theo khung phím thật)

    private fun copyTiles(src: List<DanceFloor.Tile>, dst: FloatArray, max: Int): Int {
        val n = minOf(src.size, max)
        for (k in 0 until n) {
            val t = src[k]
            dst[6 * k] = t.ring.toFloat(); dst[6 * k + 1] = t.color.toFloat()
            dst[6 * k + 2] = t.x.toFloat(); dst[6 * k + 3] = t.y.toFloat(); dst[6 * k + 4] = t.w.toFloat(); dst[6 * k + 5] = t.h.toFloat()
        }
        return n
    }

    private fun fireDance(x: Float, y: Float, w: Float, h: Float, now: Long) {
        val level = combo.press(now)
        val s = danceCursor; danceCursor = (s + 1) % DanceFloor.POOL
        danceSeq++
        danceN[s] = copyTiles(DanceFloor.tiles(x.toDouble(), y.toDouble(), w.toDouble(), h.toDouble(), danceSeq), danceTiles[s], DANCE_TILES)
        danceStart[s] = now
        // Gõ dồn (mức combo cao nhất): cả bàn phím nháy một nhịp — trần nhịp FLICKER_COOLDOWN.
        if (flickerGate.trigger(level, now / 1000.0) && (flashGate?.trigger(now / 1000.0) ?: true) && width > 0 && height > 0) {
            flickerN = copyTiles(DanceFloor.grid(0.0, 0.0, width.toDouble(), height.toDouble(), x.toDouble(), y.toDouble(),
                w.toDouble(), h.toDouble(), danceSeq), flickerTiles, DanceFloor.MAX_GRID)
            flickerStart = now
        }
    }

    private fun drawTile(canvas: Canvas, t: FloatArray, k: Int, a: Double) {
        val c = DanceFloor.COLORS[t[6 * k + 1].toInt()] or (0xFF shl 24)
        val cx = t[6 * k + 2]; val cy = t[6 * k + 3]; val hw = t[6 * k + 4] / 2; val hh = t[6 * k + 5] / 2
        danceRect.set(cx - hw, cy - hh, cx + hw, cy + hh)
        val r = (DanceFloor.CORNER_FACTOR * minOf(hw, hh) * 2).toFloat()
        fill.color = c; fill.alpha = (a * 255).toInt().coerceIn(0, 255)
        canvas.drawRoundRect(danceRect, r, r, fill)
        stroke.color = c; stroke.alpha = (a * 0.9 * 255).toInt().coerceIn(0, 255); stroke.strokeWidth = 1.5f * density
        canvas.drawRoundRect(danceRect, r, r, stroke)
    }

    private fun drawDance(canvas: Canvas, now: Long): Boolean {
        var any = false
        val fdt = (now - flickerStart) / 1000.0
        if (fdt >= 0 && fdt < DanceFloor.FLICKER_DURATION) {
            any = true
            val a = DanceFloor.flickerAlpha(fdt)
            if (a > 0) for (k in 0 until flickerN) drawTile(canvas, flickerTiles, k, a)
        }
        for (s in 0 until DanceFloor.POOL) {
            val dt = (now - danceStart[s]) / 1000.0
            if (dt < 0 || dt >= DanceFloor.LIFETIME) continue
            any = true
            val t = danceTiles[s]
            for (k in 0 until danceN[s]) {
                val a = DanceFloor.alpha(dt, t[6 * k].toInt())
                if (a > 0) drawTile(canvas, t, k, a)
            }
        }
        return any
    }

    /** Test: số chùm sàn nhảy còn sáng lúc [now] + đã nháy cả bàn phím bao nhiêu lần. */
    internal fun dancesAlive(now: Long): Int = danceStart.count { (now - it) / 1000.0 in 0.0..<DanceFloor.LIFETIME }
    internal val flickersFired: Int get() = flickerGate.fired

    // ---- Rep (theme Gym — [RepsFx], hàm thuần chung iOS; ở đây px = dp × density)

    private fun fireRep(x: Float, y: Float, h: Float, now: Long) {
        val ev = repCounter.press(now / 1000.0)
        repFrom = repFill; repTo = ev.fill; repStart = now; repActive = true
        repFill = if (ev.fill >= RepsFx.PER_SET) 0 else ev.fill
        ev.completedSet?.let { badgeStart = now; badgeLabel = RepsFx.badgeText(it) }
        if (combo.press(now) >= 1 && width > 0 && height > 0) {
            val s = repLabelCursor; repLabelCursor = (s + 1) % RepsFx.LABEL_CAP
            repSeq++
            val d = density.toDouble()
            RepsFx.labelOrigin(x / d, (y - h / 2) / d, repSeq, 0.0, 0.0, width / d, height / d, repTmp)
            repLabelStart[s] = now; repLabelX[s] = (repTmp[0] * d).toFloat(); repLabelY[s] = (repTmp[1] * d).toFloat()
        }
        repLastMs = now
        scheduleRepSweep(((RepsFx.IDLE_RESET + 0.5) * 1000).toLong())
    }

    private fun scheduleRepSweep(delayMs: Long) {
        if (repSweepPosted) return
        repSweepPosted = true
        postDelayed(repSweep, delayMs)
    }

    /** Nghỉ đủ [RepsFx.IDLE_RESET] ⇒ hiệp về 0 (thanh rỗng); chưa đủ ⇒ hẹn lại phần còn lại. Một lần hẹn cho cả loạt gõ. */
    private fun sweepReps() {
        repSweepPosted = false
        if (sim.effect != KeyEffect.REPS) return
        val idle = (SystemClock.uptimeMillis() - repLastMs) / 1000.0
        if (idle <= RepsFx.IDLE_RESET) { scheduleRepSweep(((RepsFx.IDLE_RESET - idle + 0.5) * 1000).toLong()); return }
        resetReps()
        invalidate()
    }

    /** Hiệp về 0 + tắt mọi thứ đang bay (ẩn bàn phím / nghỉ lâu / đổi kiểu). */
    private fun resetReps() {
        repCounter.reset(); repFill = 0; repFrom = 0; repTo = 0; repStart = Long.MIN_VALUE / 2; repActive = false
        badgeStart = Long.MIN_VALUE / 2; slamStart = Long.MIN_VALUE / 2; repLabelStart.fill(Long.MIN_VALUE / 2); pendingSlam = false
    }

    /** Chữ trên nền màu nhấn: đen hay trắng tuỳ độ sáng. */
    private fun inkOn(c: Int): Int {
        val l = 0.299 * ((c shr 16) and 0xFF) + 0.587 * ((c shr 8) and 0xFF) + 0.114 * (c and 0xFF)
        return if (l / 255 > 0.55) 0xFF121212.toInt() else 0xFFFFFFFF.toInt()
    }

    private fun drawReps(canvas: Canvas, now: Long): Boolean {
        var any = false
        val d = density
        val accent = color or (0xFF shl 24)
        // Thanh rep (tĩnh khi nghỉ — chỉ hẹn khung hình lúc đang trượt).
        if (repActive) {
            val bdt = (now - repStart) / 1000.0
            val life = if (repTo >= RepsFx.PER_SET) RepsFx.SET_LIFE else RepsFx.BAR_STEP
            val f = if (bdt >= 0 && bdt < life) { any = true; RepsFx.barFill(repFrom, repTo, bdt) } else repFill.toDouble() / RepsFx.PER_SET
            val ins = (RepsFx.BAR_INSET * d).toFloat(); val bh = (RepsFx.BAR_HEIGHT * d).toFloat(); val tw = width - 2 * ins
            if (tw > 0) {
                fill.color = accent; fill.alpha = 56
                repRect.set(ins, ins, ins + tw, ins + bh); canvas.drawRoundRect(repRect, bh / 2, bh / 2, fill)
                if (f > 5e-4) {
                    fill.alpha = 255
                    repRect.set(ins, ins, ins + (tw * f).toFloat(), ins + bh); canvas.drawRoundRect(repRect, bh / 2, bh / 2, fill)
                }
            }
        }
        // Huy hiệu SET n ✓
        val gdt = (now - badgeStart) / 1000.0
        if (gdt >= 0 && gdt < RepsFx.BADGE_DURATION) {
            any = true
            val a = (RepsFx.badgeAlpha(gdt) * 255).toInt().coerceIn(0, 255)
            val s = RepsFx.badgeScale(gdt).toFloat()
            repText.textSize = (RepsFx.BADGE_FONT * d).toFloat()
            val maxScale = RepsFx.BADGE_SCALES.max().toFloat()
            val bw = minOf(repText.measureText(badgeLabel) + 18 * d, maxOf((width - 4 * d) / maxScale, 1f))
            val bh = ((RepsFx.BADGE_FONT + 9) * d).toFloat()
            val save = canvas.save()
            canvas.translate(width / 2f, (RepsFx.BADGE_Y * d).toFloat())
            canvas.scale(s, s)
            fill.color = accent; fill.alpha = a
            repRect.set(-bw / 2, -bh / 2, bw / 2, bh / 2); canvas.drawRoundRect(repRect, bh / 2, bh / 2, fill)
            repText.color = inkOn(accent); repText.alpha = a
            canvas.drawText(badgeLabel, 0f, -(repText.ascent() + repText.descent()) / 2, repText)
            canvas.restoreToCount(save)
        }
        // "+1 rep 💪"
        for (k in 0 until RepsFx.LABEL_CAP) {
            val dt = (now - repLabelStart[k]) / 1000.0
            if (dt < 0 || dt >= RepsFx.LABEL_DURATION) continue
            any = true
            repText.textSize = (RepsFx.LABEL_FONT * RepsFx.labelScale(dt) * d).toFloat()
            repText.color = accent; repText.alpha = (RepsFx.labelAlpha(dt) * 255).toInt().coerceIn(0, 255)
            val ly = repLabelY[k] + (RepsFx.labelDy(dt) * d).toFloat()
            canvas.drawText(RepsFx.LABEL_TEXT, repLabelX[k], ly - (repText.ascent() + repText.descent()) / 2, repText)
        }
        // BEAST MODE + vòng xung kích
        val sdt = (now - slamStart) / 1000.0
        if (sdt >= 0 && sdt < RepsFx.SLAM_DURATION && width > 0 && height > 0) {
            any = true
            val cx = width / 2f; val cy = height / 2f
            val ra = RepsFx.ringAlpha(sdt)
            if (ra > 0) {
                stroke.color = accent; stroke.alpha = (ra * 255).toInt().coerceIn(0, 255); stroke.strokeWidth = (RepsFx.RING_WIDTH * d).toFloat()
                val r = RepsFx.ringRadius(width / d.toDouble(), height / d.toDouble()) * RepsFx.ringScale(sdt) * d
                canvas.drawCircle(cx, cy, r.toFloat(), stroke)
            }
            val sa = RepsFx.slamAlpha(sdt)
            if (sa > 0) {
                val s = RepsFx.slamScale(sdt).toFloat()
                repText.textSize = (RepsFx.slamFont(width / d.toDouble()) * d).toFloat()
                repText.color = accent; repText.alpha = (sa * 255).toInt().coerceIn(0, 255)
                val save = canvas.save()
                canvas.translate(cx, cy); canvas.scale(s, s)
                canvas.drawText(RepsFx.SLAM_TEXT, 0f, -(repText.ascent() + repText.descent()) / 2, repText)
                canvas.restoreToCount(save)
            }
        }
        return any
    }

    /** Test (Rep): bộ đếm, nấc thanh đang hiện, nhãn còn bay lúc [now] + tâm (px), huy hiệu / chữ đập còn chạy, chữ huy hiệu. */
    internal val repCounterState: RepsFx.Counter get() = repCounter
    internal val repFillShown: Int get() = repFill
    internal val repBarActive: Boolean get() = repActive
    internal fun repLabelsAlive(now: Long): Int = repLabelStart.count { (now - it) / 1000.0 in 0.0..<RepsFx.LABEL_DURATION }
    internal fun repLabelCenter(i: Int): Pair<Float, Float> = repLabelX[i] to repLabelY[i]
    internal fun repBadgeAlive(now: Long): Boolean = (now - badgeStart) / 1000.0 in 0.0..<RepsFx.BADGE_DURATION
    internal fun repSlamAlive(now: Long): Boolean = (now - slamStart) / 1000.0 in 0.0..<RepsFx.SLAM_DURATION
    internal val repBadgeLabel: String get() = badgeLabel
    internal fun debugSweepReps(idleSeconds: Double) {
        repLastMs = SystemClock.uptimeMillis() - (idleSeconds * 1000).toLong(); removeCallbacks(repSweep); repSweepPosted = false; sweepReps()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        halt()
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        if (sim.effect == KeyEffect.MATRIX && w > 0) columns = Array(MatrixRain.columnCount((w / density).toDouble())) { MatrixRain.column(it) }
    }

    internal val pendingCount: Int get() = pendN
    internal val isPosted: Boolean get() = posted
    internal fun aliveCount(): Int = sim.aliveCount()
    internal val glowCount: Int get() = glows.size

    override fun onDraw(canvas: Canvas) {
        if (drawEffects(canvas)) postInvalidateOnAnimation()
    }

    /** Vẽ hiệu ứng lúc này; true = còn đang chạy (hẹn khung hình kế). */
    protected fun drawEffects(canvas: Canvas): Boolean {
        val e = sim.effect
        if (e == KeyEffect.NONE) return false
        val now = SystemClock.uptimeMillis()
        return when (e) {
            KeyEffect.FLASH -> drawFlash(canvas, now)
            KeyEffect.LIGHTNING -> drawLightning(canvas, now)
            KeyEffect.MATRIX -> drawMatrix(canvas, now)
            KeyEffect.INK -> drawInk(canvas, now)
            KeyEffect.WAVE -> drawWave(canvas, now)
            KeyEffect.STRING -> drawStrings(canvas, now)
            KeyEffect.EMOJIWORD -> drawEmoji(canvas, now)
            KeyEffect.PLASMA -> drawPlasma(canvas, now)
            KeyEffect.SHAKE -> stepShake(now)
            KeyEffect.LASER -> drawLaser(canvas, now)
            KeyEffect.GLITCH -> drawGlitch(canvas, now)
            KeyEffect.TONE -> drawTone(canvas, now)
            KeyEffect.KEYWORD -> drawKeyword(canvas, now)
            KeyEffect.LETTERS -> drawLetters(canvas, now)
            KeyEffect.TOKENS -> drawTokens(canvas, now)
            KeyEffect.SAND -> drawSand(canvas, now)
            KeyEffect.SEA -> drawSea(canvas, now)
            KeyEffect.DANCEFLOOR -> drawDance(canvas, now)
            KeyEffect.REPS -> drawReps(canvas, now)
            else -> drawParticles(canvas, now)
        }
    }

    private fun drawParticles(canvas: Canvas, now: Long): Boolean {
        var any = false
        for (s in 0 until sim.capacity) {
            if (!sim.sample(s, now, density)) continue
            any = true
            val i = sim.sIndex
            if (glows.isNotEmpty()) {
                // Đốm sáng: bitmap dựng sẵn (đã theo mật độ điểm ảnh) — chỉ dời / co giãn / mờ.
                val b = glows[i % glows.size]
                bmpPaint.alpha = (255 * sim.sAlpha).toInt().coerceIn(0, 255)
                mtx.setTranslate(-b.width / 2f, -b.height / 2f)
                mtx.postScale(sim.sScale, sim.sScale)
                mtx.postTranslate(sim.sx, sim.sy)
                canvas.drawBitmap(b, mtx, bmpPaint)
                continue
            }
            val k = sim.sScale * density
            val save = canvas.save()
            canvas.translate(sim.sx, sim.sy)
            if (sim.sRot != 0f) canvas.rotate(sim.sRot)
            canvas.scale(k, k)
            val path = paths[i % paths.size]
            if (useFill) {
                if (fillColors.isNotEmpty()) fill.color = fillColors[i % fillColors.size]
                fill.alpha = (fillAlpha * sim.sAlpha).toInt(); canvas.drawPath(path, fill)
            }
            if (useStroke) { stroke.alpha = (strokeAlpha * sim.sAlpha).toInt(); canvas.drawPath(path, stroke) }
            canvas.restoreToCount(save)
        }
        return any
    }

    private fun drawFlash(canvas: Canvas, now: Long): Boolean {
        val a = FlashPulse.alpha(now - flashStart)
        if (a <= 0.0) return false
        canvas.drawColor((color and 0xFFFFFF) or ((a * 255).toInt() shl 24))
        return true
    }

    private fun drawLightning(canvas: Canvas, now: Long): Boolean {
        var any = false
        for (s in 0 until STRIKES) {
            val t = now - strikeStart[s]
            if (t < 0 || t > LightningShards.DELAY_MS + LightningShards.DURATION_MS) continue
            any = true
            val save = canvas.save()
            canvas.translate(strikeX[s], strikeY[s])
            // Mảnh vỡ (màu phím) bay ra + xoay + mờ — chỉ trên overlay.
            val ts = t - LightningShards.DELAY_MS
            if (ts >= 0) {
                val f = ts.toFloat() / LightningShards.DURATION_MS
                val ease = 1f - (1f - f) * (1f - f)
                val a = if (f < 0.25f) 0.9f else 0.9f * (1f - (f - 0.25f) / 0.75f)
                fill.color = keyFill
                fill.alpha = (255 * a * (keyFill ushr 24) / 255f).toInt()
                stroke.color = 0xFFFFFFFF.toInt(); stroke.strokeWidth = 0.5f * density
                stroke.alpha = (255 * 0.35f * a).toInt()
                for (i in 0 until LightningShards.COUNT) {
                    val sv = canvas.save()
                    canvas.translate(shardCx[s][i] + (LightningShards.dirX(i) * LightningShards.FLIGHT * ease * density).toFloat(),
                        shardCy[s][i] + ((LightningShards.dirY(i) * LightningShards.FLIGHT + 8) * ease * density).toFloat())
                    canvas.rotate(Math.toDegrees(LightningShards.rotation(i) * f).toFloat())
                    canvas.drawPath(shardPaths[s][i], fill)
                    canvas.drawPath(shardPaths[s][i], stroke)
                    canvas.restoreToCount(sv)
                }
            }
            // Ánh chớp trắng + viền nhấn trên phím lúc tia chạm.
            val tg = t - 40
            if (tg in 0..220) {
                val f = tg / 220f
                val a = if (f < 0.25f) f / 0.25f else 1f - (f - 0.25f) / 0.75f
                fill.color = 0xFFFFFFFF.toInt(); fill.alpha = (255 * 0.6f * a).toInt()
                val r = 6 * density
                canvas.drawRoundRect(glowRects[s], r, r, fill)
                stroke.color = color or (0xFF shl 24); stroke.strokeWidth = 2 * density; stroke.alpha = (255 * a).toInt()
                canvas.drawRoundRect(glowRects[s], r, r, stroke)
            }
            // Tia: quầng nhấn + lõi trắng, mờ trong ~180 ms.
            if (t <= LightningBolt.DURATION_MS) {
                val f = t.toFloat() / LightningBolt.DURATION_MS
                val a = if (f < 0.35f) 1f else 1f - (f - 0.35f) / 0.65f
                stroke.strokeJoin = Paint.Join.ROUND; stroke.strokeCap = Paint.Cap.ROUND
                stroke.color = color or (0xFF shl 24); stroke.strokeWidth = 5 * density; stroke.alpha = (255 * 0.45f * a).toInt()
                canvas.drawPath(boltPaths[s], stroke)
                stroke.color = 0xFFFFFFFF.toInt(); stroke.strokeWidth = 1.6f * density; stroke.alpha = (255 * a).toInt()
                canvas.drawPath(boltPaths[s], stroke)
            }
            canvas.restoreToCount(save)
        }
        return any
    }

    private fun drawMatrix(canvas: Canvas, now: Long): Boolean {
        if (!matrixClock.running) return false
        val fade = matrixClock.fade(now)
        if (fade <= 0.0) { matrixClock.stop(); return false }           // nghỉ: dừng hẳn, không hẹn khung hình
        val st = strips ?: return true
        val a = MatrixRain.maxOpacity(dark) * MatrixRain.intensity(matrixClock.presses) * fade
        bmpPaint.alpha = (255 * a).toInt().coerceIn(0, 255)
        val hDp = (height / density).toDouble()
        for (i in columns.indices) {
            val c = columns[i]
            val top = (MatrixRain.columnTop(c, now, hDp) * density).toFloat()
            val x = (((i + 0.5) * MatrixRain.SPACING + c.jitter - MatrixRain.COLUMN_WIDTH / 2) * density).toFloat()
            canvas.drawBitmap(st[c.strip % st.size], x, top, bmpPaint)
        }
        return true
    }

    /** Đoạn dây rung: polyline sóng dừng (17 điểm) theo biên độ tắt dần — Path cấp sẵn, hết 0,3 s ⇒ false (thôi vẽ). */
    private fun drawStrings(canvas: Canvas, now: Long): Boolean {
        var any = false
        stroke.color = color or (0xFF shl 24)
        stroke.strokeCap = Paint.Cap.ROUND; stroke.strokeJoin = Paint.Join.ROUND
        for (s in 0 until StringPluck.POOL) {
            val t = now - strStart[s]
            if (t < 0 || t >= STRING_MS) continue
            any = true
            val dt = t / 1000.0
            val a = (StringPluck.amplitudeAt(dt) * density).toFloat()
            stroke.alpha = (255 * StringPluck.alphaAt(dt)).toInt().coerceIn(0, 255)
            stroke.strokeWidth = strWidth[s]
            strPath.rewind()
            val len = strLen[s]
            for (i in 0..StringPluck.POINTS) {
                val u = i.toFloat() / StringPluck.POINTS
                val px = strX[s] + (u - 0.5f) * len
                val py = strY[s] + a * Math.sin(Math.PI * u).toFloat()
                if (i == 0) strPath.moveTo(px, py) else strPath.lineTo(px, py)
            }
            canvas.drawPath(strPath, stroke)
        }
        return any
    }

    private fun drawInk(canvas: Canvas, now: Long): Boolean {
        val b = blob ?: return false
        var any = false
        for (s in 0 until InkBloom.SLOTS) {
            val t = now - slotStart[s]
            if (t < 0 || t >= InkBloom.DURATION_MS) continue
            any = true
            val f = t.toFloat() / InkBloom.DURATION_MS
            val ease = 1f - (1f - f) * (1f - f)
            val sc = (InkBloom.SCALE_FROM + (InkBloom.SCALE_TO - InkBloom.SCALE_FROM) * ease).toFloat()
            val pk = InkBloom.PEAK_ALPHA.toFloat()
            val a = if (f < 0.4f) pk - (pk * 0.3f) * f / 0.4f else pk * 0.7f * (1f - (f - 0.4f) / 0.6f)
            bmpPaint.alpha = (255 * a).toInt().coerceIn(0, 255)
            mtx.setTranslate(-b.width / 2f, -b.height / 2f)
            mtx.postScale(sc, sc)
            mtx.postTranslate(slotX[s], slotY[s])
            canvas.drawBitmap(b, mtx, bmpPaint)
        }
        return any
    }

    private fun drawWave(canvas: Canvas, now: Long): Boolean {
        var any = false
        stroke.color = color or (0xFF shl 24)
        for (s in 0 until WaveRings.SLOTS) {
            for (k in 0 until WaveRings.RINGS) {
                val t = now - slotStart[s] - k * WaveRings.STAGGER_MS
                if (t < -WaveRings.STAGGER_MS * WaveRings.RINGS || t >= WaveRings.DURATION_MS) continue
                any = true
                if (t < 0) continue
                val f = t.toFloat() / WaveRings.DURATION_MS
                val ease = 1f - (1f - f) * (1f - f)
                val sc = (WaveRings.SCALE_FROM + (WaveRings.SCALE_TO - WaveRings.SCALE_FROM) * ease).toFloat()
                stroke.strokeWidth = 0.9f * sc * density
                stroke.alpha = (255 * 0.55f * 0.85f * (1f - f)).toInt()
                canvas.drawCircle(slotX[s], slotY[s], (WaveRings.RADIUS * sc * density).toFloat(), stroke)
            }
        }
        return any
    }

    private fun drawEmoji(canvas: Canvas, now: Long): Boolean {
        var any = false
        for (s in 0 until 3) {
            val b = slotBmp[s] ?: continue
            val t = now - slotStart[s]
            if (t < 0 || t >= EMOJI_MS) continue
            any = true
            val f = t.toFloat() / EMOJI_MS
            val ease = 1f - (1f - f) * (1f - f)
            val sc = 0.6f + 0.55f * f
            bmpPaint.alpha = (255 * (if (f < 0.6f) 1f else 1f - (f - 0.6f) / 0.4f)).toInt()
            mtx.setTranslate(-b.width / 2f, -b.height / 2f)
            mtx.postScale(sc, sc)
            mtx.postTranslate(slotX[s], slotY[s] - 64 * density * ease)
            canvas.drawBitmap(b, mtx, bmpPaint)
        }
        return any
    }

    // MARK: đợt 3 — bắn

    private fun firePlasma(x: Float, y: Float, now: Long) {
        val s = arcCursor; arcCursor = (s + 1) % PlasmaArc.POOL
        val link = plasma.press((x / density).toDouble(), (y / density).toDouble(), now)
        arcStart[s] = now; arcX[s] = x; arcY[s] = y; arcLinked[s] = link
        val p = arcPaths[s]
        p.rewind()
        if (!link) return
        PlasmaArc.points(plasma.prevX * density, plasma.prevY * density, x.toDouble(), y.toDouble(),
            arcSeq++ % PlasmaArc.VARIANTS, arcPts, density.toDouble())
        for (i in 0..PlasmaArc.SEGMENTS) {
            val px = arcPts[2 * i].toFloat(); val py = arcPts[2 * i + 1].toFloat()
            if (i == 0) p.moveTo(px, py) else p.lineTo(px, py)
        }
    }

    private fun fireLaser(x: Float, y: Float, now: Long) {
        val f = spaceFrame
        val ox: Float; val oy: Float
        if (f != null && f(spaceRect)) {
            if (!LaserBeam.fires(spaceRect.left.toDouble(), spaceRect.top.toDouble(), spaceRect.right.toDouble(),
                    spaceRect.bottom.toDouble(), x.toDouble(), y.toDouble())) return
            ox = spaceRect.centerX(); oy = spaceRect.top
        } else {
            ox = width / 2f; oy = height - (LaserBeam.FALLBACK_INSET * density).toFloat()
        }
        val s = laserCursor; laserCursor = (s + 1) % LaserBeam.POOL
        laserStart[s] = now; laserOx[s] = ox; laserOy[s] = oy; laserTx[s] = x; laserTy[s] = y
    }

    /** Tâm phát ở mép trên phím (tâm − nửa cao), không vượt đỉnh view. */
    private fun keyTop(y: Float, h: Float): Float = maxOf(0f, y - (if (h > 0f) h else DEFAULT_H * density) / 2 + 4 * density)

    private fun fireTone(t: ToneFx, x: Float, y: Float, h: Float, now: Long) {
        val s = toneCursor; toneCursor = (s + 1) % ToneBurst.POOL
        toneStart[s] = now; toneKind[s] = t.ordinal; toneX[s] = x; toneY[s] = keyTop(y, h)
    }

    private fun fireKeyword(k: KeywordKind, x: Float, y: Float, h: Float, now: Long) {
        val s = kwCursor; kwCursor = (s + 1) % KeywordBursts.POOL
        kwStart[s] = now; kwKind[s] = k.ordinal; kwX[s] = x; kwY[s] = keyTop(y, h)
    }

    private fun fireLetter(g: String, x: Float, y: Float, h: Float, now: Long) {
        val s = letterCursor; letterCursor = (s + 1) % FlyingLetters.POOL
        letterText[s] = g; letterStart[s] = now; letterX[s] = x; letterY[s] = keyTop(y, h); letterSeed[s] = letterSeq++
    }

    /** Token AI: tính đường bay của mọi chip MỘT lần (px, trong khung view — bao lồi ⇒ không ra ngoài bàn phím). */
    private fun fireToken(g: String, x: Float, y: Float, h: Float, now: Long) {
        if (width <= 0 || height <= 0) return
        val s = tokCursor; tokCursor = (s + 1) % TokenStream.POOL
        val w = width.toDouble(); val hh = height.toDouble(); val u = density.toDouble()
        val ky = keyTop(y, h)
        if (tokenTarget?.invoke(tokTarget) != true) { tokTarget[0] = width / 2f; tokTarget[1] = 14 * density }
        TokenStream.clamp(tokTarget[0].toDouble(), tokTarget[1].toDouble(), w, hh, tokTmp2, TokenStream.INSET * u)
        val x1 = tokTmp2[0]; val y1 = tokTmp2[1]
        val n = TokenStream.chipCount(g)
        tokGlyph[s] = g; tokStart[s] = now; tokN[s] = n
        tokGX[s] = x; tokGY[s] = maxOf(ky, (TokenStream.GLYPH_SIZE * density / 2).toFloat())
        for (i in 0 until n) {
            TokenStream.start(x.toDouble(), ky.toDouble(), i, n, w, hh, tokTmp, u)
            val x0 = tokTmp[0]; val y0 = tokTmp[1]
            TokenStream.control(x0, y0, x1, y1, i, n, w, hh, tokTmp, u)
            val o = (s * TokenStream.MAX_CHIPS + i) * 6
            tokPts[o] = x0; tokPts[o + 1] = y0; tokPts[o + 2] = tokTmp[0]; tokPts[o + 3] = tokTmp[1]
            tokPts[o + 4] = x1; tokPts[o + 5] = y1
        }
    }

    private fun tokenPaints() {
        if (tokChip[0] != null) return
        val cw = (TokenStream.CHIP_W * density).toFloat()
        val c = TokenStream.COLORS
        for (i in 0 until 3) {
            tokChip[i] = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                shader = android.graphics.LinearGradient(-cw / 2, 0f, cw / 2, 0f, c[i] or (0xFF shl 24), c[(i + 1) % 3] or (0xFF shl 24),
                    android.graphics.Shader.TileMode.CLAMP)
            }
        }
        tokText.setShadowLayer(4 * density, 0f, 0f, c[0] or (0xFF shl 24))
    }

    /** Token AI: chữ loé + chip bay (Bézier, nhanh dần, co lại) + vệt sáng dải gợi ý. Hết ⇒ false (thôi hẹn khung). */
    private fun drawTokens(canvas: Canvas, now: Long): Boolean {
        tokenPaints()
        var any = false
        tokText.textSize = (TokenStream.GLYPH_SIZE * density).toFloat()
        val fm = tokText.fontMetrics
        val base = -(fm.ascent + fm.descent) / 2
        val cw = (TokenStream.CHIP_W * density).toFloat(); val ch = (TokenStream.CHIP_H * density).toFloat()
        val cr = (TokenStream.CHIP_RADIUS * density).toFloat(); val gp = 2 * density
        for (s in 0 until TokenStream.POOL) {
            val g = tokGlyph[s] ?: continue
            val sec = (now - tokStart[s]) / 1000.0
            if (sec < 0 || sec > TokenStream.lifetime) continue
            any = true
            val fg = sec / TokenStream.GLYPH_TIME
            if (fg < 1) {
                tokText.alpha = (255 * (if (fg < 0.45) 1.0 else (1 - fg) / 0.55)).toInt().coerceIn(0, 255)
                val save = canvas.save()
                canvas.translate(tokGX[s], tokGY[s])
                val sc = (0.9 + 0.35 * fg).toFloat()
                canvas.scale(sc, sc)
                canvas.drawText(g, 0f, base, tokText)
                canvas.restoreToCount(save)
            }
            for (i in 0 until tokN[s]) {
                val f = (sec - TokenStream.delay(i)) / TokenStream.FLIGHT
                if (f < 0 || f >= 1) continue
                val o = (s * TokenStream.MAX_CHIPS + i) * 6
                TokenStream.point(tokPts[o], tokPts[o + 1], tokPts[o + 2], tokPts[o + 3], tokPts[o + 4], tokPts[o + 5],
                    TokenStream.ease(f), tokTmp)
                val a = TokenStream.alpha(f); val k = TokenStream.scale(f).toFloat()
                val save = canvas.save()
                canvas.translate(tokTmp[0].toFloat(), tokTmp[1].toFloat())
                canvas.scale(k, k)
                tokGlow.color = TokenStream.COLORS[i % 3] or (0xFF shl 24)
                tokGlow.alpha = (90 * a).toInt()
                tokRect.set(-cw / 2 - gp, -ch / 2 - gp, cw / 2 + gp, ch / 2 + gp)
                canvas.drawRoundRect(tokRect, cr + gp, cr + gp, tokGlow)
                val p = tokChip[i % 3]!!
                p.alpha = (255 * a).toInt()
                tokRect.set(-cw / 2, -ch / 2, cw / 2, ch / 2)
                canvas.drawRoundRect(tokRect, cr, cr, p)
                canvas.restoreToCount(save)
            }
        }
        val fs = (now - shimStart) / (ShimmerGate.DURATION * 1000)
        if (fs in 0.0..1.0 && shimBandW > 0f) {
            any = true
            val e = fs * fs * (3 - 2 * fs)
            val save = canvas.save()
            canvas.clipRect(shimBar)
            canvas.translate(shimBar.left + ShimmerGate.left(e, shimBar.width().toDouble()).toFloat(), shimBar.top)
            canvas.drawRect(0f, 0f, shimBandW, shimBar.height(), shimPaint)
            canvas.restoreToCount(save)
        }
        return any
    }

    // Test: Token AI
    internal fun tokenChipCount(slot: Int): Int = tokN[slot]
    internal fun tokenPath(slot: Int, i: Int): DoubleArray = tokPts.copyOfRange((slot * TokenStream.MAX_CHIPS + i) * 6,
        (slot * TokenStream.MAX_CHIPS + i) * 6 + 6)
    internal val tokenGlyphs: List<String?> get() = tokGlyph.toList()
    internal val shimmerActive: Boolean get() = (SystemClock.uptimeMillis() - shimStart) <= ShimmerGate.DURATION * 1000
    internal val shimmerRect: RectF get() = shimBar

    private fun fireSand(x: Float, y: Float, now: Long) {
        if (width <= 0 || height <= 0) return
        val pile = sand?.takeIf { it.columns == SandPile.columnsFor((width / density).toDouble()) }
            ?: SandPile((width / density).toDouble()).also { sand = it }
        // Đang lún dở ⇒ chốt mức lún hiện tại vào đống rồi gõ tiếp từ đó.
        val k = SandPile.sinkFactor(now - sandLast)
        if (k < 1.0) { if (k <= 0.0) pile.clear() else pile.scale(k) }
        sandLast = now
        grainSeq++
        for (i in 0 until SandPile.GRAINS_PER_TAP) {
            val g = grainCursor; grainCursor = (g + 1) % SandPile.FLYING
            if (grainAlive[g]) pile.deposit((grainX[g] / density).toDouble())   // hạt cũ bị thay: cho đáp luôn
            val gx = (x + SandPile.spread(i, grainSeq) * density).toFloat().coerceIn(0f, width - 1f)
            val floor = height - (pile.surface((gx / density).toDouble()) * density).toFloat()
            grainX[g] = gx; grainY[g] = y; grainStart[g] = now + i * 25L
            grainFallMs[g] = Math.round(SandPile.fallTime(((floor - y) / density).toDouble()) * 1000)
            grainAlive[g] = true
        }
    }

    // MARK: đợt 3 — vẽ

    private fun drawPlasma(canvas: Canvas, now: Long): Boolean {
        var any = false
        stroke.strokeJoin = Paint.Join.ROUND; stroke.strokeCap = Paint.Cap.ROUND
        for (s in 0 until PlasmaArc.POOL) {
            val t = now - arcStart[s]
            val a = PlasmaArc.alpha(t).toFloat()
            if (a <= 0f) continue
            any = true
            if (arcLinked[s]) {
                stroke.color = PlasmaArc.COLOR or (0xFF shl 24); stroke.strokeWidth = 5 * density; stroke.alpha = (255 * 0.5f * a).toInt()
                canvas.drawPath(arcPaths[s], stroke)
                stroke.color = PlasmaArc.CORE or (0xFF shl 24); stroke.strokeWidth = 1.5f * density; stroke.alpha = (255 * a).toInt()
                canvas.drawPath(arcPaths[s], stroke)
            }
            fill.color = PlasmaArc.COLOR or (0xFF shl 24); fill.alpha = (255 * 0.45f * a).toInt()
            canvas.drawCircle(arcX[s], arcY[s], (PlasmaArc.SPARK_RADIUS * density).toFloat() * (1.3f - 0.3f * a), fill)
        }
        return any
    }

    /** Rung combo: chỉ đặt translation của view hàng phím (RenderThread) — xong ⇒ về 0, thôi hẹn khung hình. */
    private fun stepShake(now: Long): Boolean {
        val tg = shakeTarget ?: return false
        val dt = now - shakeStart
        if (dt < 0 || dt >= ShakeFx.DURATION_MS) {
            if (tg.translationX != 0f || tg.translationY != 0f) { tg.translationX = 0f; tg.translationY = 0f }
            return false
        }
        val a = shakeAmp / density
        tg.translationX = (ShakeFx.offsetX(dt, a.toDouble()) * density).toFloat()
        tg.translationY = (ShakeFx.offsetY(dt, a.toDouble()) * density).toFloat()
        return true
    }

    private fun drawLaser(canvas: Canvas, now: Long): Boolean {
        var any = false
        stroke.strokeCap = Paint.Cap.ROUND
        for (s in 0 until LaserBeam.POOL) {
            val t = now - laserStart[s]
            val a = LaserBeam.alpha(t).toFloat()
            if (a <= 0f) continue
            any = true
            val r = LaserBeam.reach(t).toFloat()
            val ex = laserOx[s] + (laserTx[s] - laserOx[s]) * r; val ey = laserOy[s] + (laserTy[s] - laserOy[s]) * r
            stroke.color = LaserBeam.COLOR or (0xFF shl 24); stroke.strokeWidth = (LaserBeam.GLOW_WIDTH * density).toFloat()
            stroke.alpha = (255 * 0.55f * a).toInt()
            canvas.drawLine(laserOx[s], laserOy[s], ex, ey, stroke)
            stroke.color = 0xFFFFFFFF.toInt(); stroke.strokeWidth = (LaserBeam.CORE_WIDTH * density).toFloat(); stroke.alpha = (255 * a).toInt()
            canvas.drawLine(laserOx[s], laserOy[s], ex, ey, stroke)
            if (r >= 1f) {   // chạm phím: đốm loé
                fill.color = LaserBeam.COLOR or (0xFF shl 24); fill.alpha = (255 * 0.5f * a).toInt()
                canvas.drawCircle(ex, ey, 6 * density * (1.4f - 0.4f * a), fill)
            }
        }
        return any
    }

    private fun drawGlitch(canvas: Canvas, now: Long): Boolean {
        var any = false
        val r6 = 5 * density
        for (s in 0 until GlitchFx.POOL) {
            val step = GlitchFx.step(now - glStart[s])
            if (step >= GlitchFx.STEPS) continue
            any = true
            val rc = glRect[s]
            val sp = (GlitchFx.split(step) * density).toFloat()
            fill.color = GlitchFx.CYAN or (0xFF shl 24); fill.alpha = 80
            glTmp.set(rc); glTmp.offset(-sp, 0f); canvas.drawRoundRect(glTmp, r6, r6, fill)
            fill.color = GlitchFx.MAGENTA or (0xFF shl 24); fill.alpha = 80
            glTmp.set(rc); glTmp.offset(sp, 0f); canvas.drawRoundRect(glTmp, r6, r6, fill)
            GlitchFx.slices(step, glVariant[s], glSlices)
            for (k in 0 until GlitchFx.SLICES) {
                val top = rc.top + rc.height() * glSlices[3 * k].toFloat()
                val hh = rc.height() * glSlices[3 * k + 1].toFloat()
                val dx = (glSlices[3 * k + 2] * GlitchFx.MAX_SHIFT * density).toFloat()
                fill.color = keyFill or (0xFF shl 24); fill.alpha = 242
                canvas.drawRect(rc.left + dx, top, rc.right + dx, top + hh, fill)
                fill.color = (if (k % 2 == 0) GlitchFx.CYAN else GlitchFx.MAGENTA) or (0xFF shl 24); fill.alpha = 200
                canvas.drawRect(rc.left + dx, top, rc.right + dx, top + density, fill)
            }
        }
        return any
    }

    private fun drawTone(canvas: Canvas, now: Long): Boolean {
        var any = false
        for (s in 0 until ToneBurst.POOL) {
            val kind = ToneFx.entries[toneKind[s]]
            val trajs = toneTraj[kind.ordinal]
            val col = ToneBurst.color(kind) or (0xFF shl 24)
            val strokeShape = kind != ToneFx.SAC && kind != ToneFx.HUYEN && kind != ToneFx.NANG
            for (i in trajs.indices) {
                val t = trajs[i]
                val f = ((now - toneStart[s]) / (t.duration * 1000.0)).toFloat()
                if (f < 0f || f >= 1f) continue
                any = true
                val e = if (ToneBurst.easeIn(kind)) f * f else 1f - (1f - f) * (1f - f)
                val sc = (t.scaleFrom + (t.scaleTo - t.scaleFrom) * f).toFloat()
                val a = if (f < 0.5f) 1f else 1f - (f - 0.5f) / 0.5f
                val save = canvas.save()
                canvas.translate(toneX[s] + (t.dx * e * density).toFloat(), toneY[s] + (t.dy * e * density).toFloat())
                if (t.rotation != 0.0) canvas.rotate(Math.toDegrees(t.rotation * f).toFloat())
                if (ToneBurst.stretchesX(kind)) canvas.scale(sc * density, density) else canvas.scale(sc * density, sc * density)
                if (strokeShape) {
                    stroke.color = col; stroke.alpha = (255 * a).toInt(); stroke.strokeWidth = 2f
                    stroke.strokeCap = Paint.Cap.ROUND; stroke.strokeJoin = Paint.Join.ROUND
                    canvas.drawPath(tonePaths[kind.ordinal], stroke)
                } else {
                    fill.color = col; fill.alpha = (255 * a).toInt()
                    canvas.drawPath(tonePaths[kind.ordinal], fill)
                }
                canvas.restoreToCount(save)
            }
        }
        return any
    }

    private fun drawKeyword(canvas: Canvas, now: Long): Boolean {
        var any = false
        for (s in 0 until KeywordBursts.POOL) {
            val kind = KeywordKind.entries[kwKind[s]]
            val dt = (now - kwStart[s]) / 1000.0
            if (dt < 0 || dt >= KeywordBursts.lifetime(kind)) continue
            any = true
            val ems = KeywordBursts.emojis(kind)
            for (p in KeywordBursts.particles(kind)) {
                val f = ((dt - p.delay) / p.traj.duration).toFloat()
                if (f < 0f || f >= 1f) continue
                val t = p.traj
                val e = if (p.easeIn) f * f else 1f - (1f - f) * (1f - f)
                val sw = if (t.sway != 0.0) t.sway * Math.sin(f * 2 * Math.PI) else 0.0
                val px = kwX[s] + ((p.x0 + t.dx * e + sw) * density).toFloat()
                val py = kwY[s] + ((p.y0 + t.dy * e) * density).toFloat()
                val sc = (t.scaleFrom + (t.scaleTo - t.scaleFrom) * f).toFloat()
                val a = if (f < 0.5f) 1f else 1f - (f - 0.5f) / 0.5f
                if (p.shape == KeywordBursts.Shape.EMOJI) {
                    val b = ems.getOrNull(p.color)?.let { kwEmoji[it] } ?: continue
                    bmpPaint.alpha = (255 * a).toInt()
                    mtx.setTranslate(-b.width / 2f, -b.height / 2f)
                    mtx.postRotate(Math.toDegrees(t.rotation * f).toFloat())
                    mtx.postScale(sc, sc); mtx.postTranslate(px, py)
                    canvas.drawBitmap(b, mtx, bmpPaint)
                    continue
                }
                val save = canvas.save()
                canvas.translate(px, py)
                if (t.rotation != 0.0) canvas.rotate(Math.toDegrees(t.rotation * f).toFloat())
                canvas.scale(sc * density, sc * density)
                fill.color = p.color or (0xFF shl 24); fill.alpha = (255 * a).toInt()
                when (p.shape) {
                    KeywordBursts.Shape.HEART -> canvas.drawPath(kwHeart, fill)
                    KeywordBursts.Shape.SPARK -> canvas.drawPath(kwStar, fill)
                    KeywordBursts.Shape.PUFF -> { fill.alpha = (255 * 0.7f * a).toInt(); canvas.drawCircle(0f, 0f, 6f, fill) }
                    KeywordBursts.Shape.PAPER -> canvas.drawRect(-1.5f, -2.5f, 1.5f, 2.5f, fill)
                    KeywordBursts.Shape.CRACKER -> {
                        kwRect.set(-2.5f, -5.5f, 2.5f, 5.5f); canvas.drawRoundRect(kwRect, 1f, 1f, fill)
                        fill.color = KeywordBursts.GOLD or (0xFF shl 24); fill.alpha = (255 * a).toInt()
                        canvas.drawRect(-2.5f, -1f, 2.5f, 1f, fill)
                    }
                    KeywordBursts.Shape.ENVELOPE -> {
                        kwRect.set(-6f, -8f, 6f, 8f); canvas.drawRoundRect(kwRect, 1.5f, 1.5f, fill)
                        fill.color = KeywordBursts.GOLD or (0xFF shl 24); fill.alpha = (255 * a).toInt()
                        canvas.drawCircle(0f, -1f, 2.6f, fill)
                    }
                    else -> {}
                }
                canvas.restoreToCount(save)
            }
        }
        return any
    }

    private fun drawLetters(canvas: Canvas, now: Long): Boolean {
        var any = false
        textPaint.textSize = (FlyingLetters.SIZE * density).toFloat()
        textPaint.color = color or (0xFF shl 24)
        val fm = textPaint.fontMetrics
        val base = -(fm.ascent + fm.descent) / 2
        for (s in 0 until FlyingLetters.POOL) {
            val g = letterText[s] ?: continue
            val f = ((now - letterStart[s]) / (FlyingLetters.DURATION * 1000)).toFloat()
            if (f < 0f || f >= 1f) continue
            any = true
            val e = 1f - (1f - f) * (1f - f)
            textPaint.alpha = (255 * (if (f < 0.4f) 1f else 1f - (f - 0.4f) / 0.6f)).toInt()
            val save = canvas.save()
            canvas.translate(letterX[s] + (FlyingLetters.drift(letterSeed[s]) * e * density).toFloat(),
                letterY[s] - (FlyingLetters.RISE * e * density).toFloat())
            canvas.rotate(Math.toDegrees(FlyingLetters.spin(letterSeed[s]) * f).toFloat())
            val sc = 0.8f + 0.4f * f
            canvas.scale(sc, sc)
            canvas.drawText(g, 0f, base, textPaint)
            canvas.restoreToCount(save)
        }
        return any
    }

    /** Hạt rơi (gia tốc) rồi đáp vào mảng chiều cao; đống lún sau khi nghỉ. Đứng yên ⇒ chỉ hẹn MỘT lần lúc bắt đầu lún. */
    private fun drawSand(canvas: Canvas, now: Long): Boolean {
        val pile = sand ?: return false
        var flying = false
        fill.color = SandPile.COLOR or (0xFF shl 24); fill.alpha = 235
        val r = (SandPile.GRAIN_SIZE / 2 * density).toFloat()
        for (g in 0 until SandPile.FLYING) {
            if (!grainAlive[g]) continue
            val t = now - grainStart[g]
            if (t >= grainFallMs[g]) { grainAlive[g] = false; pile.deposit((grainX[g] / density).toDouble()); continue }
            flying = true
            if (t < 0) continue
            val ts = t / 1000.0
            canvas.drawCircle(grainX[g], grainY[g] + (0.5 * SandPile.GRAVITY * ts * ts * density).toFloat(), r, fill)
        }
        val idle = now - sandLast
        val k = SandPile.sinkFactor(idle)
        if (k <= 0.0 && !flying) { pile.clear(); return false }
        if (!pile.isEmpty) {
            val sx = (SandPile.COLUMN * density).toFloat()
            sandPath.rewind()
            sandPath.moveTo(0f, height.toFloat())
            for (c in 0 until pile.columns) {
                val y = height - (pile.heights[c] * k * density).toFloat()
                sandPath.lineTo(c * sx, y); sandPath.lineTo((c + 1) * sx, y)
            }
            sandPath.lineTo(pile.columns * sx, height.toFloat()); sandPath.close()
            canvas.drawPath(sandPath, fill)
        }
        if (flying || (k < 1.0 && !pile.isEmpty)) return true
        if (!pile.isEmpty) postInvalidateDelayed(maxOf(16L, SandPile.IDLE_MS - idle))   // đứng yên tới lúc lún: 0 khung hình
        return false
    }

    // MARK: Biển — sóng vỗ bờ + bọt bắn + bong bóng + cá (= iOS KeyEffectOverlay, cùng hàm thuần SeaFx)

    private fun fireSea(x: Float, y: Float, now: Long) {
        val prev = seaLevel
        val lv = combo.press(now)
        seaLevel = lv
        val s = seaTapCursor; seaTapCursor = (s + 1) % SeaFx.TAP_SLOTS
        seaTapStart[s] = now; seaTapX[s] = x; seaTapY[s] = y
        if (SeaFx.shouldLaunch((now - seaLastWave) / 1000.0)) {
            seaLastWave = now
            val w = seaWaveCursor; seaWaveCursor = (w + 1) % SeaFx.MAX_WAVES
            seaWaveStart[w] = now; seaWaveSize[w] = SeaFx.size(lv)
            onSeaWave?.invoke(seaWaveSize[w])
        }
        if (SeaFx.fishShouldSwim(lv, prev, (now - seaLastFish) / 1000.0)) {
            seaLastFish = now; seaFishStart = now; seaFishCur = seaFishSeq++
        }
    }

    /** Test: số sóng / chùm bọt đang chạy lúc [now], cỡ sóng ô [i], cá đang bơi. */
    internal fun seaWavesAlive(now: Long): Int = seaWaveStart.count { now - it in 0 until SEA_LIFE_MS }
    internal fun seaWaveSize(i: Int): Double = seaWaveSize[i]
    internal fun seaFishSwimming(now: Long): Boolean = now - seaFishStart in 0 until SEA_FISH_MS

    /** Vẽ Biển lúc [now]; true = còn gì đang chạy. Hết sóng / bọt / cá ⇒ false (thôi hẹn khung hình). */
    private fun drawSea(canvas: Canvas, now: Long): Boolean {
        var any = false
        val wDp = (width / density).toDouble()
        val h = height.toFloat()
        val accent = color or (0xFF shl 24)
        val x0 = -SeaFx.WAVELENGTH; val x1 = wDp + SeaFx.WAVELENGTH
        for (w in 0 until SeaFx.MAX_WAVES) {
            val t = (now - seaWaveStart[w]) / 1000.0
            if (t < 0 || t >= SeaFx.LIFE) continue
            any = true
            val sz = seaWaveSize[w]; val ph = SeaFx.phase(w)
            // Bờ: vệt ướt (cao WASH_MAX × cỡ) + bọt tràn (cao washHeight).
            val wet = SeaFx.wetAlpha(t)
            if (wet > 0) {
                shoreBand(x0, x1, ph, sz, h)
                fill.color = accent; fill.alpha = (255 * wet).toInt(); canvas.drawPath(seaPath, fill)
            }
            val wash = SeaFx.washHeight(t, sz)
            if (wash > 0) {
                shoreBand(x0, x1, ph, wash / SeaFx.WASH_MAX, h)
                fill.color = 0xFFFFFFFF.toInt(); fill.alpha = if (dark) 153 else 191
                canvas.drawPath(seaPath, fill)
                stroke.color = accent; stroke.alpha = 178; stroke.strokeWidth = density
                canvas.drawPath(seaEdge, stroke)
            }
            // Sóng cuộn: thân + mép màu nhấn + mép bọt.
            val a = SeaFx.waveAlpha(t)
            if (a > 0) {
                val cy = (SeaFx.travel(t) * h).toFloat()
                val dx = SeaFx.driftX(t)
                seaPath.rewind(); seaEdge.rewind()
                var x = x0; var first = true
                while (x <= x1 + 1e-9) {
                    val px = ((x + dx) * density).toFloat()
                    val py = cy + (SeaFx.crestOffset(x, ph) * sz * density).toFloat()
                    if (first) { seaPath.moveTo(px, py); seaEdge.moveTo(px, py) } else { seaPath.lineTo(px, py); seaEdge.lineTo(px, py) }
                    first = false
                    x += SeaFx.STEP
                }
                x -= SeaFx.STEP
                while (x >= x0 - 1e-9) {
                    seaPath.lineTo(((x + dx) * density).toFloat(), cy + (SeaFx.bodyTop(x, ph) * sz * density).toFloat())
                    x -= SeaFx.STEP
                }
                seaPath.close()
                stroke.strokeJoin = Paint.Join.ROUND; stroke.strokeCap = Paint.Cap.ROUND
                fill.color = accent; fill.alpha = (255 * SeaFx.BODY_ALPHA * a).toInt(); canvas.drawPath(seaPath, fill)
                val save = canvas.save()
                canvas.translate(0f, (1.8 * sz * density).toFloat())
                stroke.color = accent; stroke.alpha = (255 * 0.6 * a).toInt(); stroke.strokeWidth = density
                canvas.drawPath(seaEdge, stroke)
                canvas.restoreToCount(save)
                stroke.color = 0xFFFFFFFF.toInt(); stroke.alpha = (255 * SeaFx.FOAM_ALPHA * a).toInt()
                stroke.strokeWidth = (SeaFx.FOAM_WIDTH * density).toFloat()
                canvas.drawPath(seaEdge, stroke)
            }
        }
        // Bọt bắn + bong bóng ở phím.
        val dr = (SeaFx.DROPLET_RADIUS * density).toFloat()
        for (s in 0 until SeaFx.TAP_SLOTS) {
            val t = (now - seaTapStart[s]) / 1000.0
            if (t < 0 || t >= SeaFx.BUBBLE_DURATION) continue
            any = true
            val fd = t / SeaFx.DROPLET_DURATION
            if (fd < 1) {
                val al = if (fd < 0.6) 1.0 else 1 - (fd - 0.6) / 0.4
                for (i in 0 until SeaFx.DROPLETS_PER_TAP) {
                    SeaFx.droplet(i, fd, seaTmp)
                    val px = seaTapX[s] + (seaTmp[0] * density).toFloat(); val py = seaTapY[s] + (seaTmp[1] * density).toFloat()
                    fill.color = 0xFFFFFFFF.toInt(); fill.alpha = (255 * al).toInt(); canvas.drawCircle(px, py, dr, fill)
                    if (!dark) {
                        stroke.color = accent; stroke.alpha = (204 * al).toInt(); stroke.strokeWidth = 0.6f * density
                        canvas.drawCircle(px, py, dr, stroke)
                    }
                }
            }
            val fb = t / SeaFx.BUBBLE_DURATION
            for (i in 0 until SeaFx.BUBBLES_PER_TAP) {
                SeaFx.bubble(i, fb, seaTmp)
                val px = seaTapX[s] + (seaTmp[0] * density).toFloat(); val py = seaTapY[s] + (seaTmp[1] * density).toFloat()
                val r = (SeaFx.BUBBLE_RADIUS * seaTmp[2] * density).toFloat(); val al = seaTmp[3]
                fill.color = accent; fill.alpha = (255 * 0.15 * al).toInt(); canvas.drawCircle(px, py, r, fill)
                stroke.color = if (dark) 0xFFFFFFFF.toInt() else accent
                stroke.alpha = (255 * (if (dark) 0.85 else 1.0) * al).toInt(); stroke.strokeWidth = 1.2f * density
                canvas.drawCircle(px, py, r, stroke)
            }
        }
        // Cá.
        val ff = (now - seaFishStart) / 1000.0 / SeaFx.FISH_DURATION
        if (ff >= 0 && ff < 1) {
            any = true
            val bmps = seaFishBmp
            if (bmps != null && bmps.isNotEmpty()) {
                val b = bmps[seaFishCur % bmps.size]
                val rtl = SeaFx.fishRightToLeft(seaFishCur)
                val px = (SeaFx.fishX(ff, wDp, rtl) * density).toFloat()
                val py = ((SeaFx.fishY(seaFishCur, (h / density).toDouble()) + SeaFx.fishBobY(ff)) * density).toFloat()
                val k = (SeaFx.FISH_SIZE * density / b.width).toFloat()
                bmpPaint.alpha = (255 * SeaFx.fishAlpha(ff)).toInt().coerceIn(0, 255)
                mtx.setTranslate(-b.width / 2f, -b.height / 2f)
                mtx.postScale(if (rtl) k else -k, k)      // emoji cá quay mặt sang trái: bơi sang phải ⇒ lật ngang
                mtx.postTranslate(px, py)
                canvas.drawBitmap(b, mtx, bmpPaint)
            }
        }
        return any
    }

    /** Dải bờ (gốc = đáy view, mép trên gợn [SeaFx.washTop] nhân [k]) vào [seaPath]; mép trên riêng vào [seaEdge]. */
    private fun shoreBand(x0: Double, x1: Double, ph: Double, k: Double, h: Float) {
        seaPath.rewind(); seaEdge.rewind()
        seaPath.moveTo((x0 * density).toFloat(), h)
        var x = x0; var first = true
        while (x <= x1 + 1e-9) {
            val px = (x * density).toFloat(); val py = h + (SeaFx.washTop(x, ph) * k * density).toFloat()
            seaPath.lineTo(px, py)
            if (first) seaEdge.moveTo(px, py) else seaEdge.lineTo(px, py)
            first = false
            x += SeaFx.STEP
        }
        seaPath.lineTo(((x - SeaFx.STEP) * density).toFloat(), h)
        seaPath.close()
    }

    /** Test: số hạt cát đang bay. */
    internal fun grainsAlive(): Int = grainAlive.count { it }

    /** Hình vector dp của Dấu thanh / Từ khoá — dựng MỘT lần lúc đổi kiểu. */
    private fun buildFx3Paths(e: KeyEffect) {
        if (e == KeyEffect.TONE) {
            for (k in ToneFx.entries) {
                val p = tonePaths[k.ordinal]; p.reset()
                when (k) {
                    ToneFx.SAC, ToneFx.HUYEN -> star4(p, 3.5f, 1f)
                    ToneFx.HOI -> { p.moveTo(-3.5f, -2.5f); p.quadTo(-3f, -6.5f, 1f, -6f); p.quadTo(4.5f, -5f, 3f, -2f)
                        p.quadTo(1.5f, 0.5f, 0f, 1f); p.lineTo(0f, 4f) }
                    ToneFx.NGA -> { p.moveTo(-8f, 1f); p.quadTo(-4f, -5f, 0f, 0f); p.quadTo(4f, 5f, 8f, -1f) }
                    ToneFx.NANG -> { p.moveTo(0f, -6f); p.quadTo(5f, 0f, 3.5f, 2.5f); p.quadTo(0f, 6.5f, -3.5f, 2.5f); p.quadTo(-5f, 0f, 0f, -6f); p.close() }
                    ToneFx.HAT -> { p.moveTo(-5f, 2.5f); p.lineTo(0f, -2.5f); p.lineTo(5f, 2.5f) }
                    ToneFx.HORN -> { p.moveTo(-1f, 3f); p.quadTo(4f, 2f, 3f, -3f); p.lineTo(5f, -4f) }
                    ToneFx.STROKE -> { p.moveTo(-5f, 0f); p.lineTo(5f, 0f) }
                }
            }
        }
        if (e == KeyEffect.KEYWORD) {
            buildPath(KeyEffect.HEART, 0, kwHeart)
            kwStar.reset(); star4(kwStar, 3.5f, 1.1f)
        }
    }

    /** Sao 4 cánh (tia lửa). */
    private fun star4(p: Path, r: Float, inner: Float) {
        for (k in 0 until 8) {
            val a = k * Math.PI / 4 - Math.PI / 2
            val rr = if (k % 2 == 0) r else inner
            val x = (Math.cos(a) * rr).toFloat(); val y = (Math.sin(a) * rr).toFloat()
            if (k == 0) p.moveTo(x, y) else p.lineTo(x, y)
        }
        p.close()
    }

    // MARK: dựng sẵn

    /** Ảnh dựng NGOÀI main (dải Matrix, emoji) — một lần mỗi lần đổi kiểu. */
    private fun prewarm(e: KeyEffect) {
        when (e) {
            KeyEffect.MATRIX -> if (strips == null) Thread({
                val s = Array(MatrixRain.STRIP_COUNT) { renderStrip(it) }
                post { if (sim.effect == KeyEffect.MATRIX) strips = s }
            }, "vt-fx-matrix").start()
            KeyEffect.KEYWORD -> if (kwEmoji.isEmpty()) Thread({
                val m = KeywordBursts.allEmojis.associateWith { renderEmoji(it) }
                post { if (sim.effect == KeyEffect.KEYWORD) kwEmoji = m }
            }, "vt-fx-keyword").start()
            KeyEffect.SEA -> if (seaFishBmp == null) Thread({
                val b = Array(SeaFx.FISH_GLYPHS.size) { renderEmoji(SeaFx.FISH_GLYPHS[it]) }
                post { if (sim.effect == KeyEffect.SEA) seaFishBmp = b }
            }, "vt-fx-sea").start()
            KeyEffect.EMOJIWORD -> if (emojiBitmaps.isEmpty()) Thread({
                val m = EmojiWords.distinctEmojis.associateWith { renderEmoji(it) }
                post { if (sim.effect == KeyEffect.EMOJIWORD) emojiBitmaps = m + emojiBitmaps }
            }, "vt-fx-emoji").start()
            else -> {}
        }
        if (e != KeyEffect.MATRIX) strips = null
        if (e != KeyEffect.EMOJIWORD) emojiBitmaps = emptyMap()
        if (e != KeyEffect.KEYWORD) kwEmoji = emptyMap()
        if (e != KeyEffect.SEA) seaFishBmp = null
        if (e == KeyEffect.MATRIX && width > 0) columns = Array(MatrixRain.columnCount((width / density).toDouble())) { MatrixRain.column(it) }
    }

    private fun renderStrip(strip: Int): Bitmap {
        val w = Math.ceil(MatrixRain.COLUMN_WIDTH * density).toInt()
        val h = Math.ceil(MatrixRain.STRIP_HEIGHT * density).toInt()
        val b = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val c = Canvas(b)
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = android.graphics.Typeface.MONOSPACE
            textSize = (MatrixRain.GLYPH_SIZE * density).toFloat()
            textAlign = Paint.Align.CENTER
        }
        for (r in 0 until MatrixRain.ROWS) {
            val head = r == MatrixRain.ROWS - 1
            p.color = (if (head) MatrixRain.HEAD else MatrixRain.GREEN) or (0xFF shl 24)
            p.alpha = (255 * MatrixRain.rowAlpha(r)).toInt()
            val baseline = ((r + 1) * MatrixRain.LINE_HEIGHT * density - 3 * density).toFloat()
            c.drawText(MatrixRain.glyph(strip, r).toString(), w / 2f, baseline, p)
        }
        return b
    }

    private fun renderEmoji(e: String): Bitmap {
        val size = Math.ceil(30.0 * density).toInt()
        val b = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { textSize = 24 * density; textAlign = Paint.Align.CENTER }
        val fm = p.fontMetrics
        Canvas(b).drawText(e, size / 2f, size / 2f - (fm.ascent + fm.descent) / 2, p)
        return b
    }

    /** Đốm mực tròn mép mềm (gradient tâm) — một lần mỗi màu. */
    private fun renderBlob(c: Int): Bitmap {
        val size = Math.ceil(InkBloom.SIZE * density).toInt()
        val b = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val r = size / 2f
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            shader = RadialGradient(r, r, r, intArrayOf(c, (c and 0xFFFFFF) or (0x99 shl 24), c and 0xFFFFFF),
                floatArrayOf(0f, 0.45f, 1f), Shader.TileMode.CLAMP)
        }
        Canvas(b).drawCircle(r, r, r, p)
        return b
    }

    /** Đốm sáng mềm (Đèn lồng: lõi ấm + quầng màu; Sương ma: mờ tan mép) — một lần mỗi màu. = iOS renderGlow. */
    private fun renderGlow(e: KeyEffect, rgb: Int): Bitmap {
        val size = Math.ceil(GlowSprite.SIZE * density).toInt()
        val b = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val r = size / 2f
        val pos = GlowSprite.positions(e); val al = GlowSprite.alphas(e)
        val cols = IntArray(pos.size) { i ->
            val c = if (e == KeyEffect.LANTERN && i == 0) GlowSprite.CORE else rgb
            (c and 0xFFFFFF) or ((al[i] * 255).toInt() shl 24)
        }
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            shader = RadialGradient(r, r, r, cols, FloatArray(pos.size) { pos[it].toFloat() }, Shader.TileMode.CLAMP)
        }
        Canvas(b).drawCircle(r, r, r, p)
        return b
    }

    /** Hình vector hạt thứ [i] (dp, quanh gốc 0,0) — cùng hình iOS KeyEffectShapes. */
    private fun buildPath(e: KeyEffect, i: Int, path: Path) {
        path.reset()
        when (e) {
            KeyEffect.HEART -> {
                val s = 8f
                path.moveTo(0f, s * 0.9f)
                path.cubicTo(-s * 0.6f, s * 0.5f, -s, s * 0.15f, -s, -s * 0.2f)
                path.cubicTo(-s, -s * 0.85f, -s * 0.2f, -s * 0.95f, 0f, -s * 0.55f)
                path.cubicTo(s * 0.2f, -s * 0.95f, s, -s * 0.85f, s, -s * 0.2f)
                path.cubicTo(s, s * 0.15f, s * 0.6f, s * 0.5f, 0f, s * 0.9f)
                path.close()
            }
            KeyEffect.BUBBLE -> path.addCircle(0f, 0f, 7f, Path.Direction.CW)
            KeyEffect.RIPPLE -> path.addCircle(0f, 0f, 20f, Path.Direction.CW)
            KeyEffect.PETAL -> petal(path, 8f)
            KeyEffect.FIREWORK -> {
                for (k in 0 until 8) {
                    val a = k * Math.PI / 4 - Math.PI / 2
                    val r = if (k % 2 == 0) 5.0 else 1.6
                    val x = (Math.cos(a) * r).toFloat(); val y = (Math.sin(a) * r).toFloat()
                    if (k == 0) path.moveTo(x, y) else path.lineTo(x, y)
                }
                path.close()
            }
            KeyEffect.BLOSSOM -> if (i % 2 == 0) {
                val r = 7f; val pr = r * 0.48f
                for (k in 0 until 5) {
                    val a = k * 2 * Math.PI / 5 - Math.PI / 2
                    path.addCircle((Math.cos(a) * (r - pr)).toFloat(), (Math.sin(a) * (r - pr)).toFloat(), pr, Path.Direction.CW)
                }
            } else petal(path, 6f)
            KeyEffect.COMBO -> {
                val s = 9f
                path.moveTo(0f, -s)
                path.cubicTo(s * 0.9f, -s * 0.1f, s * 0.75f, s * 0.7f, 0f, s * 0.7f)
                path.cubicTo(-s * 0.75f, s * 0.7f, -s * 0.9f, -s * 0.1f, 0f, -s)
                path.close()
            }
            KeyEffect.METEOR -> {
                val pts = MeteorStreak.polygon()
                path.moveTo(pts[0].toFloat(), pts[1].toFloat())
                for (k in 1 until pts.size / 2) path.lineTo(pts[2 * k].toFloat(), pts[2 * k + 1].toFloat())
                path.close()
            }
            KeyEffect.SNOW -> {
                // 6 nhánh, mỗi nhánh 1 thanh + 2 ngạnh (hình chữ nhật mảnh xoay) — như iOS snowflake(6).
                val r = 6f; val w = 0.7f
                val m = Matrix(); val tmp = Path()
                for (k in 0 until 6) {
                    tmp.reset(); tmp.addRect(-w / 2, -r, w / 2, 0f, Path.Direction.CW)
                    m.setRotate(k * 60f); tmp.transform(m); path.addPath(tmp)
                    for (side in intArrayOf(-1, 1)) {
                        tmp.reset(); tmp.addRect(-w / 2, -r * 0.32f, w / 2, 0f, Path.Direction.CW)
                        m.setRotate(side * 45f); m.postTranslate(0f, -r * 0.6f); m.postRotate(k * 60f)
                        tmp.transform(m); path.addPath(tmp)
                    }
                }
            }
            else -> {}
        }
    }

    private fun petal(path: Path, s: Float) {
        path.moveTo(0f, -s)
        path.quadTo(s * 0.9f, -s * 0.1f, 0f, s)
        path.quadTo(-s * 0.9f, -s * 0.1f, 0f, -s)
        path.close()
    }

    companion object {
        const val MAX_PENDING = 4
        const val STRIKES = 3
        const val SLOTS = 4
        const val EMOJI_MS = 1100L
        const val DEFAULT_W = 34f
        /** Rung dây: thời lượng (ms) = StringPluck.DURATION. */
        val STRING_MS = Math.round(StringPluck.DURATION * 1000)
        const val DEFAULT_H = 42f
        /** Biển: đời một con sóng / một lần cá bơi (ms). */
        val SEA_LIFE_MS = Math.round(SeaFx.LIFE * 1000)
        val SEA_FISH_MS = Math.round(SeaFx.FISH_DURATION * 1000)
        /** Sàn nhảy LED: số ô mỗi chùm = (2·(RINGS−1)+1)². */
        const val DANCE_TILES = (2 * (DanceFloor.RINGS - 1) + 1) * (2 * (DanceFloor.RINGS - 1) + 1)
    }
}
