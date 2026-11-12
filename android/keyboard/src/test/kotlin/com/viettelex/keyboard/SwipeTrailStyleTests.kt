package com.viettelex.keyboard

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import kotlin.math.abs
import kotlin.math.sin

/**
 * "Hiệu ứng nét vuốt" (19/10/2026) — song sinh iOS SwipeTrailStyleTests (cùng số tham chiếu): model + id, sao
 * lưu, cổng Plus (hết Plus ⇒ Đơn giản, giá trị giữ), "swipe" của theme JSON, cấu hình lớp từng kiểu (Tắt = không
 * lớp nào), trần hạt / không rò qua 200 cú vuốt, nhiễu tia điện tất định, độ dày bút lông hàm thuần, nghỉ ⇒ hết
 * hẹn khung, và chi phí mỗi lần di chuyển so với Đơn giản (mục tiêu ≤ +0,1 ms).
 */
class SwipeTrailStyleTests {
    private var savedPaywall = PlusGate.paywallEnabled

    @Before fun setUp() { savedPaywall = PlusGate.paywallEnabled }
    @After fun tearDown() {
        PlusGate.paywallEnabled = savedPaywall
        PlusGate.install({ null }, debugBuild = false)
    }

    private fun plus(on: Boolean) {
        PlusGate.paywallEnabled = true
        PlusGate.install({ if (on && it == Keys.PLUS_UNLOCKED) true else null }, debugBuild = false)
    }

    // --- model / id / sao lưu

    @Test fun idsMatchIosAndDefaultIsSimple() {
        assertEquals(listOf("none", "simple", "fire", "electric", "brush", "rainbow", "neon", "stardust", "firework", "plasma", "kaleidoscope", "melt", "chroma", "theme"),
            SwipeTrailStyle.entries.map { it.id })
        assertEquals("swipeTrail", Keys.SWIPE_TRAIL)
        assertEquals(SwipeTrailStyle.SIMPLE, SwipeTrailStyle.DEFAULT)
        assertEquals(SwipeTrailStyle.SIMPLE, SwipeTrailStyle.of(null))
        assertEquals(SwipeTrailStyle.SIMPLE, SwipeTrailStyle.of("glitter"))
        assertEquals(SwipeTrailStyle.SIMPLE, SwipeTrailStyle.of(7))
        assertEquals(SwipeTrailStyle.NONE, SwipeTrailStyle.of("none"))
        assertEquals(listOf("none", "simple", "fire", "electric", "brush", "rainbow", "neon", "stardust", "firework", "plasma", "kaleidoscope", "melt", "chroma"),
            SwipeTrailStyle.THEME_IDS)
        assertEquals(SwipeTrailStyle.THEME_IDS.toSet(), ThemeExtraIds.SWIPES)
    }

    @Test fun settingsLoad() {
        assertEquals(SwipeTrailStyle.SIMPLE, KeyboardSettings().swipeTrail)
        assertEquals(SwipeTrailStyle.SIMPLE, KeyboardSettings.load { null }.swipeTrail)
        assertEquals(SwipeTrailStyle.NEON, KeyboardSettings.load { if (it == Keys.SWIPE_TRAIL) "neon" else null }.swipeTrail)
        assertEquals(SwipeTrailStyle.SIMPLE, KeyboardSettings.load { if (it == Keys.SWIPE_TRAIL) "lol" else null }.swipeTrail)
    }

    @Test fun backupSpecWhitelistsIds() {
        val spec = BackupSettings.all.first { it.key == Keys.SWIPE_TRAIL }
        assertEquals(SettingKind.Choice("simple", setOf("none", "simple", "fire", "electric", "brush", "rainbow", "neon",
            "stardust", "firework", "plasma", "kaleidoscope", "melt", "chroma", "theme")), spec.kind)
    }

    @Test fun titlesBilingual() {
        val en = L10nTable.EN
        for (s in SwipeTrailStyle.entries) assertTrue(s.viTitle, en.containsKey(s.viTitle))
        assertTrue(en.containsKey("Hiệu ứng nét vuốt"))
    }

    // --- cổng Plus

