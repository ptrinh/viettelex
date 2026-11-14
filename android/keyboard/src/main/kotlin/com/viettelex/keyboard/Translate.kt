package com.viettelex.keyboard

import java.text.Collator
import java.util.Locale

/**
 * DỊCH TRÊN MÁY (gói Plus, [PlusFeature.TRANSLATE]) — phần thuần JVM: chọn chiều dịch, đọc
 * nguồn / ghi kết quả qua [TextProxy], điều phối máy dịch (sau interface, app gắn ML Kit).
 *
 * KHÔNG BAO GIỜ gửi chữ lên server: máy dịch là ML Kit on-device; gói ngôn ngữ chỉ tải từ app
 * khi người dùng bấm (không bao giờ từ bàn phím).
 */
object TranslateLangs {
    const val VI = "vi"
    const val DEFAULT_TARGET = "en"

    /**
     * Mọi mã ML Kit Translation hỗ trợ (= TranslateLanguage.getAllLanguages() bản 17.0.3,
     * test app TranslateLangsMlKitTest giữ khớp). Module này thuần JVM nên chép tay.
     */
    val ALL: List<String> = listOf(
        "af", "sq", "ar", "be", "bg", "bn", "ca", "zh", "hr", "cs", "da", "nl", "en", "eo", "et", "fi",
        "fr", "gl", "ka", "de", "el", "gu", "ht", "he", "hi", "hu", "is", "id", "ga", "it", "ja", "kn",
        "ko", "lt", "lv", "mk", "mr", "ms", "mt", "no", "fa", "pl", "pt", "ro", "ru", "sk", "sl", "es",
        "sv", "sw", "tl", "ta", "te", "th", "tr", "uk", "ur", "vi", "cy",
    )

    /** Ngôn ngữ đích chọn được: mọi thứ trừ tiếng Việt (tiếng Việt luôn là đầu kia). */
    val TARGETS: Set<String> = (ALL - VI).toSet()

    /** Giá trị pref thô ⇒ mã đích hợp lệ (lạ / "vi" / null ⇒ English). */
    fun normalizeTarget(raw: Any?): String = (raw as? String)?.takeIf { it in TARGETS } ?: DEFAULT_TARGET

    /** Tên ngôn ngữ theo ngôn ngữ giao diện ("Tiếng Nhật" / "Japanese"), viết hoa chữ đầu. */
    fun displayName(code: String, uiLang: String = L10n.lang): String {
        val ui = Locale.forLanguageTag(uiLang)
        val n = Locale.forLanguageTag(code).getDisplayLanguage(ui).ifBlank { code }
        return n.replaceFirstChar { it.titlecase(ui) }
    }

    /** Danh sách cho bộ chọn: English (mặc định) đứng đầu, còn lại theo tên (Collator ngôn ngữ UI). */
    fun pickerOrder(uiLang: String = L10n.lang): List<String> {
        val col = Collator.getInstance(Locale.forLanguageTag(uiLang))
        val rest = TARGETS.filter { it != DEFAULT_TARGET }.sortedWith { a, b -> col.compare(displayName(a, uiLang), displayName(b, uiLang)) }
        return listOf(DEFAULT_TARGET) + rest
    }

    // --- chữ viết của ngôn ngữ đích ---

    private val LATIN = setOf(
        "af", "sq", "ca", "hr", "cs", "da", "nl", "en", "eo", "et", "fi", "fr", "gl", "de", "ht", "hu",
        "is", "id", "ga", "it", "lt", "lv", "ms", "mt", "no", "pl", "pt", "ro", "sk", "sl", "es", "sv",
        "sw", "tl", "tr", "cy", "vi",
    )

    fun isLatin(code: String) = code in LATIN

