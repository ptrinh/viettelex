package com.viettelex.android.ime

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Rect
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.os.SystemClock
import android.view.View
import com.viettelex.keyboard.BuddyCharacter
import com.viettelex.keyboard.BuddyDance
import com.viettelex.keyboard.BuddyHolidayClock
import com.viettelex.keyboard.BuddyDriver
import com.viettelex.keyboard.BuddyFX
import com.viettelex.keyboard.BuddyFraming
import com.viettelex.keyboard.BuddyHalo
import com.viettelex.keyboard.BuddyProp
import com.viettelex.keyboard.BuddyOutfit
import com.viettelex.keyboard.BuddyPart
import com.viettelex.keyboard.BuddyPhase
import com.viettelex.keyboard.BuddyPiece
import com.viettelex.keyboard.BuddyPose
import com.viettelex.keyboard.BuddyReaction
import com.viettelex.keyboard.BuddyRig
import com.viettelex.keyboard.BuddySVG
import com.viettelex.keyboard.BuddySignature
import com.viettelex.keyboard.BuddySeason
import com.viettelex.keyboard.BuddySprites
import com.viettelex.keyboard.BuddyStyle
import com.viettelex.keyboard.BuddyWords
import com.viettelex.keyboard.BuddyBirthday
import com.viettelex.keyboard.BuddyClock
import com.viettelex.keyboard.BuddyName
import com.viettelex.keyboard.Shape
import com.viettelex.keyboard.Show
import com.viettelex.keyboard.Stroke
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

/**
 * "Bạn đồng hành" — view vẽ khung vector ([BuddyRig]): Path dựng MỘT lần theo toạ độ thiết kế (canvas co giãn,
 * không dựng lại khi đổi cỡ), mỗi bộ phận xoay quanh điểm xoay bằng biến đổi canvas. Máy trạng thái + dáng:
 * [BuddyDriver] (thuần, test JVM). Chỉ vẽ khung kế (postInvalidateOnAnimation) khi đang chuyển động — ngủ yên /
 * đứng yên = 0 khung hình; mốc đổi trạng thái hẹn MỘT Runnable dựng sẵn. Không nhận chạm. = iOS BuddyView.
 */
