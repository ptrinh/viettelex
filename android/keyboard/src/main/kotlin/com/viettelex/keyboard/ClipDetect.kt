package com.viettelex.keyboard

import java.text.Normalizer

/**
 * Chip tách số trên thanh gợi ý khi vừa copy: mã OTP, SĐT Việt Nam, số tài khoản.
 * Hàm thuần — iOS `ClipDetect.swift` port 1:1 (cùng test vector).
 *
 * Luật biên chung cho mọi dãy số: ký tự kề hai đầu KHÔNG là chữ/số, và không là một
 * trong `.,:/` nối sang một chữ số khác ("1,234,567", "12:30", "27/09" bị loại; "STK:123…"
 * hay "…123456." cuối câu vẫn nhận).
 */
data class ClipChip(val kind: Kind, val value: String, val label: String) {
    /** Thứ tự = thứ tự hiện chip mặc định. */
    enum class Kind { OTP, PHONE, ADDRESS, ACCOUNT }
}

object ClipDetect {
    const val MAX_LEN = 500

    private val OTP_KEYWORD = Regex(
        "\\b(otp|ma xac thuc|ma xac nhan|ma kich hoat|ma giao dich|code|verification|passcode)\\b")
    /** "mã" trần: chỉ tính khi có dãy 4–8 số trong [MA_WINDOW] ký tự sau nó. */
    private val MA_WORD = Regex("\\bma\\b")
    private const val MA_WINDOW = 50
    private val ACCOUNT_KEYWORD = Regex("\\b(stk|so tk|so tai khoan|tai khoan|tk|account|acc)\\b|\\ba/c\\b")
    private val MONEY_SUFFIX = Regex("^\\s*(vnd|dong|usd|d|k)(?![\\p{L}\\p{N}])")

    /** [groupEnds]: vị trí kết thúc (exclusive) + số chữ số tích luỹ của từng nhóm. */
    private class Run(val start: Int, val end: Int, val digits: String,
                      val groupEnds: List<Pair<Int, Int>> = emptyList())

    fun detect(text: String): List<ClipChip> {
        if (text.length > MAX_LEN || text.isBlank()) return emptyList()
        val folded = fold(text)
        val trimmed = text.trim()
        val out = ArrayList<ClipChip>(3)
        val taken = ArrayList<IntRange>()

        // --- OTP ---
        var otp: Run? = null
        if (trimmed.length in 4..8 && trimmed.all { it in '0'..'9' }) {
            val s = text.indexOf(trimmed)
            otp = Run(s, s + trimmed.length, trimmed)
        } else {
            val runs = runs(text, "").filter { it.digits.length in 4..8 && !moneyAfter(folded, it.end) }
            val kw = OTP_KEYWORD.find(folded)
            if (kw != null) {
                otp = runs.firstOrNull { it.start >= kw.range.first } ?: runs.firstOrNull()
            } else {
                for (m in MA_WORD.findAll(folded)) {
                    val e = m.range.last + 1
                    otp = runs.firstOrNull { it.start >= e && it.start - e <= MA_WINDOW }
                    if (otp != null) break
                }
            }
        }
        otp?.let { out += chip(ClipChip.Kind.OTP, it.digits); taken += it.start until it.end }

        // --- SĐT ---
        phone@ for (r in runs(text, " .-")) {
            val plus = r.start > 0 && text[r.start - 1] == '+'
            if (plus && r.start - 1 > 0 && !leftOk(text, r.start - 1)) continue
            // Gộp dần các nhóm từ đầu tới khi hợp lệ ("0912 345 678 99" → 0912345678).
            for ((gEnd, n) in r.groupEnds) {
                val phone = normalizePhone(r.digits.substring(0, n), plus) ?: continue
                val span = (if (plus) r.start - 1 else r.start) until gEnd
                if (taken.any { it.overlaps(span) }) continue
                out += chip(ClipChip.Kind.PHONE, phone); taken += span
                break@phone
            }
        }

        // --- Địa chỉ --- (nguyên văn, không chiếm span số)
        AddressDetect.detect(text)?.let { out += chip(ClipChip.Kind.ADDRESS, it) }

        // --- STK ---
        val whole = trimmed.all { it in '0'..'9' || it == ' ' || it == '-' }
        val hasKw = ACCOUNT_KEYWORD.containsMatchIn(folded)
        for (r in runs(text, " -")) {
            val n = r.digits.length
            if (n !in 6..19) continue
            val span = r.start until r.end
            if (taken.any { it.overlaps(span) }) continue
            if (r.start > 0 && text[r.start - 1] == '+') continue
            if (moneyAfter(folded, r.end)) continue
            val ok = if (whole) n >= 9 else hasKw || n >= 9
            if (!ok) continue
            out += chip(ClipChip.Kind.ACCOUNT, r.digits); taken += span
            break
        }
        return out.sortedBy { it.kind.ordinal }.take(3)
    }