    /** Các script Unicode coi là "chữ của" [code] (rỗng = không biết). */
    fun scriptsOf(code: String): Set<Character.UnicodeScript> =
        when (code) {
            in LATIN -> setOf(Character.UnicodeScript.LATIN)
            "be", "bg", "mk", "ru", "uk" -> setOf(Character.UnicodeScript.CYRILLIC)
            "ar", "fa", "ur" -> setOf(Character.UnicodeScript.ARABIC)
            "he" -> setOf(Character.UnicodeScript.HEBREW)
            "el" -> setOf(Character.UnicodeScript.GREEK)
            "ka" -> setOf(Character.UnicodeScript.GEORGIAN)
            "hi", "mr" -> setOf(Character.UnicodeScript.DEVANAGARI)
            "bn" -> setOf(Character.UnicodeScript.BENGALI)
            "gu" -> setOf(Character.UnicodeScript.GUJARATI)
            "kn" -> setOf(Character.UnicodeScript.KANNADA)
            "ta" -> setOf(Character.UnicodeScript.TAMIL)
            "te" -> setOf(Character.UnicodeScript.TELUGU)
            "th" -> setOf(Character.UnicodeScript.THAI)
            "ko" -> setOf(Character.UnicodeScript.HANGUL)
            "ja" -> setOf(Character.UnicodeScript.HIRAGANA, Character.UnicodeScript.KATAKANA, Character.UnicodeScript.HAN)
            "zh" -> setOf(Character.UnicodeScript.HAN)
            else -> emptySet()
        }
}

/**
 * Chiều dịch — heuristic rẻ, KHÔNG dùng ML Kit language-id (thêm ~1 MB native/ABI). Quy tắc:
 *  1. Chữ "trông như tiếng Việt" ⇒ vi → đích.
 *  2. Không thì: chữ viết đúng script của đích ⇒ coi là đã ở ngôn ngữ đích ⇒ đích → vi (khứ hồi).
 *  3. Còn lại ⇒ vi → đích (coi như tiếng Việt gõ không dấu, vd "hom nay" khi đích là tiếng Nhật).
 *
 * "Trông như tiếng Việt": có chữ CHỈ tiếng Việt dùng (ă đ ĩ ũ ơ ư và khối U+1EA0–U+1EF9: ạ ả ấ ầ…);
 * riêng khi đích là English (không dùng dấu) thì mọi chữ Latin có dấu (à é ô…) cũng tính.
 *
 * GIỚI HẠN (đã biết): đích Latin + tiếng Việt KHÔNG dấu ("xin chao") ⇒ bị coi là ngôn ngữ đích
 * (đích → vi); đích Latin có dấu (fr/es/pt…) + câu Việt chỉ có à/é/ô… (vd "cà phê") ⇒ cũng bị coi
 * là đích; Latin khác đích (gõ tiếng Anh khi đích là tiếng Nhật) ⇒ dịch như tiếng Việt; chữ Hán
 * thuần khi đích ja/zh coi là đích. Không phân biệt các ngôn ngữ cùng script (ru/uk, ar/fa).
 */
object TranslateDirection {
    data class Plan(val from: String, val to: String)

    /** Chữ cái chỉ có trong bảng chữ tiếng Việt (ngoài Latin-1). */
    fun isVietnameseOnly(cp: Int): Boolean = when (cp) {
        0x0102, 0x0103, // Ă ă
        0x0110, 0x0111, // Đ đ
        0x0128, 0x0129, // Ĩ ĩ
        0x0168, 0x0169, // Ũ ũ
        0x01A0, 0x01A1, // Ơ ơ
        0x01AF, 0x01B0, // Ư ư
        -> true
        else -> cp in 0x1EA0..0x1EF9
    }

    /** Chữ Latin có dấu trong bảng tiếng Việt thuộc Latin-1 (à á â ã è é ê ì í ò ó ô õ ù ú ý). */
    private fun isLatin1VnVowel(cp: Int): Boolean {
        val c = Character.toLowerCase(cp)
        return c in intArrayOf(0xE0, 0xE1, 0xE2, 0xE3, 0xE8, 0xE9, 0xEA, 0xEC, 0xED, 0xF2, 0xF3, 0xF4, 0xF5, 0xF9, 0xFA, 0xFD)
    }

