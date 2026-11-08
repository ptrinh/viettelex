package com.viettelex.keyboard

import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction

/*
 * "Giao diện JSON": đặc tả theme dạng JSON có phiên bản — theme có sẵn (themes/builtin-themes.json),
 * theme tự tạo (dán / sửa), tuỳ chỉnh theo theme (KeyStyle.light/.dark). Y HỆT iOS
 * (iOS/Keyboard/ThemeSpec.swift): cùng luật đọc, cùng chuỗi chuẩn, cùng bảng lỗi — fixture chung
 * iOS/KeyboardTests/Fixtures/theme-json-cases.txt chạy ở cả hai bên.
 *
 * AN TOÀN (dữ liệu không tin được — dán từ clipboard): kiểm cỡ TRƯỚC khi đọc (16 KB), UTF-8 chặt (không
 * BOM), độ sâu ≤ 8, chuỗi ≤ 200 ký tự (tên ≤ 40), chỉ số nguyên ≤ 9 chữ số, khoá lặp / khoá lạ / null /
 * sai kiểu / ký tự điều khiển ⇒ LỖI (không bao giờ ném ra ngoài, không `!!`). Không mã: chỉ màu, số,
 * vài giá trị liệt kê và URL tệp tải về (đã kiểm). IME chỉ đọc bản app đã chuẩn hoá và vẫn kiểm lại —
 * hỏng thì về theme có sẵn / Hệ thống.
 *
 * "font" chuỗi ([KeyLabelFont]): "default" | "rounded" | "serif" | "mono" | "condensed" — phông hệ thống — | "pixel" — phông
 *   điểm ảnh NHÚNG (Tiny5, fonts/Tiny5-Regular.ttf, đủ chữ Việt; nạp lười chỉ khi dùng, bỏ qua "weight"). Khác ⇒ badValue.
 * "keyShape" (tuỳ chọn, danh sách trắng [ThemeExtraIds.KEY_SHAPES]): dáng phím — "pixel" = góc cắt bậc thang theo khối,
 *   viền khối đậm + bóng khối cứng dưới/phải, bấm = phím lún một khối (mất bóng) — [PixelKeys], vẽ vài hình chữ nhật mỗi
 *   phím, 0 cấp phát; theme khác không chạm tới. Không có ⇒ bo góc theo "corner" như cũ. iOS y hệt.
 * "borderFx" (trong "light"/"dark", danh sách trắng [ThemeSlots.BORDER_FX]): "rainbow" = viền phím cầu vồng (Gaming RGB,
 *   chỉ xoay màu khi đang gõ) | "aurora" = viền gradient tím → lam ĐỨNG YÊN + dải cực quang tĩnh dọc mép trên (theme AI,
 *   [AuroraFx]; vẽ một lần, 0 hoạt ảnh) | "none" (bản vá: bỏ). Motif "deco" có thêm "neural" (theme AI).
 * "schedule" (tuỳ chọn): bảng màu đổi theo giờ địa phương (theme "Theo giờ") — xem [ThemeSchedule] / [ThemeScheduleEntry].
 *
 * Tệp tải về (Plus — ThemeAssets.kt: kế hoạch / kho / dọn; app ui/ThemeAssetDownloader.kt: tải + xử lý):
 *   "font": "serif" | {"name":"Nunito","url":"https://….ttf|otf","sha256":"…"?}
 *   "background": {"url":"https://…","sha256":"…"?}      ảnh nền theme (ảnh nền tự đặt của người dùng thắng)
 *   "foreground": {"url":"https://…","sha256":"…"?}      PNG/WebP trong suốt TRÊN phím, căng đúng cỡ bàn phím
 *   "keys": {"default"|"special"|"space"|"return"|"shift"|"delete"|"a"…"z":
 *            {"url","sha256"?,"slice":[t,l,b,r]? (9-slice, px ảnh gốc),"pressed":{"url","sha256"?}?}}
 * Chỉ https, không user/cổng, host có dấu chấm; ≤ 16 ảnh khác nhau, ≤ 20 tệp. JSON chỉ là CHỈ DẪN: dán /
 * đọc không bao giờ tự tải — app hỏi trước rồi mới tải; bàn phím không bao giờ dùng mạng.
 *
 * "photoFx" (tuỳ chọn, danh sách trắng [ThemeExtraIds.PHOTO_FX]): hiệu ứng trên ẢNH NỀN chạy KHI theme này đang dùng —
 * "spotlight" = Đèn rọi (Spotlight.kt + app ime/SpotlightView): ảnh nền người dùng tối gần đen, mỗi phím bấm rọi một quầng
 * sáng mềm (tô nhẹ hồng / tím / lục lam xoay vòng) quanh chỗ chạm rồi tắt dần ~0,8 s, tối đa 6 quầng; gõ nhanh ⇒ to +
 * sáng hơn. Không có ảnh nền ⇒ quầng sáng rọi lên hoạ tiết neon tối; quả cầu disco nhỏ ở góc trên xoay + toả chấm sáng.
 * Như "game": không ghi gì lúc chọn theme, IME đọc từ kiểu thực dùng ([SpotlightPolicy]); theme tự tạo dùng được.
 * iOS ThemeSpec.swift y hệt.
 */

// ---- Lỗi / cảnh báo

data class ThemeIssue(val code: Code, val path: String = "") {
    enum class Code {
        tooLarge, encoding, syntax, depth, duplicateKey, unknownKey, missingKey, wrongType,
        badColor, badNumber, tooLong, badValue, badVersion, controlChar, clamped, lowContrast,
        contrastTooLow, tooMany, bgKept, badUrl, tooManyFiles
    }
    val isError: Boolean get() = code != Code.clamped && code != Code.lowContrast && code != Code.bgKept

    /** Thông báo theo ngôn ngữ giao diện (L10n) — tiếng Việt + tiếng Anh. */
    val message: String get() = when (code) {
        Code.tooLarge -> tr("Quá lớn (tối đa 16 KB).")
        Code.encoding -> tr("Không phải văn bản UTF-8 hợp lệ.")
        Code.syntax -> tr("JSON sai cú pháp ở %s (dòng:cột).", path)
        Code.depth -> tr("JSON lồng quá sâu.")
        Code.duplicateKey -> tr("Khoá bị lặp: %s", path)
        Code.unknownKey -> tr("Khoá không hỗ trợ: %s", path)
        Code.missingKey -> tr("Thiếu khoá bắt buộc: %s", path)
        Code.wrongType -> tr("Sai kiểu giá trị: %s", path)
        Code.badColor -> tr("Màu không hợp lệ ở %s (dùng #RRGGBB hoặc #AARRGGBB).", path)
        Code.badNumber -> tr("Số không hợp lệ ở %s (chỉ số nguyên).", path)
        Code.tooLong -> tr("Chuỗi quá dài ở %s.", path)
        Code.badValue -> tr("Giá trị không hỗ trợ ở %s.", path)
        Code.badVersion -> tr("Phiên bản định dạng không hỗ trợ (cần \"v\": 1).")
        Code.controlChar -> tr("Có ký tự điều khiển trong chuỗi.")
        Code.clamped -> tr("Đã đưa %s về khoảng cho phép.", path)
        Code.lowContrast -> tr("Tương phản thấp ở %s (nên ≥ 3:1).", path)
        Code.contrastTooLow -> tr("Tương phản quá thấp ở %s (tối thiểu 2:1).", path)
        Code.tooMany -> tr("Đã đủ %s giao diện tự tạo — xoá bớt trước khi dán.", path)
        Code.bgKept -> tr("Giao diện có sẵn này luôn có nền — đã giữ nền gốc.")
        Code.badUrl -> tr("Địa chỉ tệp không hợp lệ ở %s (chỉ https://, phông .ttf/.otf).", path)
        Code.tooManyFiles -> tr("Quá nhiều tệp tải về (%s).", path)
    }
}

// ---- JSON chặt

/** Cây JSON đã đọc (object giữ thứ tự). Số: chỉ nguyên. */
sealed class SJ {
    data class Obj(val m: List<Pair<String, SJ>>) : SJ() {
        operator fun get(k: String): SJ? = m.firstOrNull { it.first == k }?.second
    }
    data class Arr(val a: List<SJ>) : SJ()
    data class Str(val s: String) : SJ()
    data class Num(val v: Int) : SJ()
    data class Bool(val b: Boolean) : SJ()
    object Null : SJ()

    /** Chuỗi CHUẨN: khoá sắp xếp, không khoảng trắng; chỉ escape `"` và `\` — trùng iOS từng ký tự. */
    val canonical: String get() = StringBuilder().also { write(it) }.toString()
    private fun write(o: StringBuilder) {
        when (this) {
            is Obj -> { o.append('{'); m.sortedBy { it.first }.forEachIndexed { i, (k, v) -> if (i > 0) o.append(','); str(k, o); o.append(':'); v.write(o) }; o.append('}') }
            is Arr -> { o.append('['); a.forEachIndexed { i, v -> if (i > 0) o.append(','); v.write(o) }; o.append(']') }
            is Str -> str(s, o)
            is Num -> o.append(v)
            is Bool -> o.append(if (b) "true" else "false")
            Null -> o.append("null")
        }
    }

