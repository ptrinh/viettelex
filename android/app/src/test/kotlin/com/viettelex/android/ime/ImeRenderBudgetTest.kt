package com.viettelex.android.ime

import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Looper
import android.os.SystemClock
import android.text.InputType
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import com.viettelex.keyboard.KeyboardData
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import org.robolectric.android.controller.ServiceController

/**
 * NGÂN SÁCH VIỆC trên đường hiện bàn phím / bấm phím — tất định (đếm việc, không đo giờ), chạy
 * VietTelexIME thật trên Robolectric. Chặn hồi quy "bàn phím hiện chậm hơn" trước khi phát hành.
 *
 * Trần = giá trị đo được lúc đặt + chút dư. Một test đỏ nghĩa là đường hiện/gõ làm THÊM việc:
 *  1. Nếu là vô tình ⇒ sửa code (dời việc ra sau khung đầu / sang worker / dùng cache).
 *  2. Nếu là cố ý (tính năng mới thật sự cần) ⇒ nâng hằng số [Budget] tương ứng TRONG CÙNG commit,
 *     ghi lý do vào commit message và bảng ngân sách ở android/docs/PERF-IME-SHOW.md.
 * Số giờ thật (ms) đo bằng :benchmark (Macrobenchmark) — xem tài liệu đó.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-port-xxhdpi")
class ImeRenderBudgetTest {

    /** Trần ngân sách — sửa theo quy trình ở đầu file. */
    object Budget {
        /** Số view trong cây input view lúc hiện (mặc định, chưa bật hiệu ứng / nhân vật). */
        const val VIEWS = 6
        /** Byte cấp phát cho MỘT lượt vẽ lại lưới phím (onDraw), sau lượt đầu (đã trừ chi phí View.draw). */
        const val DRAW_ALLOC_BYTES = 0L
        /** Byte cấp phát cho một lần chạm-nhả phím chữ (đường chạm + session + IcProxy, chưa tính lượt gợi ý hẹn giờ). */
        const val KEYPRESS_ALLOC_BYTES = 3_000L
    }

    private lateinit var ctrl: ServiceController<VietTelexIME>
    private lateinit var ime: VietTelexIME
    private val loads = ArrayList<String>()
    private val main: Thread = Looper.getMainLooper().thread

    @Before fun setUp() {
        ImeCost.reset()
        com.viettelex.keyboard.L10n.lang = com.viettelex.keyboard.L10n.DEFAULT   // process mới
        KeyboardData.onLoad = { name, decode ->
            if (Thread.currentThread() === main) synchronized(loads) { loads += (if (decode) "text:" else "map:") + name }
        }
        ctrl = Robolectric.buildService(VietTelexIME::class.java).create()
        ime = ctrl.get()
    }

    /** Tạo lại service (process mới) với prefs đặt TRƯỚC onCreate. */
    private fun restartWith(prefs: Map<String, String>) {
        ctrl.destroy(); root = null
        val ctx = org.robolectric.RuntimeEnvironment.getApplication()
        ctx.getSharedPreferences(com.viettelex.keyboard.Keys.PREFS, android.content.Context.MODE_PRIVATE).edit().apply {
            prefs.forEach { (k, v) -> putString(k, v) }
        }.commit()
        com.viettelex.keyboard.L10n.lang = com.viettelex.keyboard.L10n.DEFAULT
        ImeCost.reset()
        ctrl = Robolectric.buildService(VietTelexIME::class.java).create()
        ime = ctrl.get()
    }

    @After fun tearDown() {
        KeyboardData.onLoad = null
        ctrl.destroy()
    }

    private fun field(type: Int = InputType.TYPE_CLASS_TEXT, action: Int = EditorInfo.IME_ACTION_NONE) = EditorInfo().apply {
        inputType = type; imeOptions = action; packageName = "com.example.chat"
        initialSelStart = 0; initialSelEnd = 0
    }

    private val width get() = ime.resources.displayMetrics.widthPixels

    /** Như framework: lần đầu dựng input view, rồi onStartInputView, đo + layout + vẽ một khung. */
    private var root: View? = null
    private fun show(info: EditorInfo = field(), restarting: Boolean = false): View {
        if (root == null) root = ime.onCreateInputView().also { ime.setInputView(it); inputFrame = it.parent as ViewGroup }
        ime.onStartInputView(info, restarting)
        // onStartInputView có thể dựng lại (setInputView cây mới) ⇒ lấy cây hiện hành từ khung input.
        val r = inputFrame!!.getChildAt(0)
        root = r
        frame(r)
        return r
    }
    /** mInputFrame của InputMethodService — cha của input view hiện hành. */
    private var inputFrame: ViewGroup? = null

    private fun frame(r: View) {
        r.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(ime.resources.displayMetrics.heightPixels, View.MeasureSpec.AT_MOST))
        r.layout(0, 0, r.measuredWidth, r.measuredHeight)
        val bmp = Bitmap.createBitmap(maxOf(1, r.width), maxOf(1, r.height), Bitmap.Config.ARGB_8888)
        r.draw(Canvas(bmp))
    }

    private fun hide() { ime.onFinishInputView(true) }

    private fun keyboard(v: View): KeyboardView = find(v, KeyboardView::class.java) ?: error("không thấy KeyboardView")
    private fun <T : View> find(v: View, type: Class<T>): T? {
        if (type.isInstance(v)) return type.cast(v)
        if (v is ViewGroup) for (i in 0 until v.childCount) find(v.getChildAt(i), type)?.let { return it }
        return null
    }
    private fun count(v: View): Int = 1 + if (v is ViewGroup) (0 until v.childCount).sumOf { count(v.getChildAt(it)) } else 0

    /** ThreadMXBean qua reflection (unit test app biên dịch với android.jar — không có java.lang.management). */
    private val mx: Any = Class.forName("java.lang.management.ManagementFactory").getMethod("getThreadMXBean").invoke(null)!!
    private val allocM = Class.forName("com.sun.management.ThreadMXBean").getMethod("getCurrentThreadAllocatedBytes")
    private fun allocated(): Long = allocM.invoke(mx) as Long

    private fun fail(what: String, got: Number, ceiling: Number) =
        "$what = $got > trần $ceiling. Đường hiện/gõ vừa làm thêm việc. Vô tình ⇒ sửa code; cố ý ⇒ nâng " +
            "ImeRenderBudgetTest.Budget + ghi lý do (android/docs/PERF-IME-SHOW.md, mục Ngân sách)."

    // MARK: mở lạnh

    @Test fun coldOpenBuildsOneTreeOneThemeOneLayout() {
        val r = show()
        assertEquals("onCreateInputView", 1, ImeCost.inputViews)
        assertEquals("ImeTheme dựng (onCreateInputView, không dựng lại ở onStartInputView)", 1, ImeCost.themes)
        assertEquals("KeyLayout.build — chỉ bảng chữ đang hiện", 1, ImeCost.layoutBuilds)
        println("BUDGET views = ${count(r)}")
        assertTrue(fail("Số view trong cây bàn phím", count(r), Budget.VIEWS), count(r) <= Budget.VIEWS)
    }

    /** Giao diện tiếng Anh: process mới vẫn chỉ dựng cây view MỘT lần (trước đây: dựng ở L10n mặc định rồi dựng lại). */
    @Test fun coldOpenWithEnglishUiBuildsTreeOnce() {
        restartWith(mapOf(com.viettelex.keyboard.Keys.UI_LANGUAGE to com.viettelex.keyboard.L10n.EN))
        show()
        assertEquals("onCreateInputView (giao diện EN)", 1, ImeCost.inputViews)
        assertEquals("ImeTheme dựng (giao diện EN)", 1, ImeCost.themes)
    }

    /** Không giải dữ liệu văn bản (seed / emoji / mẫu câu) trên main trước khung đầu; map blob nhị phân (mmap) thì rẻ. */
    @Test fun coldOpenDecodesNoTextAssetOnMain() {
        show()
        val decoded = synchronized(loads) { loads.filter { it.startsWith("text:") } }
        assertTrue("Giải asset văn bản trên main trước khung đầu: $decoded — dời sang worker / lười tới lần dùng", decoded.isEmpty())
    }

    // MARK: mở ấm

    @Test fun warmReopenRebuildsNothing() {
        val first = show()
        hide()
        ImeCost.reset()
        val again = show()
        assertSame("Mở lại phải giữ nguyên cây view", first, again)
        assertEquals("onCreateInputView khi mở lại", 0, ImeCost.inputViews)
        assertEquals("ImeTheme dựng lại khi mở lại (prefs không đổi)", 0, ImeCost.themes)
        assertEquals("KeyLayout.build khi mở lại cùng ô", 0, ImeCost.layoutBuilds)
    }

    /** Qua lại hai loại ô (chat ↔ tìm kiếm): lần thứ hai mỗi loại lấy bố cục từ cache. */
    @Test fun alternatingFieldsServeLayoutsFromCache() {
        val chat = field()
        val search = field(InputType.TYPE_CLASS_TEXT, EditorInfo.IME_ACTION_SEARCH)
        show(chat); hide(); show(search); hide()
        ImeCost.reset()
        show(chat); hide(); show(search); hide(); show(chat)
        assertEquals("KeyLayout.build khi quay lại ô đã gặp", 0, ImeCost.layoutBuilds)
        assertEquals("onCreateInputView khi đổi ô", 0, ImeCost.inputViews)
    }

    // MARK: đổi bảng phím

    @Test fun planeSwitchBuildsEachPlaneOnce() {
        val kb = keyboard(show())
        ImeCost.reset()
        repeat(3) {
            kb.setPlane(Plane.NUMBERS); frame(root!!)
            kb.setPlane(Plane.LETTERS); frame(root!!)
        }
        assertEquals("KeyLayout.build: ?123 dựng một lần, chữ từ cache", 1, ImeCost.layoutBuilds)
    }

    // MARK: hoãn gợi ý lúc hiện ra sau khung đầu

    @Test fun startInputDefersSuggestionBarPastFirstFrame() {
        show()
        assertEquals("gợi ý chạy trong onStartInputView (trước khung đầu có phím)", 0, ImeCost.barRefreshes)
        shadowOf(Looper.getMainLooper()).idleFor(java.time.Duration.ofMillis(100))
        assertEquals("gợi ý chạy một lần ngay sau khung đầu", 1, ImeCost.barRefreshes)
    }

    /** Gõ ngay khi bàn phím vừa hiện (lượt gợi ý hoãn chưa chạy): phím đầu không mất, lượt hoãn tự bỏ. */
    @Test fun keysTypedBeforeDeferredBarAreNotLost() {
        val ed = FakeEditor("")
        ime.testPort = ed
        val kb = keyboard(show(field()))
        tap(kb, "x"); tap(kb, "i")
        assertEquals("phím gõ trước lượt gợi ý hoãn", "xi", ed.text)
        shadowOf(Looper.getMainLooper()).idleFor(java.time.Duration.ofMillis(200))
        assertEquals("xi", ed.text)
        assertEquals("lượt hoãn bỏ qua (phím đã đổi thế hệ — gợi ý của chính phím lo bar)", 0, ImeCost.barRefreshes)
    }

    /** Ẩn trước khi khung kế tới: lượt hoãn không chạy cho bàn phím đã ẩn. */
    @Test fun deferredBarDroppedWhenHiddenFirst() {
        show(); hide()
        shadowOf(Looper.getMainLooper()).idleFor(java.time.Duration.ofMillis(100))
        assertEquals(0, ImeCost.barRefreshes)
    }

    // MARK: không đọc / nạp gì thừa trước khung đầu (đợt 10/11/2026)

    private fun capField(initial: String?) = field(InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES).apply {
        initialCapsMode = android.text.TextUtils.CAP_MODE_SENTENCES
        val n = initial?.length ?: 0
        initialSelStart = n; initialSelEnd = n
        if (initial != null) setInitialSurroundingText(initial)
    }

    /** Ô viết hoa đầu câu + chữ ban đầu tin được (API 30+): auto-shift lúc hiện KHÔNG đọc ô (0 IPC). */
    @Test fun firstAutoShiftUsesInitialTextWithoutReads() {
        val port = ImePerf.CountingPort(FakeEditor("Xin chào. "))
        ime.testPort = port
        val kb = keyboard(show(capField("Xin chào. ")))
        assertEquals("getTextBeforeCursor trước khung đầu", 0, port.reads)
        assertEquals("sau \". \" phải bật shift", KeyboardView.Shift.ON, kb.shift)
        shadowOf(Looper.getMainLooper()).idleFor(java.time.Duration.ofMillis(100))
        assertEquals(KeyboardView.Shift.ON, kb.shift)
    }

    /** Giữa câu: chữ ban đầu cho shift TẮT ngay ở khung đầu (không chờ đọc). */
    @Test fun firstAutoShiftMidSentenceFromInitialText() {
        val port = ImePerf.CountingPort(FakeEditor("xin chào"))
        ime.testPort = port
        val kb = keyboard(show(capField("xin chào").apply { initialCapsMode = 0 }))
        assertEquals(0, port.reads)
        assertEquals(KeyboardView.Shift.OFF, kb.shift)
    }

    /** Không có chữ ban đầu: khung đầu theo initialCapsMode, 0 IPC; đọc xác nhận ngay sau khung đầu. */
    @Test fun firstAutoShiftWithoutInitialTextConfirmsAfterFirstFrame() {
        val port = ImePerf.CountingPort(FakeEditor("xin chào"))   // giữa câu, app báo initialCaps sai
        ime.testPort = port
        val kb = keyboard(show(capField(null).apply { initialSelStart = 8; initialSelEnd = 8 }))
        assertEquals("getTextBeforeCursor trước khung đầu", 0, port.reads)
        assertEquals("khung đầu theo initialCapsMode", KeyboardView.Shift.ON, kb.shift)
        shadowOf(Looper.getMainLooper()).idleFor(java.time.Duration.ofMillis(100))
        assertTrue("xác nhận sau khung đầu phải đọc ô", port.reads >= 1)
        assertEquals("chữ thật giữa câu ⇒ shift tắt", KeyboardView.Shift.OFF, kb.shift)
    }

    /** Kaomoji (emoji.bin + đo ~136 chuỗi) chỉ dàn khi mở tab ^‿^ — không ở lượt layout đầu, không khi mở bảng emoji. */
    @Test fun kaomojiNotLaidOutUntilTabOpens() {
        val kb = keyboard(show())
        assertEquals("dàn kaomoji lúc hiện bàn phím", 0, ImeCost.kaomojiLayouts)
        kb.setPlane(Plane.EMOJI); frame(root!!)
        assertEquals("dàn kaomoji khi mở bảng emoji (tab kaomoji chưa mở)", 0, ImeCost.kaomojiLayouts)
        assertTrue(kb.emojiPane.kaomojiItems.isNotEmpty())   // mở tab
        assertEquals(1, ImeCost.kaomojiLayouts)
    }

    /** Mẫu câu: không đọc / giải / cắt "…" khi bảng ☰ đóng; nạp một lần lúc mở bảng. */
    @Test fun templatesNotLoadedUntilPaneOpens() {
        val kb = keyboard(show())
        hide(); show()
        assertEquals("nạp mẫu câu khi bảng ☰ đóng", 0, ImeCost.templateLoads)
        kb.setPlane(Plane.TEMPLATES); frame(root!!)
        assertEquals(1, ImeCost.templateLoads)
        kb.setPlane(Plane.LETTERS); kb.setPlane(Plane.TEMPLATES); frame(root!!)
        assertEquals("mở lại: từ cache", 1, ImeCost.templateLoads)
    }

    /** Dò IME giọng nói (binder) sau khung đầu, không trong onStartInputView. */
    @Test fun voiceProbeRunsAfterFirstFrame() {
        show()
        assertEquals("dò IME giọng nói trước khung đầu", 0, ImeCost.voiceProbes)
        shadowOf(Looper.getMainLooper()).idleFor(java.time.Duration.ofMillis(100))
        assertEquals(1, ImeCost.voiceProbes)
    }

    /** Trình tiết kiệm pin: không tính năng có cổng pin (mặc định) ⇒ không đọc lần nào. */
    @Test fun powerSaveNotReadWithoutGatedFeature() {
        show()
        assertEquals(0, ime.powerSaveShow.reads)
    }

    /** Cỡ bàn phím dọc cho app cài đặt: ghi SAU lượt layout/vẽ đầu (prefs runtime không trong khung đầu). */
    @Test fun portraitSizeRecordedAfterFirstFrame() {
        val sp = ime.getSharedPreferences(com.viettelex.keyboard.Keys.RUNTIME_PREFS, android.content.Context.MODE_PRIVATE)
        show()
        assertEquals(null, sp.getString(com.viettelex.keyboard.Keys.IME_PORTRAIT_SIZE, null))
        shadowOf(Looper.getMainLooper()).idle()
        assertNotNull(sp.getString(com.viettelex.keyboard.Keys.IME_PORTRAIT_SIZE, null))
    }

    // MARK: bấm phím

    private fun tap(kb: KeyboardView, label: String) {
        val p = assertNotNullKey(kb, label)
        val t = SystemClock.uptimeMillis()
        val down = MotionEvent.obtain(t, t, MotionEvent.ACTION_DOWN, p.x, p.y, 0)
        val up = MotionEvent.obtain(t, t + 40, MotionEvent.ACTION_UP, p.x, p.y, 0)
        kb.dispatchTouchEvent(down); kb.dispatchTouchEvent(up)
        down.recycle(); up.recycle()
    }
    private fun assertNotNullKey(kb: KeyboardView, label: String) =
        kb.keyCenter(label).also { assertNotNull("không có phím $label", it) }!!

    /** Phím chữ: phản hồi bấm nằm ở overlay balloon — lưới phím (display list ~40 phím) không bị ghi lại. */
    @Test fun letterKeypressDoesNotDirtyKeyGrid() {
        val kb = keyboard(show(field()))   // ô không tự viết hoa ⇒ shift không đổi khi gõ
        shadowOf(Looper.getMainLooper()).idle()
        frame(root!!)
        assertFalse(kb.isDirty)
        for (c in "nhanh") {
            tap(kb, c.toString())
            assertFalse("Phím '$c' làm bẩn lưới phím (ghi lại display list mọi phím)", kb.isDirty)
        }
        shadowOf(Looper.getMainLooper()).idle()   // auto-shift + gợi ý đã chạy
        assertFalse("Sau lượt auto-shift / gợi ý lưới phím vẫn sạch", kb.isDirty)
    }

    /** Badge "ViệtTelex" mờ dần mỗi lần hiện (~20 khung): chỉ lớp động, lưới phím tĩnh không ghi lại. */
    @Test fun spaceBadgeAnimationKeepsGridClean() {
        val kb = keyboard(show())
        assertFalse(kb.gridStale)
        val before = ImeCost.gridRecords
        kb.showLanguageBadge()
        assertTrue("badge phải vẽ lại view", kb.isDirty)
        assertFalse("badge làm bẩn lưới phím tĩnh", kb.gridStale)
        frame(root!!)
        // Canvas phần mềm (Robolectric) vẽ thẳng — đếm ghi-lưới chỉ có nghĩa ở canvas phần cứng; ở đây
        // kiểm cờ bẩn (đúng thứ quyết định ghi lại RenderNode).
        assertTrue(ImeCost.gridRecords >= before)
    }

    /** Ngược lại: shift đổi nhãn mọi phím ⇒ lưới PHẢI ghi lại (mặc định an toàn của invalidate()). */
    @Test fun shiftChangeDirtiesGrid() {
        val kb = keyboard(show())
        assertFalse(kb.gridStale)
        kb.setAutoShift(true)
        assertTrue(kb.gridStale)
    }

    @Test fun keyGridRedrawAllocatesNothing() {
        val r = show()
        val kb = keyboard(r)
        val bmp = Bitmap.createBitmap(kb.width, kb.height, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        repeat(3) { kb.draw(c) }    // khởi động (cache nhãn / icon lười)
        // Hiệu chỉnh: chính View.draw (phần mềm, Robolectric) + lời gọi đo cũng cấp phát vài chục byte ⇒
        // trừ đi lượt vẽ một View rỗng cùng cỡ — phần còn lại là của onDraw bàn phím.
        val plain = View(ime).apply { layout(0, 0, kb.width, kb.height) }
        repeat(3) { plain.draw(c) }
        val bytes = (0 until 5).minOf {
            val p0 = allocated(); plain.draw(c); val base = allocated() - p0
            val b0 = allocated(); kb.draw(c); (allocated() - b0) - base
        }
        println("BUDGET draw alloc = $bytes B")
        assertTrue(fail("Byte cấp phát mỗi lượt vẽ lưới phím", bytes, Budget.DRAW_ALLOC_BYTES), bytes <= Budget.DRAW_ALLOC_BYTES)
    }

    @Test fun letterKeypressAllocationBudget() {
        val kb = keyboard(show(field()))
        repeat(20) { tap(kb, "a"); tap(kb, "s") }   // khởi động
        shadowOf(Looper.getMainLooper()).idle()
        val b0 = allocated()
        tap(kb, "d")
        val bytes = allocated() - b0
        println("BUDGET keypress alloc = $bytes B")
        assertTrue(fail("Byte cấp phát mỗi lần chạm phím chữ", bytes, Budget.KEYPRESS_ALLOC_BYTES), bytes <= Budget.KEYPRESS_ALLOC_BYTES)
    }
}
