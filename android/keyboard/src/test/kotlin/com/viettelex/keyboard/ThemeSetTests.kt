package com.viettelex.keyboard

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.File

/**
 * Bản tối của theme pastel + bộ theme 10/2026 (Tim đen, Hoa xanh, Xanh lá, Trắng hồng, Neon, Hồng):
 * bảng màu chung với iOS (iOS/KeyboardTests/Fixtures/theme-palettes.tsv — iOS ThemeSetTests đọc cùng
 * file), độ đọc được, cổng Plus, hoạ tiết nền rẻ, và đi cùng độ trong suốt / ảnh nền / Tuỳ chỉnh nâng cao.
 */
class ThemeSetTests {
    private val c = ThemeColor
    private var savedPaywall = false

    @Before fun setUp() { savedPaywall = PlusGate.paywallEnabled; PlusGate.paywallEnabled = false }
    @After fun tearDown() {
        PlusGate.paywallEnabled = savedPaywall
        PlusGate.install({ null }, debugBuild = false)
    }

    private val newThemes = listOf(KeyboardTheme.BLACK_HEART, KeyboardTheme.GREEN_FLORAL, KeyboardTheme.SAGE,
        KeyboardTheme.NEON, KeyboardTheme.PINK, KeyboardTheme.TET, KeyboardTheme.TET_MAI, KeyboardTheme.XMAS,
        KeyboardTheme.XMAS_SNOW, KeyboardTheme.PIANO,
        KeyboardTheme.SEN, KeyboardTheme.TYPEWRITER, KeyboardTheme.RGB, KeyboardTheme.SPACE,
        KeyboardTheme.TRUNG_THU, KeyboardTheme.VALENTINE, KeyboardTheme.HALLOWEEN,
        KeyboardTheme.MOLE, KeyboardTheme.PIXEL, KeyboardTheme.SEA, KeyboardTheme.TIME_OF_DAY)
    private val pastels = listOf(KeyboardTheme.PEACH, KeyboardTheme.MINT, KeyboardTheme.SKY, KeyboardTheme.LAVENDER)

    private fun fixtureLines(): List<List<String>> {
        val f = listOf("../../iOS", "../iOS", "iOS").map { File(it, "KeyboardTests/Fixtures/theme-palettes.tsv") }
            .firstOrNull { it.exists() } ?: error("không thấy iOS/KeyboardTests/Fixtures/theme-palettes.tsv")
        return f.readText(Charsets.UTF_8).split('\n').filter { it.isNotEmpty() && !it.startsWith("#") }.map { it.split('\t') }
    }

    private fun hex(v: Int?): String = if (v == null) "-" else String.format("%08X", v)

    @Test fun palettesMatchSharedFixtureWithIOS() {
        val lines = fixtureLines()
        assertEquals(lines.first { it[0] == "order" }[1].split(','), KeyboardTheme.entries.map { it.id })
        assertEquals(lines.first { it[0] == "plus" }[1].split(','), KeyboardTheme.entries.filter { it.isPlus }.map { it.id })
        assertEquals(lines.first { it[0] == "interactive" }[1].split(','), KeyboardTheme.entries.filter { it.isInteractive }.map { it.id })
        assertEquals("thứ tự lưới phải trùng iOS", lines.first { it[0] == "picker" }[1].split(','), ThemePicker.ordered().map { it.id })
        val rows = lines.filter { it[0] !in setOf("order", "plus", "interactive", "picker") }
        assertEquals(84, rows.size)   // 42 theme JSON × sáng / tối
        for (r in rows) {
            val t = KeyboardTheme.entries.first { it.id == r[0] }
            val p = t.palette(r[1] == "1")!!
            val deco = p.decoration?.let { "${it.motif}${it.alt?.let { a -> "+$a" } ?: ""}:${hex(it.color)}" } ?: "-"
            val got = listOf(hex(p.bg), hex(p.keyFill), hex(p.specialFill), hex(p.ink), hex(p.action), hex(p.actionInk),
                hex(p.keyBorder), hex(p.functionFill), hex(p.functionInk), deco)
            assertEquals("${r[0]} dark=${r[1]}", r.drop(2), got)
        }
    }

    @Test fun darkVariantsDifferAndFollowSystem() {
        val fixed = setOf(KeyboardTheme.OLED, KeyboardTheme.CONTRAST, KeyboardTheme.BLACK_HEART, KeyboardTheme.NEON,
            KeyboardTheme.TET, KeyboardTheme.XMAS, KeyboardTheme.PIANO, KeyboardTheme.RGB, KeyboardTheme.SPACE,
            KeyboardTheme.TRUNG_THU, KeyboardTheme.HALLOWEEN, KeyboardTheme.MOLE, KeyboardTheme.PIXEL, KeyboardTheme.AI, KeyboardTheme.NIGHTCLUB,
            KeyboardTheme.TRIPPY, KeyboardTheme.DRIFT, KeyboardTheme.STAINED_GLASS, KeyboardTheme.RAINY_NIGHT, KeyboardTheme.GYM,
            KeyboardTheme.ZODIAC, KeyboardTheme.PRIDE, KeyboardTheme.AQUARIUM)
        for (t in KeyboardTheme.entries) {
            val light = t.palette(false) ?: continue
            val dark = t.palette(true)!!
            // Piano: phím ngà chữ đen nhưng NỀN tối ⇒ vùng ngoài phím theo nhánh tối (surfaceDark).
            if (t in fixed) { assertEquals("$t", light, dark); assertTrue("$t", dark.surfaceDark ?: dark.isDark); continue }
            assertNotEquals("$t", light, dark)
            // Vùng ngoài phím (thanh gợi ý, emoji…) sáng ở bản sáng, tối ở bản tối. Ghi-ta: bản sáng phím gỗ tối chữ ngà
            // (isDark) trên mặt đàn sáng ⇒ surfaceDark = false.
            assertFalse("$t", light.surfaceDark ?: light.isDark)
            assertTrue("$t bản tối", dark.surfaceDark ?: dark.isDark)
            // Kính, Xám trung tính (kiểu Gboard): nhấn xám đậm ở bản sáng, xám nhạt ở bản tối — cố ý khác.
            if (t != KeyboardTheme.GLASS && t != KeyboardTheme.NEUTRAL)
                assertEquals("$t giữ màu nhấn", light.action, dark.action)
        }
    }