    /** Bản dễ đọc (thụt 2, khoá sắp xếp) — "Chép JSON" và trình sửa. */
    val pretty: String get() = StringBuilder().also { writePretty(it, 0) }.toString()
    private fun writePretty(o: StringBuilder, depth: Int) {
        val pad = "  ".repeat(depth + 1); val end = "  ".repeat(depth)
        when {
            this is Obj && m.isNotEmpty() -> {
                o.append("{\n")
                m.sortedBy { it.first }.forEachIndexed { i, (k, v) -> if (i > 0) o.append(",\n"); o.append(pad); str(k, o); o.append(": "); v.writePretty(o, depth + 1) }
                o.append('\n').append(end).append('}')
            }
            this is Arr && a.isNotEmpty() -> {
                o.append("[\n")
                a.forEachIndexed { i, v -> if (i > 0) o.append(",\n"); o.append(pad); v.writePretty(o, depth + 1) }
                o.append('\n').append(end).append(']')
            }
            else -> write(o)
        }
    }

    companion object {
        private fun str(s: String, o: StringBuilder) {
            o.append('"')
            for (c in s) when {
                c == '"' -> o.append("\\\"")
                c == '\\' -> o.append("\\\\")
                c.code < 0x20 -> o.append(String.format("\\u%04x", c.code))
                else -> o.append(c)
            }
            o.append('"')
        }
    }
}

object StrictJson {
    data class Limits(val maxBytes: Int = 16 * 1024, val maxDepth: Int = 8, val maxString: Int = 200, val maxMembers: Int = 64)

    sealed class Result {
        data class Ok(val v: SJ) : Result()
        data class Err(val issue: ThemeIssue) : Result()
    }

    private class Fail(val issue: ThemeIssue) : Exception() {
        override fun fillInStackTrace(): Throwable = this   // rẻ — chỉ dùng điều khiển luồng
    }

    /** Đọc BYTES (UTF-8 chặt, không BOM). Cỡ kiểm TRƯỚC khi giải mã. */
    fun parse(bytes: ByteArray, limits: Limits = Limits()): Result {
        if (bytes.size > limits.maxBytes) return Result.Err(ThemeIssue(ThemeIssue.Code.tooLarge))
        if (bytes.size >= 3 && bytes[0] == 0xEF.toByte() && bytes[1] == 0xBB.toByte() && bytes[2] == 0xBF.toByte())
            return Result.Err(ThemeIssue(ThemeIssue.Code.encoding, "BOM"))
        val text = try {
            Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString()
        } catch (e: CharacterCodingException) { return Result.Err(ThemeIssue(ThemeIssue.Code.encoding)) }
        return parseText(text, limits)
    }

    /** Đọc CHUỖI (clipboard / prefs). Cỡ = số byte UTF-8, kiểm trước khi duyệt. */
    fun parse(s: String, limits: Limits = Limits()): Result {
        if (utf8Size(s, limits.maxBytes + 1) > limits.maxBytes) return Result.Err(ThemeIssue(ThemeIssue.Code.tooLarge))
        if (s.isNotEmpty() && s[0] == '﻿') return Result.Err(ThemeIssue(ThemeIssue.Code.encoding, "BOM"))
        return parseText(s, limits)
    }

    /** Số byte UTF-8 (dừng sớm khi vượt `cap`) — không cấp phát mảng byte. */
    private fun utf8Size(s: String, cap: Int): Int {
        var n = 0; var i = 0
        while (i < s.length && n <= cap) {
            val c = s[i]
            n += when {
                c.code < 0x80 -> 1
                c.code < 0x800 -> 2
                Character.isHighSurrogate(c) && i + 1 < s.length && Character.isLowSurrogate(s[i + 1]) -> { i++; 4 }
                else -> 3
            }
            i++
        }
        return n
    }

    private fun parseText(text: String, limits: Limits): Result {
        // Mảng code point; nửa surrogate lẻ (chuỗi Java hỏng) ⇒ lỗi mã hoá.
        val cps = IntArray(text.length)
        var n = 0; var i = 0
        while (i < text.length) {
            val c = text[i]
            if (Character.isHighSurrogate(c)) {
                if (i + 1 >= text.length || !Character.isLowSurrogate(text[i + 1])) return Result.Err(ThemeIssue(ThemeIssue.Code.encoding))
                cps[n++] = Character.toCodePoint(c, text[i + 1]); i += 2; continue
            }
            if (Character.isLowSurrogate(c)) return Result.Err(ThemeIssue(ThemeIssue.Code.encoding))
            cps[n++] = c.code; i++
        }
        val p = P(cps, n, limits)
        return try {
            p.ws()
            val v = p.value(1)
            p.ws()
            if (p.i != n) throw Fail(ThemeIssue(ThemeIssue.Code.syntax, p.i.toString()))
            Result.Ok(v)
        } catch (f: Fail) {
            // Vị trí (chỉ số ký tự) ⇒ "dòng:cột" (1-based) cho người đọc; iOS y hệt.
            val idx = f.issue.path.toIntOrNull()
            Result.Err(if (idx != null && f.issue.code in setOf(ThemeIssue.Code.syntax, ThemeIssue.Code.badNumber, ThemeIssue.Code.tooLong))
                f.issue.copy(path = lineColumn(cps, n, idx)) else f.issue)
        } catch (e: RuntimeException) {
            Result.Err(ThemeIssue(ThemeIssue.Code.syntax))
        }
    }

    /** "dòng:cột" (1-based) của chỉ số [idx] trong dãy code point. */
    fun lineColumn(s: IntArray, n: Int, idx: Int): String {
        var line = 1; var col = 1
        for (k in 0 until minOf(maxOf(0, idx), n)) { if (s[k] == '\n'.code) { line++; col = 1 } else col++ }
        return "$line:$col"
    }

    private class P(val s: IntArray, val n: Int, val limits: Limits) {
        var i = 0
        fun fail(c: ThemeIssue.Code, path: String = "") = Fail(ThemeIssue(c, path))
        val syntax: Fail get() = fail(ThemeIssue.Code.syntax, i.toString())
        fun peek(): Int = if (i < n) s[i] else -1
        fun ws() { while (i < n && (s[i] == ' '.code || s[i] == '\t'.code || s[i] == '\n'.code || s[i] == '\r'.code)) i++ }
        fun expect(c: Char) { if (peek() != c.code) throw syntax; i++ }

        /** `depth` = số object/array đang mở (vượt ⇒ lỗi trước khi đệ quy tiếp — không tràn ngăn xếp). */
        fun value(depth: Int): SJ {
            val c = peek()
            if (c == -1) throw syntax
            if ((c == '{'.code || c == '['.code) && depth > limits.maxDepth) throw fail(ThemeIssue.Code.depth)
            return when (c) {
                '{'.code -> obj(depth)
                '['.code -> arr(depth)
                '"'.code -> SJ.Str(string())
                't'.code -> { literal("true"); SJ.Bool(true) }
                'f'.code -> { literal("false"); SJ.Bool(false) }
                'n'.code -> { literal("null"); SJ.Null }
                '-'.code, in '0'.code..'9'.code -> SJ.Num(number())
                else -> throw syntax
            }
        }

        fun literal(w: String) { for (ch in w) expect(ch) }

        fun number(): Int {
            val start = i
            var neg = false
            if (peek() == '-'.code) { neg = true; i++ }
            var digits = 0; var v = 0
            val first = i
            while (peek() in '0'.code..'9'.code) {
                digits++
                if (digits > 9) throw fail(ThemeIssue.Code.badNumber, start.toString())
                v = v * 10 + (s[i] - '0'.code)
                i++
            }
            if (digits == 0) throw syntax
            if (digits > 1 && s[first] == '0'.code) throw syntax
            val c = peek()
            if (c == '.'.code || c == 'e'.code || c == 'E'.code) throw fail(ThemeIssue.Code.badNumber, start.toString())
            return if (neg) -v else v
        }

        fun hex4(): Int {
            var v = 0
            repeat(4) {
                val d = hexDigit(peek())
                if (d < 0) throw syntax
                v = (v shl 4) or d; i++
            }
            return v
        }
        fun hexDigit(c: Int): Int = when (c) {
            in '0'.code..'9'.code -> c - '0'.code
            in 'a'.code..'f'.code -> c - 'a'.code + 10
            in 'A'.code..'F'.code -> c - 'A'.code + 10
            else -> -1
        }

        fun string(): String {
            expect('"')
            val out = StringBuilder()
            var count = 0
            while (true) {
                val c = peek()
                if (c == -1) throw syntax
                i++
                if (c == '"'.code) break
                val cp: Int = if (c == '\\'.code) {
                    val e = peek()
                    if (e == -1) throw syntax
                    i++
                    when (e) {
                        '"'.code -> '"'.code
                        '\\'.code -> '\\'.code
                        '/'.code -> '/'.code
                        'b'.code, 'f'.code, 'n'.code, 'r'.code, 't'.code -> throw fail(ThemeIssue.Code.controlChar)
                        'u'.code -> {
                            val u = hex4()
                            if (u in 0xD800..0xDBFF) {
                                if (peek() != '\\'.code) throw fail(ThemeIssue.Code.encoding)
                                i++
                                if (peek() != 'u'.code) throw fail(ThemeIssue.Code.encoding)
                                i++
                                val lo = hex4()
                                if (lo !in 0xDC00..0xDFFF) throw fail(ThemeIssue.Code.encoding)
                                0x10000 + ((u - 0xD800) shl 10) + (lo - 0xDC00)
                            } else if (u in 0xDC00..0xDFFF) throw fail(ThemeIssue.Code.encoding)
                            else u
                        }
                        else -> throw syntax
                    }
                } else c
                if (cp < 0x20 || cp == 0x7F) throw fail(ThemeIssue.Code.controlChar)
                count++
                if (count > limits.maxString) throw fail(ThemeIssue.Code.tooLong, i.toString())
                out.appendCodePoint(cp)
            }
            return out.toString()
        }