    @Test fun onlyOffAndSimpleAreFree() {
        assertFalse(SwipeTrailStyle.NONE.isPlus)
        assertFalse(SwipeTrailStyle.SIMPLE.isPlus)
        for (s in SwipeTrailStyle.entries) if (s != SwipeTrailStyle.NONE && s != SwipeTrailStyle.SIMPLE) assertTrue(s.id, s.isPlus)
        plus(false)
        assertTrue(SwipeTrailGate.allows(SwipeTrailStyle.NONE))
        assertTrue(SwipeTrailGate.allows(SwipeTrailStyle.SIMPLE))
        assertFalse("Theo giao diện cũng là Plus", SwipeTrailGate.allows(SwipeTrailStyle.THEME))
        assertFalse(SwipeTrailGate.allows(SwipeTrailStyle.FIRE))
        plus(true)
        assertTrue(SwipeTrailGate.allows(SwipeTrailStyle.FIRE))
    }

    /** Đã chọn Neon rồi hết Plus ⇒ vẽ Đơn giản, dòng cài đặt hiện Đơn giản; giá trị lưu giữ nguyên. */
    @Test fun lapsedPlusFallsBackToSimpleButKeepsSetting() {
        plus(false)
        val stored = KeyboardSettings.load { if (it == Keys.SWIPE_TRAIL) "neon" else null }.swipeTrail
        assertEquals(SwipeTrailStyle.NEON, stored)
        assertEquals(SwipeTrailStyle.SIMPLE, SwipeTrailPolicy.active(stored, SwipeTrailGate.allows(stored), null, false))
        assertEquals(SwipeTrailStyle.SIMPLE, SwipeTrailStyle.displayed("neon"))
        plus(true)
        assertEquals(SwipeTrailStyle.NEON, SwipeTrailPolicy.active(stored, SwipeTrailGate.allows(stored), null, false))
        assertEquals(SwipeTrailStyle.NEON, SwipeTrailStyle.displayed("neon"))
    }

    @Test fun policyResolvesThemeAtDrawTime() {
        fun a(s: SwipeTrailStyle, p: Boolean, t: String?, ps: Boolean) = SwipeTrailPolicy.active(s, p, t, ps)
        assertEquals(SwipeTrailStyle.RAINBOW, a(SwipeTrailStyle.THEME, true, "rainbow", false))
        assertEquals(SwipeTrailStyle.SIMPLE, a(SwipeTrailStyle.THEME, true, null, false))
        assertEquals(SwipeTrailStyle.SIMPLE, a(SwipeTrailStyle.THEME, true, "theme", false))
        assertEquals(SwipeTrailStyle.SIMPLE, a(SwipeTrailStyle.THEME, true, "junk", false))
        assertEquals(SwipeTrailStyle.NONE, a(SwipeTrailStyle.THEME, true, "none", false))
        assertEquals(SwipeTrailStyle.SIMPLE, a(SwipeTrailStyle.THEME, false, "rainbow", false))
        assertEquals(SwipeTrailStyle.FIRE, a(SwipeTrailStyle.FIRE, true, "rainbow", false))
        assertEquals("tiết kiệm pin ⇒ Đơn giản", SwipeTrailStyle.SIMPLE, a(SwipeTrailStyle.FIRE, true, null, true))
        assertEquals(SwipeTrailStyle.NONE, a(SwipeTrailStyle.NONE, false, null, true))
        assertEquals(SwipeTrailStyle.SIMPLE, a(SwipeTrailStyle.SIMPLE, false, null, true))
        for (s in SwipeTrailStyle.entries) assertNotEquals(SwipeTrailStyle.THEME, a(s, true, "theme", false))
    }

    // --- theme JSON "swipe"

    @Test fun builtinThemesSwipeMapping() {
        val want = mapOf("tet" to "stardust", "tetMai" to "stardust", "xmas" to "stardust", "xmasSnow" to "stardust",
            "rgb" to "rainbow", "neon" to "neon", "space" to "stardust", "typewriter" to "brush", "halloween" to "electric",
            "pixel" to "neon", "ai" to "neon", "nightclub" to "neon", "trippy" to "kaleidoscope", "drift" to "stardust", "rainyNight" to "simple", "gym" to "neon",
            "zodiac" to "stardust", "pride" to "rainbow")
        assertTrue(BuiltinThemes.specs.isNotEmpty())
        for ((id, spec) in BuiltinThemes.specs) {
            assertEquals(id, want[id], spec.swipe)
            assertEquals(id, want[id], spec.typography.swipe)
        }
        for (id in want.keys) assertTrue(id, BuiltinThemes.specs.containsKey(id))
    }

