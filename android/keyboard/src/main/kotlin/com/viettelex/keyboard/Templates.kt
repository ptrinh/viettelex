package com.viettelex.keyboard

/** Một mẫu câu: text + label tuỳ chọn (emoji/chữ ngắn) cho bubble. */
data class TemplateItem(val label: String, val text: String)

/**
 * Mẫu câu (☰): YAML phẳng giống hệt iOS (`- "label | câu"` / `- "câu"`, `\"` escape),
 * lưu pref [Keys.USER_TEMPLATES] dạng JSON `[{"label":…,"text":…}]`.
 */
object Templates {
    val fallback = listOf(TemplateItem("👋", "Chào buổi sáng"))

    fun parseYAML(text: String): List<TemplateItem> = text.split('\n').mapNotNull { line ->
        var s = line.trim(' ', '\t', '\r')
        if (s.isEmpty() || s.startsWith("#") || !s.startsWith("- ")) return@mapNotNull null
        s = s.substring(2).trim(' ', '\t', '\r')
        if (s.length >= 2 && s.startsWith("\"") && s.endsWith("\"")) {
            s = s.substring(1, s.length - 1).replace("\\\"", "\"")
        }
        if (s.isEmpty()) return@mapNotNull null
        val r = s.indexOf(" | ")
        if (r >= 0) {
            val label = s.substring(0, r).trim(' ', '\t')
            val body = s.substring(r + 3).trim(' ', '\t')
            if (body.isEmpty()) null else TemplateItem(label, body)
        } else TemplateItem("", s)
    }

    fun exportYAML(items: List<TemplateItem>): String {
        fun esc(s: String) = s.replace("\"", "\\\"")
        return "# VietTelex — mẫu câu (${items.size})\n" + items.joinToString("\n") {
            if (it.label.isEmpty()) "- \"${esc(it.text)}\"" else "- \"${esc(it.label)} | ${esc(it.text)}\""
        } + "\n"
    }

    /**
     * Danh sách hiện hành: pref JSON nếu có, không thì YAML mặc định (assets). YAML rỗng
     * ⇒ [fallback] (như iOS).
     */
    fun load(json: String?, defaultsYaml: () -> String?): List<TemplateItem> {
        if (json != null) fromJson(json)?.let { return it }
        val y = defaultsYaml() ?: return fallback
        return parseYAML(y).ifEmpty { fallback }
    }

    /** Import gộp thêm (bỏ trùng theo text). Trả (danh sách mới, thông báo iOS). */
    fun merge(current: List<TemplateItem>, imported: List<TemplateItem>): Pair<List<TemplateItem>, String> {
        val out = current.toMutableList()
        for (item in imported) if (out.none { it.text == item.text }) out.add(item)
        val added = out.size - current.size
        val notice = if (imported.size > added) tr("Đã thêm %d/%d mẫu (trùng bị bỏ qua).", added, imported.size)
            else tr("Đã thêm %d/%d mẫu.", added, imported.size)
        return out to notice
    }

    /** Sửa dòng [index]; null nếu câu rỗng, trùng dòng khác, hoặc index sai. */
    fun edit(current: List<TemplateItem>, index: Int, label: String, text: String): List<TemplateItem>? {
        val t = text.trim()
        val l = label.trim(' ', '\t')
        if (index !in current.indices || t.isEmpty()) return null
        if (current.withIndex().any { it.index != index && it.value.text == t }) return null
        return current.toMutableList().also { it[index] = TemplateItem(l, t) }
    }

    /**
     * "Hoàn tác" sau khi vuốt xoá (báo lỗi 13/11/2026: vuốt nhầm mất mẫu câu): chèn lại [item]
     * (cả label) đúng vị trí [index] cũ — kẹp vào cuối nếu danh sách đã ngắn hơn. Câu đã có lại
     * (vừa thêm tay) ⇒ giữ nguyên, không nhân đôi.
     */
    fun restore(current: List<TemplateItem>, index: Int, item: TemplateItem): List<TemplateItem> {
        if (current.any { it.text == item.text }) return current
        return current.toMutableList().also { it.add(index.coerceIn(0, it.size), item) }
    }

    /** Thêm mới: null = không thêm (lý do: [tryAdd]). */
    fun add(current: List<TemplateItem>, label: String, text: String): List<TemplateItem>? =
        (tryAdd(current, label, text) as? AddResult.Added)?.list

    /** Kết quả thêm mẫu câu — không bao giờ "im lặng": mọi nhánh không thêm có lý do. */
    sealed class AddResult {
        data class Added(val list: List<TemplateItem>) : AddResult()
        object EmptyText : AddResult()
        /** Trùng câu ở dòng [index] (0-based). */
        data class Duplicate(val index: Int) : AddResult()
    }