    @Test fun labelsReadableInEveryMode() {
        for (t in KeyboardTheme.entries) for (d in listOf(false, true)) {
            val p = t.palette(d) ?: continue
            if (t == KeyboardTheme.GLASS) continue
            val key = c.over(p.keyFill, p.bg); val fn = c.over(p.fnFill, p.bg); val space = c.over(p.spaceFill, p.bg)
            assertTrue("$t/$d phím", c.contrast(p.ink, key) >= 4.5)
            assertTrue("$t/$d phím chức năng", c.contrast(p.fnInk, fn) >= 4.5)
            val spaceInk = if (p.functionFill != null) p.fnInk else p.ink
            assertTrue("$t/$d phím cách", c.contrast(spaceInk, space) >= 4.5)
            val bar = p.barInk ?: p.ink
            assertEquals("$t/$d thanh gợi ý", bar, KeyboardTransparency.readable(bar, p.bg))
            assertEquals(p.ink, KeyboardTransparency.readable(p.ink, key))
            assertEquals(p.fnInk, KeyboardTransparency.readable(p.fnInk, fn))
            p.decoration?.let { assertTrue("$t/$d hoạ tiết", c.contrast(bar, c.over(it.color, p.bg)) >= 4.5) }
        }
    }

    @Test fun newThemesArePlusAndGated() {
        newThemes.forEach { assertTrue("$it", it.isPlus) }
        PlusGate.paywallEnabled = true
        PlusGate.install({ null }, debugBuild = false)
        for (t in newThemes) {
            assertFalse("$t", ThemeGate.allows(t))
            val s = ThemeSettings(theme = t)
            assertEquals(KeyboardTheme.SYSTEM, s.effectiveTheme)
            assertNull("hết Plus ⇒ không mang bo góc Hồng", s.effectiveKeyStyle.corner)
        }
        PlusGate.install({ if (it == Keys.PLUS_UNLOCKED) true else null }, debugBuild = false)
        newThemes.forEach { assertTrue("$it", ThemeGate.allows(it)) }
    }

    @Test fun newThemesRoundTrip() {
        for (t in newThemes) {
            val m = ThemeSettings(theme = t).toMap()
            assertEquals(t, ThemeSettings.load { m[it] }.theme)
            L10n.lang = "en"
            assertNotEquals("", t.title)
        }
        L10n.lang = "vi"
    }

    // ---- âm / hiệu ứng đi kèm theme ("sound" / "effect") — iOS ThemeSetTests y hệt

    /** Bộ đủ món Trung Thu / Valentine / Halloween — iOS testFestivalFullPackThemes y hệt. */
    @Test fun festivalFullPackThemes() {
        val want = listOf(
            listOf(KeyboardTheme.TRUNG_THU, "trong", "lantern", ThemeDecoration.LANTERN, ThemeDecoration.MOON, "Mid-Autumn"),
            listOf(KeyboardTheme.VALENTINE, "pop", "heart", ThemeDecoration.HEARTS, null, "Valentine"),
            listOf(KeyboardTheme.HALLOWEEN, "boo", "smoke", ThemeDecoration.PUMPKIN, ThemeDecoration.BAT, "Halloween"))
        val yes: (String) -> Boolean = { true }
        for (w in want) {
            val t = w[0] as KeyboardTheme
            val spec = t.spec!!
            assertEquals(w[1], spec.sound); assertEquals(w[2], spec.effect)
            assertTrue(spec.sound in KeySoundStyle.PRESET_IDS); assertTrue(KeyEffect.entries.any { it.id == spec.effect })
            assertTrue("$t", t.isPlus)
            assertEquals(w[5], L10nTable.EN[t.viTitle])
            for (dk in listOf(false, true)) {
                val d = t.palette(dk)!!.decoration!!
                assertEquals(w[3], d.motif); assertEquals(w[4], d.alt)
            }
            assertEquals(ThemeExtras.Outcome(w[2] as String, w[1] as String, true),
                ThemeExtras.plan(ThemeSettings(theme = t).effectiveKeyStyle, false, yes, yes))
        }
        assertTrue(KeyboardTheme.TRUNG_THU.palette(false)!!.isDark)
        assertTrue(KeyboardTheme.HALLOWEEN.palette(false)!!.isDark)
        assertFalse(KeyboardTheme.VALENTINE.palette(false)!!.isDark)
        assertTrue(KeyboardTheme.VALENTINE.palette(true)!!.isDark)
    }

    /** Motif thứ hai xen kẽ ("alt") + khứ hồi JSON — iOS testDecorationAltAlternates. */
    @Test fun decorationAltAlternates() {
        val d = ThemeDecoration(ThemeDecoration.PUMPKIN, 0, alt = ThemeDecoration.BAT)
        assertEquals(listOf("pumpkin", "bat", "pumpkin", "bat"), (0 until 4).map(d::motifAt))
        assertEquals("hearts", ThemeDecoration(ThemeDecoration.HEARTS, 0).motifAt(1))
        val base = ThemeJsonActions.Base { t, dk -> t.palette(dk)!! }
        val text = ThemeJsonActions.copyText(ThemeEditTarget.Builtin(KeyboardTheme.HALLOWEEN), ThemeSettings(theme = KeyboardTheme.HALLOWEEN),
            emptyMap(), base)!!
        assertTrue(text, text.contains("\"alt\""))
        val back = ThemeSpecParser.parse(text).spec!!
        assertEquals("bat", back.light.deco?.alt)
        assertEquals(KeyboardTheme.HALLOWEEN.palette(false)!!.decoration, back.palette(false).decoration)
    }

    /** Hình motif mới: cùng chiều quay, trong ô ±0.5, tổng toạ độ = mốc iOS (motifChecksums). */
    @Test fun newMotifShapesParity() {
        val want = mapOf("lantern" to 0.55, "moon" to 6.8533471195, "pumpkin" to -4.65, "bat" to -26.67)
        for ((m, sumWant) in want) {
            val subs = ThemeDecoration.shape(m)
            assertTrue(m, subs.isNotEmpty())
            var sum = 0.0
            for (sub in subs) {
                val pts = ArrayList<DoubleArray>()
                pts.add(doubleArrayOf(sub.sx, sub.sy))
                for (g in sub.segs) { var i = 0; while (i < g.size) { pts.add(doubleArrayOf(g[i], g[i + 1])); i += 2 } }
                var a = 0.0
                for (i in pts.indices) { val p = pts[i]; val q = pts[(i + 1) % pts.size]; a += p[0] * q[1] - q[0] * p[1] }
                assertTrue("$m chiều quay", a > 0)
                for (p in pts) { assertTrue(m, Math.abs(p[0]) <= 0.5 + 1e-9 && Math.abs(p[1]) <= 0.5 + 1e-9); sum += p[0] * 3 + p[1] * 7 }
            }
            assertEquals(m, sumWant, sum, 1e-6)
        }
    }

