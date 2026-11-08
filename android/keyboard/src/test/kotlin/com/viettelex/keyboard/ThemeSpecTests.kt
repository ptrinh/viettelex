package com.viettelex.keyboard

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.File
import java.util.Base64

/**
 * "Giao diện JSON" — y hệt iOS ThemeJSONTests: theme có sẵn từ JSON = palette cũ, đọc chặt + lỗi, ca chung
 * (iOS/KeyboardTests/Fixtures/theme-json-cases.txt), fuzz không crash, thời gian, dán (trùng id, giới hạn),
 * sửa = bản vá + đặt lại, xoá, cổng Plus (giữ dữ liệu), sao lưu khứ hồi.
 */
class ThemeSpecTests {
    private val c = ThemeColor
    private var savedPaywall = false

    @Before fun setUp() { savedPaywall = PlusGate.paywallEnabled; PlusGate.paywallEnabled = false }
    @After fun tearDown() {
        PlusGate.paywallEnabled = savedPaywall
        PlusGate.install({ null }, debugBuild = false)
    }
    private fun lockPlus() { PlusGate.paywallEnabled = true; PlusGate.install({ null }, debugBuild = false) }

    /** Hệ thống (màu resource) giả lập như ThemePage.previewPalette. */
    private val base = ThemeJsonActions.Base { t, dark -> t.palette(dark) ?: ThemeSpec.palette(ThemeSlots(key = c.WHITE,
        special = c.rgb(0xD6DBE3), ink = c.rgb(0x1F1F1F), accent = c.rgb(0x0B57D0), bg = c.rgb(0xEEF0F4)), dark) }

    companion object {
        const val CASE_A = """{"v":1,"name":{"vi":"Thử"},"light":{"key":"#ffffff","special":"#DDDDDD","ink":"#000000","accent":"#0a84ff","bg":"#EEEEEE"}}"""

        fun generate(input: String): ByteArray {
            if (input.startsWith("b64:")) return Base64.getDecoder().decode(input.removePrefix("b64:"))
            if (!input.startsWith("gen:")) return input.toByteArray(Charsets.UTF_8)
            val p = input.split(":")
            val n = p.getOrNull(2)?.toIntOrNull() ?: 0
            val slots = """"light":{"key":"#FFFFFF","special":"#DDDDDD","ink":"#000000","accent":"#000000"}"""
            val s = when (p.getOrNull(1)) {
                "size" -> CASE_A + " ".repeat(maxOf(0, n - CASE_A.toByteArray(Charsets.UTF_8).size))
                "deep" -> "[".repeat(n) + "1" + "]".repeat(n)
                "deepobj" -> """{"a":""".repeat(n) + "1" + "}".repeat(n)
                "longname" -> """{"v":1,"name":{"vi":"${"a".repeat(n)}"},$slots}"""
                "longkey" -> """{"${"k".repeat(n)}":1}"""
                "skins", "skinspressed" -> {
                    val letters = ThemeAssetSpec.LETTER_KEYS.take(n).mapIndexed { i, l ->
                        val pr = if (p[1] == "skinspressed") ""","pressed":{"url":"https://example.com/p$i.png"}""" else ""
                        """"$l":{"url":"https://example.com/k$i.png"$pr}"""
                    }
                    """{"v":1,"name":{"vi":"x"},$slots,"keys":{${letters.joinToString(",")}}}"""
                }
                else -> ""
            }
            return s.toByteArray(Charsets.UTF_8)
        }
    }

    private fun spec(text: String): ThemeSpec {
        val o = ThemeSpecParser.parse(text)
        return o.spec ?: error("${o.issues}")
    }

    private fun repoFile(rel: String): File = listOf("../..", "..", ".").map { File(it, rel) }.firstOrNull { it.exists() }
        ?: error("không thấy $rel")

    // ---- theme có sẵn

    /** Nguồn duy nhất themes/builtin-themes.json ⇒ chuỗi nhúng iOS + Android trùng từng ký tự. */
    @Test fun builtinSourceMatchesEmbeddedOnBothPlatforms() {
        val src = repoFile("themes/builtin-themes.json").readText().trim()
        assertEquals("chạy python3 Scripts/gen-builtin-themes.py", src, BuiltinThemesData.JSON.trim())
        val swift = repoFile("iOS/Keyboard/BuiltinThemes.swift").readText()
        assertTrue("iOS nhúng đúng nguồn", swift.contains(src))
    }