@SuppressLint("ViewConstructor")
class BuddyView(
    context: Context,
    val character: BuddyCharacter,
    private val density: Float,
    bar: Int,
    lowPower: Boolean,
    val season: BuddySeason? = null,
    private val framing: BuddyFraming = BuddyFraming.BAR,
    /** Kiểu vẽ ([BuddyStyle], riêng từng nhân vật): Hoạt hình ⇒ ảnh atlas, không trang phục; Vẽ nét ⇒ khung vector. */
    artStyle: BuddyStyle = BuddyStyle.DEFAULT,
) : View(context) {
    val artStyle: BuddyStyle = artStyle.resolved(character)
    private object SpriteAssets {
        private val cache = object : android.util.LruCache<String, Bitmap>(3_145_728) {
            override fun sizeOf(key: String, value: Bitmap): Int = value.allocationByteCount
        }

        @Synchronized fun load(context: Context, character: BuddyCharacter): Bitmap? {
            if (character == BuddyCharacter.OFF) return null
            val name = "buddy-${character.id}-v2.png"
            cache.get(name)?.let { return it }
            return try {
                val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                context.assets.open(name).use { BitmapFactory.decodeStream(it, null, options) }
                options.inJustDecodeBounds = false
                options.inScaled = false
                val maxEdge = 512
                while (max(options.outWidth, options.outHeight) / options.inSampleSize > maxEdge) {
                    options.inSampleSize *= 2
                }
                context.assets.open(name).use {
                    BitmapFactory.decodeStream(it, null, options)
                }.also { if (it != null) cache.put(name, it) }
            } catch (_: java.io.IOException) { null } // Keep vector fallback for missing assets.
        }
    }
    // Hoạt hình: chỉ nạp ảnh atlas; thiếu ảnh ⇒ lùi về vector. Vẽ nét: không nạp ảnh.
    private var spriteAtlas = if (this.artStyle == BuddyStyle.SPRITE) SpriteAssets.load(context, character) else null
    private val spriteSource = Rect()
    private val spriteTarget = RectF()
    private val spritePaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
    private var signature: BuddySignature? = null
    private var signatureStart = 0.0
    private var signatureUntil = 0.0
    private var cheerSerial = 0
    private val prefs = context.getSharedPreferences(com.viettelex.keyboard.Keys.PREFS, Context.MODE_PRIVATE)
    private val petName = BuddyName.clean(prefs.getString(BuddyName.key(character), "") ?: "")
    private val birthdayToday: Boolean = java.util.Calendar.getInstance().let { cal ->
        BuddyBirthday.matches(prefs.getInt(BuddyBirthday.MONTH_KEY, 0), prefs.getInt(BuddyBirthday.DAY_KEY, 0),
            cal.get(java.util.Calendar.YEAR), cal.get(java.util.Calendar.MONTH) + 1, cal.get(java.util.Calendar.DAY_OF_MONTH))
    }
    private var clockPart = java.util.Calendar.getInstance().let { BuddyClock.part(it.get(java.util.Calendar.HOUR_OF_DAY), it.get(java.util.Calendar.MINUTE)) }
    val outfitClockPart = clockPart
    val appearanceDay = java.util.Calendar.getInstance().let {
        it.get(java.util.Calendar.YEAR) * 10000 + (it.get(java.util.Calendar.MONTH) + 1) * 100 + it.get(java.util.Calendar.DAY_OF_MONTH)
    }
    var onTimeChanged: (() -> Unit)? = null
    private var lastClockRead = Double.NEGATIVE_INFINITY
    private var lastTickle = Double.NEGATIVE_INFINITY
    private var lastNightYawn = Double.NEGATIVE_INFINITY
    private val tickleAfterYawn = Runnable { if (isAttachedToWindow) react(BuddyReaction.TICKLE) }
    private val momentTick = Runnable { if (isAttachedToWindow) { invalidate(); scheduleMoment() } }
    private var momentCheered = false
    private var momentMode = 0
    private var momentBurstStart = 0L

    private fun scheduleMoment() {
        removeCallbacks(momentTick)
        momentMode = 0
        if (!isAttachedToWindow || driver.lowPower) return
        val cal = java.util.Calendar.getInstance()
        val y = cal.get(java.util.Calendar.YEAR); val m = cal.get(java.util.Calendar.MONTH) + 1
        val d = cal.get(java.util.Calendar.DAY_OF_MONTH); val h = cal.get(java.util.Calendar.HOUR_OF_DAY)
        val minute = cal.get(java.util.Calendar.MINUTE); val second = cal.get(java.util.Calendar.SECOND)
        val fire = BuddyHolidayClock.fireworks(y, m, d, h, minute)
        val countdown = BuddyHolidayClock.countdown(m, d, h, minute, second)
        momentMode = if (fire) 1 else if (countdown != null) 2 else 0
        if (fire) momentBurstStart = System.currentTimeMillis()
        if (fire && !momentCheered) { momentCheered = true; driver.cheer(clock()) }
        val delay = when {
            fire -> 3000L
            countdown != null -> 1000L
            m == 12 && d == 31 -> {
                val target = cal.clone() as java.util.Calendar
                target.set(java.util.Calendar.HOUR_OF_DAY, 23); target.set(java.util.Calendar.MINUTE, 59); target.set(java.util.Calendar.SECOND, 57)
                (target.timeInMillis - cal.timeInMillis).takeIf { it > 0 }
            }
            else -> {
                val next = cal.clone() as java.util.Calendar
                next.add(java.util.Calendar.DAY_OF_MONTH, 1)
                val tet = BuddySeason.LUNAR_NEW_YEAR[next.get(java.util.Calendar.YEAR)]
                if (tet != null && tet.first == next.get(java.util.Calendar.MONTH) + 1 && tet.second == next.get(java.util.Calendar.DAY_OF_MONTH)) {
                    next.set(java.util.Calendar.HOUR_OF_DAY, 0); next.set(java.util.Calendar.MINUTE, 0); next.set(java.util.Calendar.SECOND, 0)
                    (next.timeInMillis - cal.timeInMillis).takeIf { it > 0 }
                } else null
            }
        }
        if (delay != null) postDelayed(momentTick, delay)
    }
    private var flamePath: Path? = null
    val rig: BuddyRig = BuddyRig.rig(character) ?: BuddyRig.CAT
    val driver = BuddyDriver(rig, lowPower).apply {
        this.character = this@BuddyView.character
        danceSeed = kotlin.random.Random.nextInt(1_000_001)
        vectorDance = spriteAtlas == null
    }
    private val outfit = BuddyOutfit.make(artStyle.season(season), character,
        artStyle == BuddyStyle.VECTOR && clockPart == BuddyClock.Part.NIGHT)
    private val pieces: List<BuddyPiece> = rig.pieces + outfit.pieces
    private val paths = Array(pieces.size) { Path() }
    private val fills = Array(pieces.size) { Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL } }
    private val strokes = Array(pieces.size) {
        Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND }
    }
    /** Chỉ số mảnh theo bộ phận (thứ tự vẽ). */
    private val byPart: Array<IntArray> = BuddyPart.entries.map { p -> pieces.indices.filter { pieces[it].part == p }.toIntArray() }.toTypedArray()
    private val zPaths = rig.zzz.map { z -> svg(BuddyRig.zPath(z.x, z.y, z.size)) }
    private val zPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE; strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND; strokeWidth = 4.5f
        color = 0xFF000000.toInt() or BuddyRig.Z_COLOR
    }
    private data class PropPiece(val path: Path, val fill: Paint?, val stroke: Paint?)
    private val holidayProps = mutableMapOf<BuddyReaction, List<PropPiece>>()
    private fun drawHoliday(c: Canvas, reaction: BuddyReaction, f: Float) {
        val art = holidayProps.getOrPut(reaction) {
            BuddyProp.make(reaction, rig).map { p ->
                val path = Path(); build(p, path)
                val fill = p.fill?.let { rgb -> Paint(Paint.ANTI_ALIAS_FLAG).apply { color = argb(rgb, p.alpha) } }
                val stroke = if (p.stroke == Stroke.None) null else Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    style = Paint.Style.STROKE; strokeWidth = p.width.toFloat()
                    strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND
                    color = when (val st = p.stroke) {
                        is Stroke.Color -> argb(st.rgb, 1.0)
                        Stroke.Ink -> argb(BuddyRig.INK, 1.0)
                        else -> outline
                    }
                }
                PropPiece(path, fill, stroke)
            }
        }
        val save = c.save(); val sc = pulse(f)
        if (reaction == BuddyReaction.BALLOON && !driver.lowPower) c.translate(0f, (kotlin.math.sin(clock() * Math.PI) * 3).toFloat())
        c.scale(sc, sc, rig.heart.x.toFloat(), rig.heart.y.toFloat())
        for (p in art) { p.fill?.let { c.drawPath(p.path, it) }; p.stroke?.let { c.drawPath(p.path, it) } }
        c.restoreToCount(save)
    }
    private val heartProp = svg(BuddyFX.heartPath(rig.heart.x, rig.heart.y, rig.heart.size))
    private val flushPath = Path().apply {
        addOval(RectF((rig.face.x - rig.face.rx).toFloat(), (rig.face.y - rig.face.ry).toFloat(),
            (rig.face.x + rig.face.rx).toFloat(), (rig.face.y + rig.face.ry).toFloat()), Path.Direction.CW)
    }
    private val browsPath = svg(rig.brows)
    private val k = (BuddyFX.PARTICLE_SIZE / 2)
    private val heartSmall = svg(BuddyFX.heartPath(0.0, 0.0, k * 0.85))
    private val dropSmall = svg(BuddyFX.dropPath(0.0, 0.0, k * 0.8))
    private val fxFill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val fxStroke = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeJoin = Paint.Join.ROUND }
    private val fxText = Paint(Paint.ANTI_ALIAS_FLAG).apply { textAlign = Paint.Align.CENTER; isFakeBoldText = true }
    private val cloud = Path()
    private val rect = RectF()
    private var cloudFor = ""
    private var outline = 0
    private var tones = BuddyHalo.colors(bar)
    /** Quầng: path gộp theo (bộ phận, bề rộng nét, có tô) — vẽ một lượt DƯỚI mọi bộ phận, cùng biến đổi. */
    private class Halo(val part: BuddyPart, val width: Double, val filled: Boolean, val path: Path = Path())
    private val halos: List<Halo> = run {
        val out = ArrayList<Halo>()
        for (p in pieces) {
            if (p.alpha != 1.0) continue
            val (w, f) = BuddyHalo.key(p)
            val h = out.firstOrNull { it.part == p.part && it.width == w && it.filled == f } ?: Halo(p.part, w, f).also { out += it }
            val tmp = Path(); build(p, tmp)
            if (p.turn != null) {
                val m = android.graphics.Matrix(); m.setRotate(p.turn!!.first.toFloat(), p.turn!!.second.toFloat(), p.turn!!.third.toFloat())
                tmp.transform(m)
            }
            h.path.addPath(tmp)
        }
        out
    }
    private val haloByPart: Array<List<Halo>> = BuddyPart.entries.map { p -> halos.filter { it.part == p } }.toTypedArray()
    private val haloPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL_AND_STROKE; strokeJoin = Paint.Join.ROUND; strokeCap = Paint.Cap.ROUND }
    private val haloStroke = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeJoin = Paint.Join.ROUND; strokeCap = Paint.Cap.ROUND }
    private val pose = BuddyPose()
    private var drawScale = 1f
    private var grawlixSerial = -1
    private var grawlixText = ""

    /** Ô nhân vật đang hiện (bar mở) — root đặt; ẩn ⇒ không vẽ gì. */
    var shownInSlot = true
        set(v) { if (field != v) { field = v; if (!v) halt(); invalidate() } }
    var maxFigureDp = 200f
        set(v) { field = v; invalidate() }
    /** Đồng hồ (giây) — test thay. */
    var clock: () -> Double = { SystemClock.uptimeMillis() / 1000.0 }

    private val tick = Runnable { invalidate() }
    private var tickAt = Double.NaN

    init {
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        isClickable = false
        for ((i, p) in pieces.withIndex()) build(p, paths[i])
        applyTones()
    }

    /** Nền thanh gợi ý (RGB đục) — đổi theme / sáng-tối ⇒ màu quầng + viền. */
    fun setBar(bar: Int) {
        val t = BuddyHalo.colors(bar)
        if (t == tones) return
        tones = t
        applyTones()
    }

    private fun applyTones() {
        holidayProps.clear() // Rebuild lazily with the new outline only if a prop is shown.
        outline = 0xFF000000.toInt() or tones.outline
        haloPaint.color = 0xFF000000.toInt() or tones.halo
        haloStroke.color = haloPaint.color
        fun re(c: Int) = outfit.recolor[c] ?: c
        for ((i, p) in pieces.withIndex()) {
            fills[i].color = p.fill?.let { argb(re(it), p.alpha) } ?: 0
            strokes[i].strokeWidth = p.width.toFloat()
            strokes[i].color = when (val s = p.stroke) {
                Stroke.None -> 0
                Stroke.Outline -> outline
                Stroke.Ink -> 0xFF000000.toInt() or BuddyRig.INK
                is Stroke.Color -> argb(re(s.rgb), if (p.fill == null) p.alpha else 1.0)
            }
        }
        invalidate()
    }

    var lowPower: Boolean
        get() = driver.lowPower
        set(v) { if (driver.lowPower != v) { driver.lowPower = v; if (v) signature = null; invalidate() } }

    // MARK: đầu vào (đường phím — chỉ ghi giờ; đổi trạng thái ⇒ một invalidate, vẽ ở khung kế)

    fun keyPressed() { val t = clock(); val woke = driver.shown is BuddyPhase.Asleep; driver.keyPressed(t)
        if (woke && clockPart == BuddyClock.Part.MORNING && !driver.lowPower) driver.react(BuddyReaction.YAWN, t)
        afterInput(t) }
    fun deletePressed() { val t = clock(); val serial = driver.brain.reactSerial; driver.deletePressed(t)
        if (driver.brain.reactSerial != serial) BuddySignature.reaction(character, BuddyReaction.PANIC)?.let { showSignature(it, t) }
        afterInput(t) }
    fun cheer() { val t = clock(); driver.cheer(t); if (birthdayToday && !driver.lowPower) driver.react(BuddyReaction.CAKE, t)
        cheerSerial++; BuddySignature.cheer(character, cheerSerial)?.let { showSignature(it, t) }; afterInput(t) }
    fun wordCommitted(word: String, prev: String?, prev2: String?) {
        val t = clock()
        // Mùa chốt lúc bàn phím hiện; đổi ngày được kiểm tra tối đa mỗi phút khi còn thấy.
        driver.season = season
        BuddySignature.word(character, word)?.let { showSignature(it, t) }
            ?: prev?.let { BuddySignature.word(character, "$it $word") }?.let { showSignature(it, t) }
        if (driver.wordCommitted(word, prev, prev2, t)) {
            driver.brain.reaction?.let { BuddySignature.reaction(character, it) }?.let { showSignature(it, t) }
            afterInput(t)
        } else if (t < signatureUntil) afterInput(t)
    }
    fun emojiInserted(text: String) {
        val t = clock()
        BuddySignature.word(character, text)?.let { showSignature(it, t); afterInput(t) }
        BuddyWords.reaction(text, null, season = season)?.let { react(it) }
    }
    fun react(r: BuddyReaction) { val t = clock(); driver.react(r, t); BuddySignature.reaction(character, r)?.let { showSignature(it, t) }; afterInput(t) }
    fun tickle() {
        val t = clock()
        if (t - lastTickle < 0.6 || !isAttachedToWindow) return
        lastTickle = t
        if (driver.shown is BuddyPhase.Asleep && !driver.lowPower) {
            react(BuddyReaction.YAWN)
            removeCallbacks(tickleAfterYawn); postDelayed(tickleAfterYawn, 900)
        } else react(BuddyReaction.TICKLE)
    }

    private fun showSignature(value: BuddySignature, t: Double) {
        if (driver.lowPower) return
        signature = value; signatureStart = t
        signatureUntil = t + when (value) { BuddySignature.LASER -> 0.4; BuddySignature.FIRE -> 0.55; else -> 0.9 }
    }

    private fun afterInput(t: Double) {
        if (driver.needsUpdate(t)) invalidate()
        else if (tickAt.isNaN()) schedule(t)
    }

    private fun schedule(t: Double) {
        if (!isAttachedToWindow || !shownInSlot) { halt(); return }
        var d = driver.nextDeadline(t)
        val minute = lastClockRead + 60.0
        d = if (d == null) minute else minOf(d, minute)
        if (clockPart == BuddyClock.Part.NIGHT && !driver.lowPower && driver.shown is BuddyPhase.Idle) {
            val yawn = lastNightYawn + 5.0
            d = if (d == null) yawn else minOf(d, yawn)
        }
        if (d == null) { if (!tickAt.isNaN()) { removeCallbacks(tick); tickAt = Double.NaN }; return }
        if (tickAt == d) return
        removeCallbacks(tick)
        tickAt = d
        postDelayed(tick, ((d - t) * 1000).toLong() + 10)
    }

    /** Ẩn bàn phím: dừng hẹn giờ (không còn khung hình). */
    fun halt() { removeCallbacks(tick); removeCallbacks(tickleAfterYawn); removeCallbacks(momentTick); momentMode = 0; tickAt = Double.NaN }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        lastClockRead = clock(); lastNightYawn = lastClockRead
        val cal = java.util.Calendar.getInstance()
        clockPart = BuddyClock.part(cal.get(java.util.Calendar.HOUR_OF_DAY), cal.get(java.util.Calendar.MINUTE))
        driver.beginAppearance(kotlin.random.Random.nextInt(1_000_001))
        scheduleMoment()
        if (birthdayToday) {
            val stamp = cal.get(java.util.Calendar.YEAR) * 10000 + (cal.get(java.util.Calendar.MONTH) + 1) * 100 + cal.get(java.util.Calendar.DAY_OF_MONTH)
            if (prefs.getInt("buddyBirthdaySeenDay", 0) != stamp) {
                prefs.edit().putInt("buddyBirthdaySeenDay", stamp).apply()
                react(BuddyReaction.CAKE)
            }
        }
    }

    override fun onDetachedFromWindow() { halt(); momentCheered = false; super.onDetachedFromWindow() }

    /** Có cần khung kế không — = driver (ngủ yên / đứng yên = false). */
    fun animating(t: Double = clock()): Boolean {
        if (season == BuddySeason.CHILDRENS_DAY && !driver.lowPower) return true
        if (!driver.lowPower && (t < signatureUntil || (character == BuddyCharacter.KOI && driver.shown is BuddyPhase.Asleep))) return true
        if (spriteAtlas != null) return !driver.lowPower && when (driver.shown) {
            is BuddyPhase.Dancing, BuddyPhase.Idle, BuddyPhase.Cheering, is BuddyPhase.React -> true
            else -> false
        }
        return driver.animating(t) || fxActive(t)
    }

    private fun fxActive(t: Double): Boolean = !driver.lowPower && (driver.shown is BuddyPhase.React || t < signatureUntil)

    // MARK: vẽ

    override fun onDraw(c: Canvas) {
        val t = clock()
        if (isAttachedToWindow && shownInSlot && t - lastClockRead >= 60) {
            lastClockRead = t
            val cal = java.util.Calendar.getInstance()
            val oldPart = clockPart
            clockPart = BuddyClock.part(cal.get(java.util.Calendar.HOUR_OF_DAY), cal.get(java.util.Calendar.MINUTE))
            val day = cal.get(java.util.Calendar.YEAR) * 10000 + (cal.get(java.util.Calendar.MONTH) + 1) * 100 + cal.get(java.util.Calendar.DAY_OF_MONTH)
            if (oldPart != clockPart || day != appearanceDay) post { if (isAttachedToWindow) onTimeChanged?.invoke() }
        }
        if (clockPart == BuddyClock.Part.NIGHT && !driver.lowPower && t - lastNightYawn >= 5 && driver.shown is BuddyPhase.Idle) {
            lastNightYawn = t; react(BuddyReaction.YAWN)
        }
        driver.update(t)
        tickAt = Double.NaN
        if (!shownInSlot || width <= 0 || height <= 0) { schedule(t); return }
        spriteAtlas?.let {
            drawSprite(c, it, t)
            val reaction = driver.shown as? BuddyPhase.React
            if (birthdayToday || season == BuddySeason.CHILDRENS_DAY || reaction?.reaction == BuddyReaction.CAKE || reaction?.reaction?.isHoliday == true) {
                c.save()
                val s = spriteTarget.height() * 0.18f / (rig.heart.size * 2).toFloat()
                c.translate(width / 2f, spriteTarget.top + spriteTarget.height() * 0.54f)
                c.scale(s, s); c.translate(-rig.heart.x.toFloat(), -rig.heart.y.toFloat())
                val prop = if (birthdayToday) BuddyReaction.CAKE else if (season == BuddySeason.CHILDRENS_DAY && reaction == null) BuddyReaction.BALLOON else reaction!!.reaction
                drawHoliday(c, prop, if (reaction?.reaction == prop) ((t - driver.phaseStart) / prop.duration).toFloat() else 0.5f)
                c.restore()
            }
            drawFX(c, t)
            if (animating(t)) postInvalidateDelayed(if (character == BuddyCharacter.GIRL) 50L else 80L) else schedule(t)
            return
        }
        val vp = rig.viewport(framing)
        val hDp = min(height / density - 1f, maxFigureDp)
        val s = max(0.001f, min(hDp * density / vp.h.toFloat(), width / vp.w.toFloat()))
        drawScale = s
        val ox = (width - vp.w.toFloat() * s) / 2f
        val oy = height - vp.h.toFloat() * s
        val p = driver.poseAt(t, pose)
        if (p != null && signature == BuddySignature.BONE && t < signatureUntil) {
            val f = (t - signatureStart) / (signatureUntil - signatureStart)
            p.tail += 0.9 * kotlin.math.sin(10 * Math.PI * f)
        }
        c.save()
        c.translate(ox, oy); c.scale(s, s); c.translate(-vp.x.toFloat(), -vp.y.toFloat())
        if (p == null) {
            drawSleep(c, t)
            if (birthdayToday) drawHoliday(c, BuddyReaction.CAKE, 0.5f)
            else if (season == BuddySeason.CHILDRENS_DAY) drawHoliday(c, BuddyReaction.BALLOON, 0.5f)
        } else drawRig(c, p, t)
        c.restore()
        drawAmbient(c, t)
        drawHolidayMoment(c)
        drawFX(c, t)
        if (animating(t)) {
            if (character == BuddyCharacter.KOI && driver.shown is BuddyPhase.Asleep) postInvalidateDelayed(160L)
            else if (season == BuddySeason.CHILDRENS_DAY && driver.shown !is BuddyPhase.Dancing) postInvalidateDelayed(80L)
            else postInvalidateOnAnimation()
        } else schedule(t)
    }

    private fun drawAmbient(c: Canvas, t: Double) {
        if (driver.lowPower || driver.shown !is BuddyPhase.Dancing) return
        val count = when (season) { BuddySeason.TET -> 4; BuddySeason.CHRISTMAS -> 5; BuddySeason.MID_AUTUMN -> 1; else -> return }
        val w = width.toFloat(); val h = height.toFloat()
        fxFill.color = argb(when (season) { BuddySeason.TET -> 0xF7A7B9; BuddySeason.CHRISTMAS -> 0xF2F2F7; else -> 0xF8D77B }, 1.0)
        for (i in 0 until count) {
            if (season == BuddySeason.TET) fxFill.color = argb(if (i % 2 == 0) 0xF8D77B else 0xF7A7B9, 1.0)
            val x = w * (i + 1) / (count + 1)
            val y = if (season == BuddySeason.MID_AUTUMN) h * 0.25f else ((t / (4 + i) + i.toDouble() / count) % 1.0 * h).toFloat()
            if (season == BuddySeason.MID_AUTUMN) {
                val save = c.save(); c.rotate((t * 90 % 360).toFloat(), x, y)
                fxStroke.color = argb(0xF8D77B, 1.0); fxStroke.strokeWidth = 2f
                for (j in 0 until 10) {
                    val a = j * Math.PI / 5 - Math.PI / 2
                    val b = ((j + 1) % 10) * Math.PI / 5 - Math.PI / 2
                    val r1 = if (j % 2 == 0) 7 else 3
                    val r2 = if ((j + 1) % 2 == 0) 7 else 3
                    c.drawLine(x + (kotlin.math.cos(a) * r1).toFloat(), y + (kotlin.math.sin(a) * r1).toFloat(),
                        x + (kotlin.math.cos(b) * r2).toFloat(), y + (kotlin.math.sin(b) * r2).toFloat(), fxStroke)
                }
                c.restoreToCount(save)
            } else c.drawCircle(x, y, 2f, fxFill)
        }
    }

    private fun drawHolidayMoment(c: Canvas) {
        if (driver.lowPower || momentMode == 0) return
        val cal = java.util.Calendar.getInstance()
        val y = cal.get(java.util.Calendar.YEAR); val m = cal.get(java.util.Calendar.MONTH) + 1
        val d = cal.get(java.util.Calendar.DAY_OF_MONTH); val h = cal.get(java.util.Calendar.HOUR_OF_DAY)
        val minute = cal.get(java.util.Calendar.MINUTE); val second = cal.get(java.util.Calendar.SECOND)
        if (BuddyHolidayClock.fireworks(y, m, d, h, minute)) {
            val progress = ((System.currentTimeMillis() - momentBurstStart) / 2500f).coerceIn(0f, 1f)
            if (progress >= 1f) return
            val opacity = if (progress < 0.3f) progress / 0.3f else (1f - progress) / 0.7f
            fxStroke.strokeWidth = 1.5f
            for (i in 0..2) {
                fxStroke.color = argb(intArrayOf(0xF8D77B, 0xF7A7B9, 0x62D8EB)[i], opacity.toDouble())
                val x = width * (i + 1) / 4f; val yy = height * (0.17f + (i % 2) * 0.1f)
                for (j in 0..7) {
                    val a = j * Math.PI / 4
                    c.drawLine(x + (kotlin.math.cos(a) * 3).toFloat(), yy + (kotlin.math.sin(a) * 3).toFloat(),
                        x + (kotlin.math.cos(a) * 9).toFloat(), yy + (kotlin.math.sin(a) * 9).toFloat(), fxStroke)
                }
            }
            postInvalidateDelayed(80L)
        } else BuddyHolidayClock.countdown(m, d, h, minute, second)?.let {
            rect.set(width * 0.38f, height * 0.04f, width * 0.62f, height * 0.25f)
            fxFill.color = argb(0xFFF7ED, 1.0); c.drawRoundRect(rect, 5f, 5f, fxFill)
            fxStroke.color = argb(tones.outline, 1.0); fxStroke.strokeWidth = 1f; c.drawRoundRect(rect, 5f, 5f, fxStroke)
            fxText.color = argb(BuddyRig.INK, 1.0); fxText.textSize = 15f * density
            c.drawText(it.toString(), rect.centerX(), rect.centerY() + fxText.textSize * 0.35f, fxText)
        }
    }

    private fun drawSprite(c: Canvas, atlas: Bitmap, t: Double) {
        c.clipRect(0f, 0f, width.toFloat(), height.toFloat())   // ô ảnh rộng hơn view: cắt lề trong suốt
        val phase = driver.shown
        val elapsed = t - driver.phaseStart
        val frame = when (phase) {
            is BuddyPhase.Asleep -> BuddySprites.sleep(character)
            is BuddyPhase.Dancing -> {
                val frames = BuddySprites.dance(character, phase.tier)
                frames[BuddySprites.frameIndex(elapsed / BuddySprites.duration(character, phase.tier), frames.size)]
            }
            BuddyPhase.Idle -> {
                val frames = BuddySprites.IDLE
                frames[BuddySprites.frameIndex(elapsed / BuddySprites.IDLE_DURATION, frames.size)]
            }
            BuddyPhase.Cheering -> {
                val frames = BuddySprites.CHEER
                frames[BuddySprites.frameIndex(elapsed / com.viettelex.keyboard.BuddyBrain.CHEER, frames.size)]
            }
            is BuddyPhase.React -> {
                val frames = BuddySprites.REACT
                frames[BuddySprites.frameIndex(elapsed / phase.reaction.duration, frames.size)]
            }
            else -> BuddySprites.rest(character)
        }
        // Reuse source/destination rectangles; no per-frame bitmap or path allocation.
        val columns = BuddySprites.columns(character)
        val rows = BuddySprites.rows(character)
        val cell = BuddySprites.cell(frame)
        val col = cell % columns; val row = cell / columns
        spriteSource.set(col * atlas.width / columns, row * atlas.height / rows,
            (col + 1) * atlas.width / columns, (row + 1) * atlas.height / rows)
        val aspect = atlas.width.toFloat() / atlas.height * rows / columns
        // Cao trọn ô (chạm trần strip); ô ảnh rộng hơn view thì lề trong suốt hai bên bị cắt.
        val h = min(height.toFloat(), maxFigureDp * density).coerceAtLeast(0f)
        val w = h * aspect
        spriteTarget.set((width - w) / 2f, height - h, (width + w) / 2f, height.toFloat())
        // Khung lật gương: scale.x = −1 quanh tâm nhân vật (chân trái ↔ chân phải), không cấp phát.
        val sx = if (BuddySprites.isMirrored(frame)) -1f else 1f
        if (sx == 1f) {
            c.drawBitmap(atlas, spriteSource, spriteTarget, spritePaint)
        } else {
            val save = c.save()
            c.scale(sx, 1f, spriteTarget.centerX(), spriteTarget.centerY())
            c.drawBitmap(atlas, spriteSource, spriteTarget, spritePaint)
            c.restoreToCount(save)
        }
    }

    private fun drawRig(c: Canvas, p: BuddyPose, t: Double) {
        val shown = driver.shown
        val dance = when (shown) {
            is BuddyPhase.Dancing, BuddyPhase.Cheering -> true
            is BuddyPhase.React -> BuddyDance.happyEyes(shown.reaction)
            else -> false
        }
        val react = (shown as? BuddyPhase.React)?.reaction
        val f = if (react != null) ((t - driver.phaseStart) / react.duration).toFloat() else 0f
        c.translate(p.dx.toFloat(), p.dy.toFloat())
        val fx = rig.feet.x.toFloat(); val fy = rig.feet.y.toFloat()
        c.rotate(deg(p.rot), fx, fy)
        c.scale(p.sx.toFloat(), 1f, fx, fy)
        // Lượt quầng: cùng biến đổi bộ phận, vẽ trước (dưới) mọi bộ phận.
        for (part in BuddyPart.entries) {
            if (part == BuddyPart.SLEEP) continue
            val pv = rig.pivots[part]
            val a = angle(part, p)
            val save = c.save()
            if (pv != null && a != 0.0) c.rotate(deg(a), pv.x.toFloat(), pv.y.toFloat())
            drawHalo(c, part)
            c.restoreToCount(save)
        }
        for (part in BuddyPart.entries) {
            if (part == BuddyPart.SLEEP) continue
            val pv = rig.pivots[part]
            val a = angle(part, p)
            val save = c.save()
            if (pv != null && a != 0.0) c.rotate(deg(a), pv.x.toFloat(), pv.y.toFloat())
            for (i in byPart[part.ordinal]) {
                val pc = pieces[i]
                if (pc.show == Show.REST && dance || pc.show == Show.DANCE && !dance) continue
                drawPiece(c, i)
            }
            if (part == BuddyPart.HEAD && react == BuddyReaction.ANGRY) {
                fxFill.color = argb(BuddyFX.ANGRY_RED, 0.45 * keyframe(f, 0f, 1f, 1f, 0f, 0.15f, 0.8f))
                c.drawPath(flushPath, fxFill)
                fxStroke.color = 0xFF000000.toInt() or BuddyRig.INK; fxStroke.strokeWidth = 4.5f; fxStroke.strokeCap = Paint.Cap.ROUND
                c.drawPath(browsPath, fxStroke)
            }
            if (part == BuddyPart.HEAD && react == BuddyReaction.SURPRISED && character == BuddyCharacter.ROBOT) {
                fxFill.color = argb(0x62D8EB, 0.4 + 0.6 * kotlin.math.abs(kotlin.math.sin(f * Math.PI * 8)))
                c.drawOval(-20f, -15f, -8f, 1f, fxFill)
                c.drawOval(8f, -15f, 20f, 1f, fxFill)
            }
            c.restoreToCount(save)
            if ((part == BuddyPart.ARM_R && react != BuddyReaction.LION_DANCE && (birthdayToday || season == BuddySeason.CHILDRENS_DAY || react?.isHoliday == true || react == BuddyReaction.CAKE)) ||
                (part == BuddyPart.HEAD && react == BuddyReaction.LION_DANCE))
                drawHoliday(c, if (birthdayToday) BuddyReaction.CAKE else if (react?.isHoliday == true) react else BuddyReaction.BALLOON, if (react == BuddyReaction.CAKE) f else 0.5f)
            if (part == BuddyPart.HEAD && react == null && season == BuddySeason.TET &&
                (shown as? BuddyPhase.Dancing)?.tier == 3 && !driver.lowPower)
                drawHoliday(c, BuddyReaction.LION_DANCE, 0.5f)
            if (part == BuddyPart.BODY && react == BuddyReaction.LOVE) {
                val sc = pulse(f)
                val save2 = c.save()
                c.scale(sc, sc, rig.heart.x.toFloat(), rig.heart.y.toFloat())
                fxFill.color = 0xFF000000.toInt() or BuddyFX.HEART_COLOR
                c.drawPath(heartProp, fxFill)
                fxStroke.color = outline; fxStroke.strokeWidth = BuddyRig.OUTLINE_WIDTH.toFloat()
                c.drawPath(heartProp, fxStroke)
                c.restoreToCount(save2)
            }
        }
    }

    private fun angle(part: BuddyPart, p: BuddyPose): Double = when (part) {
        BuddyPart.HEAD -> p.head; BuddyPart.ARM_L -> p.armL; BuddyPart.ARM_R -> p.armR
        BuddyPart.LEG_L -> p.legL; BuddyPart.LEG_R -> p.legR; BuddyPart.TAIL -> p.tail
        else -> 0.0
    }

    /** Quầng bộ phận: nét rộng hơn viền đúng [BuddyHalo.WIDTH] dp mỗi bên (đổi sang đơn vị thiết kế theo tỉ lệ vẽ). */
    private fun drawHalo(c: Canvas, part: BuddyPart) {
        val extra = (2 * BuddyHalo.WIDTH * density / drawScale).toFloat()
        for (h in haloByPart[part.ordinal]) {
            val paint = if (h.filled) haloPaint else haloStroke
            paint.strokeWidth = h.width.toFloat() + extra
            c.drawPath(h.path, paint)
        }
    }

    private fun drawSleep(c: Canvas, t: Double) {
        c.translate(0f, rig.sleepOffset(framing).toFloat())
        drawHalo(c, BuddyPart.SLEEP)
        for (i in byPart[BuddyPart.SLEEP.ordinal]) drawPiece(c, i)
        if (character == BuddyCharacter.KOI && !driver.lowPower) {
            fxStroke.color = 0xFF79C9E9.toInt(); fxStroke.strokeWidth = 1.5f
            for (i in 0..2) {
                val phase = ((t / 2.4 + i / 3.0) % 1.0).toFloat()
                fxStroke.alpha = (255 * kotlin.math.sin(Math.PI * phase).coerceAtLeast(0.0)).toInt()
                c.drawCircle((i - 1) * 8f, 11f - 28f * phase, (2 + i).toFloat(), fxStroke)
            }
        }
        val zzz = (driver.shown as? BuddyPhase.Asleep)?.zzz == true && !driver.lowPower
        val n = zPaths.size
        val f = ((t - driver.phaseStart) / com.viettelex.keyboard.BuddyBrain.ZZZ).toFloat()
        for ((i, z) in zPaths.withIndex()) {
            var alpha = 1f; var rise = 0f
            if (zzz && f in 0f..1f) {
                val a = i.toFloat() / n * 0.8f; val b = (i + 1f) / n * 0.8f
                alpha = if (f <= a) 0f else if (f >= b) 1f else (f - a) / (b - a)
                rise = 4f * density * (1 - f) / drawScale
            }
            zPaint.alpha = (alpha * 255).toInt()
            if (rise != 0f) { c.save(); c.translate(0f, rise); c.drawPath(z, zPaint); c.restore() } else c.drawPath(z, zPaint)
        }
    }

    private fun drawPiece(c: Canvas, i: Int) {
        val p = pieces[i]
        val turn = p.turn
        if (turn != null) { c.save(); c.rotate(turn.first.toFloat(), turn.second.toFloat(), turn.third.toFloat()) }
        if (p.fill != null) c.drawPath(paths[i], fills[i])
        if (p.stroke !== Stroke.None) c.drawPath(paths[i], strokes[i])
        if (turn != null) c.restore()
    }

    /** Hiệu ứng phản ứng (toạ độ dp trong ô — luôn trọn trong ô). */
    private fun drawFX(c: Canvas, t: Double) {
        if (driver.lowPower) return
        drawSignature(c, t)
        val r = (driver.shown as? BuddyPhase.React)?.reaction ?: return
        val w = width / density.toDouble(); val h = height / density.toDouble()
        val el = t - driver.phaseStart
        val f = (el / r.duration).toFloat()
        c.save()
        c.scale(density, density)
        BuddyFX.badge(r, w, h)?.let { b ->
            val sc = keyframe(f, 0.3f, 1.1f, 1f, 1f, 0.12f, 0.2f)
            val al = keyframe(f, 0f, 1f, 1f, 0f, 0.1f, 0.75f)
            rect.set(b.x.toFloat(), b.y.toFloat(), (b.x + b.w).toFloat(), (b.y + b.h).toFloat())
            c.save()
            c.scale(sc, sc, rect.centerX(), rect.centerY())
            when (r) {
                BuddyReaction.ANGRY -> {
                    fxFill.color = argb(0xFFFFFF, al.toDouble())
                    c.drawRoundRect(rect, rect.height() / 2, rect.height() / 2, fxFill)
                    fxStroke.color = argb(BuddyFX.ANGRY_RED, al.toDouble()); fxStroke.strokeWidth = 1f
                    c.drawRoundRect(rect, rect.height() / 2, rect.height() / 2, fxStroke)
                    fxText.color = argb(BuddyFX.ANGRY_RED, al.toDouble()); fxText.textSize = rect.height() * 0.72f
                    if (grawlixSerial != driver.shownSerial) { grawlixSerial = driver.shownSerial; grawlixText = BuddyWords.grawlix(grawlixSerial) }
                    c.drawText(grawlixText, rect.centerX(), rect.bottom - rect.height() * 0.2f, fxText)
                }
                BuddyReaction.SURPRISED -> {
                    fxText.color = argb(BuddyFX.ANGRY_RED, al.toDouble()); fxText.textSize = rect.height() * 0.95f
                    c.drawText("!", rect.centerX(), rect.bottom - 1f, fxText)
                }
                BuddyReaction.SAD -> {
                    val key = "${b.w}x${b.h}"
                    if (key != cloudFor) { cloudFor = key; cloud.reset(); cloud.set(svg(BuddyFX.cloudPath(com.viettelex.keyboard.BuddyRect(0.0, 0.0, b.w, b.h)))) }
                    fxFill.color = argb(BuddyFX.CLOUD_COLOR, al.toDouble())
                    c.save(); c.translate(rect.left, rect.top); c.drawPath(cloud, fxFill); c.restore()
                }
                BuddyReaction.GREET, BuddyReaction.TET_WISH -> {
                    val bubble = if (r == BuddyReaction.TET_WISH) com.viettelex.keyboard.tr("Chúc mừng năm mới!") else BuddyName.bubble(petName, com.viettelex.keyboard.tr("chào bạn!") == "says hi!", (b.w / 5.2).toInt())
                    if (bubble != null) {
                        fxFill.color = argb(0xFFF7ED, al.toDouble())
                        c.drawRoundRect(rect, 5f, 5f, fxFill)
                        fxStroke.color = argb(tones.outline, al.toDouble()); fxStroke.strokeWidth = 1f
                        c.drawRoundRect(rect, 5f, 5f, fxStroke)
                        fxText.color = argb(BuddyRig.INK, al.toDouble()); fxText.textSize = if (r == BuddyReaction.TET_WISH) min(4f, rect.width() / 20f) else min(7f, rect.height() * 0.55f)
                        var fitted: String = bubble
                        while (fitted.length > 1 && fxText.measureText(fitted) > rect.width() - 4f)
                            fitted = fitted.dropLast(if (fitted.endsWith("…")) 2 else 1) + "…"
                        if (fxText.measureText(fitted) <= rect.width() - 4f)
                            c.drawText(fitted, rect.centerX(), rect.centerY() + fxText.textSize * 0.35f, fxText)
                    }
                }
                else -> {}
            }
            c.restore()
        }
        val n = min(BuddyFX.count(r), BuddyFX.MAX_PARTICLES)
        for (i in 0 until n) {
            val p = BuddyFX.particle(r, i, w, h)
            var u = ((el - p.delay) / BuddyFX.PARTICLE_DURATION).toFloat()
            if (r == BuddyReaction.PANIC && u > 0f) u -= floor(u)
            if (u < 0f || u > 1f) continue
            val x = (p.x0 + (p.x1 - p.x0) * u).toFloat(); val y = (p.y0 + (p.y1 - p.y0) * u).toFloat()
            val al = keyframe(u, 0f, 1f, 1f, 0f, 0.15f, 0.6f)
            val sc = 0.4f + 0.7f * u
            c.save(); c.translate(x, y); c.scale(sc, sc)
            when (r) {
                BuddyReaction.PANIC -> {
                    fxText.color = argb(tones.halo, al.toDouble()); fxText.textSize = 8f
                    c.drawText(BuddyFX.PANIC_GLYPHS[i % BuddyFX.PANIC_GLYPHS.size], 0f, 3f, fxText)
                }
                BuddyReaction.TICKLE -> {
                    fxText.color = argb(tones.halo, al.toDouble()); fxText.textSize = 8f
                    c.drawText(if (i % 2 == 0) "✦" else "hi", 0f, 3f, fxText)
                }
                BuddyReaction.CAKE -> {
                    fxFill.color = argb(intArrayOf(0xF8D77B, 0xF7A7B9, 0x83B9A4, 0xA48AC0)[i % 4], al.toDouble())
                    c.drawRect(-3f, -3f, 3f, 3f, fxFill)
                }
                else -> {
                    fxFill.color = argb(when (r) { BuddyReaction.LOVE, BuddyReaction.BOUQUET, BuddyReaction.ROSE -> BuddyFX.HEART_COLOR; BuddyReaction.SAD -> BuddyFX.RAIN_COLOR; else -> BuddyFX.TEAR_COLOR }, al.toDouble())
                    c.drawPath(if (r == BuddyReaction.LOVE || r == BuddyReaction.BOUQUET || r == BuddyReaction.ROSE) heartSmall else dropSmall, fxFill)
                }
            }
            c.restore()
        }
        c.restore()
    }

    /** Drawn only while a short signature is active; Canvas clips to the buddy cell. */
    private fun drawSignature(c: Canvas, t: Double) {
        val active = if (t < signatureUntil) signature else null
        val ambient = when (val phase = driver.shown) {
            BuddyPhase.Idle -> BuddySignature.idle(character)
            is BuddyPhase.Dancing -> BuddySignature.dance(character, phase.tier,
                floor((t - driver.phaseStart) / (BuddyDance.loopLength(phase.tier) * 2)).toInt(), driver.danceSeed)
            else -> null
        }
        val effect = active ?: ambient ?: return
        if (effect == BuddySignature.BAMBOO && driver.shown is BuddyPhase.Asleep) return
        val f = if (active != null) ((t - signatureStart) / (signatureUntil - signatureStart)).toFloat().coerceIn(0f, 1f) else 0.5f
        val alpha = if (active == null) 0.7 else kotlin.math.sin(Math.PI * f).coerceAtLeast(0.0)
        val w = width / density; val h = height / density
        val x = w * 0.54f; val y = h * 0.48f
        c.save(); c.clipRect(0f, 0f, width.toFloat(), height.toFloat()); c.scale(density, density)
        when (effect) {
            BuddySignature.FIRE -> {
                val colors = intArrayOf(0xF05036, 0xFF9B37, 0xFFE370)
                for (i in 0..2) {
                    fxFill.color = argb(colors[i], alpha)
                    val len = w * (0.32f - i * 0.05f) * (0.7f + 0.3f * kotlin.math.sin(f * 14 + i).toFloat())
                    val p = flamePath ?: Path().also { flamePath = it }; p.reset(); p.moveTo(x, y + (i - 1) * 2)
                    p.quadTo(x + len * 0.55f, y - h * 0.13f, min(w - 2f, x + len), y - 2f)
                    p.quadTo(x + len * 0.55f, y + h * 0.09f, x, y + (i - 1) * 2f)
                    c.drawPath(p, fxFill)
                }
            }
            BuddySignature.LASER -> {
                for ((color, sw) in listOf(0xF44A83 to 9f, 0xFF5B8F to 4f, 0xFFFFFF to 1.5f)) {
                    fxStroke.color = argb(color, alpha); fxStroke.strokeWidth = sw
                    for (eye in listOf(-1f, 1f)) c.drawLine(x + eye * w * 0.075f, y - h * 0.12f,
                        max(2f, w * 0.08f + (eye + 1) * 5f), 3f, fxStroke)
                }
            }
            BuddySignature.KISS -> {
                fxFill.color = argb(BuddyFX.HEART_COLOR, alpha)
                c.drawCircle(x + 4f + f * 15f, y - f * 18f, 5f, fxFill)
                c.drawCircle(x + 10f + f * 15f, y - f * 18f, 5f, fxFill)
                fxStroke.color = argb(BuddyRig.INK, alpha); fxStroke.strokeWidth = 2f
                c.drawLine(x - w * 0.13f, y - h * 0.12f, x - w * 0.045f, y - h * 0.12f, fxStroke)
            }
            BuddySignature.BONE -> {
                fxFill.color = argb(0xFFF4DF, alpha)
                val yy = y + 14f - 26f * f
                c.drawRoundRect(x - 15f, yy - 5f, x + 15f, yy + 5f, 5f, 5f, fxFill)
                for (end in listOf(x - 15f, x + 15f)) for (dy in listOf(-5f, 5f)) c.drawCircle(end, yy + dy, 5f, fxFill)
            }
            BuddySignature.EGG -> {
                fxFill.color = argb(0xFFF7EC, alpha); c.drawOval(x - 11f, y - 4f, x + 11f, y + 26f, fxFill)
                fxStroke.color = argb(0xE2A76E, alpha); fxStroke.strokeWidth = 1.6f
                c.drawLine(x - 9f, y + 11f, x - 2f, y + 7f, fxStroke)
                c.drawLine(x - 2f, y + 7f, x + 3f, y + 13f, fxStroke)
                c.drawLine(x + 3f, y + 13f, x + 10f, y + 8f, fxStroke)
                if (f > 0.52f) {
                    fxFill.color = argb(0xFFE17A, alpha)
                    c.drawCircle(x, y - 4f, 7f, fxFill)
                    fxFill.color = argb(BuddyRig.INK, alpha)
                    c.drawCircle(x - 3f, y - 5f, 1f, fxFill)
                    c.drawCircle(x + 3f, y - 5f, 1f, fxFill)
                }
            }
            BuddySignature.SPLASH -> {
                fxFill.color = argb(0x79C9E9, alpha)
                for (i in 0..2) c.drawCircle(x - 12f + i * 12, y + 16f - (i % 2) * 15 - f * 9, 3f, fxFill)
            }
            BuddySignature.BEEP -> {
                fxFill.color = argb(0x62D8EB, alpha)
                c.drawCircle(x, y - h * 0.31f, 5f, fxFill)
                fxFill.color = argb(0xF8D77B, alpha)
                for (i in 0..2) c.drawCircle(x - 14f + i * 12f, y - h * 0.18f - (i % 2) * 6f, 2f, fxFill)
            }
            BuddySignature.BAMBOO -> {
                fxStroke.color = argb(0x5AA873, alpha); fxStroke.strokeWidth = 5f
                c.drawLine(x - 10f, y + 20f, x + 5f, y - 22f, fxStroke)
                fxFill.color = argb(0x82C584, alpha)
                for (i in 0..2) c.drawOval(x - 14f + i * 5, y - 17f + i * 11, x + 1f + i * 5, y - 11f + i * 11, fxFill)
            }
            else -> {
                val color = when (effect) { BuddySignature.MUD -> 0x9B7158; BuddySignature.SNORT -> 0xD8D3D0
                    BuddySignature.YARN -> 0xE995B5; else -> 0x8AA6E8 }
                fxFill.color = argb(color, alpha)
                for (i in 0..2) {
                    val xx = if (effect == BuddySignature.YARN) x - 25f + f * 32f + i * 4 else x - 13f + i * 12
                    c.drawCircle(xx, y + (i % 2) * 8, 5f, fxFill)
                }
            }
        }
        c.restore()
    }

    // MARK: hình

    private fun build(p: BuddyPiece, out: Path) {
        when (val sh = p.shape) {
            is Shape.Path -> out.set(svg(sh.d))
            is Shape.Circle -> out.addCircle(sh.cx.toFloat(), sh.cy.toFloat(), sh.r.toFloat(), Path.Direction.CW)
            is Shape.Ellipse -> out.addOval(RectF((sh.cx - sh.rx).toFloat(), (sh.cy - sh.ry).toFloat(),
                (sh.cx + sh.rx).toFloat(), (sh.cy + sh.ry).toFloat()), Path.Direction.CW)
            is Shape.RRect -> {
                val rr = min(sh.r, min(sh.w, sh.h) / 2).toFloat()
                out.addRoundRect(RectF(sh.x.toFloat(), sh.y.toFloat(), (sh.x + sh.w).toFloat(), (sh.y + sh.h).toFloat()), rr, rr, Path.Direction.CW)
            }
        }
    }

    companion object {
        fun svg(d: String): Path {
            val p = Path()
            for (cmd in BuddySVG.parse(d)) when (cmd) {
                is BuddySVG.Cmd.Move -> p.moveTo(cmd.x.toFloat(), cmd.y.toFloat())
                is BuddySVG.Cmd.Line -> p.lineTo(cmd.x.toFloat(), cmd.y.toFloat())
                is BuddySVG.Cmd.Quad -> p.quadTo(cmd.cx.toFloat(), cmd.cy.toFloat(), cmd.x.toFloat(), cmd.y.toFloat())
                BuddySVG.Cmd.Close -> p.close()
            }
            return p
        }

        fun argb(rgb: Int, a: Double): Int = ((a.coerceIn(0.0, 1.0) * 255).toInt() shl 24) or (rgb and 0xFFFFFF)
        private fun deg(rad: Double) = Math.toDegrees(rad).toFloat()

        /** Giá trị khung hình 4 điểm (0, a, b, 1) → (v0, v1, v2, v3), nội suy tuyến tính. */
        fun keyframe(f: Float, v0: Float, v1: Float, v2: Float, v3: Float, a: Float, b: Float): Float = when {
            f <= 0f -> v0
            f < a -> v0 + (v1 - v0) * f / a
            f < b -> v1 + (v2 - v1) * (f - a) / (b - a)
            f < 1f -> v2 + (v3 - v2) * (f - b) / (1 - b)
            else -> v3
        }

        /** Nhịp trái tim ôm trước ngực (= iOS pulse). */
        private val PULSE_T = floatArrayOf(0f, 0.15f, 0.3f, 0.45f, 0.6f, 0.8f, 1f)
        private val PULSE_V = floatArrayOf(0.2f, 1.15f, 0.95f, 1.1f, 1f, 1.1f, 0.2f)
        fun pulse(f: Float): Float {
            if (f <= 0f) return PULSE_V[0]
            for (i in 1 until PULSE_T.size) if (f < PULSE_T[i]) {
                val u = (f - PULSE_T[i - 1]) / (PULSE_T[i] - PULSE_T[i - 1])
                return PULSE_V[i - 1] + (PULSE_V[i] - PULSE_V[i - 1]) * u
            }
            return PULSE_V.last()
        }
    }
}