    @Test fun swipeRoundTripsThroughThemeAndKeyStyleStore() {
        val text = """{"v":1,"name":{"vi":"x"},"light":{"key":"#FFFFFF","special":"#DDDDDD","ink":"#000000","accent":"#000000"},"swipe":"brush"}"""
        val spec = ThemeSpecParser.parse(text).spec!!
        assertEquals("brush", spec.swipe)
        assertEquals(spec, ThemeSpecParser.parse(spec.canonical).spec)
        val st = KeyStyle(swipe = "neon")
        val raw = KeyStyleStore.serialize(mapOf("pink" to st))
        assertTrue(raw, raw.contains("\"swipe\":\"neon\""))
        assertEquals("neon", KeyStyleStore.parse(raw)["pink"]?.swipe)
        assertNull("id lạ ⇒ bỏ mục", ThemeSpecParser.override(SJ.Obj(listOf("swipe" to SJ.Str("theme")))))
        val p = BuiltinThemes.specs["neon"]!!.palette(false)
        assertEquals("neon", ThemeSpec.export(null, "y", null, p, p, st).swipe)
    }

    /** Chọn theme KHÔNG đổi cài đặt nét vuốt — "Theo giao diện" giải lúc vẽ. */
    @Test fun selectingThemeDoesNotWriteSwipeSetting() {
        val written = mutableMapOf<String, String>()
        ThemeExtras.applyOnSelect(BuiltinThemes.specs["rgb"]!!.typography, soundOn = false) { k, v -> written[k] = v }
        assertFalse(written.containsKey(Keys.SWIPE_TRAIL))
    }

    // --- cấu hình lớp

    @Test fun strokeConfigPerStyle() {
        val n = mapOf(SwipeTrailStyle.NONE to 0, SwipeTrailStyle.THEME to 0, SwipeTrailStyle.SIMPLE to 1, SwipeTrailStyle.FIREWORK to 1,
            SwipeTrailStyle.FIRE to 3, SwipeTrailStyle.ELECTRIC to 3, SwipeTrailStyle.NEON to 3, SwipeTrailStyle.RAINBOW to 1,
            SwipeTrailStyle.BRUSH to 1, SwipeTrailStyle.STARDUST to 1, SwipeTrailStyle.PLASMA to 3,
            SwipeTrailStyle.KALEIDOSCOPE to 3, SwipeTrailStyle.MELT to 3, SwipeTrailStyle.CHROMA to 4)
        for (s in SwipeTrailStyle.entries) {
            val k = s.strokes(6.0, 0x99FFFFFF.toInt(), 0x0A84FF, false)
            assertEquals(s.id, n[s], k.size)
            assertTrue(s.id, k.all { it.width >= 0 && (it.argb ushr 24) > 0 })
        }
        assertEquals(listOf(SwipeTrailStroke(6.0, 0x99FFFFFF.toInt())), SwipeTrailStyle.SIMPLE.strokes(6.0, 0x99FFFFFF.toInt(), 0, false))
        assertEquals(SwipeTrailStroke.Kind.GRADIENT, SwipeTrailStyle.RAINBOW.strokes(6.0, 0, 0, false).first().kind)
        assertEquals(0xE61A1A1A.toInt(), SwipeTrailStyle.BRUSH.strokes(6.0, 0, 0, false).first().argb)
        assertEquals(0xE6F2F2F2.toInt(), SwipeTrailStyle.BRUSH.strokes(6.0, 0, 0, true).first().argb)
        assertEquals(listOf(0x2E0A84FF, 0x660A84FF, 0xFFA9D4FF.toInt()),
            SwipeTrailStyle.NEON.strokes(6.0, 0, 0x0A84FF, true).map { it.argb })
        assertEquals(0x808080, SwipeTrailFx.mix(0x000000, 0xFFFFFF, 0.5))
        assertEquals(3, SwipeTrailStyle.FIRE.spawnEvery)
        assertEquals(4, SwipeTrailStyle.STARDUST.spawnEvery)
        assertEquals(5, SwipeTrailStyle.PLASMA.spawnEvery)
        for (s in SwipeTrailStyle.entries) {
            val expect = s == SwipeTrailStyle.FIRE || s == SwipeTrailStyle.STARDUST || s == SwipeTrailStyle.FIREWORK ||
                s == SwipeTrailStyle.PLASMA || s == SwipeTrailStyle.MELT
            assertEquals(s.id, expect, s.usesParticles)
            assertEquals(s.id, if (expect) SwipeTrailFx.PARTICLE_CAP else 0, SwipeTrailState(s, 2f).particleCount)
        }
        // Tắt: không lớp nét, không hạt, không có gì để vẽ (IME còn gỡ hẳn view — xem VietTelexIME.applySwipeTrail).
        val off = SwipeTrailState(SwipeTrailStyle.NONE, 2f)
        assertTrue(SwipeTrailStyle.NONE.strokes(5.0, -1, 0, false).isEmpty())
        assertEquals(0, off.particleCount)
    }