    @Test fun everyBuiltinParsesAndRoundTrips() {
        val native = setOf(KeyboardTheme.SYSTEM, KeyboardTheme.GLASS)
        assertEquals(KeyboardTheme.entries.filter { it !in native }.map { it.id }.toSet(), BuiltinThemes.specs.keys)
        for ((id, s) in BuiltinThemes.specs) {
            val t = KeyboardTheme.entries.first { it.id == id }
            assertEquals("tên vi = khoá L10n", t.viTitle, s.nameVi)
            assertTrue(id, ThemeSpecParser.contrastIssues(s).none { it.isError })
            // Lịch theo giờ (Theo giờ) không nằm trong palette — đi riêng.
            val back = ThemeSpec.export(id, s.nameVi, s.nameEn, s.palette(false), s.palette(true), s.typography)
                .copy(schedule = s.schedule, tags = s.tags, buddy = s.buddy, variant = s.variant,   // lịch / nhãn / bạn đồng hành /
                    particles = s.particles, keywords = s.keywords)                                 // bảng biến thể / hạt / từ khoá đi riêng
            assertEquals(id, s.canonical, back.canonical)
            assertEquals(id, s.canonical, spec(s.canonical).canonical)
            assertEquals(id, s.canonical, ThemeSettings().exportSpec(t, base.palette(t, false), base.palette(t, true)).canonical)
        }
    }

    // ---- ca chung với iOS

    private fun fixtureLines(): List<List<String>> =
        repoFile("iOS/KeyboardTests/Fixtures/theme-json-cases.txt").readText(Charsets.UTF_8).split('\n')
            .filter { it.isNotEmpty() && !it.startsWith("#") }.map { it.split('\t') }

    @Test fun sharedCasesWithIOS() {
        val specs = HashMap<String, ThemeSpec>()
        var n = 0
        for (cs in fixtureLines().filter { it[0] == "CASE" }) {
            assertEquals(cs.joinToString("|"), 5, cs.size)
            val (name, expect, canonical) = Triple(cs[1], cs[2], cs[3])
            val out = ThemeSpecParser.parse(generate(cs[4]))
            val codes = out.issues.map { it.code.name }
            if (expect.startsWith("err:")) {
                assertNull(name, out.spec)
                assertTrue("$name: $codes", expect.removePrefix("err:") in codes)
            } else {
                val s = out.spec ?: error("$name: ${out.issues}")
                specs[name] = s
                if (canonical != "-") assertEquals(name, canonical, s.canonical)
                val w = expect.split("+").getOrNull(1)
                if (w != null) assertTrue("$name: $codes", w in codes) else assertTrue("$name: $codes", out.issues.isEmpty())
            }
            n++
        }
        assertTrue(n > 50)
        fun hex(v: Int?) = if (v == null) "-" else String.format("%08X", v)
        for (cs in fixtureLines().filter { it[0] == "PAL" }) {
            val s = specs[cs[1]] ?: error(cs[1])
            val p = s.palette(cs[2] == "1")
            val deco = p.decoration?.let { "${it.motif}:${hex(it.color)}@${it.density}" } ?: "-"
            val got = listOf(hex(s.slots(cs[2] == "1").bg), hex(p.keyFill), hex(p.specialFill), hex(p.ink), hex(p.action),
                hex(p.actionInk), hex(p.trail), hex(p.balloon), hex(p.keyBorder), deco).joinToString(" ")
            assertEquals("PAL ${cs[1]} ${cs[2]}", cs[3], got)
        }
        // Kế hoạch tệp tải về: cùng JSON ⇒ cùng chuỗi kế hoạch hai nền tảng.
        var plans = 0
        for (cs in fixtureLines().filter { it[0] == "PLAN" }) {
            val s = specs[cs[1]] ?: error(cs[1])
            assertEquals("PLAN ${cs[1]}", cs[2], ThemeAssetPlan.make(s.typography.assets).description)
            plans++
        }
        assertTrue(plans >= 6)
        // Theo giờ: mục lịch + màu chữ ở phút cho trước (cả nửa đêm / ngoài ngày) — chung iOS.
        var scheds = 0
        for (cs in fixtureLines().filter { it[0] == "SCHED" }) {
            val s = specs[cs[1]] ?: error(cs[1])
            val m = cs[2].toInt()
            assertEquals("SCHED ${cs[1]} $m", cs[3].toInt(), s.scheduleIndex(m))
            assertEquals("SCHED ink ${cs[1]} $m", cs[4], hex(s.palette(false, m).ink))
            assertEquals("lịch bỏ qua sáng/tối", s.slots(false, m), s.slots(true, m))
            scheds++
        }
        assertTrue(scheds >= 6)
    }