        fun obj(depth: Int): SJ {
            expect('{')
            val members = ArrayList<Pair<String, SJ>>()
            val seen = HashSet<String>()
            ws()
            if (peek() == '}'.code) { i++; return SJ.Obj(members) }
            while (true) {
                ws()
                if (peek() != '"'.code) throw syntax
                val k = string()
                if (!seen.add(k)) throw fail(ThemeIssue.Code.duplicateKey, k)
                ws(); expect(':'); ws()
                members.add(k to value(depth + 1))
                if (members.size > limits.maxMembers) throw fail(ThemeIssue.Code.tooLarge)
                ws()
                if (peek() == ','.code) { i++; continue }
                expect('}')
                return SJ.Obj(members)
            }
        }

        fun arr(depth: Int): SJ {
            expect('[')
            val items = ArrayList<SJ>()
            ws()
            if (peek() == ']'.code) { i++; return SJ.Arr(items) }
            while (true) {
                ws()
                items.add(value(depth + 1))
                if (items.size > limits.maxMembers) throw fail(ThemeIssue.Code.tooLarge)
                ws()
                if (peek() == ','.code) { i++; continue }
                expect(']')
                return SJ.Arr(items)
            }
        }
    }
}

// ---- Màu

object ThemeColorCode {
    /** "#RRGGBB" (đục) hoặc "#AARRGGBB" → ARGB; sai ⇒ null. */
    fun parse(s: String): Int? {
        if ((s.length != 7 && s.length != 9) || s[0] != '#') return null
        var v = 0L
        for (k in 1 until s.length) {
            val c = s[k]
            val d = when (c) { in '0'..'9' -> c - '0'; in 'a'..'f' -> c - 'a' + 10; in 'A'..'F' -> c - 'A' + 10; else -> return null }
            v = (v shl 4) or d.toLong()
        }
        return if (s.length == 7) (0xFF000000L or v).toInt() else v.toInt()
    }
    /** Đục ⇒ "#RRGGBB", có alpha ⇒ "#AARRGGBB" — chữ hoa. */
    fun format(v: Int): String = if ((v ushr 24) == 0xFF) String.format("#%06X", v and 0xFFFFFF) else String.format("#%08X", v)
}

// ---- Mô hình

/** motif null = "none" (bỏ hoạ tiết). density % (bước ngang = STEP_X × 100 / density), kẹp 50…200. */
data class ThemeDeco(val motif: String?, val color: Int = 0, val density: Int = 100,
                     /** Motif thứ hai xen kẽ ("alt", tuỳ chọn) — chỉ có khi [motif] khác null. iOS ThemeDeco.alt. */
                     val alt: String? = null) {
    companion object { val DENSITY_RANGE = 50..200; val MOTIFS = ThemeDecoration.MOTIFS.toSet() }
}

/** Màu một chế độ (ARGB). Theme đầy đủ bắt buộc key / special / ink / accent; bản vá mọi trường tuỳ chọn. bg null = theo hệ thống. */
data class ThemeSlots(
    val bg: Int? = null, val key: Int? = null, val special: Int? = null, val ink: Int? = null, val accent: Int? = null,
    val accentInk: Int? = null, val border: Int? = null, val fn: Int? = null, val fnInk: Int? = null,
    val balloon: Int? = null, val trail: Int? = null, val deco: ThemeDeco? = null,
    /** Hiệu ứng viền phím: "rainbow" (Gaming RGB — chỉ xoay màu khi đang gõ) | "none" (bản vá: bỏ). iOS y hệt. */
    val borderFx: String? = null,
    /**
     * Hình vẽ trên phím cách: "soundhole" (Ghi-ta — lỗ thoát âm + vành hoa văn, vẽ một lần cùng nền phím) | "none"
     * (bản vá: bỏ). iOS y hệt. Skin ảnh ("keys") là tệp tải về ⇒ theme có sẵn dùng slot tối giản này.
     */
    val spaceDeco: String? = null,
) {
    val isEmpty: Boolean get() = this == ThemeSlots()

    fun color(k: String): Int? = when (k) {
        "bg" -> bg; "key" -> key; "special" -> special; "ink" -> ink; "accent" -> accent; "accentInk" -> accentInk
        "border" -> border; "fn" -> fn; "fnInk" -> fnInk; "balloon" -> balloon; "trail" -> trail; else -> null
    }
    fun with(k: String, v: Int?): ThemeSlots = when (k) {
        "bg" -> copy(bg = v); "key" -> copy(key = v); "special" -> copy(special = v); "ink" -> copy(ink = v)
        "accent" -> copy(accent = v); "accentInk" -> copy(accentInk = v); "border" -> copy(border = v); "fn" -> copy(fn = v)
        "fnInk" -> copy(fnInk = v); "balloon" -> copy(balloon = v); "trail" -> copy(trail = v); else -> this
    }

    /** Bản vá biến `base` thành `this` — y hệt iOS ThemeSlots.patch(from:). */
    fun patchFrom(base: ThemeSlots): Pair<ThemeSlots, Boolean> {
        var p = ThemeSlots()
        var lostBg = false
        for (k in COLOR_KEYS) {
            val mine = color(k); val theirs = base.color(k)
            if (mine == theirs) continue
            if (mine != null) { p = p.with(k, mine); continue }
            when (k) {
                "border" -> p = p.copy(border = 0)
                "fn" -> p = p.copy(fn = key ?: base.key)
                "fnInk" -> p = p.copy(fnInk = ink ?: base.ink)
                "bg" -> lostBg = true
            }
        }
        if (deco != base.deco) p = p.copy(deco = deco ?: ThemeDeco(null))
        if (borderFx != base.borderFx) p = p.copy(borderFx = borderFx ?: "none")
        if (spaceDeco != base.spaceDeco) p = p.copy(spaceDeco = spaceDeco ?: "none")
        return p to lostBg
    }

    companion object {
        val COLOR_KEYS = listOf("accent", "accentInk", "balloon", "bg", "border", "fn", "fnInk", "ink", "key", "special", "trail")
        val REQUIRED = listOf("key", "special", "ink", "accent")
        const val RAINBOW = "rainbow"
        /** Giá trị hợp lệ của "borderFx" (iOS ThemeSlots.borderFxValues y hệt). */
        /** Theme AI: viền gradient tĩnh + dải cực quang mép trên ([AuroraFx]). */
        const val AURORA = "aurora"
        val BORDER_FX = setOf(RAINBOW, AURORA, "none")
        const val SOUNDHOLE = "soundhole"
        /** Giá trị hợp lệ của "spaceDeco" (iOS ThemeSlots.spaceDecoValues y hệt). */
        val SPACE_DECO = setOf(SOUNDHOLE, "none")
    }
}

// ---- Tệp tải về (mô hình — iOS ThemeSpec.swift y hệt)

/** Một tệp: URL https (đã kiểm) + sha256 (64 hex chữ thường) nếu có. */
data class ThemeAssetRef(val url: String, val sha256: String? = null)

/** Phông tải về: tên hiển thị + tệp .ttf/.otf. */
data class ThemeFontAsset(val name: String, val ref: ThemeAssetRef)

/** Skin một phím / nhóm phím: ảnh (9-slice theo [slice] = [trên, trái, dưới, phải] px ẢNH GỐC) + ảnh khi đè. */
data class ThemeKeySkin(val image: ThemeAssetRef, val slice: List<Int>? = null, val pressed: ThemeAssetRef? = null)

/**
 * Phần "tệp tải về" của theme (font / ảnh nền / tiền cảnh / skin phím). Nằm ở ThemeSpec lẫn KeyStyle (bản vá
 * theme có sẵn) — cùng bộ đọc ([ThemeSpecParser] typography).
 */
data class ThemeAssetSpec(
    val font: ThemeFontAsset? = null,
    val background: ThemeAssetRef? = null,
    val foreground: ThemeAssetRef? = null,
    val keys: Map<String, ThemeKeySkin> = emptyMap(),
) {
    val isEmpty: Boolean get() = font == null && background == null && foreground == null && keys.isEmpty()
    val hasImages: Boolean get() = background != null || foreground != null || keys.isNotEmpty()

    /** `this` thắng từng trường; skin phím: có bộ nào thì thay CẢ bộ (không trộn hai bộ skin). */
    fun mergedOver(base: ThemeAssetSpec): ThemeAssetSpec = ThemeAssetSpec(
        font = font ?: base.font, background = background ?: base.background,
        foreground = foreground ?: base.foreground, keys = keys.ifEmpty { base.keys })

    companion object {
        val GROUP_KEYS = listOf("default", "special")
        val NAMED_KEYS = listOf("space", "return", "shift", "delete")
        val LETTER_KEYS = ('a'..'z').map { it.toString() }
        val SKIN_KEYS: Set<String> = (GROUP_KEYS + NAMED_KEYS + LETTER_KEYS).toSet()
        const val MAX_IMAGES = 16
        const val MAX_FILES = 20
        const val MAX_SLICE = 1024
        const val NAME_MAX = 40
    }
}

