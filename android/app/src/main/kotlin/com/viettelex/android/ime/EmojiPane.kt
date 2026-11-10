package com.viettelex.android.ime

import android.graphics.Canvas
import android.graphics.Paint
import android.text.TextPaint
import android.view.VelocityTracker
import android.view.ViewConfiguration
import android.widget.OverScroller
import com.viettelex.keyboard.EmojiData
import kotlin.math.abs
import kotlin.math.ceil

/**
 * Plane emoji (port iOS EmojiPlane, spec §10.1) vẽ thẳng trên Canvas của
 * [KeyboardView] — không RecyclerView/ViewGroup. Trên cùng: THANH TÌM EMOJI luôn hiện
 * (ô bo tròn 🔍 "Tìm emoji" như iOS 27 / Gboard — chạm = plane EMOJI_SEARCH). Lưới cuộn
 * NGANG column-major liên tục qua category, KHÔNG tiêu đề nhóm; ô ≥ 44 dp, glyph ~ iOS
 * gốc ([EmojiGridLayout]). Hàng dưới [ABC][🔍][9 icon category][^‿^][⌫]. Chỉ vẽ cột
 * đang thấy. ^‿^ → tab kaomoji / ký tự đặc biệt (cuộn dọc, chạm chèn nguyên văn).
 */
