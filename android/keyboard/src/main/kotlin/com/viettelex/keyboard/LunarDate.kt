package com.viettelex.keyboard

import java.text.Normalizer
import java.util.Calendar
import java.util.GregorianCalendar
import kotlin.math.PI
import kotlin.math.floor
import kotlin.math.sin

/**
 * Ngày âm lịch Việt Nam (UTC+7, KHÔNG phải UTC+8) + chip "âm lịch" trên thanh gợi ý — phần chip
 * port 1:1 iOS LunarDate.swift (cùng bộ ca LunarDateTests). Phần tính ngày âm là port Kotlin của
 * App/Sources/LunarCalendar.swift (desktop, iOS dùng trực tiếp): điểm sóc Meeus ch. 49 đầy đủ + ΔT,
 * kinh độ biểu kiến mặt trời ch. 25; tháng 11 âm chứa Đông chí, tháng nhuận = tháng đầu không có
 * trung khí. Fixture chung iOS/KeyboardTests/Fixtures/lunar-month-starts.txt khoá kết quả 1900–2100
 * — sửa công thức thì sửa cả Swift/C++ và sinh lại fixture từ bản Swift.
 *
 * Chip: gõ "âm lịch" / "ngày âm" / "ÂL" rồi cách ⇒ chip "30/9 năm Bính Ngọ" (tháng nhuận
 * "30/9 nhuận năm Bính Ngọ"); chạm = thay cụm vừa gõ bằng chữ đó + " ". Mỗi phím chỉ so chuỗi từ
 * vừa chốt ([mayTrigger]); ngày âm chỉ tính khi khớp, cache theo ngày.
 * "Tết" rồi cách ⇒ chip ngày dương mùng 1 Tết kế tiếp "06/02/2027"; chạm = GIỮ chữ Tết như đã gõ,
 * nối ngày: "Tết " → "Tết 06/02/2027 ".
 */
object LunarDate {
    data class Lunar(val day: Int, val month: Int, val year: Int, val leap: Boolean)

    const val TIME_ZONE = 7.0

    /** Số ngày Julius (lịch Gregory) lúc trưa. */
    fun jdFromDate(dd: Int, mm: Int, yy: Int): Int {
        val a = (14 - mm) / 12
        val y = yy + 4800 - a
        val m = mm + 12 * a - 3
        return dd + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
    }

    private const val DR = PI / 180
    private fun sind(x: Double): Double = sin(x * DR)

    /** Kỳ trăng thứ k (k = 0: sóc 06/01/2000) có sóc ngay trước/ở ngày Julius [jd]. */
    private fun lunationIndex(jd: Double, rounded: Boolean = false): Int {
        val v = (jd - 2451550.09766) / 29.530588861
        return floor(if (rounded) v + 0.5 else v).toInt()
    }

    /** ΔT = TT − UT (ngày), đa thức Espenak–Meeus theo năm. */
    private fun deltaT(jd: Double): Double {
        val y = 2000 + (jd - 2451545.0) / 365.25
        val secs = when {
            y < 1961 -> { val t = y - 1950; 29.07 + 0.407 * t - t * t / 233 + t * t * t / 2547 }
            y < 1986 -> { val t = y - 1975; 45.45 + 1.067 * t - t * t / 260 - t * t * t / 718 }
            y < 2005 -> {
                val t = y - 2000
                63.86 + 0.3345 * t - 0.060374 * t * t + 0.0017275 * t * t * t +
                    0.000651814 * t * t * t * t + 0.00002373599 * t * t * t * t * t
            }
            y < 2050 -> { val t = y - 2000; 62.92 + 0.32217 * t + 0.005589 * t * t }
            y < 2150 -> { val u = (y - 1820) / 100; -20 + 32 * u * u - 0.5628 * (2150 - y) }
            else -> { val u = (y - 1820) / 100; -20 + 32 * u * u }
        }
        return secs / 86400
    }

    private val PLANET_W = doubleArrayOf(325.0, 165.0, 164.0, 126.0, 110.0, 62.0, 60.0, 56.0, 47.0, 42.0, 40.0, 37.0, 35.0, 23.0)

