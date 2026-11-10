package com.viettelex.android.ime

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Typeface
import android.view.View
import com.viettelex.keyboard.NineSlice
import com.viettelex.keyboard.ThemeAssetClass
import com.viettelex.keyboard.ThemeAssetImageMath
import com.viettelex.keyboard.ThemeAssetLimits
import com.viettelex.keyboard.ThemeAssetPlan
import com.viettelex.keyboard.ThemeAssetRef
import com.viettelex.keyboard.ThemeAssetStore
import java.io.File

/*
 * Bàn phím: nạp tệp tải về của theme (ThemeAssets.kt ở :keyboard — kế hoạch / mục lục). CHỈ đọc tệp app đã xử lý
 * trong filesDir/theme_assets — không bao giờ dùng mạng (bộ tải nằm ở ui/, IME không tham chiếu). Mỗi ảnh skin giải
 * MỘT lần mỗi lần nạp theme (inSampleSize + thu về 192 / 512 px), dùng chung Bitmap cho mọi phím cùng nhóm; ảnh
 * nền / tiền cảnh giải theo cỡ view. Theme không có tệp ⇒ null, không đọc đĩa. Thiếu tệp / hỏng ⇒ màu theme /
 * phông mặc định (không crash).
 */

/** Skin đã giải: ảnh thường + ảnh khi đè (có thể null), insets 9-slice theo px ảnh giải (null = căng cả ảnh). */
class LoadedSkin(
    @JvmField val normal: Bitmap,
    @JvmField val pressed: Bitmap?,
    @JvmField val insets: IntArray?,
    @JvmField val pressedInsets: IntArray?,
    /** Slice theo px ảnh GỐC + chiều cao ảnh gốc — insets đích = slice × chiều cao phím / srcH. */
    @JvmField val slice: IntArray?,
    @JvmField val srcH: Int,
)

class LoadedThemeAssets(
    val signature: String,
    val typeface: Typeface?,
    /** Theo [ThemeAssetPlan.ROLES] (chỉ số [ThemeKeyRole.index]); null = phím đó vẽ màu theme. */
    val skins: Array<LoadedSkin?>?,
    val background: File?,
    val foreground: File?,
) {
    /** Byte bitmap skin (mỗi Bitmap đếm một lần). */
    val skinBytes: Long get() {
        val seen = java.util.IdentityHashMap<Bitmap, Boolean>()
        var n = 0L
        skins?.forEach { s -> s ?: return@forEach; for (b in listOfNotNull(s.normal, s.pressed)) if (seen.put(b, true) == null) n += b.byteCount }
        return n
    }
}

/** Vai phím (thuần, test JVM): chỉ số trong [ThemeAssetPlan.ROLES] — default 0, special 1, space 2, return 3, shift 4, delete 5, a…z 6…31. */
object ThemeKeyRole {
    const val DEFAULT = 0
    const val SPECIAL = 1
    const val SPACE = 2
    const val RETURN = 3
    const val SHIFT = 4
    const val DELETE = 5
    const val LETTER_A = 6

    /** Chữ a–z ⇒ vai chữ; chữ khác / số / ký hiệu ⇒ default; 123 / 🌐 / emoji / phím phụ ⇒ special. Không cấp phát. */
    fun index(kind: Int, label: String): Int = when (kind) {
        KeyKind.LETTER -> if (label.length == 1 && label[0] in 'a'..'z') LETTER_A + (label[0] - 'a') else DEFAULT
        KeyKind.CHAR, KeyKind.PUNCT -> DEFAULT
        KeyKind.PAD -> DEFAULT
        KeyKind.SPACE -> SPACE
        KeyKind.RETURN -> RETURN
        KeyKind.SHIFT -> SHIFT
        KeyKind.BACKSPACE -> DELETE
        else -> SPECIAL
    }

    /** Phím phụ bàn số tô màu phím chức năng ⇒ special. */
    fun index(kind: Int, label: String, side: Boolean): Int = if (kind == KeyKind.PAD && side) SPECIAL else index(kind, label)
}

object ThemeAssetLoader {
    private var cache: LoadedThemeAssets? = null
    /** Test / đo: số lần giải thật (cache trúng không tăng). */
    @Volatile var loadCount = 0; private set

