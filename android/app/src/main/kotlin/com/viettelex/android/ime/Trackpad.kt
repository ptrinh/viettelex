package com.viettelex.android.ime

import java.text.BreakIterator
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Giữ phím cách = trackpad. Máy trạng thái THUẦN (không Android API): nhận toạ độ ngón
 * (đơn vị dp — KeyboardView chia density trước) + thời gian, trả bước di con trỏ.
 * Cùng thuật toán/ngưỡng với iOS `TrackpadGesture` (iOS/Keyboard/Trackpad.swift).
 *
 * - Ngang: mỗi [H_STEP] dp = 1 ký tự (cảm giác stock ~9pt).
 * - Dọc: mỗi [V_STEP] dp = 1 dòng.
 * - Hai trục ĐỘC LẬP như stock (kéo chéo đi cả hai), lọc theo HƯỚNG kéo: hướng = EMA
 *   véc-tơ dời ([DIR_ALPHA]/sự kiện). Hướng gần ngang (|dy| < [OFF_AXIS]·|dx|, ~22°) ⇒
 *   bỏ dy — kéo ngang hơi chéo không nhảy dòng; gần dọc ⇒ bỏ dx — rung ngang khi kéo dọc
 *   không dời ký tự; ở giữa (kéo chéo) ⇒ cộng cả hai. Một sự kiện đủ ngưỡng cả hai trục
 *   ⇒ phát trục vượt ngưỡng nhiều hơn, trục kia giữ tích luỹ, phát ở sự kiện sau.
 *   (Bản cũ khoá trục: mỗi bước ngang xoá dy tích luỹ ⇒ kéo chéo / kéo dọc hơi lệch gần
 *   như không bao giờ lên xuống dòng.)
 * - Tăng tốc: tốc độ (EMA, dp/s) theo trục của bước; ≤ slow ⇒ ×1 (chính xác từng ký
 *   tự/dòng), ≥ fast ⇒ ×max, giữa nội suy tuyến tính. Xem [accelerate].
 *
 * Pinned by TrackpadTest.
 */
class TrackpadGesture {
    enum class Axis { H, V }
    /** [count] có dấu: ngang âm = trái; dọc âm = lên. */
    data class Step(val axis: Axis, val count: Int)

    private var accX = 0f
    private var accY = 0f
    private var dirX = 0.0
    private var dirY = 0.0
    private var lastX = 0f
    private var lastY = 0f
    private var lastT = 0L
    private var speedX = 0.0
    private var speedY = 0.0

    fun begin(x: Float, y: Float, tMs: Long) {
        accX = 0f; accY = 0f; dirX = 0.0; dirY = 0.0
        lastX = x; lastY = y; lastT = tMs
        speedX = 0.0; speedY = 0.0
    }

    fun move(x: Float, y: Float, tMs: Long): Step? {
        val dx = x - lastX
        val dy = y - lastY
        val dtRaw = (tMs - lastT) / 1000.0
        lastX = x; lastY = y; lastT = tMs
        if (dx == 0f && dy == 0f) return null
        // Nghỉ lâu ⇒ tốc độ bắt đầu lại (không mang đà cũ); dt tối thiểu chống chia ~0.
        val dt = maxOf(dtRaw, MIN_DT)
        val ix = abs(dx) / dt
        val iy = abs(dy) / dt
        if (dtRaw > PAUSE_S) { speedX = ix; speedY = iy }
        else { speedX = EMA * ix + (1 - EMA) * speedX; speedY = EMA * iy + (1 - EMA) * speedY }
        dirX = DIR_ALPHA * dx + (1 - DIR_ALPHA) * dirX
        dirY = DIR_ALPHA * dy + (1 - DIR_ALPHA) * dirY
        val hx = abs(dirX); val hy = abs(dirY)
        if (hy >= OFF_AXIS * hx) accY += dy            // không gần-ngang ⇒ tính dọc
        if (hx >= OFF_AXIS * hy) accX += dx            // không gần-dọc ⇒ tính ngang
        val rx = abs(accX) / H_STEP; val ry = abs(accY) / V_STEP
        if (rx < 1f && ry < 1f) return null
        return if (ry >= rx) emitV() else emitH()
    }

    private fun emitH(): Step {
        val units = (accX / H_STEP).toInt()
        accX -= units * H_STEP
        return Step(Axis.H, accelerate(units, speedX, H_SLOW, H_FAST, H_MAX))
    }