    /**
     * Thêm mới từ tab Mẫu Câu: trim câu (giữ xuống dòng bên trong), label bỏ khoảng trắng/
     * xuống dòng hai đầu. Label/câu nhận MỌI ký tự (emoji, "→", "&", "|"…) — chỉ chặn câu
     * rỗng và câu trùng (so sau trim). Lỗi iOS 27/09/2026: "Ig😊" + câu có "→" bấm ⊕ im lặng.
     */
    fun tryAdd(current: List<TemplateItem>, label: String, text: String): AddResult {
        val t = text.trim()
        if (t.isEmpty()) return AddResult.EmptyText
        val dup = current.indexOfFirst { it.text.trim() == t }
        if (dup >= 0) return AddResult.Duplicate(dup)
        return AddResult.Added(current + TemplateItem(label.trim(), t))
    }

    /** Câu báo cho người dùng khi không thêm được (null = đã thêm). */
    fun addNotice(r: AddResult): String? = when (r) {
        is AddResult.Added -> null
        AddResult.EmptyText -> tr("Chưa có nội dung mẫu câu — nhập câu vào ô bên phải rồi bấm ⊕.")
        is AddResult.Duplicate -> tr("Mẫu câu này đã có (dòng %d) — không thêm lại.", r.index + 1)
    }

    /** Mẫu động: fetch lúc chạm. */
    fun isDynamic(text: String) = text.startsWith("https://")
    const val FETCH_TIMEOUT_MS = 4000
    const val FETCH_MAX_BYTES = 1000

    /**
     * Body chèn cho mẫu động: chỉ khi HTTP 200 ([status] null = không kiểm, dùng cho bytes đã
     * lọc); giải mã UTF-8 tường minh ≤1000 byte, lùi về ranh giới ký tự (không cắt đôi "₫"/chữ
     * có dấu thành "�"), trim. null ⇒ caller chèn chính URL (lỗi mạng, timeout, mã ≠ 200, rỗng).
     */
    fun bodyFromResponse(bytes: ByteArray?, status: Int? = 200): String? {
        if (bytes == null || status != 200) return null
        var n = minOf(bytes.size, FETCH_MAX_BYTES)
        if (bytes.size > FETCH_MAX_BYTES) n = utf8Boundary(bytes, n)
        val s = String(bytes, 0, n, Charsets.UTF_8).trim()
        return s.ifEmpty { null }
    }

    /** Độ dài ≤ [n] không kết thúc giữa một ký tự UTF-8 nhiều byte. */
    internal fun utf8Boundary(b: ByteArray, n: Int): Int {
        var i = n
        var cont = 0
        while (i > 0 && cont < 3 && (b[i - 1].toInt() and 0xC0) == 0x80) { i--; cont++ }
        if (i == 0) return n
        val lead = b[i - 1].toInt() and 0xFF
        val need = when {
            lead and 0x80 == 0 -> return n
            lead and 0xE0 == 0xC0 -> 1
            lead and 0xF0 == 0xE0 -> 2
            lead and 0xF8 == 0xF0 -> 3
            else -> return n
        }
        return if (cont >= need) n else i - 1
    }

    /** Mẫu động có sẵn — cùng thứ tự/nội dung với cuối assets/ios-mau-cau.yml (và iOS DynamicSnippets). */
    val dynamicBuiltins = listOf(
        TemplateItem("💵❓", "https://viettelex.com/api/usd"),
        TemplateItem("💸❓", "https://viettelex.com/api/usd-tudo"),
        TemplateItem("🟡❓", "https://viettelex.com/api/vang"),
        TemplateItem("🪙❓", "https://viettelex.com/api/btc"),
    )

    /**
     * Migration MỘT LẦN ([Keys.DYNAMIC_SNIPPETS_MIGRATED]): thêm các [dynamicBuiltins] còn thiếu
     * (so theo text) vào cuối danh sách đã tự chỉnh. [json] null = chưa tự chỉnh (mặc định YAML
     * đã có) ⇒ không đổi. Trả JSON mới cần ghi, null = không đổi danh sách. Caller luôn ghi cờ
     * sau khi gọi — trừ khi JSON hỏng (không đụng, thử lại lần sau) — nên người dùng xoá mẫu
     * sau đó thì không bao giờ bị thêm lại.
     */
    fun migrateDynamicBuiltins(json: String?, alreadyRan: Boolean): String? {
        if (alreadyRan || json == null) return null
        val list = fromJson(json) ?: return null
        val have = list.map { it.text.trim() }.toSet()
        val missing = dynamicBuiltins.filter { it.text !in have }
        return if (missing.isEmpty()) null else toJson(list + missing)
    }