    /** Thời điểm sóc thứ k, ngày Julius UT (phần thập phân). Meeus ch. 49. */
    private fun newMoon(k: Int): Double {
        val kd = k.toDouble()
        val t = kd / 1236.85; val t2 = t * t; val t3 = t2 * t; val t4 = t3 * t
        var jde = 2451550.09766 + 29.530588861 * kd + 0.00015437 * t2 - 0.000000150 * t3 + 0.00000000073 * t4
        val e = 1 - 0.002516 * t - 0.0000074 * t2
        val m = 2.5534 + 29.10535670 * kd - 0.0000014 * t2 - 0.00000011 * t3                        // dị thường MT
        val mp = 201.5643 + 385.81693528 * kd + 0.0107582 * t2 + 0.00001238 * t3 - 0.000000058 * t4  // dị thường trăng
        val f = 160.7108 + 390.67050284 * kd - 0.0016118 * t2 - 0.00000227 * t3 + 0.000000011 * t4   // đối số vĩ độ
        val om = 124.7746 - 1.56375588 * kd + 0.0020672 * t2 + 0.00000215 * t3
        var c = -0.40720 * sind(mp) + 0.17241 * e * sind(m) + 0.01608 * sind(2 * mp) + 0.01039 * sind(2 * f)
        c += 0.00739 * e * sind(mp - m) - 0.00514 * e * sind(mp + m) + 0.00208 * e * e * sind(2 * m)
        c += -0.00111 * sind(mp - 2 * f) - 0.00057 * sind(mp + 2 * f) + 0.00056 * e * sind(2 * mp + m)
        c += -0.00042 * sind(3 * mp) + 0.00042 * e * sind(m + 2 * f) + 0.00038 * e * sind(m - 2 * f)
        c += -0.00024 * e * sind(2 * mp - m) - 0.00017 * sind(om) - 0.00007 * sind(mp + 2 * m)
        c += 0.00004 * sind(2 * mp - 2 * f) + 0.00004 * sind(3 * m) + 0.00003 * sind(mp + m - 2 * f)
        c += 0.00003 * sind(2 * mp + 2 * f) - 0.00003 * sind(mp + m + 2 * f) + 0.00003 * sind(mp - m + 2 * f)
        c += -0.00002 * sind(mp - m - 2 * f) - 0.00002 * sind(3 * mp + m) + 0.00002 * sind(4 * mp)
        // Các số hạng hành tinh.
        val a = doubleArrayOf(
            299.77 + 0.107408 * kd - 0.009173 * t2, 251.88 + 0.016321 * kd, 251.83 + 26.651886 * kd,
            349.42 + 36.412478 * kd, 84.66 + 18.206239 * kd, 141.74 + 53.303771 * kd,
            207.14 + 2.453732 * kd, 154.84 + 7.306860 * kd, 34.52 + 27.261239 * kd,
            207.19 + 0.121824 * kd, 291.34 + 1.844379 * kd, 161.72 + 24.198154 * kd,
            239.56 + 25.513099 * kd, 331.55 + 3.592518 * kd,
        )
        for (i in a.indices) c += PLANET_W[i] * 0.000001 * sind(a[i])
        jde += c
        return jde - deltaT(jde)
    }

    /** Ngày (số ngày Julius) chứa sóc thứ k theo giờ địa phương. */
    private fun newMoonDay(k: Int, tz: Double): Int = floor(newMoon(k) + 0.5 + tz / 24).toInt()

    /** Kinh độ biểu kiến của mặt trời (radian, 0…2π) tại ngày Julius UT [jd]. Meeus ch. 25. */
    private fun sunLongitude(jd: Double): Double {
        val t = (jd + deltaT(jd) - 2451545.0) / 36525; val t2 = t * t
        val l0 = 280.46646 + 36000.76983 * t + 0.0003032 * t2
        val m = 357.52911 + 35999.05029 * t - 0.0001537 * t2
        val c = (1.914602 - 0.004817 * t - 0.000014 * t2) * sind(m) +
            (0.019993 - 0.000101 * t) * sind(2 * m) + 0.000289 * sind(3 * m)
        val om = 125.04 - 1934.136 * t
        val l = (l0 + c - 0.00569 - 0.00478 * sind(om)) * DR
        return l - PI * 2 * floor(l / (PI * 2))
    }