    fun label(kind: ClipChip.Kind, value: String): String {
        val shown = if (kind == ClipChip.Kind.OTP || value.length <= 6) value else value.take(4) + "…"
        return when (kind) {
            ClipChip.Kind.OTP -> "Dán OTP $shown"
            ClipChip.Kind.PHONE -> "Dán SĐT $shown"
            ClipChip.Kind.ACCOUNT -> "Dán STK $shown"
            ClipChip.Kind.ADDRESS -> "Dán địa chỉ"
        }
    }

    /**
     * Ô đang điền là ô địa chỉ / SĐT (EditorInfo) ⇒ chip loại đó lên đầu (dải chỉ hiện 2 chip).
     * Không biết loại ô ⇒ giữ thứ tự mặc định. Song sinh iOS ClipDetect.prioritize.
     */
    fun prioritize(chips: List<ClipChip>, kind: ClipChip.Kind?): List<ClipChip> {
        val i = if (kind == null) -1 else chips.indexOfFirst { it.kind == kind }
        if (i <= 0) return chips
        return listOf(chips[i]) + chips.filterIndexed { j, _ -> j != i }
    }

    /** Có SĐT Việt Nam trong [s] (cùng luật chip SĐT) — AddressDetect dùng làm ranh giới. */
    internal fun containsPhone(s: String): Boolean = runs(s, " .-").any { r ->
        val plus = r.start > 0 && s[r.start - 1] == '+'
        r.groupEnds.any { (_, n) -> normalizePhone(r.digits.substring(0, n), plus) != null }
    }

    private fun chip(kind: ClipChip.Kind, value: String) = ClipChip(kind, value, label(kind, value))

    /** +84/84 → 0; hợp lệ: di động 10 số đầu 03/05/07/08/09, bàn 11 số đầu 02. */
    internal fun normalizePhone(digits: String, plus: Boolean): String? {
        val d = when {
            digits.startsWith("84") && digits.length in 11..12 -> digits.substring(2).let { if (it.startsWith("0")) it else "0$it" }
            plus -> return null
            else -> digits
        }
        if (d.length == 10 && d[0] == '0' && d[1] in "35789") return d
        if (d.length == 11 && d.startsWith("02")) return d
        return null
    }

    private fun moneyAfter(folded: String, end: Int): Boolean =
        end <= folded.length && MONEY_SUFFIX.containsMatchIn(folded.substring(end))

    private fun isDigit(c: Char) = c in '0'..'9'
    private fun isAlnum(c: Char) = Character.isLetterOrDigit(c)

    private fun leftOk(s: String, i: Int): Boolean {
        if (i == 0) return true
        val c = s[i - 1]
        if (isAlnum(c)) return false
        if (c in ".,:/" && i >= 2 && isDigit(s[i - 2])) return false
        return true
    }

    private fun rightOk(s: String, j: Int): Boolean {
        if (j >= s.length) return true
        val c = s[j]
        if (isAlnum(c)) return false
        if (c in ".,:/" && j + 1 < s.length && isDigit(s[j + 1])) return false
        return true
    }