    /** Neon Night Club — iOS testNightclubTheme y hệt. */
    @Test fun nightclubTheme() {
        val t = KeyboardTheme.NIGHTCLUB
        assertEquals(KeyboardTheme.NIGHTCLUB.ordinal + 1, KeyboardTheme.TRIPPY.ordinal)
        assertEquals(KeyboardTheme.AI.ordinal + 1, KeyboardTheme.NIGHTCLUB.ordinal)
        assertTrue(KeyboardTheme.entries.indexOf(KeyboardTheme.NIGHTCLUB) > KeyboardTheme.entries.indexOf(KeyboardTheme.AI))
        assertTrue(KeyboardTheme.entries.indexOf(KeyboardTheme.RAINY_NIGHT) > KeyboardTheme.entries.indexOf(KeyboardTheme.NIGHTCLUB))
        val spec = t.spec!!
        assertTrue(t.isPlus)
        assertEquals("Neon Night Club", spec.nameVi); assertEquals("Neon Night Club", spec.nameEn)
        assertEquals("Neon Night Club", L10nTable.EN[t.viTitle])
        assertEquals("club", spec.sound); assertEquals("dancefloor", spec.effect); assertEquals("neon", spec.swipe)
        assertEquals(ThemeExtraIds.SPOTLIGHT, spec.photoFx)
        assertNull("dark = same", spec.dark)
        val st = ThemeSettings(theme = t).effectiveKeyStyle
        assertEquals("spotlight", st.photoFx)
        assertNull(ThemeSettings(theme = KeyboardTheme.PIXEL).effectiveKeyStyle.photoFx)
        assertNotNull(t.palette(false)!!.keyBorder)
        assertTrue(ThemeSpecParser.contrastIssues(spec).isEmpty())
        val back = ThemeSpecParser.parse(spec.canonical).spec!!
        assertEquals("spotlight", back.photoFx); assertEquals("spotlight", back.typography.photoFx)
        val patch = KeyStyle(photoFx = "spotlight")
        assertEquals("spotlight", KeyStyleStore.parse(KeyStyleStore.serialize(mapOf("system" to patch)))["system"]?.photoFx)
        assertTrue(SpotlightPolicy.active("spotlight", plus = true, lowPower = false))
        assertFalse(SpotlightPolicy.active("spotlight", plus = false, lowPower = false))
        assertFalse(SpotlightPolicy.active("spotlight", plus = true, lowPower = true))
        assertFalse(SpotlightPolicy.active(null, plus = true, lowPower = false))
    }

    // ---- bộ 11/2026: Pixel 8-bit, Biển, Theo giờ — iOS KeyboardThemeTests y hệt

    /** Ba theme mới: Plus, thêm CUỐI (sau Xám trung tính), tên vi/en, âm / hiệu ứng / bo góc / phông. iOS testPixelSeaTimeOfDayThemes. */
    @Test fun pixelSeaTimeOfDayThemes() {
        val all = KeyboardTheme.entries
        assertEquals(listOf(KeyboardTheme.PIXEL, KeyboardTheme.SEA, KeyboardTheme.TIME_OF_DAY),
            all.subList(all.indexOf(KeyboardTheme.NEUTRAL) + 1, all.indexOf(KeyboardTheme.NEUTRAL) + 4))
        assertEquals(KeyboardTheme.PIXEL, all[all.indexOf(KeyboardTheme.NEUTRAL) + 1])
        data class W(val t: KeyboardTheme, val vi: String, val en: String, val sound: String?, val effect: String?, val corner: Int?)
        for (w in listOf(W(KeyboardTheme.PIXEL, "Pixel 8-bit", "Pixel 8-bit", "chip", "flash", 0),
                W(KeyboardTheme.SEA, "Biển", "Sea", "water", "sea", 60),
                W(KeyboardTheme.TIME_OF_DAY, "Theo giờ", "Time of day", null, null, null))) {
            val spec = w.t.spec!!
            assertTrue("${w.t}", w.t.isPlus)
            assertEquals(w.vi, spec.nameVi); assertEquals(w.en, spec.nameEn); assertEquals(w.en, L10nTable.EN[w.t.viTitle])
            assertEquals("${w.t}", w.sound, spec.sound); assertEquals("${w.t}", w.effect, spec.effect)
            assertEquals("${w.t}", w.corner, spec.corner)
            w.sound?.let { assertTrue(it in KeySoundStyle.PRESET_IDS) }
            w.effect?.let { assertTrue(it in ThemeExtraIds.EFFECTS) }
            // Pixel 8-bit: MỘT bảng (màn tắt đèn nền) — app chủ đổi sáng/tối không làm bàn phím đổi màu (iOS y hệt).
            if (w.t == KeyboardTheme.PIXEL) assertEquals("${w.t}", w.t.palette(false), w.t.palette(true))
            else assertNotEquals("${w.t} có bản tối riêng", w.t.palette(false), w.t.palette(true))
        }
        val px = KeyboardTheme.PIXEL.spec!!
        // Phông điểm ảnh NHÚNG (không tải gì) + dáng phím điểm ảnh — iOS testPixelSeaTimeOfDayThemes y hệt.
        assertEquals(KeyLabelFont.PIXEL, px.font); assertNull(px.weight); assertTrue(px.assets.isEmpty)
        assertEquals(PixelKeys.SHAPE, px.keyShape)
        val pst = ThemeSettings(theme = KeyboardTheme.PIXEL).effectiveKeyStyle
        assertEquals(0, pst.corner); assertEquals(KeyLabelFont.PIXEL, pst.font); assertEquals("pixel", pst.keyShape)
        for (t in KeyboardTheme.entries) if (t != KeyboardTheme.PIXEL) {
            // Kính màu: dáng phím "glass" (ô kính màu, [GlassKeys]).
            if (t == KeyboardTheme.STAINED_GLASS) assertEquals("glass", ThemeSettings(theme = t).effectiveKeyStyle.keyShape)
            else assertNull("$t", ThemeSettings(theme = t).effectiveKeyStyle.keyShape)
            assertNotEquals("$t", KeyLabelFont.PIXEL, ThemeSettings(theme = t).effectiveKeyStyle.font)
        }
        assertNotNull(KeyboardTheme.PIXEL.palette(false)!!.keyBorder)
        assertEquals(ThemeDecoration.BUBBLES, KeyboardTheme.SEA.palette(false)!!.decoration!!.alt)
        assertEquals(ThemeDecoration.STAR, KeyboardTheme.TIME_OF_DAY.palette(true)!!.decoration!!.motif)
        assertNull(KeyboardTheme.TIME_OF_DAY.palette(false)!!.decoration)
    }

    /** Motif pixel / waves / bubbles: cùng chiều quay, trong ô ±0.5, mốc chung iOS (testPixelWavesBubblesMotifShapes). */
    @Test fun newMotifs1111() {
        val want = mapOf("pixel" to -10.0, "waves" to 6.86, "bubbles" to 39.71)
        for ((m, sumWant) in want) {
            assertTrue(m, m in ThemeDecoration.MOTIFS)
            val subs = ThemeDecoration.shape(m)
            assertTrue(m, subs.isNotEmpty())
            var sum = 0.0
            for (sub in subs) {
                val pts = ArrayList<DoubleArray>()
                pts.add(doubleArrayOf(sub.sx, sub.sy))
                for (g in sub.segs) { var i = 0; while (i < g.size) { pts.add(doubleArrayOf(g[i], g[i + 1])); i += 2 } }
                var a = 0.0
                for (i in pts.indices) { val p = pts[i]; val q = pts[(i + 1) % pts.size]; a += p[0] * q[1] - q[0] * p[1] }
                assertTrue("$m chiều quay", a > 0)
                for (p in pts) { assertTrue(m, Math.abs(p[0]) <= 0.5 + 1e-9 && Math.abs(p[1]) <= 0.5 + 1e-9); sum += p[0] * 3 + p[1] * 7 }
            }
            assertEquals(m, sumWant, sum, 1e-6)
        }
        assertEquals(7, ThemeDecoration.shape(ThemeDecoration.PIXEL).size)
    }