class EmojiPane(
    private val host: KeyboardView,
    private val theme: ImeTheme,
    private val feedback: Feedback,
) {
    private class Section(val name: String, val emoji: List<String>) {
        var itemsX = 0f; var cols = 0; var endX = 0f
    }

    private val d = theme.density
    private var sections: List<Section> = emptyList()
    private var width = 0f
    private var height = 0f
    private var collTop = 0f; private var collH = 0f
    /** Ô lưới (px) + số hàng — [EmojiGridLayout]; gridTop = dưới thanh tìm. */
    private var cellW = 0f; private var cellH = 0f; private var rows = 5
    private var gridTop = 0f
    /** Thanh tìm emoji trên cùng (ẩn ở tab kaomoji). */
    private var barH = 0f
    private var contentW = 0f
    private var scrollX = 0f
    private val scroller = OverScroller(host.context)
    private var velocity: VelocityTracker? = null
    private val touchSlop = ViewConfiguration.get(host.context).scaledTouchSlop
    private val maxFling = ViewConfiguration.get(host.context).scaledMaximumFlingVelocity.toFloat()

    private val emojiPaint = theme.text(30f)
    private var emojiOff = 0f
    private val fieldPaint = theme.fill(theme.keyFill)
    private val hintPaint = theme.text(16f, color = theme.withAlpha(theme.ink, 0.5f), align = Paint.Align.LEFT)
    private val hintOff = theme.centerOffset(hintPaint)
    private val headerPaint = TextPaint(theme.text(11f, color = theme.withAlpha(theme.barInk, 0.5f), bold = true,
        align = Paint.Align.LEFT))
    private val abcPaint = theme.text(15f, color = theme.barInk, medium = true)
    private val abcOff = theme.centerOffset(abcPaint)
    private val iconPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val hiPaint = theme.fill(theme.chip)   // chỉ báo kiểu thanh điều hướng Material
    private val popupPaint = theme.fill(theme.popupFill).apply {
        if (android.os.Build.VERSION.SDK_INT >= 28) setShadowLayer(theme.dp(3f), 0f, theme.dp(1f), 0x4D000000)
    }
    private val tonePaint = theme.text(26f, color = theme.balloonInk)
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

    // --- tab kaomoji ---
    private var kaomoji = false
    private var kaoScrollY = 0f
    private var kaoContentH = 0f
    private class Chip(val text: String, var l: Float, var t: Float, var r: Float, var b: Float)
    private class KaoHeader(val title: String, var y: Float)
    private val chips = ArrayList<Chip>()
    private val kaoHeaders = ArrayList<KaoHeader>()
    private val chipPaint = theme.text(17f)
    private val chipOff = theme.centerOffset(chipPaint)
    private val chipFill = theme.fill(theme.keyFill)
    private val kaoTabPaint = theme.text(12f, bold = true)
    private val kaoTabOff = theme.centerOffset(kaoTabPaint)

    fun open(recents: List<String>) {
        dismissPopup()
        val list = ArrayList<Section>(10)
        if (recents.isNotEmpty()) list += Section(EmojiData.RECENTS, recents)
        for (c in EmojiData.categories) list += Section(c.name, c.emoji)
        sections = list
        scrollX = 0f
        scroller.forceFinished(true)
        pendingIcon = -1
        kaomoji = false; kaoScrollY = 0f
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
        // Cùng cao hàng ô tìm của plane EMOJI_SEARCH ⇒ chạm vào không nhảy vị trí.
        barH = KeyLayout.searchHeaderPx(h)
        gridTop = barH + theme.dp(2f)
        val m = EmojiGridLayout.metrics(w / d, maxOf(rowTop - theme.dp(2f) - gridTop, 0f) / d)
        rows = m.rows; cellW = m.cellW * d; cellH = m.cellH * d
        emojiPaint.textSize = minOf(theme.sp(EmojiGridLayout.MAX_GLYPH), m.glyph * d)
        emojiOff = theme.centerOffset(emojiPaint)
        val abcW = 44 * d; val side = 8 * d; val gap = 2 * d
        iconsLeft = side + abcW + gap
        iconW = (w - 2 * side - 2 * abcW - 2 * gap) / SLOTS
        relayoutSections()
        // Kaomoji: dàn LƯỜI lúc mở tab ^‿^ (lần đầu chạm bảng kaomoji của emoji.bin + đo ~136 chuỗi kéo
        // font dự phòng nguội — không làm trong lượt layout đầu của bàn phím). Tab đang mở ⇒ dàn ngay.
        if (kaomoji) layoutKaomoji() else kaoDirty = true
    }

    /** Bố cục kaomoji ([chips]) lỗi thời — dàn lại ở lần mở tab kế ([ensureKaomoji]). */
    private var kaoDirty = true

    private fun ensureKaomoji() { if (kaoDirty) layoutKaomoji() }

    /** Dàn dòng các viên kaomoji theo bề ngang (toạ độ nội dung, chưa trừ kaoScrollY). */
    private fun layoutKaomoji() {
        chips.clear(); kaoHeaders.clear()
        if (width == 0f) return
        kaoDirty = false
        ImeCost.kaomojiLayouts++
        val side = 8 * d; val gap = 6 * d; val h = 34 * d
        var y = collTop + 2 * d
        for (g in EmojiData.kaomoji) {
            kaoHeaders += KaoHeader(g.name.uppercase(), y - headerPaint.fontMetrics.ascent)
            y += 18 * d
            var x = side
            for (item in g.items) {
                val w = minOf(maxOf(chipPaint.measureText(item) + 20 * d, h), width - 2 * side)
                if (x + w > width - side && x > side) { x = side; y += h + gap }
                chips += Chip(item, x, y, x + w, y + h)
                x += w + gap
            }
            y += h + 12 * d
        }
        kaoContentH = y
        kaoScrollY = kaoScrollY.coerceIn(0f, maxKaoScroll())
    }

    private fun maxKaoScroll() = maxOf(0f, kaoContentH - (rowTop - theme.dp(1f)))

    /** Test hook: các mục kaomoji theo thứ tự hiển thị. */
    internal val kaomojiItems: List<String> get() { ensureKaomoji(); return chips.map { it.text } }

    private fun relayoutSections() {
        if (width == 0f) return
        // Ô đều nhau, section nối tiếp (mỗi section bắt đầu cột mới), không tiêu đề.
        var x = 0f
        for (s in sections) {
            s.itemsX = x
            s.cols = maxOf(ceil(s.emoji.size / rows.toDouble()).toInt(), 1)
            x += s.cols * cellW
            s.endX = x
        }
        contentW = x
        scrollX = scrollX.coerceIn(0f, maxScroll())
    }

    private fun maxScroll() = maxOf(0f, contentW - width)

    // MARK: vẽ

    fun draw(c: Canvas) {
        if (kaomoji) { drawKaomoji(c); drawCategoryRow(c); return }
        val w = width
        drawSearchBar(c)
        c.save()
        c.clipRect(0f, gridTop - theme.dp(2f), w, rowTop - theme.dp(1f))
        val secs = sections
        val n = rows
        for (si in secs.indices) {
            val s = secs[si]
            if (s.endX < scrollX || s.itemsX > scrollX + w) continue
            var col = maxOf(0, ((scrollX - s.itemsX) / cellW).toInt())
            while (col < s.cols) {
                val x0 = s.itemsX + col * cellW - scrollX
                if (x0 > w) break
                val cx = x0 + cellW / 2
                for (r in 0 until n) {
                    val idx = col * n + r
                    if (idx >= s.emoji.size) break
                    c.drawText(s.emoji[idx], cx, gridTop + r * cellH + cellH / 2 + emojiOff, emojiPaint)
                }
                col++
            }
        }
        c.restore()
        drawCategoryRow(c)
        popup?.let { drawPopup(c, it) }
    }

    /** Ô tìm bo tròn kiểu iOS 27 / Gboard: 🔍 + "Tìm emoji" (chạm = plane tìm). */
    private fun drawSearchBar(c: Canvas) {
        val l = 8 * d; val r = width - 8 * d
        val t = 5 * d; val b = barH - 3 * d
        val rad = (b - t) / 2
        val cy = (t + b) / 2
        c.drawRoundRect(l, t, r, b, rad, rad, fieldPaint)
        iconPaint.color = theme.withAlpha(theme.ink, 0.5f)
        ImeIcons.draw(c, ImeIcons.SEARCH, l + 18 * d, cy, 16 * d, iconPaint)
        c.drawText(EmojiSearchBar.HINT, l + 34 * d, cy + hintOff, hintPaint)
    }

    private fun drawKaomoji(c: Canvas) {
        c.save()
        c.clipRect(0f, 0f, width, rowTop - theme.dp(1f))
        for (h in kaoHeaders) c.drawText(h.title, 10 * d, h.y - kaoScrollY, headerPaint)
        val r = 8 * d
        for (ch in chips) {
            val t = ch.t - kaoScrollY
            if (t > rowTop || ch.b - kaoScrollY < 0) continue
            c.drawRoundRect(ch.l, t, ch.r, ch.b - kaoScrollY, r, r, chipFill)
            c.drawText(ch.text, (ch.l + ch.r) / 2, (t + ch.b - kaoScrollY) / 2 + chipOff, chipPaint)
        }
        c.restore()
    }

    private fun drawCategoryRow(c: Canvas) {
        val cy = (rowTop + rowBottom) / 2
        c.drawText("ABC", 8 * d + 22 * d, cy + abcOff, abcPaint)
        // slot 0 = 🔍, 1…9 = category, 10 = kaomoji
        iconPaint.color = theme.withAlpha(theme.barInk, 0.55f)
        ImeIcons.draw(c, ImeIcons.SEARCH, iconsLeft + 0.5f * iconW, cy, 18f * d, iconPaint)
        val kx = iconsLeft + (SLOTS - 0.5f) * iconW
        if (kaomoji) { val hw = minOf(iconW / 2 - d, 16 * d); c.drawRoundRect(kx - hw, cy - 13 * d, kx + hw, cy + 13 * d, 13 * d, 13 * d, hiPaint) }
        kaoTabPaint.color = if (kaomoji) theme.barInk else theme.withAlpha(theme.barInk, 0.55f)
        c.drawText("^‿^", kx, cy + kaoTabOff, kaoTabPaint)
        for (i in 0 until 9) {
            val cx = iconsLeft + (i + 1.5f) * iconW
            val on = i == highlighted && !kaomoji
            if (on) { val hw = minOf(iconW / 2 - d, 16 * d); c.drawRoundRect(cx - hw, cy - 13 * d, cx + hw, cy + 13 * d, 13 * d, 13 * d, hiPaint) }
            iconPaint.color = if (on) theme.barInk else theme.withAlpha(theme.barInk, 0.55f)
            ImeIcons.draw(c, ImeIcons.CATEGORY[i], cx, cy, 19.5f * d, iconPaint)
        }
        iconPaint.color = theme.barInk
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
        kaomoji = false
        val s = sectionIndex(icon) ?: return
        if (sections[s].emoji.isEmpty()) return
        pendingIcon = icon
        val target = sections[s].itemsX.coerceIn(0f, maxScroll())
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
        if (kaomoji) {
            if (scroller.computeScrollOffset()) {
                kaoScrollY = scroller.currY.toFloat().coerceIn(0f, maxKaoScroll())
                host.postInvalidateOnAnimation()
            }
            return
        }
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
                x >= iconsLeft && x < iconsLeft + iconW -> { feedback.click(Feedback.MODIFIER, host); host.paneSearch() }
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
        if (!kaomoji && y < barH) {   // thanh tìm emoji
            feedback.click(Feedback.MODIFIER, host); host.paneSearch(); return
        }
        if (gridPtr >= 0) return    // một ngón cuộn/tap lưới
        gridPtr = pid
        dragging = false
        downX = x; downY = y; lastTouchX = x; lastTouchY = y
        scroller.forceFinished(true)
        velocity?.recycle()
        velocity = VelocityTracker.obtain()
        host.removeCallbacks(holdRun)
        if (!kaomoji) host.postDelayed(holdRun, 350)
    }

    /** KeyboardView chuyển MotionEvent thật cho VelocityTracker (không tổng hợp event). */
    fun track(e: android.view.MotionEvent) { if (gridPtr >= 0) velocity?.addMovement(e) }

    private var lastTouchY = 0f

    fun move(pid: Int, x: Float, y: Float) {
        if (pid != gridPtr) return
        if (kaomoji) {
            if (!dragging && abs(y - downY) > touchSlop) { dragging = true; lastTouchY = y }
            if (dragging) {
                val ny = (kaoScrollY + (lastTouchY - y)).coerceIn(0f, maxKaoScroll())
                lastTouchY = y
                if (ny != kaoScrollY) { kaoScrollY = ny; host.invalidate() }
            }
            return
        }
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
                val slot = ((x - iconsLeft) / iconW).toInt()
                if (!cancelled && y >= rowTop - 8 * d && x >= iconsLeft && slot in 1 until SLOTS) {
                    if (slot == SLOTS - 1) showKaomoji() else jumpToCategory(slot - 1)
                }
                return
            }
            gridPtr -> {
                gridPtr = -1
                host.removeCallbacks(holdRun)
                val v = velocity
                if (kaomoji) {
                    if (dragging && v != null) {
                        v.computeCurrentVelocity(1000, maxFling)
                        scroller.fling(0, kaoScrollY.toInt(), 0, -v.getYVelocity(pid).toInt(), 0, 0, 0, maxKaoScroll().toInt())
                        host.postInvalidateOnAnimation()
                    } else if (!cancelled && !dragging) {
                        kaomojiAt(downX, downY)?.let { s ->
                            feedback.click(Feedback.LETTER, host)
                            host.paneKaomoji(s)
                        }
                    }
                    velocity?.recycle(); velocity = null
                    dragging = false
                    return
                }
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
            list += Section(EmojiData.RECENTS, listOf(e))
            list.addAll(sections)
            sections = list
            relayoutSections()
            scrollX = keep.coerceIn(0f, maxScroll())
            highlighted = iconIndex(sectionOnScreen())
        }
        host.invalidate()
    }

    private fun showKaomoji() {
        kaomoji = true
        ensureKaomoji()
        scroller.forceFinished(true)
        dismissPopup()
        host.invalidate()
    }

    /** Kaomoji tại điểm chạm (toạ độ view) — internal cho test. */
    internal fun kaomojiAt(x: Float, y: Float): String? {
        if (y >= rowTop - 2 * d) return null
        ensureKaomoji()
        val cy = y + kaoScrollY
        return chips.firstOrNull { x >= it.l && x < it.r && cy >= it.t && cy < it.b }?.text
    }

    private fun emojiAt(x: Float, y: Float): String? {
        if (y < gridTop - 2 * d) return null
        val r = ((y - gridTop) / cellH).toInt().coerceAtMost(rows - 1)
        if (r < 0) return null
        val cx = x + scrollX
        for (s in sections) {
            if (cx < s.itemsX || cx >= s.endX) continue
            val col = ((cx - s.itemsX) / cellW).toInt().coerceIn(0, s.cols - 1)
            return s.emoji.getOrNull(col * rows + r)
        }
        return null
    }

    private fun showTonePopupAt(x: Float, y: Float) {
        if (dragging) return
        val e = emojiAt(x, y) ?: return
        val variants = EmojiData.toneVariants(e) ?: return
        feedback.click(Feedback.MODIFIER, host)
        // ô chứa điểm chạm
        val r = ((y - gridTop) / cellH).toInt().coerceIn(0, rows - 1)
        val cellTop = gridTop + r * cellH
        var cellMid = x
        for (s in sections) {
            val cx = x + scrollX
            if (cx >= s.itemsX && cx < s.endX) {
                val col = ((cx - s.itemsX) / cellW).toInt().coerceIn(0, s.cols - 1)
                cellMid = s.itemsX + col * cellW + cellW / 2 - scrollX
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

    /** Bàn phím ẩn lâu: bỏ danh sách emoji (String theo category) — [open] dựng lại. */
    fun releaseData() { sections = emptyList(); chips.clear(); kaoHeaders.clear(); kaoDirty = true }

    fun onHidden() {
        host.removeCallbacks(holdRun); host.removeCallbacks(delStartRun); host.removeCallbacks(delTickRun)
        host.removeCallbacks(animRun)
        scroller.forceFinished(true)
        velocity?.recycle(); velocity = null
        gridPtr = -1; delPtr = -1; iconPtr = -1; popupPtr = -1
        popup = null
    }

    companion object {
        /** Hàng dưới giữa ABC và ⌫: 🔍 + 9 category + kaomoji. */
        private const val SLOTS = 11
    }
}