    /** Dãy số tối đa (phân cách đơn thuộc [seps] giữa 2 chữ số), đã qua luật biên. */
    private fun runs(s: String, seps: String): List<Run> {
        val out = ArrayList<Run>()
        var i = 0
        while (i < s.length) {
            if (!isDigit(s[i])) { i++; continue }
            val start = i
            val sb = StringBuilder()
            val groups = ArrayList<Pair<Int, Int>>()
            var j = i
            while (j < s.length) {
                val c = s[j]
                if (isDigit(c)) { sb.append(c); j++ }
                else if (c in seps && j + 1 < s.length && isDigit(s[j + 1])) { groups += j to sb.length; j++ }
                else break
            }
            groups += j to sb.length
            if (leftOk(s, start) && rightOk(s, j)) out += Run(start, j, sb.toString(), groups)
            i = j
        }
        return out
    }

    /** Bỏ dấu + lowercase, GIỮ nguyên độ dài (index khớp chuỗi gốc). */
    fun fold(s: String): String {
        val sb = StringBuilder(s.length)
        for (c in s) {
            val base = when (c) {
                'đ', 'Đ' -> 'd'
                else -> {
                    val n = Normalizer.normalize(c.toString(), Normalizer.Form.NFD)
                    if (n.isNotEmpty()) n[0] else c
                }
            }
            sb.append(base.lowercaseChar())
        }
        return sb.toString()
    }

    private fun IntRange.overlaps(o: IntRange) = first <= o.last && o.first <= last
}

/**
 * Địa chỉ Việt Nam trong nội dung vừa copy (thông tin giao hàng…). Luật THUẦN, chặt — bỏ sót thì
 * vẫn còn Dán nguyên văn, hiện nhầm mới phiền. Port 1:1 iOS `AddressDetect` (ClipDetect.swift).
 *  1. Tách đoạn theo xuống dòng , ; | và " - ".
 *  2. Đoạn có nhãn "Địa chỉ:/ĐC:/Đ/c:/Address:" ⇒ phần sau nhãn + các đoạn kế tới khi gặp đoạn có
 *     SĐT hoặc nhãn khác ("Tên:", "Ghi chú:").
 *  3. Không nhãn: mỗi đoạn chấm "tầng" — số nhà, đường/ngõ/hẻm…, phường/xã, quận/huyện, tỉnh/thành
 *     (từ khoá phải đi kèm chữ HOA hoặc số: "Quận 3", "P.14", "xã Tân Lập"; "quán phở" không tính).
 *     Lấy khúc liền nhau (không vượt đoạn có SĐT/nhãn) có ≥ 2 tầng, ít nhất một tầng là số nhà /
 *     phường-xã / quận-huyện.
 */
object AddressDetect {
    const val MAX_OUTPUT = 200

    enum class Level { HOUSE, STREET, WARD, DISTRICT, PROVINCE }

    private sealed class Part { class Label(val rest: String) : Part(); object Boundary : Part(); object Content : Part() }

    fun detect(raw: String): String? {
        val text = Normalizer.normalize(raw, Normalizer.Form.NFC)
        val parts = split(text).map { it to classify(it) }
        // 1. có nhãn
        for ((i, p) in parts.withIndex()) {
            val k = p.second as? Part.Label ?: continue
            val out = ArrayList<String>()
            if (k.rest.isNotEmpty()) out += k.rest
            var j = i + 1
            while (j < parts.size && parts[j].second === Part.Content) { out += parts[j].first; j++ }
            return finish(out)
        }
        // 2. không nhãn: khúc tốt nhất trong từng dải giữa các ranh giới
        var bestScore = 0
        var best: List<String>? = null
        var lo = -1; var hi = 0; var head = ""
        val levels = HashSet<Level>()
        fun close() {
            if (lo >= 0 && accepts(levels) && levels.size > bestScore) {
                // Đoạn đầu: bỏ lời dẫn trước dấu hiệu đầu tiên ("ship giúp e về 25 Trần Phú").
                bestScore = levels.size
                best = listOf(head) + parts.subList(lo + 1, hi + 1).map { it.first }
            }
            lo = -1; levels.clear()
        }
        for ((i, p) in parts.withIndex()) {
            if (p.second !== Part.Content) { close(); continue }
            val (lv, from) = scan(p.first)
            if (lv.isEmpty()) continue
            if (lo < 0) { lo = i; head = p.first.substring(from) }
            hi = i; levels += lv
        }
        close()
        return best?.let { finish(it) }
    }