    private fun emitV(): Step {
        val lines = (accY / V_STEP).toInt()
        accY -= lines * V_STEP
        return Step(Axis.V, accelerate(lines, speedY, V_SLOW, V_FAST, V_MAX))
    }

    companion object {
        const val H_STEP = 9f
        const val V_STEP = 24f
        /** Tỉ lệ trục phụ / trục chính (theo hướng kéo) dưới ngưỡng này ⇒ bỏ trục phụ. */
        const val OFF_AXIS = 0.4
        /** Trọng số sự kiện mới trong EMA hướng kéo. */
        const val DIR_ALPHA = 0.3
        /** Ngang: ≤300 dp/s ×1, ≥1500 dp/s ×5. */
        const val H_SLOW = 300.0
        const val H_FAST = 1500.0
        const val H_MAX = 5.0
        /** Dọc: ≤200 dp/s ×1, ≥1000 dp/s ×3. */
        const val V_SLOW = 200.0
        const val V_FAST = 1000.0
        const val V_MAX = 3.0
        const val EMA = 0.5
        const val MIN_DT = 1.0 / 240
        const val PAUSE_S = 0.1

        /** [units] bước thô ⇒ bước đã tăng tốc theo [speed]. Chậm ⇒ nguyên [units]. */
        fun accelerate(units: Int, speed: Double, slow: Double, fast: Double, max: Double): Int {
            if (units == 0) return 0
            val f = when {
                speed <= slow -> 1.0
                speed >= fast -> max
                else -> 1.0 + (max - 1.0) * (speed - slow) / (fast - slow)
            }
            val n = maxOf(1, (abs(units) * f).roundToInt())
            return if (units < 0) -n else n
        }
    }
}

/**
 * Gom bước trackpad theo FRAME (Choreographer): cộng dồn các bước cùng trục, ≤ 1 lệnh dời
 * con trỏ (IPC) mỗi frame. Đổi trục giữa frame ⇒ [add] trả bước trục cũ để phát NGAY
 * (giữ đúng thứ tự ngang/dọc). THUẦN — pinned by TrackpadTest.
 */
class TrackpadBatcher {
    private var axis = TrackpadGesture.Axis.H
    private var count = 0
    val hasPending get() = count != 0

    /** Thêm bước; != null ⇒ bước cũ khác trục, phát ngay trước khi gom tiếp. */
    fun add(step: TrackpadGesture.Step): TrackpadGesture.Step? {
        if (step.count == 0) return null
        var out: TrackpadGesture.Step? = null
        if (count != 0 && step.axis != axis) { out = TrackpadGesture.Step(axis, count); count = 0 }
        axis = step.axis
        count += step.count
        return out
    }

    /** Frame tới / nhả tay: bước đã gom (null nếu không có hoặc triệt tiêu nhau). */
    fun drain(): TrackpadGesture.Step? {
        if (count == 0) return null
        val s = TrackpadGesture.Step(axis, count)
        count = 0
        return s
    }

    fun clear() { count = 0 }
}

/**
 * Lên/xuống dòng — tính THUẦN trên văn bản quanh con trỏ.
 *
 * [plan] chọn cách:
 * - TYPE_NULL (terminal): DPAD — app tự hiểu phím (lịch sử lệnh…).
 * - Con trỏ chưa biết (vừa gửi DPAD, chưa có onUpdateSelection): KHÔNG làm gì — văn bản
 *   đọc lúc này còn cũ, không kiểm được biên.
 * - Không đọc được văn bản: lên chỉ khi biết con trỏ > 0 (1 DPAD); xuống: không làm gì
 *   (không biết cuối ô ⇒ DPAD có thể thoát focus).
 * - Ở biên (lên mà trước trống / xuống mà sau trống): không làm gì.
 * - Ô NHIỀU DÒNG: DPAD_UP/DOWN — EditText biết dòng HIỂN THỊ (kể cả tự ngắt) và giữ cột
 *   theo pixel, điều '\n' không làm được. An toàn biên: ArrowKeyMovementMethod
 *   (Selection.moveUp/moveDown) chỉ trả false (⇒ hệ thống dời focus) khi con trỏ ĐÃ ở
 *   offset 0 / cuối. Số phím gửi ≤ max(1, số '\n' thấy được theo hướng đó) ⇒ không bao
 *   giờ bấm quá dòng đầu/cuối (xem chứng minh ở [safeDpadCount]).
 * - Ô một dòng có '\n' (hiếm): setSelection tới cùng cột dòng trên/dưới ([offset]).
 */