/**
 * Kiểm URL tệp (thuần, iOS y hệt): https://host/đường-dẫn, ASCII in được, không khoảng trắng / gạch chéo
 * ngược / user@ / cổng; host chữ thường a-z 0-9 . -, có dấu chấm, không phải IP số; phông: đường dẫn kết thúc
 * .ttf/.otf.
 */
object ThemeAssetURL {
    const val PREFIX = "https://"

    fun isValid(s: String, font: Boolean): Boolean {
        if (!s.startsWith(PREFIX)) return false
        val bytes = s.toByteArray(Charsets.UTF_8)
        if (bytes.size > 200) return false
        for (b in bytes) {
            val v = b.toInt() and 0xFF
            if (v <= 0x20 || v >= 0x7F || v == 0x5C || v == 0x22) return false
        }
        val rest = s.substring(PREFIX.length)
        val hostEnd = rest.indexOfFirst { it == '/' || it == '?' || it == '#' }
        if (hostEnd < 0 || rest[hostEnd] != '/') return false
        val host = rest.substring(0, hostEnd)
        if (host.isEmpty() || host.length > 253) return false
        var dot = false
        var allNumeric = true
        for (ch in host) when (ch) {
            in 'a'..'z', '-' -> allNumeric = false
            in '0'..'9' -> {}
            '.' -> dot = true
            else -> return false   // chữ hoa, @, :, [ …
        }
        if (!dot || allNumeric || host.first() == '.' || host.last() == '.' || host.first() == '-') return false
        if (font) {
            val path = s.split('?', '#').first().lowercase()
            if (!path.endsWith(".ttf") && !path.endsWith(".otf")) return false
        }
        return true
    }

    /** Tên miền (hiện trong câu hỏi trước khi tải). */
    fun host(s: String): String = s.removePrefix(PREFIX).takeWhile { it != '/' && it != '?' && it != '#' }

    /** "64 hex" (hoa / thường) ⇒ chữ thường; sai ⇒ null. */
    fun sha256(s: String): String? =
        if (s.length == 64 && s.all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' }) s.lowercase() else null
}

/** Một mục "schedule": từ phút [from] trong ngày (0…1439) dùng bảng màu [slots] (đầy đủ như "light"). iOS y hệt. */
data class ThemeScheduleEntry(val from: Int, val slots: ThemeSlots)

/**
 * "schedule" (tuỳ chọn, 2…6 mục, "from" tăng dần): bảng màu ĐỔI THEO GIỜ ĐỊA PHƯƠNG (theme "Theo giờ") —
 * `"schedule":[{"from":"05:00","palette":{…như "light"…}}, …]`. Mục có "from" lớn nhất ≤ giờ hiện tại thắng; trước mục
 * đầu ⇒ mục CUỐI (qua nửa đêm). Có lịch ⇒ bỏ qua sáng/tối hệ thống; "light"/"dark" vẫn bắt buộc (bảng dự phòng khi
 * không có giờ). Chọn MỘT lần lúc bàn phím hiện — 0 chi phí mỗi phím, không hẹn giờ. Thuần — iOS ThemeSchedule y hệt.
 */
object ThemeSchedule {
    val ENTRY_RANGE = 2..6
    const val MINUTES_PER_DAY = 24 * 60

    /** "HH:MM" (đúng 5 ký tự, 00…23 : 00…59) ⇒ phút trong ngày; sai ⇒ null. */
    fun parseTime(s: String): Int? {
        if (s.length != 5 || s[2] != ':') return null
        val d = intArrayOf(0, 1, 3, 4).map { i -> s[i].takeIf { it in '0'..'9' }?.let { it - '0' } ?: return null }
        val h = d[0] * 10 + d[1]; val m = d[2] * 10 + d[3]
        return if (h < 24 && m < 60) h * 60 + m else null
    }
    fun format(minute: Int): String = String.format(java.util.Locale.ROOT, "%02d:%02d", minute / 60, minute % 60)

    /** Chỉ số mục hiệu lực ở phút [minute] (kẹp vào ngày); trước mục đầu ⇒ mục cuối. [froms] rỗng ⇒ null. */
    fun index(froms: List<Int>, minute: Int): Int? {
        if (froms.isEmpty()) return null
        val m = ((minute % MINUTES_PER_DAY) + MINUTES_PER_DAY) % MINUTES_PER_DAY
        var best = froms.size - 1
        for ((i, f) in froms.withIndex()) if (f <= m) best = i
        return best
    }