    // ---- fuzz — không crash, hoặc model hợp lệ hoặc lỗi

    @Test fun fuzzNeverCrashes() {
        val seeds = listOf(CASE_A, spec(CASE_A).canonical) + BuiltinThemes.specs.values.map { it.canonical }
        val r = java.util.Random(0x5EED)
        val junk = listOf("{", "}", "[", "]", "\"", ":", ",", "null", "true", "-", "9", "1e9", "\\u", "\\", "#", "NaN",
            "999999999999", "\u0000", "﻿", "💖", "\"name\"", "{\"a\":", "[[[[", "\"#FFFFFF\"", "\uD800")
        var oks = 0; var errs = 0
        for (i in 0 until 4000) {
            var bytes = seeds[r.nextInt(seeds.size)].toByteArray(Charsets.UTF_8)
            when (i % 6) {
                0 -> bytes = bytes.copyOf(r.nextInt(bytes.size + 1))
                1 -> repeat(1 + r.nextInt(4)) { if (bytes.isNotEmpty()) { val k = r.nextInt(bytes.size); bytes[k] = (bytes[k].toInt() xor (1 shl r.nextInt(8))).toByte() } }
                2 -> { val k = r.nextInt(bytes.size + 1); bytes = bytes.copyOfRange(0, k) + junk[r.nextInt(junk.size)].toByteArray() + bytes.copyOfRange(k, bytes.size) }
                3 -> { val a = bytes.indexOf('"'.code.toByte()); if (a >= 0) bytes = bytes.copyOfRange(0, a) + "12345,".toByteArray() + bytes.copyOfRange(minOf(bytes.size, a + 8), bytes.size) }
                4 -> bytes += "[".repeat(r.nextInt(2000)).toByteArray()
                else -> bytes = ByteArray(r.nextInt(300)) { r.nextInt(256).toByte() }
            }
            val out = ThemeSpecParser.parse(bytes)
            if (out.spec != null) { oks++; assertTrue(out.errors.isEmpty()) } else { errs++; assertFalse(out.errors.isEmpty()) }
            out.spec?.let { assertEquals(it.canonical, ThemeSpecParser.parse(it.canonical).spec?.canonical) }
            val text = String(bytes, Charsets.UTF_8)
            KeyStyleStore.parse(text); CustomThemeStore.parse(text); ThemeSpecParser.parse(text)
        }
        assertTrue(oks > 0); assertTrue(errs > 1000)
        assertFalse(ThemeSpecParser.parse("{\"v\":" + "9".repeat(10_000) + "}").errors.isEmpty())
        assertEquals(ThemeIssue.Code.tooLarge, ThemeSpecParser.parse("a".repeat(100_000)).errors.first().code)
        // Lỗi cú pháp báo "dòng:cột" (iOS cùng giá trị).
        assertEquals(ThemeIssue(ThemeIssue.Code.syntax, "2:10"), ThemeSpecParser.parse("{\n  \"v\": 1,,\n}").errors.first())
        // Chuỗi Java hỏng (nửa surrogate lẻ) ⇒ lỗi mã hoá, không crash.
        assertEquals(ThemeIssue.Code.encoding, ThemeSpecParser.parse("{\"v\":1,\"name\":{\"vi\":\"\uD800\"}}").errors.first().code)
    }

    // ---- thời gian (IME)

    @Test fun parse16KBIsFast() {
        val big = String(generate("gen:size:16384"), Charsets.UTF_8)
        val nasty = "{\"v\":1,\"name\":{\"vi\":\"" + "\\u00e0".repeat(2700) + "\"}}"
        assertNotNull(ThemeSpecParser.parse(big).spec)
        repeat(50) { ThemeSpecParser.parse(big); ThemeSpecParser.parse(nasty) }   // JIT
        val t0 = System.nanoTime()
        repeat(100) { ThemeSpecParser.parse(big); ThemeSpecParser.parse(nasty) }
        val perMs = (System.nanoTime() - t0) / 200 / 1e6
        assertTrue("đọc 16 KB phải < 5 ms (đo $perMs ms)", perMs < 5)
    }