    /** Theo giờ: mốc biên + qua nửa đêm, bỏ qua sáng/tối, bảng gốc light = ngày / dark = đêm — iOS testTimeOfDayScheduleBoundaries. */
    @Test fun timeOfDaySchedule() {
        val spec = KeyboardTheme.TIME_OF_DAY.spec!!
        val sc = spec.schedule!!
        assertEquals(listOf(300, 420, 1020, 1140), sc.map { it.from })
        assertEquals(listOf("05:00", "07:00", "17:00", "19:00"), sc.map { ThemeSchedule.format(it.from) })
        val cases = listOf(0 to 3, 299 to 3, 300 to 0, 419 to 0, 420 to 1, 720 to 1, 1019 to 1, 1020 to 2, 1139 to 2,
            1140 to 3, 1439 to 3, 1440 to 3, 1440 + 300 to 0, -1 to 3)
        for ((m, want) in cases) {
            assertEquals("phút $m", want, ThemeSchedule.index(sc.map { it.from }, m))
            assertEquals("phút $m tối", sc[want].slots, spec.slots(true, m))
            assertEquals("phút $m sáng", sc[want].slots, spec.slots(false, m))
        }
        assertNull(ThemeSchedule.index(emptyList(), 5))
        assertEquals(sc[1].slots, spec.light); assertEquals(sc[3].slots, spec.dark)
        assertEquals(spec.light, spec.slots(false, null))
        // Đồng hồ: ngày cố định, múi UTC.
        val utc = java.util.TimeZone.getTimeZone("UTC")
        val cal = java.util.Calendar.getInstance(utc).apply { clear(); set(2026, 10, 8, 17, 59) }
        assertEquals(1079, ThemeSchedule.minuteOfDay(cal.timeInMillis, utc))
        assertEquals(1439, ThemeSchedule.parseTime("23:59"))
        for (bad in listOf("24:00", "7:00", "07:60", "0700", "07-00", "ab:cd", "07:00 ", "")) assertNull(bad, ThemeSchedule.parseTime(bad))
        // Mọi mục lịch đọc được như mọi theme.
        for ((i, e) in sc.withIndex()) {
            val p = ThemeSpec.palette(e.slots, false)
            val key = c.over(p.keyFill, p.bg); val fn = c.over(p.fnFill, p.bg)
            assertTrue("mục $i phím", c.contrast(p.ink, key) >= 4.5)
            assertTrue("mục $i phím chức năng", c.contrast(p.fnInk, fn) >= 4.5)
            assertTrue("mục $i phím đè", c.contrast(p.ink, c.over(p.specialFill, p.bg)) >= 4.5)
            val bar = p.barInk ?: p.ink
            assertTrue("mục $i thanh gợi ý", c.contrast(bar, p.bg) >= 4.5)
            assertTrue("mục $i Nhập", c.contrast(p.actionInk, p.action) >= 3)
            p.decoration?.let { assertTrue("mục $i hoạ tiết", c.contrast(bar, c.over(it.color, p.bg)) >= 4.5) }
        }
        assertTrue(ThemeSpecParser.contrastIssues(spec).isEmpty())
        // Qua ThemeSettings / IME: phút chọn bảng, theme khác không phụ thuộc giờ.
        val s = ThemeSettings(theme = KeyboardTheme.TIME_OF_DAY)
        assertEquals(sc[2].slots.bg, s.basePaletteAt(false, 18 * 60)!!.bg)
        assertEquals(sc[2].slots.bg, s.basePaletteAt(true, 18 * 60)!!.bg)
        assertEquals(sc[3].slots.bg, s.basePalette(true, 33, 3 * 60)!!.bg)
        assertNotNull(s.scheduledSpec); assertNull(ThemeSettings(theme = KeyboardTheme.SEA).scheduledSpec)
        assertNull(ThemeSettings(theme = KeyboardTheme.SEA).scheduleMinuteNow())
        val sea = ThemeSettings(theme = KeyboardTheme.SEA)
        assertEquals(sea.basePaletteAt(false, 3 * 60), sea.basePaletteAt(false, 15 * 60))
        // "Chép JSON" giữ lịch; khứ hồi chuỗi chuẩn.
        val exported = s.exportSpec(KeyboardTheme.TIME_OF_DAY, KeyboardTheme.TIME_OF_DAY.palette(false)!!, KeyboardTheme.TIME_OF_DAY.palette(true)!!)
        assertEquals(sc, exported.schedule)
        assertEquals(spec.canonical, exported.canonical)
        assertEquals(exported, ThemeSpecParser.parse(exported.canonical).spec)
    }

    @Test fun festiveThemesCarrySoundAndEffect() {
        assertEquals("phao", KeyboardTheme.TET.spec?.sound); assertEquals("keyword", KeyboardTheme.TET.spec?.effect)
        assertEquals("phao", KeyboardTheme.TET_MAI.spec?.sound)
        assertEquals("jingle", KeyboardTheme.XMAS.spec?.sound); assertEquals("snow", KeyboardTheme.XMAS.spec?.effect)
        assertEquals("piano", KeyboardTheme.PIANO.spec?.sound); assertNull(KeyboardTheme.PIANO.spec?.effect)
        assertNull(KeyboardTheme.PEACH.spec?.sound); assertNull(KeyboardTheme.PEACH.spec?.effect)
        assertEquals("phao", ThemeSettings(theme = KeyboardTheme.TET).effectiveKeyStyle.sound)
        for (t in listOf(KeyboardTheme.TET, KeyboardTheme.TET_MAI, KeyboardTheme.XMAS, KeyboardTheme.XMAS_SNOW, KeyboardTheme.PIANO,
                KeyboardTheme.TYPEWRITER, KeyboardTheme.RGB, KeyboardTheme.SPACE))
            assertNotNull("$t", L10nTable.EN[t.viTitle])
        assertNotNull(L10nTable.EN[ThemeExtras.HINT])
    }