    /** Phút trong ngày theo giờ địa phương — gọi MỘT lần mỗi lần hiện bàn phím, chỉ khi theme có lịch. */
    fun minuteOfDay(epochMillis: Long = System.currentTimeMillis(), zone: java.util.TimeZone = java.util.TimeZone.getDefault()): Int {
        val c = java.util.Calendar.getInstance(zone).apply { timeInMillis = epochMillis }
        return c.get(java.util.Calendar.HOUR_OF_DAY) * 60 + c.get(java.util.Calendar.MINUTE)
    }
}

data class ThemeSpec(
    val id: String? = null,
    val nameVi: String,
    val nameEn: String? = null,
    val light: ThemeSlots,
    /** null = "same". */
    val dark: ThemeSlots? = null,
    val corner: Int? = null,
    val fontScale: Int? = null,
    val font: KeyLabelFont? = null,
    val weight: KeyLabelWeight? = null,
    /** Tệp tải về (phông / ảnh nền / tiền cảnh / skin phím). Có `assets.font` ⇒ `font` = null. */
    val assets: ThemeAssetSpec = ThemeAssetSpec(),
    /** Âm phím / hiệu ứng đi kèm (id [ThemeExtraIds]) — chỉ áp lúc chọn theme ([ThemeExtras]). */
    val sound: String? = null,
    val effect: String? = null,
    /** Nét vuốt của theme (id [ThemeExtraIds.SWIPES]) — chỉ dùng khi cài đặt nét vuốt = "Theo giao diện". */
    val swipe: String? = null,
    /** Trò chơi khi gõ ("mole" — [MoleGame]) — chạy khi theme đang dùng ([ThemeExtraIds.GAMES]). iOS `game`. */
    val game: String? = null,
    /** Bảng màu theo giờ ([ThemeSchedule]); null = theo sáng/tối hệ thống. iOS `schedule`. */
    val schedule: List<ThemeScheduleEntry>? = null,
    /** Dáng phím ("pixel" — [ThemeExtraIds.KEY_SHAPES]). iOS `keyShape`. */
    val keyShape: String? = null,
    /** Hiệu ứng trên ảnh nền ("spotlight" — Đèn rọi) — chạy khi theme đang dùng ([ThemeExtraIds.PHOTO_FX]). iOS `photoFx`. */
    val photoFx: String? = null,
) {
    fun slots(dark: Boolean): ThemeSlots = if (dark) (this.dark ?: light) else light
    /** Bảng màu ở phút [minute] trong ngày: có lịch ⇒ mục hiệu lực (bỏ qua sáng/tối); không lịch / null ⇒ [slots]. */
    fun slots(dark: Boolean, minute: Int?): ThemeSlots {
        val sc = schedule ?: return slots(dark)
        val i = minute?.let { ThemeSchedule.index(sc.map { e -> e.from }, it) } ?: return slots(dark)
        return sc[i].slots
    }
    /** Chỉ số mục lịch đang hiệu lực (null = không có lịch). */
    fun scheduleIndex(minute: Int): Int? = schedule?.let { ThemeSchedule.index(it.map { e -> e.from }, minute) }
    /** Palette ở phút [minute] (theme có lịch); null / không lịch ⇒ [palette]. */
    fun palette(dark: Boolean, minute: Int?): ThemePalette =
        if (schedule == null || minute == null) palette(dark) else palette(slots(dark, minute), dark)
    val name: String get() = if (L10n.isEnglish) (nameEn ?: nameVi) else nameVi
    /** Kiểu chữ / bo góc / tệp tải về mặc định của theme. */
    val typography: KeyStyle get() = KeyStyle(corner = corner, fontScale = fontScale, font = font ?: KeyLabelFont.DEFAULT,
        weight = weight ?: KeyLabelWeight.REGULAR, assets = assets, sound = sound, effect = effect, swipe = swipe, game = game,
        keyShape = keyShape, photoFx = photoFx)

    fun palette(dark: Boolean): ThemePalette = palette(slots(dark), dark)

    val json: SJ get() {
        val m = ArrayList<Pair<String, SJ>>()
        m.add("v" to SJ.Num(VERSION))
        id?.let { m.add("id" to SJ.Str(it)) }
        val nm = ArrayList<Pair<String, SJ>>()
        nm.add("vi" to SJ.Str(nameVi))
        nameEn?.let { nm.add("en" to SJ.Str(it)) }
        m.add("name" to SJ.Obj(nm))
        m.add("light" to json(light))
        m.add("dark" to (dark?.let { json(it) } ?: SJ.Str("same")))
        corner?.let { m.add("corner" to SJ.Num(it)) }
        fontScale?.let { m.add("fontScale" to SJ.Num(it)) }
        val fa = assets.font
        if (fa != null) m.add("font" to json(fa)) else font?.let { m.add("font" to SJ.Str(it.id)) }
        weight?.let { m.add("weight" to SJ.Str(it.id)) }
        appendImages(assets, m)
        sound?.let { m.add("sound" to SJ.Str(it)) }
        effect?.let { m.add("effect" to SJ.Str(it)) }
        swipe?.let { m.add("swipe" to SJ.Str(it)) }
        game?.let { m.add("game" to SJ.Str(it)) }
        keyShape?.let { m.add("keyShape" to SJ.Str(it)) }
        photoFx?.let { m.add("photoFx" to SJ.Str(it)) }
        schedule?.let { sc ->
            m.add("schedule" to SJ.Arr(sc.map { SJ.Obj(listOf("from" to SJ.Str(ThemeSchedule.format(it.from)), "palette" to json(it.slots))) }))
        }
        return SJ.Obj(m)
    }
    /** Chuỗi chuẩn (trùng iOS từng ký tự). */
    val canonical: String get() = json.canonical

    companion object {
        const val VERSION = 1
        const val MAX_NAME = 40

        fun json(s: ThemeSlots): SJ {
            val m = ArrayList<Pair<String, SJ>>()
            for (k in ThemeSlots.COLOR_KEYS) s.color(k)?.let { m.add(k to SJ.Str(ThemeColorCode.format(it))) }
            s.deco?.let { d ->
                val dm = ArrayList<Pair<String, SJ>>()
                dm.add("motif" to SJ.Str(d.motif ?: "none"))
                if (d.motif != null) {
                    d.alt?.let { dm.add("alt" to SJ.Str(it)) }
                    dm.add("color" to SJ.Str(ThemeColorCode.format(d.color)))
                    if (d.density != 100) dm.add("density" to SJ.Num(d.density))
                }
                m.add("deco" to SJ.Obj(dm))
            }
            s.borderFx?.let { m.add("borderFx" to SJ.Str(it)) }
            s.spaceDeco?.let { m.add("spaceDeco" to SJ.Str(it)) }
            return SJ.Obj(m)
        }

        fun json(r: ThemeAssetRef, extra: List<Pair<String, SJ>> = emptyList()): SJ {
            val m = ArrayList<Pair<String, SJ>>()
            m.add("url" to SJ.Str(r.url))
            r.sha256?.let { m.add("sha256" to SJ.Str(it)) }
            return SJ.Obj(m + extra)
        }
        fun json(f: ThemeFontAsset): SJ = json(f.ref, listOf("name" to SJ.Str(f.name)))
        fun json(k: ThemeKeySkin): SJ {
            val extra = ArrayList<Pair<String, SJ>>()
            k.slice?.let { s -> extra.add("slice" to SJ.Arr(s.map { SJ.Num(it) })) }
            k.pressed?.let { extra.add("pressed" to json(it)) }
            return json(k.image, extra)
        }
        /** background / foreground / keys (font ghi riêng — chung khoá với phông hệ thống). */
        fun appendImages(a: ThemeAssetSpec, m: MutableList<Pair<String, SJ>>) {
            a.background?.let { m.add("background" to json(it)) }
            a.foreground?.let { m.add("foreground" to json(it)) }
            if (a.keys.isNotEmpty()) m.add("keys" to SJ.Obj(a.keys.map { (k, v) -> k to json(v) }))
        }

        /** Chữ trên nền nhấn tự tính: trắng nếu đọc được (≥ 3:1), không thì đen/trắng tương phản hơn. */
        fun autoAccentInk(accent: Int): Int = KeyboardTransparency.readable(ThemeColor.WHITE, accent)

        /** Palette một chế độ — y hệt iOS ThemeSpec.palette (+ popup = balloon, chip = special như theme cũ). */
        fun palette(s: ThemeSlots, dark: Boolean): ThemePalette {
            val c = ThemeColor
            val key = s.key ?: c.WHITE
            val ink = s.ink ?: c.BLACK
            val accent = s.accent ?: c.rgb(0x007AFF)
            val special = s.special ?: c.rgb(0xCCCCCC)
            val balloon = s.balloon ?: key
            // Nền đục mà chữ theme không đọc được trên nền (Piano: phím ngà chữ đen trên thân đàn đen) ⇒ thanh gợi ý /
            // bảng emoji theo tông NỀN (chữ đen/trắng đọc được), phím vẫn theo ink — iOS y hệt. Theme khác: null.
            val solidBg = s.bg?.let { it or (0xFF shl 24) }
            val barInk = solidBg?.takeIf { c.contrast(ink, it) < KeyboardTransparency.MIN_LABEL_CONTRAST }
                ?.let { KeyboardTransparency.readable(ink, it) }
            return ThemePalette(barInk = barInk, surfaceDark = if (barInk != null && solidBg != null) c.luminance(solidBg) < 0.18 else null,
                bg = s.bg ?: KeyboardTransparency.systemBackdrop(dark), keyFill = key, specialFill = special,
                ink = ink, trail = s.trail ?: c.withAlpha(accent, 0.6f), balloon = balloon, popup = balloon, action = accent,
                actionInk = s.accentInk ?: autoAccentInk(accent), chip = special, keyBorder = s.border,
                isDark = c.luminance(ink) > 0.5, functionFill = s.fn, functionInk = s.fnInk,
                decoration = s.deco?.let { d -> d.motif?.let { ThemeDecoration(it, d.color, d.density, d.alt) } },
                rainbowBorder = s.borderFx == ThemeSlots.RAINBOW, auroraBorder = s.borderFx == ThemeSlots.AURORA,
                spaceSoundhole = s.spaceDeco == ThemeSlots.SOUNDHOLE)
        }

        /** Palette (đã giải) → màu một chế độ; bỏ trường bằng mặc định tự tính. */
        fun slots(p: ThemePalette): ThemeSlots {
            val c = ThemeColor
            return ThemeSlots(bg = p.bg, key = p.keyFill, special = p.specialFill, ink = p.ink, accent = p.action,
                accentInk = p.actionInk.takeIf { it != autoAccentInk(p.action) }, border = p.keyBorder,
                fn = p.functionFill, fnInk = p.functionInk, balloon = p.balloon.takeIf { it != p.keyFill },
                trail = p.trail.takeIf { it != c.withAlpha(p.action, 0.6f) },
                deco = p.decoration?.let { ThemeDeco(it.motif, it.color, it.density, it.alt) },
                borderFx = if (p.rainbowBorder) ThemeSlots.RAINBOW else if (p.auroraBorder) ThemeSlots.AURORA else null,
                spaceDeco = if (p.spaceSoundhole) ThemeSlots.SOUNDHOLE else null)
        }

        /** Theme đầy đủ từ palette sáng/tối đã giải + kiểu chữ ("Chép JSON"). */
        fun export(id: String?, nameVi: String, nameEn: String?, light: ThemePalette, dark: ThemePalette, style: KeyStyle): ThemeSpec {
            val l = slots(light); val d = slots(dark)
            return ThemeSpec(id, nameVi, nameEn, l, if (d == l) null else d, style.corner, style.fontScale,
                style.font.takeIf { it != KeyLabelFont.DEFAULT && style.assets.font == null },
                style.weight.takeIf { it != KeyLabelWeight.REGULAR }, style.assets, style.sound, style.effect, style.swipe, style.game,
                keyShape = style.keyShape, photoFx = style.photoFx)
        }
    }
}

// ---- Đọc / kiểm

object ThemeSpecParser {
    data class Outcome(val spec: ThemeSpec?, val issues: List<ThemeIssue>) {
        val errors: List<ThemeIssue> get() = issues.filter { it.isError }
    }

    private class Ctx {
        val issues = ArrayList<ThemeIssue>()
        fun err(c: ThemeIssue.Code, p: String) { issues.add(ThemeIssue(c, p)) }
        val failed: Boolean get() = issues.any { it.isError }
    }

    private val ASSET_KEYS = setOf("background", "foreground", "keys")
    private val ROOT_KEYS = setOf("v", "id", "name", "light", "dark", "corner", "fontScale", "font", "weight",
        "sound", "effect", "swipe", "game", "keyShape", "schedule", "photoFx") + ASSET_KEYS
    private val SLOT_KEYS = (ThemeSlots.COLOR_KEYS + "deco" + "borderFx" + "spaceDeco").toSet()

    fun parse(text: String): Outcome = when (val r = StrictJson.parse(text)) {
        is StrictJson.Result.Err -> Outcome(null, listOf(r.issue))
        is StrictJson.Result.Ok -> spec(r.v, contrast = true)
    }
    fun parse(bytes: ByteArray): Outcome = when (val r = StrictJson.parse(bytes)) {
        is StrictJson.Result.Err -> Outcome(null, listOf(r.issue))
        is StrictJson.Result.Ok -> spec(r.v, contrast = true)
    }

