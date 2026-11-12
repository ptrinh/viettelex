package com.viettelex.keyboard

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * "swipe" / "swipeSound" của theme: ghi MỘT lần lúc chọn theme khi Gõ vuốt đang bật ([ThemeExtras]). iOS
 * ThemeSwipeExtrasTests (KeyboardThemeTests.swift) y hệt.
 */
class ThemeSwipeExtrasTests {
    private var savedPaywall = false

    @Before fun setUp() { savedPaywall = PlusGate.paywallEnabled; PlusGate.paywallEnabled = false }
    @After fun tearDown() {
        PlusGate.paywallEnabled = savedPaywall
        PlusGate.install({ null }, debugBuild = false)
    }

    private val theme = KeyStyle(sound = "phao", effect = "blossom", swipe = "plasma", swipeSound = "wand")
    private val yes: (String) -> Boolean = { true }

    private fun plan(st: KeyStyle, swipeOn: Boolean, trail: String? = null,
                     trailOk: (String) -> Boolean = { true }, soundOk: (String) -> Boolean = { true }) =
        ThemeExtras.plan(st, true, yes, yes, swipeOn, trail, trailOk, soundOk)

    @Test fun planSwipeOffWritesNoSwipe() {
        val r = plan(theme, swipeOn = false)
        assertNull(r.swipeTrail); assertNull(r.swipeSound)
        assertEquals("blossom", r.effect); assertEquals("phao", r.sound)
        // Gọi kiểu cũ (không truyền swipeOn) = Gõ vuốt tắt.
        val old = ThemeExtras.plan(theme, true, yes, yes)
        assertNull(old.swipeTrail); assertNull(old.swipeSound)
    }

    @Test fun planSwipeOnAppliesAllowed() {
        assertEquals(ThemeExtras.Outcome("blossom", "phao", false, "plasma", "wand"), plan(theme, true, "simple"))
        // Chưa có cài đặt nét vuốt / đang Tắt ⇒ vẫn ghi.
        assertEquals("plasma", plan(theme, true, null).swipeTrail)
        assertEquals("plasma", plan(theme, true, "none").swipeTrail)
    }

    @Test fun planKeepsFollowThemeTrail() {
        val r = plan(theme, true, SwipeTrailStyle.THEME.id)
        assertNull("đang Theo giao diện ⇒ giữ", r.swipeTrail)
        assertEquals("wand", r.swipeSound)
    }

    @Test fun planRespectsGates() {
        val r = plan(theme, true, trailOk = { false }, soundOk = { false })
        assertNull(r.swipeTrail); assertNull(r.swipeSound)
        val onlySound = plan(theme, true, trailOk = { false })
        assertNull(onlySound.swipeTrail); assertEquals("wand", onlySound.swipeSound)
    }

    @Test fun planMissingFields() {
        assertEquals(ThemeExtras.Outcome(null, null, false), plan(KeyStyle(), true))
        assertNull(plan(KeyStyle(swipe = "fire"), true).swipeSound)
        assertNull(plan(KeyStyle(swipeSound = "chalk"), true).swipeTrail)
    }

    @Test fun allowedIdsAndPlusGate() {
        for (bad in listOf("theme", "nope", "")) assertFalse(bad, ThemeExtras.swipeTrailAllowed(bad))
        for (bad in listOf("none", "custom", "nope", "")) assertFalse(bad, ThemeExtras.swipeSoundAllowed(bad))
        assertTrue(ThemeExtras.swipeTrailAllowed("plasma"))
        assertTrue(ThemeExtras.swipeSoundAllowed("plasma"))
        // Chưa có Plus: chỉ kiểu miễn phí (nét: Tắt / Đơn giản; âm: Bút chì).
        PlusGate.paywallEnabled = true
        PlusGate.install({ null }, debugBuild = false)
        assertTrue(ThemeExtras.swipeTrailAllowed("simple"))
        assertTrue(ThemeExtras.swipeTrailAllowed("none"))
        assertFalse(ThemeExtras.swipeTrailAllowed("plasma"))
        assertTrue(ThemeExtras.swipeSoundAllowed("pencil"))
        assertFalse(ThemeExtras.swipeSoundAllowed("wand"))
    }

    @Test fun applyOnSelectWritesOnlyWhenSwipeOn() {
        val w = mutableMapOf<String, String>()
        // Gõ vuốt tắt (mặc định) ⇒ không ghi nét / âm vuốt.
        ThemeExtras.applyOnSelect(theme, soundOn = false) { k, v -> w[k] = v }
        assertFalse(w.containsKey(Keys.SWIPE_TRAIL)); assertFalse(w.containsKey(Keys.SWIPE_SOUND))
        // Gõ vuốt bật ⇒ ghi cả hai; không bao giờ ghi công tắc Gõ vuốt / Âm thanh phím.
        w.clear()
        val r = ThemeExtras.applyOnSelect(theme, soundOn = false, swipeOn = true, currentTrail = "simple") { k, v -> w[k] = v }
        assertEquals("plasma", r.swipeTrail); assertEquals("wand", r.swipeSound)
        assertEquals("plasma", w[Keys.SWIPE_TRAIL]); assertEquals("wand", w[Keys.SWIPE_SOUND])
        assertFalse(w.containsKey(Keys.SWIPE_TYPING)); assertFalse(w.containsKey(Keys.KEY_SOUND))
        // "Theo giao diện" ⇒ giữ nét; âm vẫn ghi.
        w.clear()
        ThemeExtras.applyOnSelect(theme, soundOn = false, swipeOn = true, currentTrail = "theme") { k, v -> w[k] = v }
        assertFalse(w.containsKey(Keys.SWIPE_TRAIL)); assertEquals("wand", w[Keys.SWIPE_SOUND])
        // Theme không khai báo / id lạ ⇒ không ghi.
        w.clear()
        ThemeExtras.applyOnSelect(KeyStyle(), soundOn = false, swipeOn = true) { k, v -> w[k] = v }
        ThemeExtras.applyOnSelect(KeyStyle(swipe = "nope", swipeSound = "nope"), soundOn = false, swipeOn = true) { k, v -> w[k] = v }
        assertTrue(w.toString(), w.isEmpty())
    }