    /** Theme không có tệp ⇒ null, 0 việc. Cùng chữ ký (kế hoạch + mốc mục lục) ⇒ bản cache. */
    @Synchronized
    fun load(plan: ThemeAssetPlan, dir: File, stamp: Long): LoadedThemeAssets? {
        if (plan.isEmpty) { cache = null; return null }
        val sig = plan.signature + "|" + dir.path + "|" + stamp
        cache?.let { if (it.signature == sig) return it }
        cache = null                                   // nhả bộ cũ TRƯỚC khi giải bộ mới
        loadCount++
        val index = ThemeAssetStore.readIndex(dir)
        fun file(cls: ThemeAssetClass, r: ThemeAssetRef?) = ThemeAssetStore.locate(cls, r, index, dir)
        val typeface = file(ThemeAssetClass.font, plan.font)?.let { (f, _) -> runCatching { Typeface.createFromFile(f) }.getOrNull() }
        // Skin: gom vai theo ảnh ⇒ cạnh giải = lớn nhất các vai cần; mỗi ảnh giải một lần.
        val roles = HashMap<ThemeAssetRef, MutableSet<String>>()
        for ((role, s) in plan.skins) {
            roles.getOrPut(s.image) { HashSet() }.add(role)
            s.pressed?.let { roles.getOrPut(it) { HashSet() }.add(role) }
        }
        val decoded = HashMap<ThemeAssetRef, Pair<Bitmap, ThemeAssetStore.Entry>>()
        for ((ref, rs) in roles) {
            val (f, e) = file(ThemeAssetClass.key, ref) ?: continue
            decodeKey(f, ThemeAssetLimits.keyDecodeEdge(rs))?.let { decoded[ref] = it to e }
        }
        var skins: Array<LoadedSkin?>? = null
        if (decoded.isNotEmpty()) {
            val arr = arrayOfNulls<LoadedSkin>(ThemeAssetPlan.ROLES.size)
            for ((i, role) in ThemeAssetPlan.ROLES.withIndex()) {
                val s = plan.skins[role] ?: continue
                val (img, e) = decoded[s.image] ?: continue          // thiếu ảnh ⇒ màu theme
                val pr = s.pressed?.let { decoded[it] }
                arr[i] = LoadedSkin(img, pr?.first,
                    s.slice?.let { NineSlice.scale(it, e.sw, e.sh, img.width, img.height).toIntArray() },
                    s.slice?.let { sl -> pr?.let { (pb, pe) -> NineSlice.scale(sl, pe.sw, pe.sh, pb.width, pb.height).toIntArray() } },
                    s.slice?.toIntArray(), maxOf(e.sh, 1))
            }
            skins = arr
        }
        val out = LoadedThemeAssets(sig, typeface, skins, file(ThemeAssetClass.screen, plan.background)?.first,
            file(ThemeAssetClass.screen, plan.foreground)?.first)
        cache = out
        return out
    }

    /** Theme không có tệp ([ImeTheme.assets]) ⇒ bỏ skin / phông của theme trước (không còn view nào vẽ). */
    @Synchronized fun dropCache() { cache = null }
    /** Test: bộ đang cache. */
    internal val cached: LoadedThemeAssets? @Synchronized get() = cache

    /** Skin: giải có lấy mẫu rồi thu về cạnh dài ≤ [edge] (ảnh đã lưu ≤ 512). */
    private fun decodeKey(f: File, edge: Int): Bitmap? = runCatching {
        val b = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(f.path, b)
        if (ThemeAssetImageMath.checkSource(b.outWidth, b.outHeight) != null) return@runCatching null
        val img = BitmapFactory.decodeFile(f.path, BitmapFactory.Options().apply {
            inSampleSize = ThemeAssetImageMath.sampleSize(b.outWidth, b.outHeight, edge)
        }) ?: return@runCatching null
        val t = ThemeAssetImageMath.fit(img.width, img.height, edge)
        if (t[0] == img.width && t[1] == img.height) img
        else Bitmap.createScaledBitmap(img, t[0], t[1], true).also { if (it !== img) img.recycle() }
    }.getOrNull()

    /**
     * Ảnh nền ([fill] — aspect-fill, chỉ giữ vùng thấy) / tiền cảnh (căng) cho khung vw×vh: bitmap ≤ khung và ≤ ảnh
     * đã lưu ([ThemeAssetImageMath.screenDecodeSize]); cửa sổ vẽ GPU ⇒ chuyển HARDWARE như ảnh nền người dùng.
     */
    fun loadScreen(f: File, vw: Int, vh: Int, fill: Boolean, hardware: Boolean): Bitmap? = runCatching {
        if (vw <= 0 || vh <= 0) return@runCatching null
        val b = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(f.path, b)
        val w = b.outWidth; val h = b.outHeight
        if (ThemeAssetImageMath.checkSource(w, h) != null) return@runCatching null
        val target = ThemeAssetImageMath.screenDecodeSize(w, h, vw, vh, fill)
        val crop = if (fill) ThemeAssetImageMath.fillCrop(w, h, vw, vh) else intArrayOf(0, 0, w, h)
        val sample = ThemeAssetImageMath.coverSample(crop[2], crop[3], target[0], target[1])
        val img = BitmapFactory.decodeFile(f.path, BitmapFactory.Options().apply { inSampleSize = sample }) ?: return@runCatching null
        val sx = img.width.toFloat() / w; val sy = img.height.toFloat() / h
        val src = Rect((crop[0] * sx).toInt(), (crop[1] * sy).toInt(),
            minOf(img.width, ((crop[0] + crop[2]) * sx).toInt()), minOf(img.height, ((crop[1] + crop[3]) * sy).toInt()))
        val out = if (src.left == 0 && src.top == 0 && src.right == img.width && src.bottom == img.height &&
            img.width == target[0] && img.height == target[1]) img
        else Bitmap.createBitmap(target[0], target[1], Bitmap.Config.ARGB_8888).also { o ->
            Canvas(o).drawBitmap(img, src, Rect(0, 0, target[0], target[1]), Paint(Paint.FILTER_BITMAP_FLAG))
            img.recycle()
        }
        if (!hardware) out else runCatching { out.copy(Bitmap.Config.HARDWARE, false) }.getOrNull()?.also { out.recycle() } ?: out
    }.getOrNull()
}

