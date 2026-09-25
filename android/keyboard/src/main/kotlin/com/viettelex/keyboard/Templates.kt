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
        val notice = "Đã thêm $added/${imported.size} mẫu" +
            if (imported.size > added) " (trùng bị bỏ qua)." else "."
        return out to notice
    }

    /** Thêm mới từ tab Mẫu Câu: trim, chặn rỗng + trùng text. null = không thêm. */
    /** Sửa dòng [index]; null nếu câu rỗng, trùng dòng khác, hoặc index sai. */
    fun edit(current: List<TemplateItem>, index: Int, label: String, text: String): List<TemplateItem>? {
        val t = text.trim()
        val l = label.trim(' ', '\t')
        if (index !in current.indices || t.isEmpty()) return null
        if (current.withIndex().any { it.index != index && it.value.text == t }) return null
        return current.toMutableList().also { it[index] = TemplateItem(l, t) }
    }

    fun add(current: List<TemplateItem>, label: String, text: String): List<TemplateItem>? {
        val t = text.trim()
        val l = label.trim(' ', '\t')
        if (t.isEmpty() || current.any { it.text == t }) return null
        return current + TemplateItem(l, t)
    }

    /** Mẫu động: fetch lúc chạm. */
    fun isDynamic(text: String) = text.startsWith("https://")
    const val FETCH_TIMEOUT_MS = 4000
    const val FETCH_MAX_BYTES = 1000

    /** Body chèn cho mẫu động: ≤1000 byte, trim; null/rỗng ⇒ caller chèn chính URL. */
    fun bodyFromResponse(bytes: ByteArray?): String? {
        if (bytes == null) return null
        val s = String(bytes, 0, minOf(bytes.size, FETCH_MAX_BYTES), Charsets.UTF_8).trim()
        return s.ifEmpty { null }
    }

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