    // --- hàm thuần (số tham chiếu chung iOS)

    @Test fun electricJitterDeterministicParity() {
        val ref = listOf(Triple(0, 0, 0.550744), Triple(1, 1, 0.736660), Triple(7, 3, -0.921202), Triple(42, 10, 0.172717),
            Triple(-5, 2, -0.025589), Triple(123456, 127, -0.434409))
        for ((s, i, v) in ref) {
            assertEquals("seed $s i $i", v, SwipeTrailFx.jitter(s, i), 1e-6)
            assertEquals(SwipeTrailFx.jitter(s, i), SwipeTrailFx.jitter(s, i), 0.0)
        }
        var differs = 0
        for (i in 0 until 64) {
            val a = SwipeTrailFx.jitter(9, i); val b = SwipeTrailFx.jitter(10, i)
            assertTrue(a in -1.0..1.0)
            if (a != b) differs++
        }
        assertTrue("seed khác ⇒ tia khác", differs > 60)
    }

    @Test fun electricGeometryDeterministicPerSeedAndKeepsEnds() {
        fun draw(): Pair<FloatArray, FloatArray> {
            val st = SwipeTrailState(SwipeTrailStyle.ELECTRIC, 1f)
            st.begin()
            for (i in 0 until 20) st.add(20f + i * 15, 150f, 1000L + i * 10)
            assertTrue(st.build(1190))
            assertEquals(1, st.seed)
            return st.outX.copyOf(st.outN) to st.outY.copyOf(st.outN)
        }
        val (ax, ay) = draw(); val (bx, by) = draw()
        assertTrue(ax.contentEquals(bx) && ay.contentEquals(by))
        assertEquals(20f, ax.first(), 0.01f); assertEquals(150f, ay.first(), 0.01f)
        assertEquals(305f, ax.last(), 0.01f); assertEquals(150f, ay.last(), 0.01f)
        val span = ay.max() - ay.min()
        assertTrue("$span", span > 1f && span <= 2 * SwipeTrailFx.ELECTRIC_AMPLITUDE + 0.01)
    }

    @Test fun brushWidthIsPureFunctionOfSpeed() {
        assertEquals(10.0, SwipeTrailFx.brushWidth(0.0), 0.0)
        assertEquals(6.25, SwipeTrailFx.brushWidth(0.8), 1e-9)
        assertEquals(2.5, SwipeTrailFx.brushWidth(1.6), 0.0)
        assertEquals(2.5, SwipeTrailFx.brushWidth(50.0), 0.0)
        assertEquals(10.0, SwipeTrailFx.brushWidth(-1.0), 0.0)
        var last = Double.MAX_VALUE
        for (i in 0..40) { val w = SwipeTrailFx.brushWidth(i * 0.05); assertTrue(w <= last); last = w }
        assertEquals(7.375, SwipeTrailFx.brushSmooth(10.0, 2.5), 1e-9)
        assertEquals(1.0 / 6, SwipeTrailFx.brushTaperFactor(0, 30), 1e-9)
        assertEquals(1.0, SwipeTrailFx.brushTaperFactor(15, 30), 0.0)
        assertEquals(1.0 / 6, SwipeTrailFx.brushTaperFactor(29, 30), 1e-9)
        // Dải kín: nhanh ⇒ mảnh hơn chậm.
        fun thickness(stepMs: Long): Float {
            val st = SwipeTrailState(SwipeTrailStyle.BRUSH, 1f)
            st.begin()
            for (i in 0 until 30) st.add(10f + i * 4, 100f, 10_000L + i * stepMs)
            assertTrue(st.build(10_000L + 29 * stepMs))
            assertEquals(60, st.outN)
            val k = st.outN / 4   // giữa nét (không bị vuốt nhọn)
            return abs(st.outY[k] - st.outY[st.outN - 1 - k])
        }
        assertTrue(thickness(8) > thickness(1))
    }