/** Vẽ skin 9-slice vào khung phím — mảng / Rect dựng sẵn, không cấp phát mỗi lần vẽ. */
class SkinPainter {
    private val paint = Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG)
    private val src = Rect()
    private val dst = RectF()
    private val d = DoubleArray(4)
    private val xs = DoubleArray(4); private val ys = DoubleArray(4)
    private val dx = DoubleArray(4); private val dy = DoubleArray(4)

    fun draw(c: Canvas, s: LoadedSkin, down: Boolean, l: Float, t: Float, r: Float, b: Float, alpha: Int = 255) {
        val usePressed = down && s.pressed != null
        val bmp = if (usePressed) s.pressed!! else s.normal
        val ins = if (usePressed) s.pressedInsets else s.insets
        val sl = s.slice
        paint.alpha = alpha
        if (ins == null || sl == null) { dst.set(l, t, r, b); c.drawBitmap(bmp, null, dst, paint); return }
        val w = (r - l).toDouble(); val h = (b - t).toDouble()
        NineSlice.destInsetsInto(sl[0], sl[1], sl[2], sl[3], s.srcH, w, h, d)
        NineSlice.grid(bmp.width, bmp.height, ins[0], ins[1], ins[2], ins[3], w, h, d, xs, ys, dx, dy)
        for (j in 0 until 3) for (i in 0 until 3) {
            if (xs[i + 1] <= xs[i] || ys[j + 1] <= ys[j] || dx[i + 1] <= dx[i] || dy[j + 1] <= dy[j]) continue
            src.set(xs[i].toInt(), ys[j].toInt(), xs[i + 1].toInt(), ys[j + 1].toInt())
            dst.set(l + dx[i].toFloat(), t + dy[j].toFloat(), l + dx[i + 1].toFloat(), t + dy[j + 1].toFloat())
            c.drawBitmap(bmp, src, dst, paint)
        }
    }
}

/**
 * Ảnh tiền cảnh của theme: PNG trong suốt căng đúng khung bàn phím, TRÊN phím, DƯỚI vệt vuốt / hiệu ứng / ô phóng to.
 * Không nhận chạm (chạm xuyên xuống phím), không trợ năng. Bitmap giải một lần mỗi cỡ; gõ phím không vẽ lại view này.
 */
@SuppressLint("ViewConstructor")
class ThemeForegroundView(context: Context, private val file: File) : View(context) {
    private var bitmap: Bitmap? = null
    private var loadedW = 0
    private var loadedH = 0
    private val paint = Paint(Paint.FILTER_BITMAP_FLAG)
    private val rect = RectF()

    init {
        isClickable = false
        isFocusable = false
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    override fun onTouchEvent(event: android.view.MotionEvent?) = false

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        load(w, h)
    }

    private fun load(w: Int, h: Int) {
        if (w == loadedW && h == loadedH && bitmap != null) return
        loadedW = w; loadedH = h
        bitmap = ThemeAssetLoader.loadScreen(file, w, h, fill = false, hardware = isHardwareAccelerated)
        invalidate()
    }

    /** Hẹn giờ ẩn: nhả bitmap (true nếu đã có). */
    fun drop(): Boolean { val had = bitmap != null; bitmap = null; loadedW = 0; loadedH = 0; return had }

    /** Hiện lại sau [drop]: giải lại trên [background], chưa xong thì không vẽ gì. */
    fun reload(background: (Runnable) -> Unit) {
        val w = width; val h = height
        if (bitmap != null || w <= 0 || h <= 0) return
        val hw = isHardwareAccelerated
        background(Runnable {
            val b = ThemeAssetLoader.loadScreen(file, w, h, fill = false, hardware = hw)
            post { if (width == w && height == h && bitmap == null) { bitmap = b; loadedW = w; loadedH = h; invalidate() } }
        })
    }

    override fun onDraw(canvas: Canvas) {
        val b = bitmap ?: return
        if (b.config == Bitmap.Config.HARDWARE && !canvas.isHardwareAccelerated) return
        rect.set(0f, 0f, width.toFloat(), height.toFloat())
        canvas.drawBitmap(b, null, rect, paint)
    }
}
