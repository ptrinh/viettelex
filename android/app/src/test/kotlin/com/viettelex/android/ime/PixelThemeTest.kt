package com.viettelex.android.ime

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Typeface
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.text.InputType
import com.viettelex.keyboard.KeyLabelFont
import com.viettelex.keyboard.KeyStyle
import com.viettelex.keyboard.Keys
import com.viettelex.keyboard.PlusGate
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import org.robolectric.android.controller.ServiceController
import java.io.File
import java.text.Normalizer

/**
 * Theme "Pixel 8-bit" trên IME thật (Robolectric, đồ hoạ native): phông điểm ảnh NHÚNG có glyph cho MỌI chữ Việt
 * (Paint.hasGlyph), nạp lười + dùng chung, dáng phím điểm ảnh vẽ không cấp phát, theme khác không chạm tới; ảnh chụp
 * cho chủ repo xem (/Users/ptrinh/Downloads/Temp/pixel-theme-android.png — chỉ khi thư mục có sẵn).
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-port-xxhdpi")
class PixelThemeTest {
    private var ctrl: ServiceController<VietTelexIME>? = null
    private val savedPaywall = PlusGate.paywallEnabled

    @Before fun setUp() { PlusGate.paywallEnabled = false }
    @After fun tearDown() {
        ctrl?.destroy()
        // Không để lại theme / chế độ tối cho lớp test khác chạy cùng sandbox (ImeRenderBudgetTest đo theme mặc định).
        RuntimeEnvironment.getApplication().getSharedPreferences(Keys.PREFS, android.content.Context.MODE_PRIVATE)
            .edit().clear().commit()
        RuntimeEnvironment.setQualifiers("+notnight")
        PlusGate.paywallEnabled = savedPaywall
    }

    /** Mọi chữ cái tiếng Việt: a–z, đ, 12 nguyên âm × 6 thanh — hoa + thường (iOS PixelKeysTests y hệt). */
    private val vietnameseLetters: List<String> by lazy {
        val vowels = listOf("a", "ă", "â", "e", "ê", "i", "o", "ô", "ơ", "u", "ư", "y")
        val tones = listOf("", "́", "̀", "̉", "̃", "̣")
        val lower = ('a'..'z').map { it.toString() } + "đ" +
            vowels.flatMap { v -> tones.map { Normalizer.normalize(v + it, Normalizer.Form.NFC) } }
        (lower + lower.map { it.uppercase() }).toSortedSet().toList()
    }

    @Test fun pixelFontCoversVietnamese() {
        val ctx = RuntimeEnvironment.getApplication()
        val tf = PixelFont.typeface(ctx.assets)
        assertNotNull("assets/${PixelFont.ASSET} phải có (fonts/ gốc repo)", tf)
        assertSame("nạp một lần, dùng chung", tf, PixelFont.typeface(ctx.assets))
        assertEquals(2 * (26 + 1 + 12 * 6 - 6), vietnameseLetters.size)
        val p = Paint().apply { typeface = tf; textSize = 48f }
        for (s in vietnameseLetters) {
            assertEquals("$s một ký tự dựng sẵn", 1, s.length)
            assertTrue("thiếu glyph $s", p.hasGlyph(s))
        }
        // Phông nhỏ (< 60 KB) + có giấy phép OFL đi kèm trong assets.
        assertTrue(ctx.assets.open(PixelFont.ASSET).use { it.readBytes().size } < 60 * 1024)
        assertTrue(ctx.assets.open("OFL-Tiny5-Regular.txt").use { it.readBytes().decodeToString() }.contains("SIL OPEN FONT LICENSE"))
        // KeyLabelFont.PIXEL ⇒ đúng phông này, bỏ qua độ đậm.
        assertSame(tf, keyLabelTypeface(KeyStyle(font = KeyLabelFont.PIXEL, weight = com.viettelex.keyboard.KeyLabelWeight.HEAVY), null, ctx.assets))
    }

    private fun startWithTheme(theme: String): VietTelexIME {
        ctrl?.destroy()
        val ctx = RuntimeEnvironment.getApplication()
        ctx.getSharedPreferences(Keys.PREFS, android.content.Context.MODE_PRIVATE).edit()
            .putString(Keys.KEYBOARD_THEME, theme).commit()
        val c = Robolectric.buildService(VietTelexIME::class.java).create()
        ctrl = c
        return c.get()
    }

    private fun show(ime: VietTelexIME): View {
        val v = ime.onCreateInputView()
        ime.setInputView(v)
        val frame = v.parent as ViewGroup
        ime.onStartInputView(EditorInfo().apply { inputType = InputType.TYPE_CLASS_TEXT; packageName = "com.example.chat" }, false)
        val r = frame.getChildAt(0)
        val dm = ime.resources.displayMetrics
        r.measure(View.MeasureSpec.makeMeasureSpec(dm.widthPixels, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(dm.heightPixels, View.MeasureSpec.AT_MOST))
        r.layout(0, 0, r.measuredWidth, r.measuredHeight)
        return r
    }

    private fun <T : View> find(v: View, type: Class<T>): T? {
        if (type.isInstance(v)) return type.cast(v)
        if (v is ViewGroup) for (i in 0 until v.childCount) find(v.getChildAt(i), type)?.let { return it }
        return null
    }

    // Đo cấp phát khi vẽ: KHÔNG đo ở đây — ImeRenderBudgetTest dùng đếm byte theo luồng qua reflection, gọi thêm ở
    // lớp khác trong cùng JVM làm số đo của nó dao động (hộp Long 16 B). Đường vẽ điểm ảnh dùng mảng ghi sẵn
    // (PixelKeys.write, PixelKeysTests.writeIsAllocationFreeShape).
    @Test fun pixelThemeWiringAndOtherThemesUntouched() {
        val ime = startWithTheme("pixel")
        val r = show(ime)
        val kb = find(r, KeyboardView::class.java)!!
        val theme = ImeTheme(ime, com.viettelex.keyboard.ThemeSettings.load { ime.getSharedPreferences(Keys.PREFS, 0).all[it] })
        assertTrue(theme.pixelKeys)
        assertNotNull(theme.stripTypeface)
        assertSame(PixelFont.typeface(ime.assets), theme.keyTypeface)
        val bmp = Bitmap.createBitmap(kb.width, kb.height, Bitmap.Config.ARGB_8888)
        kb.draw(Canvas(bmp))
        // Lõi phím "q" (cạnh chữ) = màu phím; viền khối màu viền ngay trên nó (đi lên tới khi đổi màu).
        val q = kb.keyCenter("q")!!
        val x = q.x.toInt() - (10 * ime.resources.displayMetrics.density).toInt()
        assertEquals(theme.keyFill or 0xFF000000.toInt(), bmp.getPixel(x, q.y.toInt()) or 0xFF000000.toInt())
        var y = q.y.toInt()
        while (y > 0 && bmp.getPixel(x, y) == bmp.getPixel(x, q.y.toInt())) y--
        assertEquals("viền khối trên lõi", theme.keyBorder!! or 0xFF000000.toInt(), bmp.getPixel(x, y) or 0xFF000000.toInt())

        val other = ImeTheme(ime, com.viettelex.keyboard.ThemeSettings(theme = com.viettelex.keyboard.KeyboardTheme.MINT))
        assertTrue(!other.pixelKeys)
        assertNull(other.stripTypeface)
    }

    @Test fun snapshotForOwner() {
        val dir = File("/Users/ptrinh/Downloads/Temp")
        if (!dir.isDirectory) return
        val shots = ArrayList<Bitmap>()
        for (night in listOf(false, true)) {
            RuntimeEnvironment.setQualifiers(if (night) "+night" else "+notnight")
            val ime = startWithTheme("pixel")
            val r = show(ime)
            val kb = find(r, KeyboardView::class.java)!!
            kb.keyCenter("g")?.let { p ->
                val t = android.os.SystemClock.uptimeMillis()
                kb.dispatchTouchEvent(android.view.MotionEvent.obtain(t, t, android.view.MotionEvent.ACTION_DOWN, p.x, p.y, 0))
            }
            val bmp = Bitmap.createBitmap(r.width, r.height, Bitmap.Config.ARGB_8888)
            r.draw(Canvas(bmp))
            shots.add(bmp)
        }
        val out = Bitmap.createBitmap(shots[0].width, shots.sumOf { it.height } + 24, Bitmap.Config.ARGB_8888)
        val c = Canvas(out)
        c.drawColor(0xFFFFFFFF.toInt())
        var y = 0f
        for (s in shots) { c.drawBitmap(s, 0f, y, null); y += s.height + 24 }
        File(dir, "pixel-theme-android.png").outputStream().use { out.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }
}