    @Test fun particleTrajectoriesParity() {
        val f3 = SwipeTrailFx.trajectory(SwipeTrailStyle.FIREWORK, 3)
        assertEquals(0.0, f3.dx, 1e-9); assertEquals(36.0, f3.dy, 1e-9); assertEquals(0.6, f3.duration, 0.0)
        val e0 = SwipeTrailFx.trajectory(SwipeTrailStyle.FIRE, 0)
        assertEquals(-8.0, e0.dx, 1e-9); assertEquals(-22.0, e0.dy, 0.0); assertEquals(0.55, e0.duration, 1e-9)
        val e5 = SwipeTrailFx.trajectory(SwipeTrailStyle.FIRE, 5)
        assertEquals(8.0 * 3 / 7, e5.dx, 1e-9); assertEquals(-34.0, e5.dy, 0.0)
        val s2 = SwipeTrailFx.trajectory(SwipeTrailStyle.STARDUST, 2)
        assertEquals(-0.16, s2.rotation, 1e-9); assertEquals(1.1, s2.duration, 1e-9)
        for (s in listOf(SwipeTrailStyle.FIRE, SwipeTrailStyle.STARDUST, SwipeTrailStyle.FIREWORK, SwipeTrailStyle.PLASMA,
                SwipeTrailStyle.MELT))
            for (v in 0 until SwipeTrailFx.variants(s)) assertTrue(SwipeTrailFx.trajectory(s, v).duration <= SwipeTrailFx.MAX_PARTICLE_LIFE)
        val sp = SwipeTrailFx.Spawner(3)
        assertEquals(listOf(false, false, true, false, false, true, false, false, true), (0 until 9).map { sp.tick() })
        assertFalse(SwipeTrailFx.Spawner(0).tick())
        assertEquals(1.0, SwipeTrailFx.particleAlpha(SwipeTrailStyle.STARDUST, 0.12), 1e-9)
        assertEquals(0.3, SwipeTrailFx.particleAlpha(SwipeTrailStyle.STARDUST, 0.3), 1e-9)
        assertEquals(1.0, SwipeTrailFx.particleAlpha(SwipeTrailStyle.FIRE, 0.2), 0.0)
        assertEquals(0.5, SwipeTrailFx.particleAlpha(SwipeTrailStyle.FIRE, 0.7), 1e-9)
    }

    // --- Ảo ảnh / Tan chảy / Vệt lặp (số tham chiếu chung iOS)