    fun looksVietnamese(text: String, target: String): Boolean {
        val s = TextTools.nfc(text)
        val loose = target == "en"
        return s.codePoints().anyMatch { isVietnameseOnly(it) || (loose && isLatin1VnVowel(it)) }
    }

    /** Chữ cái của [text] chủ yếu thuộc script của [target] (không tính dấu câu/số/khoảng trắng). */
    fun inTargetScript(text: String, target: String): Boolean {
        val want = TranslateLangs.scriptsOf(target)
        if (want.isEmpty()) return false
        var hit = 0; var miss = 0; var kana = false
        for (cp in text.codePoints().toArray()) {
            if (!Character.isLetter(cp)) continue
            val sc = Character.UnicodeScript.of(cp)
            if (sc == Character.UnicodeScript.HIRAGANA || sc == Character.UnicodeScript.KATAKANA) kana = true
            if (sc in want) hit++ else miss++
        }
        if (target == "zh" && kana) return false      // có kana ⇒ tiếng Nhật, không phải tiếng Trung
        return hit > 0 && hit >= miss
    }

    /** null = không có chữ để dịch. */
    fun plan(text: String, rawTarget: Any?): Plan? {
        if (text.codePoints().noneMatch { Character.isLetter(it) }) return null
        val target = TranslateLangs.normalizeTarget(rawTarget)
        return when {
            looksVietnamese(text, target) -> Plan(TranslateLangs.VI, target)
            inTargetScript(text, target) -> Plan(target, TranslateLangs.VI)
            else -> Plan(TranslateLangs.VI, target)
        }
    }
}

/** Một lượt dịch: [source] đọc lúc chạm, ghi lại khi có kết quả (nếu ô chưa đổi). */
data class TranslateJob(val source: TextTools.Source, val plan: TranslateDirection.Plan)

/** Đọc nguồn + ghi kết quả — cùng đường ghi với [TextToolRunner] (confirmTail, đếm code point). */
object TranslateRunner {
    /** Đọc vùng chọn / đoạn trước con trỏ (giống công cụ văn bản) và chọn chiều. */
    fun prepare(proxy: TextProxy, target: Any?, contextCap: Int = Int.MAX_VALUE): TranslateJob? {
        val before = proxy.contextBeforeInput()
        val src = TextTools.source(proxy.selectedText(), before, before != null && before.length >= contextCap)
            ?: return null
        val plan = TranslateDirection.plan(src.text, target) ?: return null
        return TranslateJob(src, plan)
    }

    /**
     * Ghi [translated] thay cho nguồn của [job] — CHỈ khi ô vẫn như lúc chạm: vùng chọn vẫn là
     * đúng chữ đó, hoặc đuôi trước con trỏ vẫn là đoạn nguồn. Lệch ⇒ FailSafe, không đụng gì.
     */
    fun commit(job: TranslateJob, translated: String, proxy: TextProxy): TextToolRunner.Outcome {
        val src = job.source
        val result = TextTools.nfc(translated)
        if (result.isBlank()) return TextToolRunner.Outcome.Unchanged
        if (TextTools.nfc(src.text) == result) return TextToolRunner.Outcome.Unchanged
        if (src.isSelection) {
            val sel = proxy.selectedText() ?: return TextToolRunner.Outcome.FailSafe
            if (TextTools.nfc(sel) != TextTools.nfc(src.text)) return TextToolRunner.Outcome.FailSafe
            proxy.insertText(result)
        } else {
            if (proxy.hasSelection) return TextToolRunner.Outcome.FailSafe
            if (!proxy.confirmTail(src.text)) return TextToolRunner.Outcome.FailSafe
            proxy.deleteCodePoints(Cp.count(src.text))
            proxy.insertText(result)
        }
        return TextToolRunner.Outcome.Applied(TextTools.Undo(src.text, result))
    }
}

// --- máy dịch (app gắn ML Kit; test gắn bản giả) ---

sealed class TranslateResult {
    data class Ok(val text: String) : TranslateResult()
    /** Chưa có gói ngôn ngữ trên máy ⇒ bàn phím nhắc mở app để tải. */
    object MissingModel : TranslateResult()
    data class Failed(val reason: String) : TranslateResult()
}

