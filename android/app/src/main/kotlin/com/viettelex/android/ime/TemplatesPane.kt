package com.viettelex.android.ime

import android.graphics.Canvas
import android.text.TextPaint
import android.text.TextUtils
import android.view.MotionEvent
import android.view.VelocityTracker
import android.view.ViewConfiguration
import android.widget.OverScroller
import com.viettelex.keyboard.TemplateItem
import kotlin.math.abs

/**
 * Plane mẫu câu (☰, spec §10.2): bubble chip kiểu tag cloud, cuộn dọc, vẽ trên Canvas
 * của [KeyboardView]. Có label ⇒ chỉ hiện label, không thì text cắt "…" (≤150 dp);
 * bubble ⚙️ cuối mở tab Mẫu Câu. Hàng đáy do KeyboardView vẽ (plane TEMPLATES).
 * Dàn dòng như UICollectionViewFlowLayout: dòng ≥2 chip dàn đều (justified), dòng 1
 * chip canh giữa.
 */
class TemplatesPane(
    private val host: KeyboardView,
    private val theme: ImeTheme,
    private val feedback: Feedback,
) {
    private class Chip(val item: TemplateItem?, val shown: String) {
        var l = 0f; var t = 0f; var r = 0f; var b = 0f
    }

    private val d = theme.density
    private var items: List<TemplateItem> = emptyList()
    private var chips: List<Chip> = emptyList()
    private var width = 0f
    private var bottom = 0f
    private var contentH = 0f
    private var scrollY = 0f
    private val scroller = OverScroller(host.context)
    private var velocity: VelocityTracker? = null
    private val touchSlop = ViewConfiguration.get(host.context).scaledTouchSlop
    private val maxFling = ViewConfiguration.get(host.context).scaledMaximumFlingVelocity.toFloat()

    private val textPaint = TextPaint(theme.text(16f))
    private val textOff = theme.centerOffset(textPaint)
    private val chipPaint = theme.fill(theme.keyFill)

    private var ptr = -1
    private var dragging = false
    private var downX = 0f; private var downY = 0f; private var lastY = 0f

    fun setItems(list: List<TemplateItem>) {
        if (list == items) return
        items = list
        width = 0f   // ép dàn lại ở layout kế
    }

    fun resetScroll() { scrollY = 0f; scroller.forceFinished(true) }

    fun contains(x: Float, y: Float) = y < bottom

    fun layout(w: Float, paneBottom: Float) {
        if (w == width && paneBottom == bottom && chips.isNotEmpty()) return
        width = w; bottom = paneBottom
        val maxLabel = 150 * d
        val padH = 12 * d; val padV = 7 * d
        val fm = textPaint.fontMetrics
        val lineH = fm.descent - fm.ascent
        val chipH = padV * 2 + lineH
        val list = ArrayList<Chip>(items.size + 1)
        for (it in items) {
            val s = if (it.label.isEmpty()) it.text else it.label
            val oneLine = s.replace('\n', ' ')
            list += Chip(it, TextUtils.ellipsize(oneLine, textPaint, maxLabel, TextUtils.TruncateAt.END).toString())
        }
        list += Chip(null, "⚙️")
        // flow layout: inset 8/6, khoảng cách chip 6, dòng 8
        val left = 6 * d; val right = w - 6 * d
        var y = 8 * d
        var i = 0
        while (i < list.size) {
            var j = i
            var used = 0f
            while (j < list.size) {
                val cw = textPaint.measureText(list[j].shown) + 2 * padH
                val need = if (j == i) cw else used + 6 * d + cw
                if (j > i && need > right - left) break
                used = need
                list[j].r = cw          // tạm giữ bề rộng
                j++
            }
            val n = j - i
            val totalW = (i until j).sumOf { list[it].r.toDouble() }.toFloat()
            if (n == 1) {
                val cw = minOf(list[i].r, right - left)
                val x0 = left + (right - left - cw) / 2
                list[i].apply { l = x0; r = x0 + cw; t = y; b = y + chipH }
            } else {
                val gap = (right - left - totalW) / (n - 1)
                var x = left
                for (k in i until j) {
                    val cw = list[k].r
                    list[k].apply { l = x; r = x + cw; t = y; b = y + chipH }
                    x += cw + gap
                }
            }
            y += chipH + 8 * d
            i = j
        }
        chips = list
        contentH = y - 8 * d + 8 * d
        scrollY = scrollY.coerceIn(0f, maxScroll())
    }

    private fun maxScroll() = maxOf(0f, contentH - bottom)

    fun draw(c: Canvas) {
        c.save()
        c.clipRect(0f, 0f, width, bottom)
        val rad = 8 * d; val sd = 0f   // chip Material: bo 8 dp, phẳng
        val list = chips
        for (i in list.indices) {
            val ch = list[i]
            val t = ch.t - scrollY; val b = ch.b - scrollY
            if (b + sd < 0 || t > bottom) continue
            c.drawRoundRect(ch.l, t, ch.r, b, rad, rad, chipPaint)
            c.drawText(ch.shown, (ch.l + ch.r) / 2, (t + b) / 2 + textOff, textPaint)
        }
        c.restore()
    }

    fun track(e: MotionEvent) { if (ptr >= 0) velocity?.addMovement(e) }

    fun down(pid: Int, x: Float, y: Float) {
        if (ptr >= 0) return
        ptr = pid; dragging = false
        downX = x; downY = y; lastY = y
        scroller.forceFinished(true)
        velocity?.recycle(); velocity = VelocityTracker.obtain()
    }

    fun move(pid: Int, x: Float, y: Float) {
        if (pid != ptr) return
        if (!dragging && abs(y - downY) > touchSlop) { dragging = true; lastY = y }
        if (dragging) {
            val ny = (scrollY + (lastY - y)).coerceIn(0f, maxScroll())
            lastY = y
            if (ny != scrollY) { scrollY = ny; host.invalidate() }
        }
    }

    fun up(pid: Int, x: Float, y: Float, cancelled: Boolean) {
        if (pid != ptr) return
        ptr = -1
        val v = velocity
        if (dragging && v != null) {
            v.computeCurrentVelocity(1000, maxFling)
            scroller.fling(0, scrollY.toInt(), 0, (-v.getYVelocity(pid)).toInt(), 0, 0, 0, maxScroll().toInt())
            host.postInvalidateOnAnimation()
        } else if (!cancelled) {
            val cy = downY + scrollY
            val hit = chips.firstOrNull { downX >= it.l - 3 * d && downX < it.r + 3 * d && cy >= it.t - 4 * d && cy < it.b + 4 * d }
            if (hit != null && abs(x - downX) < 24 * d && abs(y - downY) < 24 * d) {
                val item = hit.item
                if (item == null) { feedback.click(Feedback.MODIFIER, host); host.paneGear() }
                else { feedback.click(Feedback.LETTER, host); host.paneTemplate(item) }
            }
        }
        velocity?.recycle(); velocity = null
        dragging = false
    }

    fun computeScroll() {
        if (scroller.computeScrollOffset()) {
            scrollY = scroller.currY.toFloat().coerceIn(0f, maxScroll())
            host.postInvalidateOnAnimation()
        }
    }

    fun onHidden() {
        scroller.forceFinished(true)
        velocity?.recycle(); velocity = null
        ptr = -1
    }
}