    fun spec(j: SJ, contrast: Boolean): Outcome {
        if (j !is SJ.Obj) return Outcome(null, listOf(ThemeIssue(ThemeIssue.Code.wrongType, "$")))
        val c = Ctx()
        for ((k, _) in j.m) if (k !in ROOT_KEYS) c.err(ThemeIssue.Code.unknownKey, k)
        when (val v = j["v"]) {
            null -> c.err(ThemeIssue.Code.missingKey, "v")
            is SJ.Num -> if (v.v != 1) c.err(ThemeIssue.Code.badVersion, "v")
            else -> c.err(ThemeIssue.Code.wrongType, "v")
        }
        var id: String? = null
        j["id"]?.let { v ->
            if (v is SJ.Str) { if (KeyStyleStore.validId(v.s)) id = v.s else c.err(ThemeIssue.Code.badValue, "id") }
            else c.err(ThemeIssue.Code.wrongType, "id")
        }
        var vi = ""; var en: String? = null
        when (val nm = j["name"]) {
            null -> c.err(ThemeIssue.Code.missingKey, "name")
            is SJ.Obj -> {
                for ((k, _) in nm.m) if (k != "vi" && k != "en") c.err(ThemeIssue.Code.unknownKey, "name.$k")
                vi = name(nm["vi"], "name.vi", true, c) ?: ""
                en = name(nm["en"], "name.en", false, c)
            }
            else -> c.err(ThemeIssue.Code.wrongType, "name")
        }
        var light = ThemeSlots()
        when (val v = j["light"]) {
            null -> c.err(ThemeIssue.Code.missingKey, "light")
            else -> light = slots(v, "light", true, c)
        }
        var dark: ThemeSlots? = null
        when (val v = j["dark"]) {
            null -> {}
            is SJ.Str -> if (v.s != "same") c.err(ThemeIssue.Code.badValue, "dark")
            else -> dark = slots(v, "dark", true, c)
        }
        val typo = typography(j, KeyStyle(), c)
        val schedule = j["schedule"]?.let { schedule(it, c) }
        if (c.failed) return Outcome(null, c.issues)
        val spec = ThemeSpec(id, vi, en, light, if (dark == light) null else dark, typo.corner, typo.fontScale,
            if (j["font"] != null && typo.assets.font == null) typo.font else null,
            if (j["weight"] != null) typo.weight else null, typo.assets, typo.sound, typo.effect, typo.swipe, typo.game,
            schedule, typo.keyShape, photoFx = typo.photoFx)
        if (contrast) c.issues.addAll(contrastIssues(spec))
        return Outcome(if (c.failed) null else spec, c.issues)
    }

    /** "schedule": mảng 2…6 {"from":"HH:MM","palette":{màu đầy đủ}}, "from" tăng dần — iOS y hệt. */
    private fun schedule(v: SJ, c: Ctx): List<ThemeScheduleEntry>? {
        if (v !is SJ.Arr) { c.err(ThemeIssue.Code.wrongType, "schedule"); return null }
        if (v.a.size !in ThemeSchedule.ENTRY_RANGE) { c.err(ThemeIssue.Code.badValue, "schedule"); return null }
        val out = ArrayList<ThemeScheduleEntry>()
        for ((i, e) in v.a.withIndex()) {
            val p = "schedule[$i]"
            if (e !is SJ.Obj) { c.err(ThemeIssue.Code.wrongType, p); continue }
            for ((k, _) in e.m) if (k != "from" && k != "palette") c.err(ThemeIssue.Code.unknownKey, "$p.$k")
            var from: Int? = null
            when (val f = e["from"]) {
                null -> c.err(ThemeIssue.Code.missingKey, "$p.from")
                is SJ.Str -> ThemeSchedule.parseTime(f.s)?.let { from = it } ?: c.err(ThemeIssue.Code.badValue, "$p.from")
                else -> c.err(ThemeIssue.Code.wrongType, "$p.from")
            }
            val last = out.lastOrNull()?.from
            if (from != null && last != null && from!! <= last) { c.err(ThemeIssue.Code.badValue, "$p.from"); from = null }
            val pv = e["palette"]
            if (pv == null) { c.err(ThemeIssue.Code.missingKey, "$p.palette"); continue }
            val sl = slots(pv, "$p.palette", true, c)
            from?.let { out.add(ThemeScheduleEntry(it, sl)) }
        }
        return if (out.size == v.a.size) out else null
    }

    private fun name(v: SJ?, p: String, required: Boolean, c: Ctx): String? {
        if (v == null) { if (required) c.err(ThemeIssue.Code.missingKey, p); return null }
        if (v !is SJ.Str) { c.err(ThemeIssue.Code.wrongType, p); return null }
        val t = v.s.trim()
        if (t.isEmpty()) { c.err(ThemeIssue.Code.badValue, p); return null }
        if (t.codePointCount(0, t.length) > ThemeSpec.MAX_NAME) { c.err(ThemeIssue.Code.tooLong, p); return null }
        return t
    }

    private fun slots(v: SJ, p: String, full: Boolean, c: Ctx): ThemeSlots {
        if (v !is SJ.Obj) { c.err(ThemeIssue.Code.wrongType, p); return ThemeSlots() }
        var s = ThemeSlots()
        for ((k, value) in v.m) {
            val path = "$p.$k"
            if (k == "deco") { s = s.copy(deco = deco(value, path, c)); continue }
            if (k == "borderFx") {
                when {
                    value !is SJ.Str -> c.err(ThemeIssue.Code.wrongType, path)
                    value.s !in ThemeSlots.BORDER_FX -> c.err(ThemeIssue.Code.badValue, path)
                    else -> s = s.copy(borderFx = value.s)
                }
                continue
            }
            if (k == "spaceDeco") {
                when {
                    value !is SJ.Str -> c.err(ThemeIssue.Code.wrongType, path)
                    value.s !in ThemeSlots.SPACE_DECO -> c.err(ThemeIssue.Code.badValue, path)
                    else -> s = s.copy(spaceDeco = value.s)
                }
                continue
            }
            if (k !in SLOT_KEYS) { c.err(ThemeIssue.Code.unknownKey, path); continue }
            if (value !is SJ.Str) { c.err(ThemeIssue.Code.wrongType, path); continue }
            val col = ThemeColorCode.parse(value.s)
            if (col == null) { c.err(ThemeIssue.Code.badColor, path); continue }
            s = s.with(k, col)
        }
        if (full) for (k in ThemeSlots.REQUIRED) if (s.color(k) == null && v[k] == null) c.err(ThemeIssue.Code.missingKey, "$p.$k")
        return s
    }

    private fun deco(v: SJ, p: String, c: Ctx): ThemeDeco? {
        if (v !is SJ.Obj) { c.err(ThemeIssue.Code.wrongType, p); return null }
        for ((k, _) in v.m) if (k !in setOf("motif", "alt", "color", "density")) c.err(ThemeIssue.Code.unknownKey, "$p.$k")
        var motif: String? = null
        when (val m = v["motif"]) {
            null -> { c.err(ThemeIssue.Code.missingKey, "$p.motif"); return null }
            is SJ.Str -> when {
                m.s == "none" -> motif = null
                m.s in ThemeDeco.MOTIFS -> motif = m.s
                else -> { c.err(ThemeIssue.Code.badValue, "$p.motif"); return null }
            }
            else -> { c.err(ThemeIssue.Code.wrongType, "$p.motif"); return null }
        }
        var color = 0
        val cv = v["color"]
        if (motif != null) {
            when (cv) {
                null -> { c.err(ThemeIssue.Code.missingKey, "$p.color"); return null }
                is SJ.Str -> color = ThemeColorCode.parse(cv.s) ?: run { c.err(ThemeIssue.Code.badColor, "$p.color"); return null }
                else -> { c.err(ThemeIssue.Code.wrongType, "$p.color"); return null }
            }
        } else if (cv != null && (cv !is SJ.Str || ThemeColorCode.parse(cv.s) == null)) c.err(ThemeIssue.Code.badColor, "$p.color")
        // "alt": motif thứ hai xen kẽ (không "none"; bỏ qua khi motif = "none") — như iOS.
        var alt: String? = null
        when (val av = v["alt"]) {
            null -> {}
            is SJ.Str -> if (av.s in ThemeDeco.MOTIFS) { if (motif != null) alt = av.s }
                else { c.err(ThemeIssue.Code.badValue, "$p.alt"); return null }
            else -> { c.err(ThemeIssue.Code.wrongType, "$p.alt"); return null }
        }
        var density = 100
        when (val dv = v["density"]) {
            null -> {}
            is SJ.Num -> {
                if (dv.v !in ThemeDeco.DENSITY_RANGE) c.err(ThemeIssue.Code.clamped, "$p.density")
                density = dv.v.coerceIn(ThemeDeco.DENSITY_RANGE)
            }
            else -> c.err(ThemeIssue.Code.wrongType, "$p.density")
        }
        return ThemeDeco(motif, color, density, alt)
    }