/**
 * Dịch bằng LLM trên máy (Gemini Nano — thử nghiệm): prompt + kiểm kết quả. Kết quả không qua
 * [validate] ⇒ app dùng ML Kit (không bao giờ ghi bản dịch đáng ngờ vào ô).
 */
object AITranslate {
    /** Đoạn dài hơn ⇒ khỏi hỏi model (giới hạn ngữ cảnh / đầu ra của model trên máy), dùng ML Kit. */
    const val MAX_CHARS = 1000

    private fun englishName(code: String) =
        java.util.Locale.forLanguageTag(code).getDisplayLanguage(java.util.Locale.ENGLISH).ifBlank { code }

    fun prompt(text: String, plan: TranslateDirection.Plan): String =
        "Translate the text below from ${englishName(plan.from)} to ${englishName(plan.to)}. " +
            "Write it the way a native speaker would say it, keeping the meaning, tone, names, numbers, " +
            "emoji and line breaks. Reply with the translation only, no notes or quotes.\n\nText:\n" + text

    /** Bản dịch đã gọn, hoặc null nếu trông không ổn (trống, lời dẫn, độ dài lệch, sai chữ viết, mất dòng). */
    fun validate(output: String, source: String, plan: TranslateDirection.Plan): String? {
        var out = output.trim()
        // Lời dẫn kiểu "Translation:" / "Here is the translation:" ở dòng đầu.
        val firstLine = out.substringBefore('\n')
        if (firstLine.endsWith(':') && firstLine.length < 60 && out.contains('\n')) out = out.substringAfter('\n').trim()
        if (out.length >= 2 && out.first() in "\"“'" && out.last() in "\"”'" && source.trim().first() !in "\"“'") {
            out = out.substring(1, out.length - 1).trim()
        }
        if (out.isEmpty()) return null
        val n = source.trim().length
        if (out.length > n * 3 + 20 || out.length * 3 + 10 < n) return null
        val srcLines = source.trim().lines().size
        if (srcLines > 1 && out.lines().size != srcLines) return null
        val ok = when {
            plan.to == TranslateLangs.VI -> TranslateDirection.looksVietnamese(out, "en") || !out.any { it.isLetter() }
            // Đích Latin: không được còn chữ RIÊNG tiếng Việt (ơ ư đ ă… — kiểm chặt, không tính à á é).
            TranslateLangs.isLatin(plan.to) -> !TranslateDirection.looksVietnamese(out, "")
            else -> TranslateDirection.inTargetScript(out, plan.to)
        }
        return if (ok) out else null
    }
}

/** Một client dịch cho MỘT cặp; [close] giải phóng model native. Callback về main thread. */
interface TranslateEngine {
    fun translate(text: String, onDone: (TranslateResult) -> Unit)
    fun close()
}

fun interface TranslateEngineFactory {
    fun create(plan: TranslateDirection.Plan): TranslateEngine
}

/**
 * Điều phối: KHÔNG tạo client nào tới khi chạm "Dịch"; mỗi lượt một client, đóng ngay khi
 * xong / huỷ. Kết quả của lượt đã huỷ (đổi ô, chạm lại, IME đóng) bị bỏ.
 */
class TranslateController(private val factory: TranslateEngineFactory) {
    private var gen = 0
    private var active: TranslateEngine? = null

    val busy: Boolean get() = active != null

    fun start(job: TranslateJob, onResult: (TranslateJob, TranslateResult) -> Unit) {
        cancel()
        val g = ++gen
        val e = try { factory.create(job.plan) } catch (t: Throwable) {
            onResult(job, TranslateResult.Failed(t.toString())); return
        }
        active = e
        e.translate(job.source.text) { r ->
            if (g != gen) return@translate          // đã huỷ / lượt mới — client đã đóng
            active = null
            e.close()
            onResult(job, r)
        }
    }

    /** Huỷ lượt đang chạy (nếu có) và đóng client. */
    fun cancel() {
        gen++
        active?.let { active = null; it.close() }
    }
}