    // ---- dán

    @Test fun pasteCollisionAndLimits() {
        var store: Map<String, ThemeSpec> = emptyMap()
        fun add(s: ThemeSpec): String {
            val r = ThemeJsonActions.commitPaste(s, store) as CustomThemeStore.Added.Ok
            store = r.store; return r.id
        }
        val s = spec(CASE_A)
        assertEquals("peach-2", add(s.copy(id = "peach")))
        assertEquals("peach-3", add(s.copy(id = "peach")))
        assertEquals("custom", add(s))
        assertEquals("custom-2", add(s))
        assertEquals("peach-2", store["peach-2"]?.id)
        while (store.size < CustomThemeStore.MAX_THEMES) add(s)
        val e = ThemeJsonActions.commitPaste(s, store)
        assertTrue(e is CustomThemeStore.Added.Err && e.issue.code == ThemeIssue.Code.tooMany)
        assertEquals(store, CustomThemeStore.parse(CustomThemeStore.serialize(store)))
        assertEquals(emptyMap<String, ThemeSpec>(), CustomThemeStore.parse("""{"x":{"v":1},"peach":{"v":1}}"""))
        assertEquals(emptyMap<String, ThemeSpec>(), CustomThemeStore.parse("rác"))
        assertNotNull(ThemeJsonActions.preview(CASE_A).spec)
        assertNull(ThemeJsonActions.preview("{oops").spec)
        assertTrue(ThemeJsonActions.preview("{oops").issues.first().message.isNotEmpty())
    }

    // ---- sửa / đặt lại / xoá / chọn

    @Test fun editBuiltinIsOverrideAndResetRemovesIt() {
        var s = ThemeSettings(theme = KeyboardTheme.PEACH)
        val store = emptyMap<String, ThemeSpec>()
        val copied = ThemeJsonActions.copyText(ThemeEditTarget.Builtin(KeyboardTheme.PEACH), s, store, base)!!
        var r = ThemeJsonActions.save(copied, ThemeEditTarget.Builtin(KeyboardTheme.PEACH), s, store, base)
        assertTrue(r.ok); assertNull(r.settings.keyStyles["peach"])
        val edited = copied.replace("\"#FFF8F7\"", "\"#102030\"").replace("\"#4A2226\"", "\"#FFFFFF\"")
            .replace("\"v\": 1", "\"corner\": 0,\n  \"v\": 1")
        r = ThemeJsonActions.save(edited, ThemeEditTarget.Builtin(KeyboardTheme.PEACH), s, store, base)
        assertTrue("${r.issues}", r.ok)
        s = r.settings
        val st = s.keyStyles["peach"]!!
        assertEquals(c.rgb(0x102030), st.light.key); assertEquals(c.WHITE, st.light.ink)
        assertTrue(st.dark.isEmpty); assertEquals(0, st.corner)
        assertEquals(c.rgb(0x102030), s.styledCurrent(s.basePalette(false)!!, false).keyFill)
        assertEquals(ThemeSettings(theme = KeyboardTheme.PEACH).styledCurrent(KeyboardTheme.PEACH.palette(true)!!, true),
            s.styledCurrent(s.basePalette(true)!!, true))
        assertEquals(spec(edited).canonical, spec(ThemeJsonActions.copyText(ThemeEditTarget.Builtin(KeyboardTheme.PEACH), s, store, base)!!).canonical)
        // Điều khiển có cấu trúc sửa CÙNG bản vá — giữ bản vá JSON.
        s = s.withKeyStyle(s.keyStyle.copy(accentColor = 0x00FF00))
        assertEquals(c.rgb(0x102030), s.keyStyles["peach"]?.light?.key)
        assertEquals(c.rgb(0x00FF00), s.styledCurrent(s.basePalette(false)!!, false).action)
        // Lỗi ⇒ không đổi gì.
        val bad = ThemeJsonActions.save("""{"v":1}""", ThemeEditTarget.Builtin(KeyboardTheme.PEACH), s, store, base)
        assertFalse(bad.ok); assertEquals(s, bad.settings)
        // Đặt lại.
        s = ThemeJsonActions.reset(KeyboardTheme.PEACH, s)
        assertNull(s.keyStyles["peach"])
        // Bỏ nền theme có nền ⇒ cảnh báo, giữ nền.
        val nb = spec(copied).let { it.copy(light = it.light.copy(bg = null), dark = it.dark?.copy(bg = null)) }
        val w = ThemeJsonActions.save(nb.json.pretty, ThemeEditTarget.Builtin(KeyboardTheme.PEACH), s, store, base)
        assertTrue(w.ok); assertTrue(w.issues.any { it.code == ThemeIssue.Code.bgKept })
        // Hệ thống / Kính (không có JSON gốc) vẫn sửa được; chép rồi lưu nguyên ⇒ không có bản vá.
        for (t in listOf(KeyboardTheme.SYSTEM, KeyboardTheme.GLASS)) {
            val g = ThemeSettings(theme = t)
            val gc = ThemeJsonActions.copyText(ThemeEditTarget.Builtin(t), g, store, base)!!
            val gs = ThemeJsonActions.save(gc, ThemeEditTarget.Builtin(t), g, store, base)
            assertTrue("$t ${gs.issues}", gs.ok); assertNull(t.id, gs.settings.keyStyles[t.id])
        }
    }