    private fun typography(d: SJ.Obj, base: KeyStyle, c: Ctx): KeyStyle {
        var s = base
        when (val v = d["corner"]) {
            null -> {}
            is SJ.Num -> { if (v.v !in 0..100) c.err(ThemeIssue.Code.clamped, "corner"); s = s.copy(corner = v.v.coerceIn(0, 100)) }
            else -> c.err(ThemeIssue.Code.wrongType, "corner")
        }
        when (val v = d["fontScale"]) {
            null -> {}
            is SJ.Num -> {
                if (v.v !in KeyStyle.FONT_SCALE_MIN..KeyStyle.FONT_SCALE_MAX) c.err(ThemeIssue.Code.clamped, "fontScale")
                s = s.copy(fontScale = v.v.coerceIn(KeyStyle.FONT_SCALE_MIN, KeyStyle.FONT_SCALE_MAX))
            }
            else -> c.err(ThemeIssue.Code.wrongType, "fontScale")
        }
        when (val v = d["font"]) {
            null -> {}
            is SJ.Str -> KeyLabelFont.entries.firstOrNull { it.id == v.s }?.let { s = s.copy(font = it) } ?: c.err(ThemeIssue.Code.badValue, "font")
            is SJ.Obj -> fontAsset(v, c)?.let { s = s.copy(font = KeyLabelFont.DEFAULT, assets = s.assets.copy(font = it)) }
            else -> c.err(ThemeIssue.Code.wrongType, "font")
        }
        d["background"]?.let { s = s.copy(assets = s.assets.copy(background = assetRef(it, "background", false, emptySet(), c))) }
        d["foreground"]?.let { s = s.copy(assets = s.assets.copy(foreground = assetRef(it, "foreground", false, emptySet(), c))) }
        d["keys"]?.let { s = s.copy(assets = s.assets.copy(keys = keySkins(it, c))) }
        c.issues.addAll(assetLimitIssues(s.assets))
        when (val v = d["weight"]) {
            null -> {}
            is SJ.Str -> KeyLabelWeight.entries.firstOrNull { it.id == v.s }?.let { s = s.copy(weight = it) } ?: c.err(ThemeIssue.Code.badValue, "weight")
            else -> c.err(ThemeIssue.Code.wrongType, "weight")
        }
        fun pick(k: String, allowed: Set<String>): String? = when (val v = d[k]) {
            null -> null
            is SJ.Str -> if (v.s in allowed) v.s else { c.err(ThemeIssue.Code.badValue, k); null }
            else -> { c.err(ThemeIssue.Code.wrongType, k); null }
        }
        s = s.copy(sound = pick("sound", ThemeExtraIds.SOUNDS), effect = pick("effect", ThemeExtraIds.EFFECTS),
            swipe = pick("swipe", ThemeExtraIds.SWIPES), game = pick("game", ThemeExtraIds.GAMES),
            keyShape = pick("keyShape", ThemeExtraIds.KEY_SHAPES), photoFx = pick("photoFx", ThemeExtraIds.PHOTO_FX))
        return s
    }

    // ---- tệp tải về

    /** {"url","sha256"?} (+ khoá thêm cho phông / skin). Sai ⇒ lỗi + null. */
    private fun assetRef(v: SJ, p: String, font: Boolean, extra: Set<String>, c: Ctx): ThemeAssetRef? {
        if (v !is SJ.Obj) { c.err(ThemeIssue.Code.wrongType, p); return null }
        for ((k, _) in v.m) if (k != "url" && k != "sha256" && k !in extra) c.err(ThemeIssue.Code.unknownKey, "$p.$k")
        var ok = true
        var url = ""
        when (val u = v["url"]) {
            null -> { c.err(ThemeIssue.Code.missingKey, "$p.url"); ok = false }
            is SJ.Str -> if (ThemeAssetURL.isValid(u.s, font)) url = u.s else { c.err(ThemeIssue.Code.badUrl, "$p.url"); ok = false }
            else -> { c.err(ThemeIssue.Code.wrongType, "$p.url"); ok = false }
        }
        var sha: String? = null
        when (val h = v["sha256"]) {
            null -> {}
            is SJ.Str -> { sha = ThemeAssetURL.sha256(h.s); if (sha == null) { c.err(ThemeIssue.Code.badValue, "$p.sha256"); ok = false } }
            else -> { c.err(ThemeIssue.Code.wrongType, "$p.sha256"); ok = false }
        }
        return if (ok) ThemeAssetRef(url, sha) else null
    }

    private fun fontAsset(m: SJ.Obj, c: Ctx): ThemeFontAsset? {
        val n = name(m["name"], "font.name", true, c)
        val ref = assetRef(m, "font", true, setOf("name"), c)
        return if (ref != null && n != null) ThemeFontAsset(n, ref) else null
    }

    private fun keySkins(v: SJ, c: Ctx): Map<String, ThemeKeySkin> {
        if (v !is SJ.Obj) { c.err(ThemeIssue.Code.wrongType, "keys"); return emptyMap() }
        val out = LinkedHashMap<String, ThemeKeySkin>()
        for ((k, value) in v.m) {
            val p = "keys.$k"
            if (k !in ThemeAssetSpec.SKIN_KEYS) { c.err(ThemeIssue.Code.unknownKey, p); continue }
            if (value !is SJ.Obj) { c.err(ThemeIssue.Code.wrongType, p); continue }
            val ref = assetRef(value, p, false, setOf("slice", "pressed"), c) ?: continue
            var slice: List<Int>? = null
            var pressed: ThemeAssetRef? = null
            var ok = true
            when (val sv = value["slice"]) {
                null -> {}
                is SJ.Arr -> {
                    val ins = ArrayList<Int>()
                    for (x in sv.a) { if (x is SJ.Num) ins.add(x.v) else { c.err(ThemeIssue.Code.wrongType, "$p.slice"); ok = false; break } }
                    if (ok) {
                        if (ins.size == 4 && ins.all { it in 0..ThemeAssetSpec.MAX_SLICE }) slice = ins
                        else { c.err(ThemeIssue.Code.badValue, "$p.slice"); ok = false }
                    }
                }
                else -> { c.err(ThemeIssue.Code.wrongType, "$p.slice"); ok = false }
            }
            value["pressed"]?.let { pv ->
                pressed = assetRef(pv, "$p.pressed", false, emptySet(), c)
                if (pressed == null) ok = false
            }
            if (ok) out[k] = ThemeKeySkin(ref, slice, pressed)
        }
        return out
    }

    /** ≤ 16 ảnh khác nhau (theo URL), ≤ 20 tệp (ảnh + phông). */
    fun assetLimitIssues(a: ThemeAssetSpec): List<ThemeIssue> {
        val images = ThemeAssetPlan.imageURLs(a)
        val files = images.size + (if (a.font == null) 0 else 1)
        return when {
            images.size > ThemeAssetSpec.MAX_IMAGES ->
                listOf(ThemeIssue(ThemeIssue.Code.tooManyFiles, "${images.size} > ${ThemeAssetSpec.MAX_IMAGES}"))
            files > ThemeAssetSpec.MAX_FILES -> listOf(ThemeIssue(ThemeIssue.Code.tooManyFiles, "$files > ${ThemeAssetSpec.MAX_FILES}"))
            else -> emptyList()
        }
    }

    /** Bản vá theo theme (KeyStyleStore) — khoá lạ / sai ⇒ null (cả mục bị bỏ). */
    fun override(j: SJ): KeyStyle? {
        if (j !is SJ.Obj) return null
        val c = Ctx()
        val allowed = setOf("label", "fill", "accent", "corner", "fontScale", "font", "weight", "light", "dark",
            "sound", "effect", "swipe", "game", "keyShape", "photoFx") + ASSET_KEYS
        for ((k, _) in j.m) if (k !in allowed) c.err(ThemeIssue.Code.unknownKey, k)
        fun rgb(k: String): Int? {
            val v = j[k] ?: return null
            val col = (v as? SJ.Str)?.let { ThemeColorCode.parse(it.s) }
            if (col == null || (col ushr 24) != 0xFF) { c.err(ThemeIssue.Code.badColor, k); return null }
            return col and 0xFFFFFF
        }
        var st = KeyStyle(labelColor = rgb("label"), fillColor = rgb("fill"), accentColor = rgb("accent"))
        st = typography(j, st, c)
        j["light"]?.let { st = st.copy(light = slots(it, "light", false, c)) }
        j["dark"]?.let { st = st.copy(dark = slots(it, "dark", false, c)) }
        return if (c.failed) null else st
    }

    /** Chữ/phím, chữ/phím chức năng, chữ/nhấn mỗi chế độ: < 2:1 lỗi, < 3:1 cảnh báo. */
    fun contrastIssues(spec: ThemeSpec): List<ThemeIssue> {
        val out = ArrayList<ThemeIssue>()
        val c = ThemeColor
        val modes = ArrayList<Triple<String, ThemeSlots, Boolean>>()
        modes.add(Triple("light", spec.light, false))
        spec.dark?.let { modes.add(Triple("dark", it, true)) }
        // Bảng theo giờ: kiểm trên backdrop theo độ sáng chữ của chính nó — iOS y hệt.
        spec.schedule?.forEachIndexed { i, e -> modes.add(Triple("schedule[$i]", e.slots, ThemeSpec.palette(e.slots, false).isDark)) }
        for ((name, s, dark) in modes) {
            val p = ThemeSpec.palette(s, dark)
            val sys = KeyboardTransparency.systemBackdrop(dark)
            val behind = s.bg?.let { c.over(it, sys) } ?: sys
            val pairs = listOf(
                Triple("ink/key", p.ink, c.over(p.keyFill, behind)),
                Triple("fnInk/fn", p.fnInk, c.over(p.functionFill ?: p.keyFill, behind)),
                Triple("accentInk/accent", p.actionInk, c.over(p.action, behind)),
            )
            for ((what, fg, bg) in pairs) {
                val r = c.contrast(c.over(fg, bg), bg)
                if (r < 2) out.add(ThemeIssue(ThemeIssue.Code.contrastTooLow, "$name $what"))
                else if (r < 3) out.add(ThemeIssue(ThemeIssue.Code.lowContrast, "$name $what"))
            }
        }
        return out
    }
}

// ---- Theme có sẵn

object BuiltinThemes {
    /** Đọc MỘT lần (lazy, an toàn luồng). Hỏng (không xảy ra — test khoá) ⇒ rỗng ⇒ theme vẽ như Hệ thống. */
    val specs: Map<String, ThemeSpec> by lazy { parse(BuiltinThemesData.JSON) }