    /** JSON hỏng ⇒ chưa đánh dấu đã chạy (không đụng dữ liệu lạ). */
    fun shouldMarkDynamicMigrated(json: String?): Boolean = json == null || fromJson(json) != null

    /**
     * Nhập mẫu câu KHÔNG cần mạng (file qua SAF hoặc chữ chia sẻ ACTION_SEND): nội dung có
     * dòng YAML (`- "label | câu"` / `- "câu"`) ⇒ [parseYAML]; không có dòng nào ⇒ cả đoạn
     * (trim, giữ xuống dòng) là MỘT mẫu không label. Bỏ BOM đầu file; đoạn quá dài
     * (> [IMPORT_MAX_CHARS]) hoặc rỗng ⇒ danh sách rỗng.
     */
    fun parseImport(text: String?): List<TemplateItem> {
        if (text == null) return emptyList()
        val s = text.removePrefix("\uFEFF").replace("\r\n", "\n")
        val yaml = parseYAML(s)
        if (yaml.isNotEmpty()) return yaml
        val one = s.trim()
        if (one.isEmpty() || one.length > IMPORT_MAX_CHARS) return emptyList()
        return listOf(TemplateItem("", one))
    }
    const val IMPORT_MAX_CHARS = 2000

    // --- JSON tối giản (không phụ thuộc thư viện) ---

    fun toJson(items: List<TemplateItem>): String {
        val sb = StringBuilder("[")
        items.forEachIndexed { i, it ->
            if (i > 0) sb.append(',')
            sb.append("{\"label\":"); jsonString(sb, it.label)
            sb.append(",\"text\":"); jsonString(sb, it.text); sb.append('}')
        }
        return sb.append(']').toString()
    }

    private fun jsonString(sb: StringBuilder, s: String) {
        sb.append('"')
        for (c in s) when {
            c == '"' -> sb.append("\\\"")
            c == '\\' -> sb.append("\\\\")
            c == '\n' -> sb.append("\\n")
            c == '\r' -> sb.append("\\r")
            c == '\t' -> sb.append("\\t")
            c < ' ' -> sb.append(String.format("\\u%04x", c.code))
            else -> sb.append(c)
        }
        sb.append('"')
    }

    /** Parse `[{"label":…,"text":…}]`; entry thiếu/rỗng text bị bỏ. null = JSON hỏng. */
    fun fromJson(json: String): List<TemplateItem>? = try {
        val p = JsonReader(json)
        val out = ArrayList<TemplateItem>()
        p.ws(); p.expect('[')
        p.ws()
        if (p.peek() == ']') p.i++ else while (true) {
            p.ws(); p.expect('{')
            var label = ""; var text: String? = null
            p.ws()
            if (p.peek() == '}') p.i++ else while (true) {
                p.ws(); val k = p.string(); p.ws(); p.expect(':'); p.ws()
                val v: String? = if (p.peek() == '"') p.string() else { p.skipValue(); null }
                when (k) { "label" -> label = v ?: ""; "text" -> text = v }
                p.ws()
                if (p.peek() == ',') { p.i++; continue }
                p.expect('}'); break
            }
            if (!text.isNullOrEmpty()) out.add(TemplateItem(label, text!!))
            p.ws()
            if (p.peek() == ',') { p.i++; continue }
            p.expect(']'); break
        }
        out
    } catch (e: IllegalArgumentException) { null } catch (e: IndexOutOfBoundsException) { null }

    private class JsonReader(val s: String) {
        var i = 0
        fun peek(): Char = s[i]
        fun ws() { while (i < s.length && s[i].isWhitespace()) i++ }
        fun expect(c: Char) { require(s[i] == c) { "expected $c" }; i++ }
        fun string(): String {
            expect('"')
            val sb = StringBuilder()
            while (true) {
                val c = s[i++]
                when (c) {
                    '"' -> return sb.toString()
                    '\\' -> when (val e = s[i++]) {
                        'n' -> sb.append('\n'); 'r' -> sb.append('\r'); 't' -> sb.append('\t')
                        'b' -> sb.append('\b'); 'f' -> sb.append('\u000C')
                        'u' -> { sb.append(s.substring(i, i + 4).toInt(16).toChar()); i += 4 }
                        else -> sb.append(e)
                    }
                    else -> sb.append(c)
                }
            }
        }
        fun skipValue() {
            when (peek()) {
                '"' -> string()
                '{', '[' -> {
                    var depth = 0
                    do {
                        when (s[i]) { '{', '[' -> depth++; '}', ']' -> depth--; '"' -> { string(); continue } }
                        i++
                    } while (depth > 0)
                }
                else -> while (i < s.length && s[i] !in ",}]") i++
            }
        }
    }
}