    // ---- JSON "swipeSound"

    private val base = """{"v":1,"name":{"vi":"x"},"light":{"key":"#FFFFFF","special":"#DDDDDD","ink":"#000000","accent":"#000000"}"""

    @Test fun swipeSoundRoundTrips() {
        val spec = ThemeSpecParser.parse(base + ""","swipe":"brush","swipeSound":"brush"}""").spec!!
        assertEquals("brush", spec.swipeSound)
        assertEquals("brush", spec.typography.swipeSound)
        assertTrue(spec.canonical.contains("\"swipeSound\":\"brush\""))
        assertEquals(spec, ThemeSpecParser.parse(spec.canonical).spec)
        // Bản vá theo theme (KeyStyleStore) giữ "swipeSound".
        val st = KeyStyle(swipeSound = "chalk")
        val raw = KeyStyleStore.serialize(mapOf("pink" to st))
        assertTrue(raw, raw.contains("\"swipeSound\":\"chalk\""))
        assertEquals("chalk", KeyStyleStore.parse(raw)["pink"]?.swipeSound)
        assertEquals("whip", ThemeSpecParser.override(SJ.Obj(listOf("swipeSound" to SJ.Str("whip"))))?.swipeSound)
        // Export ("Chép JSON") mang "swipeSound".
        val p = BuiltinThemes.specs["neon"]!!.palette(false)
        assertEquals("chalk", ThemeSpec.export(null, "y", null, p, p, st).swipeSound)
    }

    @Test fun swipeSoundRejectsBadIds() {
        for (bad in listOf("none", "custom", "nope", "THEME")) {
            val out = ThemeSpecParser.parse(base + ""","swipeSound":"$bad"}""")
            assertTrue(bad, out.issues.any { it.code == ThemeIssue.Code.badValue && it.path == "swipeSound" })
            assertNull(bad, out.spec?.swipeSound)
            assertNull(bad, ThemeSpecParser.override(SJ.Obj(listOf("swipeSound" to SJ.Str(bad)))))
        }
        val wrong = ThemeSpecParser.parse(base + ""","swipeSound":3}""")
        assertTrue(wrong.issues.any { it.code == ThemeIssue.Code.wrongType && it.path == "swipeSound" })
        assertEquals(SwipeSoundStyle.SYNTHESIZED.map { it.id }.toSet(), ThemeExtraIds.SWIPE_SOUNDS)
    }

    @Test fun effectiveStyleInheritsAndEditDropsSameAsBase() {
        val space = KeyboardTheme.of("space")
        assertEquals("plasma", ThemeSettings(theme = space).effectiveKeyStyle.swipeSound)
        val b = ThemeJsonActions.Base { t, dark -> t.palette(dark)!! }
        val s = ThemeSettings(theme = space)
        val store = emptyMap<String, ThemeSpec>()
        val text = ThemeJsonActions.copyText(ThemeEditTarget.Builtin(space), s, store, b)!!
        assertTrue(text, text.contains("\"swipeSound\": \"plasma\""))
        // Giữ nguyên "swipeSound" ⇒ không lưu vào bản vá; đổi ⇒ lưu.
        var r = ThemeJsonActions.save(text, ThemeEditTarget.Builtin(space), s, store, b)
        assertTrue("${r.issues}", r.ok)
        assertNull(r.settings.keyStyles["space"]?.swipeSound)
        val edited = text.replace("\"swipeSound\": \"plasma\"", "\"swipeSound\": \"chalk\"")
        r = ThemeJsonActions.save(edited, ThemeEditTarget.Builtin(space), r.settings, store, b)
        assertTrue("${r.issues}", r.ok)
        assertEquals("chalk", r.settings.keyStyles["space"]?.swipeSound)
        assertEquals("chalk", r.settings.effectiveKeyStyle.swipeSound)
    }

    @Test fun builtinThemesSwipeSoundMapping() {
        val want = mapOf("xmas" to "wand", "xmasSnow" to "wand", "sen" to "brush", "typewriter" to "pencil",
            "rgb" to "lightning", "space" to "plasma", "halloween" to "lightning", "gym" to "whip", "zodiac" to "wand")
        assertTrue(BuiltinThemes.specs.isNotEmpty())
        for ((id, spec) in BuiltinThemes.specs) {
            assertEquals(id, want[id], spec.swipeSound)
            spec.swipeSound?.let { assertTrue(id, it in ThemeExtraIds.SWIPE_SOUNDS) }
        }
        for (id in want.keys) assertNotNull(id, BuiltinThemes.specs[id])
    }
}