    @Test fun customThemeSelectEditDeleteAndImeLoad() {
        var store: Map<String, ThemeSpec> = emptyMap()
        val added = ThemeJsonActions.commitPaste(spec(CASE_A), store) as CustomThemeStore.Added.Ok
        store = added.store
        val id = added.id
        var s = ThemePicker.select(store[id]!!, ThemeSettings())!!
        val prefs = HashMap<String, Any?>(s.toMap())
        prefs[Keys.CUSTOM_THEMES] = CustomThemeStore.serialize(store)
        assertEquals(id, prefs[Keys.KEYBOARD_THEME])
        val ime = ThemeSettings.load { prefs[it] }
        assertEquals(id, ime.custom?.id)
        assertEquals(c.rgb(0xEEEEEE), ime.basePalette(false)?.bg)
        // Dữ liệu hỏng ⇒ Hệ thống, không crash.
        prefs[Keys.ACTIVE_THEME_SPEC] = "{hỏng"
        assertNull(ThemeSettings.load { prefs[it] }.custom)
        assertNull(ThemeSettings.load { prefs[it] }.basePalette(false))
        prefs[Keys.ACTIVE_THEME_SPEC] = """{"v":1,"id":"khac","name":{"vi":"x"},"light":{"key":"#FFFFFF","special":"#DDDDDD","ink":"#000000","accent":"#000000"}}"""
        assertNull("id không khớp ⇒ bỏ", ThemeSettings.load { prefs[it] }.custom)
        // refreshCustom: kho có bản khác ⇒ cập nhật; mất khỏi kho ⇒ Hệ thống.
        assertEquals(id, ThemeSettings.refreshCustom { prefs[it] }?.custom?.id)
        prefs[Keys.CUSTOM_THEMES] = "{}"
        assertEquals(null, ThemeSettings.refreshCustom { prefs[it] }?.custom)
        // Sửa theme tự tạo: thay đặc tả, theme đang chọn cập nhật.
        val text = ThemeJsonActions.copyText(ThemeEditTarget.Custom(id), s, store, base)!!.replace("\"#EEEEEE\"", "\"#123456\"")
        val r = ThemeJsonActions.save(text, ThemeEditTarget.Custom(id), s, store, base)
        assertTrue(r.ok)
        s = r.settings; store = r.store
        assertEquals(c.rgb(0x123456), store[id]?.light?.bg)
        assertEquals(c.rgb(0x123456), s.custom?.light?.bg)
        // Hết Plus ⇒ vẽ Hệ thống, dữ liệu giữ; mua lại ⇒ có lại.
        lockPlus()
        assertNull(s.effectiveCustom); assertNull(s.basePalette(false))
        assertNull(ThemePicker.select(store[id]!!, s))
        assertNotNull(s.custom)
        PlusGate.paywallEnabled = false
        assertNotNull(s.effectiveCustom)
        // Xoá ⇒ về Hệ thống.
        val (ns, nstore) = ThemeJsonActions.delete(id, s, store)
        assertNull(nstore[id]); assertNull(ns.custom); assertEquals(KeyboardTheme.SYSTEM, ns.theme)
        assertEquals("", ns.toMap()[Keys.ACTIVE_THEME_SPEC])
    }