    /** ≥ 2 tầng, trong đó có số nhà / phường-xã / quận-huyện ("Phở Hà Nội" = đường + tỉnh: không). */
    fun accepts(l: Set<Level>): Boolean =
        l.size >= 2 && (Level.HOUSE in l || Level.WARD in l || Level.DISTRICT in l)

    // --- tách + phân loại đoạn ---

    fun split(text: String): List<String> {
        val out = ArrayList<String>()
        val cur = StringBuilder()
        fun flush() { val t = cur.toString().trim(' ', '\t'); if (t.isNotEmpty()) out += t; cur.setLength(0) }
        for ((i, ch) in text.withIndex()) {
            if (ch == '\n' || ch == '\r' || ch in ",;|") { flush(); continue }
            if ((ch == '-' || ch == '–') && i > 0 && i + 1 < text.length && text[i - 1] == ' ' && text[i + 1] == ' ') { flush(); continue }
            cur.append(ch)
        }
        flush()
        return out
    }

    private val ADDRESS_LABELS = setOf("dc", "d/c", "d.c", "add", "addr", "address", "noi nhan", "giao den", "giao toi",
        "ship den", "ship toi", "gui den", "gui toi")

    private fun classify(p: String): Part {
        val f = ClipDetect.fold(p)
        val c = f.take(26).indexOf(':')
        if (c >= 0) {
            val head = f.substring(0, c).trim()
            if (head.isNotEmpty() && head.all { it.isLetter() || it in " /." }) {
                val rest = p.substring(c + 1).trim()
                if (head.startsWith("dia chi") || head in ADDRESS_LABELS) return Part.Label(rest)
                val first = head.split(' ').first()
                if (first !in KEYWORD_WORDS) return Part.Boundary
            }
        } else if (f.startsWith("dia chi ")) {
            return Part.Label(p.substring(8).trim())
        }
        if (ClipDetect.containsPhone(p)) return Part.Boundary
        return Part.Content
    }

    private val TRAILING_PARTICLES = setOf("nhé", "nha", "nhe", "nhá", "nhen", "ạ", "nhé.", "nha.")

    private fun finish(parts: List<String>): String? {
        val words = parts.joinToString(", ").split(Regex("\\s+")).filter { it.isNotEmpty() }.toMutableList()
        // Tiểu từ cuối câu nhắn ("…Đà Nẵng nhé").
        while (words.isNotEmpty() && words.last().lowercase() in TRAILING_PARTICLES) words.removeAt(words.size - 1)
        val s = words.joinToString(" ").trimEnd('.', ',', ';', '-', '–', ':', ' ')
        if (s.length > MAX_OUTPUT || s.count { it.isLetter() } < 4) return null
        return s
    }

    // --- tầng địa chỉ trong một đoạn ---

    /** Từ khoá đầy đủ (đã gập dấu) — phải đi kèm chữ HOA hoặc số phía sau. */
    private val FULL_KEYWORDS: List<Pair<List<String>, Level>> = listOf(
        "to dan pho" to Level.STREET, "khu do thi" to Level.STREET, "khu dan cu" to Level.STREET,
        "thanh pho" to Level.PROVINCE, "thi xa" to Level.DISTRICT, "thi tran" to Level.WARD,
        "khu pho" to Level.STREET, "so nha" to Level.HOUSE, "chung cu" to Level.STREET, "toa nha" to Level.STREET,
        "phuong" to Level.WARD, "xa" to Level.WARD, "ward" to Level.WARD,
        "quan" to Level.DISTRICT, "huyen" to Level.DISTRICT, "district" to Level.DISTRICT,
        "tinh" to Level.PROVINCE, "province" to Level.PROVINCE, "city" to Level.PROVINCE,
        "duong" to Level.STREET, "pho" to Level.STREET, "ngo" to Level.STREET, "ngach" to Level.STREET,
        "hem" to Level.STREET, "kiet" to Level.STREET, "thon" to Level.STREET, "xom" to Level.STREET,
        "ap" to Level.STREET, "lo" to Level.STREET, "street" to Level.STREET, "road" to Level.STREET,
        "lane" to Level.STREET, "alley" to Level.STREET,
    ).map { (w, l) -> w.split(' ') to l }