    @Test fun newStylesPureParity() {
        assertEquals(4, SwipeTrailStyle.MELT.spawnEvery)
        assertEquals(6, SwipeTrailFx.KALEIDO_BRANCHES)
        assertEquals(SwipeTrailFx.HUE_WHEEL.first(), SwipeTrailFx.HUE_WHEEL.last())
        assertEquals(0xFF4D6D, SwipeTrailFx.cycleColor(0.0))
        assertEquals(0xFF4D6D, SwipeTrailFx.cycleColor(1.0))
        assertEquals(SwipeTrailFx.mix(0x4DFF88, 0x4DD8FF, 0.5), SwipeTrailFx.cycleColor(0.5))
        assertEquals(SwipeTrailFx.cycleColor(0.25), SwipeTrailFx.cycleColor(1.25))
        assertEquals(SwipeTrailFx.cycleColor(0.25), SwipeTrailFx.cycleColor(-0.75))
        assertEquals("1,75 mốc: giữa cam và vàng chanh", 0xEEED4D, SwipeTrailFx.cycleColor(0.25))
        assertEquals(1.0, SwipeTrailFx.meltBreath(0.0), 1e-9)
        assertEquals(1.3, SwipeTrailFx.meltBreath(0.25), 1e-9)
        assertEquals(0.7, SwipeTrailFx.meltBreath(0.75), 1e-9)
        assertEquals(0.0, SwipeTrailFx.meltSag(0.0), 0.0)
        assertEquals(1.75, SwipeTrailFx.meltSag(0.5), 1e-9)
        assertEquals(7.0, SwipeTrailFx.meltSag(1.0), 0.0)
        assertEquals(7.0, SwipeTrailFx.meltSag(3.0), 0.0)
        assertEquals(0.0, SwipeTrailFx.meltSag(-1.0), 0.0)
        assertEquals(0.0, SwipeTrailFx.chromaShiftX(0, 0.0), 1e-9); assertEquals(-2.5, SwipeTrailFx.chromaShiftY(0, 0.0), 1e-9)
        assertEquals(8 * Math.sqrt(3.0) / 2, SwipeTrailFx.chromaShiftX(1, 1.0), 1e-9); assertEquals(4.0, SwipeTrailFx.chromaShiftY(1, 1.0), 1e-9)
        assertEquals(-5.25 * Math.sqrt(3.0) / 2, SwipeTrailFx.chromaShiftX(2, 0.5), 1e-9)
        assertEquals(2.625, SwipeTrailFx.chromaShiftY(2, 0.5), 1e-9)
        val m4 = SwipeTrailFx.trajectory(SwipeTrailStyle.MELT, 4)
        assertEquals(1.2, m4.dx, 1e-9); assertEquals(14.0, m4.dy, 0.0); assertEquals(0.68, m4.duration, 1e-9)
        for (v in 0 until SwipeTrailFx.variants(SwipeTrailStyle.MELT)) assertTrue(SwipeTrailFx.trajectory(SwipeTrailStyle.MELT, v).dy > 0)
        val k = SwipeTrailStyle.KALEIDOSCOPE.strokes(6.0, 0, 0, false)
        assertEquals(listOf(0x73FFFFFF, 0xFFFFFFFF.toInt(), 0xD9FFFFFF.toInt()), k.map { it.argb })
        assertEquals(listOf(SwipeTrailStroke.Kind.MIRROR, SwipeTrailStroke.Kind.CONIC, SwipeTrailStroke.Kind.STROKE), k.map { it.kind })
        assertTrue("nhánh mảnh hơn nét thật", k[0].width < k[1].width)
        assertTrue("nhánh mờ hơn nét thật", (k[0].argb ushr 24) < (k[1].argb ushr 24))
        assertEquals(listOf(0x73FF4D6D, 0xBFFF4D6D.toInt(), 0xFFFF4D6D.toInt()),
            SwipeTrailStyle.MELT.strokes(6.0, 0, 0, false).map { it.argb })
        assertEquals(listOf(0x99FF2D55.toInt(), 0x9930D158.toInt(), 0x990A84FF.toInt(), 0x99ABCDEF.toInt()),
            SwipeTrailStyle.CHROMA.strokes(6.0, 0x99ABCDEF.toInt(), 0, false).map { it.argb })
        assertTrue(intArrayOf(0xFF4D6D, 0xE8FF4D, 0x4DD8FF).contentEquals(SwipeTrailStyle.MELT.particleColors(0)))
    }

    /** Tan chảy: điểm mới nhất không chảy, cũ nhất chảy meltSag(tuổi/đuôi); chia đoạn theo chiều dài (= iOS strokeStart). */
    @Test fun meltSagAndLengthCuts() {
        val st = SwipeTrailState(SwipeTrailStyle.MELT, 2f)
        st.begin()
        for (i in 0 until 25) st.add(20f + i * 15, 150f, 1_000L + i * 10)
        assertTrue(st.build(1_240))
        assertEquals(25, st.outN)
        assertEquals(150f, st.outY[24], 1e-4f)
        assertEquals((150 + SwipeTrailFx.meltSag(0.8) * 2).toFloat(), st.outY[0], 1e-3f)
        assertTrue(st.outY.copyOf(st.outN).all { it >= 150f && it <= 150f + SwipeTrailFx.MELT_DRIP.toFloat() * 2 + 1e-3f })
        assertEquals(0f, st.cut(0.0), 0f)
        assertEquals(24f, st.cut(1.0), 1e-4f)
        val a = st.cut(0.35); val b = st.cut(0.7)
        assertTrue("$a $b", a > 0f && a < b && b < 24f)
        // Gần như thẳng ngang (độ võng nhỏ so với chiều dài) ⇒ mốc ≈ tỉ lệ số điểm.
        assertEquals(0.35f * 24, a, 0.6f); assertEquals(0.7f * 24, b, 0.6f)
        // Thời gian (màu / thở) tính từ điểm đầu cú vuốt.
        assertEquals(0.24, st.elapsed(1_240), 1e-9)
        assertEquals(0.0, SwipeTrailState(SwipeTrailStyle.MELT, 1f).elapsed(5_000), 0.0)
    }

