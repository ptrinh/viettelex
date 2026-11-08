package com.viettelex.keyboard

import java.text.Normalizer
import java.util.Calendar
import java.util.GregorianCalendar
import kotlin.math.PI
import kotlin.math.floor
import kotlin.math.sin

/**
 * Ngày âm lịch Việt Nam (UTC+7, KHÔNG phải UTC+8) + chip "âm lịch" trên thanh gợi ý — port 1:1
 * iOS LunarDate.swift (cùng bộ ca LunarDateTests). Thuật toán thiên văn công khai: điểm sóc theo số
 * ngày Julius, kinh độ mặt trời để tìm tháng 11 âm và tháng nhuận.
 *
 * Chip: gõ "âm lịch" / "ngày âm" / "ÂL" rồi cách ⇒ chip "30/9 năm Bính Ngọ" (tháng nhuận
 * "30/9 nhuận năm Bính Ngọ"); chạm = thay cụm vừa gõ bằng chữ đó + " ". Mỗi phím chỉ so chuỗi từ
 * vừa chốt ([mayTrigger]); ngày âm chỉ tính khi khớp, cache theo ngày.
 */
object LunarDate {
    data class Lunar(val day: Int, val month: Int, val year: Int, val leap: Boolean)

    const val TIME_ZONE = 7.0

    fun jdFromDate(dd: Int, mm: Int, yy: Int): Int {
        val a = (14 - mm) / 12
        val y = yy + 4800 - a
        val m = mm + 12 * a - 3
        return dd + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
    }

    fun newMoon(kk: Int): Double {
        val k = kk.toDouble()
        val t = k / 1236.85; val t2 = t * t; val t3 = t2 * t
        val dr = PI / 180
        var jd1 = 2415020.75933 + 29.53058868 * k + 0.0001178 * t2 - 0.000000155 * t3
        jd1 += 0.00033 * sin((166.56 + 132.87 * t - 0.009173 * t2) * dr)
        val m = 359.2242 + 29.10535608 * k - 0.0000333 * t2 - 0.00000347 * t3
        val mpr = 306.0253 + 385.81691806 * k + 0.0107306 * t2 + 0.00001236 * t3
        val f = 21.2964 + 390.67050646 * k - 0.0016528 * t2 - 0.00000239 * t3
        var c1 = (0.1734 - 0.000393 * t) * sin(m * dr) + 0.0021 * sin(2 * dr * m)
        c1 = c1 - 0.4068 * sin(mpr * dr) + 0.0161 * sin(dr * 2 * mpr)
        c1 = c1 - 0.0004 * sin(dr * 3 * mpr)
        c1 = c1 + 0.0104 * sin(dr * 2 * f) - 0.0051 * sin(dr * (m + mpr))
        c1 = c1 - 0.0074 * sin(dr * (m - mpr)) + 0.0004 * sin(dr * (2 * f + m))
        c1 = c1 - 0.0004 * sin(dr * (2 * f - m)) - 0.0006 * sin(dr * (2 * f + mpr))
        c1 = c1 + 0.0010 * sin(dr * (2 * f - mpr)) + 0.0005 * sin(dr * (2 * mpr + m))
        val deltat = if (t < -11) 0.001 + 0.000839 * t + 0.0002261 * t2 - 0.00000845 * t3 - 0.000000081 * t * t3
        else -0.000278 + 0.000265 * t + 0.000262 * t2
        return jd1 + c1 - deltat
    }

    fun sunLongitude(jdn: Double): Double {
        val t = (jdn - 2451545.0) / 36525; val t2 = t * t
        val dr = PI / 180
        val m = 357.52910 + 35999.05030 * t - 0.0001559 * t2 - 0.00000048 * t * t2
        val l0 = 280.46645 + 36000.76983 * t + 0.0003032 * t2
        var dl = (1.914600 - 0.004817 * t - 0.000014 * t2) * sin(dr * m)
        dl += (0.019993 - 0.000101 * t) * sin(dr * 2 * m) + 0.000290 * sin(dr * 3 * m)
        var l = (l0 + dl) * dr
        l -= PI * 2 * floor(l / (PI * 2))
        return l
    }

    fun newMoonDay(k: Int, tz: Double = TIME_ZONE): Int = floor(newMoon(k) + 0.5 + tz / 24).toInt()

    fun sunSector(dayNumber: Int, tz: Double = TIME_ZONE): Int =
        floor(sunLongitude(dayNumber - 0.5 - tz / 24) / PI * 6).toInt()

    fun lunarMonth11(yy: Int, tz: Double = TIME_ZONE): Int {
        val off = (jdFromDate(31, 12, yy) - 2415021).toDouble()
        val k = floor(off / 29.530588853).toInt()
        val nm = newMoonDay(k, tz)
        return if (sunSector(nm, tz) >= 9) newMoonDay(k - 1, tz) else nm
    }

    fun leapMonthOffset(a11: Int, tz: Double = TIME_ZONE): Int {
        val k = floor((a11 - 2415021.076998695) / 29.530588853 + 0.5).toInt()
        var i = 1
        var arc = sunSector(newMoonDay(k + i, tz), tz)
        var last: Int
        do {
            last = arc
            i++
            arc = sunSector(newMoonDay(k + i, tz), tz)
        } while (arc != last && i < 14)
        return i - 1
    }