    fun parse(text: String): Map<String, ThemeSpec> {
        val r = StrictJson.parse(text, StrictJson.Limits(maxBytes = 64 * 1024))
        val root = (r as? StrictJson.Result.Ok)?.v as? SJ.Obj ?: return emptyMap()
        val arr = root["themes"] as? SJ.Arr ?: return emptyMap()
        val out = LinkedHashMap<String, ThemeSpec>()
        for (t in arr.a) {
            val s = ThemeSpecParser.spec(t, contrast = false).spec ?: continue
            s.id?.let { out[it] = s }
        }
        return out
    }
}

// ---- Theme tự tạo

/**
 * Theme tự tạo / dán (Plus): pref [KEY] = chuỗi chuẩn {"id": spec, …} (sao lưu); [ACTIVE_KEY] = chuỗi chuẩn
 * của theme ĐANG CHỌN (IME chỉ đọc khoá này — không đọc cả kho). Y hệt iOS CustomThemeStore.
 */
object CustomThemeStore {
    const val KEY = Keys.CUSTOM_THEMES
    const val ACTIVE_KEY = Keys.ACTIVE_THEME_SPEC
    const val MAX_THEMES = 50
    const val MAX_BYTES = 16 * 1024
    const val MAX_STORE_BYTES = MAX_THEMES * MAX_BYTES + 1024
    private val LIMITS = StrictJson.Limits(maxBytes = MAX_STORE_BYTES, maxDepth = 9)

    fun parse(raw: String?): Map<String, ThemeSpec> {
        if (raw.isNullOrEmpty()) return emptyMap()
        val m = (StrictJson.parse(raw, LIMITS) as? StrictJson.Result.Ok)?.v as? SJ.Obj ?: return emptyMap()
        val out = LinkedHashMap<String, ThemeSpec>()
        for ((id, v) in m.m) {
            if (!KeyStyleStore.validId(id) || KeyboardTheme.entries.any { it.id == id } || out.size >= MAX_THEMES) continue
            val s = ThemeSpecParser.spec(v, contrast = false).spec ?: continue
            out[id] = s.copy(id = id)
        }
        return out
    }

    fun serialize(m: Map<String, ThemeSpec>): String = SJ.Obj(m.map { (id, s) -> id to s.copy(id = id).json }).canonical

    fun normalize(raw: String): String? =
        if ((StrictJson.parse(raw, LIMITS) as? StrictJson.Result.Ok)?.v is SJ.Obj) serialize(parse(raw)) else null

    /** Id không trùng theme có sẵn / theme tự tạo: giữ `want` nếu trống, không thì "-2", "-3"… (iOS y hệt). */
    fun uniqueId(want: String?, taken: Set<String>): String {
        val base = (want?.takeIf { KeyStyleStore.validId(it) } ?: "custom").take(36)
        fun free(s: String) = s !in taken && KeyboardTheme.entries.none { it.id == s }
        if (free(base)) return base
        var n = 2
        while (!free("$base-$n")) n++
        return "$base-$n"
    }

    sealed class Added {
        data class Ok(val id: String, val store: Map<String, ThemeSpec>) : Added()
        data class Err(val issue: ThemeIssue) : Added()
    }

    fun add(spec: ThemeSpec, m: Map<String, ThemeSpec>): Added {
        if (m.size >= MAX_THEMES) return Added.Err(ThemeIssue(ThemeIssue.Code.tooMany, MAX_THEMES.toString()))
        val id = uniqueId(spec.id, m.keys)
        return Added.Ok(id, LinkedHashMap(m).apply { put(id, spec.copy(id = id)) })
    }

    @Volatile private var cache: Pair<String, ThemeSpec?>? = null

    /** IME: theme đang chọn (đã chuẩn hoá bởi app) — kiểm lại; hỏng ⇒ null (về Hệ thống). Cùng chuỗi ⇒ dùng lại. */
    fun active(raw: String?, id: String): ThemeSpec? {
        if (raw.isNullOrEmpty()) return null
        val c = cache
        val spec = if (c != null && c.first == raw) c.second else {
            val s = ThemeSpecParser.parse(raw).spec?.let { if (it.id == null) it.copy(id = id) else it }
            cache = raw to s
            s
        }
        return spec?.takeIf { it.id == id }
    }
}

// ---- Hành động thẻ "Chọn giao diện" (thuần — app gọi, test JVM; iOS ThemeJSONActions y hệt)

sealed class ThemeEditTarget {
    data class Builtin(val theme: KeyboardTheme) : ThemeEditTarget()
    data class Custom(val id: String) : ThemeEditTarget()
}

object ThemeJsonActions {
    /**
     * Palette gốc của theme có sẵn: [KeyboardTheme.palette] hoặc (SYSTEM — màu resource) do app cấp.
     */
    fun interface Base { fun palette(t: KeyboardTheme, dark: Boolean): ThemePalette }

    /** "Chép JSON" (miễn phí): theme thực thấy gồm tuỳ chỉnh, dạng dễ đọc. */
    fun copyText(t: ThemeEditTarget, s: ThemeSettings, store: Map<String, ThemeSpec>, base: Base): String? = when (t) {
        is ThemeEditTarget.Builtin -> s.exportSpec(t.theme, base.palette(t.theme, false), base.palette(t.theme, true)).json.pretty
        is ThemeEditTarget.Custom -> store[t.id]?.let { s.exportSpec(it).json.pretty }
    }

    class Saved(val ok: Boolean, val issues: List<ThemeIssue>, val settings: ThemeSettings, val store: Map<String, ThemeSpec>)

    /** Lưu văn bản đã sửa — y hệt iOS ThemeJSONActions.save. */
    fun save(text: String, t: ThemeEditTarget, s: ThemeSettings, store: Map<String, ThemeSpec>, base: Base): Saved {
        val out = ThemeSpecParser.parse(text)
        val spec = out.spec ?: return Saved(false, out.issues, s, store)
        val warnings = ArrayList(out.issues)
        return when (t) {
            is ThemeEditTarget.Builtin -> {
                val b = t.theme
                val bl = b.spec?.light ?: ThemeSpec.slots(base.palette(b, false))
                val bd = b.spec?.slots(true) ?: ThemeSpec.slots(base.palette(b, true))
                val (style, lostBg) = KeyStyle.fromEdited(spec, bl, bd)
                var st = style
                if (st.corner == b.spec?.corner) st = st.copy(corner = null)
                if (st.fontScale == b.spec?.fontScale) st = st.copy(fontScale = null)
                b.spec?.font?.let { if (st.font == it) st = st.copy(font = KeyLabelFont.DEFAULT) }
                b.spec?.weight?.let { if (st.weight == it) st = st.copy(weight = KeyLabelWeight.REGULAR) }
                if (st.sound == b.spec?.sound) st = st.copy(sound = null)
                if (st.effect == b.spec?.effect) st = st.copy(effect = null)
                if (st.swipe == b.spec?.swipe) st = st.copy(swipe = null)
                if (st.game == b.spec?.game) st = st.copy(game = null)
                if (st.keyShape == b.spec?.keyShape) st = st.copy(keyShape = null)
                if (st.photoFx == b.spec?.photoFx) st = st.copy(photoFx = null)
                if (lostBg) warnings.add(ThemeIssue(ThemeIssue.Code.bgKept, "bg"))
                Saved(true, warnings, s.withKeyStyle(st, b), store)
            }
            is ThemeEditTarget.Custom -> {
                if (store[t.id] == null) return Saved(false, listOf(ThemeIssue(ThemeIssue.Code.missingKey, t.id)), s, store)
                val n = spec.copy(id = t.id)
                val ns = s.copy(keyStyles = s.keyStyles - t.id).let { if (it.custom?.id == t.id) it.copy(custom = n) else it }
                Saved(true, warnings, ns, LinkedHashMap(store).apply { put(t.id, n) })
            }
        }
    }

    /** "Đặt lại mặc định" (theme có sẵn): bỏ mọi tuỳ chỉnh của theme đó. */
    fun reset(b: KeyboardTheme, s: ThemeSettings): ThemeSettings = s.withKeyStyle(KeyStyle.DEFAULT, b)

    /** "Xoá" (theme tự tạo): bỏ khỏi kho + tuỳ chỉnh; đang chọn ⇒ về Hệ thống. */
    fun delete(id: String, s: ThemeSettings, store: Map<String, ThemeSpec>): Pair<ThemeSettings, Map<String, ThemeSpec>> {
        var ns = s.copy(keyStyles = s.keyStyles - id)
        if (ns.custom?.id == id) ns = ns.copy(theme = KeyboardTheme.SYSTEM, custom = null)
        return ns to (store - id)
    }

    /** "Dán giao diện": CHỈ khi người dùng bấm. Trả kết quả kiểm để XEM TRƯỚC; [commitPaste] mới ghi. */
    fun preview(text: String): ThemeSpecParser.Outcome = ThemeSpecParser.parse(text)

    fun commitPaste(spec: ThemeSpec, store: Map<String, ThemeSpec>): CustomThemeStore.Added = CustomThemeStore.add(spec, store)
}