    /** Vệt lặp: nét chính mờ trong FADE_MS như mọi kiểu, bóng còn trôi + mờ tới CHROMA_FADE rồi ngừng hẹn khung. */
    @Test fun chromaGhostsOutliveMainStrokeThenStop() {
        val st = SwipeTrailState(SwipeTrailStyle.CHROMA, 1f)
        assertEquals(450L, st.fadeMs)
        assertEquals(SwipeTrailState.FADE_MS, SwipeTrailState(SwipeTrailStyle.KALEIDOSCOPE, 1f).fadeMs)
        st.begin()
        for (i in 0 until 10) st.add(10f + i * 10, 50f, 1_000L + i * 10)
        assertTrue(st.build(1_090)); assertEquals(0f, st.fadeFrac, 0f); assertEquals(1f, st.strokeAlpha, 0f)
        st.end(fade = true, nowMs = 1_100)
        assertTrue(st.build(1_200))
        assertEquals(0.5f, st.strokeAlpha, 1e-6f)
        assertEquals(100f / 450, st.fadeFrac, 1e-6f)
        assertTrue("nét chính đã tắt, bóng còn", st.build(1_400))
        assertEquals(0f, st.strokeAlpha, 0f)
        assertTrue(st.isAnimating(1_540))
        assertFalse(st.build(1_550))
        assertFalse("tan hẳn ⇒ ngừng hẹn khung", st.isAnimating(1_560))
        // Kiểu khác: vẫn 200 ms như cũ.
        val k = SwipeTrailState(SwipeTrailStyle.KALEIDOSCOPE, 1f)
        k.begin(); for (i in 0 until 10) k.add(10f + i * 10, 50f, 1_000L + i * 10)
        k.end(fade = true, nowMs = 1_100)
        assertTrue(k.build(1_250)); assertFalse(k.build(1_300))
    }

    // --- trần hạt / không rò / nghỉ = không hẹn khung

    @Test fun particlesCappedNoLeakOver200SwipesAndIdleStops() {
        for (s in listOf(SwipeTrailStyle.FIRE, SwipeTrailStyle.STARDUST, SwipeTrailStyle.FIREWORK, SwipeTrailStyle.ELECTRIC,
                SwipeTrailStyle.PLASMA, SwipeTrailStyle.KALEIDOSCOPE, SwipeTrailStyle.MELT, SwipeTrailStyle.CHROMA)) {
            val st = SwipeTrailState(s, 2.5f)
            val out = FloatArray(5)
            var t = 1_000L
            val rt = Runtime.getRuntime()
            var heap0 = 0L
            for (k in 0 until 200) {
                if (k == 20) { System.gc(); heap0 = rt.totalMemory() - rt.freeMemory() }
                st.begin()
                for (i in 0 until 40) {
                    t += 8
                    st.add(10f + (i * 9 % 380), 40f + ((i * 7 + k) % 200), t)
                    st.build(t)
                    for (p in 0 until st.particleCount) st.particle(p, t, out)
                }
                st.end(fade = k % 2 == 1, nowMs = t)
                st.commitBurst(t)
                assertTrue(s.id, st.liveParticles() <= SwipeTrailFx.PARTICLE_CAP)
                assertTrue(st.size <= SwipeTrailState.CAP)
            }
            if (s.usesParticles) assertTrue(s.id, st.liveParticles() > 0)
            assertTrue("${s.id}: còn vẽ ngay sau nhấc tay", st.isAnimating(t))
            assertFalse("${s.id}: nghỉ ⇒ ngừng hẹn khung", st.isAnimating(t + 200 + (SwipeTrailFx.MAX_PARTICLE_LIFE * 1000).toLong() + 10))
            assertEquals(0, st.liveParticles())
            System.gc()
            val grew = (rt.totalMemory() - rt.freeMemory()) - heap0
            assertTrue("${s.id}: heap tăng $grew B qua 180 cú vuốt", grew < 2_000_000)
        }
    }