    /** Sen Việt: Plus, âm đàn tranh + hiệu ứng cánh hoa, motif hoa sen cả hai chế độ, tên vi + en (iOS y hệt). */
    @Test fun senThemeCarriesDanTranhAndPetal() {
        val t = KeyboardTheme.SEN
        assertTrue(t.isPlus)
        assertEquals("dantranh", t.spec?.sound); assertEquals("petal", t.spec?.effect)
        assertEquals("Vietnamese Lotus", L10nTable.EN[t.viTitle])
        assertTrue("dantranh" in ThemeExtraIds.SOUNDS)
        val light = t.palette(false)!!; val dark = t.palette(true)!!
        assertFalse(light.isDark); assertTrue(dark.isDark)
        assertEquals(ThemeColor.rgb(0xFFFFFF), light.keyFill)
        assertEquals(ThemeColor.rgb(0x2E7D32), light.functionFill)
        assertEquals(light.action, dark.action)
        assertEquals(ThemeDecoration.LOTUS, light.decoration!!.motif); assertEquals(ThemeDecoration.LOTUS, dark.decoration!!.motif)
        val plan = ThemeExtras.plan(ThemeSettings(theme = t).effectiveKeyStyle, false, { true }, { it in ThemeExtraIds.SOUNDS })
        assertEquals(ThemeExtras.Outcome("petal", "dantranh", true), plan)
        val base = ThemeJsonActions.Base { th, dk -> th.palette(dk)!! }
        val text = ThemeJsonActions.copyText(ThemeEditTarget.Builtin(t), ThemeSettings(theme = t), emptyMap(), base)!!
        val back = ThemeSpecParser.parse(text).spec!!
        assertEquals("dantranh", back.sound); assertEquals("petal", back.effect)
        assertEquals(back, ThemeSpecParser.parse(back.canonical).spec)
    }

    /** Hoa sen: mốc chung iOS testLotusMotifShape; mọi đường con cùng chiều quay (không thủng), trong ô ±0.5. */
    @Test fun lotusShape() {
        val subs = ThemeDecoration.shape(ThemeDecoration.LOTUS)
        assertEquals(6, subs.size)
        assertEquals(-0.2807, subs[0].segs[0][0], 1e-4)
        assertEquals(-0.6276, subs[0].segs[0][1], 1e-4)
        assertEquals(0.5932, subs[4].segs[0][2], 1e-4)
        var minY = 1.0; var maxY = -1.0; var maxX = 0.0
        for (sub in subs) {
            val pts = ArrayList<DoubleArray>(); pts.add(doubleArrayOf(sub.sx, sub.sy))
            var cx = sub.sx; var cy = sub.sy
            for (g in sub.segs) {
                if (g.size == 2) { cx = g[0]; cy = g[1]; pts.add(doubleArrayOf(cx, cy)); continue }
                for (i in 1..20) {
                    val t = i / 20.0; val u = 1 - t
                    pts.add(doubleArrayOf(u * u * u * cx + 3 * u * u * t * g[0] + 3 * u * t * t * g[2] + t * t * t * g[4],
                        u * u * u * cy + 3 * u * u * t * g[1] + 3 * u * t * t * g[3] + t * t * t * g[5]))
                }
                cx = g[4]; cy = g[5]
            }
            var area = 0.0
            for (i in pts.indices) { val a = pts[i]; val b = pts[(i + 1) % pts.size]; area += a[0] * b[1] - b[0] * a[1] }
            assertTrue("đường con ngược chiều ⇒ thủng", area > 0)
            for (p in pts) { minY = minOf(minY, p[1]); maxY = maxOf(maxY, p[1]); maxX = maxOf(maxX, Math.abs(p[0])) }
        }
        assertEquals(-0.40, minY, 0.01); assertEquals(0.40, maxY, 0.01); assertTrue(maxX <= 0.5)
        assertTrue(ThemeDecoration.LOTUS in ThemeDecoration.MOTIFS)
    }

    // ---- bộ đủ món: Máy chữ cổ / Gaming RGB / Vũ trụ (iOS ThemeSetTests.testFullPackThemes y hệt)

    @Test fun fullPackThemes() {
        val tw = KeyboardTheme.TYPEWRITER.spec!!
        assertEquals("Vintage Typewriter", tw.nameEn)
        assertEquals("typewriter", tw.sound); assertEquals("ink", tw.effect)
        val entry = BuiltinFonts.list.first { it.id == "xanh-mono" }
        assertEquals("theme trỏ đúng phông có sẵn (url + sha256)", entry.ref, tw.assets.font!!.ref)
        assertEquals(0xFFEFE6D2.toInt(), tw.palette(false).bg)
        assertEquals(80, tw.corner)
        val rgb = KeyboardTheme.RGB.spec!!
        assertEquals("mechanical", rgb.sound); assertEquals("glitch", rgb.effect)
        for (dk in listOf(false, true)) {
            assertTrue(KeyboardTheme.RGB.palette(dk)!!.rainbowBorder)
            assertNull("viền thường nhường chỗ cầu vồng", KeyboardTheme.RGB.palette(dk)!!.keyBorder)
        }
        val sp = KeyboardTheme.SPACE.spec!!
        assertEquals("Outer Space", sp.nameEn)
        assertEquals("scifi", sp.sound); assertEquals("plasma", sp.effect)
        for (t in listOf(KeyboardTheme.TYPEWRITER, KeyboardTheme.RGB, KeyboardTheme.SPACE)) {
            assertTrue("$t", t.spec!!.sound in ThemeExtraIds.SOUNDS)
            assertTrue("$t", t.spec!!.effect in ThemeExtraIds.EFFECTS)
            assertTrue("$t", t.isPlus)
        }
        for (t in KeyboardTheme.entries) if (t != KeyboardTheme.RGB) assertFalse("$t", t.palette(false)?.rainbowBorder ?: false)
    }