    /**
     * Viết tắt: dính số ("P14", "Q3") hoặc có chấm/khoảng trắng rồi chữ HOA/số ("P. Bến Nghé",
     * "TP HCM"); một chữ cái thì bắt buộc dính số hoặc có chấm.
     */
    private val ABBREVIATIONS = mapOf(
        "p" to Level.WARD, "x" to Level.WARD, "tt" to Level.WARD, "q" to Level.DISTRICT, "h" to Level.DISTRICT,
        "tx" to Level.DISTRICT, "tp" to Level.PROVINCE, "kp" to Level.STREET, "kdc" to Level.STREET,
        "kdt" to Level.STREET, "cc" to Level.STREET, "d" to Level.STREET, "sn" to Level.HOUSE,
    )
    private val KEYWORD_WORDS: Set<String> = FULL_KEYWORDS.map { it.first.first() }.toSet() + ABBREVIATIONS.keys

    /** Tỉnh/thành (34 đơn vị sau sáp nhập 2025 + tên cũ còn hay dùng), đã gập dấu. Chữ đầu phải HOA. */
    private val PROVINCES: List<List<String>> = listOf(
        "ha noi", "ho chi minh", "sai gon", "hai phong", "da nang", "can tho", "hue", "thua thien hue",
        "lai chau", "dien bien", "son la", "lang son", "quang ninh", "thanh hoa", "nghe an", "ha tinh",
        "cao bang", "tuyen quang", "lao cai", "thai nguyen", "phu tho", "bac ninh", "hung yen",
        "ninh binh", "quang tri", "quang ngai", "gia lai", "khanh hoa", "lam dong", "dak lak", "dak nong",
        "dong nai", "tay ninh", "vinh long", "dong thap", "ca mau", "an giang", "ha giang", "yen bai",
        "bac kan", "vinh phuc", "bac giang", "hoa binh", "hai duong", "thai binh", "ha nam", "nam dinh",
        "quang binh", "quang nam", "kon tum", "binh dinh", "phu yen", "ninh thuan", "binh thuan",
        "binh phuoc", "binh duong", "vung tau", "long an", "tien giang", "ben tre", "tra vinh",
        "hau giang", "soc trang", "bac lieu", "kien giang", "nha trang", "da lat", "bien hoa",
    ).map { it.split(' ') }
    /** Viết liền / viết tắt thành phố (chỉ khi viết HOA toàn bộ, trừ "tphcm"). */
    private val CITY_TOKENS = setOf("hcm", "tphcm", "hn", "sg", "hcmc")

    private class Tok(val s: String, val start: Int, val end: Int, val digit: Boolean)

    fun levels(p: String): Set<Level> = scan(p).first