    @Test fun fireworkBurstsOnlyOnCommit() {
        val st = SwipeTrailState(SwipeTrailStyle.FIREWORK, 1f)
        st.begin()
        for (i in 0 until 30) st.add(10f + i * 8, 100f, 1_000L + i * 10)
        assertEquals("không hạt dọc đường", 0, st.liveParticles())
        st.end(fade = true, nowMs = 1_300)
        assertEquals(0, st.liveParticles())
        assertTrue(st.commitBurst(1_300))
        assertEquals(SwipeTrailFx.FIREWORK_COUNT, st.liveParticles())
        val out = FloatArray(5)
        assertTrue(st.particle(0, 1_300, out))
        assertEquals(242f, out[0], 0.01f); assertEquals(100f, out[1], 0.01f)
        assertFalse(SwipeTrailState(SwipeTrailStyle.SIMPLE, 1f).also { it.begin(); it.add(1f, 1f, 1) }.commitBurst(2))
    }

    // --- chi phí mỗi lần di chuyển (add + dựng hình học + mô phỏng hạt) so với Đơn giản

    /**
     * Phần CHỈ khác nhau giữa các kiểu trên main thread: add() lúc chạm di chuyển + build()/particle() lúc vẽ khung
     * (một khung ~ một lần di chuyển — sự kiện chạm Android gom theo vsync; Canvas.drawPath ghi display list,
     * RenderThread rasterize). Khối xen kẽ, trung vị. In "TRAILBENCH …".
     */
    @Test fun perMoveCostVsSimple() {
        val path = (0 until 60).map { i -> val f = i / 59.0; floatArrayOf((20 + 360 * f).toFloat(), (145 + 90 * sin(f * 3 * Math.PI)).toFloat()) }
        val out = FloatArray(5)
        fun run(s: SwipeTrailStyle, swipes: Int): DoubleArray {
            val st = SwipeTrailState(s, 2.75f)
            val r = DoubleArray(swipes * path.size)
            var t = 1_000L; var n = 0
            repeat(swipes) {
                st.begin()
                for (p in path) {
                    t += 8
                    val t0 = System.nanoTime()
                    st.add(p[0], p[1], t)
                    st.build(t)
                    for (i in 0 until st.particleCount) st.particle(i, t, out)
                    r[n++] = (System.nanoTime() - t0) / 1e6
                }
                st.end(true, t); st.commitBurst(t)
            }
            return r
        }
        fun pct(a: DoubleArray, q: Double): Double { val s = a.sorted(); return s[minOf(s.size - 1, (s.size * q).toInt())] }
        repeat(3) { run(SwipeTrailStyle.SIMPLE, 200); for (s in SwipeTrailStyle.entries) run(s, 50) }   // JIT
        for (s in listOf(SwipeTrailStyle.FIRE, SwipeTrailStyle.ELECTRIC, SwipeTrailStyle.BRUSH, SwipeTrailStyle.RAINBOW,
                SwipeTrailStyle.NEON, SwipeTrailStyle.STARDUST, SwipeTrailStyle.FIREWORK, SwipeTrailStyle.PLASMA,
                SwipeTrailStyle.KALEIDOSCOPE, SwipeTrailStyle.MELT, SwipeTrailStyle.CHROMA)) {
            val deltas = DoubleArray(5); var base = DoubleArray(0); var on = DoubleArray(0)
            for (b in 0 until 5) {
                val a = run(SwipeTrailStyle.SIMPLE, 40); val x = run(s, 40)
                base += a; on += x
                deltas[b] = pct(x, 0.5) - pct(a, 0.5)
            }
            val d = pct(deltas, 0.5)
            println(String.format(java.util.Locale.ROOT, "TRAILBENCH android %s per_move_p50 simple=%.4f style=%.4f Δ=%.4f ms | p95 simple=%.4f style=%.4f",
                s.id, pct(base, 0.5), pct(on, 0.5), d, pct(base, 0.95), pct(on, 0.95)))
            assertTrue("${s.id}: Δ=$d ms mỗi lần di chuyển", d <= 0.1)
        }
    }
}