    /** "borderFx": đọc / chuẩn hoá / lỗi; bản vá bỏ cầu vồng ("none") và thêm cho theme khác (iOS y hệt). */
    @Test fun borderFxParseAndPatch() {
        val base = """{"v":1,"name":{"vi":"x"},"light":{"key":"#000000","special":"#111111","ink":"#FFFFFF","accent":"#7C4DFF","borderFx":"rainbow"}}"""
        val s = ThemeSpecParser.parse(base).spec!!
        assertEquals("rainbow", s.light.borderFx)
        assertTrue(s.palette(false).rainbowBorder)
        assertTrue(s.canonical.contains(""""borderFx":"rainbow""""))
        assertEquals(s.canonical, ThemeSpecParser.parse(s.canonical).spec!!.canonical)
        for (bad in listOf(""""borderFx":"disco"""", """"borderFx":1""", """"borderFx":true""")) {
            assertNull(bad, ThemeSpecParser.parse(base.replace(""""borderFx":"rainbow"""", bad)).spec)
        }
        val rgbSlots = KeyboardTheme.RGB.spec!!.light
        val off = rgbSlots.copy(borderFx = null)
        val patch = off.patchFrom(rgbSlots).first
        assertEquals("none", patch.borderFx)
        val pal = KeyStyle(light = patch, dark = patch).applyPatch(KeyboardTheme.RGB.palette(false)!!, false)
        assertFalse(pal.rainbowBorder)
        val on = ThemeSlots(borderFx = "rainbow")
        assertTrue(KeyStyle(light = on, dark = on).applyPatch(KeyboardTheme.NEON.palette(true)!!, true).rainbowBorder)
    }

    /** Chép JSON → sửa → dán: "sound" / "effect" đi trọn vòng (theme có sẵn, bản vá, theme tự tạo). */
    @Test fun soundEffectRoundTrip() {
        val base = ThemeJsonActions.Base { t, dk -> t.palette(dk)!! }
        val s = ThemeSettings(theme = KeyboardTheme.TET)
        val text = ThemeJsonActions.copyText(ThemeEditTarget.Builtin(KeyboardTheme.TET), s, emptyMap(), base)!!
        assertTrue(text, text.contains("\"sound\""))
        val back = ThemeSpecParser.parse(text).spec!!
        assertEquals("phao", back.sound); assertEquals("keyword", back.effect)
        assertEquals(back, ThemeSpecParser.parse(back.canonical).spec)
        val edited = text.replace("\"phao\"", "\"wood\"")
        val r = ThemeJsonActions.save(edited, ThemeEditTarget.Builtin(KeyboardTheme.TET), s, emptyMap(), base)
        assertTrue(r.ok)
        assertEquals("wood", r.settings.keyStyles["tet"]?.sound)
        assertEquals("wood", r.settings.effectiveKeyStyle.sound)
        assertNull(r.settings.keyStyles["tet"]?.effect)
        val raw = KeyStyleStore.serialize(r.settings.keyStyles)
        assertEquals(r.settings.keyStyles, KeyStyleStore.parse(raw))
        val same = ThemeJsonActions.save(text, ThemeEditTarget.Builtin(KeyboardTheme.TET), s, emptyMap(), base)
        assertNull(same.settings.keyStyles["tet"]?.sound)
        val restored = CustomThemeStore.parse(CustomThemeStore.serialize(mapOf("mytet" to back.copy(id = "mytet"))))
        assertEquals("phao", restored["mytet"]?.sound); assertEquals("keyword", restored["mytet"]?.effect)
    }

    @Test fun themeExtrasPlanNeverEnablesSound() {
        val yes: (String) -> Boolean = { true }; val no: (String) -> Boolean = { false }
        val st = KeyStyle(sound = "phao", effect = "blossom")
        assertEquals(ThemeExtras.Outcome("blossom", "phao", true), ThemeExtras.plan(st, false, yes, yes))
        assertFalse(ThemeExtras.plan(st, true, yes, yes).soundHint)
        assertEquals(ThemeExtras.Outcome(null, null, false), ThemeExtras.plan(KeyStyle(), false, yes, yes))
        assertEquals(ThemeExtras.Outcome(null, null, false), ThemeExtras.plan(st, false, no, no))
    }

    @Test fun themeExtrasApplyOnSelect() {
        val prefs = HashMap<String, String>()
        prefs[Keys.KEY_SOUND_STYLE] = "subtle"
        fun apply(st: KeyStyle, soundOn: Boolean) = ThemeExtras.applyOnSelect(st, soundOn) { k, v -> prefs[k] = v }
        // Chọn theme có âm + hiệu ứng: lưu kiểu âm + hiệu ứng; âm thanh phím không bị bật (hàm không ghi KEY_SOUND).
        val r = apply(KeyStyle(sound = "wood", effect = "heart"), soundOn = false)
        assertTrue(r.soundHint)
        assertEquals("wood", prefs[Keys.KEY_SOUND_STYLE]); assertEquals("heart", prefs[Keys.KEY_EFFECT])
        assertFalse(prefs.containsKey(Keys.KEY_SOUND))
        // Đổi tay sau đó: giữ — chọn theme KHÔNG khai báo cũng không đổi.
        prefs[Keys.KEY_SOUND_STYLE] = "bubble"; prefs[Keys.KEY_EFFECT] = "ripple"
        assertFalse(apply(ThemeSettings(theme = KeyboardTheme.PEACH).effectiveKeyStyle, soundOn = false).soundHint)
        assertEquals("bubble", prefs[Keys.KEY_SOUND_STYLE]); assertEquals("ripple", prefs[Keys.KEY_EFFECT])
        assertFalse(apply(KeyStyle(sound = "wood"), soundOn = true).soundHint)
        // Id chưa có trên máy ⇒ bỏ qua.
        apply(KeyStyle(sound = "notASound", effect = "notAnEffect"), soundOn = false)
        assertEquals("wood", prefs[Keys.KEY_SOUND_STYLE]); assertEquals("ripple", prefs[Keys.KEY_EFFECT])
        // Khoá Plus: hiệu ứng Plus không được đặt.
        PlusGate.paywallEnabled = true
        PlusGate.install({ null }, debugBuild = false)
        prefs[Keys.KEY_EFFECT] = "none"
        assertNull(apply(KeyStyle(effect = "firework"), soundOn = false).effect)
        assertEquals("none", prefs[Keys.KEY_EFFECT])
    }

    @Test fun pickerSectionsFreeThenInteractiveThenPlus() {
        val secs = ThemePicker.sections
        assertEquals(listOf("Miễn phí", "Tương tác", "Plus"), secs.map { it.title })
        assertEquals(listOf(KeyboardTheme.SYSTEM, KeyboardTheme.OLED, KeyboardTheme.CONTRAST, KeyboardTheme.NEUTRAL), secs[0].themes)
        assertEquals(listOf("nightclub", "ai", "trippy", "sea", "mole", "piano", "space", "rgb", "tet", "tetMai", "guitar", "drift", "mo", "stainedGlass", "football", "aquarium", "cafe", "zodiac", "pride", "gym"), secs[1].themes.map { it.id })
        assertEquals(ThemePicker.ordered(), secs.flatMap { it.themes })
        assertEquals(KeyboardTheme.entries.toSet(), secs.flatMap { it.themes }.toSet())
        assertEquals("không trùng", KeyboardTheme.entries.size, secs.flatMap { it.themes }.size)
        assertTrue(secs[1].themes.all { it.isPlus && it.isInteractive })
        assertTrue(secs[2].themes.all { it.isPlus && !it.isInteractive })
        assertEquals(ThemePicker.INTERACTIVE_ORDER.toSet(), KeyboardTheme.entries.filter { it.isInteractive }.map { it.id }.toSet())
        assertEquals(KeyboardTheme.entries.filter { it.isPlus && !it.isInteractive }, secs[2].themes)
        assertEquals("Interactive", L10nTable.EN["Tương tác"])
        for ((vi, en) in listOf("Miễn phí" to "Free", "Chọn giao diện" to "Choose theme", "Giao diện bàn phím" to "Keyboard theme"))
            assertEquals(en, L10nTable.EN[vi])
    }

    /** Hàm thứ tự thuần: theme miễn phí có nhãn vẫn ở nhóm miễn phí; = iOS testPickerOrderingPure. */
    @Test fun pickerOrderingPure() {
        val g = ThemePicker.groups(listOf(KeyboardTheme.PEACH, KeyboardTheme.AI, KeyboardTheme.OLED, KeyboardTheme.GUITAR, KeyboardTheme.NIGHTCLUB, KeyboardTheme.SYSTEM))
        assertEquals(listOf(KeyboardTheme.OLED, KeyboardTheme.SYSTEM), g.free)
        assertEquals(listOf(KeyboardTheme.NIGHTCLUB, KeyboardTheme.AI, KeyboardTheme.GUITAR), g.interactive)
        assertEquals(listOf(KeyboardTheme.PEACH), g.rest)
        assertEquals(emptyList<KeyboardTheme>(), ThemePicker.ordered(emptyList()))
    }

    /** Chip "Tương tác": đúng theme có nhãn (có sẵn + tự tạo). = iOS testInteractiveBadge. */
    @Test fun interactiveBadge() {
        for (t in KeyboardTheme.entries) assertEquals(t.id, t.id in ThemePicker.INTERACTIVE_ORDER, ThemePicker.badge(t) != null)
        assertEquals(tr("Tương tác"), ThemePicker.badge(KeyboardTheme.NIGHTCLUB))
        assertNull(ThemePicker.badge(KeyboardTheme.SYSTEM)); assertNull(ThemePicker.badge(KeyboardTheme.GLASS))
        val base = """{"v":1,"name":{"vi":"x"},"light":{"key":"#FFFFFF","special":"#DDDDDD","ink":"#000000","accent":"#000000"}"""
        assertNotNull(ThemePicker.badge(ThemeSpecParser.parse(base + ""","tags":["interactive"]}""").spec!!))
        assertNull(ThemePicker.badge(ThemeSpecParser.parse("$base}").spec!!))
    }

    /** Chọn theme AI ⇒ bạn đồng hành = Mắt AI, cỡ 5 (một lần); theme khác không đổi. = iOS testThemeBuddyAppliedOnSelect. */
    @Test fun themeBuddyAppliedOnSelect() {
        assertEquals(ThemeBuddy("ai", 5), KeyboardTheme.AI.spec?.buddy)
        assertEquals("chỉ theme AI đặt bạn đồng hành", listOf(KeyboardTheme.AI), KeyboardTheme.entries.filter { it.spec?.buddy != null })
        val b = ThemeBuddy("ai", 5)
        assertEquals(b, ThemeExtras.planBuddy(b) { true })
        assertNull(ThemeExtras.planBuddy(b) { false })
        assertNull(ThemeExtras.planBuddy(null) { true })
        assertNull(ThemeExtras.planBuddy(ThemeBuddy("off")) { true })
        val prefs = HashMap<String, Any>()
        prefs[Keys.KEYBOARD_BUDDY] = "cat"; prefs[Keys.BUDDY_SIZE] = 9
        fun apply(s: ThemeSettings) = ThemeExtras.applyBuddyOnSelect(s.selectedSpec?.buddy, { k, v -> prefs[k] = v }, { k, v -> prefs[k] = v })
        assertNull(apply(ThemeSettings(theme = KeyboardTheme.PEACH)))
        assertEquals("cat", prefs[Keys.KEYBOARD_BUDDY]); assertEquals(9, prefs[Keys.BUDDY_SIZE])
        assertEquals(b, apply(ThemeSettings(theme = KeyboardTheme.AI)))
        assertEquals("ai", prefs[Keys.KEYBOARD_BUDDY]); assertEquals(5, prefs[Keys.BUDDY_SIZE])
        // Đổi tay sau đó ⇒ giữ (chọn theme khác không ghi đè).
        prefs[Keys.KEYBOARD_BUDDY] = "cat"
        apply(ThemeSettings(theme = KeyboardTheme.NIGHTCLUB))
        assertEquals("cat", prefs[Keys.KEYBOARD_BUDDY])
        // Theme tự tạo có "buddy" cũng áp; không có cỡ ⇒ giữ cỡ cũ.
        val custom = ThemeSpecParser.parse("""{"v":1,"id":"my-b","name":{"vi":"x"},"light":{"key":"#FFFFFF","special":"#DDDDDD","ink":"#000000","accent":"#000000"},"buddy":{"character":"robot"}}""").spec!!
        assertEquals("robot", apply(ThemeSettings(custom = custom))?.character)
        assertEquals("robot", prefs[Keys.KEYBOARD_BUDDY]); assertEquals(5, prefs[Keys.BUDDY_SIZE])
        // Khoá Plus ⇒ bỏ qua cả nhân vật lẫn cỡ.
        PlusGate.paywallEnabled = true
        PlusGate.install({ null }, debugBuild = false)
        assertNull(apply(ThemeSettings(theme = KeyboardTheme.AI)))
        assertEquals("robot", prefs[Keys.KEYBOARD_BUDDY])
    }

    @Test fun pickerSelectRespectsPlusGate() {
        val s = ThemeSettings(theme = KeyboardTheme.OLED, keyboardTransparency = 30)
        assertEquals(ThemeSettings(theme = KeyboardTheme.NEON, keyboardTransparency = 30), ThemePicker.select(KeyboardTheme.NEON, s))
        PlusGate.paywallEnabled = true
        PlusGate.install({ null }, debugBuild = false)
        assertNull(ThemePicker.select(KeyboardTheme.BLACK_HEART, s))
        assertEquals(KeyboardTheme.CONTRAST, ThemePicker.select(KeyboardTheme.CONTRAST, s)?.theme)
        PlusGate.install({ if (it == Keys.PLUS_UNLOCKED) true else null }, debugBuild = false)
        assertEquals(KeyboardTheme.BLACK_HEART, ThemePicker.select(KeyboardTheme.BLACK_HEART, s)?.theme)
    }

    @Test fun pinkRoundedByDefaultButUserCornerWins() {
        assertEquals(70, ThemeSettings(theme = KeyboardTheme.PINK).effectiveKeyStyle.corner)
        assertNull(ThemeSettings(theme = KeyboardTheme.PEACH).effectiveKeyStyle.corner)
        assertEquals(10, ThemeSettings(theme = KeyboardTheme.PINK).withKeyStyle(KeyStyle(corner = 10)).effectiveKeyStyle.corner)
    }

    /** Hoạ tiết CHỈ ở khe giữa các hàng phím (bug ảnh 18/10: tim đè chữ gợi ý + ☰) — y hệt iOS. */
    @Test fun decorationOnlyInRowGapsMatchesIOS() {
        val d = ThemeDecoration
        val spans = (0 until 4).flatMap { r -> val t = 46.0 + r * 53; listOf(doubleArrayOf(t, t + 42), doubleArrayOf(t + 0.5, t + 41.5)) }
        val gaps = d.rowGaps(spans)
        assertEquals(listOf(ThemeDecoration.Gap(93.5, 11.0), ThemeDecoration.Gap(146.5, 11.0), ThemeDecoration.Gap(199.5, 11.0)), gaps)
        assertTrue(d.rowGaps(listOf(doubleArrayOf(0.0, 40.0))).isEmpty())
        assertTrue(d.rowGaps(listOf(doubleArrayOf(0.0, 40.0), doubleArrayOf(38.0, 80.0))).isEmpty())
        val pts = d.placements(402.0, gaps)
        assertEquals(18, pts.size)                      // mốc chung iOS (testDecorationOnlyInRowGaps)
        for (p in pts) {
            assertTrue("không lên thanh gợi ý / hàng đầu", p.y - p.size / 2 > 88.0 - 1e-9)
            val g = gaps.first { Math.abs(it.center - p.y) < 1e-9 }
            assertTrue("motif nằm trọn trong khe", p.size <= g.height - 2 * d.CLEARANCE + 1e-9)
            assertTrue(p.x - p.size / 2 >= d.INSET - 1e-9 && p.x + p.size / 2 <= 402 - d.INSET + 1e-9)
        }
        assertTrue(d.placements(800.0, listOf(ThemeDecoration.Gap(50.0, 6.0))).isEmpty())
        assertTrue(d.placements(5000.0, List(8) { ThemeDecoration.Gap(50.0, 11.0) }).size <= d.MAX_MOTIFS)
        assertEquals(KeyboardTheme.BLACK_HEART.palette(false)!!.decoration!!.motif, ThemeDecoration.HEARTS)
        assertEquals(KeyboardTheme.GREEN_FLORAL.palette(true)!!.decoration!!.motif, ThemeDecoration.FLOWERS)
        val festive = mapOf(KeyboardTheme.TET to ThemeDecoration.MAI, KeyboardTheme.TET_MAI to ThemeDecoration.MAI,
            KeyboardTheme.XMAS to ThemeDecoration.SNOWFLAKE, KeyboardTheme.PIANO to ThemeDecoration.NOTES,
            KeyboardTheme.SEN to ThemeDecoration.LOTUS,
            KeyboardTheme.SPACE to ThemeDecoration.STARFIELD,
            KeyboardTheme.TRUNG_THU to ThemeDecoration.LANTERN, KeyboardTheme.VALENTINE to ThemeDecoration.HEARTS,
            KeyboardTheme.HALLOWEEN to ThemeDecoration.PUMPKIN, KeyboardTheme.GUITAR to ThemeDecoration.STRINGS,
            KeyboardTheme.MOLE to ThemeDecoration.FLOWERS, KeyboardTheme.PIXEL to ThemeDecoration.PIXEL,
            KeyboardTheme.SEA to ThemeDecoration.WAVES, KeyboardTheme.AI to ThemeDecoration.NEURAL,
            KeyboardTheme.TRIPPY to ThemeDecoration.SWIRL, KeyboardTheme.DRIFT to ThemeDecoration.STARFIELD,
            KeyboardTheme.MO to ThemeDecoration.LOTUS, KeyboardTheme.RAINY_NIGHT to ThemeDecoration.BOKEH,
            KeyboardTheme.GYM to ThemeDecoration.TREADPLATE, KeyboardTheme.ZODIAC to ThemeDecoration.STARFIELD,
            KeyboardTheme.PRIDE to ThemeDecoration.HEARTS, KeyboardTheme.FOOTBALL to ThemeDecoration.PITCH,
            KeyboardTheme.AQUARIUM to ThemeDecoration.AQUARIUM, KeyboardTheme.CAFE to ThemeDecoration.CAFE)
        for ((t, m) in festive) for (dk in listOf(false, true)) assertEquals("$t", m, t.palette(dk)!!.decoration!!.motif)
        assertEquals(ThemeDecoration.SNOWFLAKE, KeyboardTheme.XMAS_SNOW.palette(false)!!.decoration!!.motif)
        assertEquals(ThemeDecoration.STAR, KeyboardTheme.XMAS_SNOW.palette(true)!!.decoration!!.motif)
        // Theo giờ: bảng gốc ngày không hoạ tiết, đêm có sao (iOS testDecorationOnlyOnHeartAndFloral).
        assertNull(KeyboardTheme.TIME_OF_DAY.palette(false)!!.decoration)
        assertEquals(ThemeDecoration.STAR, KeyboardTheme.TIME_OF_DAY.palette(true)!!.decoration!!.motif)
        for (t in KeyboardTheme.entries) if (t != KeyboardTheme.BLACK_HEART && t != KeyboardTheme.GREEN_FLORAL &&
            t != KeyboardTheme.XMAS_SNOW && t != KeyboardTheme.TIME_OF_DAY && t !in festive)
            for (dk in listOf(false, true)) assertNull("$t", t.palette(dk)?.decoration)
    }

    @Test fun darkComposesWithTransparencyWallpaperAndAdvanced() {
        for (t in pastels + newThemes) {
            val base = t.palette(true)!!
            val wp = base.overWallpaper()
            assertNull(wp.decoration)
            if (t != KeyboardTheme.PIANO) assertTrue("$t", wp.isDark)   // Piano: phím ngà chữ đen ở cả hai chế độ
            assertTrue("$t chức năng trên ảnh", c.contrast(wp.fnInk, c.over(wp.fnFill, c.WHITE)) >= 4.5)
            wp.barInk?.let { assertEquals("$t thanh gợi ý trên lớp phủ", it, KeyboardTransparency.readable(it, wp.wallpaperOverlay)) }
            val half = base.withTransparency(50, 0, true)
            base.decoration?.let { assertTrue(Math.abs(c.alpha(it.color) / 2 - c.alpha(half.decoration!!.color)) <= 1) }
            base.functionFill?.let { assertEquals(127, c.alpha(half.functionFill!!)) }
            val full = base.withTransparency(100, 0, true)
            val sys = KeyboardTransparency.systemBackdrop(true)
            assertTrue("$t", c.contrast(full.fnInk, c.over(full.fnFill, sys)) >= KeyboardTransparency.MIN_LABEL_CONTRAST)
            assertTrue("$t", c.contrast(full.keyInk, c.over(full.keyFill, sys)) >= KeyboardTransparency.MIN_LABEL_CONTRAST)
            val adv = KeyStyle(labelColor = 0xFF2D55, fillColor = 0x102030).applyColors(base)
            assertNull(adv.functionFill); assertEquals(c.rgb(0xFF2D55), adv.fnInk)
            val wf = KeyStyle(fillColor = 0xFFFFFF).applyColors(base)
            assertTrue("$t", c.contrast(wf.fnInk, wf.fnFill) >= KeyboardTransparency.MIN_LABEL_CONTRAST)
        }
    }
}