object VerticalMove {
    sealed class Plan {
        object None : Plan()
        data class Dpad(val count: Int) : Plan()
        /** Dời con trỏ [units] UTF-16 (âm = lùi). */
        data class Select(val units: Int) : Plan()
    }

    fun plan(before: String?, after: String?, lines: Int, multiLine: Boolean,
             cursor: Int, rawKeys: Boolean): Plan {
        if (lines == 0) return Plan.None
        val k = minOf(abs(lines), MAX_LINES)
        val up = lines < 0
        if (rawKeys) return Plan.Dpad(k)
        if (cursor < 0) return Plan.None
        if (before == null || after == null) {
            return if (up && cursor > 0) Plan.Dpad(1) else Plan.None
        }
        if (up && before.isEmpty()) return Plan.None
        if (!up && after.isEmpty()) return Plan.None
        if (multiLine) return Plan.Dpad(safeDpadCount(if (up) before else after, k))
        val off = offset(before, after, lines) ?: return Plan.None
        return if (off == 0) Plan.None else Plan.Select(off)
    }

    /**
     * Số DPAD tối đa không thoát focus. Bắt đầu KHÔNG ở biên; mỗi '\n' theo hướng đi là
     * ít nhất một dòng hiển thị ⇒ còn ≥ nl dòng. Sau j < nl phím vẫn còn dòng phía trước
     * nên phím kế được tiêu thụ. nl = 0: một phím — dòng đầu mà chưa ở offset 0 thì
     * moveUp đưa về 0 (vẫn tiêu thụ). Không cho nl+1: phím thứ nl có thể đã về đúng 0.
     */
    fun safeDpadCount(textInDirection: String, k: Int): Int =
        minOf(k, maxOf(1, breaks(textInDirection).size))

    /**
     * Dời UTF-16 để lên (lines < 0) / xuống [lines] dòng logic ('\n'), giữ cột tính theo
     * grapheme (ngắn hơn cột ⇒ cuối dòng). Chỉ đi trong phần văn bản thấy được: ít '\n'
     * hơn yêu cầu ⇒ đi hết số có; không có '\n' ⇒ null. Đầu dòng đích không thấy (văn bản
     * trước bị cắt) ⇒ coi đầu [before] là đầu dòng — vẫn đúng dòng, cột có thể lệch.
     */
    fun offset(before: String, after: String, lines: Int): Int? {
        if (lines == 0) return 0
        val bb = breaks(before)
        val curLineStart = bb.lastOrNull()?.second ?: 0
        val col = graphemeCount(before.substring(curLineStart))
        if (lines < 0) {
            if (bb.isEmpty()) return null
            val k = minOf(-lines, bb.size)
            // Dòng đích: từ sau break thứ k (tính từ cuối) tới break đó.
            val targetEnd = bb[bb.size - k].first
            val targetStart = if (bb.size - k - 1 >= 0) bb[bb.size - k - 1].second else 0
            val pos = targetStart + graphemeUnits(before.substring(targetStart, targetEnd), col)
            return pos - before.length
        } else {
            val ab = breaks(after)
            if (ab.isEmpty()) return null
            val k = minOf(lines, ab.size)
            val targetStart = ab[k - 1].second
            val targetEnd = if (k < ab.size) ab[k].first else after.length
            return targetStart + graphemeUnits(after.substring(targetStart, targetEnd), col)
        }
    }

    /** Các ngắt dòng [start, end) theo UTF-16: \n, \r, \r\n (một ngắt), U+2028, U+2029. */
    fun breaks(s: String): List<Pair<Int, Int>> {
        val out = ArrayList<Pair<Int, Int>>()
        var i = 0
        while (i < s.length) {
            when (s[i]) {
                '\r' -> { val e = if (i + 1 < s.length && s[i + 1] == '\n') i + 2 else i + 1; out.add(i to e); i = e }
                '\n', ' ', ' ' -> { out.add(i to i + 1); i++ }
                else -> i++
            }
        }
        return out
    }

    fun graphemeCount(s: String): Int {
        if (s.isEmpty()) return 0
        val bi = BreakIterator.getCharacterInstance(); bi.setText(s)
        var n = 0
        while (bi.next() != BreakIterator.DONE) n++
        return n
    }

    /** UTF-16 của [n] grapheme đầu [s] (ít hơn ⇒ cả chuỗi). */
    fun graphemeUnits(s: String, n: Int): Int = Graphemes.unitsForward(s, n)

    const val MAX_LINES = 8
}