    /** Tầng + vị trí dấu hiệu đầu tiên trong đoạn. */
    fun scan(p: String): Pair<Set<Level>, Int> {
        val o = p
        val f = ClipDetect.fold(p)
        val toks = ArrayList<Tok>()
        var i = 0
        while (i < f.length) {
            val d = f[i] in '0'..'9'
            if (!d && !f[i].isLetter()) { i++; continue }
            val s = i
            while (i < f.length && (if (d) f[i] in '0'..'9' else f[i].isLetter())) i++
            toks += Tok(f.substring(s, i), s, i, d)
        }
        fun isUpper(k: Int) = k < o.length && o[k].isUpperCase()
        fun isDigit(k: Int) = k < o.length && o[k] in '0'..'9'
        /** Vị trí ký tự đầu sau [end] khi bỏ qua khoảng trắng và "." — (vị trí, có chấm). */
        fun next(end: Int): Pair<Int, Boolean> {
            var k = end; var dot = false
            while (k < f.length && (f[k] == ' ' || f[k] == '.')) { if (f[k] == '.') dot = true; k++ }
            return k to dot
        }
        fun capOrDigit(k: Int) = isUpper(k) || isDigit(k)

        val out = HashSet<Level>()
        var from = -1
        fun hit(l: Level, at: Int) { out += l; if (from < 0) from = at }
        var t = 0
        while (t < toks.size) {
            val tok = toks[t]
            if (tok.digit) {
                // Số nhà: 1–5 chữ số, trước là đầu đoạn/khoảng trắng; ở đầu đoạn hoặc ngay sau là tên
                // viết HOA ("ở 12 Nguyễn Trãi"). "Phường 14", "P.14", "12:30" không tính.
                val prevOK = tok.start == 0 || f[tok.start - 1] == ' '
                val nt = toks.getOrNull(t + 1)
                val followedByName = nt != null && !nt.digit && isUpper(nt.start) && nt.start > tok.end
                if (tok.s.length <= 5 && prevOK && (tok.start == 0 || followedByName)) hit(Level.HOUSE, tok.start)
                t++; continue
            }
            // Tỉnh/thành
            if (isUpper(tok.start)) {
                val n = PROVINCES.firstOrNull { w ->
                    t + w.size <= toks.size && w.indices.all { toks[t + it].s == w[it] && !toks[t + it].digit }
                }
                if (n != null) { hit(Level.PROVINCE, tok.start); t += n.size; continue }
            }
            if (tok.s in CITY_TOKENS && (tok.s == "tphcm" || (tok.start until tok.end).all { o[it].isUpperCase() })) {
                hit(Level.PROVINCE, tok.start); t++; continue
            }
            // "Số 5" ⇒ số nhà
            if (tok.s == "so" && toks.getOrNull(t + 1)?.digit == true) { hit(Level.HOUSE, tok.start); t++; continue }
            // Từ khoá đầy đủ
            val kw = FULL_KEYWORDS.firstOrNull { (w, _) ->
                t + w.size <= toks.size && w.indices.all { toks[t + it].s == w[it] }
            }
            if (kw != null) {
                val end = toks[t + kw.first.size - 1].end
                if (capOrDigit(next(end).first)) hit(kw.second, tok.start)
                t += kw.first.size; continue
            }
            // Viết tắt
            ABBREVIATIONS[tok.s]?.let { lv ->
                val attachedDigit = tok.end < f.length && f[tok.end] in '0'..'9'
                val (k, dot) = next(tok.end)
                val ok = attachedDigit || (capOrDigit(k) && (dot || tok.s.length >= 2))
                // "8h30", "2x3": viết tắt dính chữ/số phía trước không tính.
                val prevFree = tok.start == 0 || !(f[tok.start - 1].isLetter() || f[tok.start - 1] in '0'..'9')
                if (ok && prevFree) hit(lv, tok.start)
            }
            t++
        }
        return out to (if (from < 0) 0 else from)
    }
}

/** Heuristic "trông như bí mật" — mục nhạy cảm tự hết hạn sớm (2 phút) trong lịch sử. */
object ClipSensitivity {
    fun looksSecret(text: String): Boolean {
        val t = text.trim()
        if (t.isEmpty()) return false
        if (t.length in 4..8 && t.all { it in '0'..'9' }) return true
        if (t.length <= ClipDetect.MAX_LEN && ClipDetect.detect(t).any { it.kind == ClipChip.Kind.OTP }) return true
        if (t.any { it.isWhitespace() }) return false
        if (t.contains("://") || t.lowercase().startsWith("www.")) return false
        val at = t.indexOf('@')
        if (at > 0 && t.indexOf('.', at) > at + 1) return false
        val lower = t.any { it.isLowerCase() }
        val upper = t.any { it.isUpperCase() }
        val digit = t.any { it.isDigit() }
        val symbol = t.any { !it.isLetterOrDigit() }
        val classes = listOf(lower, upper, digit, symbol).count { it }
        if (t.length in 8..64 && classes >= 3) return true
        if (t.length >= 20 && (lower || upper) && digit) return true
        return false
    }
}