    /** Cung 30° (0…11) của mặt trời lúc bắt đầu ngày [dayNumber] (giờ địa phương). */
    private fun sunSector(dayNumber: Int, tz: Double): Int =
        floor(sunLongitude(dayNumber.toDouble() - 0.5 - tz / 24) / PI * 6).toInt()

    /** Ngày bắt đầu tháng 11 âm (tháng chứa Đông chí) của năm [y]. */
    private fun lunarMonth11(y: Int, tz: Double): Int {
        val dec31 = jdFromDate(31, 12, y)
        var k = lunationIndex(dec31.toDouble())
        var nm = newMoonDay(k, tz)
        if (nm > dec31) { k -= 1; nm = newMoonDay(k, tz) }
        if (sunSector(nm, tz) >= 9) nm = newMoonDay(k - 1, tz)
        return nm
    }

    /** Vị trí tháng nhuận (tính từ tháng 11 bắt đầu ngày [a11]): tháng đầu không có trung khí. */
    private fun leapMonthOffset(a11: Int, tz: Double): Int {
        val k = lunationIndex(a11.toDouble(), rounded = true)
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

    /** Dương lịch (d, m, y) → âm lịch Việt Nam (múi giờ [tz] giờ, mặc định +7). */
    fun lunar(dd: Int, mm: Int, yy: Int, tz: Double = TIME_ZONE): Lunar {
        val dayNumber = jdFromDate(dd, mm, yy)
        val k = lunationIndex(dayNumber.toDouble())
        var monthStart = newMoonDay(k + 1, tz)
        if (monthStart > dayNumber) monthStart = newMoonDay(k, tz)
        if (monthStart > dayNumber) monthStart = newMoonDay(k - 1, tz)
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
        val diff = floor((monthStart - a11).toDouble() / 29).toInt()
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

    /** Ngày Julius của mùng 1 Tết năm âm [lunarYear] (= LunarCalendar.tetDayNumber). */
    fun tetDayNumber(lunarYear: Int, tz: Double = TIME_ZONE): Int {
        val a11 = lunarMonth11(lunarYear - 1, tz)
        var off = 2   // tháng Giêng = 2 tháng sau tháng 11 (3 nếu tháng 11/12 nhuận)
        if (lunarMonth11(lunarYear, tz) - a11 > 365 && off >= leapMonthOffset(a11, tz)) off++
        return newMoonDay(lunationIndex(a11.toDouble(), rounded = true) + off, tz)
    }

    /** Ngày Julius → (năm, tháng, ngày) Gregory. */
    fun gregorian(jd: Int): Triple<Int, Int, Int> {
        val a = jd + 32044; val b = (4 * a + 3) / 146097; val c = a - 146097 * b / 4
        val d = (4 * c + 3) / 1461; val e = c - 1461 * d / 4; val m = (5 * e + 2) / 153
        return Triple(100 * b + d - 4800 + m / 10, m + 3 - 12 * (m / 10), e - (153 * m + 2) / 5 + 1)
    }

    @Volatile private var tetCache: Pair<Int, String>? = null

    /** "06/02/2027" — mùng 1 Tết đầu tiên có ngày dương ≥ [y]/[m]/[d] (đúng mùng 1 ⇒ hôm nay). Cache theo ngày. */
    fun nextTetText(y: Int, m: Int, d: Int): String {
        val today = jdFromDate(d, m, y)
        tetCache?.let { if (it.first == today) return it.second }
        var jd = tetDayNumber(y)
        if (jd < today) jd = tetDayNumber(y + 1)
        val (ty, tm, td) = gregorian(jd)
        fun pad(n: Int, w: Int) = n.toString().padStart(w, '0')   // không theo Locale (chữ số Ả Rập…)
        val text = "${pad(td, 2)}/${pad(tm, 2)}/${pad(ty, 4)}"
        tetCache = today to text
        return text
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
        return when (norm(w)) { "lịch", "âm", "âl", "tết" -> true; else -> false }
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
        if (w1 == "âl" || w1 == "tết") {
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
        val word = tail.removeSuffix(" ")
        if (norm(word) == "tết") {
            val date = nextTetText(y, m, d)
            return NumberChip(display = date, replace = tail, insert = "$word $date ")
        }
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
