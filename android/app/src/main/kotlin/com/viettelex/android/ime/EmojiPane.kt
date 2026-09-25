package com.viettelex.android.ime

import android.graphics.Canvas
import android.graphics.Paint
import android.text.TextPaint
import android.text.TextUtils
import android.view.VelocityTracker
import android.view.ViewConfiguration
import android.widget.OverScroller
import com.viettelex.keyboard.EmojiData
import kotlin.math.abs
import kotlin.math.ceil

/**
 * Plane emoji (port iOS EmojiPlane, spec §10.1) vẽ thẳng trên Canvas của
 * [KeyboardView] — không RecyclerView/ViewGroup. Lưới cuộn NGANG column-major 5 hàng
 * liên tục qua category, tiêu đề section xám trên cột đầu, hàng dưới
 * [ABC][9 icon category][⌫]. Chỉ vẽ cột đang thấy.
 */
class EmojiPane(
    private val host: KeyboardView,
    private val theme: ImeTheme,
    private val feedback: Feedback,
) {
    private class Section(val name: String, val emoji: List<String>, val title: String) {
        var headerX = 0f; var itemsX = 0f; var cols = 0; var endX = 0f
        var titleShown = title
    }

    private val d = theme.density
    private var sections: List<Section> = emptyList()
    private var width = 0f
    private var height = 0f
    private var collTop = 0f; private var collH = 0f
    private var item = 0f
    private var contentW = 0f
    private var scrollX = 0f
    private val scroller = OverScroller(host.context)
    private var velocity: VelocityTracker? = null
    private val touchSlop = ViewConfiguration.get(host.context).scaledTouchSlop
    private val maxFling = ViewConfiguration.get(host.context).scaledMaximumFlingVelocity.toFloat()

    private val emojiPaint = theme.text(30f)
    private var emojiOff = 0f
    private var headerBase = 0f
    private val headerPaint = TextPaint(theme.text(11f, color = theme.withAlpha(theme.ink, 0.5f), bold = true,
        align = Paint.Align.LEFT))
    private val abcPaint = theme.text(15f, medium = true)
    private val abcOff = theme.centerOffset(abcPaint)
    private val iconPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val hiPaint = theme.fill(theme.chip)   // chỉ báo kiểu thanh điều hướng Material
    private val popupPaint = theme.fill(theme.popupFill).apply {
        if (android.os.Build.VERSION.SDK_INT >= 28) setShadowLayer(theme.dp(3f), 0f, theme.dp(1f), 0x4D000000)
    }
    private val tonePaint = theme.text(26f)
    private val toneOff = theme.centerOffset(tonePaint)

    // hàng category
    private var rowTop = 0f; private var rowBottom = 0f
    private var iconsLeft = 0f; private var iconW = 0f
    private var highlighted = 0
    private var pendingIcon = -1

    // touch
    private var gridPtr = -1
    private var dragging = false
    private var downX = 0f; private var downY = 0f; private var lastTouchX = 0f
    private var delPtr = -1
    private var iconPtr = -1
    private var popup: List<String>? = null
    private var popupX = 0f; private var popupY = 0f
    private var popupPtr = -1

    private val holdRun = Runnable { showTonePopupAt(downX, downY) }
    private val delStartRun = Runnable { host.postDelayed(delTickRun, 90) }
    private val delTickRun = object : Runnable {
        override fun run() { host.paneBackspace(); host.postDelayed(this, 90) }
    }
    private val animRun = Runnable { tick() }

    fun open(recents: List<String>) {
        dismissPopup()
        val list = ArrayList<Section>(10)
        if (recents.isNotEmpty()) list += Section(EmojiData.RECENTS, recents, EmojiData.displayName(EmojiData.RECENTS))
        for (c in EmojiData.categories) list += Section(c.name, c.emoji, EmojiData.displayName(c.name))
        sections = list
        scrollX = 0f
        scroller.forceFinished(true)
        pendingIcon = -1
        relayoutSections()
        highlighted = iconIndex(sectionOnScreen())
    }

    fun layout(w: Float, h: Float) {
        if (w == width && h == height) return
        width = w; height = h
        collTop = theme.dp(6f)
        rowBottom = h - theme.dp(2f)
        rowTop = rowBottom - theme.dp(32f)
        collH = rowTop - theme.dp(2f) - collTop
        item = maxOf((collH - HEADER_BAND * d - 4 * 4 * d) / 5f, 10 * d)
        emojiPaint.textSize = minOf(theme.sp(30f), item * 0.82f)
        emojiOff = theme.centerOffset(emojiPaint)
        headerBase = collTop - headerPaint.fontMetrics.ascent
        val abcW = 44 * d; val side = 8 * d; val gap = 2 * d
        iconsLeft = side + abcW + gap
        iconW = (w - 2 * side - 2 * abcW - 2 * gap) / 9f
        relayoutSections()
    }

    private fun relayoutSections() {
        if (width == 0f) return
        var x = 0f
        for (s in sections) {
            s.headerX = x
            x += 8 * d                     // header strip
            x += 6 * d                     // section inset trái
            s.itemsX = x
            s.cols = maxOf(ceil(s.emoji.size / 5.0).toInt(), 1)
            x += s.cols * item + (s.cols - 1) * 8 * d
            s.endX = x
            x += 6 * d
            val maxW = s.cols * item + (s.cols - 1) * 8 * d
            // Tiêu đề không tràn sang section kế (bug iOS 2026-07-25) — ellipsize 1 lần.
            s.titleShown = TextUtils.ellipsize(s.title, headerPaint, maxW, TextUtils.TruncateAt.END).toString()
        }
        contentW = x
        scrollX = scrollX.coerceIn(0f, maxScroll())
    }

    private fun maxScroll() = maxOf(0f, contentW - width)

    // MARK: vẽ

    fun draw(c: Canvas) {
        val w = width
        c.save()
        c.clipRect(0f, 0f, w, rowTop - theme.dp(1f))
        val colStep = item + 8 * d
        val rowStep = item + 4 * d
        val gridTop = collTop + HEADER_BAND * d
        val secs = sections
        for (si in secs.indices) {
            val s = secs[si]
            if (s.endX + 6 * d < scrollX || s.headerX > scrollX + w) continue
            c.drawText(s.titleShown, s.headerX + 2 * d - scrollX, headerBase, headerPaint)
            val firstCol = maxOf(0, ((scrollX - s.itemsX) / colStep).toInt())
            var col = firstCol
            while (col < s.cols) {
                val x0 = s.itemsX + col * colStep - scrollX
                if (x0 > w) break
                val cx = x0 + item / 2
                for (r in 0 until 5) {
                    val idx = col * 5 + r
                    if (idx >= s.emoji.size) break
                    c.drawText(s.emoji[idx], cx, gridTop + r * rowStep + item / 2 + emojiOff, emojiPaint)
                }
                col++
            }
        }
        c.restore()
        drawCategoryRow(c)
        popup?.let { drawPopup(c, it) }
    }

    private fun drawCategoryRow(c: Canvas) {
        val cy = (rowTop + rowBottom) / 2
        c.drawText("ABC", 8 * d + 22 * d, cy + abcOff, abcPaint)
        for (i in 0 until 9) {
            val cx = iconsLeft + (i + 0.5f) * iconW
            val on = i == highlighted
            if (on) { val hw = minOf(iconW / 2 - d, 16 * d); c.drawRoundRect(cx - hw, cy - 13 * d, cx + hw, cy + 13 * d, 13 * d, 13 * d, hiPaint) }
            iconPaint.color = if (on) theme.ink else theme.withAlpha(theme.ink, 0.55f)
            ImeIcons.draw(c, ImeIcons.CATEGORY[i], cx, cy, 19.5f * d, iconPaint)
        }
        iconPaint.color = theme.ink
        ImeIcons.draw(c, ImeIcons.DELETE, width - 8 * d - 22 * d, cy, 22f * d, iconPaint)
    }

    private fun drawPopup(c: Canvas, variants: List<String>) {
        val iw = 36 * d; val h = 44 * d
        val w = variants.size * iw
        c.drawRoundRect(popupX, popupY, popupX + w, popupY + h, 10 * d, 10 * d, popupPaint)
        for (i in variants.indices) {
            c.drawText(variants[i], popupX + (i + 0.5f) * iw, popupY + h / 2 + toneOff, tonePaint)
        }
    }

    // MARK: category

    private fun sectionIndex(forIcon: Int): Int? {
        val hasRecents = sections.firstOrNull()?.name == EmojiData.RECENTS
        if (forIcon == 0) return if (hasRecents) 0 else null
        val idx = forIcon - 1 + if (hasRecents) 1 else 0
        return if (idx < sections.size) idx else null
    }

    private fun iconIndex(section: Int): Int {
        val hasRecents = sections.firstOrNull()?.name == EmojiData.RECENTS
        return if (hasRecents) section else section + 1
    }

    /** Section của item trái nhất đang thấy. */
    private fun sectionOnScreen(): Int {
        for (i in sections.indices) if (sections[i].endX > scrollX) return i
        return maxOf(0, sections.size - 1)
    }

    private fun jumpToCategory(icon: Int) {
        val s = sectionIndex(icon) ?: return
        if (sections[s].emoji.isEmpty()) return
        pendingIcon = icon
        val target = (sections[s].itemsX - 6 * d).coerceIn(0f, maxScroll())
        scroller.forceFinished(true)
        scroller.startScroll(scrollX.toInt(), 0, (target - scrollX).toInt(), 0, 300)
        highlighted = icon
        host.postInvalidateOnAnimation()
    }

    private fun onScrolled() {
        if (pendingIcon >= 0) return
        val h = iconIndex(sectionOnScreen())
        if (h != highlighted) highlighted = h
    }

    fun computeScroll() {
        if (scroller.computeScrollOffset()) {
            scrollX = scroller.currX.toFloat().coerceIn(0f, maxScroll())
            onScrolled()
            host.postInvalidateOnAnimation()
        } else if (pendingIcon >= 0 && scroller.isFinished && !dragging) {
            pendingIcon = -1
        }
    }

    private fun tick() = host.postInvalidateOnAnimation()

    // MARK: touch

    fun down(pid: Int, x: Float, y: Float) {
        popup?.let { v ->
            val iw = 36 * d
            if (y >= popupY && y < popupY + 44 * d && x >= popupX && x < popupX + v.size * iw) {
                popupPtr = pid; return
            }
            dismissPopup()
        }
        if (y >= rowTop - 2 * d) {
            when {
                x < iconsLeft -> { feedback.click(Feedback.MODIFIER, host); host.paneABC() }
                x >= width - 8 * d - 44 * d - 2 * d -> {
                    feedback.click(Feedback.DELETE, host)
                    host.paneBackspace()
                    delPtr = pid
                    host.removeCallbacks(delStartRun); host.removeCallbacks(delTickRun)
                    host.postDelayed(delStartRun, 500)
                }
                else -> iconPtr = pid
            }
            return
        }
        if (gridPtr >= 0) return    // một ngón cuộn/tap lưới
        gridPtr = pid
        dragging = false
        downX = x; downY = y; lastTouchX = x
        scroller.forceFinished(true)
        velocity?.recycle()
        velocity = VelocityTracker.obtain()
        host.removeCallbacks(holdRun)
        host.postDelayed(holdRun, 350)
    }

    /** KeyboardView chuyển MotionEvent thật cho VelocityTracker (không tổng hợp event). */
    fun track(e: android.view.MotionEvent) { if (gridPtr >= 0) velocity?.addMovement(e) }

    fun move(pid: Int, x: Float, y: Float) {
        if (pid != gridPtr) return
        if (!dragging && abs(x - downX) > touchSlop) {
            dragging = true
            pendingIcon = -1
            host.removeCallbacks(holdRun)
            dismissPopup()
            lastTouchX = x
        }
        if (dragging) {
            val nx = (scrollX + (lastTouchX - x)).coerceIn(0f, maxScroll())
            lastTouchX = x
            if (nx != scrollX) { scrollX = nx; onScrolled(); host.invalidate() }
        }
    }

    fun up(pid: Int, x: Float, y: Float, cancelled: Boolean) {
        when (pid) {
            popupPtr -> {
                popupPtr = -1
                val v = popup ?: return
                val i = ((x - popupX) / (36 * d)).toInt()
                if (!cancelled && y >= popupY - 8 * d && y < popupY + 52 * d && i in v.indices) {
                    feedback.click(Feedback.LETTER, host)
                    val e = v[i]
                    dismissPopup()
                    chose(e)
                }
                return
            }
            delPtr -> { delPtr = -1; host.removeCallbacks(delStartRun); host.removeCallbacks(delTickRun); return }
            iconPtr -> {
                iconPtr = -1
                if (!cancelled && y >= rowTop - 8 * d && x >= iconsLeft && x < iconsLeft + 9 * iconW) {
                    jumpToCategory(((x - iconsLeft) / iconW).toInt().coerceIn(0, 8))
                }
                return
            }
            gridPtr -> {
                gridPtr = -1
                host.removeCallbacks(holdRun)
                val v = velocity
                if (dragging && v != null) {
                    v.computeCurrentVelocity(1000, maxFling)
                    val vx = -v.getXVelocity(pid)
                    scroller.fling(scrollX.toInt(), 0, vx.toInt(), 0, 0, maxScroll().toInt(), 0, 0)
                    host.postInvalidateOnAnimation()
                } else if (!cancelled && popup == null && !dragging) {
                    emojiAt(downX, downY)?.let { e ->
                        feedback.click(Feedback.LETTER, host)
                        chose(e)
                    }
                }
                velocity?.recycle(); velocity = null
                dragging = false
            }
        }
    }

    private fun chose(e: String) {
        val hadRecents = sections.firstOrNull()?.name == EmojiData.RECENTS
        host.paneEmoji(e)
        if (!hadRecents) {
            // Lần dùng đầu trong phiên: section 🕐 xuất hiện ngay.
            val keep = scrollX
            val list = ArrayList<Section>(sections.size + 1)
            list += Section(EmojiData.RECENTS, listOf(e), EmojiData.displayName(EmojiData.RECENTS))
            list.addAll(sections)
            sections = list
            relayoutSections()
            scrollX = keep.coerceIn(0f, maxScroll())
            highlighted = iconIndex(sectionOnScreen())
        }
        host.invalidate()
    }

    private fun emojiAt(x: Float, y: Float): String? {
        val gridTop = collTop + HEADER_BAND * d
        val rowStep = item + 4 * d
        val colStep = item + 8 * d
        if (y < gridTop - 2 * d) return null
        val r = ((y - gridTop) / rowStep).toInt()
        if (r !in 0..4) return null
        val cx = x + scrollX
        for (s in sections) {
            if (cx < s.itemsX - 4 * d || cx > s.endX + 4 * d) continue
            val col = ((cx - s.itemsX + 4 * d) / colStep).toInt().coerceIn(0, s.cols - 1)
            val idx = col * 5 + r
            return s.emoji.getOrNull(idx)
        }
        return null
    }

    private fun showTonePopupAt(x: Float, y: Float) {
        if (dragging) return
        val e = emojiAt(x, y) ?: return
        val variants = EmojiData.toneVariants(e) ?: return
        feedback.click(Feedback.MODIFIER, host)
        // ô chứa điểm chạm
        val gridTop = collTop + HEADER_BAND * d
        val rowStep = item + 4 * d
        val colStep = item + 8 * d
        val r = ((y - gridTop) / rowStep).toInt()
        val cellTop = gridTop + r * rowStep
        var cellMid = x
        for (s in sections) {
            val cx = x + scrollX
            if (cx >= s.itemsX - 4 * d && cx <= s.endX + 4 * d) {
                val col = ((cx - s.itemsX + 4 * d) / colStep).toInt().coerceIn(0, s.cols - 1)
                cellMid = s.itemsX + col * colStep + item / 2 - scrollX
                break
            }
        }
        val w = variants.size * 36 * d
        popupX = (cellMid - w / 2).coerceIn(4 * d, maxOf(4 * d, width - w - 4 * d))
        popupY = maxOf(cellTop - 44 * d - 6 * d, 2 * d)
        popup = variants
        // Ngón đang giữ KHÔNG chọn biến thể lúc nhấc (như iOS): phải chạm lại.
        gridPtr = -1
        velocity?.recycle(); velocity = null
        host.invalidate()
    }

    private fun dismissPopup() {
        if (popup != null) { popup = null; host.invalidate() }
    }

    fun onHidden() {
        host.removeCallbacks(holdRun); host.removeCallbacks(delStartRun); host.removeCallbacks(delTickRun)
        host.removeCallbacks(animRun)
        scroller.forceFinished(true)
        velocity?.recycle(); velocity = null
        gridPtr = -1; delPtr = -1; iconPtr = -1; popupPtr = -1
        popup = null
    }

    companion object {
        private const val HEADER_BAND = 14f
    }
}