    @Test fun overridesIgnoredWithoutPlusButKept() {
        val st = KeyStyle(light = ThemeSlots(key = c.rgb(0x333333)), dark = ThemeSlots(key = c.rgb(0x333333)))
        val s = ThemeSettings(theme = KeyboardTheme.OLED).withKeyStyle(st)
        assertEquals(c.rgb(0x333333), s.styledCurrent(KeyboardTheme.OLED.palette(true)!!, true).keyFill)
        lockPlus()
        assertEquals(KeyboardTheme.OLED.palette(true), s.styledCurrent(KeyboardTheme.OLED.palette(true)!!, true))
        assertEquals(st, s.keyStyle)
    }

    // ---- sao lưu

    @Test fun backupRoundTripCustomThemesAndPatches() {
        var store: Map<String, ThemeSpec> = emptyMap()
        store = (ThemeJsonActions.commitPaste(spec(CASE_A), store) as CustomThemeStore.Added.Ok).store
        val st = KeyStyle(accentColor = 0xFF9500, dark = ThemeSlots(bg = c.BLACK),
            light = ThemeSlots(deco = ThemeDeco(ThemeDecoration.HEARTS, 0x80FF0000.toInt(), 150)))
        val s = ThemeSettings(theme = KeyboardTheme.MINT).withKeyStyle(st)
        val prefs = HashMap<String, Any?>(s.toMap()); prefs[Keys.CUSTOM_THEMES] = CustomThemeStore.serialize(store)
        val snap = BackupPrefs.snapshot({ prefs[it] }, emptyList(), null)
        assertEquals(CustomThemeStore.serialize(store), snap.settings!![Keys.CUSTOM_THEMES])
        val back = BackupCodec.decode(BackupCodec.encode(snap))
        val plan = BackupPrefs.plan(back, { null }, emptyList())
        assertEquals(store, CustomThemeStore.parse(plan.writes[Keys.CUSTOM_THEMES] as String))
        assertEquals(st, ThemeSettings.load { plan.writes[it] }.keyStyles["mint"])
        val junk = BackupCodec.decode("""{"format":"viettelex-backup","version":1,"settings":{"customThemes":"[1]"}}""")
        assertNull(junk.settings!![Keys.CUSTOM_THEMES])
    }

    /** Cùng chuỗi bản vá ⇒ cùng chuỗi chuẩn hai nền tảng (iOS PerThemeKeyStyleTests dùng y chuỗi). */
    @Test fun patchCanonicalMatchesIOS() {
        val st = KeyStyle(accentColor = 0xFF9500, dark = ThemeSlots(bg = c.BLACK),
            light = ThemeSlots(deco = ThemeDeco(ThemeDecoration.HEARTS, 0x80FF0000.toInt(), 150)))
        assertEquals("""{"mint":{"accent":"#FF9500","dark":{"bg":"#000000"},"light":{"deco":{"color":"#80FF0000","density":150,"motif":"hearts"}}}}""",
            KeyStyleStore.serialize(mapOf("mint" to st)))
        // Phông điểm ảnh + dáng phím điểm ảnh trong bản vá (iOS testPatchCanonicalMatchesAndroid y hệt).
        val px = KeyStyle(font = KeyLabelFont.PIXEL, keyShape = "pixel")
        assertEquals("""{"mint":{"font":"pixel","keyShape":"pixel"}}""", KeyStyleStore.serialize(mapOf("mint" to px)))
        assertEquals(px, KeyStyleStore.parse(KeyStyleStore.serialize(mapOf("mint" to px)))["mint"])
        assertTrue(KeyStyleStore.parse("""{"mint":{"keyShape":"round"}}""").isEmpty())
    }

    /** "Chép JSON" theme có sẵn giữ "tags" + "buddy"; dán lại đọc ra y hệt. = iOS testCopyJSONKeepsTagsAndBuddy. */
    @Test fun copyJsonKeepsTagsAndBuddy() {
        val s = ThemeSettings(theme = KeyboardTheme.AI)
        val text = ThemeJsonActions.copyText(ThemeEditTarget.Builtin(KeyboardTheme.AI), s, emptyMap(), base)!!
        val back = ThemeSpecParser.parse(text).spec!!
        assertEquals(listOf("interactive"), back.tags)
        assertEquals(ThemeBuddy("ai", 5), back.buddy)
        val plain = ThemeJsonActions.copyText(ThemeEditTarget.Builtin(KeyboardTheme.PEACH), s, emptyMap(), base)!!
        assertFalse(plain.contains("tags")); assertFalse(plain.contains("buddy"))
    }

}