    /** Dương lịch (d, m, y) → âm lịch Việt Nam. */
    fun lunar(dd: Int, mm: Int, yy: Int, tz: Double = TIME_ZONE): Lunar {
        val dayNumber = jdFromDate(dd, mm, yy)
        val k = floor((dayNumber - 2415021.076998695) / 29.530588853).toInt()
        var monthStart = newMoonDay(k + 1, tz)
        if (monthStart > dayNumber) monthStart = newMoonDay(k, tz)
        var a11 = lunarMonth11(yy, tz)
        var b11 = a11
        var lunarYear: Int
        if (a11 >= monthStart) {
            lunarYear = yy
            a11 = lunarMonth11(yy - 1, tz)
        } else {
            lunarYear = yy + 1
            b11 = lunarMonth11(yy + 1, tz)
        }
        val lunarDay = dayNumber - monthStart + 1
        val diff = (monthStart - a11) / 29
        var leap = false
        var lunarMonth = diff + 11
        if (b11 - a11 > 365) {
            val leapDiff = leapMonthOffset(a11, tz)
            if (diff >= leapDiff) {
                lunarMonth = diff + 10
                if (diff == leapDiff) leap = true
            }
        }
        if (lunarMonth > 12) lunarMonth -= 12
        if (lunarMonth >= 11 && diff < 4) lunarYear -= 1
        return Lunar(lunarDay, lunarMonth, lunarYear, leap)
    }

    private val CAN = arrayOf("Canh", "Tân", "Nhâm", "Quý", "Giáp", "Ất", "Bính", "Đinh", "Mậu", "Kỷ")
    private val CHI = arrayOf("Thân", "Dậu", "Tuất", "Hợi", "Tý", "Sửu", "Dần", "Mão", "Thìn", "Tỵ", "Ngọ", "Mùi")

    /** Tên năm âm lịch ("Bính Ngọ" cho 2026). */
    fun yearName(lunarYear: Int): String = "${CAN[Math.floorMod(lunarYear, 10)]} ${CHI[Math.floorMod(lunarYear, 12)]}"

    /** "30/9 năm Bính Ngọ" · tháng nhuận "30/9 nhuận năm Bính Ngọ". */
    fun label(l: Lunar): String = "${l.day}/${l.month}${if (l.leap) " nhuận" else ""} năm ${yearName(l.year)}"

    // MARK: chip "âm lịch"

    private fun norm(s: CharSequence): String = Normalizer.normalize(s, Normalizer.Form.NFC).lowercase()

    /** Lọc rẻ theo từ vừa chốt (mỗi lượt gợi ý lúc không gõ dở): chỉ so chuỗi. */
    fun mayTrigger(lastWord: String?): Boolean {
        val w = lastWord ?: return false
        if (w.length > 8) return false
        return when (norm(w)) { "lịch", "âm", "âl" -> true; else -> false }
    }

    /**
     * Cụm kích hoạt ở cuối [before] (bỏ tối đa một dấu cách cuối) ⇒ đuôi cần thay (giữ nguyên chữ
     * đã gõ, kèm dấu cách cuối nếu có); không khớp ⇒ null.
     */
    fun triggerTail(before: String): String? {
        var end = before.length
        if (end > 0 && before[end - 1] == ' ') end--
        if (end == 0) return null
        val i1 = (end - 1 downTo 0).firstOrNull { before[it].isWhitespace() } ?: -1
        val t1 = before.substring(i1 + 1, end)
        if (t1.length > 8) return null
        val w1 = norm(t1)
        var start = i1 + 1
        if (w1 == "âl") {
            // một từ
        } else if ((w1 == "lịch" || w1 == "âm") && i1 >= 0 && before[i1] == ' ') {
            val i0 = (i1 - 1 downTo 0).firstOrNull { before[it].isWhitespace() } ?: -1
            val w0 = norm(before.substring(i0 + 1, i1))
            if (!((w1 == "lịch" && w0 == "âm") || (w1 == "âm" && w0 == "ngày"))) return null
            start = i0 + 1
        } else {
            return null
        }
        return before.substring(start)
    }

    /** Chip cho [before] vào ngày dương [y]/[m]/[d] (lịch máy). */
    fun chip(before: String, y: Int, m: Int, d: Int): NumberChip? {
        val tail = triggerTail(before) ?: return null
        val text = cachedLabel(y, m, d)
        return NumberChip(display = text, replace = tail, insert = "$text ")
    }

    /** Chip theo ngày hôm nay của máy. */
    fun chip(before: String): NumberChip? {
        val c = GregorianCalendar()
        return chip(before, c.get(Calendar.YEAR), c.get(Calendar.MONTH) + 1, c.get(Calendar.DAY_OF_MONTH))
    }

    @Volatile private var cache: Pair<Int, String>? = null

    private fun cachedLabel(y: Int, m: Int, d: Int): String {
        val key = y * 10_000 + m * 100 + d
        cache?.let { if (it.first == key) return it.second }
        val text = label(lunar(d, m, y))
        cache = key to text
        return text
    }
}
